#!/usr/bin/env bash
# Behavior tests for the attribution suppression bin/fm-spawn.sh installs.
#
# Layer one is per-harness suppression at the source; layer two is the
# harness-independent guard bin/fm-attribution-guard.sh enforces. This suite
# proves a real spawn delivers both to the worker: the guard arming reaches the
# pane before the launch command, and claude's own byline is switched off in the
# settings file the spawn writes. tests/fm-attribution-guard.test.sh owns
# whether the guard's refusals are correct.
set -u

# shellcheck source=tests/fixtures.sh
. "$(dirname "${BASH_SOURCE[0]}")/fixtures.sh"

TMP_ROOT=$(fm_test_tmproot fm-spawn-attribution)
HOOKS_DIR=$("$ROOT/bin/fm-attribution-guard.sh" hooks-dir)

# Fake tmux that logs the payload of BOTH send forms - the text line
# (`send-keys -t <target> <text> Enter`) that carries the shell setup and the
# literal (`send-keys -t <target> -l <text>`) that carries the launch command -
# one per line in send order, so ordering between them is observable. A literal
# payload is written with a `launch: ` prefix, because which form carried a line
# is what the tests below need and the payloads themselves are ordinary shell.
make_attribution_fakebin() {
  local dir=$1 fakebin
  fakebin=$(fm_fakebin "$dir")
  cat > "$fakebin/tmux" <<'SH'
#!/usr/bin/env bash
set -u
case "$*" in
  *"#{pane_current_path}"*) printf '%s\n' "${FM_FAKE_PANE_PATH:-}"; exit 0 ;;
esac
case "${1:-}" in
  display-message) printf 'firstmate\n'; exit 0 ;;
  list-windows) exit 0 ;;
  has-session|new-session|new-window|kill-window|set-window-option) exit 0 ;;
  send-keys)
    if [ -n "${FM_FAKE_SEND_FAIL_MATCH:-}" ]; then
      case "$*" in
        *"$FM_FAKE_SEND_FAIL_MATCH"*) exit 1 ;;
      esac
    fi
    if [ -n "${FM_FAKE_LAUNCH_LOG:-}" ]; then
      shift
      skip_next=
      literal=
      for a in "$@"; do
        if [ -n "$skip_next" ]; then skip_next=; continue; fi
        case "$a" in
          -t) skip_next=1; continue ;;
          -l) literal=1; continue ;;
          Enter|C-m) continue ;;
          *) printf '%s%s\n' "${literal:+launch: }" "$a" >> "$FM_FAKE_LAUNCH_LOG" ;;
        esac
      done
    fi
    exit 0
    ;;
esac
exit 0
SH
  chmod +x "$fakebin/tmux"
  fm_fake_exit0 "$fakebin" treehouse gh gh-axi
  printf '%s\n' "$fakebin"
}

# make_case <name> <id> <harness> echoes "<home>|<project>|<worktree>|<fakebin>"
make_case() {
  local name=$1 id=$2 harness=$3 case_dir home proj wt fakebin
  case_dir="$TMP_ROOT/$name"
  home="$case_dir/home"
  proj="$case_dir/project"
  wt="$case_dir/wt"
  fakebin=$(make_attribution_fakebin "$case_dir/fake")
  fm_test_spawn_home "$home" "$harness"
  fm_git_worktree "$proj" "$wt" "wt-$name"
  fm_test_spawn_brief "$home" "$id"
  printf '%s|%s|%s|%s\n' "$home" "$proj" "$wt" "$fakebin"
}

read_case() {
  IFS='|' read -r HOME_DIR PROJ_DIR WT_DIR FAKEBIN <<EOF
$1
EOF
}

test_spawn_arms_the_guard_before_launch() {
  local rec id log out guard_line launch_line
  id=attr-arming-a1
  rec=$(make_case arming "$id" codex)
  read_case "$rec"
  log="$TMP_ROOT/arming/launch.log"
  : > "$log"

  out=$(FM_FAKE_LAUNCH_LOG="$log" \
    fm_test_run_spawn "$HOME_DIR" "$WT_DIR" "$FAKEBIN" \
    "$id" "$PROJ_DIR" --mode no-mistakes --yolo off)
  expect_code 0 $? "spawn failed: $out"

  assert_grep "core.hooksPath" "$log" "the spawn never armed the attribution guard in the pane"
  assert_grep "$HOOKS_DIR" "$log" "the arming did not point at the tracked hooks directory"
  guard_line=$(grep -nF 'GIT_CONFIG_KEY_$fm_guard_gc=core.hooksPath' "$log" | tail -1 | cut -d: -f1)
  launch_line=$(grep -n '^launch: ' "$log" | tail -1 | cut -d: -f1)
  [ -n "$guard_line" ] || fail "no arming line was recorded"
  [ -n "$launch_line" ] || fail "no launch command was recorded"
  [ "$guard_line" -lt "$launch_line" ] ||
    fail "the guard was armed after the launch command, so the worker's first commits are unguarded"
  pass "fm-spawn: the attribution guard is armed in the pane before launch"
}

# The arming must not depend on the harness: a harness with no suppression knob
# of its own is exactly the case layer two exists for.
test_arming_is_harness_independent() {
  local rec id log out harness
  for harness in codex claude; do
    id="attr-any-$harness"
    rec=$(make_case "arming-$harness" "$id" "$harness")
    read_case "$rec"
    log="$TMP_ROOT/arming-$harness/launch.log"
    : > "$log"
    out=$(FM_FAKE_LAUNCH_LOG="$log" \
      fm_test_run_spawn "$HOME_DIR" "$WT_DIR" "$FAKEBIN" \
      "$id" "$PROJ_DIR" --mode no-mistakes --yolo off)
    expect_code 0 $? "spawn on $harness failed: $out"
    assert_grep 'GIT_CONFIG_KEY_$fm_guard_gc=core.hooksPath' "$log" \
      "the $harness spawn did not arm the attribution guard"
  done
  pass "fm-spawn: every harness gets the same arming"
}

# The arming is the only thing that makes layer two reach the worker, so a send
# that never lands must stop the launch rather than produce an unguarded worker.
test_spawn_refuses_when_the_arming_cannot_be_delivered() {
  local rec id log out rc=0
  id=attr-undeliverable-c1
  rec=$(make_case arming-undeliverable "$id" codex)
  read_case "$rec"
  log="$TMP_ROOT/arming-undeliverable/launch.log"
  : > "$log"

  out=$(FM_FAKE_LAUNCH_LOG="$log" FM_FAKE_SEND_FAIL_MATCH='=core.hooksPath' \
    fm_test_run_spawn "$HOME_DIR" "$WT_DIR" "$FAKEBIN" \
    "$id" "$PROJ_DIR" --mode no-mistakes --yolo off 2>&1) || rc=$?
  [ "$rc" -ne 0 ] || fail "the spawn launched a worker although the arming never reached the pane"
  assert_contains "$out" "refusing to launch a worker that could sign the captain's history" \
    "the refusal did not name why the launch was refused"
  grep -q 'core.hooksPath' "$log" && fail "the failed arming was recorded as delivered"
  case "$(tail -n 1 "$log")" in
    "export GOTMPDIR="*) ;;
    *) fail "the spawn kept sending after the arming failed: $(tail -n 1 "$log")" ;;
  esac
  pass "fm-spawn: an undeliverable arming refuses the launch"
}

# config/launch-env-allowlist rewrites the launch as
# `/usr/bin/env -i <retained names> /bin/sh -c '<launch>'`, which silently drops
# every name the retained set does not list. It dropped the guard's arming, so a
# worker launched under that supported feature committed with no hook at all.
# This runs the recorded launch environment for real and commits through it.
test_guard_survives_a_filtered_launch_environment() {
  local rec id log out exports launch prefix repo script rcfile outfile rc
  id=attr-allowlist-d1
  rec=$(make_case arming-allowlist "$id" codex)
  read_case "$rec"
  printf '# nothing but the floor\n' > "$HOME_DIR/config/launch-env-allowlist"
  log="$TMP_ROOT/arming-allowlist/launch.log"
  : > "$log"

  out=$(FM_FAKE_LAUNCH_LOG="$log" \
    fm_test_run_spawn "$HOME_DIR" "$WT_DIR" "$FAKEBIN" \
    "$id" "$PROJ_DIR" --mode no-mistakes --yolo off)
  expect_code 0 $? "spawn under a launch-env allowlist failed: $out"

  exports=$(grep -v '^launch: ' "$log")
  launch=$(sed -n 's/^launch: //p' "$log" | tail -1)
  case "$launch" in
    "/usr/bin/env -i "*) ;;
    *) fail "the allowlist did not filter the launch environment: $launch" ;;
  esac
  prefix=${launch%%/bin/sh -c *}
  [ "$prefix" != "$launch" ] || fail "the filtered launch had no /bin/sh -c payload: $launch"

  # A scratch repository, committed to through the launch environment the spawn
  # actually produced: the exports as the pane shell received them, then the
  # real env filter, then a commit in place of the harness command.
  repo="$TMP_ROOT/arming-allowlist/repo"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email captain@example.com
  git -C "$repo" config user.name Captain
  printf 'seed\n' > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -qm seed || fail "seed commit failed"

  script="$TMP_ROOT/arming-allowlist/commit.sh"
  rcfile="$TMP_ROOT/arming-allowlist/rc"
  outfile="$TMP_ROOT/arming-allowlist/commit.out"
  filtered_commit() {  # <message>; runs one commit inside the filtered launch env
    printf 'work-%s\n' "$RANDOM" > "$repo/a.txt"
    git -C "$repo" add a.txt
    cat > "$script" <<SH
cd $repo || exit 99
git commit -m '$1' > $outfile 2>&1
printf '%s\n' "\$?" > $rcfile
SH
    bash -c "$exports
$prefix /bin/sh $script" || true
    cat "$rcfile"
  }

  rc=$(filtered_commit 'feat: add a

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>')
  [ "$rc" != 0 ] ||
    fail "a worker launched under the allowlist committed agent attribution: $(cat "$outfile")"
  grep -q "no reference to an AI agent" "$outfile" ||
    fail "the commit failed for some other reason than the guard: $(cat "$outfile")"
  [ "$(git -C "$repo" log -1 --format=%s)" = seed ] || fail "the refused commit still landed"

  # The control: the same filtered environment must still commit ordinary work,
  # so the refusal above is the guard rather than a broken launch environment.
  rc=$(filtered_commit 'feat: add a')
  [ "$rc" = 0 ] || fail "the filtered launch environment cannot commit at all: $(cat "$outfile")"
  [ "$(git -C "$repo" log -1 --format=%s)" = "feat: add a" ] ||
    fail "the clean commit did not land under the filtered launch environment"
  pass "fm-spawn: the guard survives a filtered launch environment"
}

test_claude_spawn_suppresses_its_own_byline() {
  local rec id out settings
  id=attr-claude-b1
  rec=$(make_case claude-settings "$id" claude)
  read_case "$rec"

  out=$(fm_test_run_spawn "$HOME_DIR" "$WT_DIR" "$FAKEBIN" \
    "$id" "$PROJ_DIR" --mode no-mistakes --yolo off)
  expect_code 0 $? "spawn failed: $out"

  settings="$WT_DIR/.claude/settings.local.json"
  assert_present "$settings" "the claude spawn wrote no settings file"
  python3 - "$settings" <<'PY' || fail "the claude settings do not switch the byline off"
import json, sys
s = json.load(open(sys.argv[1]))
a = s.get("attribution", {})
assert a.get("commit") == "", a
assert a.get("pr") == "", a
assert a.get("sessionUrl") is False, a
assert s.get("includeCoAuthoredBy") is False, s
assert "hooks" in s, "the busy-state hooks were lost"
PY
  pass "fm-spawn: a claude worker's own commit and PR byline is switched off"
}

test_spawn_arms_the_guard_before_launch
test_arming_is_harness_independent
test_spawn_refuses_when_the_arming_cannot_be_delivered
test_guard_survives_a_filtered_launch_environment
test_claude_spawn_suppresses_its_own_byline
