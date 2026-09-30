"""Isolated live test. Deletes only the conversation created by this run."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import uuid

root = Path(__file__).resolve().parent.parent
socket = "opvi-test-" + uuid.uuid4().hex
env = dict(os.environ, OPVI_LIVE_TEST="1")
tmux = ["tmux", "-L", socket]
name = "opencode-opvi-test"
with tempfile.TemporaryDirectory(prefix="opvi-live-", dir="/tmp/opencode") as directory:
    result = Path(directory) / "result"
    log = Path(directory) / "log"
    # Keep the tmux session alive after Neovim exits so cleanup can read its binding.
    script = Path(directory) / "run.sh"
    script.write_text(f'#!/bin/sh\nnvim --headless -u NONE -l tests/e2e.lua >"{log}" 2>&1\necho $? >"{result}"\nexec sleep 180\n')
    code = 1
    try:
        subprocess.run(tmux + ["-f", "/dev/null", "new-session", "-d", "-s", name, "-c", str(root), "sh", str(script)],
                       check=True, env=env)
        deadline = time.monotonic() + 180
        while not result.exists() and time.monotonic() < deadline:
            time.sleep(0.1)
        if log.exists():
            print(log.read_text())
        if result.exists():
            code = int(result.read_text().strip())
        else:
            print("Live test timed out", file=sys.stderr)
    finally:
        binding = subprocess.run(tmux + ["show-option", "-qv", "-t", name, "@opencode_session_id"], capture_output=True, text=True)
        session = binding.stdout.strip()
        if session.startswith("ses_"):
            for method, endpoint in [("post", f"/api/session/{session}/interrupt"), ("delete", f"/api/session/{session}")]:
                cleanup = subprocess.run(["opencode", "api", method, endpoint], capture_output=True, text=True, timeout=20)
                if cleanup.returncode:
                    print(f"Cleanup failed for {session}: {cleanup.stderr}", file=sys.stderr)
                    code = 1
        subprocess.run(tmux + ["kill-server"], capture_output=True)
    sys.exit(code)
