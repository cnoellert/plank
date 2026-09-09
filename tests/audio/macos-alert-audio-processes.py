#!/usr/bin/env python3
"""Run the non-capturing alert-source probe in the current user's Aqua session.

Default is identity-only (silent). --play-alerts emits three deliberate system
alerts. No tap, capture, permission request, setting change or permanent job.
"""
import argparse
import os
from pathlib import Path
import plistlib
import pwd
import re
import subprocess
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=Path)
    parser.add_argument("--play-alerts", action="store_true")
    args = parser.parse_args()
    assert os.getuid() == 0 and os.uname().sysname == "Darwin"
    uid = os.stat("/dev/console").st_uid
    assert uid > 0
    gid = pwd.getpwuid(uid).pw_gid
    binary = args.binary.resolve(strict=True)
    label = "la.instinctual.PLANK.alert-inventory"
    domain = f"gui/{uid}"

    def run(*command, check=True):
        return subprocess.run(command, check=check, capture_output=True, text=True)

    assert run("launchctl", "print", f"{domain}/{label}", check=False).returncode != 0
    with tempfile.TemporaryDirectory(prefix="plank-alert-inventory-", dir="/private/tmp") as directory:
        stage = Path(directory)
        os.chmod(stage, 0o755)
        executable = stage / "inventory"
        executable.write_bytes(binary.read_bytes())
        os.chmod(executable, 0o755)
        for name in ("stdout", "stderr"):
            (stage / name).touch(mode=0o600)
            os.chown(stage / name, uid, gid)
        plist = stage / "agent.plist"
        command = [str(executable)] + ([] if args.play_alerts else ["--identity-only"])
        plist.write_bytes(plistlib.dumps({"Label": label, "ProgramArguments": command,
            "RunAtLoad": True, "LimitLoadToSessionType": "Aqua",
            "StandardOutPath": str(stage / "stdout"), "StandardErrorPath": str(stage / "stderr")}))
        try:
            assert os.stat("/dev/console").st_uid == uid
            run("launchctl", "bootstrap", domain, str(plist))
            result = None
            for _ in range(25):
                status = run("launchctl", "print", f"{domain}/{label}").stdout
                match = re.search(r"last exit code = (-?\d+)", status)
                if match:
                    result = int(match[1])
                    break
                time.sleep(1)
            print((stage / "stdout").read_text())
            print((stage / "stderr").read_text())
            assert result == 0, result
        finally:
            run("launchctl", "bootout", f"{domain}/{label}", check=False)


if __name__ == "__main__":
    main()
