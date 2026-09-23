#!/usr/bin/env python3
"""Tests for the macOS Wacom session preflight log gate."""

import importlib.util
from pathlib import Path
import unittest


SOURCE = Path(__file__).resolve().parents[2] / "scripts/test/check-macos-wacom-preflight.py"
SPEC = importlib.util.spec_from_file_location("wacom_preflight", SOURCE)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

START = "PLANK Wacom preflight: host_raw_hid=1 host_focus_suspend=1"
READY = [
    START,
    "PLANK Wacom preflight: input_monitoring=granted",
    "PLANK Wacom preflight: device=owned",
    "Mac Wacom attach sent: 2 interfaces, generation 1",
    "Mac Wacom attached; exclusive raw HID forwarding active",
]


class WacomPreflightTests(unittest.TestCase):
    def test_all_prerequisites_and_ack_pass(self):
        result = MODULE.check_lines(READY)
        self.assertTrue(result["passed"])
        self.assertTrue(all(value == "pass" for value in result["gates"].values()))

    def test_denied_permission_is_distinct_from_missing_device(self):
        result = MODULE.check_lines([START, "PLANK Wacom preflight: input_monitoring=denied"])
        self.assertEqual(result["reason"], "input_monitoring")
        self.assertEqual(result["gates"]["device_ownership"], "unverified")

    def test_capabilities_negotiate_independently(self):
        for flags, reason in (("0 host_focus_suspend=1", "host_raw_hid"),
                              ("1 host_focus_suspend=0", "host_focus_suspend")):
            with self.subTest(flags=flags):
                result = MODULE.check_lines(["PLANK Wacom preflight: host_raw_hid=" + flags])
                self.assertEqual(result["reason"], reason)

    def test_device_and_host_failures_are_separate(self):
        missing = MODULE.check_lines(READY[:2] + ["PLANK Wacom preflight: device=device_not_found"])
        self.assertEqual(missing["reason"], "device_ownership")
        rejected = MODULE.check_lines(READY[:4] + ["Mac Wacom host attach rejected: 5"])
        self.assertEqual(rejected["reason"], "host_ack")

    def test_latest_session_wins_and_release_invalidates(self):
        latest = MODULE.check_lines(READY + [START, "PLANK Wacom preflight: input_monitoring=denied"])
        self.assertEqual(latest["reason"], "input_monitoring")
        released = MODULE.check_lines(READY + ["Mac Wacom ownership released"])
        self.assertEqual(released["reason"], "device_ownership")
        reattached = MODULE.check_lines(READY + [
            "Mac Wacom ownership released",
            "Mac Wacom attach sent: 2 interfaces, generation 2",
            "Mac Wacom attached; exclusive raw HID forwarding active",
        ])
        self.assertTrue(reattached["passed"])

    def test_old_client_without_marker_cannot_pass(self):
        self.assertEqual(MODULE.check_lines(["Mac Wacom attached; exclusive raw HID forwarding active"])
                         ["reason"], "preflight_marker_missing")


if __name__ == "__main__":
    unittest.main()
