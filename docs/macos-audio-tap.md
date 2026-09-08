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

Standalone probe source `32ecdd7` compiled in a clean Mac worktree with macOS
SDK/deployment 27 and warnings-as-errors. Signing from SSH failed with
`errSecInternalComponent`, even after the operator unlocked the login keychain.
The same `codesign` operation succeeded in the desktop's Aqua launchd session.
Thus SSH signing access was the confirmed problem at that point; the earlier
claim that the keychain itself was locked was too strong. No signing identity,
key ACL or partition policy changes. The temporary signing job was removed.

The operator approved the separate system-audio capture permission. Initial
executable SHA256
`06cafe6ab240e209103e72792442f50639154ea830d4380c94620faa413c7b74`
passed silence and an audible signal test: 48000 Hz, stereo interleaved Float32,
flags9, 8 bytes/frame, 512-frame blocks, zero sample/host clock gaps. Maximum
callback age ~10.8 ms. This is capture callback age, not glass-to-glass latency.

Latest probe source `8b59b7e` passes the real QuickTime loop through unchanged
production `PLANKMacOpusEncoder`. The HAL callback copies PCM into a fixed
16-slot ring; the main-queue consumer builds CoreMedia buffers and encodes.
No recording is saved and no Client/transport is involved. The source timestamp
is Core Audio's actual host time, not a manufactured continuous timestamp.
Three ten-second runs, including two fresh restarts, passed: 2007–2018 Opus
packets/run, zero encoder failures, zero ring overflows, zero sample/host clock
gaps, nonzero captured signal. Maximum callback age across runs ~10.9 ms.
All IO stop/destroy, aggregate destroy and tap destroy calls returned success.
Source at `root-audio-tap-probe-3`, app at `audio-tap-probe-3` under the Mac work
root; executable SHA256
`277e158106e4eb8baf0e9368d8f0c64ffb3114164e538e141e6d249e726e350c`.
Build/signing ran in a one-shot Aqua job that has been removed.

No production code, installed Host or saved audio settings changed. Physical
speaker suppression/restoration, process-death restoration, owner isolation and
end-to-end synchronization remain unqualified. Asked whether the operator can
hear the Mac's physical speakers or only the PLANK stream, to arrange the
audible test. Do not replace the Host with this standalone feasibility probe.

Product scope must be explicit: SDK27 defines a global tap as *all processes*
and `privateTap` only as visibility to its creator. Neither documents same-user
isolation. Do not infer an authorization boundary from `privateTap`. Before
integration, qualify an authenticated-user process selection policy and preserve
LoginWindow behavior and cleanup-gated desktop transitions. Do not add a global
root tap to the sign-in worker or weaken ownership checks for audio.
