#!/usr/bin/env bash
# End-to-end reproduction of task firstmate-doorbell-vals-pending-p1.
#
# It drives the REAL doorbell decision point - fm_task_inbox_ring() in
# bin/fm-task-inbox-lib.sh, the function bin/fm-send.sh calls and whose
# return code 1 produces the captain-facing
#   "fm-send: doorbell skipped (composer visibly holds pending text)"
# - against a cursorless backend (zellij, the same cursor=0/styled=1/identity=0
# read herdr, cmux and orca perform) whose pane renders the shape captured live
# on 2026-09-20 from claude 2.1.236: a `❯`+NBSP composer between two solid
# rules, with this home's statusLine (leading with `→`) and claude's
# permission-mode hint drawn on the two rows BELOW the closing rule.
#
# The pane is a real, writable terminal model: `zellij action paste` types into
# the composer row, `send-keys Enter` submits it, and what the worker actually
# receives is printed at the end. Run with `base` to load the pre-fix composer
# library from git and see the same steer refused.
set -u

ROOT=${FM_ROOT:?set FM_ROOT to the firstmate worktree}
MODE=${1:-fixed}       # fixed | base
SCREEN=${2:-idle}      # idle | typed
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-doorbell-e2e.XXXXXX")
trap 'rm -rf "$LAB"' EXIT

NBSP=$' '
SESSION=fmzell
PANE=2

# ---- the live-captured worker pane ----------------------------------------
composer_row="❯$NBSP"
[ "$SCREEN" = typed ] && composer_row='❯ fix the login bug'
# The second, separate live case of 2026-09-20: a stray SGR mouse report left
# in the composer by a click in the pane. That IS content, and must keep
# refusing after the fix.
[ "$SCREEN" = mouse ] && composer_row='❯ <65;77;27M'
if [ "$SCREEN" = box ]; then
  # The other shape claude 2.x draws (a wide pane): the same composer inside a
  # rounded border, with the same statusLine + mode hint footer under it.
  inner_w=58
  rule=$(printf '─%.0s' $(seq "$inner_w"))
  pad=$((inner_w - 1 - ${#composer_row}))
  printf '%s\n' \
    '> think about de galerij indeling' \
    "  I'll restructure the gallery grid and relink the thumbnails." \
    "╭${rule}╮" \
    "│ $composer_row$(printf '%*s' "$pad" '')│" \
    "╰${rule}╯" \
    '  → bloomandhuda26 git:(g4)× | Opus 5 (1M context) | ctx [█░░░░░░] 15%' \
    '  ⏵⏵ bypass permissions on (shift+tab to cycle)' >"$LAB/pane.txt"
else
cat >"$LAB/pane.txt" <<EOF
> think about the galerij indeling
  I'll restructure the gallery grid and relink the thumbnails.
────────────────────────────────────────────────────────────
$composer_row
────────────────────────────────────────────────────────────
  → bloomandhuda26 git:(g4)× | Opus 5 (1M context) | ctx [█░░░░░░] 15%
  ⏵⏵ bypass permissions on (shift+tab to cycle)
EOF
fi
: >"$LAB/delivered.txt"

# ---- a fake zellij CLI: a writable pane, not a canned answer ---------------
mkdir -p "$LAB/bin"
cat >"$LAB/bin/zellij" <<'FAKE'
#!/usr/bin/env bash
set -u
LAB=$FM_DOORBELL_LAB
args=("$@")
sub=""
for i in "${!args[@]}"; do
  case "${args[$i]}" in
    list-sessions) printf '%s\n' "$FM_DOORBELL_SESSION"; exit 0 ;;
    action) sub=${args[$((i+1))]:-}; break ;;
  esac
done
case "$sub" in
  list-panes) printf '[{"id":%s,"is_plugin":false}]\n' "$FM_DOORBELL_PANE"; exit 0 ;;
  dump-screen) cat "$LAB/pane.txt"; exit 0 ;;
  paste)
    text=${args[$(( ${#args[@]} - 1 ))]}
    printf '%s\n' "PASTE $text" >>"$LAB/keys.log"
    awk -v t="$text" '
      /^❯/ && !done { sub(/\xc2\xa0$/, ""); printf "%s%s\n", $0, t; done=1; next }
      { print }
    ' "$LAB/pane.txt" >"$LAB/pane.new" && mv "$LAB/pane.new" "$LAB/pane.txt"
    exit 0 ;;
  send-keys)
    key=${args[$(( ${#args[@]} - 1 ))]}
    printf '%s\n' "KEY $key" >>"$LAB/keys.log"
    if [ "$key" = Enter ]; then
      grep '^❯' "$LAB/pane.txt" | sed 's/^❯[[:space:]\xc2\xa0]*//' \
        | grep '[^[:space:]]' >>"$LAB/delivered.txt" || true
      awk -v empty="$(printf '❯ ')" '/^❯/ && !done { print empty; done=1; next } { print }' \
        "$LAB/pane.txt" >"$LAB/pane.new" && mv "$LAB/pane.new" "$LAB/pane.txt"
    fi
    exit 0 ;;
esac
exit 0
FAKE
chmod +x "$LAB/bin/zellij"
export FM_DOORBELL_LAB=$LAB FM_DOORBELL_SESSION=$SESSION FM_DOORBELL_PANE=$PANE
export PATH="$LAB/bin:$PATH"

# ---- the captain's steer, durably recorded the way fm-send records it ------
mkdir -p "$LAB/state/inbox/bloomandhuda-galerij-indeling-en-links-g4/handled"
REC=$LAB/state/inbox/bloomandhuda-galerij-indeling-en-links-g4/0001.msg
cat >"$REC" <<'EOF'
from=captain
--
Neem de galerij-indeling terug naar drie kolommen en herstel de links.
EOF

# shellcheck source=/dev/null
. "$ROOT/bin/fm-backend.sh"
# shellcheck source=/dev/null
. "$ROOT/bin/fm-task-inbox-lib.sh"
fm_backend_source zellij
if [ "$MODE" = base ]; then
  # Load the PRE-FIX classifier over the fixed one: same adapters, same pane,
  # only the shape owner changes.
  eval "$(git -C "$ROOT" show "${FM_BASE_COMMIT:-631bc26d}:bin/fm-composer-lib.sh")"
fi

echo "=== pane the worker is showing (composer row is between the two rules) ==="
cat "$LAB/pane.txt"
echo
verdict=$(fm_backend_composer_state zellij "$SESSION:$PANE" 2>/dev/null)
echo "composer verdict for this pane (library: $MODE) : $verdict"
echo

if [ "${FM_DOORBELL_VERDICT_ONLY:-0}" = 1 ]; then
  echo "(verdict-only run: that verdict IS the doorbell gate - fm_task_inbox_ring"
  echo " defers on exactly \`pending\` and rings on anything else.)"
  exit 0
fi

rc=0
fm_task_inbox_ring zellij "$SESSION:$PANE" "$REC" || rc=$?
case "$rc" in
  0) echo "fm-send: doorbell rang" ;;
  1) echo "fm-send: doorbell skipped (composer visibly holds pending text); the steer is durably recorded at $REC and the watcher will re-ring" ;;
  2) echo "fm-send: doorbell did not reach $SESSION:$PANE" ;;
  3) echo "fm-send: doorbell not typed because the agent has exited" ;;
esac
echo
echo "=== what the worker actually received (submitted lines) ==="
if [ -s "$LAB/delivered.txt" ]; then
  cat "$LAB/delivered.txt"
else
  echo "(nothing - the captain's instruction never reached the worker)"
fi
echo
echo "=== pane after the doorbell attempt ==="
cat "$LAB/pane.txt"
exit "$rc"
