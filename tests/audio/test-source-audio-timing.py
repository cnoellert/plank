import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("source_timing", ROOT / "scripts/test/analyze-source-audio-timing.py")
timing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(timing)


def row(ms, lead=0, common=1, valid=1):
    return (f"PLANK A/V source timing: observe_ms={ms} common={common} valid={valid} "
            f"estimated_lead_us={lead} queue_ms=20 device_ms=10 resampler_us=500 "
            "gaps=0 correction_ppm=0\n")


class SourceTiming(unittest.TestCase):
    def test_steady(self):
        samples = timing.latest_samples([row(n * 1000, -25000) for n in range(120)])
        result = timing.summarize(samples)
        self.assertEqual(result["estimated_lead_ms_median"], -25)
        self.assertEqual(result["fitted_estimated_lead_change_ms_per_hour"], 0)

    def test_signed_drift(self):
        for direction in [-1, 1]:
            samples = timing.latest_samples([row(n * 1000, direction * n * 10) for n in range(120)])
            result = timing.summarize(samples)
            self.assertAlmostEqual(result["fitted_estimated_lead_change_ms_per_hour"], direction * 36)

    def test_reconnect_and_clock_reset(self):
        for boundary in ["PLANK A/V source timing begin: common=1", row(1, -100000)]:
            samples = timing.latest_samples([row(100000, 90000), boundary, row(1000), row(2000), row(3000)])
            result = timing.summarize(samples, 1)
            self.assertEqual(result["estimated_lead_ms_median"], 0)

    def test_independent_and_stale_clock(self):
        for common, valid in [(0, 1), (1, 0)]:
            with self.assertRaises(ValueError):
                timing.summarize(timing.latest_samples([row(1000, common=common, valid=valid), row(2000, common=common, valid=valid)]), 0)

    def test_incomplete(self):
        with self.assertRaises(ValueError):
            timing.latest_samples(["PLANK A/V source timing: common=1"])


if __name__ == "__main__":
    unittest.main()
