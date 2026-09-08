#!/usr/bin/env python3
"""Loopback TLS/auth qualification. Synthetic credentials only by default."""
import argparse
import getpass
import hashlib
import http.client
import io
import json
import os
from pathlib import Path
import plistlib
import re
import select
import socket
import subprocess
import tempfile
import time
import uuid
import xml.etree.ElementTree as ET


def context(certificate):
    # Xcode's Python links LibreSSL 2.8.3 without TLS 1.3. The OS openssl CLI
    # supports TLS 1.3. Trust only our generated self-signed loopback fixture;
    # there is no insecure/no-verify option and this is not the product client.
    return Path(certificate)


def tls_command(certificate, port, version="-tls1_3"):
    return ["openssl", "s_client", "-connect", f"127.0.0.1:{port}", "-servername", "localhost",
            "-CAfile", str(certificate), "-verify_return_error", "-verify", "1", version,
            "-alpn", "http/1.1", "-quiet"]


class ResponseBytes:
    def __init__(self, value):
        self.value = value

    def makefile(self, *args):
        return io.BytesIO(self.value)


def request(tls, port, body, path="/plank/auth/start", raw=None, xml=False):
    encoded = json.dumps(body).encode()
    message = raw if raw is not None else (
        f"POST {path} HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\n"
        f"Content-Length: {len(encoded)}\r\n\r\n".encode() + encoded
    )
    result = subprocess.run(tls_command(tls, port), input=message, capture_output=True, timeout=7)
    if result.returncode:
        raise AssertionError(f"TLS request failed (exit {result.returncode}): " + result.stderr.decode(errors="replace")[-1000:])
    reply = http.client.HTTPResponse(ResponseBytes(result.stdout))
    reply.begin()
    assert reply.getheader("Cache-Control") == "no-store"
    assert reply.getheader("Connection") == "close"
    content = reply.read()
    if xml:
        assert reply.getheader("Content-Type") == "application/xml; charset=utf-8"
        return reply.status, ET.fromstring(content)
    return reply.status, json.loads(content)


def discovery(tls, port):
    # Exact current Client request shape, including its optional cache busters.
    target = "/serverinfo?uniqueid=0123456789ABCDEF&uuid=" + uuid.uuid4().hex
    raw = f"GET {target} HTTP/1.1\r\nHost: localhost\r\n\r\n".encode()
    status, root = request(tls, port, {}, raw=raw, xml=True)
    assert status == 200 and root.tag == "root" and root.attrib == {"status_code": "200"}
    expected = {"hostname": "PLANK Mac qualification",
                "uniqueid": "f92140f5-8740-4b3b-82f7-74db5353de27",
                "HttpsPort": str(port), "PlankHostMetadataVersion": "1",
                "PlankHostVersion": "macos-host-qualification", "PlankAuth": "1",
                "ServerCodecModeSupport": "0", "PlankTopologyVersion": "0",
                "PlankFeatureFlags": "0", "PairStatus": "0"}
    assert len(root) == len(expected) and {node.tag: node.text for node in root} == expected
    # Discovery is public, but must neither expose session state nor create an
    # alternative GET authentication path. Reject bearer tokens in query strings.
    for path in ["/plank/auth/start", "/plank/auth/respond", "/serverinfo?session_token=abc",
                 "/serverinfo?uuid=abc&uuid=def", "/serverinfo?uuid=%61"]:
        raw = f"GET {path} HTTP/1.1\r\nHost: localhost\r\n\r\n".encode()
        assert request(tls, port, {}, raw=raw)[0] == 404
    assert request(tls, port, {}, "/serverinfo")[0] == 404
    assert request(tls, port, {}, raw=b"GET /plank/topology HTTP/1.1\r\nHost: localhost\r\n\r\n")[0] == 401
    for extra in ["Content-Length: 1\r\n", "Transfer-Encoding: chunked\r\n",
                  "Expect: 100-continue\r\n", "Content-Length: 0\r\nContent-Length: 0\r\n"]:
        raw = ("GET /serverinfo HTTP/1.1\r\nHost: localhost\r\n" + extra + "\r\n").encode()
        assert request(tls, port, {}, raw=raw)[0] == 400


def authenticate(tls, port, username, password):
    status, start = request(tls, port, {"username": username})
    assert status == 200 and start["state"] == "challenge"
    assert start["messages"][0]["style"] == 1
    response = {"conversation_id": start["conversation_id"], "responses": [password]}
    status, result = request(tls, port, response, "/plank/auth/respond")
    assert status == 200 and result["state"] == "authenticated"
    assert len(result["session_token"]) == 44
    token = result["session_token"]
    for bearer, expected in [(token, "1"), ("x" * 44, "0"), ("", "0")]:
        header = f"Authorization: Bearer {bearer}\r\n" if bearer else ""
        raw = f"GET /serverinfo HTTP/1.1\r\nHost: localhost\r\n{header}\r\n".encode()
        status, info = request(tls, port, {}, raw=raw, xml=True)
        assert status == 200 and info.findtext("PairStatus") == expected
    # No token or credential is printed or written to a file.
    status, replay = request(tls, port, response, "/plank/auth/respond")
    assert status == 200 and replay["state"] == "denied"
    raw = ("GET /plank/topology?uniqueid=0123456789ABCDEF&uuid=abc HTTP/1.1\r\nHost: localhost\r\n"
           "Authorization: Bearer " + token + "\r\n\r\n").encode()
    status, topology = request(tls, port, {}, raw=raw)
    assert status == 200 and topology["schema_version"] == 13 and topology["feature_flags"] == 1572977
    capture = topology["capture"]
    assert 2 <= capture["width"] <= 8192 and capture["width"] % 2 == 0
    assert 2 <= capture["height"] <= 8192 and capture["height"] % 2 == 0
    assert capture["logical_bounds"]["width"] > 0 and capture["logical_bounds"]["height"] > 0
    assert capture["encoding_profile"]["encoding_mode"] == "hevc-10-420-videotoolbox"
    assert capture["encoding_profile"]["rgb_identity"] is False
    status, repeated = request(tls, port, {}, raw=raw)
    assert status == 200 and repeated == topology
    # Same request shape, unknown token; never echo it or any account data.
    assert request(tls, port, {}, raw=raw.replace(token.encode(), b"x" * 44))[0] == 401
    return token, topology


def preview(tls, port, token, topology, receiver, media, seconds=3):
    capture = topology["capture"]
    body = {"schema_version": 1, "capture_generation": topology["generation"], "capture_id": capture["id"],
            "width": capture["width"], "height": capture["height"], "encoding_mode": "hevc-10-420-videotoolbox",
            "frame_rate": 60, "bitrate_kbps": 50000, "max_udp_payload_size": 1200}

    def launch(value, bearer, path="/plank/launch"):
        encoded = json.dumps(value).encode()
        raw = (f"POST {path} HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\n"
               f"Authorization: Bearer {bearer}\r\nContent-Length: {len(encoded)}\r\n\r\n").encode() + encoded
        return request(tls, port, {}, raw=raw)

    if not media:  # Synthetic display adapter; never changes a real desktop.
        mode = {"schema_version": 1, "width": 1920, "height": 1080}
        assert launch(mode, "x" * 44, "/plank/display")[0] == 401
        for invalid in [dict(mode, width=True), dict(mode, width=1920.5),
                        dict(mode, width=-1), dict(mode, extra=0), dict(mode, schema_version=2)]:
            assert launch(invalid, token, "/plank/display")[0] == 400
        assert launch(dict(mode, width=1922), token, "/plank/display")[0] == 503
        status, resized = launch(mode, token, "/plank/display")
        assert status == 200 and resized["capture"]["width"] == 1920
        status, restored = launch(dict(mode, width=3840, height=2160), token, "/plank/display")
        assert status == 200 and restored == topology

    assert launch(body, "x" * 44)[0] == 401
    assert launch(dict(body, width=1), token)[0] == 400
    assert launch(dict(body, encoding_mode="hevc-10-444-nvenc"), token)[0] == 400
    assert launch(dict(body, capture_generation=str(uuid.uuid4())), token)[0] == 400
    status, reply = launch(body, token)
    assert status == 200 and reply["schema_version"] == 1 and reply["state"] == "connecting"
    assert reply["udp_port"] == port and reply["max_udp_payload_size"] == 1200
    assert reply["capture"] == capture and reply["transport_token"] != token
    assert reply["services"] == {"audio": True, "input": True, "cursor": "embedded"}
    assert launch(body, token)[0] == 401  # one-use HTTP token, before QUIC activation
    assert launch({"schema_version": 1, "width": 1920, "height": 1080}, token, "/plank/display")[0] == 401
    fingerprint = hashlib.sha256(tls.with_name("cert.der").read_bytes()).hexdigest()
    command = [str(receiver), fingerprint] + (["--seconds", str(seconds)] if media else ["--no-media"])
    # No launch/transport credential in argv, environment, files or diagnostics.
    result = subprocess.run(command, input=json.dumps(reply).encode(), capture_output=True, timeout=seconds + 15)
    assert result.returncode == 0, "Native preview receiver failed: " + result.stderr.decode(errors="replace")
    print(result.stdout.decode().strip())


def create_identity(temporary, config):
    os.chmod(temporary, 0o700)
    cert, key = [Path(temporary) / name for name in ("cert.pem", "key.pem")]
    subprocess.run(["openssl", "req", "-new", "-x509", "-newkey", "rsa:3072", "-sha256",
                    "-nodes", "-days", "1", "-config", str(config), "-keyout", str(key),
                    "-out", str(cert)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    os.chmod(key, 0o600)
    subprocess.run(["openssl", "x509", "-in", str(cert), "-outform", "DER", "-out", str(Path(temporary) / "cert.der")],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["openssl", "rsa", "-in", str(key), "-outform", "DER", "-out", str(Path(temporary) / "key.der")],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    os.chmod(Path(temporary) / "key.der", 0o600)
    return cert


def aqua(executable, config, receiver=None, seconds=3):
    if not os.isatty(0) or os.geteuid() == 0:
        raise AssertionError("Aqua qualification requires the desktop user's TTY")
    domain = f"gui/{os.geteuid()}"
    subprocess.run(["launchctl", "print", domain], check=True, stdout=subprocess.DEVNULL)
    password = getpass.getpass("Development account password: ")
    with tempfile.TemporaryDirectory(prefix="plank-https-aqua-") as temporary:
        cert = create_identity(temporary, config)
        label = "la.instinctual.PLANK.https-qualification." + uuid.uuid4().hex
        stage = Path(temporary)
        # This generated, one-shot qualification job is never installed in a
        # LaunchAgents directory. Finally always unregisters it and removes its
        # own fixtures/logs. No password or bearer token enters the plist/logs.
        plist = {"Label": label, "ProgramArguments": [str(executable), temporary],
                 "RunAtLoad": True, "LimitLoadToSessionType": "Aqua", "ProcessType": "Interactive",
                 "StandardOutPath": str(stage / "stdout"), "StandardErrorPath": str(stage / "stderr")}
        with (stage / "agent.plist").open("wb") as stream:
            plistlib.dump(plist, stream)
        try:
            subprocess.run(["launchctl", "bootstrap", domain, str(stage / "agent.plist")], check=True)
            deadline = time.monotonic() + 10
            match = None
            while time.monotonic() < deadline:
                output = (stage / "stdout").read_text() if (stage / "stdout").exists() else ""
                match = re.fullmatch(r"macos_https_auth_ready port=(\d+) desktop_active=1\n", output)
                if match:
                    break
                time.sleep(0.1)
            assert match, "Aqua HTTPS readiness/desktop ownership failed"
            port = int(match[1])
            discovery(context(cert), port)
            token, topology = authenticate(context(cert), port, getpass.getuser(), password)
            password = None
            if receiver:
                preview(context(cert), port, token, topology, receiver, True, seconds)
                print("macos_https_aqua_preview=pass tls13_verified=1 live_owner=1 authenticated_capture=1 native_quic=1")
            else:
                print("macos_https_aqua_account=pass tls13_verified=1 live_owner=1 replay_denied=1 authenticated_topology=1 desktop_granted=0")
        except Exception:
            # Narrow numeric/stage-only diagnostics; never dump server stderr,
            # which could gain account/session details in a future dependency.
            error_file = stage / "stderr"
            if error_file.exists():
                for line in error_file.read_text(errors="replace").splitlines():
                    if re.fullmatch(r"macos_(?:opus|capture)_failure stage=[a-z-]+(?: (?:gap_ns|code)=[0-9.+-]+)?", line):
                        print(line, flush=True)
            raise
        finally:
            password = None
            subprocess.run(["launchctl", "bootout", f"{domain}/{label}"], stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, check=False)


def synthetic(executable, config, receiver=None):
    with tempfile.TemporaryDirectory(prefix="plank-https-qualification-") as temporary:
        cert = create_identity(temporary, config)
        process = subprocess.Popen([str(executable), temporary], stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, text=True)
        try:
            if not select.select([process.stdout], [], [], 10)[0]:
                raise AssertionError("HTTPS listener readiness timed out")
            line = process.stdout.readline()
            match = re.fullmatch(r"macos_https_auth_ready port=(\d+) desktop_active=1\n", line)
            if not match:
                raise AssertionError("HTTPS listener did not report ready: " + line.strip())
            port = int(match[1])
            tls = context(cert)
            discovery(tls, port)
            token, topology = authenticate(tls, port, "synthetic", "test")
            if receiver:
                preview(tls, port, token, topology, receiver, False)
            status, start = request(tls, port, {"username": "synthetic"})
            status, denied = request(tls, port, {"conversation_id": start["conversation_id"],
                                               "responses": ["wrong-synthetic-secret"]}, "/plank/auth/respond")
            assert status == 200 and denied["state"] == "denied"
            for body, path in [([], "/plank/auth/start"), ({"username": 3}, "/plank/auth/start"),
                               ({"username": "synthetic", "extra": 1}, "/plank/auth/start"),
                               ({"conversation_id": "x", "responses": ["a", "b"]}, "/plank/auth/respond")]:
                status, result = request(tls, port, body, path)
                assert status == 400 and result["state"] == "denied"
            assert request(tls, port, {}, "/not-an-endpoint")[0] == 404
            for extra in ["Transfer-Encoding: chunked\r\n", "Content-Length: 2\r\n", "Expect: 100-continue\r\n"]:
                raw = ("POST /plank/auth/start HTTP/1.1\r\nHost: localhost\r\n"
                       "Content-Type: application/json\r\nContent-Length: 2\r\n" + extra + "\r\n{}").encode()
                assert request(tls, port, {}, raw=raw)[0] == 400
            old_tls = subprocess.run(tls_command(cert, port, "-tls1_2"), input=b"", capture_output=True, timeout=7)
            assert old_tls.returncode != 0 and b"HTTP/" not in old_tls.stdout
            untrusted_command = tls_command(cert, port)
            ca_index = untrusted_command.index("-CAfile")
            del untrusted_command[ca_index:ca_index + 2]
            untrusted = subprocess.run(untrusted_command, input=b"", capture_output=True, timeout=7)
            assert untrusted.returncode != 0 and b"HTTP/" not in untrusted.stdout
            with socket.create_connection(("127.0.0.1", port), timeout=3) as plain:
                plain.sendall(b"POST /plank/auth/start HTTP/1.1\r\n\r\n")
                try:
                    assert b"HTTP/" not in plain.recv(4096)
                except ConnectionResetError:
                    pass
            # Slow request must close, not occupy an admission slot indefinitely.
            began = time.monotonic()
            slow = subprocess.run(tls_command(cert, port), input=b"POST /plank/auth/start HTTP/1.1\r\n",
                                  capture_output=True, timeout=7)
            assert b"HTTP/" not in slow.stdout and time.monotonic() - began < 6
            idle = []
            try:
                for _ in range(8):
                    idle.append(socket.create_connection(("127.0.0.1", port), timeout=2))
                time.sleep(0.2)  # Let the listener process admitted connections.
                overflow = subprocess.run(tls_command(cert, port), input=b"", capture_output=True, timeout=3)
                assert overflow.returncode != 0 and b"HTTP/" not in overflow.stdout
            finally:
                for connection in idle:
                    connection.close()
            time.sleep(0.2)
            authenticate(tls, port, "synthetic", "test")
            discovery(tls, port)  # No public metadata change after authentication.
            # No desktop/capture endpoint or real account is used by this suite.
            print("macos_https_auth=pass discovery=1 authenticated_topology=1 invalid_topology_token_rejected=1 no_media_claim=1 tls13=1 tls12_rejected=1 trust_enforced=1 plaintext_rejected=1 replay_denied=1 framing_rejected=1 slow_request_closed=1 admission_bounded=1 recovery_pass=1 synthetic_only=1")
        finally:
            process.terminate()
            try:
                process.communicate(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.communicate(timeout=3)
            # TemporaryDirectory removes only this test's exact ephemeral fixtures.


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--server", type=Path)
    parser.add_argument("--config", type=Path)
    parser.add_argument("--real-port", type=int)
    parser.add_argument("--certificate", type=Path)
    parser.add_argument("--aqua", action="store_true")
    parser.add_argument("--preview-receiver", type=Path)
    parser.add_argument("--preview-seconds", type=int, choices=range(3, 31), default=3)
    args = parser.parse_args()
    if args.aqua:
        if not args.server or not args.config:
            parser.error("Aqua mode requires the real --server and --config")
        aqua(args.server, args.config, args.preview_receiver, args.preview_seconds)
    elif args.real_port:
        if not args.certificate or not os.isatty(0):
            parser.error("Real verification requires a TTY and the exact certificate")
        password = getpass.getpass("Development account password: ")
        authenticate(context(args.certificate), args.real_port, getpass.getuser(), password)
        password = None
        print("macos_https_real_account=pass tls13_verified=1 replay_denied=1 desktop_granted=0")
    else:
        if not args.server or not args.config:
            parser.error("Synthetic suite requires --server and --config")
        synthetic(args.server, args.config, args.preview_receiver)


if __name__ == "__main__":
    main()
