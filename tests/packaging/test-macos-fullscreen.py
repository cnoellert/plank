#!/usr/bin/env python3
"""Fullscreen wiring and required SDL patch gates; not live notch acceptance."""
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest

root = Path(sys.argv.pop(1)).resolve()
client = root / 'apps/client'
session = (client / 'app/streaming/session.cpp').read_text()
patch_file = client / 'app/deploy/macos/sdl-patches/0001-cocoa-opt-in-full-display-content-size.patch'


class NativeFullscreenTests(unittest.TestCase):
    def test_native_spaces_and_full_panel_opt_in(self):
        self.assertIn('SDL_SetHint(SDL_HINT_VIDEO_MAC_FULLSCREEN_SPACES, "1")', session)
        self.assertNotIn('SDL_SetHint(SDL_HINT_VIDEO_MAC_FULLSCREEN_SPACES, "0")', session)
        self.assertIn('SDL_SetHint("PLANK_MAC_FULLSCREEN_FULL_DISPLAY", "1")', session)
        info = plistlib.loads((client / 'app/Info.plist').read_bytes())
        self.assertIs(info['NSPrefersDisplaySafeAreaCompatibilityMode'], False)

    def test_dynamic_appkit_size_and_upstream_fallback(self):
        patch = patch_file.read_text()
        self.assertIn('willUseFullScreenContentSize:(NSSize)proposedSize', patch)
        self.assertIn('SDL_GetHintBoolean("PLANK_MAC_FULLSCREEN_FULL_DISPLAY", false)', patch)
        self.assertIn('window.screen.frame.size', patch)
        self.assertIn('return proposedSize;', patch)
        self.assertNotIn('visibleFrame', patch)
        self.assertNotIn('setFrame:', patch)

    def test_focus_loss_keeps_release_and_toolbar_cleanup(self):
        focus = session.rsplit('case SDL_EVENT_WINDOW_FOCUS_LOST:', 1)[1].split('case SDL_EVENT_WINDOW_FOCUS_GAINED:', 1)[0]
        self.assertIn('m_InputHandler->notifyFocusLost()', focus)
        self.assertIn('m_PlankToolbar->notifyFocusLost()', focus)
        source = (client / 'app/streaming/input/input.cpp').read_text()
        lost = source.split('void SdlInputHandler::notifyFocusLost()', 1)[1].split('void SdlInputHandler::notifyFocusGained()', 1)[0]
        self.assertIn('raiseAllKeys()', lost)
        self.assertIn('activateCompositorCursor()', lost)

    def test_fullscreen_events_refresh_controls_and_log_geometry(self):
        self.assertIn('case SDL_EVENT_WINDOW_ENTER_FULLSCREEN:', session)
        self.assertIn('case SDL_EVENT_WINDOW_LEAVE_FULLSCREEN:', session)
        self.assertIn('MacWindow::logGeometry(eventWindow)', session)
        mac = (client / 'app/streaming/macwindow.mm').read_text()
        self.assertIn('SDL_GetWindowSizeInPixels', mac)
        self.assertIn('screen.auxiliaryTopLeftArea', mac)
        self.assertIn('screen.auxiliaryTopRightArea', mac)

    def test_bootstrap_and_build_require_patch(self):
        for name, operation in [('bootstrap-macos-client-deps.sh', 'apply'),
                                ('build-macos-client.sh', 'verify')]:
            script = (root / 'scripts/build' / name).read_text()
            self.assertIn('prepare-macos-sdl.sh" ' + operation, script)

    def test_patch_apply_is_idempotent_and_verify_fails_closed(self):
        with tempfile.TemporaryDirectory(prefix='plank-sdl-gate-') as tmp:
            deps = Path(tmp)
            source = deps / 'src/SDL3-3.4.2/src/video/cocoa/SDL_cocoawindow.m'
            source.parent.mkdir(parents=True)
            # The exact old-side hunk is sufficient to test the patch gate,
            # without downloading an SDK or representing it as a native build.
            hunk = patch_file.read_text().split('@@', 2)[2].splitlines()[1:]
            source.write_text(''.join(line[1:] + '\n' for line in hunk if line.startswith((' ', '-'))))
            binary = deps / 'install/lib/libSDL3.dylib'
            binary.parent.mkdir(parents=True)
            binary.write_bytes(b'old library')
            def run(operation):
                return subprocess.run(['bash', str(root / 'scripts/build/prepare-macos-sdl.sh'),
                                       operation, str(root), str(deps)],
                                      stdout=subprocess.PIPE, stderr=subprocess.STDOUT).returncode
            self.assertNotEqual(run('verify'), 0)  # Unpatched source.
            self.assertEqual(run('apply'), 0)
            applied = source.read_bytes()
            self.assertEqual(run('apply'), 0)
            self.assertEqual(source.read_bytes(), applied)
            self.assertNotEqual(run('verify'), 0)  # Stale installed library.
            binary.write_bytes(b'PLANK native fullscreen content:')
            self.assertEqual(run('verify'), 0)
            source.write_text('unrelated source version\n')
            self.assertNotEqual(run('apply'), 0)
            self.assertNotEqual(run('verify'), 0)


unittest.main()
