#!/usr/bin/env python3
"""Real loopback HTTPS, synthetic account/display; no operator secrets or GUI."""
import importlib.util
import os
from pathlib import Path
import re
import select
import subprocess
import sys
import tempfile

spec = importlib.util.spec_from_file_location("auth_test", Path(__file__).with_name("macos-https-auth.py"))
auth = importlib.util.module_from_spec(spec)
spec.loader.exec_module(auth)


def run(executable, config, mode):
    with tempfile.TemporaryDirectory(prefix="plank-recovery-test-") as temporary:
        cert = auth.create_identity(temporary, config)
        process = subprocess.Popen([str(executable), temporary], stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, text=True,
                                   env=dict(os.environ, PLANK_TEST_RECOVERY=mode))
        try:
            assert select.select([process.stdout], [], [], 10)[0], "listener timeout"
            match = re.fullmatch(r"macos_https_auth_ready port=(\d+) desktop_active=1\n", process.stdout.readline())
            assert match, "listener not ready"
            port = int(match[1])
            tls = auth.context(cert)
            auth.discovery(tls, port)
            assert not select.select([process.stdout], [], [], .1)[0], "unauthenticated recovery"
            status, challenge = auth.request(tls, port, {"username": "synthetic"})
            assert status == 200
            status, result = auth.request(tls, port, {"conversation_id": challenge["conversation_id"],
                                         "responses": ["test"]}, "/plank/auth/respond")
            assert status == 200 and result["state"] == "authenticated"
            token = result["session_token"]

            def get(path, bearer):
                return f"GET {path} HTTP/1.1\r\nHost: localhost\r\nAuthorization: Bearer {bearer}\r\n\r\n".encode()

            assert auth.request(tls, port, {}, raw=get("/plank/topology", "x" * 44))[0] == 401
            assert auth.request(tls, port, {}, raw=get("/serverinfo", token), xml=True)[0] == 200
            assert auth.request(tls, port, {}, raw=get("/applist", token))[0] == 503
            assert not select.select([process.stdout], [], [], .1)[0], "discovery/app-list triggered recovery"
            if mode == "timeout":
                pending = subprocess.Popen(auth.tls_command(tls, port), stdin=subprocess.PIPE,
                                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                try:
                    pending.stdin.write(get("/plank/topology", token)); pending.stdin.flush()
                    assert select.select([process.stdout], [], [], 2)[0]
                    assert process.stdout.readline() == "macos_recovery_called\n"
                    # The network loop must continue serving public discovery.
                    assert auth.request(tls, port, {}, raw=b"GET /serverinfo HTTP/1.1\r\nHost: localhost\r\n\r\n", xml=True)[0] == 200
                    assert select.select([process.stdout], [], [], 7)[0]
                    assert process.stdout.readline() == "macos_recovery_cancelled\n"
                finally:
                    pending.kill(); pending.communicate(timeout=3)
            else:
                status, reply = auth.request(tls, port, {}, raw=get("/plank/topology", token))
                assert status == {"success": 200, "failure": 503, "revoked": 401}[mode]
                assert select.select([process.stdout], [], [], 2)[0]
                assert process.stdout.readline() == "macos_recovery_called\n"
                if mode == "success":
                    assert reply["capture"]["width"] == 3840
                    assert auth.request(tls, port, {}, raw=get("/plank/topology", token)) == (200, reply)
                    assert not select.select([process.stdout], [], [], .1)[0], "healthy topology repeated recovery"
                else:
                    assert reply == {"state": "denied"}
            print(f"macos_topology_recovery={mode}:pass", flush=True)
        finally:
            process.terminate(); process.communicate(timeout=5)


if __name__ == "__main__":
    for scenario in ("success", "failure", "revoked", "timeout"):
        run(Path(sys.argv[1]), Path(sys.argv[2]), scenario)
