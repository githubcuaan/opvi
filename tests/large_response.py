"""Reproduce a CLI exiting successfully with a partially drained stdout pipe."""
import json
import os

payload = json.dumps({"data": {"text": "á🙂" * 100000, "complete": True}}, ensure_ascii=False).encode()
os.set_blocking(1, False)
# Deterministically exceed pipe capacity. With a regular stdout file, the full
# payload is written. With a pipe, queued output is lost on this early exit.
while payload:
    try:
        written = os.write(1, payload)
        payload = payload[written:]
    except BlockingIOError:
        break
os._exit(0)
