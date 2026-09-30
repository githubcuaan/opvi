"""Hold an advisory lock until the owner's stdin closes (also on owner crash)."""
import fcntl
import os
import select
import sys
import time

path, timeout = sys.argv[1], float(sys.argv[2])
deadline = time.monotonic() + timeout
with open(path, "a") as lock:
    while True:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            break
        except BlockingIOError:
            if time.monotonic() >= deadline:
                sys.exit("Timed out waiting for Opvi session lock")
            if select.select([sys.stdin], [], [], 0.05)[0] and not os.read(0, 1):
                sys.exit(0)
    print("locked", flush=True)
    sys.stdin.read()
