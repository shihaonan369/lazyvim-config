#!/usr/bin/env python3
"""Exercise the hook's stdin pipe and optional mailbox through real processes."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

HOOK = Path(__file__).resolve().with_name("agent-status-hook.sh")
BASE_ENV = {k: v for k, v in os.environ.items() if not k.startswith("AGENT_")}


def run(env):
    process = subprocess.Popen(
        [str(HOOK), "working"], env=env, stdin=subprocess.PIPE,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    # Larger than pipe capacity: an early exit must fail the writer, as in Codex.
    try:
        process.stdin.write(b"x" * 1048576)
        process.stdin.close()
    except BrokenPipeError:
        process.wait()
        raise AssertionError("hook closed stdin before consuming the event")
    stdout = process.stdout.read()
    stderr = process.stderr.read()
    assert process.wait() == 0, stderr
    assert not stdout and not stderr, (stdout, stderr)


with tempfile.TemporaryDirectory() as directory:
    mailbox = Path(directory) / "events"
    run(BASE_ENV)
    env = dict(BASE_ENV, AGENT_SESSION_TAG="test.1", AGENT_STATUS_FILE=str(mailbox))
    run(env)
    assert json.loads(mailbox.read_text()) == {"tag": "test.1", "state": "working"}
    run(dict(env, AGENT_STATUS_FILE=str(Path(directory) / "missing" / "events")))
    run(dict(env, AGENT_STATUS_FILE=directory))
print("PASS: stdin drained; valid mailbox delivered; absent/unwritable mailbox harmless")
