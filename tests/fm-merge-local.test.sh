#!/usr/bin/env bash
# Behavior tests for the working-tree guard in bin/fm-merge-local.sh.
#
# The guard is split by what a fast-forward can actually destroy. Modified or
# staged TRACKED files always refuse, because the landing would overwrite them.
# An untracked file is only at risk when the incoming range puts a file at
# exactly its path, so an unrelated scratch directory the captain keeps on
# purpose must not block the landing. The diverged-branch refusal is unchanged.
#
# Every case here drives the real entrypoint against a fixture project, so a
# refusal is proven by the default branch staying where it was, not by reading
# the script.
set -u

# shellcheck source=tests/lib.sh
# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# An exported TASKS_AXI_BACKEND outranks the fixture's own .tasks.toml in
# fm_tasks_axi_backend_resolve, so the merge-authority check must start from a
# clean slate before the fixtures pin the backend themselves.
unset TASKS_AXI_BACKEND || :

TMP_ROOT=$(fm_test_tmproot fm-merge-local)

# A home with no backlog at all: no captain call can be recorded, so the merge
# authority check reports "absent" and the landing turns only on the working
# tree, which is what these cases are about.
make_home() {  # <name>
  local home="$TMP_ROOT/$1" fakebin
  mkdir -p "$home/data" "$home/state" "$home/config" "$home/projects"
  # Pin the backend to the fixture, so the absent-backlog path is decided here
  # and not by whatever tasks-axi configuration the host happens to carry.
  cp "$ROOT/.tasks.toml" "$home/.tasks.toml"
  fakebin=$(fm_fakebin "$home")
  fm_fake_exit0 "$fakebin" tmux treehouse no-mistakes gh gh-axi
  printf '%s\n' "$home"
}

git_commit() {  # <dir> <message>
  git -C "$1" -c user.name='Firstmate Tests' -c user.email='tests@example.invalid' \
    commit -qm "$2"
}

# Build a local-only ship task whose branch adds the approved fix, and echo
# "<project repo>|<task worktree>". The incoming commit touches only the two
# flexible-content files, so nothing else in the project can be in its way.
make_local_task() {  # <home> <id>
  local home=$1 id=$2 repo wt
  repo="$home/projects/sample-local"
  wt="$home/projects/$id"
  fm_git_worktree "$repo" "$wt" "fm/$id"
  mkdir -p "$wt/flexibele-content/two_column_section"
  printf '.two-column { display: flex; }\n' \
    > "$wt/flexibele-content/two_column_section/two_column_section.css"
  printf '<?php // two column section\n' \
    > "$wt/flexibele-content/two_column_section/two_column_section.php"
  git -C "$wt" add flexibele-content
  git_commit "$wt" 'fix the two column section'
  fm_write_meta "$home/state/$id.meta" \
    "window=firstmate:fm-$id" "endpoint_task_id=$id" "worktree=$wt" \
    "project=$repo" "harness=codex" "kind=ship" "mode=local-only" \
    "spawn_gen=fixture-$id"
  printf '%s|%s\n' "$repo" "$wt"
}

run_merge_local() {  # <home> <id>
  local home=$1
  shift
  PATH="$home/fakebin:$PATH" FM_ROOT_OVERRIDE="$ROOT" FM_HOME="$home" \
    FM_STATE_OVERRIDE="$home/state" FM_DATA_OVERRIDE="$home/data" \
    FM_CONFIG_OVERRIDE="$home/config" "$ROOT/bin/fm-merge-local.sh" "$@"
}

test_untracked_directory_beside_the_change_does_not_block_the_landing() {
  local home id repo wt before after rc
  home=$(make_home untracked-beside)
  id=sample-untracked-beside
  IFS='|' read -r repo wt <<< "$(make_local_task "$home" "$id")"

  # The captain keeps a database dump in the project on purpose. It shares no
  # path with the incoming fix, so the fast-forward cannot touch it.
  mkdir -p "$repo/import"
  printf 'INSERT INTO orders VALUES (1);\n' > "$repo/import/dump.sql"
  before=$(git -C "$repo" rev-parse main)

  set +e
  run_merge_local "$home" "$id" > "$home/merge.out" 2> "$home/merge.err"
  rc=$?
  set -e
  after=$(git -C "$repo" rev-parse main)
  [ "$rc" -eq 0 ] || fail "the local merge refused an unrelated untracked directory: $(cat "$home/merge.err")"
  [ "$after" != "$before" ] || fail "the local merge reported success without moving the default branch"
  assert_grep "merged fm/$id into local main" "$home/merge.out" \
    "the successful landing did not report the merge"
  assert_present "$repo/import/dump.sql" "the landing removed the captain's untracked file"
  assert_equals 'INSERT INTO orders VALUES (1);' "$(cat "$repo/import/dump.sql")" \
    "the landing rewrote the captain's untracked file"
  assert_grep 'display: flex' \
    "$repo/flexibele-content/two_column_section/two_column_section.css" \
    "the landing did not deliver the incoming change"
  pass "an untracked directory beside the incoming change does not block the landing"
}

test_untracked_file_on_an_incoming_path_refuses_and_names_it() {
  local home id repo wt before after rc collision
  home=$(make_home untracked-collision)
  id=sample-untracked-collision
  IFS='|' read -r repo wt <<< "$(make_local_task "$home" "$id")"

  # This time the untracked file sits on exactly a path the incoming commit
  # adds, so landing would destroy it.
  collision="flexibele-content/two_column_section/two_column_section.css"
  mkdir -p "$repo/flexibele-content/two_column_section"
  printf '.local-only-draft {}\n' > "$repo/$collision"
  before=$(git -C "$repo" rev-parse main)

  set +e
  run_merge_local "$home" "$id" > "$home/merge.out" 2> "$home/merge.err"
  rc=$?
  set -e
  after=$(git -C "$repo" rev-parse main)
  [ "$rc" -ne 0 ] || fail "the local merge accepted a collision with an untracked file"
  [ "$after" = "$before" ] || fail "the refused local merge moved the default branch"
  assert_grep "$collision" "$home/merge.err" \
    "the refusal did not name the colliding path"
  assert_equals '.local-only-draft {}' "$(cat "$repo/$collision")" \
    "the refused local merge overwrote the untracked file it refused for"
  pass "an untracked file on an incoming path refuses and names that path"
}

test_modified_or_staged_tracked_files_still_refuse() {
  local home id repo wt before after rc
  home=$(make_home tracked-dirty)
  id=sample-tracked-dirty
  IFS='|' read -r repo wt <<< "$(make_local_task "$home" "$id")"
  before=$(git -C "$repo" rev-parse main)

  # A modified tracked file is exactly what the fast-forward could overwrite.
  printf '# edited by the captain\n' >> "$repo/README.md"
  set +e
  run_merge_local "$home" "$id" > "$home/modified.out" 2> "$home/modified.err"
  rc=$?
  set -e
  after=$(git -C "$repo" rev-parse main)
  [ "$rc" -ne 0 ] || fail "the local merge accepted a modified tracked file"
  [ "$after" = "$before" ] || fail "the refused local merge moved the default branch"
  assert_grep "modified or staged tracked files" "$home/modified.err" \
    "the refusal did not name the tracked dirtiness"
  git -C "$repo" checkout -q -- README.md

  # Staging a new file makes it tracked, so it refuses even though it was
  # untracked a moment earlier.
  printf 'staged note\n' > "$repo/note.txt"
  git -C "$repo" add note.txt
  set +e
  run_merge_local "$home" "$id" > "$home/staged.out" 2> "$home/staged.err"
  rc=$?
  set -e
  after=$(git -C "$repo" rev-parse main)
  [ "$rc" -ne 0 ] || fail "the local merge accepted a staged tracked file"
  [ "$after" = "$before" ] || fail "the refused local merge moved the default branch"
  assert_grep "modified or staged tracked files" "$home/staged.err" \
    "the staged refusal did not name the tracked dirtiness"
  pass "modified or staged tracked files still refuse the local merge"
}

test_diverged_branch_still_refuses() {
  local home id repo wt before after rc
  home=$(make_home diverged)
  id=sample-diverged
  IFS='|' read -r repo wt <<< "$(make_local_task "$home" "$id")"

  # Move the default branch on after the task branched, so the branch is no
  # longer a fast-forward, and keep an unrelated untracked directory beside it
  # to prove the relaxed untracked rule does not soften this refusal.
  printf 'main moved on\n' > "$repo/CHANGELOG.md"
  git -C "$repo" add CHANGELOG.md
  git_commit "$repo" 'main moved on'
  mkdir -p "$repo/import"
  printf 'INSERT INTO orders VALUES (1);\n' > "$repo/import/dump.sql"
  before=$(git -C "$repo" rev-parse main)

  set +e
  run_merge_local "$home" "$id" > "$home/merge.out" 2> "$home/merge.err"
  rc=$?
  set -e
  after=$(git -C "$repo" rev-parse main)
  [ "$rc" -ne 0 ] || fail "the local merge accepted a diverged branch"
  [ "$after" = "$before" ] || fail "the refused local merge moved the default branch"
  assert_grep "is not a fast-forward of main" "$home/merge.err" \
    "the refusal did not report the divergence"
  pass "a diverged branch still refuses the local merge"
}

test_untracked_directory_beside_the_change_does_not_block_the_landing
test_untracked_file_on_an_incoming_path_refuses_and_names_it
test_modified_or_staged_tracked_files_still_refuse
test_diverged_branch_still_refuses
