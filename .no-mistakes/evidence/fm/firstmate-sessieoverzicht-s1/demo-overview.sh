#!/usr/bin/env bash
# Demo harness for the running-session overview (bin/fm-session-view.sh).
#
# Builds a throwaway firstmate home holding the mix the captain actually has
# open - work in flight for a fortnight, fresh work, work he is deliberately
# holding, abandoned work, open Lavish review pages, background services and a
# real live background session - and then runs the overview against it exactly
# as a captain would from a WezTerm pane.
set -u
ROOT=$1                 # firstmate checkout
DEMO=$2                 # scratch dir
NOW_EPOCH=1788696000    # fixed observation clock: 2026-09-06T12:00:00Z
DAY=86400

HOME_DIR="$DEMO/home"
FAKEBIN="$DEMO/fakebin"
mkdir -p "$HOME_DIR/state" "$HOME_DIR/data" "$HOME_DIR/projects" "$HOME_DIR/config" "$FAKEBIN"

days_ago() { local e=$((NOW_EPOCH - $1 * DAY)); date -u -r "$e" +%Y-%m-%d 2>/dev/null || date -u -d "@$e" +%Y-%m-%d; }

# --- stand-ins for the machine's tools --------------------------------------
for t in no-mistakes node chrome-devtools-axi; do printf '#!/usr/bin/env bash\nexit 0\n' > "$FAKEBIN/$t"; chmod +x "$FAKEBIN/$t"; done
cat > "$FAKEBIN/tmux" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  list-windows) sed -n 's/^window=[^:]*://p' "${FM_HOME:?}"/state/*.meta 2>/dev/null ;;
  display-message) printf '%%1\n' ;;
  capture-pane) printf 'all quiet\n> \n' ;;
esac
exit 0
SH
chmod +x "$FAKEBIN/tmux"
# Lavish's machine-wide review-page listing: two long-open pages, one of them
# holding queued notes, and one opened today.
mkdir -p "$DEMO/pages/bloomandhuda-webshop" "$DEMO/pages/boekhouding" "$DEMO/pages/sqills"
touch_days_ago() { local f=$1 d=$2; printf '<html></html>\n' > "$f"; touch -t "$(date -u -r $((NOW_EPOCH - d * DAY)) +%Y%m%d%H%M 2>/dev/null || date -u -d "@$((NOW_EPOCH - d * DAY))" +%Y%m%d%H%M)" "$f"; }
PLAN="$DEMO/pages/bloomandhuda-webshop/plan.html"; touch_days_ago "$PLAN" 9
STAND="$DEMO/pages/boekhouding/stand.html"; touch_days_ago "$STAND" 4
CHEAT="$DEMO/pages/sqills/cheatsheet.html"; touch_days_ago "$CHEAT" 0
cat > "$FAKEBIN/lavish-axi" <<SH
#!/usr/bin/env bash
[ "\${1:-}" = --version ] && { echo 0.1.46; exit 0; }
printf 'sessions[3]{file,status,url,pending_prompts}:\n'
printf '  $PLAN,open,"http://127.0.0.1:4387/session/7dc7a432",0\n'
printf '  $STAND,feedback,"http://127.0.0.1:4387/session/029eac42",2\n'
printf '  $CHEAT,open,"http://127.0.0.1:4387/session/526c3d41",0\n'
exit 0
SH
chmod +x "$FAKEBIN/lavish-axi"
ln -sf /bin/bash "$FAKEBIN/claude"

# --- the work in flight ------------------------------------------------------
write_worker() {  # <id> <days-old> [suffix]
  local id=$1 days=$2 extra=${3:-}
  mkdir -p "$HOME_DIR/projects/$id-worktree"
  {
    printf 'window=firstmate:fm-%s\n' "$id"
    printf 'worktree=%s/projects/%s-worktree\n' "$HOME_DIR" "$id"
    printf 'project=%s\nharness=claude\nkind=ship\nmode=no-mistakes\nyolo=off\n' alpha
  } > "$HOME_DIR/state/$id.meta"
  printf -- '- [ ] %s - %s (repo: alpha) (kind: ship) (since %s)%s\n' \
    "$id" "$id" "$(days_ago "$days")" "$extra" >> "$DEMO/inflight"
}
: > "$DEMO/inflight"
write_worker webshop-checkout 14
write_worker boekhouding-import 6
write_worker sessie-overzicht 0
write_worker facturen-export 21 ' (hold: wachten op klant) (hold-kind: captain)'
{ printf '## In flight\n'; cat "$DEMO/inflight"; printf '\n## Queued\n\n## Done\n'; } > "$HOME_DIR/data/backlog.md"

# The crew states the close advice is judged on, recorded the ordinary way.
for id in webshop-checkout boekhouding-import sessie-overzicht facturen-export; do
  gen=$("$ROOT/bin/fm-busy-event.sh" arm "$HOME_DIR/state" "$id")
  "$ROOT/bin/fm-busy-event.sh" apply "$HOME_DIR/state" "$id" idle --gen "$gen" --source claude-hook --event stop >/dev/null
done
printf 'done: gate passed, PR merged\n' > "$HOME_DIR/state/boekhouding-import.status"
printf 'blocked: wachten op toegang tot de webshop-API\n' > "$HOME_DIR/state/webshop-checkout.status"

# --- background services this home owns --------------------------------------
mkdir -p "$HOME_DIR/state/.watch.lock" "$HOME_DIR/state/procevent"
sleep 600 & WATCHER=$!; echo "$WATCHER" > "$HOME_DIR/state/.watch.lock/pid"
sleep 600 & LISTENER=$!; echo "$LISTENER" > "$HOME_DIR/state/procevent/pr-review-ready.runner"

# --- one real live background session working in this home -------------------
( cd "$HOME_DIR" && exec "$FAKEBIN/claude" -c 'sleep 600; :' bg-spare --bg-spare /tmp/cc-daemon-501/spare/a.claim.sock ) &
SESSION=$!
sleep 0.6
echo "$SESSION" > "$HOME_DIR/state/.lock"

printf '%s\n' "$WATCHER $LISTENER $SESSION" > "$DEMO/pids"
printf '%s\n' "$HOME_DIR" > "$DEMO/home-path"
printf '%s\n' "$FAKEBIN" > "$DEMO/fakebin-path"
