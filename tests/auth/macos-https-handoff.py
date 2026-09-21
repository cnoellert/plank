#!/usr/bin/env python3
"""Real loopback TLS socket ownership: root -> desktop -> root -> desktop.

Run only on a disposable Mac builder or an explicitly authorized test Mac.
Root is needed only to launch fixture children as two UIDs; no accounts, jobs,
trust settings, sysctls, production listeners or graphical sessions are changed.
"""
import argparse
import importlib.util
import os
from pathlib import Path
import re
import select
import socket
import subprocess
import tempfile
import time

spec = importlib.util.spec_from_file_location("https_fixture", Path(__file__).with_name("macos-https-auth.py"))
https = importlib.util.module_from_spec(spec)
spec.loader.exec_module(https)


def ready(process, timeout=3):
    if not select.select([process.stdout], [], [], timeout)[0]:
        raise AssertionError("handoff listener readiness exceeded three seconds")
    line = process.stdout.readline()
    match = re.fullmatch(rb"macos_https_auth_ready port=(\d+) desktop_active=1\n", line)
    assert match, "handoff listener failed to bind after old worker exit"
    return int(match[1])


def stop(process):
    if process.poll() is None:
        process.terminate()
    try:
        process.communicate(timeout=3)
    except subprocess.TimeoutExpired:
        process.kill()
        process.communicate(timeout=3)
        raise AssertionError("HTTPS worker did not drain within three seconds")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--server", type=Path, required=True)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--uid", type=int, required=True)
    parser.add_argument("--gid", type=int, required=True)
    args = parser.parse_args()
    assert os.geteuid() == 0 and args.uid > 0 and args.gid > 0
    with tempfile.TemporaryDirectory(prefix="plank-https-handoff-") as temporary:
        certificate = https.create_identity(temporary, args.config)
        # Fixture credentials only. Each tested UID can read the same ephemeral
        # identity without making any private key world-readable.
        for path in [Path(temporary), *Path(temporary).iterdir()]:
            os.chown(path, args.uid, args.gid)
        processes = []
        held = []
        port = 0

        def start(uid, requested):
            process = subprocess.Popen([str(args.server), temporary],
                env={**os.environ, "PLANK_TEST_LISTEN_PORT": str(requested)},
                user=uid, group=args.gid if uid else 0, extra_groups=[],
                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            processes.append(process)
            return process

        try:
            # Multiple real cross-UID rebinds, without sleeps/retry-until-green.
            for uid in [0, args.uid, 0, args.uid]:
                began = time.monotonic()
                server = start(uid, port)
                assigned = ready(server)
                assert not port or assigned == port
                port = assigned
                assert time.monotonic() - began < 3
                https.discovery(certificate, port)
                # A second listener must fail even for the same UID. This gate
                # rejects a blanket SO_REUSEPORT workaround.
                competitor = start(uid, port)
                output, _ = competitor.communicate(timeout=3)
                assert competitor.returncode == 2 and b"ready" not in output
                # Pending TLS and incomplete HTTP must not leave lingering
                # sockets during retirement, nor wait for the admission timer.
                held.append(socket.create_connection(("127.0.0.1", port), timeout=2))
                stop(server)
                assert server.returncode == 0
                for connection in held:
                    connection.close()
                held.clear()
            print("macos_https_cross_uid_handoff=pass transitions=3 exclusive_listener=1 max_ready_seconds=3")
        finally:
            for connection in held:
                connection.close()
            for process in processes:
                stop(process)


if __name__ == "__main__":
    main()
