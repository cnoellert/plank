#!/usr/bin/env python3
"""No-display tests for mode bounds and the temporary layout transaction."""
import importlib.machinery
import importlib.util
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

path = Path(__file__).resolve().parents[2] / "packaging/host/linux/bin/plank-display-match"
loader = importlib.machinery.SourceFileLoader("display_match", str(path))
spec = importlib.util.spec_from_loader(loader.name, loader)
match = importlib.util.module_from_spec(spec)
loader.exec_module(match)

QUERY = """Screen 0: minimum 8 x 8, current 2560 x 1440, maximum 32767 x 32767
DP-0 connected primary 2560x1440+0+0 (normal left inverted right x axis y axis)
   existing-mode 60.00*
DP-2 connected (normal left inverted right x axis y axis)
DP-4 disconnected (normal left inverted right x axis y axis)
"""
BASELINE = "DPY-0: existing-mode @2560x1440 +0+0 {ViewPortIn=2560x1440, ViewPortOut=2560x1440+0+0}"


class DisplayMatchTest(unittest.TestCase):
    def test_bounds_and_injection(self):
        for mode in ["2056x1286", "4112x2572", "320x200", "8192x8192"]:
            self.assertEqual(match.dimensions(mode), tuple(map(int, mode.split("x"))))
        for mode in ["0x0", "02056x1286", "2056X1286", "2056x1287", "8194x2160",
                     "2056x1286;id", "2056x1286\n", "99999999999x200", "319x200", "320x198"]:
            with self.assertRaises(ValueError):
                match.dimensions(mode)

    def test_active_order_and_connected_spare(self):
        parsed = match.outputs(QUERY)
        self.assertEqual([item["name"] for item in match.ordered_outputs(parsed, 2)], ["DP-0", "DP-2"])
        parsed[1]["rect"] = (3456, 2234, 0, 0)
        parsed[0]["rect"] = (2560, 1440, 3456, 0)
        self.assertEqual(match.ordered_outputs(parsed, 2)[0]["name"], "DP-2")
        with self.assertRaises(ValueError):
            match.ordered_outputs(parsed, 3)

    def test_exact_even_width_inside_cvt_envelope(self):
        cvt = 'Modeline "3424x2214R" 500.00 3424 3472 3504 3584 2214 2217 2227 2280 +hsync -vsync\n'
        with patch.object(match, "command", return_value=cvt) as run:
            line = match.modeline(3420, 2214)
        self.assertEqual(run.call_args.args[0], [match.CVT, "-r", "3424", "2214", "60"])
        self.assertEqual(line[1:5], ["3420", "3472", "3504", "3584"])

    def test_primary_output_identity_survives_single_to_matched_transition(self):
        parsed = match.outputs(QUERY)
        for index, expected in [(0, ["DP-0", "DP-2"]), (1, ["DP-2", "DP-0"])]:
            self.assertEqual([item["name"] for item in match.ordered_outputs(parsed, 2, index)], expected)
        # The right-hand primary remains the same connector on a later match.
        parsed[0]["rect"] = (2560, 1440, 2056, 0)
        parsed[1]["rect"] = (2056, 1286, 0, 0)
        self.assertEqual([item["name"] for item in match.ordered_outputs(parsed, 2, 1)], ["DP-2", "DP-0"])
        self.assertEqual(match.ordered_outputs(parsed, 1, 0)[0]["name"], "DP-0")

    def test_inactive_primary_does_not_replace_the_existing_active_output(self):
        parsed = match.outputs(QUERY)
        parsed[0]["primary"] = False
        parsed[1]["primary"] = True
        self.assertEqual([item["name"] for item in match.ordered_outputs(parsed, 2, 1)], ["DP-2", "DP-0"])

    def test_primary_connector_is_not_assumed_to_be_first(self):
        parsed = match.outputs(QUERY)
        parsed[0]["primary"] = False
        parsed[1].update(primary=True, rect=(2560, 1440, 2560, 0))
        self.assertEqual(match.ordered_outputs(parsed, 1, 0)[0]["name"], "DP-2")
        self.assertEqual([item["name"] for item in match.ordered_outputs(parsed, 2, 0)], ["DP-2", "DP-0"])

    def test_inactive_outputs_use_primary_or_stable_fallback(self):
        parsed = match.outputs(QUERY)
        for item in parsed:
            item["rect"] = None
            item["primary"] = False
        self.assertEqual([item["name"] for item in match.ordered_outputs(parsed, 2, 1)], ["DP-2", "DP-0"])
        parsed[1]["primary"] = True
        self.assertEqual([item["name"] for item in match.ordered_outputs(parsed, 2, 0)], ["DP-2", "DP-0"])

    def transaction(self, fail=False, primary=-1):
        commands = []

        def run(argv):
            commands.append(argv)
            if argv == [match.XRANDR, "--query"]:
                return QUERY
            if argv[:3] == [match.NVIDIA, "--query", "CurrentMetaMode"]:
                return "id=7 :: " + BASELINE
            return ""

        with patch.object(match, "command", side_effect=run), \
             patch.object(match, "mutter_geometry", return_value={}), \
             patch.object(match, "modeline", return_value=["timing"]), \
             patch.object(match, "verify", side_effect=ValueError("mismatch") if fail else None) as verify:
            if fail:
                with self.assertRaisesRegex(ValueError, "mismatch"):
                    match.apply("123-456", ["2056x1286", "2560x1440"], primary)
            else:
                match.apply("123-456", ["2056x1286", "2560x1440"], primary)
                expected = {"DP-2": (2056, 1286, 0, 0), "DP-0": (2560, 1440, 2056, 0)} if primary == 1 else {
                    "DP-0": (2056, 1286, 0, 0), "DP-2": (2560, 1440, 2056, 0)}
                verify.assert_called_once_with(expected, None if primary == -1 else "DP-0")
        return commands

    def test_activates_real_modes_not_viewport_scaling(self):
        commands = self.transaction()
        apply = next(argv for argv in commands if "--fb" in argv)
        self.assertEqual(apply[2], "4616x1440")
        self.assertIn("PLANK-Match-123-456-0", apply)
        self.assertIn("2056x0", apply)
        panning = [apply[index + 1] for index, arg in enumerate(apply) if arg == "--panning"]
        self.assertEqual(panning, ["2056x1286+0+0", "2560x1440+2056+0"])
        self.assertFalse(any(argv[0] == match.NVIDIA and "--assign" in argv for argv in commands))

    def test_rejects_viewport_that_can_pan_despite_correct_current_position(self):
        query = QUERY.replace("2560x1440+0+0 (normal", "2056x1286+0+0 (normal")
        query = query.replace("x axis y axis)\n", "x axis y axis) panning 2560x1440+0+0\n", 1)
        expected = {"DP-0": (2056, 1286, 0, 0)}
        with patch.object(match, "command", return_value=query), \
             patch.object(match, "mutter_geometry", return_value={"DP-0": (*expected["DP-0"], 1.0, 0)}), \
             patch.object(match.time, "monotonic", side_effect=[0, 7]):
            with self.assertRaisesRegex(ValueError, "geometry"):
                match.verify(expected)

    def test_accepts_fixed_panning_domain(self):
        for suffix in ["", " panning 2560x1440+0+0"]:
            query = QUERY.replace("x axis y axis)\n", "x axis y axis)" + suffix + "\n", 1)
            with patch.object(match, "command", return_value=query), \
                 patch.object(match, "mutter_geometry", return_value={"DP-0": (2560, 1440, 0, 0, 1.0, 0)}):
                match.verify({"DP-0": (2560, 1440, 0, 0)})

    def test_nvidia_zero_exit_error_is_not_success(self):
        result = subprocess.CompletedProcess([], 0, "", "ERROR: Error assigning value (Attribute not available).")
        with patch.object(match.subprocess, "run", return_value=result):
            with self.assertRaisesRegex(ValueError, "NVIDIA rejected"):
                match.command([match.NVIDIA, "--assign", "CurrentMetaMode=" + BASELINE])

    def test_matches_either_primary_in_desktop_order(self):
        for index in (0, 1):
            commands = self.transaction(primary=index)
            apply = next(argv for argv in commands if "--fb" in argv)
            self.assertEqual(apply[-3:], ["--output", "DP-0", "--primary"])
            first_output = apply[apply.index("--output") + 1]
            self.assertEqual(first_output, "DP-2" if index == 1 else "DP-0")

    def test_primary_must_agree_with_compositor(self):
        expected = {"DP-0": (2560, 1440, 0, 0)}
        for primary, succeeds in [(True, True), (False, False)]:
            with patch.object(match, "command", return_value=QUERY), \
                 patch.object(match, "mutter_geometry", return_value={"DP-0": (2560, 1440, 0, 0, 1.0, 0, primary)}), \
                 patch.object(match.time, "monotonic", side_effect=[0, 7]):
                if succeeds:
                    match.verify(expected, "DP-0")
                else:
                    with self.assertRaises(ValueError):
                        match.verify(expected, "DP-0")

    def test_restore_does_not_claim_success_on_unchanged_metamode(self):
        with patch.object(match, "command", side_effect=["", "id=1 :: unchanged"]) as run:
            with self.assertRaisesRegex(ValueError, "did not take effect"):
                match.restore(BASELINE, "DP-0")
            self.assertEqual(run.call_count, 2)

    def test_restore_preserves_primary_and_verifies_it(self):
        with patch.object(match, "command", side_effect=["", "id=1 :: " + BASELINE, "", QUERY]) as run:
            match.restore(BASELINE, "DP-0")
            self.assertEqual(run.call_args_list[2].args[0], [match.XRANDR, "--output", "DP-0", "--primary"])

    def test_restore_can_clear_an_absent_primary(self):
        with patch.object(match, "command", side_effect=["", "id=1 :: " + BASELINE, "", QUERY.replace(" primary", "")]) as run:
            match.restore(BASELINE, "none")
            self.assertEqual(run.call_args_list[2].args[0], [match.XRANDR, "--noprimary"])

    def test_primary_index_rejected_before_mutation(self):
        with patch.object(match, "command") as run:
            for index in [-2, 2, 100]:
                with self.assertRaises(ValueError):
                    match.apply("123-456", ["2056x1286", "2560x1440"], index)
            with self.assertRaises(ValueError):
                match.apply("123-456", ["2056x1286"], 1)
            run.assert_not_called()

    def test_compositor_mismatch_restores_baseline_before_cleanup(self):
        for primary in (-1, 1):
            commands = self.transaction(fail=True, primary=primary)
            restore = commands.index([match.NVIDIA, "--assign", "CurrentMetaMode=" + BASELINE])
            removes = [index for index, argv in enumerate(commands) if "--delmode" in argv or "--rmmode" in argv]
            self.assertEqual(len(removes), 4)
            self.assertTrue(all(index > restore for index in removes))

    def test_cleanup_wont_delete_active_modes(self):
        query = QUERY.replace("existing-mode", "PLANK-Match-123-456-0")
        with patch.object(match, "command", return_value=query) as run:
            with self.assertRaises(ValueError):
                match.cleanup("123-456")
        self.assertEqual(run.call_count, 1)

    def test_invalid_requests_do_not_run_commands(self):
        with patch.object(match, "command") as run:
            for token, modes in [("../12", ["2056x1286"]), ("12-34", ["5120x2160"] * 2),
                                 ("12-34", []), ("12-34", ["320x200"] * 3)]:
                with self.assertRaises(ValueError):
                    match.apply(token, modes)
            run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
