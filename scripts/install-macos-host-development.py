#!/usr/bin/env python3
"""Install a signed development Host for LoginWindow and every Aqua user.

Not a release installer. No login, logout, reboot, TCC change,
firewall change, or private key copying from another machine. The narrow root
coordinator and the current user's graphical agent retain separate authority.
"""
import argparse
import os
from pathlib import Path
import plistlib
import pwd
import re
import shutil
import stat
import subprocess
import tempfile
import time
import uuid


def run(*args, check=True):
    return subprocess.run(args, check=check, capture_output=True, text=True, timeout=30)


def job_state(job):
    result = run("launchctl", "print", job, check=False)
    if result.returncode == 0:
        match = re.search(r"^\s*pid = ([1-9][0-9]*)$", result.stdout, re.MULTILINE)
        return True, int(match[1]) if match else None
    # Other launchctl failures (notably permission errors) are not absence.
    if f'Could not find service "{job.rsplit("/", 1)[1]}"' in result.stderr:
        return False, None
    # LoginWindow/Aqua domains can legitimately be absent during transitions.
    if "Could not find domain for" in result.stderr:
        return False, None
    raise RuntimeError(f"Cannot inspect launchd job {job}: {result.stderr.strip()}")


def process_exists(pid):
    try:
        os.kill(pid, 0)  # Existence check only, never a termination signal.
        return True
    except ProcessLookupError:
        return False


def stop_job(job, timeout=20):
    """Do not replace code or start another coordinator while a worker drains.

    bootout is asynchronous. Require both deregistration and observed process
    exit. PID reuse can only cause a conservative timeout, not premature success.
    No force-kill, repeated bootstrap or fixed sleep masquerading as completion.
    """
    present, pid = job_state(job)
    if not present:
        return
    pids = {pid} if pid else set()
    run("launchctl", "bootout", job, check=False)
    deadline = time.monotonic() + timeout
    while True:
        present, pid = job_state(job)
        if pid:
            pids.add(pid)
        pids = {pid for pid in pids if process_exists(pid)}
        if not present and not pids:
            return
        if time.monotonic() >= deadline:
            raise RuntimeError(f"Timed out draining {job}; app replacement/startup cancelled")
        time.sleep(0.1)


def signing_identity(app):
    """Verify code before trusting its metadata; never silently reset TCC identity."""
    if app.is_symlink() or not app.is_dir():
        raise ValueError("Host application must be a real application directory")
    run("codesign", "--verify", "--strict", str(app))
    signature = run("codesign", "-d", "--verbose=4", str(app)).stderr
    teams = re.findall(r"^TeamIdentifier=([A-Z0-9]{10})$", signature, re.MULTILINE)
    if "Authority=Apple Development:" not in signature or len(teams) != 1:
        raise ValueError("Development installer requires an Apple Development-signed Host")
    result = run("codesign", "-d", "-r-", str(app))
    # codesign writes the requirement to stdout, while diagnostics go to
    # stderr. Accept either stream, but never two ambiguous requirements.
    detail = result.stdout + "\n" + result.stderr
    requirements = re.findall(r"^designated => (.+)$", detail, re.MULTILINE)
    if len(requirements) != 1:
        raise ValueError("Host has no unambiguous designated signing requirement")
    return teams[0], requirements[0]


def verify_upgrade_identity(source, installed):
    """Fail before changing state or stopping services if consent identity changes.

    An intentional transition to Developer ID distribution needs its own
    administrator-approved provisioning/consent test, not an automatic bypass.
    Equality is deliberately conservative; no CDHash/version pinning, so an
    ordinary rebuild under the same signing requirement remains installable.
    """
    candidate = signing_identity(source)
    if installed.exists() or installed.is_symlink():
        current = signing_identity(installed)
        if current != candidate:
            raise ValueError("Host signing identity changed; preserving installed app and services. "
                             "Qualify permission continuity before changing signer or designated requirement.")


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
    if config_path.exists() or config_path.is_symlink() or (private / "cert.pem").exists():
        for name in (("host.plist",) if public_config is not None else ()) + ("cert.pem", "key.pem", "cert.der", "key.der"):
            path = private / name
            assert not path.is_symlink() and path.is_file()
            assert path.stat().st_uid == os.geteuid() and stat.S_IMODE(path.stat().st_mode) == 0o600
        if public_config is not None:
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
        if public_config is not None:
            (stage / "host.plist").write_bytes(plistlib.dumps(public_config))
        for name in ("cert.pem", "key.pem", "cert.der", "key.der") + (("host.plist",) if public_config is not None else ()):
            os.chmod(stage / name, 0o600)
            os.replace(stage / name, private / name)


def read_public(path, mode=0o644):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, "rb") as source:
        st = os.fstat(source.fileno())
        if not stat.S_ISREG(st.st_mode) or st.st_uid != 0 or st.st_nlink != 1 or \
                stat.S_IMODE(st.st_mode) != mode or not 0 < st.st_size <= 32768:
            raise ValueError("Invalid administrator-owned public configuration")
        config = plistlib.loads(source.read(32769))
    if set(config) != {"Address", "Port", "Name", "UUID"} or config["Address"] != "0.0.0.0" or \
            type(config["Port"]) is not int or not 1 <= config["Port"] <= 65535 or \
            not isinstance(config["Name"], str) or not config["Name"] or not uuid.UUID(config["UUID"]):
        raise ValueError("Invalid public configuration values")
    return config


MACHINE_LABEL = "la.instinctual.PLANK.Host.machine"
DESKTOP_LABEL = "la.instinctual.PLANK.Host.desktop"
SIGN_IN_LABEL = "la.instinctual.PLANK.Host.sign-in"


def stop_roles():
    stop_job("loginwindow/" + SIGN_IN_LABEL)
    # Enumerate OS accounts, not home directories. Stop existing Aqua jobs,
    # including fast-switched users, before retiring the exclusive coordinator.
    for uid in sorted({entry.pw_uid for entry in pwd.getpwall() if entry.pw_uid > 0}):
        stop_job(f"gui/{uid}/" + DESKTOP_LABEL)
    stop_job("system/" + MACHINE_LABEL)


def retire_user_agent(name):
    """Explicit upgrade cleanup only; permanently drop authority before homes."""
    account = pwd.getpwnam(name)
    if account.pw_uid <= 0:
        raise ValueError("Refusing root as a desktop user")
    pid = os.fork()
    if pid == 0:
        try:
            os.initgroups(account.pw_name, account.pw_gid)
            os.setgid(account.pw_gid)
            os.setuid(account.pw_uid)
            path = Path(account.pw_dir) / "Library/LaunchAgents" / (DESKTOP_LABEL + ".plist")
            if path.exists() or path.is_symlink():
                if path.is_symlink() or not path.is_file():
                    raise ValueError("Invalid prior user LaunchAgent")
                data = plistlib.loads(path.read_bytes())
                args = data.get("ProgramArguments", [])
                if data.get("Label") != DESKTOP_LABEL or len(args) != 5 or args[:4] != [
                    "/Applications/PLANK Host.app/Contents/MacOS/plank-host", "--graphical", MACHINE_LABEL, "desktop"]:
                    raise ValueError("Unrecognized prior user LaunchAgent")
                # Recoverable and no longer a .plist launchd startup entry.
                backup = path.with_suffix(".plist.retired")
                if backup.exists() or backup.is_symlink():
                    raise ValueError("Prior LaunchAgent backup already exists")
                path.rename(backup)
            os._exit(0)
        except Exception:
            os._exit(1)
    _, status = os.waitpid(pid, 0)
    if not os.WIFEXITED(status) or os.WEXITSTATUS(status):
        raise RuntimeError("Could not retire the explicitly selected user LaunchAgent")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--retire-user-agent", action="append", default=[], metavar="USER",
                        help="Retire an explicitly named prior development-install user job; no home scanning")
    parser.add_argument("--port", type=int, help="First-install port; existing administrator value is preserved")
    args = parser.parse_args()
    assert os.getuid() == 0 and os.uname().sysname == "Darwin"
    assert int(run("sw_vers", "-productVersion").stdout.split(".")[0]) >= 27
    assert args.port is None or 1 <= args.port <= 65535
    console_uid = os.stat("/dev/console").st_uid
    active_domain = "loginwindow" if console_uid == 0 else f"gui/{console_uid}"
    # Installation may occur before first login. This proves that launchd has
    # the domain; the graphical executable still independently proves authority.
    run("launchctl", "print", active_domain)
    assert not args.app.is_symlink(), "Refusing an application symlink"
    source = args.app.resolve(strict=True)
    info = plistlib.loads((source / "Contents/Info.plist").read_bytes())
    assert info["CFBundleIdentifier"] == "la.instinctual.PLANK.Host"
    assert re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+(?:-[a-z][a-z0-9.-]*)?", info["PLANKVersion"])
    installed = Path("/Applications/PLANK Host.app")
    verify_upgrade_identity(source, installed)

    machine_state = Path("/Library/Application Support/PLANK")
    machine_state.mkdir(mode=0o700, exist_ok=True)
    assert not machine_state.is_symlink() and machine_state.stat().st_uid == 0
    sign_in_private = machine_state / "SignIn"
    public_path = machine_state / "host.plist"
    if public_path.exists() or public_path.is_symlink():
        public_config = read_public(public_path)
    elif (sign_in_private / "host.plist").exists():
        # Upgrade only the prior PLANK development installation's public data.
        assert not sign_in_private.is_symlink() and sign_in_private.stat().st_uid == 0
        public_config = read_public(sign_in_private / "host.plist", 0o600)
    else:
        public_config = {"Address": "0.0.0.0", "Port": args.port or 28989,
                         "Name": "PLANK Mac Host", "UUID": str(uuid.uuid4())}
    if args.port is not None and args.port != public_config["Port"]:
        raise ValueError("Existing administrator port is preserved")
    prepare_sign_in_identity(sign_in_private, None)
    if not public_path.exists():
        with public_path.open("xb") as target:
            target.write(plistlib.dumps(public_config))
        os.chmod(public_path, 0o644)
    # Only public settings become readable. SignIn remains root-only 0700/0600.
    os.chmod(machine_state, 0o755)

    machine_label = "la.instinctual.PLANK.Host.machine"
    graphical_label = "la.instinctual.PLANK.Host.desktop"
    sign_in_label = "la.instinctual.PLANK.Host.sign-in"
    stop_roles()
    for name in args.retire_user_agent:
        retire_user_agent(name)
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
    graphical = {"Label": graphical_label, "ProgramArguments": [executable, "--desktop", machine_label],
        "RunAtLoad": True, "KeepAlive": True, "ThrottleInterval": 2,
        "LimitLoadToSessionType": "Aqua", "ProcessType": "Interactive",
        "StandardOutPath": "/dev/null", "StandardErrorPath": "/dev/null", "Umask": 0o077}
    sign_in = {"Label": sign_in_label,
        "ProgramArguments": [executable, "--sign-in", machine_label],
        "RunAtLoad": True, "KeepAlive": True, "ThrottleInterval": 2,
        "LimitLoadToSessionType": "LoginWindow", "ProcessType": "Interactive",
        "StandardOutPath": str(sign_in_log), "StandardErrorPath": str(sign_in_log)}
    machine_path = Path("/Library/LaunchDaemons") / (machine_label + ".plist")
    agent_path = Path("/Library/LaunchAgents") / (graphical_label + ".plist")
    sign_in_path = Path("/Library/LaunchAgents") / (sign_in_label + ".plist")
    for path, content in ((machine_path, machine), (agent_path, graphical), (sign_in_path, sign_in)):
        assert not path.is_symlink()
        path.write_bytes(plistlib.dumps(content))
        os.chmod(path, 0o644)
        os.chown(path, 0, 0)
    run("launchctl", "bootstrap", "system", str(machine_path))
    if os.stat("/dev/console").st_uid == console_uid:
        run("launchctl", "bootstrap", active_domain, str(sign_in_path if console_uid == 0 else agent_path))
    else:
        print("Console changed during installation; graphical startup deferred to its next session.")
    print("Installed", info["PLANKVersion"], "for LoginWindow and all Aqua users")
    print("Graphical jobs are registered for LoginWindow/Aqua; no logout or reboot performed.")
    print("Desktop logs: each user's Library/Logs/PLANK; machine/sign-in logs:", machine_logs)


if __name__ == "__main__":
    main()
