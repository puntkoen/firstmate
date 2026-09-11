#!/usr/bin/env python3
"""Split a --watch capture into the frames the pane actually showed.

Each redraw is preceded by cursor-home + erase-display, which is the boundary
the pane itself uses, so the frames here are the ones a captain saw."""
import os, re, sys
src, outdir, prefix = sys.argv[1], sys.argv[2], sys.argv[3]
raw = open(src, encoding="utf-8", errors="replace").read()
frames = [f for f in re.split(r"\x1b\[H\x1b\[2J", raw) if f.strip()]
os.makedirs(outdir, exist_ok=True)
for i, frame in enumerate(frames, 1):
    open(os.path.join(outdir, f"{prefix}{i}.ansi.txt"), "w").write(frame)
print(len(frames))
