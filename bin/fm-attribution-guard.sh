#!/usr/bin/env bash
# fm-attribution-guard.sh - refuse agent attribution before it enters history.
#
# The captain's standing requirement is that no project of theirs carries a
# reference to an AI agent. An instruction in a crewmate brief is advice a
# worker can forget; this guard is the enforcement, and it is deliberately
# harness-independent so a new harness that ships its own byline is covered on
# the day it ships.
#
# This script is the single owner of what counts as agent attribution: the
# co-author, session-link, generated-with, and agent-file rules below. Nothing
# else in the repo restates them.
#
# It runs three ways, all the same checks:
#   commit-msg   refuses the message being committed
#   pre-commit   refuses agent files being added to the commit
#   pre-push     re-checks every outgoing commit, which is what catches a
#                message that reached history through --no-verify, a rebase, a
#                cherry-pick, or plumbing
# bin/git-hooks/{commit-msg,pre-commit,pre-push} are symlinks to this file and
# the hook name comes from $0, so one file owns all three. bin/fm-spawn.sh
# points each task copy's shell at that directory through GIT_CONFIG_*, so an
# ordinary `git commit` is checked without writing anything into the project's
# own .git.
#
# After its own verdict each hook chains to the repository's real hook of the
# same name when one exists, so a project keeping its own hooks does not lose
# them.
#
# Usage:
#   fm-attribution-guard.sh check-message <file>    check one commit message file
#   fm-attribution-guard.sh check-staged            check the staged paths
#   fm-attribution-guard.sh check-commits <rev>...  check message and paths per commit
#   fm-attribution-guard.sh hooks-dir               print the tracked hooks directory
#   fm-attribution-guard.sh export-env              print the shell line that arms the hooks
#   fm-attribution-guard.sh --help                  print this usage
#
# Known limits, stated because a guard whose gaps are secret is worse than one
# whose gaps are known:
#   - `git commit --no-verify` skips the first two hooks; the pre-push pass is
#     what still stops that commit before it leaves the machine. `git push
#     --no-verify` defeats both.
#   - Unsetting GIT_CONFIG_*, passing `git -c core.hooksPath=`, or committing
#     from a shell that never received the export (the captain's own terminal,
#     an IDE, CI) defeats the arming.
#   - Pull request titles and bodies never reach a git hook. Harness-side
#     suppression and the crewmate brief cover those.
#   - The commit-msg pass reads the message the way git's default cleanup leaves
#     it, so `#` lines are ignored there. The pre-push pass reads the recorded
#     message, where a `#` is final text, so a trailer hidden behind one under
#     --cleanup=verbatim is refused there.
#   - The pre-push pass checks at most 1000 outgoing commits per ref, newest
#     first, and says on stderr when a push exceeds that.
set -eu
shopt -s nocasematch

SELF_NAME=$(basename -- "$0")

usage() {
  cat <<'EOF'
usage: fm-attribution-guard.sh check-message <file>
       fm-attribution-guard.sh check-staged
       fm-attribution-guard.sh check-commits <rev>...
       fm-attribution-guard.sh hooks-dir
       fm-attribution-guard.sh export-env
Also runs as the commit-msg, pre-commit, and pre-push hooks through the
symlinks in bin/git-hooks/. Read this script's header for the full contract.
EOF
}

# --- the attribution contract ----------------------------------------------
#
# Tier A names an agent and never plausibly names a person, so it is refused on
# sight. Tier B is a product name that is also a human given name, so it is
# refused only together with a bot signal on the same line. That split is what
# keeps a real human co-author working, which is the whole reason it exists.
TIER_A_RE='anthropic|codex|chatgpt|openai|copilot|opencode|claude[ -]code|cursor[ -]?agent|gemini[ -]cli|gpt-[0-9]|devin|aider|windsurf|codewhisperer|tabnine|ai (assistant|agent|bot)|\[bot\]'
TIER_B_RE='claude|gemini|grok|kimi|jules|opus|sonnet|haiku|qwen|llama|mistral'
BOT_SIGNAL_RE='noreply|no-reply|@(anthropic\.com|openai\.com|cursor\.com|x\.ai|xai\.com|moonshot\.(cn|ai)|deepmind\.com)|bot@|\[bot\]'
COAUTHOR_RE='^[[:space:]]*co-?authored?-by:'
# A session link is a trailer whose key ends in -Session, or any URL on a host
# that only ever identifies an agent transcript or agent product page.
SESSION_TRAILER_RE='^[[:space:]]*[a-z][a-z0-9_-]*-session:[[:space:]]*[^[:space:]]'
AGENT_URL_RE='https?://[^[:space:]]*(claude\.ai|claude\.com|anthropic\.com|chatgpt\.com|chat\.openai\.com|openai\.com/codex|cursor\.com|gemini\.google\.com|x\.ai/grok)'
# The verbs are anchored on non-alphanumeric boundaries so `written by` does not
# fire inside `rewritten by`, `overwritten by`, or `handwritten by`.
CREDIT_RE='(^|[^[:alnum:]])(generated|created|authored|written|built|assisted) (with|by)([^[:alnum:]]|$)'

# Agent memory and agent configuration paths. CLAUDE.md is the concrete leak
# this guard was built for: bin/fm-ensure-agents-md.sh writes one into every
# project copy, and a repo whose ignore list happened not to name it committed
# it. AGENTS.md is deliberately absent from this list - that name credits nobody.
#
# A path the repository already tracks is not refused: a project that
# deliberately committed one of these names may keep maintaining it, and a
# name-based exemption for one such project would be forgotten the moment a
# second one appears. Trackedness is judged against BASE_REF - HEAD for a
# staged check, the commit's own first parent for an outgoing commit - so an
# older commit is never judged against today's HEAD. An empty BASE_REF, which is
# what an unborn branch and a root commit both produce, tracks nothing.
BASE_REF=

path_is_tracked() {  # <path>
  [ -n "$BASE_REF" ] || return 1
  git cat-file -e "$BASE_REF:$path" 2>/dev/null
}

agent_path_reason() {  # <path>; prints a reason and returns 0 when the path is refused
  local path=$1 base=${1##*/} problem=
  if [[ $base == CLAUDE.md ]]; then
    problem="names an agent vendor; project memory belongs in AGENTS.md"
  else
    case "/$path/" in
      */.claude/*) problem="is agent configuration and must stay out of the project" ;;
    esac
  fi
  [ -n "$problem" ] || return 1
  if path_is_tracked "$path"; then
    return 1
  fi
  printf '%s\n' "$path $problem"
  return 0
}

REASONS=()
add_reason() { REASONS[${#REASONS[@]}]=$1; }

refuse() {  # <headline>
  local line
  printf 'firstmate: refusing this %s - %s\n' "$SELF_NAME" "$1" >&2
  for line in ${REASONS[@]+"${REASONS[@]}"}; do
    printf '  %s\n' "$line" >&2
  done
  printf '  %s\n' "The captain's projects carry no reference to an AI agent. Remove it and retry." >&2
  exit 1
}

# --- message check ----------------------------------------------------------

# Appends one reason per offending line; returns 1 when the text is refused.
# Reads the message on file descriptor 0 and never runs in a pipeline, so the
# reasons it collects survive into the caller.
#
# Mode `strip-comments` is for the commit-msg buffer, where git's default cleanup
# is still to come and a `#` line is an editor comment. Mode `verbatim` is for a
# recorded message, which is final text: a `#` there is a character the author
# chose to keep, so the comment marker is peeled off and what it hides is scanned
# like any other line. That is what closes --cleanup=verbatim at push time.
scan_message() {  # [strip-comments|verbatim]
  local mode=${1:-strip-comments} line text found=0
  while IFS= read -r line || [ -n "$line" ]; do
    text=$line
    if [[ $text =~ ^[[:space:]]*#+[[:space:]]* ]]; then
      if [ "$mode" = strip-comments ]; then
        continue
      fi
      text=${text#"${BASH_REMATCH[0]}"}
    fi
    if [[ $text =~ $COAUTHOR_RE ]]; then
      if [[ $text =~ $TIER_A_RE ]] ||
         { [[ $text =~ $TIER_B_RE ]] && [[ $text =~ $BOT_SIGNAL_RE ]]; }; then
        add_reason "co-author line naming an agent: $line"
        found=1
      fi
      continue
    fi
    if [[ $text =~ $SESSION_TRAILER_RE ]] || [[ $text =~ $AGENT_URL_RE ]]; then
      add_reason "session link: $line"
      found=1
      continue
    fi
    if [[ $text =~ $CREDIT_RE ]] &&
       { [[ $text =~ $TIER_A_RE ]] ||
         { [[ $text =~ $TIER_B_RE ]] && [[ $text =~ $BOT_SIGNAL_RE ]]; }; }; then
      add_reason "generated-with credit: $line"
      found=1
    fi
  done
  [ "$found" -eq 0 ]
}

check_message() {  # <file>
  [ -f "${1:-}" ] || { echo "error: no such commit message file: ${1:-}" >&2; exit 2; }
  REASONS=()
  scan_message strip-comments < "$1" || refuse "commit message carries agent attribution"
}

# --- path check -------------------------------------------------------------

# Reads NUL-separated paths on file descriptor 0, for the same no-pipeline reason.
scan_paths() {
  local path reason found=0
  while IFS= read -r -d '' path; do
    if reason=$(agent_path_reason "$path"); then
      add_reason "$reason"
      found=1
    fi
  done
  [ "$found" -eq 0 ]
}

# Process substitution, never a command substitution: bash drops NUL bytes from
# $(...) output, which would silently destroy the -z separation.
check_staged() {
  REASONS=()
  BASE_REF=$(git rev-parse --verify --quiet HEAD) || BASE_REF=
  scan_paths < <(git diff --cached --name-only --diff-filter=ACMR -z) ||
    refuse "commit adds agent files"
}

# --- whole-commit check (pre-push) ------------------------------------------

check_commits() {  # <rev>...
  local rev short message
  for rev in "$@"; do
    short=$(git log -1 --format=%h "$rev")
    message=$(git log -1 --format=%B "$rev")
    BASE_REF=$(git rev-parse --verify --quiet "$rev^1") || BASE_REF=
    REASONS=()
    scan_message verbatim <<< "$message" || {
      REASONS=("commit $short:" ${REASONS[@]+"${REASONS[@]}"})
      refuse "an outgoing commit carries agent attribution"
    }
    REASONS=()
    scan_paths < <(git diff-tree --root --no-commit-id --name-only -r --diff-filter=ACMR -z "$rev") || {
      REASONS=("commit $short:" ${REASONS[@]+"${REASONS[@]}"})
      refuse "an outgoing commit adds agent files"
    }
  done
}

# --- hook chaining ----------------------------------------------------------

hooks_dir() {
  local self_dir
  self_dir=$(cd "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
  case "$self_dir" in
    */git-hooks) printf '%s\n' "$self_dir" ;;
    *) printf '%s\n' "$self_dir/git-hooks" ;;
  esac
}

# The repository's own hook directory, as git would have resolved it without
# firstmate's GIT_CONFIG_* override. Environment-injected config is its own
# scope, so an explicitly scoped read still returns what the repo itself set.
original_hooks_dir() {
  local scope value top
  for scope in --local --global --system; do
    value=$(git config "$scope" --get core.hooksPath 2>/dev/null) || value=
    [ -n "$value" ] || continue
    case "$value" in
      /*) printf '%s\n' "$value" ;;
      *)
        top=$(git rev-parse --show-toplevel 2>/dev/null) || top=.
        printf '%s\n' "$top/$value"
        ;;
    esac
    return 0
  done
  value=$(git rev-parse --git-common-dir 2>/dev/null) || return 1
  case "$value" in
    /*) ;;
    *)
      top=$(git rev-parse --show-toplevel 2>/dev/null) || top=.
      value="$top/$value"
      ;;
  esac
  printf '%s\n' "$value/hooks"
}

chain_original_hook() {  # <hook-name> <arg>...
  local name=$1 dir target resolved
  shift
  dir=$(original_hooks_dir) || return 0
  target="$dir/$name"
  [ -x "$target" ] || return 0
  resolved=$(cd "$dir" 2>/dev/null && pwd -P) || return 0
  [ "$resolved" != "$(hooks_dir)" ] || return 0
  "$target" "$@"
}

# --- entry point ------------------------------------------------------------

is_zero_sha() { case "$1" in *[!0]*) return 1 ;; *) return 0 ;; esac; }

# One more than the cap is requested so a real truncation is detectable and can
# be reported instead of silently dropping the oldest outgoing commits.
MAX_OUTGOING_COMMITS=1000

run_pre_push() {  # <remote-name>; reads git's ref lines on file descriptor 0
  local remote=$1 local_sha remote_sha rev range probe count
  local revs=()
  probe=$((MAX_OUTGOING_COMMITS + 1))
  # git's ref line is "<local ref> <local sha> <remote ref> <remote sha>"; only
  # the two shas bound the outgoing range.
  while read -r _ local_sha _ remote_sha; do
    [ -n "${local_sha:-}" ] || continue
    is_zero_sha "$local_sha" && continue
    if [ -n "${remote_sha:-}" ] && ! is_zero_sha "$remote_sha"; then
      range=$(git rev-list "--max-count=$probe" "$remote_sha..$local_sha" 2>/dev/null) || range=
    else
      range=$(git rev-list "--max-count=$probe" "$local_sha" --not "--remotes=$remote" 2>/dev/null) || range=
    fi
    count=0
    while IFS= read -r rev; do
      [ -n "$rev" ] || continue
      count=$((count + 1))
      if [ "$count" -gt "$MAX_OUTGOING_COMMITS" ]; then
        printf 'firstmate: %s checks only the newest %s outgoing commits; older commits in this push are unchecked\n' \
          "$SELF_NAME" "$MAX_OUTGOING_COMMITS" >&2
        break
      fi
      revs[${#revs[@]}]=$rev
    done <<< "$range"
  done
  [ "${#revs[@]}" -eq 0 ] || check_commits "${revs[@]}"
}

case "$SELF_NAME" in
  commit-msg)
    check_message "${1:-}"
    chain_original_hook commit-msg "$@"
    exit 0
    ;;
  pre-commit)
    check_staged
    chain_original_hook pre-commit "$@"
    exit 0
    ;;
  pre-push)
    PUSH_INPUT=$(cat || true)
    run_pre_push "${1:-origin}" <<< "$PUSH_INPUT"
    chain_original_hook pre-push "$@" <<< "$PUSH_INPUT"
    exit 0
    ;;
esac

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  check-message) shift; check_message "${1:-}" ;;
  check-staged) check_staged ;;
  check-commits) shift; [ "$#" -gt 0 ] || { usage >&2; exit 2; }; check_commits "$@" ;;
  hooks-dir) hooks_dir ;;
  export-env)
    printf 'export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=%s\n' \
      "$(hooks_dir | sed "s/'/'\\\\''/g; s/^/'/; s/\$/'/")"
    ;;
  *) usage >&2; exit 2 ;;
esac
