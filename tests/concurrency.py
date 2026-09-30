"""Two actual Neovim processes, different cwd, same real tmux target."""
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import time
import uuid

root = Path(__file__).resolve().parent.parent
tmux = ["tmux", "-L", "opvi-concurrent-" + uuid.uuid4().hex]
with tempfile.TemporaryDirectory(prefix="opvi-concurrent-", dir="/tmp/opencode") as directory:
    state = Path(directory)
    env = dict(os.environ, OPVI_TEST_ROOT=str(root), OPVI_TEST_STATE=directory)
    try:
        subprocess.run(tmux + ["-f", "/dev/null", "new-session", "-d", "-s", "opencode-test", "sleep", "30"], env=env, check=True)
        for index, cwd in enumerate([root, root / "lua"]):
            script = state / f"worker{index}.sh"
            script.write_text(f'#!/bin/sh\nnvim --headless -u NONE -l {shlex.quote(str(root / "tests/concurrent.lua"))} >"{state / str(index)}.log" 2>&1\necho $? >"{state / str(index)}.exit"\n')
            subprocess.run(tmux + ["new-window", "-d", "-t", "opencode-test", "-c", str(cwd), "sh", str(script)], check=True)
        deadline = time.monotonic() + 15
        while not all((state / f"{i}.exit").exists() for i in range(2)) and time.monotonic() < deadline:
            time.sleep(0.05)
        for i in range(2):
            log = (state / f"{i}.log").read_text()
            print(log)
            assert (state / f"{i}.exit").read_text().strip() == "0", log
        assert (state / "creates").read_text().splitlines() == ["created"], "Created more than one session"
        print("PASS two Neovim processes share exactly one conversation")
    finally:
        subprocess.run(tmux + ["kill-server"], capture_output=True)
