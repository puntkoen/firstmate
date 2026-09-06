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
#   fm-attribution-guard.sh env-names               print the names that line assigns
#   fm-attribution-guard.sh --help                  print this usage
#
# Known limits, stated because a guard whose gaps are secret is worse than one
# whose gaps are known:
#   - `git commit --no-verify` skips the first two hooks; the pre-push pass is
#     what still stops that commit before it leaves the machine. `git push
#     --no-verify` defeats both.
#   - Unsetting GIT_CONFIG_*, passing `git -c core.hooksPath=`, or committing
#     from a shell that never received the export (the captain's own terminal,
#     an IDE, CI) defeats the arming. A launch path that FILTERS the environment
#     would defeat it the same way without anyone unsetting anything, which is
#     why `env-names` exists: bin/fm-spawn.sh reads the names from here and
#     retains them through config/launch-env-allowlist's `/usr/bin/env -i`.
#   - Pull request titles and bodies never reach a git hook. Harness-side
#     suppression and the crewmate brief cover those.
#   - Both passes peel a leading `#` and judge what it hides. git cleans a
#     message it asked an author to EDIT with `strip`, which drops commentary,
#     but `git commit -m` and `git commit -F` clean with `whitespace`, which
#     keeps it, so a `#` line in those messages is text that reaches history.
#     The cost of reading both the same way is disclosed rather than hidden: an
#     attribution line typed into an editor comment git would have dropped is
#     refused too. That costs one re-edit, where the other way round costs the
#     captain's ban.
#   - Both message rules read the comment marker this repository configures,
#     under either config name and however many characters it is, except that
#     `auto` resolves to `#` rather than to the character git would pick for the
#     message at hand.
#   - The commit-msg pass stops reading at git's scissors marker, because
#     everything below it is the verbose diff git discards. A scissors line
#     typed into a message by hand therefore hides what follows it from that
#     first gate; the pre-push pass reads the recorded message, where such a
#     line is ordinary text, and refuses it before anything leaves the machine.
#   - A transcript trailer is recognised by a key ending in -Session,
#     -Transcript, -Conversation, -Thread or -Chat, with or without a -Url
#     suffix. A key with no such ending - a bare `Session:` or `Transcript:` -
#     is left alone on purpose, so a human linking an internal debugging
#     session still commits; such a line is refused only when it names an agent
#     or its link is on an agent host.
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
       fm-attribution-guard.sh env-names
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
# A vendor address is the third way a line names an agent, and it needs no token
# at all: see AGENT_ADDRESS_RE.
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
# An address at a vendor, subdomains included, so `noreply@mail.anthropic.com`
# counts the way `noreply@anthropic.com` does. The dot before the host is
# required rather than optional text, because a host that merely ENDS in one of
# these strings is somebody else's: `mailbox.ai` ends in `x.ai`.
#
# This is attribution on its own, with no token anywhere on the line, because of
# the premise stated just above: no human's personal mail lives at one of these
# hosts. While it counted only as a bot signal, a co-author line refused only
# when the display name also carried a token, so `Co-authored-by: Composer
# <noreply@cursor.com>` committed - the vendor whose harness has no suppression
# control at all, which is the exact case this layer exists to answer for.
# `users.noreply.github.com` is not a vendor host and is untouched by this.
AGENT_ADDRESS_RE='@([^[:space:]>]*\.)?('"$AGENT_HOST_RE"')'
# `noreply` on its own is not a bot signal. GitHub gives every account a private
# <id>+<user>@users.noreply.github.com address and puts it in every co-author
# trailer it generates - web UI, squash merge, co-author suggestion - so reading
# the word alone as evidence refused a real person whose given name happens to
# be a Tier B token, which is the one thing the tier split exists to prevent.
# The word still counts at a vendor host, through AGENT_ADDRESS_RE, and `bot@`
# and `[bot]` are untouched, so GitHub's own `github-actions[bot]` keeps
# refusing on the suffix its bots all carry.
BOT_SIGNAL_RE="$AGENT_ADDRESS_RE"'|bot@|\[bot\]'
# A trailer is a trailer whatever punctuation a body puts in front of it. A
# squash body, a release note, or a quoted mail lists trailers as `- `, `* `,
# `> ` or `1. ` items, and anchoring the key at the very start of the line let an
# agent co-author trailer through on exactly that shape. The decoration a line
# may carry is therefore owned once, and every trailer rule reads the key through
# it. Nothing alphanumeric may precede the key, so `history: strip the
# Co-authored-by trailers` is still ordinary prose rather than a trailer.
# Punctuation of any kind decorates a trailer - `> `, `>> `, `| `, `-- `, a
# surrounding quote - with one exception: a single `-` or `+` followed straight
# by the key is a diff line rather than a decorated trailer, and the removal of a
# trailer is the opposite of adding one.
LINE_DECORATION_RE='^([^-+[:alnum:]][^[:alnum:]]*|[-+][^[:alnum:]]+|[[:space:]]*[0-9]+[.)][^[:alnum:]]*)?'
COAUTHOR_RE="$LINE_DECORATION_RE"'co-?authored?-by:'
# The marker git comments a message with, resolved once so the rule that reads a
# commented line and the rule that finds the scissors marker can never disagree
# about it. `core.commentString` is the current spelling and answers for both
# names, `core.commentChar` is the older one, and either may be more than one
# character since git 2.45. Compared as a literal string rather than as a
# pattern, so a marker made of regex metacharacters needs no escaping.
# `auto` resolves to git's default here, which is the one shape this does not
# follow: git picks a character the message does not use, and reproducing that
# choice would mean re-implementing it.
comment_marker() {
  local value
  value=$(git config --get core.commentString 2>/dev/null) || value=
  if [ -z "$value" ]; then
    value=$(git config --get core.commentChar 2>/dev/null) || value=
  fi
  case "$value" in
    ''|auto) value='#' ;;
  esac
  printf '%s' "$value"
}
COMMENT_MARKER=$(comment_marker)
# A session link is a transcript trailer whose value is a link or whose line
# names an agent, or an agent URL as AGENT_URL_RE defines one.
# Every line is put to every rule below, because one line can carry two
# signatures at once: a session URL riding along on a co-author trailer used to
# leave the message unscanned for the link. The value is what makes such a
# trailer attribution: an ordinary body line reading `user-session: expires too
# early after the cookie change` links to nothing and names nobody, and refusing
# it would block a human commit over wording, which is the same false positive
# the tier split exists to avoid. Nothing real is lost, because
# `Claude-Session: https://claude.ai/code/session_...` carries both a link and a
# token and AGENT_URL_RE refuses it a second time.
#
# A transcript trailer is the KEY set, not one spelling of it: the same link
# rides on `-Session`, `-Transcript`, `-Conversation`, `-Thread`, `-Chat` and the
# `-Url` suffix any of them may carry, and while only `-session:` was read,
# `Assistant-Transcript: https://transcripts.example.internal/s/...` committed
# whenever the transcript host was self-hosted or vendor-neutral. The value rule
# is unchanged and is what keeps the narrowing safe: a bare `Session:` or
# `Transcript:` key is not a transcript trailer at all, so a human linking an
# internal debugging session still commits.
SESSION_TRAILER_KEY_RE="$LINE_DECORATION_RE"'[a-z][a-z0-9_-]*-(session|transcript|conversation|thread|chat)(-url)?:'
SESSION_TRAILER_RE="$SESSION_TRAILER_KEY_RE"'[[:space:]]*[^[:space:]]'
SESSION_TRAILER_URL_RE="$SESSION_TRAILER_KEY_RE"'[[:space:]]*[a-z][a-z0-9+.-]*://'
# The authority a URL's host sits in: the scheme, any userinfo, and any
# subdomains, each of which must end in a dot. The host is anchored there for the
# reason the address rule anchors on `@`: a name that merely ENDS in one of these
# strings is somebody else's, and a path segment that spells one is not a host at
# all, so `https://docs.example.com/mailbox.ai/chat/1` is an ordinary link. The
# trailing boundary rejects alphanumerics and hyphens only, so a port, a path, a
# fully qualified trailing dot and end-of-line all still close the host while
# `claude.aire.example.com` no longer opens with one.
AGENT_URL_AUTHORITY_RE='https?://([^[:space:]/?#]*@)?([^[:space:]/?#]*\.)?'
AGENT_URL_RE="$AGENT_URL_AUTHORITY_RE"'('"$AGENT_TRANSCRIPT_HOST_RE"')([^[:alnum:]-]|$)|'"$AGENT_URL_AUTHORITY_RE"'('"$AGENT_MIXED_HOST_RE"')([^[:alnum:]-][^[:space:]]*)?'"$AGENT_PRODUCT_PATH_RE"
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

# Owns the "this line names an agent" test, for every rule that needs it. The
# co-author rule and the credit rule ask exactly the same question, and while
# each spelled it out for itself the two copies could drift the way the two host
# lists did.
names_an_agent() {  # <line>
  local text=$1
  if [[ $text =~ $TIER_A_RE ]]; then
    return 0
  fi
  if [[ $text =~ $AGENT_ADDRESS_RE ]]; then
    return 0
  fi
  if [[ $text =~ $TIER_B_RE ]] && [[ $text =~ $BOT_SIGNAL_RE ]]; then
    return 0
  fi
  return 1
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
# A comment marker is peeled off and what it hides is judged like any other line,
# in both passes. Skipping such a line would have been right only for a message
# git is about to clean with `strip`, which is what it does for a message an
# author edits; `git commit -m` and `git commit -F` clean with `whitespace` and
# keep the comment, so the trailer reaches history. See the header for what that
# costs.
scan_message() {
  local line text rest found=0
  while IFS= read -r line || [ -n "$line" ]; do
    text=$line
    rest=${text#"${text%%[![:space:]]*}"}
    if [ -n "$COMMENT_MARKER" ] && [ "${rest#"$COMMENT_MARKER"}" != "$rest" ]; then
      while [ "${rest#"$COMMENT_MARKER"}" != "$rest" ]; do
        rest=${rest#"$COMMENT_MARKER"}
      done
      text=${rest#"${rest%%[![:space:]]*}"}
    fi
    if [[ $text =~ $COAUTHOR_RE ]] && names_an_agent "$text"; then
      add_reason "co-author line naming an agent: $line"
      found=1
    fi
    if is_session_link "$text"; then
      add_reason "session link: $line"
      found=1
    fi
    if is_credit_line "$text" && names_an_agent "$text"; then
      add_reason "generated-with credit: $line"
      found=1
    fi
  done
  [ "$found" -eq 0 ]
}

# git's own scissors marker, built the way git builds it: from the comment marker
# this repository is configured with. Only that exact line counts, not one that
# merely resembles it.
scissors_line() {
  printf '%s ------------------------ >8 ------------------------\n' "$COMMENT_MARKER"
}

# The commit-msg buffer down to git's scissors marker, which is the part of it
# that can still become a commit message. `git commit -v` and
# `--cleanup=scissors` put the staged diff below that marker and git discards it,
# so judging it would refuse a commit for the text it is REMOVING - the captain's
# own cleanup work reads as attribution when the diff is read as a message.
message_before_scissors() {  # <marker>; copies file descriptor 0 up to it
  local marker=$1 line
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$line" = "$marker" ]; then
      return 0
    fi
    printf '%s\n' "$line"
  done
}

# Process substitution, not a pipeline, so scan_message's reasons survive.
check_message() {  # <file>
  [ -f "${1:-}" ] || { echo "error: no such commit message file: ${1:-}" >&2; exit 2; }
  REASONS=()
  scan_message < <(message_before_scissors "$(scissors_line)" < "$1") ||
    refuse "commit message carries agent attribution"
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
    scan_message <<< "$message" || {
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

# The environment names export-env assigns, owned here rather than restated by
# the caller. A launch path that filters the environment - config/launch-env-
# allowlist rewrites the launch as `/usr/bin/env -i <retained names> ...` - has
# to retain exactly these, and a name it does not know about is dropped
# silently, leaving a worker whose commits run no hook at all. Reading the list
# from the guard means adding a name here cannot leave such a filter behind.
ARMED_ENV_NAMES=(GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0)

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
  env-names) printf '%s\n' "${ARMED_ENV_NAMES[@]}" ;;
  export-env)
    GUARD_HOOKS_DIR=$(require_hooks_installed) || exit 1
    printf 'export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=%s\n' \
      "$(printf '%s\n' "$GUARD_HOOKS_DIR" | sed "s/'/'\\\\''/g; s/^/'/; s/\$/'/")"
    ;;
  *) usage >&2; exit 2 ;;
esac
