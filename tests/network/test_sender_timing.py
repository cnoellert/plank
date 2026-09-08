# SPDX-License-Identifier: AGPL-3.0-or-later
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    "sender_timing", Path(__file__).resolve().parents[2] / "scripts/analyze-sender-timing.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class SenderTimingTests(unittest.TestCase):
    def test_only_last_complete_trace(self):
        text = ("PLANK sender-timing begin rows=1\n"
                "PLANK sender-timing columns=frame,send_ns\n"
                "PLANK sender-timing 7,100\nPLANK sender-timing end\n"
                "PLANK sender-timing begin rows=2\n")
        self.assertEqual(module.read_trace(text)["rows"], [{"frame": 7, "send_ns": 100}])

    def test_reject_malformed(self):
        for text in ("", "PLANK sender-timing begin rows=1\nPLANK sender-timing end",
                     "PLANK sender-timing begin rows=1\nPLANK sender-timing columns=frame\n"
                     "PLANK sender-timing 1,2\nPLANK sender-timing end"):
            with self.assertRaises(ValueError):
                module.read_trace(text)


if __name__ == "__main__":
    unittest.main()
