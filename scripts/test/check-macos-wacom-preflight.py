#!/usr/bin/env python3
"""Check the current macOS Client session's raw Wacom prerequisites."""

import argparse
import json
from pathlib import Path
import re


START = re.compile(r"PLANK Wacom preflight: host_raw_hid=([01]) host_focus_suspend=([01])")
PERMISSION = re.compile(r"PLANK Wacom preflight: input_monitoring=(granted|denied|pending)")
DEVICE = re.compile(r"PLANK Wacom preflight: device=([a-z_]+)")


def gate(observed, expected):
    if observed is None:
        return "unverified"
    return "pass" if observed == expected else "fail"


def check_lines(lines):
    session = None
    for line in lines:
        start = START.search(line)
        if start:
            session = {
                "host_raw_hid": start.group(1) == "1",
                "host_focus_suspend": start.group(2) == "1",
                "input_monitoring": None,
                "device": None,
                "attach_sent": False,
                "host_ack": None,
            }
            continue
        if session is None:
            continue
        permission = PERMISSION.search(line)
        device = DEVICE.search(line)
        if permission:
            session["input_monitoring"] = permission.group(1)
        elif device:
            session["device"] = device.group(1)
            if session["device"] != "owned":
                session["attach_sent"] = False
                session["host_ack"] = None
        elif "Mac Wacom attach sent:" in line:
            session["attach_sent"] = True
            session["host_ack"] = None
        elif "Mac Wacom attached; exclusive raw HID forwarding active" in line:
            session["host_ack"] = True
        elif "Mac Wacom host attach rejected:" in line or "Mac Wacom attachment timed out" in line:
            session["host_ack"] = False
        elif "Mac Wacom ownership released" in line and session["device"] == "owned":
            session["device"] = "released"
            session["attach_sent"] = False
            session["host_ack"] = None

    if session is None:
        return {"passed": False, "reason": "preflight_marker_missing", "gates": {}}

    gates = {
        "host_raw_hid": gate(session["host_raw_hid"], True),
        "host_focus_suspend": gate(session["host_focus_suspend"], True),
        "input_monitoring": gate(session["input_monitoring"], "granted"),
        "device_ownership": gate(session["device"], "owned"),
        "attach_sent": gate(session["attach_sent"], True),
        "host_ack": gate(session["host_ack"], True),
    }
    reason = next((name for name, status in gates.items() if status != "pass"), None)
    return {
        "passed": reason is None,
        "reason": reason,
        "gates": gates,
        "input_monitoring": session["input_monitoring"],
        "device": session["device"],
    }


def latest_log():
    directory = Path.home() / "Library/Logs/PLANK/Client"
    logs = list(directory.glob("plank-client-*.log"))
    return max(logs, key=lambda path: path.stat().st_mtime) if logs else None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--log", type=Path, help="Client log; defaults to the newest PLANK Client log")
    args = parser.parse_args()
    path = args.log or latest_log()
    if path is None or not path.is_file():
        result = {"passed": False, "reason": "client_log_missing", "gates": {}}
    else:
        with path.open(encoding="utf-8", errors="replace") as source:
            result = check_lines(source)
    print(json.dumps(result, indent=2))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
