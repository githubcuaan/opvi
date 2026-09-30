"""Deterministic CLI fixture for multi-Neovim connection tests; no network."""
import json
from pathlib import Path
import sys
import time

directory, method, path = sys.argv[1:4]
state = Path(directory) / "creates"
if method == "post" and path == "/api/session":
    # Deliberately slow: without Opvi's cross-process lock both clients create.
    with state.open("a") as stream:
        stream.write("created\n")
    time.sleep(0.3)
    print(json.dumps({"data": {"id": "ses_fixture"}}))
elif path == "/api/info":
    print(json.dumps({"version": "2.fixture"}))
elif path == "/api/session/ses_fixture":
    print(json.dumps({"data": {"id": "ses_fixture", "location": {"directory": directory}}}))
else:
    sys.exit("Unexpected fixture request: " + method + " " + path)
