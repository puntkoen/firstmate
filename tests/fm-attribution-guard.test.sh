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

# A recorded message is final text, so a `#` line in it is real content. Git's
# default cleanup would have removed this trailer before the commit existed;
# --cleanup=verbatim keeps it, so the push pass is what has to see it.
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
  git -C "$repo" commit -q --cleanup=verbatim -F "$msg" ||
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

test_agent_coauthor_commit_is_refused
test_codex_coauthor_commit_is_refused
test_human_coauthor_commit_is_accepted
test_human_named_claude_is_accepted
test_session_link_commit_is_refused
test_generated_with_commit_is_refused
test_ordinary_generated_wording_is_accepted
test_claude_md_commit_is_refused
test_claude_dir_commit_is_refused
test_agents_md_commit_is_accepted
test_project_hook_still_runs
test_no_verify_commit_is_caught_at_push
test_verbatim_commented_trailer_is_caught_at_push
test_tracked_agent_path_stays_maintainable
test_ordinary_vendor_wording_is_accepted
test_clean_push_is_accepted
test_unarmed_repo_is_not_enforced
