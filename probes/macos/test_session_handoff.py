# SPDX-License-Identifier: GPL-3.0-or-later
"""Pure controller validation tests. No macOS commands or session mutations."""
import importlib.util
import json
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('handoff', Path(__file__).with_name('run-session-handoff.py'))
handoff = importlib.util.module_from_spec(spec)
spec.loader.exec_module(handoff)


class HandoffTests(unittest.TestCase):
    def test_designated_desktop(self):
        self.assertEqual(handoff.parse_snapshot('{"phase":"desktop","uid":501}', 501), ('desktop', 501))

    def test_sign_in(self):
        self.assertEqual(handoff.parse_snapshot('{"phase":"sign-in","uid":0}', 501), ('sign-in', 0))

    def test_unknown_pauses(self):
        self.assertIsNone(handoff.parse_snapshot('{"phase":"unavailable","uid":0}', 501))

    def test_other_user_refused(self):
        with self.assertRaises(ValueError):
            handoff.parse_snapshot('{"phase":"desktop","uid":502}', 501)

    def test_malformed_records(self):
        cases = [None, [], {}, {'phase': 'desktop', 'uid': True},
                 {'phase': 'desktop', 'uid': '501'}, {'phase': 'desktop', 'uid': -1},
                 {'phase': 'desktop', 'uid': 2**32}, {'phase': 'other', 'uid': 501},
                 {'phase': 'sign-in', 'uid': 501}, {'phase': 'desktop', 'uid': 0},
                 {'phase': 'desktop', 'uid': 501, 'command': 'ignored?'}]
        for record in cases:
            with self.subTest(record=record), self.assertRaises(ValueError):
                handoff.parse_snapshot(json.dumps(record), 501)

    def test_inventory_must_be_available(self):
        cases = [[], [{'id': 0}], [{'id': True}], [{'id': '1'}], [{'id': 1}] * 32]
        for displays in cases:
            with self.subTest(displays=displays):
                with self.assertRaises(RuntimeError):
                    handoff.Controller.parse_inventory(json.dumps({'displays': displays}))

    def test_inventory_valid(self):
        self.assertEqual(handoff.Controller.parse_inventory('{"displays":[{"id":12},{"id":15}]}'), {12, 15})


if __name__ == '__main__':
    unittest.main()
