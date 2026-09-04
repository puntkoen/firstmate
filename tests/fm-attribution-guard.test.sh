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

# Arming core.hooksPath at a directory git finds no hooks in would leave the
# worker silently unguarded, so resolving the arming must fail instead.
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

test_export_env_refuses_a_hooks_dir_without_the_checked_hooks() {
  local stage out rc=0
  stage="$TMP_ROOT/bare-hooks/bin"
  mkdir -p "$stage/git-hooks"
  cp "$ROOT/bin/fm-attribution-guard.sh" "$stage/fm-attribution-guard.sh"
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

test_agent_coauthor_commit_is_refused
test_codex_coauthor_commit_is_refused
test_human_coauthor_commit_is_accepted
test_human_named_claude_is_accepted
test_humans_whose_names_contain_agent_tokens_are_accepted
test_session_link_commit_is_refused
test_generated_with_commit_is_refused
test_ordinary_generated_wording_is_accepted
test_ordinary_session_wording_is_accepted
test_session_trailer_with_a_link_value_is_refused
test_session_trailer_naming_an_agent_is_refused
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
