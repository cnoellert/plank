"""Probe isolation/wiring checks; not a replacement for AppKit live testing."""
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]


class FullscreenProbeTests(unittest.TestCase):
    def test_probe_does_not_change_product_or_system_state(self):
        source = (ROOT/'probes/macos/fullscreen-window.m').read_text()
        for forbidden in ('CGDisplaySetDisplayMode', 'CGEventPost', 'method_exchangeImplementations',
                          'setPresentationOptions', 'NSClassFromString', 'CGRequestScreenCaptureAccess'):
            self.assertNotIn(forbidden, source)
        self.assertIn('toggleFullScreen:sender', source)
        self.assertIn('self.fullPanelConstraint && self.fullscreenIntent', source)
        self.assertIn('return bypass ? frame : normal', source)
        self.assertIn('frame-matches-panel', source)
        self.assertIn('O_EXCL | O_NOFOLLOW, 0600', source)
        timer = source.split('scheduledTimerWithTimeInterval:')[1].split('}];')[0]
        self.assertNotIn('setFrame', timer)
        self.assertIn('snapshot:', timer)

    def test_package_has_independent_identity_and_distribution_gates(self):
        script = ROOT/'scripts/package/build-macos-fullscreen-probe.sh'
        subprocess.run(['bash', '-n', str(script)], check=True)
        source = script.read_text()
        for required in ('la.instinctual.plank.fullscreen-probe', '-mmacosx-version-min=27.0',
                         'NSPrefersDisplaySafeAreaCompatibilityMode=False',
                         'codesign --verify --deep --strict', 'notarytool submit',
                         'stapler validate', 'spctl --assess', "functional_validation='not-recorded'"):
            self.assertIn(required, source)
        for forbidden in ('bootstrap-macos-client-deps', 'sudo ', 'launchctl ', 'submodule update'):
            self.assertNotIn(forbidden, source)

    def test_probe_dispatch_is_explicit_signed_only(self):
        source = (ROOT/'scripts/ci/dispatch.sh').read_text()
        self.assertIn('[[ $product != macos-fullscreen-probe || $signed == true ]]', source)
        workflow = (ROOT/'.github/workflows/build.yml').read_text()
        ordinary = workflow.split('  macos:\n')[1].split('  macos-signed:\n')[0]
        self.assertNotIn('macos-fullscreen-probe', ordinary)
        signed = workflow.split('  macos-signed:\n')[1]
        self.assertIn("github.event_name == 'workflow_dispatch' && inputs.signed", signed)
        self.assertIn("inputs.product == 'macos-fullscreen-probe'", signed)
        self.assertIn('environment: macos-signing', signed)


if __name__ == '__main__':
    unittest.main()
