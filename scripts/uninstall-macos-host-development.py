#!/usr/bin/env python3
"""Uninstall the development macOS Host, preserving settings, identities and logs.

Run as administrator with Python 3. No TCC reset, account changes or reboot.
The application is retained in a root-only recovery directory, not erased.
"""
import importlib.util
import os
from pathlib import Path
import plistlib
import tempfile
import sys

sys.dont_write_bytecode = True  # Never mutate the signed Resources directory.

SPEC = importlib.util.spec_from_file_location("installer", Path(__file__).with_name("install-macos-host-development.py"))
INSTALLER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(INSTALLER)


def owned_job(path, label):
    if not path.exists() and not path.is_symlink():
        return False
    if path.is_symlink() or not path.is_file() or path.stat().st_uid != 0:
        raise ValueError("Refusing an unexpected launchd file: " + str(path))
    data = plistlib.loads(path.read_bytes())
    args = data.get("ProgramArguments", [])
    if data.get("Label") != label or not args or args[0] != "/Applications/PLANK Host.app/Contents/MacOS/plank-host":
        raise ValueError("Refusing an unrelated launchd file: " + str(path))
    return True


def main():
    if os.getuid() != 0 or os.uname().sysname != "Darwin":
        raise SystemExit("Run this development uninstaller as administrator on macOS")
    app = Path("/Applications/PLANK Host.app")
    if app.exists() or app.is_symlink():
        INSTALLER.signing_identity(app)
    jobs = [(Path("/Library/LaunchDaemons") / (INSTALLER.MACHINE_LABEL + ".plist"), INSTALLER.MACHINE_LABEL),
            (Path("/Library/LaunchAgents") / (INSTALLER.DESKTOP_LABEL + ".plist"), INSTALLER.DESKTOP_LABEL),
            (Path("/Library/LaunchAgents") / (INSTALLER.SIGN_IN_LABEL + ".plist"), INSTALLER.SIGN_IN_LABEL)]
    paths = [path for path, label in jobs if owned_job(path, label)]
    INSTALLER.stop_roles()
    for path in paths:
        path.unlink()
    if app.exists():
        recovery = Path(tempfile.mkdtemp(prefix="plank-host-uninstalled-", dir="/Library/Caches"))
        app.rename(recovery / app.name)
        print("Application retained for recovery:", recovery)
    print("PLANK Host launch entries removed; configuration, identities and logs preserved.")
    print("macOS privacy permissions and other products were not modified.")


if __name__ == "__main__":
    main()
