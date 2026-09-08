# Session-scoped local audio suppression

Work branch: `macos-audio-tap`, based on main `35ed81f`.

The operator wants the Mac's audio to play through the remote Client, without
simultaneously playing from the Mac's speakers. ScreenCaptureKit does not expose
a local-playback suppression setting. Its `excludesCurrentProcessAudio` setting
only excludes the capturing application's output from the recording.

Apple's public Core Audio process-tap API exposes `CATapMutedWhenTapped`:
local playback is suppressed while a client reads the tap, not by changing the
hardware volume or the user's selected output device. See
[Apple's tap guide](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps)
and [mute behavior](https://developer.apple.com/documentation/coreaudio/catapmutebehavior).
The macOS 27 SDK headers confirm these APIs. This is a proposed audio-only change;
ScreenCaptureKit video, VideoToolbox, transport, Opus and the Client remain intact.

## Qualification before integration

1. Build a separate, signed `PLANK Audio Tap Probe` on the dedicated Mac. Use a
   private stereo tap and private aggregate input. Record only counters/format/
   timing/RMS, never audio samples. Do not replace the installed Host.
2. Establish the separate system-audio TCC grant through the native prompt.
   No permission reset, synthetic approval, microphone access or default-device
   change. Check actual sample rate, chunking and timestamp continuity.
3. Prove local suppression and restoration after stop, failure and process death.
   Callback data alone cannot prove that physical speakers are silent; operator
   confirmation is a gate unless a trustworthy independent output test is found.
4. Integrate only after feasibility. Keep HAL callback work bounded and avoid
   allocation, encoding/network calls or a synchronous hop to the session owner
   that could deadlock during teardown. Preserve sample clock and A/V timing.
5. Qualify silence, active audio, output-device changes, disconnect/reconnect,
   logout/login, permission denial, new audio processes and owner isolation.
   A global probe tap is not approval to capture another user's audio in product.
6. Build a branch-qualified Host candidate and test through the existing Client,
   including an A/V soak. Do not silently retain simultaneous speaker playback
   as a successful fallback if the intended capture path fails.

## Current state

Standalone probe and build script prepared. No production code, installed Host,
saved audio settings or permissions have been changed. The probe has not yet
qualified capture, muting, crash cleanup or synchronization.
