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
# bin/git-hooks/ holds a symlink to this file per hook name and the hook name
# comes from $0, so one file owns them all. bin/fm-spawn.sh points each task
# copy's shell at that directory through GIT_CONFIG_*, so an ordinary
# `git commit` is checked without writing anything into the project's own .git.
#
# core.hooksPath REPLACES the repository's hook directory, so every hook name
# git documents has a symlink here. The three checked names run their own
# verdict and then chain to the repository's real hook of that name; every other
# name is a pass-through that only chains, preserving the arguments, standard
# input, and exit status, and exits 0 when the project has no such hook. A
# project keeping husky, git-lfs, or its own hooks therefore does not lose them.
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
#   - push-to-checkout, proc-receive, and fsmonitor-watchman have no
#     pass-through, because git's behaviour when one of them is absent is not
#     the same as a hook that exits 0, so a pass-through would silently change
#     what the repository does. A project owning one of those three loses it for
#     the life of the task copy.
set -eu
shopt -s nocasematch

SELF_NAME=$(basename -- "$0")

# git runs this through a symlink in bin/git-hooks, so the directory the shell
# reports is that hook directory rather than bin itself; the library and the
# hooks are resolved from one place for both spellings.
GUARD_BIN_DIR=$(cd "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
case "$GUARD_BIN_DIR" in
  */git-hooks) GUARD_BIN_DIR=${GUARD_BIN_DIR%/git-hooks} ;;
esac
# shellcheck source=bin/fm-git-tracked-lib.sh
. "$GUARD_BIN_DIR/fm-git-tracked-lib.sh"

usage() {
  cat <<'EOF'
usage: fm-attribution-guard.sh check-message <file>
       fm-attribution-guard.sh check-staged
       fm-attribution-guard.sh check-commits <rev>...
       fm-attribution-guard.sh hooks-dir
       fm-attribution-guard.sh export-env
Also runs as every git hook through the symlinks in bin/git-hooks/. Read this
script's header for the full contract.
EOF
}

# --- the attribution contract ----------------------------------------------
#
# Tier A names an agent and never plausibly names a person, so it is refused on
# sight. Tier B is a product name that is also a human given name, so it is
# refused only together with a bot signal on the same line. That split is what
# keeps a real human co-author working, which is the whole reason it exists.
# Both token lists are anchored on non-alphanumeric boundaries so a token only
# matches as a whole word: `aider` must not fire inside a person named Raider,
# nor `codex` inside Codexis. `gpt-[0-9]` and `[bot]` carry their own delimiters
# and stay outside the anchored group so they keep matching as they always did.
TIER_A_RE='(^|[^[:alnum:]])(anthropic|codex|chatgpt|openai|copilot|opencode|claude[ -]code|cursor[ -]?agent|gemini[ -]cli|devin|aider|windsurf|codewhisperer|tabnine|ai (assistant|agent|bot))([^[:alnum:]]|$)|gpt-[0-9]|\[bot\]'
TIER_B_RE='(^|[^[:alnum:]])(claude|gemini|grok|kimi|jules|opus|sonnet|haiku|qwen|llama|mistral)([^[:alnum:]]|$)'
# The hosts of an agent vendor, in the two shapes the rules below need.
# A transcript host serves the agent conversation itself and nothing else, so
# any URL on one of them is attribution. A mixed host belongs to the same
# vendors but is also their company site, carrying pricing, research, careers,
# install and documentation pages an ordinary commit may legitimately cite - this
# repository's own bootstrap points at one of them - so a URL there is only
# attribution when its path names the agent product or a shared conversation.
# The product-path list is deliberately short: a path is only listed when it can
# mean nothing but the agent, and an ambiguous one is left out and disclosed in
# docs/verification/agent-attribution.md rather than refusing a real commit.
AGENT_TRANSCRIPT_HOST_RE='claude\.ai|chatgpt\.com|chat\.openai\.com|gemini\.google\.com'
AGENT_MIXED_HOST_RE='anthropic\.com|claude\.com|cursor\.com|openai\.com|x\.ai|xai\.com|moonshot\.(cn|ai)|deepmind\.com'
AGENT_PRODUCT_PATH_RE='/(claude-code|codex|grok|kimi|session|sessions|share|shared|chat|chats|conversation|conversations|transcript|transcripts)([^[:alnum:]]|$)'
# One owner for "mail from this host is a vendor address". Both host shapes count
# there, because no human's personal mail lives at any of them, and the bot-signal
# rule and the URL rule read the same lists: while they were two hand-kept ones, a
# co-author line at claude.ai committed even though a URL on that host was refused.
AGENT_HOST_RE="$AGENT_TRANSCRIPT_HOST_RE"'|'"$AGENT_MIXED_HOST_RE"
BOT_SIGNAL_RE='noreply|no-reply|@('"$AGENT_HOST_RE"')|bot@|\[bot\]'
# A trailer is a trailer whatever punctuation a body puts in front of it. A
# squash body, a release note, or a quoted mail lists trailers as `- `, `* `,
# `> ` or `1. ` items, and anchoring the key at the very start of the line let an
# agent co-author trailer through on exactly that shape. The decoration a line
# may carry is therefore owned once, and every trailer rule reads the key through
# it. Nothing alphanumeric may precede the key, so `history: strip the
# Co-authored-by trailers` is still ordinary prose rather than a trailer.
LINE_DECORATION_RE='^[^[:alnum:]]*([0-9]+[.)][^[:alnum:]]*)?'
COAUTHOR_RE="$LINE_DECORATION_RE"'co-?authored?-by:'
# A session link is a trailer whose key ends in -Session whose value is a link
# or whose line names an agent, or an agent URL as AGENT_URL_RE defines one.
# Every line is put to every rule below, because one line can carry two
# signatures at once: a session URL riding along on a co-author trailer used to
# leave the message unscanned for the link. The value is what makes such a
# trailer attribution: an ordinary body line reading `user-session: expires too
# early after the cookie change` links to nothing and names nobody, and refusing
# it would block a human commit over wording, which is the same false positive
# the tier split exists to avoid. Nothing real is lost, because
# `Claude-Session: https://claude.ai/code/session_...` carries both a link and a
# token and AGENT_URL_RE refuses it a second time.
SESSION_TRAILER_RE="$LINE_DECORATION_RE"'[a-z][a-z0-9_-]*-session:[[:space:]]*[^[:space:]]'
SESSION_TRAILER_URL_RE="$LINE_DECORATION_RE"'[a-z][a-z0-9_-]*-session:[[:space:]]*[a-z][a-z0-9+.-]*://'
AGENT_URL_RE='https?://[^[:space:]]*('"$AGENT_TRANSCRIPT_HOST_RE"')|https?://[^[:space:]]*('"$AGENT_MIXED_HOST_RE"')[^[:space:]]*'"$AGENT_PRODUCT_PATH_RE"
# The verbs are anchored on non-alphanumeric boundaries so `written by` does not
# fire inside `rewritten by`, `overwritten by`, or `handwritten by`. A hyphen
# counts where a space does, because `Generated-With:` is the git-trailer
# spelling of the same credit and a harness that ships it must be covered on the
# day it ships. A trailer key alone still refuses nobody: this rule needs the
# same evidence the co-author rule needs, so `Reviewed-by: Jane Doe` and
# `Co-authored-by: Claude Dupont <claude.dupont@example.fr>` keep committing.
CREDIT_RE='(^|[^[:alnum:]])(generated|created|authored|written|built|assisted)[ -](with|by)([^[:alnum:]]|$)'
# `authored-by` sits inside `co-authored-by`, where the hyphen of `co-` is the
# leading boundary, so the credit rule would read a co-author trailer - and any
# sentence merely naming one - as a credit of its own. That one spelling is the
# co-author rule's to judge, so it is taken out of the line before the credit
# rule reads it, and nothing else is: `Co-generated with`, `auto-generated with`,
# `Generated-With:` and `Assisted-By:` all still match.
COAUTHOR_WORD_RE='(^|[^[:alnum:]])(co-?authored?-by)([^[:alnum:]]|$)'

# Agent memory and agent configuration paths. CLAUDE.md is the concrete leak
# this guard was built for: bin/fm-ensure-agents-md.sh writes one into every
# project copy, and a repo whose ignore list happened not to name it committed
# it. AGENTS.md is deliberately absent from this list - that name credits nobody.
#
# A path the repository already tracks is not refused: a project that
# deliberately committed one of these names may keep maintaining it, and a
# name-based exemption for one such project would be forgotten the moment a
# second one appears. bin/fm-git-tracked-lib.sh owns that test and
# bin/fm-ensure-agents-md.sh draws its own boundary from the same function, so
# the two halves cannot disagree about one file. Trackedness is judged against
# BASE_REF - HEAD for a staged check, the commit's own first parent for an
# outgoing commit - so an older commit is never judged against today's HEAD.
BASE_REF=

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
  if fm_git_path_tracked_at "$BASE_REF" "$path"; then
    return 1
  fi
  printf '%s\n' "$path $problem"
  return 0
}

# Owns which lines count as a credit, for both the message passes.
is_credit_line() {  # <line>
  local text=$1
  while [[ $text =~ $COAUTHOR_WORD_RE ]]; do
    text=${text/"${BASH_REMATCH[2]}"/ }
  done
  [[ $text =~ $CREDIT_RE ]]
}

# Owns which lines count as a session link, for both the message passes.
is_session_link() {  # <line>
  local text=$1
  if [[ $text =~ $AGENT_URL_RE ]]; then
    return 0
  fi
  if [[ $text =~ $SESSION_TRAILER_RE ]]; then
    if [[ $text =~ $SESSION_TRAILER_URL_RE ]] ||
       [[ $text =~ $TIER_A_RE ]] ||
       [[ $text =~ $TIER_B_RE ]]; then
      return 0
    fi
  fi
  return 1
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
    if [[ $text =~ $COAUTHOR_RE ]] &&
       { [[ $text =~ $TIER_A_RE ]] ||
         { [[ $text =~ $TIER_B_RE ]] && [[ $text =~ $BOT_SIGNAL_RE ]]; }; }; then
      add_reason "co-author line naming an agent: $line"
      found=1
    fi
    if is_session_link "$text"; then
      add_reason "session link: $line"
      found=1
    fi
    if is_credit_line "$text" &&
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

# A merge commit needs the combined diff: plain diff-tree prints nothing for a
# commit with more than one parent, so a path the merge itself introduces would
# go unseen. A path arriving unchanged from one parent needs no special handling
# because that parent is separately in the outgoing range.
check_commits() {  # <rev>...
  local rev short message scope
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
    if [ "$(git log -1 --format=%P "$rev" | wc -w)" -gt 1 ]; then
      scope=-c
    else
      scope=--root
    fi
    scan_paths < <(git diff-tree "$scope" --no-commit-id --name-only -r --diff-filter=ACMR -z "$rev") || {
      REASONS=("commit $short:" ${REASONS[@]+"${REASONS[@]}"})
      refuse "an outgoing commit adds agent files"
    }
  done
}

# --- hook chaining ----------------------------------------------------------

hooks_dir() {
  printf '%s\n' "$GUARD_BIN_DIR/git-hooks"
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

# The three names that run a verdict of their own before chaining. Arming
# core.hooksPath at a directory where any of them is missing or not executable
# would leave git running no hook at all and the worker silently unguarded, so
# export-env resolves through this check rather than printing the line blind.
CHECKED_HOOKS='commit-msg pre-commit pre-push'

require_hooks_installed() {  # prints the hooks directory, or names what is missing
  local dir name missing=
  dir=$(hooks_dir)
  if [ ! -d "$dir" ]; then
    echo "error: $SELF_NAME: hook directory $dir does not exist, so the guard cannot be armed" >&2
    return 1
  fi
  for name in $CHECKED_HOOKS; do
    [ -x "$dir/$name" ] || missing="${missing:+$missing }$name"
  done
  if [ -n "$missing" ]; then
    echo "error: $SELF_NAME: $dir has no executable $missing hook, so arming core.hooksPath there would leave commits unchecked" >&2
    return 1
  fi
  printf '%s\n' "$dir"
}

# Every other hook name git's own githooks documentation lists, so a project's
# hooks keep running under core.hooksPath. See Known limits for the three names
# deliberately absent from this set.
PASS_THROUGH_HOOKS='applypatch-msg pre-applypatch post-applypatch pre-merge-commit prepare-commit-msg post-commit pre-rebase post-checkout post-merge pre-receive update post-receive post-update reference-transaction pre-auto-gc post-rewrite sendemail-validate p4-changelist p4-prepare-changelist p4-post-changelist p4-pre-submit post-index-change'

is_pass_through_hook() {  # <name>
  local name
  for name in $PASS_THROUGH_HOOKS; do
    [ "$name" = "$1" ] && return 0
  done
  return 1
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

# What the push target already has, as arguments for `git rev-list --not`.
# Local remote-tracking refs answer this without a round trip, but
# `--remotes=<pattern>` is a glob over refs/remotes/ and matches NOTHING when the
# target is a URL, a filesystem path, or a remote that has never been fetched.
# The exclusion would then be empty and the entire history would count as
# outgoing, so the guard would refuse a push over an ancestor the remote already
# has and the worker never authored. Ask the remote itself in that case: one
# ls-remote is bounded, and every ref it reports that this repository also has is
# provably not being added by this push. An empty answer from a remote with no
# refs is correct rather than a failure - everything really is new then.
outgoing_exclusions() {  # <remote>; prints one rev-list argument per line
  local remote=$1 refs sha
  if [ -n "$(git for-each-ref --count=1 --format='%(refname)' "refs/remotes/$remote" 2>/dev/null)" ]; then
    printf '%s\n' "--remotes=$remote"
    return 0
  fi
  refs=$(git ls-remote "$remote" 2>/dev/null) || return 1
  while read -r sha _; do
    [ -n "$sha" ] || continue
    git cat-file -e "${sha}^{commit}" 2>/dev/null && printf '%s\n' "$sha"
  done <<< "$refs"
  return 0
}

# Owns the wording for a push whose outgoing range could not be bounded.
warn_unbounded_range() {  # <remote>
  printf 'firstmate: %s could not ask %s which commits it already has, so every commit on this ref is checked and a refusal may name one the remote already carries\n' \
    "$SELF_NAME" "$1" >&2
}

# The outgoing revs for one ref, newest first, bounded by what the push target
# already has.
#
# git's ref line carries the object name the ref has ON THE REMOTE, and this
# repository need not have that object: a diverged branch, a never-fetched ref,
# and a pruned object all produce a name `git rev-list <remote-sha>..<local-sha>`
# rejects as a bad object. Swallowing that failure would leave the ref scanned
# for nothing at all, and `--force` or `--force-with-lease` would then carry
# commits this guard never read, so an unusable remote sha falls back to the
# same bound the remote itself reports. When even that cannot be established the
# whole local ref is scanned and the fallback says so, because a guard that
# silently checks nothing is worse than one that refuses too much.
outgoing_range() {  # <remote> <local-sha> <remote-sha>
  local remote=$1 local_sha=$2 remote_sha=$3 exclusions line probe range
  probe=$((MAX_OUTGOING_COMMITS + 1))
  local args=("--max-count=$probe" "$local_sha")
  if [ -n "$remote_sha" ] && ! is_zero_sha "$remote_sha" &&
    git cat-file -e "${remote_sha}^{commit}" 2>/dev/null; then
    if range=$(git rev-list "--max-count=$probe" "$remote_sha..$local_sha" 2>/dev/null); then
      printf '%s\n' "$range"
      return 0
    fi
  fi
  if exclusions=$(outgoing_exclusions "$remote"); then
    if [ -n "$exclusions" ]; then
      args+=(--not)
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        args+=("$line")
      done <<< "$exclusions"
    fi
  else
    warn_unbounded_range "$remote"
  fi
  if range=$(git rev-list "${args[@]}" 2>/dev/null); then
    printf '%s\n' "$range"
    return 0
  fi
  warn_unbounded_range "$remote"
  git rev-list "--max-count=$probe" "$local_sha" 2>/dev/null || true
}

run_pre_push() {  # <remote-name>; reads git's ref lines on file descriptor 0
  local remote=$1 local_sha remote_sha rev range count
  local revs=()
  # git's ref line is "<local ref> <local sha> <remote ref> <remote sha>"; only
  # the two shas bound the outgoing range.
  while read -r _ local_sha _ remote_sha; do
    [ -n "${local_sha:-}" ] || continue
    is_zero_sha "$local_sha" && continue
    range=$(outgoing_range "$remote" "$local_sha" "${remote_sha:-}")
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
  *)
    if is_pass_through_hook "$SELF_NAME"; then
      chain_original_hook "$SELF_NAME" "$@" || exit $?
      exit 0
    fi
    ;;
esac

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  check-message) shift; check_message "${1:-}" ;;
  check-staged) check_staged ;;
  check-commits) shift; [ "$#" -gt 0 ] || { usage >&2; exit 2; }; check_commits "$@" ;;
  hooks-dir) hooks_dir ;;
  export-env)
    GUARD_HOOKS_DIR=$(require_hooks_installed) || exit 1
    printf 'export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=%s\n' \
      "$(printf '%s\n' "$GUARD_HOOKS_DIR" | sed "s/'/'\\\\''/g; s/^/'/; s/\$/'/")"
    ;;
  *) usage >&2; exit 2 ;;
esac
