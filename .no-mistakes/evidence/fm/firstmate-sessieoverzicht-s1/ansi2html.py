#!/usr/bin/env python3
"""Render captured terminal bytes as the pane that produced them.

Input is the raw pty capture, so the colours, the bold header and the red "!"
markers are the ones the program actually emitted. Only the SGR codes this
renderer uses are translated (bold, dim, red, reset); anything else is dropped
rather than guessed at.
"""
import html, re, sys

SGR = re.compile(r"\x1b\[([0-9;]*)m")
STYLE = {"1": "font-weight:700;color:#f5f5f2", "2": "color:#8a8f98", "31": "color:#ff6b6b;font-weight:700"}

def render(text):
    out, open_spans = [], 0
    pos = 0
    for m in SGR.finditer(text):
        out.append(html.escape(text[pos:m.start()]))
        pos = m.end()
        code = m.group(1) or "0"
        if code in ("0", ""):
            out.append("</span>" * open_spans)
            open_spans = 0
        elif code in STYLE:
            out.append(f'<span style="{STYLE[code]}">')
            open_spans += 1
    out.append(html.escape(text[pos:]))
    out.append("</span>" * open_spans)
    return "".join(out)

def wrap_like_a_terminal(text, cols):
    """Break lines at the column count, the way the pane they came from does.

    The overview leaves close commands and home paths whole on purpose and lets
    the terminal wrap them, so a renderer that lets them run off the edge is
    showing a pane nobody has. Only visible characters are counted; the SGR
    state in force at a break is reopened on the next row."""
    out = []
    for line in text.split("\n"):
        line = SGR.sub(lambda m: m.group(0), line).rstrip()
        row, visible, active = "", 0, []
        pos = 0
        for m in list(SGR.finditer(line)) + [None]:
            chunk = line[pos:(m.start() if m else len(line))]
            for ch in chunk:
                if visible == cols:
                    out.append(row + "\x1b[0m")
                    row, visible = "".join(active), 0
                row += ch
                visible += 1
            if m:
                row += m.group(0)
                code = m.group(1) or "0"
                if code in ("0", ""):
                    active = []
                else:
                    active.append(m.group(0))
                pos = m.end()
        out.append(row)
    return "\n".join(out)


title, cols, src, dst = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
raw = open(src, encoding="utf-8", errors="replace").read().replace("\r\n", "\n").replace("\r", "")
raw = re.sub(r"\x1b\[[0-9;]*[HJ]", "", raw)
body = render(wrap_like_a_terminal(raw.rstrip("\n"), cols))
open(dst, "w").write(f"""<!doctype html><meta charset="utf-8">
<style>
 body {{ margin:0; background:#12141a; font-family:"SF Mono","JetBrains Mono",Menlo,monospace; }}
 .pane {{ width:{cols}ch; margin:0; background:#1b1e26; border-radius:10px; overflow:hidden;
          box-shadow:0 18px 50px rgba(0,0,0,.55); }}
 .bar {{ background:#2a2e38; color:#cdd3de; font-size:12px; padding:7px 12px; letter-spacing:.02em; }}
 .bar b {{ color:#fff; font-weight:600; }}
 pre {{ margin:0; padding:14px 16px; color:#d7dbe3; font-size:13px; line-height:1.45;
        white-space:pre; overflow:visible; }}
</style>
<div style="display:inline-block;padding:26px">
<div class="pane"><div class="bar"><b>WezTerm</b> — {html.escape(title)} — {cols} cols</div>
<pre>{body}</pre></div></div>
""")
