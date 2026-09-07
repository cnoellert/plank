# Native macOS Host components

Experimental work for macOS 27+. This directory is not an installable Host yet.
It does not replace or relocate the supported Linux Host under `sunshine-fork`.

`auth/account-verifier.m` uses Open Directory password verification, including
the framework's account/password-policy evaluation. The authenticated record's
UID and GeneratedUID must agree with macOS membership resolution. It returns
only a verified identity, never a capture/input grant or a macOS GUI login.

`auth/account-policy.h` authorizes only that identity's active desktop when
trusted before/after snapshots have the same nonzero session generation.
Root, invalid identity, cross-account attachment and session replacement fail
closed. These snapshots must come from the future trusted session owner; a
network request cannot supply them. LoginWindow authorization is not implemented
by this desktop-only function.

`auth/account-channel.m` runs that verifier in a short-lived re-exec child over
an inherited private socket. It validates both running code identities, checks
the parent peer, bounds attempts and transaction time, and kills/reaps failed
workers. It exposes no listener and does not require root. Mutable passwords
are cleared; framework-internal secret copies cannot be guaranteed erased.

`auth/authentication-session.m` implements the current Client's start/respond
conversation shapes and expiring, address-bound tokens. It requires trusted
desktop snapshots before verification and on every authorization. Tests cover
replay, expiry, peer mismatch, ownership replacement and bounded state. It is
now wired to the native HTTPS adapter and live Aqua desktop authority, with
one-use claims and revocable native QUIC stream leases.
LoginWindow authority, continuous stream revocation, deployment signing and
account-policy failure qualification remain gates before product acceptance.

`control/https-auth-server.m` uses Apple's Network/Security frameworks for the
existing start/respond contract over TLS 1.3. The narrow HTTP parser bounds
input and rejects ambiguous framing. `auth/desktop-authority.m` requires a real
matching Aqua session and never reactivates revoked authority. Public discovery,
authenticated fixed topology and an optional typed launch handler are implemented.
Discovery still advertises no ready media service. See
`docs/macos-control-plane.md` for limits and measured qualification results.

Build/test instructions: `docs/macos-build-runbook.md`. Overall architecture and
remaining gates: `docs/macos-host.plan`.

`media/preview-session.m` owns an authenticated one-shot native endpoint,
lifecycle/control timer, capture startup and ordered revocation/cleanup.
`media/screen-capture.m` connects the exact ScreenCaptureKit display to hardware
VideoToolbox Main10 using IOSurfaces; `media/native-video.m` validates and sends
complete Annex-B samples through the existing transport. This path has passed
combined system-audio capture using `media/opus-encoder.m` and authorized native
Opus submission through `media/native-audio.m`. Audio and video share the capture
owner's serial queue and revocation/drain lifetime; microphone capture is off.
The qualification launch now includes audio, but ordinary Client work remains
paused until the Host service contract is complete. These are short authenticated
loopback capture tests, not existing-Client playback,
performance soak or LoginWindow product lifecycle. Linux is unchanged.

`input/input-events.m` translates existing native input payloads to Quartz
events with dynamic point/pixel mapping and transactional held-state tracking.
`input/native-input.m` qualifies delivery through the existing revocable lease;
tests use a non-posting sink and real native QUIC. Neither is wired into the
A/V owner yet. Two own-window live tests pass on the unlocked desktop. See
`docs/macos-input.md`; do not advertise keyboard/mouse/cursor readiness from
component tests alone.
