# PLANK Fullscreen Probe

macOS 27 / Apple Silicon diagnostic, not a replacement Client. Open the DMG
and launch **PLANK Fullscreen Probe**. No installation, Host connection, capture
permission, Accessibility permission or administrator access is required.
It changes no display modes, global preferences, services or PLANK settings.

For each of the five modes in order:

1. Choose the mode while windowed, then click **Enter Fullscreen**.
2. Look for the yellow top edge beside the camera notch, green left edge,
   pink right edge and orange bottom edge. Do they reach the panel edges?
3. Swipe to another Space and back. Does this behave like a native fullscreen
   app, and does coverage remain correct after returning?
4. Press Escape (or **Exit Fullscreen**). Verify normal window controls return.
5. Repeat entry once before selecting the next mode.

Please report which modes fill the panel and which allow swipe switching.
Use **Show Log in Finder** to locate the current log and share it privately.
Logs contain local wall time, mode, window/screen/backing geometry and focus
state, not keystrokes, credentials, window titles from other apps or screen
images. Directory: `~/Library/Logs/PLANK/FullscreenProbe/`.

Modes distinguish standard AppKit behavior, the ineffective 1.0.117 content
request, a documented NSWindow frame-constraint override, custom native
fullscreen animation, and the combination. These are hypotheses, not fixes.
All modes use native `toggleFullScreen`; no private APIs, gesture interception,
swizzling, display-mode changes or window-resizing timers are used. The timer
only measures geometry. Frame-matches-panel in the log is NOT a visual pass.

Quit with Command-Q or **Quit**. The process owns only its own windows; quitting
removes them. Delete the app/DMG to remove the probe; logs can be deleted
separately. Do not change PLANK Host or Client for this test.

## Hosted build

From clean/pushed `macos-fullscreen` source:

```bash
bash scripts/ci/dispatch.sh macos-fullscreen-probe true
```

This uses the existing protected disposable-runner signing flow. It compiles
only this AppKit file with SDK27, signs/notarizes/staples the DMG, and uploads
`diagnostics/<version>-<branch>/macos/` with source provenance and checksum.
No Qt, SDL, FFmpeg, Rust or product submodules are needed. Public push/PR jobs
do not build or sign this probe. GUI behavior still needs a real notched Mac.
