#!/usr/bin/env python3
"""Build wiring only; macmetaloverlay executes the actual updater on macOS."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
CLIENT = ROOT / "apps/client"


class MetalOverlayWiring(unittest.TestCase):
    def test_native_regression_runs_in_every_client_build(self):
        build = (ROOT / "scripts/build/build-macos-client.sh").read_text()
        suites = build.split("for suite in ", 1)[1].split("; do", 1)[0].split()
        self.assertIn("macmetaloverlay", suites)
        fixture = (CLIENT / "tests/macmetaloverlay/test_macmetaloverlay.mm").read_text()
        self.assertIn('#include "../../app/streaming/video/ffmpeg-renderers/vt_metal.mm"', fixture)
        self.assertIn("renderer.updateOverlayTexture(", fixture)
        self.assertIn("delayedReplacement(UploadGate::Allocation)", fixture)
        self.assertIn("delayedReplacement(UploadGate::Upload)", fixture)
        self.assertIn("fixture.device->failAllocation = true", fixture)

    def test_notification_uses_tested_updater(self):
        source = (CLIENT / "app/streaming/video/ffmpeg-renderers/vt_metal.mm").read_text()
        callback = source.split("virtual void notifyOverlayUpdated", 1)[1].split("void updateOverlayTexture", 1)[0]
        self.assertIn("updateOverlayTexture(type, newSurface, overlayEnabled);", callback)


if __name__ == "__main__":
    unittest.main()
