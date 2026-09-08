#!/usr/bin/env python3
"""Install a signed development Host for LoginWindow and the designated Mac user.

Not a release installer. No login, logout, reboot, TCC change,
firewall change, or private key copying from another machine. The narrow root
coordinator and the current user's graphical agent retain separate authority.
"""
import argparse
import os
from pathlib import Path
import plistlib
import pwd
import shutil
import stat
import subprocess
import tempfile
import uuid


def run(*args, check=True):
    return subprocess.run(args, check=check, capture_output=True, text=True, timeout=30)


def prepare_sign_in_identity(private, public_config):
    """Root LoginWindow gets its own key, never a copy of the desktop key.

    Only public discovery values are shared. The existing Client profile-TLS
    policy supports fresh authentication after a role/certificate replacement;
    a matching UUID is discovery identity, not a cryptographic trust claim.
    """
    private.mkdir(mode=0o700, exist_ok=True)
    assert not private.is_symlink() and private.stat().st_uid == os.geteuid()
    assert stat.S_IMODE(private.stat().st_mode) == 0o700
    config_path = private / "host.plist"
    if config_path.exists() or config_path.is_symlink():
        for name in ("host.plist", "cert.pem", "key.pem", "cert.der", "key.der"):
            path = private / name
            assert not path.is_symlink() and path.is_file()
            assert path.stat().st_uid == os.geteuid() and stat.S_IMODE(path.stat().st_mode) == 0o600
        existing = plistlib.loads(config_path.read_bytes())
        assert existing == public_config, "Installed sign-in identity/configuration must be preserved"
        return
    assert not any(private.iterdir()), "Refusing a partial sign-in identity"
    with tempfile.TemporaryDirectory(prefix=".identity-", dir=private) as temporary:
        stage = Path(temporary)
        run("openssl", "req", "-x509", "-newkey", "rsa:3072", "-nodes", "-sha256", "-days", "365",
            "-subj", "/CN=PLANK Host", "-addext", "subjectAltName=DNS:plank-host",
            "-keyout", str(stage / "initial.pem"), "-out", str(stage / "cert.pem"))
        run("openssl", "rsa", "-in", str(stage / "initial.pem"), "-out", str(stage / "key.pem"))
        run("openssl", "rsa", "-in", str(stage / "key.pem"), "-outform", "DER", "-out", str(stage / "key.der"))
        run("openssl", "x509", "-in", str(stage / "cert.pem"), "-outform", "DER", "-out", str(stage / "cert.der"))
        (stage / "host.plist").write_bytes(plistlib.dumps(public_config))
        for name in ("cert.pem", "key.pem", "cert.der", "key.der", "host.plist"):
            os.chmod(stage / name, 0o600)
            os.replace(stage / name, private / name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--desktop-user", required=True)
    parser.add_argument("--port", type=int, default=28989)
    args = parser.parse_args()
    assert os.getuid() == 0 and os.uname().sysname == "Darwin"
    assert int(run("sw_vers", "-productVersion").stdout.split(".")[0]) >= 27
    assert 1 <= args.port <= 65535
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
        config_path.write_bytes(plistlib.dumps({"Address": "0.0.0.0", "Port": args.port,
            "Name": "PLANK Mac Host", "UUID": str(uuid.uuid4())}))
    else:
        config = plistlib.loads(config_path.read_bytes())
        assert config["Port"] == args.port, "Existing listener port is preserved"
        # Product listeners serve every interface, including ZeroTier interfaces
        # added after installation. Never bind to the builder's access address.
        config["Address"] = "0.0.0.0"
        config_path.write_bytes(plistlib.dumps(config))
    for name in ("host.plist", "cert.pem", "key.pem", "cert.der", "key.der"):
        path = private / name
        assert not path.is_symlink() and path.is_file()
        os.chmod(path, 0o600)
        os.chown(path, account.pw_uid, account.pw_gid)
    os.chown(private, account.pw_uid, account.pw_gid)
    # Read only public values with the desktop user's authority. No root code
    # follows paths in a writable user home to obtain secrets.
    public_config = plistlib.loads(config_path.read_bytes())

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

    machine_state = Path("/Library/Application Support/PLANK")
    machine_state.mkdir(mode=0o700, exist_ok=True)
    assert not machine_state.is_symlink() and machine_state.stat().st_uid == 0
    os.chmod(machine_state, 0o700)
    sign_in_private = machine_state / "SignIn"
    prepare_sign_in_identity(sign_in_private, public_config)

    machine_label = "la.instinctual.PLANK.Host.machine"
    graphical_label = "la.instinctual.PLANK.Host.desktop"
    sign_in_label = "la.instinctual.PLANK.Host.sign-in"
    domain = f"gui/{account.pw_uid}"
    for job in ("loginwindow/" + sign_in_label, domain + "/" + graphical_label, "system/" + machine_label):
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
    sign_in_log = machine_logs / "host-sign-in.log"
    assert not sign_in_log.is_symlink()
    sign_in_log.touch(mode=0o600, exist_ok=True)
    os.chmod(sign_in_log, 0o600)
    machine = {"Label": machine_label, "ProgramArguments": [executable, "--machine", machine_label],
        "MachServices": {machine_label: True}, "RunAtLoad": True,
        "StandardOutPath": str(machine_log), "StandardErrorPath": str(machine_log)}
    graphical = {"Label": graphical_label, "ProgramArguments": [executable, "--graphical", machine_label, "desktop", str(private)],
        "RunAtLoad": True, "KeepAlive": True, "ThrottleInterval": 2,
        "LimitLoadToSessionType": "Aqua", "ProcessType": "Interactive",
        "StandardOutPath": str(logs / "host-desktop.log"), "StandardErrorPath": str(logs / "host-desktop.log")}
    sign_in = {"Label": sign_in_label,
        "ProgramArguments": [executable, "--graphical", machine_label, "sign-in", str(sign_in_private)],
        "RunAtLoad": True, "KeepAlive": True, "ThrottleInterval": 2,
        "LimitLoadToSessionType": "LoginWindow", "ProcessType": "Interactive",
        "StandardOutPath": str(sign_in_log), "StandardErrorPath": str(sign_in_log)}
    machine_path = Path("/Library/LaunchDaemons") / (machine_label + ".plist")
    agent_path = agent_dir / (graphical_label + ".plist")
    sign_in_path = Path("/Library/LaunchAgents") / (sign_in_label + ".plist")
    for path, content, uid in ((machine_path, machine, 0), (agent_path, graphical, account.pw_uid),
                               (sign_in_path, sign_in, 0)):
        os.setegid(0 if uid == 0 else account.pw_gid)
        os.seteuid(uid)
        assert not path.is_symlink()
        path.write_bytes(plistlib.dumps(content))
        os.chmod(path, 0o644)
        os.chown(path, uid, 0 if uid == 0 else account.pw_gid)
        os.seteuid(0)
    run("launchctl", "bootstrap", "system", str(machine_path))
    run("launchctl", "bootstrap", domain, str(agent_path))
    print("Installed", info["PLANKVersion"], "for LoginWindow and desktop user", account.pw_name)
    print("LoginWindow agent will load in the next LoginWindow session; no logout or reboot performed.")
    print("Desktop logs:", logs, "Machine/sign-in logs:", machine_logs)


if __name__ == "__main__":
    main()
