#!/usr/bin/env bash
# Replays the captain's 2026-09-20 afternoon on task
# bloomandhuda-kern-en-plugins-bijwerken-u6 through the REAL bin/fm-spawn.sh and
# the REAL bin/fm-watch.sh of one checkout, and prints what the captain would
# actually have seen.
#
#   usage: fm-wedge-scenario.sh <repo-root> <label>
#
# Only the tmux pane and the crew-state probe are faked; the spawn, the hook
# commands it installs, the busy-state writer, the watcher, and the durable wake
# queue are the production ones from <repo-root>.
set -u
REPO=$1
LABEL=$2

. "$REPO/tests/fixtures.sh"
. "$REPO/tests/wake-helpers.sh"

TMP_ROOT=$(fm_test_tmproot "fm-wedge-scenario-$LABEL")
WATCH="$REPO/bin/fm-watch.sh"
DRAIN="$REPO/bin/fm-wake-drain.sh"
ID=bloomandhuda-kern-en-plugins-bijwerken-u6
PANE_TEXT='> docker exec bloomandhuda-wp wp plugin update woocommerce --path=/var/www/html
  Downloading update from https://downloads.wordpress.org/plugin/woocommerce.zip ...
  Unpacking the update ...
* Updating... (esc to interrupt)'

set_mtime() {  # <epoch> <file>
  local stamp
  stamp=$(date -r "$1" +%Y%m%d%H%M.%S 2>/dev/null) || stamp=$(date -d "@$1" +%Y%m%d%H%M.%S)
  touch -t "$stamp" "$2"
}
hook_cmd() {  # <settings> <event>
  jq -r ".hooks[\"$2\"][0].hooks[0].command // empty" "$1"
}
fire_hook() {  # <settings> <event>
  local cmd; cmd=$(hook_cmd "$1" "$2"); [ -n "$cmd" ] || return 1; sh -c "$cmd"
}
ack() {  # <state>
  local err seq gen
  err="$1/.ack.err"
  FM_STATE_OVERRIDE="$1" "$DRAIN" >/dev/null 2>"$err" || true
  seq=$(sed -n 's/^WAKE_ACK_REQUIRED:.*--ack-through \([0-9][0-9]*\) --recovery-generation [A-Za-z0-9._-][A-Za-z0-9._-]*$/\1/p' "$err")
  gen=$(sed -n 's/^WAKE_ACK_REQUIRED:.*--ack-through [0-9][0-9]* --recovery-generation \([A-Za-z0-9._-][A-Za-z0-9._-]*\)$/\1/p' "$err")
  rm -f "$err"
  [ -n "$seq" ] && [ -n "$gen" ] || return 0
  FM_STATE_OVERRIDE="$1" "$DRAIN" --ack-through "$seq" --recovery-generation "$gen" >/dev/null
}

# --- 1. a real spawn -------------------------------------------------------
LAB="$TMP_ROOT/lab"; HOME_DIR="$LAB/home"; PROJ="$LAB/project"; WT="$LAB/wt"
mkdir -p "$LAB"
SPAWN_FAKEBIN=$(make_spawn_fakebin "$LAB/fake" claude)
fm_test_spawn_home "$HOME_DIR" claude
fm_git_worktree "$PROJ" "$WT" wt-bloomandhuda
fm_test_spawn_brief "$HOME_DIR" "$ID" 'WordPress-kern en plugins bijwerken'
SPAWN_OUT=$(fm_test_run_spawn "$HOME_DIR" "$WT" "$SPAWN_FAKEBIN" "$ID" "$PROJ" --mode no-mistakes --yolo off) \
  || { printf 'spawn failed: %s\n' "$SPAWN_OUT"; exit 1; }
STATE="$HOME_DIR/state"
SETTINGS="$WT/.claude/settings.local.json"
WINDOW=$(sed -n 's/^window=//p' "$STATE/$ID.meta")
KEY=$(printf '%s' "$WINDOW" | tr ':/.' '___')

printf '=== [%s] 1. Wat fm-spawn in de Claude-worktree installeert ===\n' "$LABEL"
printf 'hook-events in %s:\n' ".claude/settings.local.json"
jq -r '.hooks | keys[]' "$SETTINGS" | sed 's/^/  - /'
if jq -e '.hooks.PreToolUse' "$SETTINGS" >/dev/null 2>&1; then
  printf '  PreToolUse matcher : %s\n' "$(jq -r '.hooks.PreToolUse[0].matcher' "$SETTINGS")"
  printf '  PreToolUse command : %s\n' "$(hook_cmd "$SETTINGS" PreToolUse | sed "s#$REPO#<repo>#g; s#$STATE#<state>#g")"
else
  printf '  (geen tool-grens-hook: de bewaking krijgt binnen een turn geen enkel activiteitssignaal)\n'
fi
printf '\n'

# --- 2. the crew's afternoon ----------------------------------------------
CASE=$(make_case "watch-$LABEL")
WFAKEBIN="$CASE/fakebin"
PANE="$CASE/pane.txt"
printf '%s' "$PANE_TEXT" > "$PANE"
printf '%s' "$(hash_text "$PANE_TEXT")" > "$STATE/.hash-$KEY"
printf '1\n' > "$STATE/.count-$KEY"
printf 'working: plugins een voor een bijwerken\n' > "$STATE/$ID.status"
prime_status_seen "$STATE" "$STATE/$ID.status"
fire_hook "$SETTINGS" UserPromptSubmit >/dev/null 2>&1 || true
# One unbroken turn since the crew started, five hours ago: nothing has ever
# ended a turn, which is exactly how an autonomous crewmate works.
set_mtime "$(( $(date +%s) - 18000 ))" "$STATE/$ID.meta"

run_watch() {  # <out>
  local out=$1 pid i=0
  : > "$out"
  PATH="$WFAKEBIN:$PATH" FM_FAKE_TMUX_WINDOW="$WINDOW" FM_FAKE_TMUX_CAPTURE="$PANE" \
    FM_STATE_OVERRIDE="$STATE" FM_BUSY_TURN_MAX_SECS=3600 FM_STALE_ESCALATE_SECS=240 \
    FM_POLL=1 FM_SIGNAL_GRACE=1 FM_CHECK_INTERVAL=999999 FM_HEARTBEAT=999999 "$WATCH" > "$out" &
  pid=$!
  while [ "$i" -lt 60 ]; do
    kill -0 "$pid" 2>/dev/null || { wait "$pid" 2>/dev/null; return 0; }
    sleep 0.1; i=$((i + 1))
  done
  kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true
  return 1
}

report_round() {  # <label> <out> <exited>
  local what=$1 out=$2 exited=$3
  if [ "$exited" = 0 ] && [ -s "$out" ]; then
    printf '  %-34s WAKKER GEMAAKT -> %s\n' "$what" "$(grep -m1 . "$out")"
  else
    printf '  %-34s (stil: geen melding, geen wake-rij' "$what"
    [ -e "$STATE/.stale-since-$KEY" ] && printf ', maar wel op de wedge-timer' || printf ', geen wedge-timer'
    printf ')\n'
  fi
  # Every round stops an owned watcher on purpose; consume the downtime-recovery
  # handshake so the NEXT round is not woken by this test's own restart.
  ack "$STATE"
}

printf '=== [%s] 2. Vijf polls terwijl de werker gewoon bezig is ===\n' "$LABEL"
printf 'pane toont een lopende docker/wp plugin-update; turn staat 5 uur open; geen afgeronde turn.\n'
n=1
while [ "$n" -le 5 ]; do
  if [ -n "$(hook_cmd "$SETTINGS" PostToolUse)" ]; then
    # The plugin command of this round just finished: the real PostToolUse hook
    # command runs, and the boundary is then 1500s (25 min) old.
    fire_hook "$SETTINGS" PostToolUse >/dev/null 2>&1 || true
    set_mtime "$(( $(date +%s) - 1500 ))" "$STATE/$ID.progress"
    desc="ronde $n (laatste tool-grens 1500s)"
  else
    desc="ronde $n (geen tool-grens bekend)"
  fi
  # 240s wedge-cadence has elapsed for a pane that is already on the timer.
  [ -e "$STATE/.stale-since-$KEY" ] && echo $(( $(date +%s) - 500 )) > "$STATE/.stale-since-$KEY"
  OUT="$CASE/round-$n.out"
  if run_watch "$OUT"; then report_round "$desc" "$OUT" 0; else report_round "$desc" "$OUT" 1; fi
  # first sighting past the bound only arms the timer; make the next poll due
  [ -e "$STATE/.stale-since-$KEY" ] && echo $(( $(date +%s) - 500 )) > "$STATE/.stale-since-$KEY"
  n=$((n + 1))
done
printf '\n'

printf '=== [%s] 3. Ronde 6: de stroom valt uit, de werker verliest zijn verbinding ===\n' "$LABEL"
if [ -e "$STATE/$ID.progress" ]; then
  set_mtime "$(( $(date +%s) - 7200 ))" "$STATE/$ID.progress"
fi
echo $(( $(date +%s) - 500 )) > "$STATE/.stale-since-$KEY"
OUT="$CASE/round-6.out"
if run_watch "$OUT"; then
  printf '  %-34s WAKKER GEMAAKT -> %s\n' "echte storing" "$(grep -m1 . "$OUT")"
  printf '\n  durabele wake-rij die de kapitein binnenkrijgt:\n'
  FM_STATE_OVERRIDE="$STATE" "$DRAIN" 2>/dev/null | grep "$(printf '\tstale\t')" | sed 's/^/    /'
  ack "$STATE"
else
  printf '  %-34s (stil)\n' "echte storing"
fi
printf '\n'
