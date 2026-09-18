#!/usr/bin/env python3
"""Wiring gates; the native callback/queue regression runs on the Mac builder."""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
CLIENT = ROOT / "apps/client"


class MacKeyboardCapture(unittest.TestCase):
    def test_public_session_tap_only(self):
        source = (CLIENT / "app/streaming/mackeyboardcapture.mm").read_text()
        self.assertIn("CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap", source)
        self.assertIn("kCGEventTapOptionDefault", source)
        self.assertIn("AXIsProcessTrusted", source)
        self.assertNotIn("kCGHIDEventTap", source)
        self.assertNotIn("CGSSet", source)
        self.assertNotIn("CGEventPost", source)
        self.assertNotIn("LiSend", source)
        self.assertIn("QueueLimit = 256", source)
        self.assertIn("kCGEventTapDisabledByTimeout", source)
        self.assertIn("kCGEventTapDisabledByUserInput", source)
        self.assertIn("CFMachPortInvalidate", source)

    def test_focused_session_routes_once(self):
        source = (CLIENT / "app/streaming/input/input.cpp").read_text()
        self.assertIn("isSystemKeyCaptureActive() && hasMacStreamKeyboardFocus()", source)
        self.assertIn("MacWindow::hasKeyboardFocus(output.window)", source)
        self.assertIn("m_MacKeyboardCapture.reset();", source)
        keyboard = (CLIENT / "app/streaming/input/keyboard.cpp").read_text()
        self.assertIn("suppressSdlKeyEvent() || !hasMacStreamKeyboardFocus()", keyboard)
        session = (CLIENT / "app/streaming/session.cpp").read_text()
        self.assertIn("m_InputHandler->handleCapturedMacKeyEvent(event)", session)

    def test_mac_suite_is_mandatory(self):
        build = (ROOT / "scripts/build/build-macos-client.sh").read_text()
        self.assertIn("macapplication mackeyboardcapture plankpresentation", build)
        test = (CLIENT / "tests/mackeyboardcapture/test_mackeyboardcapture.mm").read_text()
        self.assertIn('#include "../../app/streaming/mackeyboardcapture.mm"', test)
        for name in ("commandTabAndSpaceAreQueuedOnce", "focusLossDiscardsQueuedKeys",
                     "deniedOrRevokedPermissionReleasesCapture", "disabledTapReleasesBeforeRecovery",
                     "overflowFailsOpenAndReleasesRemoteKeys", "sdlQueueFailureDoesNotSwallowInput",
                     "gesturesAndHardwareControlsStayLocal", "teardownFlushesOnlyItsOwnEvents"):
            self.assertIn(name, test)


if __name__ == "__main__":
    unittest.main()
