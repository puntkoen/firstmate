#!/usr/bin/env bash
# End-to-end reproduction of the reported failure and its fix.
#
# A live claude 2.1.259 pane whose composer border carries the session title
# (tests/captures/claude-2.1.259-herdr-0.8.0/titled-composer-border.ansi) is
# served to the REAL herdr backend adapter through the REAL capture primitive
# (`herdr pane read <pane> --source visible --format ansi`), modelled by a
# throwaway herdr CLI stub. Nothing on the host's real fleet is touched: the
# stub is first on PATH, the session name is fake, and the firstmate home is a
# marked disposable lab home.
#
# Each supported recovery route named in the report is then driven twice:
# once against the library at the base commit, once against the branch.
#
# Usage: reproduce-titled-composer-recovery.sh <repo-worktree> <base-commit>
set -u

ROOT=${1:?repo worktree}
BASE=${2:?base commit}
ROOT=$(cd "$ROOT" && pwd)

LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-titled-repro.XXXXXX")
LAB=$(cd "$LAB" && pwd)
SHELL_PID=
cleanup() {
  [ -z "$SHELL_PID" ] || kill "$SHELL_PID" 2>/dev/null || true
  git -C "$LAB/proj" worktree remove --force "$LAB/wt" >/dev/null 2>&1 || true
  chmod -R u+w "$LAB" 2>/dev/null || true
  rm -rf "$LAB"
}
trap cleanup EXIT

mkdir -p "$LAB/fakebin" "$LAB/log" "$LAB/inbox/handled"
cp "$ROOT/tests/captures/claude-2.1.259-herdr-0.8.0/titled-composer-border.ansi" "$LAB/capture.ansi"
ln -sf "$(command -v jq)" "$LAB/fakebin/jq"
printf 'wake up and continue the task\n' > "$LAB/inbox/001.msg"

# A real, long-lived pid so the adapter's process-table descendant walk (which
# proves an agent-free pane) has a shell to anchor on.
sleep 900 >/dev/null 2>&1 &
SHELL_PID=$!
printf '%s' "$SHELL_PID" > "$LAB/shellpid"

# --- the herdr CLI stub: one claude pane, one title-bearing composer rule ----
cat > "$LAB/fakebin/herdr" <<'SH'
#!/usr/bin/env bash
set -u
L=${FM_LAB_DIR:?}
printf '%s\n' "$*" >> "$L/log/herdr.log"
typed=$(cat "$L/typed" 2>/dev/null || true)
shellpid=$(cat "$L/shellpid")
wt="$L/wt"
render() {  # the recorded viewport, with the composer row carrying $typed
  sed -n '1,4p' "$L/capture.ansi"
  if [ -n "$typed" ]; then printf '\xe2\x9d\xaf %s\n' "$typed"; else sed -n '5p' "$L/capture.ansi"; fi
  sed -n '6,$p' "$L/capture.ansi"
}
proc=claude
[ ! -e "$L/agent-gone" ] || proc=zsh
case "${1:-} ${2:-}" in
  "status --json")
    printf '{"client":{"version":"0.8.0","channel":"stable","protocol":22},"server":{"status":"running","running":true,"version":"0.8.0","protocol":22,"compatible":true,"session":"fm-lab"}}\n' ;;
  "pane get")
    printf '{"id":"cli:pane:get","result":{"pane":{"agent":"claude","agent_status":"idle","pane_id":"w1:p2","tab_id":"w1:t2","workspace_id":"w1","cwd":"%s","foreground_cwd":"%s"},"type":"pane_info"}}\n' "$wt" "$wt" ;;
  "agent get")
    printf '{"id":"cli:agent:get","result":{"agent":{"agent":"claude","agent_status":"idle","pane_id":"w1:p2"},"type":"agent_info"}}\n' ;;
  "pane process-info")
    printf '{"id":"cli:pane:process_info","result":{"process_info":{"pane_id":"w1:p2","shell_pid":%s,"foreground_process_group_id":4243,"foreground_processes":[{"pid":4243,"name":"%s","argv0":"%s","argv":["%s"],"cmdline":"%s"}]},"type":"pane_process_info"}}\n' \
      "$shellpid" "$proc" "$proc" "$proc" "$proc" ;;
  "pane read") render ;;
  "pane send-text")
    shift 3
    printf '%s' "${1:-}" > "$L/typed"
    case "${1:-}" in
      *'encode launch-brief'*|*'Firstmate operational input waiting'*|*launch.s*.sh*) rm -f "$L/agent-gone" ;;
    esac ;;
  "pane run")
    shift 3
    case "${1:-}" in *'encode launch-brief'*) rm -f "$L/agent-gone" ;; esac ;;
  "pane send-keys")
    shift 3
    case "${1:-}" in
      enter|Enter)
        case "$typed" in /exit|/quit) : > "$L/agent-gone" ;; esac
        : > "$L/typed" ;;
      ctrl+u) : > "$L/typed" ;;
    esac ;;
esac
exit 0
SH
chmod +x "$LAB/fakebin/herdr"

# --- the library at the base commit, beside the branch's ---------------------
mkdir -p "$LAB/before"
(cd "$ROOT" && tar --exclude=.git -cf - .) | (cd "$LAB/before" && tar -xf -)
git -C "$ROOT" show "$BASE:bin/fm-composer-lib.sh" > "$LAB/before/bin/fm-composer-lib.sh"

# --- a marked disposable lab home holding one claude task on that pane -------
mkdir -p "$LAB/home"
printf 'fm-lab-home v1\n' > "$LAB/home/.fm-lab-home"
mkdir -p "$LAB/home/state" "$LAB/home/data/t1" "$LAB/proj"
cat > "$LAB/home/data/t1/brief.md" <<'EOF'
# Task

## Captain's intent
Keep the lab task moving after its worker fell over.

## Firstmate spec
Resume the recorded work in the local copy and report back.
EOF
git -C "$LAB/proj" init -q
printf '# proj\n' > "$LAB/proj/README.md"
git -C "$LAB/proj" add README.md
git -C "$LAB/proj" -c user.name=Lab -c user.email=lab@example.invalid commit -qm init
git -C "$LAB/proj" worktree add --quiet -b t1 "$LAB/wt"
write_meta() {
  cat > "$LAB/home/state/t1.meta" <<EOF
window=fm-lab:w1:p2
endpoint_task_id=t1
worktree=$LAB/wt
project=$LAB/proj
harness=claude
kind=ship
mode=no-mistakes
yolo=off
model=default
effort=default
backend=herdr
herdr_session=fm-lab
herdr_workspace_id=w1
herdr_tab_id=w1:t2
herdr_pane_id=w1:p2
EOF
}

reset_pane() {  # [draft]
  rm -f "$LAB/typed" "$LAB/agent-gone" "$LAB/home/state/.control-t1.lock"
  rm -f "$LAB/home/state/t1.control-relaunch" 2>/dev/null || true
  [ $# -eq 0 ] || printf '%s' "$1" > "$LAB/typed"
  : > "$LAB/log/herdr.log"
  write_meta
}

run_fm() {  # <before|after> <args...>
  local side=$1; shift
  local r="$ROOT"; [ "$side" = after ] || r="$LAB/before"
  env PATH="$LAB/fakebin:$PATH" FM_LAB_DIR="$LAB" FM_HOME="$LAB/home" \
    FM_CONTROL_POLL=0.05 FM_CONTROL_SETTLE_WAIT=0.05 \
    FM_CONTROL_EXIT_WAIT=3 FM_CONTROL_LAUNCH_WAIT=4 \
    "$r/bin/fm-control.sh" "$@" 2>&1 \
    | grep -v '^fm-gate-refuse:\|^●\|^WARNING\|^warning:'
}

run_doorbell() {  # <before|after>
  local side=$1 r="$ROOT"
  [ "$side" = after ] || r="$LAB/before"
  env PATH="$LAB/fakebin:$PATH" FM_LAB_DIR="$LAB" bash -c '
    . '"$r"'/bin/fm-backend.sh
    . '"$r"'/bin/fm-task-inbox-lib.sh
    fm_task_inbox_ring herdr fm-lab:w1:p2 "'"$LAB"'/inbox/001.msg" fm-t1
    case $? in
      0) echo "doorbell RANG" ;;
      1) echo "doorbell SKIPPED - composer proven to hold unsubmitted text" ;;
      2) echo "doorbell send failed" ;;
      3) echo "doorbell skipped - endpoint dead or missing" ;;
    esac'
}

typed_into_pane() {
  grep 'send-text' "$LAB/log/herdr.log" | sed 's/ --session fm-lab$//;s/^pane send-text w1:p2 /    typed into the pane: /' | cut -c1-110
}

hdr() { printf '\n=== %s ===\n' "$1"; }

printf 'recorded pane: tests/captures/claude-2.1.259-herdr-0.8.0/titled-composer-border.ansi\n'
printf 'base commit:   %s\n' "$BASE"
printf 'branch commit: %s\n' "$(git -C "$ROOT" rev-parse --short HEAD)"

hdr 'what the composer read says about this pane (real herdr adapter, real capture primitive)'
for side in before after; do
  r="$ROOT"; [ "$side" = after ] || r="$LAB/before"
  reset_pane
  env PATH="$LAB/fakebin:$PATH" FM_LAB_DIR="$LAB" bash -c '
    . '"$r"'/bin/fm-backend.sh
    . '"$r"'/bin/fm-composer-lib.sh
    printf "  '"$side"' fix: fm_backend_composer_state herdr fm-lab:w1:p2 -> %s\n" \
      "$(fm_backend_composer_state herdr fm-lab:w1:p2 fm-t1)"
    printf "            the \"unsubmitted text\" it reports: [%s]\n" \
      "$(fm_composer_extract_selected_content "$(printf "styled=1\ncursor=0\nidentity=1")" "$(cat '"$LAB"'/capture.ansi)")"'
done

hdr 'route 1: the steering-inbox doorbell (fm-send / the watcher)'
for side in before after; do
  reset_pane
  printf '  %s fix: %s\n' "$side" "$(run_doorbell "$side")"
  typed_into_pane
done

hdr 'route 2: fm-control exit (the stop half of interrupt-then-steer and of relaunch)'
for side in before after; do
  reset_pane
  printf '  %s fix:\n' "$side"
  run_fm "$side" t1 exit | sed 's/^/    /'
done

hdr 'route 3: fm-control relaunch'
for side in before after; do
  reset_pane
  printf '  %s fix:\n' "$side"
  run_fm "$side" t1 relaunch --note 'the agent fell over on an API failure; resume the task' | sed 's/^/    /'
done

hdr 'the protection is intact: the SAME pane with real typed text still refuses'
reset_pane 'half typed thought'
printf '  after fix, composer holds "half typed thought":\n'
run_fm after t1 exit | sed 's/^/    /'
printf '  after fix, doorbell on the same pane: %s\n' "$(run_doorbell after)"
typed_into_pane
printf '    (no send-text line above means nothing was typed into the held composer)\n'
