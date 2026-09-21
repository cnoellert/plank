"""Keep the Host candidate and its transport tests on the same rate policy."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class LinuxSenderPolicyTests(unittest.TestCase):
    def test_linux_feature_does_not_enable_macos_fec_or_diagnostics(self):
        manifest = (ROOT / 'protocol/plank-transport/Cargo.toml').read_text()
        self.assertRegex(manifest, r'(?m)^linux-fast-send = \[\]$')
        self.assertIn('macos-source-first = ["macos-fast-send", "kyproto/source-first-fec"]', manifest)
        self.assertRegex(manifest, r'(?m)^default = \[\]$')

    def test_only_linux_host_package_selects_new_policy(self):
        host = (ROOT / 'scripts/build/build-host-package-binaries.sh').read_text()
        self.assertIn('${PLANK_TRANSPORT_CARGO_FEATURES:-quinn-telemetry,linux-fast-send}', host)
        for name in ('build-client-package-binaries.sh', 'build-macos-client.sh',
                     'build-macos-transport.sh'):
            self.assertNotIn('linux-fast-send', (ROOT / 'scripts/build' / name).read_text())

    def test_real_transport_fixtures_do_not_force_old_pacer(self):
        native = (ROOT / 'protocol/plank-transport/src/native.rs').read_text()
        ffi = (ROOT / 'protocol/plank-transport/src/native_ffi.rs').read_text()
        for source in (native, ffi):
            selections = re.findall(r'datagram_pacer: ([^\n]+)', source)
            self.assertEqual(len(selections), 2)
            self.assertTrue(all('.outgoing_pacer()' in value for value in selections))

    def test_package_tests_match_compiled_features_and_target_directory(self):
        host = (ROOT / 'scripts/build/build-host-package-binaries.sh').read_text()
        self.assertIn('-DPLANK_TRANSPORT_CARGO_FEATURES="$plank_transport_cargo_features"', host)
        self.assertIn('tested_policies=("$plank_transport_cargo_features")', host)
        self.assertIn('tested_policies+=(quinn-telemetry)', host)
        self.assertIn('--features "$tested_features"', host)
        self.assertIn('export CARGO_TARGET_DIR="$build_dir/plank-transport-cargo"', host)
        self.assertIn('PLANK_TRANSPORT_CARGO_FEATURES="$tested_features"', host)
        self.assertIn('PLANK_TRANSPORT_CARGO_FEATURES="$plank_transport_cargo_features" \\', host)
        self.assertIn('host_fast_send_binary_gate=pass', host)

    def test_loopback_runners_accept_explicit_features(self):
        for name in ('run-plank-transport-native-loopback.sh',
                     'run-plank-transport-native-ffi-loopback.sh'):
            script = (ROOT / 'scripts/test' / name).read_text()
            self.assertIn('--features "$PLANK_TRANSPORT_CARGO_FEATURES"', script)
            self.assertIn('--locked --offline', script)

    def test_datagram_regressions_and_repetitions_are_required(self):
        host = (ROOT / 'scripts/build/build-host-package-binaries.sh').read_text()
        self.assertIn('--lib connection::datagrams::plank_tests', host)
        bootstrap = (ROOT / 'scripts/ci/dependencies/cargo.sh').read_text()
        self.assertIn('third_party/quinn-proto-0.11.17/Cargo.toml', bootstrap)
        script = (ROOT / 'scripts/test/run-plank-transport-native-loopback.sh').read_text()
        self.assertIn('for loss_trial in 1 2 3;', script)
        self.assertIn('set -euo pipefail', script)

    def test_vendor_telemetry_snapshot_regression_is_required(self):
        host = (ROOT / 'scripts/build/build-host-package-binaries.sh').read_text()
        self.assertIn('--features plank-telemetry', host)
        self.assertIn('--lib tests::plank_telemetry_snapshot_is_owned_and_preserves_queue_counters -- --exact', host)

    def test_loss_performance_gate_is_wired_into_required_matrix(self):
        native = (ROOT / 'protocol/plank-transport/src/native.rs').read_text()
        matrix = native.split('async fn native_raptorq_survives_progressive_transport_loss_at_150_mbps()', 1)[1]
        self.assertIn('PhasePerformance::measure(', matrix)
        self.assertIn('metrics.violations()', matrix)
        self.assertIn('performance_failures.is_empty()', matrix)
        self.assertIn('tokio::time::timeout_at(', matrix)
        self.assertIn('due + FRAME_DEADLINE', matrix)
        self.assertIn('first.checked_sub(1).map(|index| received[index])', matrix)
        self.assertIn('assert_eq!(media.payload, expected_payload)', matrix)
        self.assertIn('assert_eq!(fec.video_fec_source_symbols_unrecovered, Some(0))', matrix)
        script = (ROOT / 'scripts/test/run-plank-transport-native-loopback.sh').read_text()
        self.assertIn('${SC_NATIVE_CARGO_PROFILE:-release}', script)
        host = (ROOT / 'scripts/build/build-host-package-binaries.sh').read_text()
        self.assertIn('SC_NATIVE_CARGO_PROFILE=release', host)


if __name__ == '__main__':
    unittest.main()
