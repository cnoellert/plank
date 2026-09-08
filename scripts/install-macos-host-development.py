#!/usr/bin/env python3
"""Install a signed development Host for the existing dedicated Mac desktop.

Not a release installer or LoginWindow enablement. No login, logout, TCC change,
firewall change, or private key copying from another machine. The narrow root
coordinator and the current user's graphical agent retain separate authority.
"""
import argparse
import ipaddress
import os
from pathlib import Path
import plistlib
import pwd
import shutil
import subprocess
import tempfile
import uuid


def run(*args, check=True):
    return subprocess.run(args, check=check, capture_output=True, text=True, timeout=30)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--desktop-user", required=True)
    parser.add_argument("--bind", required=True)
    parser.add_argument("--port", type=int, default=28989)
    args = parser.parse_args()
    assert os.getuid() == 0 and os.uname().sysname == "Darwin"
    assert int(run("sw_vers", "-productVersion").stdout.split(".")[0]) >= 27
    assert 1 <= args.port <= 65535
    ipaddress.IPv4Address(args.bind)
    account = pwd.getpwnam(args.desktop_user)
    assert account.pw_uid > 0 and os.stat("/dev/console").st_uid == account.pw_uid
    source = args.app.resolve(strict=True)
    info = plistlib.loads((source / "Contents/Info.plist").read_bytes())
    assert info["CFBundleIdentifier"] == "la.instinctual.PLANK.Host"
    assert "-macos-host" in info["PLANKVersion"]
    run("codesign", "--verify", "--strict", str(source))
    signature = run("codesign", "-d", "--verbose=4", str(source)).stderr
    assert "Authority=Apple Development:" in signature and "TeamIdentifier=" in signature

    home = Path(account.pw_dir)
    # User configuration is prepared with the user's authority, never by
    # following writable home-directory paths with root file-write privileges.
    os.setegid(account.pw_gid)
    os.seteuid(account.pw_uid)
    private = home / "Library/Application Support/PLANK/Host"
    private.mkdir(parents=True, mode=0o700, exist_ok=True)
    assert not private.is_symlink() and private.stat().st_uid in (0, account.pw_uid)
    os.chmod(private, 0o700)
    config_path = private / "host.plist"
    if not config_path.exists():
        assert not any(private.iterdir()), "Refusing a partial identity; inspect it before retrying"
        with tempfile.TemporaryDirectory(prefix=".identity-", dir=private) as stage_name:
            stage = Path(stage_name)
            run("openssl", "req", "-x509", "-newkey", "rsa:3072", "-nodes", "-sha256", "-days", "365",
                "-subj", "/CN=PLANK Host", "-addext", "subjectAltName=DNS:plank-host",
                "-keyout", str(stage / "initial.pem"), "-out", str(stage / "cert.pem"))
            run("openssl", "rsa", "-in", str(stage / "initial.pem"), "-out", str(stage / "key.pem"))
            run("openssl", "rsa", "-in", str(stage / "key.pem"), "-outform", "DER", "-out", str(stage / "key.der"))
            run("openssl", "x509", "-in", str(stage / "cert.pem"), "-outform", "DER", "-out", str(stage / "cert.der"))
            for name in ("cert.pem", "key.pem", "cert.der", "key.der"):
                os.chmod(stage / name, 0o600)
                os.replace(stage / name, private / name)
        config_path.write_bytes(plistlib.dumps({"Address": args.bind, "Port": args.port,
            "Name": "PLANK Mac Host", "UUID": str(uuid.uuid4())}))
    else:
        config = plistlib.loads(config_path.read_bytes())
        assert config["Address"] == args.bind and config["Port"] == args.port, "Existing listener configuration is preserved"
    for name in ("host.plist", "cert.pem", "key.pem", "cert.der", "key.der"):
        path = private / name
        assert not path.is_symlink() and path.is_file()
        os.chmod(path, 0o600)
        os.chown(path, account.pw_uid, account.pw_gid)
    os.chown(private, account.pw_uid, account.pw_gid)

    logs = home / "Library/Logs/PLANK"
    logs.mkdir(parents=True, mode=0o700, exist_ok=True)
    desktop_log = logs / "host-desktop.log"
    assert not desktop_log.is_symlink()
    desktop_log.touch(mode=0o600, exist_ok=True)
    os.chmod(desktop_log, 0o600)
    agent_dir = home / "Library/LaunchAgents"
    agent_dir.mkdir(mode=0o755, exist_ok=True)
    os.seteuid(0)
    os.setegid(0)

    machine_label = "la.instinctual.PLANK.Host.machine"
    graphical_label = "la.instinctual.PLANK.Host.desktop"
    domain = f"gui/{account.pw_uid}"
    for job in (domain + "/" + graphical_label, "system/" + machine_label):
        run("launchctl", "bootout", job, check=False)
    installed = Path("/Applications/PLANK Host.app")
    if installed.exists():
        backup = Path(tempfile.mkdtemp(prefix="plank-host-previous-", dir="/Library/Caches"))
        os.replace(installed, backup / installed.name)
        print("Previous app retained:", backup)
    shutil.copytree(source, installed)
    for path in [installed, *installed.rglob("*")]:
        os.chown(path, 0, 0)
    run("codesign", "--verify", "--strict", str(installed))
    executable = str(installed / "Contents/MacOS/plank-host")
    machine_logs = Path("/Library/Logs/PLANK")
    machine_logs.mkdir(mode=0o700, exist_ok=True)
    assert not machine_logs.is_symlink() and machine_logs.stat().st_uid == 0
    os.chmod(machine_logs, 0o700)
    machine_log = machine_logs / "host-machine.log"
    assert not machine_log.is_symlink()
    machine_log.touch(mode=0o600, exist_ok=True)
    os.chmod(machine_log, 0o600)
    machine = {"Label": machine_label, "ProgramArguments": [executable, "--machine", machine_label],
        "MachServices": {machine_label: True}, "RunAtLoad": True,
        "StandardOutPath": str(machine_log), "StandardErrorPath": str(machine_log)}
    graphical = {"Label": graphical_label, "ProgramArguments": [executable, "--graphical", machine_label, "desktop", str(private)],
        "RunAtLoad": True, "LimitLoadToSessionType": "Aqua", "ProcessType": "Interactive",
        "StandardOutPath": str(logs / "host-desktop.log"), "StandardErrorPath": str(logs / "host-desktop.log")}
    machine_path = Path("/Library/LaunchDaemons") / (machine_label + ".plist")
    agent_path = agent_dir / (graphical_label + ".plist")
    for path, content, uid in ((machine_path, machine, 0), (agent_path, graphical, account.pw_uid)):
        os.setegid(0 if uid == 0 else account.pw_gid)
        os.seteuid(uid)
        assert not path.is_symlink()
        path.write_bytes(plistlib.dumps(content))
        os.chmod(path, 0o644)
        os.chown(path, uid, 0 if uid == 0 else account.pw_gid)
        os.seteuid(0)
    run("launchctl", "bootstrap", "system", str(machine_path))
    run("launchctl", "bootstrap", domain, str(agent_path))
    print("Installed", info["PLANKVersion"], "for the existing desktop only; logs:", logs)


if __name__ == "__main__":
    main()
