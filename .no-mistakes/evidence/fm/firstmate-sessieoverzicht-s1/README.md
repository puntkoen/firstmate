# Running-session overview - evidence

The captain asked to see, at a glance in WezTerm, what is running, and to be able
to close old things easily - plus a short notice when something has been running
longer than three days.

Everything below was produced against a throwaway firstmate home (`demo-overview.sh`)
holding the mix he actually has open: work in flight for 21, 14 and 6 days, fresh
work, work he is deliberately holding, three Lavish review pages, the background
services, and a real live background session claimed for that home. The observation
clock is pinned to 2026-09-06T12:00:00Z so the ages are stable.

Every pane was captured through a real pty of the stated width (`pty-capture.py`),
so the colours and the column layout are the ones the program emitted, not a
reconstruction; `ansi2html.py` re-renders those exact bytes, wrapping at the same
column count the pane does.

| Artifact | What it shows |
|---|---|
| `01-overview-wide.png` | `bin/fm-session-view.sh` in a 110-column pane: workers, the live background session, review pages and services in one table, `!` on everything past three days, and a pasteable close command for every row that has one. |
| `02-overview-narrow.png` | The same overview in a 46-column side pane. `BELONGS TO` and `TASK` are dropped, the table still fits, and the close commands wrap whole rather than being cut off. |
| `03-overview-stale-only.png` | `--stale-only`: just the five things over three days, and just their close commands. |
| `06-watch-closes-live.gif` | `--watch --interval 15` in a pane left open. Between redraws the listener is closed with the command the pane itself printed; the next redraw drops the row and goes from 12 running to 11, with nothing re-run by hand. |
| `05-close-from-the-overview.txt` | The close half end to end: the printed command, pasted verbatim, retires the listener, and the row is gone from the next render. |
| `07-session-start-notification.png` | What a session start says unasked: four short lines, no report. The 21-day item is deliberately held by the captain, so it stays in the overview and out of the notice. With nothing over the threshold, the notice says nothing at all. |
| `08-live-harness-drift-guard.txt` | The one judgement that depends on real vendor behaviour, checked against the harnesses actually installed here (Claude Code 2.1.236, Codex 0.147.0) and against the captain's own live home: every harness process under its lock-owning harness accounted for. |

`04-overview-watch.ansi.txt` and `06-watch-live.ansi.txt` are the raw pty captures
behind the watch frames; `split-frames.py` cuts them at the redraw boundary.
