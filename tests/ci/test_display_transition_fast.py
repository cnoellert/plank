"""The display component job must compile without operating a desktop."""
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]


class DisplayTransitionFastTests(unittest.TestCase):
    def test_job_is_manual_without_runtime_or_signing_authority(self):
        workflow = (ROOT / '.github/workflows/build.yml').read_text()
        job = workflow.split('\n  linux-display-tests:\n')[1]
        self.assertIn("github.event_name == 'workflow_dispatch'", job)
        self.assertIn("inputs.product == 'linux-display-tests'", job)
        self.assertIn('rockylinux/rockylinux:9.7@sha256:', job)
        for forbidden in ('secrets.', 'self-hosted', 'sudo ', 'build-host-rpm.sh'):
            self.assertNotIn(forbidden, job)
        script = ROOT / 'scripts/ci/display-transition-fast.sh'
        subprocess.run(['bash', '-n', str(script)], check=True)
        source = script.read_text()
        self.assertIn('PLANK_DISPLAY_SANITIZERS=1', source)
        self.assertIn('"$host/src/session/host_supervisor.cpp"', source)
        self.assertIn('package_built=0 hardware_acceptance=not-performed', source)
        for line in source.splitlines():
            self.assertFalse(line.startswith(('"$build_dir/plank-host-supervisor"',
                                             'xrandr ', 'systemctl ', 'sudo ')))
        self.assertIn('linux-display-tests', (ROOT / 'scripts/ci/dispatch.sh').read_text())


if __name__ == '__main__':
    unittest.main()
