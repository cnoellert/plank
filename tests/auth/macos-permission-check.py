#!/usr/bin/env python3
"""Non-prompting check of installed PLANK in the current user's Aqua domain.

Run as root on the dedicated Mac after the operator logs into the account to
check. No login/logout, persistent job, TCC changes, media or input injection.
Output is a diagnostic, not an authorization decision for another process.
"""
import argparse
import json
import os
from pathlib import Path
import plistlib
import pwd
import subprocess
import tempfile
import time
import uuid


def run(*args, check=True):
    return subprocess.run(args, check=check, capture_output=True, text=True, timeout=15)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--uid", required=True, type=int)
    args = parser.parse_args()
    assert os.uname().sysname == "Darwin" and os.getuid() == 0
    assert args.uid > 0 and os.stat("/dev/console").st_uid == args.uid
    account = pwd.getpwuid(args.uid)
    app = Path("/Applications/PLANK Host.app")
    assert not app.is_symlink()
    run("codesign", "--verify", "--strict", str(app))
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    assert info["CFBundleIdentifier"] == "la.instinctual.PLANK.Host"
    label = "la.instinctual.PLANK.permission-check." + str(uuid.uuid4())
    domain = f"gui/{args.uid}"
    job = domain + "/" + label
    with tempfile.TemporaryDirectory(prefix="plank-permission-check-", dir="/private/tmp") as temporary:
        stage = Path(temporary)
        os.chmod(stage, 0o755)
        out, err = stage / "report.json", stage / "stderr"
        for path in (out, err):
            path.touch(mode=0o600)
            os.chown(path, account.pw_uid, account.pw_gid)
        config = {"Label": label, "ProgramArguments": [str(app / "Contents/MacOS/plank-host"),
                  "--check-permissions"], "RunAtLoad": True, "LimitLoadToSessionType": "Aqua",
                  "StandardOutPath": str(out), "StandardErrorPath": str(err)}
        launch = stage / "check.plist"
        launch.write_bytes(plistlib.dumps(config))
        try:
            run("launchctl", "bootstrap", domain, str(launch))
            deadline = time.monotonic() + 10
            status = ""
            while time.monotonic() < deadline:
                status = run("launchctl", "print", job).stdout
                if "last exit code =" in status:
                    break
                time.sleep(0.1)
            assert os.stat("/dev/console").st_uid == args.uid, "Console changed; discard report"
            assert "last exit code = 0" in status or "last exit code = 3" in status, "Permission diagnostic failed/timed out"
            assert out.stat().st_size <= 4096
            report = json.loads(out.read_text())
            assert report["uid"] == args.uid and report["version"] == info["PLANKVersion"]
            assert report["audio_tap_permission"] == "not-checked"
            print(json.dumps(report, sort_keys=True))
            return 0 if report["screen_input_ready"] else 3
        finally:
            run("launchctl", "bootout", job, check=False)


if __name__ == "__main__":
    raise SystemExit(main())
