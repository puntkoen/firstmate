#!/usr/bin/env bash
# Behavior tests for bin/fm-attribution-guard.sh.
#
# Every case drives a REAL `git commit` or `git push` in a real repository with
# the hooks armed exactly the way bin/fm-spawn.sh arms them, and asserts on the
# resulting history. Nothing here inspects the guard's own source.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-attribution-guard)
HOOKS_DIR=$("$ROOT/bin/fm-attribution-guard.sh" hooks-dir)

# Arm the hooks for the whole suite the way a task copy is armed: environment
# only, nothing written into the repository's own .git.
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0="$HOOKS_DIR"

# git without firstmate's arming, for fixture setup and for the case that
# asserts where the enforcement actually comes from.
unarmed_git() {
  env -u GIT_CONFIG_COUNT -u GIT_CONFIG_KEY_0 -u GIT_CONFIG_VALUE_0 git "$@"
}

new_repo() {  # <name>
  local repo="$TMP_ROOT/$1"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email captain@example.com
  git -C "$repo" config user.name Captain
  printf 'seed\n' > "$repo/README.md"
  git -C "$repo" add README.md
  unarmed_git -C "$repo" commit -qm "seed" || fail "seed commit failed in $1"
  printf '%s\n' "$repo"
}

head_subject() { git -C "$1" log -1 --format=%s 2>/dev/null || printf ''; }

# One battery over every message shape the captain has ruled on across this
# work, so a fix for one rule can no longer quietly reopen another. Each case
# runs the real guard against a real message file through its own entry point.
MUST_REFUSE=(
  "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
  "Co-authored-by: Claude Code <noreply@anthropic.com>"
  "Co-authored-by: Codex <noreply@openai.com>"
  "- Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
  "> Co-authored-by: Claude Code <noreply@anthropic.com>"
  "* Co-authored-by: Codex <noreply@openai.com>"
  "1. Co-authored-by: Claude Opus 5 <noreply@anthropic.com>"
  "1) Co-authored-by: Claude Opus 5 <noreply@anthropic.com>"
  ">> Co-authored-by: Claude Code <noreply@anthropic.com>"
  "> > Co-authored-by: Claude Code <noreply@anthropic.com>"
  "| Co-authored-by: Claude Code <noreply@anthropic.com>"
  "-- Co-authored-by: Claude Code <noreply@anthropic.com>"
  "\"Co-authored-by: Claude Code <noreply@anthropic.com>\""
  "	Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
  "# Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
  "#Generated with Claude Code"
  "Co-authored-by: Claude <claude@claude.ai>"
  "Co-authored-by: Claude <claude@anthropic.com>"
  "Co-authored-by: Gemini <gemini@gemini.google.com>"
  "Co-authored-by: Jane Doe <jane@example.com> paired via https://claude.ai/code/session_01ABC"
  "Claude-Session: https://claude.ai/code/session_01DEDS82"
  "Claude-Session: session_01DEDS82"
  "Assistant-Session: https://transcripts.example.internal/s/01DEDS82"
  "- Claude-Session: https://claude.ai/code/session_01DEDS82"
  "* Claude-Session: session_01DEDS82"
  "Generated with Claude Code"
  "Generated with [Claude Code](https://claude.com/claude-code)"
  "Generated-With: Claude Code"
  "Assisted-By: Claude <noreply@anthropic.com>"
  "chore: ship the auto-generated with Claude Code helper"
  "chore: the module was Co-generated with Claude Code"
  "See https://claude.com/claude-code"
  "See https://www.anthropic.com/share/01ABC"
  "See https://cursor.com/conversation/01ABC"
  "See https://openai.com/codex/"
  "See https://x.ai/grok"
  "See https://kimi.moonshot.cn/chat/01ABC"
  "See https://moonshot.ai/share/01ABC"
  "See https://deepmind.com/conversation/01ABC"
  "See https://xai.com/transcript/01ABC"
  "See https://chatgpt.com/c/01ABC"
  "Co-authored-by: github-actions[bot] <41898282+github-actions[bot]@users.noreply.github.com>"
  "Co-authored-by: Claude <noreply@mail.anthropic.com>"
  "Co-authored-by: Claude <claude-bot@example.com>"
  "Co-authored-by: Cursor <noreply@cursor.com>"
  "Co-authored-by: Composer <noreply@cursor.com>"
  "Co-authored-by: Assistant <noreply@x.ai>"
  "Co-authored-by: Bard <noreply@deepmind.com>"
  "Co-authored-by: Someone <noreply@moonshot.ai>"
  "Assistant-Transcript: https://transcripts.example.internal/s/01DEDS82"
  "Claude-Session-Url: https://transcripts.example.internal/s/01DEDS82"
  "Agent-Conversation: https://transcripts.example.internal/c/01DEDS82"
  "Worker-Thread: https://transcripts.example.internal/t/01DEDS82"
  "Assistant-Chat: https://transcripts.example.internal/x/01DEDS82"
  "- Assistant-Transcript: https://transcripts.example.internal/s/01DEDS82"
  "Claude-Transcript: transcript_01DEDS82"
)
MUST_COMMIT=(
  "Co-authored-by: Jane Doe <jane@example.com>"
  "- Co-authored-by: Jane Doe <jane@example.com>"
  "Co-authored-by: Claude Dupont <claude.dupont@example.fr>"
  "Co-authored-by: Jan Raider <jan@raiderstech.com>"
  "Co-authored-by: Ana Codexis <ana@codexis.com>"
  "history: strip the Co-authored-by trailers Claude Code left behind"
  "Reviewed-by: Jane Doe <jane@example.com>"
  "user-session: expires too early after the cookie change"
  "# Please enter the commit message for your changes."
  "-Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
  "+Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
  "# Conflicts:"
  "the tokenizer was rewritten by hand to drop the llama dependency"
  "the table was overwritten by the migration"
  "that page was handwritten by Jane"
  "refresh the client generated with the openapi script"
  "response created with mistral-small endpoint"
  "bootstrap: point cursor-agent installs at https://cursor.com/cli"
  "Background: https://www.anthropic.com/research/tracing-thoughts"
  "Pricing: https://cursor.com/pricing"
  "See https://claude.com/careers"
  "See https://deepmind.com/research/alphafold"
  "Pricing at https://moonshot.ai/pricing looks fine."
  "Company page https://xai.com/about and https://x.ai/news"
  "Compare https://openai.com/pricing before deciding."
  "Co-authored-by: Claude Dupont <1234+cdupont@users.noreply.github.com>"
  "Co-authored-by: Opus Jansen <9+ojansen@users.noreply.github.com>"
  "Co-authored-by: Rik Mailbox <rik@mailbox.ai>"
  "user-transcript: renders the wrong speaker after the merge"
  "support-thread: the customer reported it twice"
  "Session: https://sessions.example.internal/s/01DEDS82"
  "Transcript: https://transcripts.example.internal/s/01DEDS82"
  "See https://docs.example.com/mailbox.ai/chat/1"
  "See https://claude.aire.example.com/news"
)

test_every_ruled_message_shape_keeps_its_verdict() {
  local msg line failures=0
  msg="$TMP_ROOT/battery.msg"
  for line in "${MUST_REFUSE[@]}"; do
    printf 'feat: add a\n\n%s\n' "$line" > "$msg"
    if "$ROOT/bin/fm-attribution-guard.sh" check-message "$msg" >/dev/null 2>&1; then
      printf 'battery accepted a line that must refuse: %s\n' "$line" >&2
      failures=$((failures + 1))
    fi
  done
  for line in "${MUST_COMMIT[@]}"; do
    printf 'feat: add a\n\n%s\n' "$line" > "$msg"
    if ! "$ROOT/bin/fm-attribution-guard.sh" check-message "$msg" >/dev/null 2>&1; then
      printf 'battery refused a line that must commit: %s\n' "$line" >&2
      failures=$((failures + 1))
    fi
  done
  [ "$failures" -eq 0 ] || fail "$failures ruled message shapes changed verdict"
  pass "fm-attribution-guard: every ruled message shape keeps its verdict"
}

# A decorated trailer is the shape the co-author rule used to miss entirely.
test_decorated_coauthor_trailer_is_refused() {
  local repo out
  repo=$(new_repo decorated-coauthor)
  printf 'work\n' > "$repo/a.txt"
  git -C "$repo" add a.txt
  out=$(git -C "$repo" commit -m "feat: add a

- Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>" 2>&1) &&
    fail "a bulleted agent co-author trailer was accepted"
  assert_contains "$out" "co-author line naming an agent" "refusal did not name the co-author rule"
  [ "$(head_subject "$repo")" = "seed" ] || fail "the refused commit still landed"
  git -C "$repo" commit -qm "feat: add a

- Co-authored-by: Jane Doe <jane@example.com>" ||
    fail "a bulleted human co-author trailer was refused"
  [ "$(head_subject "$repo")" = "feat: add a" ] || fail "the human co-author commit did not land"
  pass "fm-attribution-guard: a decorated agent co-author trailer refuses the commit"
}

# git lets a repository choose its comment marker, under either config name and
# with more than one character since 2.45. Both message rules have to read the
# same one: the marker hides a trailer from the comment rule, and the scissors
# marker git writes with it is what keeps a verbose diff out of the scan.
test_configured_comment_marker_is_honoured() {
  local repo out spec key marker n=0
  for spec in "core.commentChar ;" "core.commentString ;" "core.commentChar //" "core.commentString //"; do
    n=$((n + 1))
    key=${spec%% *}
    marker=${spec##* }
    repo=$(new_repo "comment-marker-$n")
    git -C "$repo" config "$key" "$marker"
    printf 'work\n' > "$repo/a.txt"
    git -C "$repo" add a.txt
    out=$(git -C "$repo" commit -m "feat: add a

$marker Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>" 2>&1) &&
      fail "an agent trailer behind the configured marker was accepted ($spec)"
    assert_contains "$out" "co-author line naming an agent" \
      "refusal did not name the co-author rule ($spec)"
    git -C "$repo" commit -qm "feat: add a

$marker Please enter the commit message for your changes." ||
      fail "an ordinary commented message was refused ($spec)"
    [ "$(head_subject "$repo")" = "feat: add a" ] || fail "the ordinary commit did not land ($spec)"
  done
  pass "fm-attribution-guard: the configured comment marker is read by both rules"
}

# The same marker builds git's scissors line, so a verbose diff must stay out of
# the scan when the repository does not use the default marker either.
test_verbose_commit_under_a_configured_marker_still_commits() {
  local repo editor
  repo=$(new_repo verbose-marker)
  printf 'first\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\nlast\n' > "$repo/notes.md"
  unarmed_git -C "$repo" add notes.md
  unarmed_git -C "$repo" commit -qm "chore: add the agent trailer fixture" || fail "fixture commit failed"
  git -C "$repo" config core.commentString '//'
  printf 'first\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\nchanged\n' > "$repo/notes.md"
  git -C "$repo" add notes.md
  editor="$TMP_ROOT/verbose-marker-editor.sh"
  cat > "$editor" <<'SH'
#!/usr/bin/env bash
printf 'chore: touch the neighbouring line\n%s\n' "$(cat "$1")" > "$1"
SH
  chmod +x "$editor"
  GIT_EDITOR="$editor" git -C "$repo" commit -qv ||
    fail "a verbose commit was refused over its own diff under a configured marker"
  [ "$(head_subject "$repo")" = "chore: touch the neighbouring line" ] ||
    fail "the verbose commit did not land"
  git -C "$repo" log -1 --format=%B | grep -q 'noreply@anthropic.com' &&
    fail "git recorded the discarded diff into the message"
  pass "fm-attribution-guard: a verbose commit under a configured marker still commits"
}

# `git commit -v` puts the staged diff in the buffer and git discards it below
# the scissors marker, so removing an agent trailer from a file must not read as
# adding one to the message.
test_verbose_commit_removing_a_trailer_still_commits() {
  local repo editor
  repo=$(new_repo verbose-removal)
  printf 'Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n' > "$repo/notes.md"
  unarmed_git -C "$repo" add notes.md
  unarmed_git -C "$repo" commit -qm "chore: add the agent trailer fixture" ||
    fail "fixture commit failed"
  git -C "$repo" rm -q notes.md
  editor="$TMP_ROOT/verbose-removal-editor.sh"
  cat > "$editor" <<'SH'
#!/usr/bin/env bash
printf 'chore: remove the agent trailer fixture\n%s\n' "$(cat "$1")" > "$1"
SH
  chmod +x "$editor"
  GIT_EDITOR="$editor" git -C "$repo" commit -qv ||
    fail "a verbose commit removing an agent trailer was refused"
  [ "$(head_subject "$repo")" = "chore: remove the agent trailer fixture" ] ||
    fail "the verbose commit did not land"
  git -C "$repo" log -1 --format=%B | grep -q 'noreply@anthropic.com' &&
    fail "git recorded the discarded diff into the message"
  pass "fm-attribution-guard: a verbose commit removing a trailer still commits"
}

# The scissors stop is a disclosed hole in the first gate, and this is the pass
# that closes it: the recorded message is final text, marker and all.
test_scissors_line_typed_by_hand_is_caught_at_push() {
  local repo remote out msg
  repo=$(new_repo scissors-typed)
  remote="$TMP_ROOT/scissors-typed.git"
  git init -q --bare "$remote"
  git -C "$repo" remote add origin "$remote"
  unarmed_git -C "$repo" push -q origin HEAD:refs/heads/main || fail "seed push failed"
  printf 'work\n' > "$repo/a.txt"
  git -C "$repo" add a.txt
  msg="$TMP_ROOT/scissors-typed.msg"
  printf 'feat: add a\n\n# ------------------------ >8 ------------------------\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n' > "$msg"
  git -C "$repo" commit -q -F "$msg" ||
    fail "the commit gate refused below its own scissors stop, so the push case cannot be exercised"
  git -C "$repo" log -1 --format=%B | grep -q 'noreply@anthropic.com' ||
    fail "the trailer did not survive into the recorded message"
  out=$(git -C "$repo" push origin HEAD:refs/heads/main 2>&1) &&
    fail "pushing a message that hides an agent trailer below a typed scissors line was accepted"
  assert_contains "$out" "outgoing commit carries agent attribution" \
    "the push refusal did not name the outgoing commit"
  [ "$(git -C "$remote" log -1 --format=%s refs/heads/main)" = "seed" ] ||
    fail "the tainted commit reached the remote"
  pass "fm-attribution-guard: a trailer below a typed scissors line is refused at push"
}

# `git commit -m` and `-F` clean with `whitespace`, which keeps a `#` line, so a
# trailer behind one reaches history unless the commit gate reads it.
test_commented_agent_trailer_is_refused_at_commit() {
  local repo out msg
  repo=$(new_repo commented-trailer)
  printf 'work\n' > "$repo/a.txt"
  git -C "$repo" add a.txt
  out=$(git -C "$repo" commit -m "feat: add a

# Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>" 2>&1) &&
    fail "a commented agent trailer was accepted by git commit -m"
  assert_contains "$out" "co-author line naming an agent" "refusal did not name the co-author rule"
  msg="$TMP_ROOT/commented-trailer.msg"
  printf 'feat: add a\n\n# Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n' > "$msg"
  out=$(git -C "$repo" commit -F "$msg" 2>&1) &&
    fail "a commented agent trailer was accepted by git commit -F"
  assert_contains "$out" "co-author line naming an agent" "refusal did not name the co-author rule"
  [ "$(head_subject "$repo")" = "seed" ] || fail "a refused commit still landed"
  git -C "$repo" commit -qm "feat: add a

# Please enter the commit message for your changes. Lines starting
# with '#' will be ignored, and an empty message aborts the commit." ||
    fail "a message carrying git's own template comments was refused"
  [ "$(head_subject "$repo")" = "feat: add a" ] || fail "the ordinary commented commit did not land"
  pass "fm-attribution-guard: a commented agent trailer refuses the commit"
}

test_agent_coauthor_commit_is_refused() {
  local repo out
  repo=$(new_repo agent-coauthor)
  printf 'work\n' > "$repo/a.txt"
  git -C "$repo" add a.txt
  out=$(git -C "$repo" commit -m "feat: add a

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>" 2>&1) && fail "commit with an agent co-author was accepted"
  assert_contains "$out" "co-author line naming an agent" "refusal did not name the co-author rule"
  [ "$(head_subject "$repo")" = "seed" ] || fail "the refused commit still landed"
  pass "fm-attribution-guard: agent co-author trailer refuses the commit"
}

test_codex_coauthor_commit_is_refused() {
  local repo out
  repo=$(new_repo codex-coauthor)
  printf 'work\n' > "$repo/a.txt"
  git -C "$repo" add a.txt
  out=$(git -C "$repo" commit -m "feat: add a

Co-authored-by: Codex <noreply@openai.com>" 2>&1) && fail "commit with a Codex co-author was accepted"
  assert_contains "$out" "co-author line naming an agent" "refusal did not name the co-author rule"
  [ "$(head_subject "$repo")" = "seed" ] || fail "the refused commit still landed"
  pass "fm-attribution-guard: a second harness's co-author trailer refuses the commit"
}

test_human_coauthor_commit_is_accepted() {
  local repo
  repo=$(new_repo human-coauthor)
  printf 'work\n' > "$repo/a.txt"
  git -C "$repo" add a.txt
  git -C "$repo" commit -qm "feat: add a

Co-authored-by: Jane Doe <jane@example.com>" ||
    fail "commit with a human co-author was refused"
  [ "$(head_subject "$repo")" = "feat: add a" ] || fail "the human co-author commit did not land"
  git -C "$repo" log -1 --format=%B | grep -q "Jane Doe" || fail "the human co-author trailer was lost"
  pass "fm-attribution-guard: a human co-author still commits"
}

# The tier split exists for exactly this person: Claude is a human given name.
test_human_named_claude_is_accepted() {
  local repo
  repo=$(new_repo human-claude)
  printf 'work\n' > "$repo/a.txt"
  git -C "$repo" add a.txt
  git -C "$repo" commit -qm "feat: add a

Co-authored-by: Claude Dupont <claude.dupont@example.fr>" ||
    fail "commit co-authored by a human named Claude was refused"
  [ "$(head_subject "$repo")" = "feat: add a" ] || fail "the human Claude commit did not land"
  pass "fm-attribution-guard: a human whose name is also a product name still commits"
}

# GitHub puts <id>+<user>@users.noreply.github.com in every co-author trailer it
# generates, so reading `noreply` alone as a bot signal locked every Tier B given
# name out of being credited whenever the trailer came from GitHub.
test_human_at_a_github_private_address_is_accepted() {
  local repo
  repo=$(new_repo human-github-noreply)
  printf 'work\n' > "$repo/a.txt"
  git -C "$repo" add a.txt
  git -C "$repo" commit -qm "feat: add a

Co-authored-by: Claude Dupont <1234+cdupont@users.noreply.github.com>" ||
    fail "a human co-author at GitHub's own private address was refused"
  [ "$(head_subject "$repo")" = "feat: add a" ] || fail "the GitHub co-author commit did not land"
  git -C "$repo" log -1 --format=%B | grep -q "cdupont" || fail "the human co-author trailer was lost"
  pass "fm-attribution-guard: a human at GitHub's private address still commits"
}

# The same address must keep refusing GitHub's own bots, which all carry the
# `[bot]` suffix, and a vendor address stays a bot signal wherever it appears.
test_bots_at_a_github_private_address_are_refused() {
  local repo out
  repo=$(new_repo github-noreply-bot)
  printf 'work\n' > "$repo/a.txt"
  git -C "$repo" add a.txt
  out=$(git -C "$repo" commit -m "feat: add a

Co-authored-by: github-actions[bot] <41898282+github-actions[bot]@users.noreply.github.com>" 2>&1) &&
    fail "a GitHub bot co-author was accepted"
  assert_contains "$out" "co-author line naming an agent" "refusal did not name the co-author rule"
  out=$(git -C "$repo" commit -m "feat: add a

Co-authored-by: Claude <noreply@mail.anthropic.com>" 2>&1) &&
    fail "a co-author at a vendor mail subdomain was accepted"
  assert_contains "$out" "co-author line naming an agent" "refusal did not name the co-author rule"
  [ "$(head_subject "$repo")" = "seed" ] || fail "a refused commit still landed"
  pass "fm-attribution-guard: a bot at GitHub's private address is still refused"
}

# The two halves of the arming have one owner, so a name added to the exported
# line can never be missing from the list every launch-environment filter reads.
test_env_names_covers_every_name_export_env_assigns() {
  local line names name assignment
  line=$("$ROOT/bin/fm-attribution-guard.sh" export-env) ||
    fail "export-env failed in this repository"
  names=$("$ROOT/bin/fm-attribution-guard.sh" env-names) || fail "env-names failed"
  [ -n "$names" ] || fail "env-names printed nothing"
  for assignment in $(printf '%s\n' "${line#export }" | tr ' ' '\n'); do
    case "$assignment" in
      *=*) name=${assignment%%=*} ;;
      *) continue ;;
    esac
    case "$name" in
      [A-Z_]*) ;;
      *) continue ;;
    esac
    printf '%s\n' "$names" | grep -qxF "$name" ||
      fail "export-env assigns $name but env-names does not list it, so a filtered launch environment would drop it"
  done
  for name in $names; do
    case "$line" in
      *"$name="*) ;;
      *) fail "env-names lists $name but export-env never assigns it" ;;
    esac
  done
  pass "fm-attribution-guard: env-names names exactly what export-env assigns"
}

# The tier split exists so real people keep committing, and an unanchored token
# refuses them: `aider` sits inside Raider, `codex` inside Codexis.
test_humans_whose_names_contain_agent_tokens_are_accepted() {
  local repo
  repo=$(new_repo human-substrings)
  printf 'work\n' > "$repo/a.txt"
  git -C "$repo" add a.txt
  git -C "$repo" commit -qm "feat: add a

Co-authored-by: Jan Raider <jan@raiderstech.com>" ||
    fail "a human named Raider was refused"
  printf 'more\n' > "$repo/b.txt"
  git -C "$repo" add b.txt
  git -C "$repo" commit -qm "feat: add b

Co-authored-by: Ana Codexis <ana@codexis.com>" ||
    fail "a human named Codexis was refused"
  [ "$(head_subject "$repo")" = "feat: add b" ] || fail "the second human co-author commit did not land"
  pass "fm-attribution-guard: a human whose name contains an agent token still commits"
}

# A vendor's own agent host is the bot signal Tier B needs; the two host lists
# had drifted, so a co-author at claude.ai committed while the same host in a URL
# was refused.
test_agent_vendor_domain_coauthor_is_refused() {
  local repo out
  repo=$(new_repo vendor-domain-coauthor)
  printf 'work\n' > "$repo/a.txt"
  git -C "$repo" add a.txt
  out=$(git -C "$repo" commit -m "feat: add a

Co-authored-by: Claude <claude@claude.ai>" 2>&1) &&
    fail "a co-author at the vendor's own agent host was accepted"
  assert_contains "$out" "co-author line naming an agent" "refusal did not name the co-author rule"
  out=$(git -C "$repo" commit -m "feat: add a

Co-authored-by: Gemini <gemini@gemini.google.com>" 2>&1) &&
    fail "a co-author at a second vendor's agent host was accepted"
  assert_contains "$out" "co-author line naming an agent" "refusal did not name the co-author rule"
  out=$(git -C "$repo" commit -m "feat: add a

Co-authored-by: Claude <claude@anthropic.com>" 2>&1) &&
    fail "a co-author at a vendor's company host was accepted"
  assert_contains "$out" "co-author line naming an agent" "refusal did not name the co-author rule"
  [ "$(head_subject "$repo")" = "seed" ] || fail "a refused commit still landed"
  git -C "$repo" commit -qm "feat: add a

Co-authored-by: Koen de Vries <koen@example.nl>" ||
    fail "a human co-author at a human address was refused"
  [ "$(head_subject "$repo")" = "feat: add a" ] || fail "the human co-author commit did not land"
  pass "fm-attribution-guard: a co-author at an agent vendor host refuses the commit"
}

# The vendor address is evidence on its own. While it counted only as a bot
# signal the line still needed a token, so every vendor whose product name is in
# neither token list - Cursor's Composer above all, the harness with no
# suppression control at all - committed its own byline.
test_vendor_address_alone_refuses_a_coauthor_line() {
  local repo out line
  repo=$(new_repo vendor-address-alone)
  printf 'work\n' > "$repo/a.txt"
  git -C "$repo" add a.txt
  for line in \
    "Co-authored-by: Cursor <noreply@cursor.com>" \
    "Co-authored-by: Composer <noreply@cursor.com>" \
    "Co-authored-by: Assistant <noreply@x.ai>" \
    "Co-authored-by: Bard <noreply@deepmind.com>" \
    "Co-authored-by: Someone <noreply@moonshot.ai>"; do
    out=$(git -C "$repo" commit -m "feat: add a

$line" 2>&1) && fail "a co-author at a vendor host with no token was accepted: $line"
    assert_contains "$out" "co-author line naming an agent" "refusal did not name the co-author rule for $line"
  done
  out=$(git -C "$repo" commit -m "feat: add a

Co-authored-by: github-actions[bot] <41898282+github-actions[bot]@users.noreply.github.com>" 2>&1) &&
    fail "widening the address rule stopped refusing a GitHub bot"
  [ "$(head_subject "$repo")" = "seed" ] || fail "a refused commit still landed"
  git -C "$repo" commit -qm "feat: add a

Co-authored-by: Claude Dupont <1234+cdupont@users.noreply.github.com>" ||
    fail "a human at GitHub's private address was refused by the address rule"
  [ "$(head_subject "$repo")" = "feat: add a" ] || fail "the GitHub co-author commit did not land"
  printf 'more\n' >> "$repo/a.txt"
  git -C "$repo" add a.txt
  git -C "$repo" commit -qm "feat: extend a

Co-authored-by: Rik Mailbox <rik@mailbox.ai>" ||
    fail "a human at a host that merely ends in a vendor host was refused"
  [ "$(head_subject "$repo")" = "feat: extend a" ] || fail "the mailbox.ai co-author commit did not land"
  pass "fm-attribution-guard: an agent vendor address alone refuses the co-author line"
}

test_session_link_commit_is_refused() {
  local repo out
  repo=$(new_repo session-link)
  printf 'work\n' > "$repo/a.txt"
  git -C "$repo" add a.txt
  out=$(git -C "$repo" commit -m "feat: add a

Claude-Session: https://claude.ai/code/session_01DEDS82wWQt5RcjtK6pANJB" 2>&1) &&
    fail "commit with a session link was accepted"
  assert_contains "$out" "session link" "refusal did not name the session-link rule"
  [ "$(head_subject "$repo")" = "seed" ] || fail "the refused commit still landed"
  pass "fm-attribution-guard: a session link refuses the commit"
}

# A `<word>-session:` line is only attribution when its value is a link or its
# line names an agent; ordinary wording in a body must still commit.
test_ordinary_session_wording_is_accepted() {
  local repo
  repo=$(new_repo ordinary-session)
  printf 'work\n' > "$repo/a.txt"
  git -C "$repo" add a.txt
  git -C "$repo" commit -qm "fix: shorten the cookie lifetime

user-session: expires too early after the cookie change" ||
    fail "an ordinary body line ending in -session: was refused"
  [ "$(head_subject "$repo")" = "fix: shorten the cookie lifetime" ] ||
    fail "the ordinary session-wording commit did not land"
  git -C "$repo" log -1 --format=%B | grep -q "user-session: expires too early" ||
    fail "the ordinary body line was lost"
  pass "fm-attribution-guard: ordinary -session: wording still commits"
}

test_session_trailer_with_a_link_value_is_refused() {
  local repo out
  repo=$(new_repo session-trailer-link)
  printf 'work\n' > "$repo/a.txt"
  git -C "$repo" add a.txt
  out=$(git -C "$repo" commit -m "feat: add a

Assistant-Session: https://transcripts.example.internal/s/01DEDS82" 2>&1) &&
    fail "commit with a session trailer linking to a transcript was accepted"
  assert_contains "$out" "session link" "refusal did not name the session-link rule"
  [ "$(head_subject "$repo")" = "seed" ] || fail "the refused commit still landed"
  pass "fm-attribution-guard: a session trailer whose value is a link refuses the commit"
}

test_session_trailer_naming_an_agent_is_refused() {
  local repo out
  repo=$(new_repo session-trailer-token)
  printf 'work\n' > "$repo/a.txt"
  git -C "$repo" add a.txt
  out=$(git -C "$repo" commit -m "feat: add a

Claude-Session: session_01DEDS82wWQt5RcjtK6pANJB" 2>&1) &&
    fail "commit with an agent-named session trailer was accepted"
  assert_contains "$out" "session link" "refusal did not name the session-link rule"
  [ "$(head_subject "$repo")" = "seed" ] || fail "the refused commit still landed"
  pass "fm-attribution-guard: a session trailer naming an agent refuses the commit without a link"
}

# The same transcript link rides on more than one key. While only `-session:`
# was read, moving it to `Assistant-Transcript:` walked it straight past the
# rule whenever the transcript host was self-hosted or vendor-neutral.
test_every_transcript_trailer_key_is_refused() {
  local repo out line
  repo=$(new_repo transcript-trailer-keys)
  printf 'work\n' > "$repo/a.txt"
  git -C "$repo" add a.txt
  for line in \
    "Assistant-Transcript: https://transcripts.example.internal/s/01DEDS82" \
    "Claude-Session-Url: https://transcripts.example.internal/s/01DEDS82" \
    "Agent-Conversation: https://transcripts.example.internal/c/01DEDS82" \
    "Worker-Thread: https://transcripts.example.internal/t/01DEDS82" \
    "Assistant-Chat: https://transcripts.example.internal/x/01DEDS82" \
    "Claude-Transcript: transcript_01DEDS82"; do
    out=$(git -C "$repo" commit -m "feat: add a

$line" 2>&1) && fail "a transcript trailer was accepted: $line"
    assert_contains "$out" "session link" "refusal did not name the session-link rule for $line"
  done
  [ "$(head_subject "$repo")" = "seed" ] || fail "a refused commit still landed"
  pass "fm-attribution-guard: every transcript trailer key refuses the commit"
}

# The key set is what widened, not the value rule. A bare `Session:` or
# `Transcript:` key is not a transcript trailer, so a human linking an internal
# debugging session keeps committing, and ordinary wording under a hyphenated
# key still needs a link or a token before anything is refused.
test_human_transcript_wording_and_bare_keys_are_accepted() {
  local repo
  repo=$(new_repo transcript-human-wording)
  printf 'work\n' > "$repo/a.txt"
  git -C "$repo" add a.txt
  git -C "$repo" commit -qm "fix: shorten the cookie lifetime

user-transcript: renders the wrong speaker after the merge
support-thread: the customer reported it twice
Session: https://sessions.example.internal/s/01DEDS82
Transcript: https://transcripts.example.internal/s/01DEDS82" ||
    fail "a human's own session and transcript references were refused"
  [ "$(head_subject "$repo")" = "fix: shorten the cookie lifetime" ] ||
    fail "the human transcript-wording commit did not land"
  git -C "$repo" log -1 --format=%B | grep -q "sessions.example.internal" ||
    fail "the human's own session link was lost"
  pass "fm-attribution-guard: a human's own session and transcript lines still commit"
}

# A line can carry two signatures at once. The co-author rule does not refuse a
# human co-author, and the session link riding along on that same line used to
# ride past every other rule with it.
test_session_link_on_a_coauthor_line_is_refused() {
  local repo out
  repo=$(new_repo coauthor-session-link)
  printf 'work\n' > "$repo/a.txt"
  git -C "$repo" add a.txt
  out=$(git -C "$repo" commit -m "feat: add a

Co-authored-by: Jane Doe <jane@example.com> paired via https://claude.ai/code/session_01ABC" 2>&1) &&
    fail "a session link sharing a line with a co-author trailer was accepted"
  assert_contains "$out" "session link" "refusal did not name the session-link rule"
  [ "$(head_subject "$repo")" = "seed" ] || fail "the refused commit still landed"
  git -C "$repo" commit -qm "feat: add a

Co-authored-by: Jane Doe <jane@example.com>" ||
    fail "the same human co-author without a link was refused"
  [ "$(head_subject "$repo")" = "feat: add a" ] || fail "the human co-author commit did not land"
  pass "fm-attribution-guard: a session link on a co-author line refuses the commit"
}

# An agent vendor also runs pricing, research, and company pages. Citing one is
# not attribution, while that vendor's agent product or a shared conversation on
# the same host still is.
test_vendor_reference_links_still_commit() {
  local repo
  repo=$(new_repo vendor-reference-links)
  printf 'work\n' > "$repo/a.txt"
  git -C "$repo" add a.txt
  git -C "$repo" commit -qm "docs: cite the vendor pages this decision rests on

Background: https://www.anthropic.com/research/tracing-thoughts
Pricing we compared: https://cursor.com/pricing and https://openai.com/pricing
Hiring page: https://claude.com/careers
Install docs: https://cursor.com/cli
More background: https://deepmind.com/research/alphafold and https://moonshot.ai/pricing
Company pages: https://xai.com/about and https://x.ai/news" ||
    fail "a commit citing ordinary vendor pages was refused"
  [ "$(head_subject "$repo")" = "docs: cite the vendor pages this decision rests on" ] ||
    fail "the vendor-reference commit did not land"
  pass "fm-attribution-guard: ordinary links to a vendor's own site still commit"
}

test_agent_product_links_are_refused() {
  local repo out link
  repo=$(new_repo agent-product-links)
  printf 'work\n' > "$repo/a.txt"
  git -C "$repo" add a.txt
  for link in \
    "https://claude.com/claude-code" \
    "https://www.anthropic.com/share/01ABC" \
    "https://cursor.com/conversation/01ABC" \
    "https://openai.com/codex/" \
    "https://x.ai/grok" \
    "https://kimi.moonshot.cn/chat/01ABC" \
    "https://moonshot.ai/share/01ABC" \
    "https://deepmind.com/conversation/01ABC" \
    "https://xai.com/transcript/01ABC"; do
    out=$(git -C "$repo" commit -m "feat: add a

See $link" 2>&1) && fail "a link to an agent product page was accepted: $link"
    assert_contains "$out" "session link" "refusal did not name the session-link rule for $link"
  done
  [ "$(head_subject "$repo")" = "seed" ] || fail "a refused commit still landed"
  pass "fm-attribution-guard: an agent product or conversation link refuses the commit"
}

# The URL rule anchors its host in the URL's authority, the way the address rule
# anchors on `@`. Without that a vendor host matched anywhere in the URL, so an
# unrelated path segment and a longer host that merely opens with one were both
# refused.
test_url_host_is_anchored_in_the_authority() {
  local repo out
  repo=$(new_repo url-host-anchor)
  printf 'work\n' > "$repo/a.txt"
  git -C "$repo" add a.txt
  git -C "$repo" commit -qm "docs: link the internal mail runbook

See https://docs.example.com/mailbox.ai/chat/1
And https://claude.aire.example.com/news" ||
    fail "a link whose host merely contains a vendor host was refused"
  [ "$(head_subject "$repo")" = "docs: link the internal mail runbook" ] ||
    fail "the anchored-host commit did not land"
  printf 'more\n' >> "$repo/a.txt"
  git -C "$repo" add a.txt
  out=$(git -C "$repo" commit -m "feat: extend a

See https://cursor.com/chat/1" 2>&1) &&
    fail "anchoring the host stopped refusing a real agent conversation link"
  assert_contains "$out" "session link" "refusal did not name the session-link rule"
  out=$(git -C "$repo" commit -m "feat: extend a

See https://claude.ai/code/session_01ABC" 2>&1) &&
    fail "anchoring the host stopped refusing a transcript host"
  assert_contains "$out" "session link" "refusal did not name the session-link rule"
  [ "$(head_subject "$repo")" = "docs: link the internal mail runbook" ] ||
    fail "a refused commit still landed"
  pass "fm-attribution-guard: a URL's host is judged in its authority, not anywhere in the URL"
}

test_generated_with_commit_is_refused() {
  local repo out
  repo=$(new_repo generated-with)
  printf 'work\n' > "$repo/a.txt"
  git -C "$repo" add a.txt
  out=$(git -C "$repo" commit -m "feat: add a

Generated with Claude Code" 2>&1) && fail "commit with a generated-with credit was accepted"
  assert_contains "$out" "generated-with credit" "refusal did not name the generated-with rule"
  [ "$(head_subject "$repo")" = "seed" ] || fail "the refused commit still landed"
  pass "fm-attribution-guard: a generated-with credit refuses the commit"
}

# The byline a harness actually appends, verbatim. Its host is a company site
# whose ordinary pages stay citable, so this proves the refusal does not rest on
# the URL alone.
test_harness_footer_is_refused() {
  local repo out
  repo=$(new_repo harness-footer)
  printf 'work\n' > "$repo/a.txt"
  git -C "$repo" add a.txt
  out=$(git -C "$repo" commit -m "feat: add a

Generated with [Claude Code](https://claude.com/claude-code)" 2>&1) &&
    fail "the harness byline was accepted"
  assert_contains "$out" "generated-with credit" "refusal did not name the generated-with rule"
  [ "$(head_subject "$repo")" = "seed" ] || fail "the refused commit still landed"
  pass "fm-attribution-guard: the harness byline refuses the commit"
}

# A git trailer spells the same credit with a hyphen, so the rule reads both.
test_hyphenated_credit_trailers_are_refused() {
  local repo out
  repo=$(new_repo hyphenated-credit)
  printf 'work\n' > "$repo/a.txt"
  git -C "$repo" add a.txt
  out=$(git -C "$repo" commit -m "feat: add a

Generated-With: Claude Code" 2>&1) && fail "a hyphenated generated-with trailer was accepted"
  assert_contains "$out" "generated-with credit" "refusal did not name the generated-with rule"
  out=$(git -C "$repo" commit -m "feat: add a

Assisted-By: Claude <noreply@anthropic.com>" 2>&1) && fail "a hyphenated assisted-by trailer was accepted"
  assert_contains "$out" "generated-with credit" "refusal did not name the generated-with rule"
  [ "$(head_subject "$repo")" = "seed" ] || fail "a refused commit still landed"
  git -C "$repo" commit -qm "feat: add a

Reviewed-by: Jane Doe <jane@example.com>" ||
    fail "an ordinary hyphenated trailer was refused"
  [ "$(head_subject "$repo")" = "feat: add a" ] || fail "the human trailer commit did not land"
  pass "fm-attribution-guard: a hyphenated credit trailer refuses the commit"
}

# `authored-by` hides inside `co-authored-by`, so the credit rule would read a
# sentence about cleaning those trailers up - the captain's own history work - as
# a credit, and would name a second rule on every real agent trailer.
test_wording_about_coauthor_trailers_is_accepted() {
  local repo
  repo=$(new_repo coauthor-wording)
  printf 'work\n' > "$repo/a.txt"
  git -C "$repo" add a.txt
  git -C "$repo" commit -qm "history: strip the Co-authored-by trailers Claude Code left behind" ||
    fail "a sentence about co-authored-by trailers was refused"
  [ "$(head_subject "$repo")" = "history: strip the Co-authored-by trailers Claude Code left behind" ] ||
    fail "the wording commit did not land"
  pass "fm-attribution-guard: wording about co-authored-by trailers still commits"
}

test_agent_coauthor_refusal_names_one_rule() {
  local repo out
  repo=$(new_repo coauthor-one-reason)
  printf 'work\n' > "$repo/a.txt"
  git -C "$repo" add a.txt
  out=$(git -C "$repo" commit -m "feat: add a

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>" 2>&1) &&
    fail "the agent co-author trailer was accepted"
  assert_contains "$out" "co-author line naming an agent" "refusal did not name the co-author rule"
  case "$out" in
    *"generated-with credit"*)
      fail "the refusal named a rule the line has nothing to do with: $out"
      ;;
  esac
  pass "fm-attribution-guard: an agent co-author trailer is refused by one rule"
}

# The hyphen still has to reach every other spelling of the credit.
test_hyphen_prefixed_credit_wording_is_refused() {
  local repo out line
  repo=$(new_repo hyphen-credit-wording)
  printf 'work\n' > "$repo/a.txt"
  git -C "$repo" add a.txt
  for line in \
    "chore: ship the auto-generated with Claude Code helper" \
    "chore: the module was Co-generated with Claude Code"; do
    out=$(git -C "$repo" commit -m "$line" 2>&1) && fail "a credit spelling was accepted: $line"
    assert_contains "$out" "generated-with credit" "refusal did not name the generated-with rule for $line"
  done
  [ "$(head_subject "$repo")" = "seed" ] || fail "a refused commit still landed"
  pass "fm-attribution-guard: a hyphen-prefixed credit verb still refuses the commit"
}

# A plain sentence about code generation is not attribution.
test_ordinary_generated_wording_is_accepted() {
  local repo
  repo=$(new_repo ordinary-generated)
  printf 'work\n' > "$repo/a.txt"
  git -C "$repo" add a.txt
  git -C "$repo" commit -qm "chore: refresh the client generated with the openapi script" ||
    fail "an ordinary generated-with sentence was refused"
  [ "$(head_subject "$repo")" = "chore: refresh the client generated with the openapi script" ] ||
    fail "the ordinary commit did not land"
  pass "fm-attribution-guard: ordinary generated-with wording still commits"
}

test_claude_md_commit_is_refused() {
  local repo out
  repo=$(new_repo claude-md)
  printf '@AGENTS.md\n' > "$repo/CLAUDE.md"
  git -C "$repo" add -f CLAUDE.md
  out=$(git -C "$repo" commit -m "chore: add project memory" 2>&1) &&
    fail "commit adding CLAUDE.md was accepted"
  assert_contains "$out" "CLAUDE.md" "refusal did not name the offending path"
  [ "$(head_subject "$repo")" = "seed" ] || fail "the refused commit still landed"
  pass "fm-attribution-guard: adding CLAUDE.md refuses the commit"
}

test_claude_dir_commit_is_refused() {
  local repo out
  repo=$(new_repo claude-dir)
  mkdir -p "$repo/.claude"
  printf '{}\n' > "$repo/.claude/settings.json"
  git -C "$repo" add -f .claude/settings.json
  out=$(git -C "$repo" commit -m "chore: add settings" 2>&1) &&
    fail "commit adding .claude/ was accepted"
  assert_contains "$out" ".claude/settings.json" "refusal did not name the offending path"
  [ "$(head_subject "$repo")" = "seed" ] || fail "the refused commit still landed"
  pass "fm-attribution-guard: adding .claude/ refuses the commit"
}

test_agents_md_commit_is_accepted() {
  local repo
  repo=$(new_repo agents-md)
  printf '# Project agent memory\n' > "$repo/AGENTS.md"
  git -C "$repo" add AGENTS.md
  git -C "$repo" commit -qm "chore: add AGENTS.md" || fail "commit adding AGENTS.md was refused"
  git -C "$repo" ls-files --error-unmatch AGENTS.md >/dev/null 2>&1 ||
    fail "AGENTS.md did not land"
  pass "fm-attribution-guard: AGENTS.md still commits"
}

# The project's own hooks must survive being overridden.
test_project_hook_still_runs() {
  local repo hooks out
  repo=$(new_repo chained-hook)
  hooks="$repo/.git/hooks"
  mkdir -p "$hooks"
  cat > "$hooks/commit-msg" <<'SH'
#!/usr/bin/env bash
grep -q "^feat\|^fix\|^chore" "$1" || { echo "project hook: bad subject" >&2; exit 1; }
echo "project hook ran" >&2
SH
  chmod +x "$hooks/commit-msg"
  printf 'work\n' > "$repo/a.txt"
  git -C "$repo" add a.txt
  out=$(git -C "$repo" commit -m "nope: bad subject" 2>&1) &&
    fail "the project's own hook was bypassed"
  assert_contains "$out" "project hook: bad subject" "the project's own commit-msg hook did not run"
  out=$(git -C "$repo" commit -m "feat: good subject" 2>&1) ||
    fail "a message both hooks accept was refused: $out"
  assert_contains "$out" "project hook ran" "the project's own hook did not run on the accepted commit"
  pass "fm-attribution-guard: the project's own commit-msg hook still runs"
}

# --no-verify is a real gap at commit time; the push pass is what closes it.
test_no_verify_commit_is_caught_at_push() {
  local repo remote out
  repo=$(new_repo no-verify-push)
  remote="$TMP_ROOT/no-verify-push.git"
  git init -q --bare "$remote"
  git -C "$repo" remote add origin "$remote"
  unarmed_git -C "$repo" push -q origin HEAD:refs/heads/main || fail "seed push failed"
  printf 'work\n' > "$repo/a.txt"
  git -C "$repo" add a.txt
  git -C "$repo" commit -q --no-verify -m "feat: add a

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>" ||
    fail "--no-verify commit did not land, so the push case cannot be exercised"
  out=$(git -C "$repo" push origin HEAD:refs/heads/main 2>&1) &&
    fail "pushing a commit with agent attribution was accepted"
  assert_contains "$out" "outgoing commit carries agent attribution" \
    "the push refusal did not name the outgoing commit"
  pass "fm-attribution-guard: a --no-verify commit is still refused at push"
}

# The commit gate refuses this shape outright now, so the commit has to be forced
# past it to reach the case this covers: a recorded message is final text, and
# the push pass has to see the trailer the comment marker hides.
test_verbatim_commented_trailer_is_caught_at_push() {
  local repo remote out msg
  repo=$(new_repo verbatim-comment)
  remote="$TMP_ROOT/verbatim-comment.git"
  git init -q --bare "$remote"
  git -C "$repo" remote add origin "$remote"
  unarmed_git -C "$repo" push -q origin HEAD:refs/heads/main || fail "seed push failed"
  printf 'work\n' > "$repo/a.txt"
  git -C "$repo" add a.txt
  msg="$TMP_ROOT/verbatim-comment.msg"
  printf 'feat: add a\n\n# Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n' > "$msg"
  git -C "$repo" commit -q --no-verify --cleanup=verbatim -F "$msg" ||
    fail "the commented trailer did not commit, so the push case cannot be exercised"
  git -C "$repo" log -1 --format=%B | grep -q 'noreply@anthropic.com' ||
    fail "the commented trailer did not survive into the recorded message"
  out=$(git -C "$repo" push origin HEAD:refs/heads/main 2>&1) &&
    fail "pushing a recorded message that hides an agent trailer in a comment was accepted"
  assert_contains "$out" "outgoing commit carries agent attribution" \
    "the push refusal did not name the outgoing commit"
  [ "$(git -C "$remote" log -1 --format=%s refs/heads/main)" = "seed" ] ||
    fail "the tainted commit reached the remote"
  pass "fm-attribution-guard: a trailer hidden in a comment is refused at push"
}

# A repository that deliberately tracks one of these names must stay maintainable;
# a new one appearing beside it is still refused.
test_tracked_agent_path_stays_maintainable() {
  local repo remote out
  repo=$(new_repo tracked-agent-path)
  remote="$TMP_ROOT/tracked-agent-path.git"
  git init -q --bare "$remote"
  mkdir -p "$repo/.claude"
  printf '{}\n' > "$repo/.claude/settings.json"
  printf '@AGENTS.md\n' > "$repo/CLAUDE.md"
  unarmed_git -C "$repo" add -f .claude/settings.json CLAUDE.md
  unarmed_git -C "$repo" commit -qm "chore: track agent config on purpose" ||
    fail "fixture commit failed"
  git -C "$repo" remote add origin "$remote"
  unarmed_git -C "$repo" push -q origin HEAD:refs/heads/main || fail "seed push failed"

  printf '{"model":"x"}\n' > "$repo/.claude/settings.json"
  printf '@AGENTS.md\n\n' > "$repo/CLAUDE.md"
  git -C "$repo" add .claude/settings.json CLAUDE.md
  git -C "$repo" commit -qm "chore: update the tracked agent config" ||
    fail "modifying already-tracked agent paths was refused"
  git -C "$repo" push -q origin HEAD:refs/heads/main ||
    fail "pushing a change to already-tracked agent paths was refused"
  [ "$(git -C "$remote" log -1 --format=%s refs/heads/main)" = "chore: update the tracked agent config" ] ||
    fail "the tracked-path change did not reach the remote"

  printf '{}\n' > "$repo/.claude/other.json"
  git -C "$repo" add -f .claude/other.json
  out=$(git -C "$repo" commit -m "chore: add a new agent file" 2>&1) &&
    fail "a new .claude path was accepted just because a sibling is tracked"
  assert_contains "$out" ".claude/other.json" "refusal did not name the untracked path"
  pass "fm-attribution-guard: an already-tracked agent path stays maintainable"
}

# Tier B is a vendor product name that is also an ordinary English word or given
# name, so on its own it is not attribution.
test_ordinary_vendor_wording_is_accepted() {
  local repo
  repo=$(new_repo vendor-wording)
  printf 'work\n' > "$repo/a.txt"
  git -C "$repo" add a.txt
  git -C "$repo" commit -qm "refactor: the tokenizer was rewritten by hand to drop the llama dependency" ||
    fail "a message whose 'written by' sits inside 'rewritten by' was refused"
  printf 'more\n' > "$repo/b.txt"
  git -C "$repo" add b.txt
  git -C "$repo" commit -qm "feat: response created with mistral-small endpoint" ||
    fail "a vendor product name without a bot signal was refused"
  [ "$(head_subject "$repo")" = "feat: response created with mistral-small endpoint" ] ||
    fail "the ordinary vendor-wording commit did not land"
  pass "fm-attribution-guard: ordinary wording naming a model vendor still commits"
}

# git prints nothing for a merge commit's own tree without a combined diff, so a
# merge that introduces the file itself used to sail past the path scan.
test_evil_merge_adding_claude_md_is_refused_at_push() {
  local repo remote out
  repo=$(new_repo evil-merge)
  remote="$TMP_ROOT/evil-merge.git"
  git init -q --bare "$remote"
  git -C "$repo" remote add origin "$remote"
  unarmed_git -C "$repo" push -q origin HEAD:refs/heads/main || fail "seed push failed"
  unarmed_git -C "$repo" checkout -qb side
  printf 'side\n' > "$repo/side.txt"
  unarmed_git -C "$repo" add side.txt
  unarmed_git -C "$repo" commit -qm "feat: side work"
  unarmed_git -C "$repo" checkout -q main
  printf 'main\n' > "$repo/main.txt"
  unarmed_git -C "$repo" add main.txt
  unarmed_git -C "$repo" commit -qm "feat: main work"
  unarmed_git -C "$repo" merge --no-commit --no-ff side >/dev/null 2>&1
  printf '@AGENTS.md\n' > "$repo/CLAUDE.md"
  unarmed_git -C "$repo" add -f CLAUDE.md
  unarmed_git -C "$repo" commit -qm "chore: merge side" ||
    fail "the evil merge did not commit, so the push case cannot be exercised"
  [ "$(git -C "$repo" log -1 --format=%P | wc -w)" -eq 2 ] || fail "the fixture is not a merge commit"
  out=$(git -C "$repo" push origin HEAD:refs/heads/main 2>&1) &&
    fail "pushing a merge that introduces CLAUDE.md in its own tree was accepted"
  assert_contains "$out" "CLAUDE.md" "the push refusal did not name the offending path"
  [ "$(git -C "$remote" log -1 --format=%s refs/heads/main)" = "seed" ] ||
    fail "the evil merge reached the remote"
  pass "fm-attribution-guard: an evil merge adding CLAUDE.md is refused at push"
}

# core.hooksPath replaces the repository's hook directory outright, so a hook
# name the guard does not check must still reach the project's own hook.
test_project_pass_through_hooks_still_run() {
  local repo hooks out
  repo=$(new_repo pass-through)
  hooks="$repo/.git/hooks"
  mkdir -p "$hooks"
  cat > "$hooks/post-commit" <<SH
#!/usr/bin/env bash
printf 'post-commit ran\n' > "$repo/post-commit.marker"
SH
  cat > "$hooks/prepare-commit-msg" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$1" > "$repo/prepare.marker"
grep -q "^allow" "\$1" || { echo "project hook: subject not allowed" >&2; exit 1; }
SH
  chmod +x "$hooks/post-commit" "$hooks/prepare-commit-msg"

  printf 'work\n' > "$repo/a.txt"
  git -C "$repo" add a.txt
  out=$(git -C "$repo" commit -m "denied: bad subject" 2>&1) &&
    fail "the project's prepare-commit-msg hook did not abort the commit"
  assert_contains "$out" "project hook: subject not allowed" \
    "the project's prepare-commit-msg hook did not run"
  [ ! -e "$repo/post-commit.marker" ] || fail "post-commit ran for an aborted commit"

  git -C "$repo" commit -qm "allow: good subject" || fail "an allowed commit was refused"
  assert_present "$repo/prepare.marker" "prepare-commit-msg left no evidence it ran"
  assert_present "$repo/post-commit.marker" "the project's post-commit hook did not run"
  grep -q 'COMMIT_EDITMSG$' "$repo/prepare.marker" ||
    fail "prepare-commit-msg did not receive git's own message-file argument: $(cat "$repo/prepare.marker")"
  pass "fm-attribution-guard: a project's unchecked hooks still run"
}

# `--remotes=<pattern>` is a glob over refs/remotes/ and matches nothing for a
# filesystem path or a never-fetched remote name, which used to make the whole
# history outgoing and refuse the push over an ancestor the remote already has.
seed_tainted_history() {  # <name>; echoes "<repo> <remote>"
  local repo remote
  repo=$(new_repo "$1")
  remote="$TMP_ROOT/$1.git"
  git init -q --bare "$remote"
  printf 'old\n' > "$repo/old.txt"
  unarmed_git -C "$repo" add old.txt
  unarmed_git -C "$repo" commit -qm "chore: historical work

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>" ||
    fail "could not seed a tainted ancestor"
  unarmed_git -C "$repo" push -q "$remote" HEAD:refs/heads/main || fail "seed push failed"
  printf '%s %s\n' "$repo" "$remote"
}

test_push_to_a_path_remote_ignores_ancestors_the_remote_has() {
  local repo remote out
  read -r repo remote <<< "$(seed_tainted_history path-remote)"
  unarmed_git -C "$repo" checkout -qb feature
  printf 'new\n' > "$repo/new.txt"
  git -C "$repo" add new.txt
  git -C "$repo" commit -qm "feat: clean work" || fail "the clean commit was refused"
  out=$(git -C "$repo" push "$remote" HEAD:refs/heads/feature 2>&1) ||
    fail "a clean push to a filesystem-path remote was refused over an ancestor the remote already has: $out"
  [ "$(git -C "$remote" log -1 --format=%s refs/heads/feature)" = "feat: clean work" ] ||
    fail "the clean commit did not reach the remote"
  pass "fm-attribution-guard: a push by path is judged only on what it adds"
}

test_push_to_a_never_fetched_remote_ignores_ancestors_the_remote_has() {
  local repo remote out
  read -r repo remote <<< "$(seed_tainted_history named-remote)"
  unarmed_git -C "$repo" remote add gate "$remote"
  [ -z "$(git -C "$repo" for-each-ref --format='%(refname)' refs/remotes/gate)" ] ||
    fail "the fixture remote already has tracking refs, so it does not exercise the case"
  unarmed_git -C "$repo" checkout -qb feature
  printf 'new\n' > "$repo/new.txt"
  git -C "$repo" add new.txt
  git -C "$repo" commit -qm "feat: clean work" || fail "the clean commit was refused"
  out=$(git -C "$repo" push gate HEAD:refs/heads/feature 2>&1) ||
    fail "a clean push to a never-fetched named remote was refused over an ancestor: $out"
  [ "$(git -C "$remote" log -1 --format=%s refs/heads/feature)" = "feat: clean work" ] ||
    fail "the clean commit did not reach the remote"
  pass "fm-attribution-guard: a push to a never-fetched remote is judged only on what it adds"
}

# A commit the push genuinely adds must still be caught in that same shape.
test_push_to_a_path_remote_still_refuses_a_new_tainted_commit() {
  local repo remote out
  read -r repo remote <<< "$(seed_tainted_history path-remote-tainted)"
  unarmed_git -C "$repo" checkout -qb feature
  printf 'new\n' > "$repo/new.txt"
  git -C "$repo" add new.txt
  git -C "$repo" commit -q --no-verify -m "feat: new work

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>" ||
    fail "the fixture commit did not land"
  out=$(git -C "$repo" push "$remote" HEAD:refs/heads/feature 2>&1) &&
    fail "a newly added tainted commit was accepted"
  assert_contains "$out" "outgoing commit carries agent attribution" \
    "the push refusal did not name the outgoing commit"
  pass "fm-attribution-guard: a push by path still refuses a commit it adds"
}

# git's pre-push input carries the object name the ref has ON THE REMOTE, which
# a diverged or never-fetched repository need not have in its own object store.
# `git rev-list <that sha>..<local>` then dies, and swallowing that would leave
# the ref scanned for nothing while --force pushed it anyway.
test_push_with_a_remote_sha_this_repo_lacks_is_still_checked() {
  local repo remote other out
  repo=$(new_repo missing-remote-sha)
  remote="$TMP_ROOT/missing-remote-sha.git"
  other="$TMP_ROOT/missing-remote-sha-other"
  git init -q --bare "$remote"
  git -C "$repo" remote add origin "$remote"
  unarmed_git -C "$repo" push -q origin HEAD:refs/heads/main || fail "seed push failed"
  # A second worker advances the remote; this repo never fetches that commit.
  unarmed_git clone -q "$remote" "$other" || fail "fixture clone failed"
  unarmed_git -C "$other" config user.email mate@example.com
  unarmed_git -C "$other" config user.name Mate
  printf 'theirs\n' > "$other/theirs.txt"
  unarmed_git -C "$other" add theirs.txt
  unarmed_git -C "$other" commit -qm "feat: their work" || fail "fixture commit failed"
  unarmed_git -C "$other" push -q origin HEAD:refs/heads/main || fail "fixture push failed"

  printf 'work\n' > "$repo/a.txt"
  git -C "$repo" add a.txt
  git -C "$repo" commit -q --no-verify -m "feat: add a

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>" ||
    fail "the tainted commit did not land, so the push case cannot be exercised"
  git -C "$repo" cat-file -e "$(git -C "$remote" rev-parse refs/heads/main)^{commit}" 2>/dev/null &&
    fail "the fixture repository has the remote's commit, so it does not exercise the case"
  out=$(git -C "$repo" push --force origin HEAD:refs/heads/main 2>&1) &&
    fail "a force push whose remote sha is unknown locally was accepted unchecked"
  assert_contains "$out" "outgoing commit carries agent attribution" \
    "the push refusal did not name the outgoing commit"
  [ "$(git -C "$remote" log -1 --format=%s refs/heads/main)" = "feat: their work" ] ||
    fail "the tainted commit reached the remote"
  pass "fm-attribution-guard: a push whose remote sha is missing locally is still scanned"
}

# Arming core.hooksPath at a directory git finds no hooks in would leave the
# worker silently unguarded, so resolving the arming must fail instead.
test_export_env_refuses_a_hooks_dir_without_the_checked_hooks() {
  local stage out rc=0
  stage="$TMP_ROOT/bare-hooks/bin"
  mkdir -p "$stage/git-hooks"
  cp "$ROOT/bin/fm-attribution-guard.sh" "$ROOT/bin/fm-git-tracked-lib.sh" "$stage/"
  chmod +x "$stage/fm-attribution-guard.sh"
  out=$("$stage/fm-attribution-guard.sh" export-env 2>&1) || rc=$?
  [ "$rc" -ne 0 ] || fail "export-env printed an arming line for a directory with no hooks: $out"
  assert_contains "$out" "commit-msg" "the failure did not name the missing hooks"
  case "$out" in
    *GIT_CONFIG_KEY_0*) fail "export-env printed an arming line despite failing" ;;
  esac
  pass "fm-attribution-guard: export-env refuses a hooks directory git would find empty"
}

test_clean_push_is_accepted() {
  local repo remote
  repo=$(new_repo clean-push)
  remote="$TMP_ROOT/clean-push.git"
  git init -q --bare "$remote"
  git -C "$repo" remote add origin "$remote"
  unarmed_git -C "$repo" push -q origin HEAD:refs/heads/main || fail "seed push failed"
  printf 'work\n' > "$repo/a.txt"
  git -C "$repo" add a.txt
  git -C "$repo" commit -qm "feat: add a

Co-authored-by: Jane Doe <jane@example.com>" || fail "clean commit was refused"
  git -C "$repo" push -q origin HEAD:refs/heads/main || fail "clean push was refused"
  [ "$(git -C "$remote" log -1 --format=%s refs/heads/main)" = "feat: add a" ] ||
    fail "the clean commit did not reach the remote"
  pass "fm-attribution-guard: a clean branch still pushes"
}

# Without the arming there is no enforcement; this is the documented gap, and
# asserting it keeps the other cases honest about what is doing the work.
test_unarmed_repo_is_not_enforced() {
  local repo
  repo=$(new_repo unarmed)
  printf 'work\n' > "$repo/a.txt"
  git -C "$repo" add a.txt
  unarmed_git -C "$repo" commit -qm "feat: add a

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>" ||
    fail "an unarmed repository unexpectedly refused the commit"
  [ "$(head_subject "$repo")" = "feat: add a" ] || fail "the unarmed commit did not land"
  pass "fm-attribution-guard: enforcement comes from the arming, not from the repository"
}

test_every_ruled_message_shape_keeps_its_verdict
test_decorated_coauthor_trailer_is_refused
test_commented_agent_trailer_is_refused_at_commit
test_configured_comment_marker_is_honoured
test_verbose_commit_under_a_configured_marker_still_commits
test_verbose_commit_removing_a_trailer_still_commits
test_scissors_line_typed_by_hand_is_caught_at_push
test_agent_coauthor_commit_is_refused
test_codex_coauthor_commit_is_refused
test_human_coauthor_commit_is_accepted
test_human_named_claude_is_accepted
test_human_at_a_github_private_address_is_accepted
test_bots_at_a_github_private_address_are_refused
test_env_names_covers_every_name_export_env_assigns
test_humans_whose_names_contain_agent_tokens_are_accepted
test_agent_vendor_domain_coauthor_is_refused
test_vendor_address_alone_refuses_a_coauthor_line
test_session_link_commit_is_refused
test_session_link_on_a_coauthor_line_is_refused
test_vendor_reference_links_still_commit
test_agent_product_links_are_refused
test_url_host_is_anchored_in_the_authority
test_generated_with_commit_is_refused
test_harness_footer_is_refused
test_hyphenated_credit_trailers_are_refused
test_wording_about_coauthor_trailers_is_accepted
test_agent_coauthor_refusal_names_one_rule
test_hyphen_prefixed_credit_wording_is_refused
test_ordinary_generated_wording_is_accepted
test_ordinary_session_wording_is_accepted
test_session_trailer_with_a_link_value_is_refused
test_session_trailer_naming_an_agent_is_refused
test_every_transcript_trailer_key_is_refused
test_human_transcript_wording_and_bare_keys_are_accepted
test_claude_md_commit_is_refused
test_claude_dir_commit_is_refused
test_agents_md_commit_is_accepted
test_project_hook_still_runs
test_no_verify_commit_is_caught_at_push
test_verbatim_commented_trailer_is_caught_at_push
test_tracked_agent_path_stays_maintainable
test_ordinary_vendor_wording_is_accepted
test_evil_merge_adding_claude_md_is_refused_at_push
test_project_pass_through_hooks_still_run
test_push_to_a_path_remote_ignores_ancestors_the_remote_has
test_push_to_a_never_fetched_remote_ignores_ancestors_the_remote_has
test_push_to_a_path_remote_still_refuses_a_new_tainted_commit
test_push_with_a_remote_sha_this_repo_lacks_is_still_checked
test_export_env_refuses_a_hooks_dir_without_the_checked_hooks
test_clean_push_is_accepted
test_unarmed_repo_is_not_enforced
