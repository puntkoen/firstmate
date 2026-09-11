#!/usr/bin/env python3
"""Run a command in a real pty of a given size and print exactly what the pane got.

The overview decides its layout and its colour from the terminal it is drawn in,
so capturing it through a pipe would capture a different program. This hands it a
real terminal of a chosen width, which is what a WezTerm pane is. The size is set
on the pty before the child is started, so the child can never observe a
different one.
"""
import fcntl, os, select, signal, struct, sys, termios, time

cols, rows = int(sys.argv[1]), int(sys.argv[2])
cmd = sys.argv[3:]
master, slave = os.openpty()
fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
pid = os.fork()
if pid == 0:
    os.close(master)
    os.setsid()
    fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
    for target in (0, 1, 2):
        os.dup2(slave, target)
    if slave > 2:
        os.close(slave)
    os.execvp(cmd[0], cmd)
os.close(slave)
# Written through as it arrives, not buffered to the end: a pane left open under
# --watch never ends on its own, so a capture of it has to survive being stopped.
deadline = float(os.environ.get("PTY_CAPTURE_SECONDS", "0")) or None
start = time.monotonic()
while True:
    if deadline is not None and time.monotonic() - start > deadline:
        os.kill(pid, signal.SIGTERM)
        break
    ready, _, _ = select.select([master], [], [], 0.2)
    if not ready:
        continue
    try:
        chunk = os.read(master, 65536)
    except OSError:
        break
    if not chunk:
        break
    sys.stdout.buffer.write(chunk)
    sys.stdout.buffer.flush()
_, status = os.waitpid(pid, 0)
sys.exit(0 if deadline else os.waitstatus_to_exitcode(status))
