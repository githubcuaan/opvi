"""Drain OpenCode CLI output without its early-exit pipe truncation.

The CLI writes synchronously to a regular file, then Python relays the complete
response to Neovim and flushes before exiting. TemporaryFile is private and
unlinked on Unix; session content is never left in a named output file.
"""
import os
import shutil
import signal
import subprocess
import sys
import tempfile


def main():
    with tempfile.TemporaryFile() as output:
        child = subprocess.Popen(sys.argv[1:], stdout=output, start_new_session=True)
        canceled = 0

        def cancel(signum, _frame):
            nonlocal canceled
            canceled = signum
            # Kill the whole command group, including custom wrapper children.
            # A separately daemonized OpenCode service is not in this group.
            try:
                os.killpg(child.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            # Never call wait() inside a signal handler: the main thread may
            # already hold Popen's waitpid lock. Its wait below reaps the child.

        signal.signal(signal.SIGTERM, cancel)
        signal.signal(signal.SIGINT, cancel)
        try:
            code = child.wait()
            if canceled:
                return 128 + canceled
            output.seek(0)
            shutil.copyfileobj(output, sys.stdout.buffer)
            sys.stdout.buffer.flush()
            return code if code >= 0 else 128 - code
        finally:
            if child.poll() is None:
                cancel(signal.SIGTERM, None)
                child.wait()


if __name__ == '__main__':
    sys.exit(main())
