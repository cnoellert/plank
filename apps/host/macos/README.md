# Native macOS Host components

Experimental work for macOS 27+. A native Host executable/application now builds;
the product installer and ordinary Client connection are not qualified yet.
It does not replace or relocate the supported Linux Host under `sunshine-fork`.

`session/host-main.m` supplies machine and graphical entry points plus native
permission requests. `session/host-runtime.m` assembles the actual HTTPS
authentication and A/V/input stream owner; the former probe launch now uses it
instead of duplicating orchestration. The machine/graphical assembly passes
temporary launchd startup, TLS discovery/denial, shutdown and process replacement.
See `docs/architecture/macos-session-lifecycle.md` for deployment and remaining display/trust
gates. This is not yet an ordinary Client streaming acceptance result.

`session/agent-registry.m` and `agent-connection.m` implement the machine/agent
XPC ownership boundary: signing and kernel peer identity checks, exclusive
generations, irreversible revocation and cleanup-gated replacement. They pass
component and cross-process LoginWindow tests and are wired to the runtime's
remote authentication and capture lifetime. Persistent installation is pending. See
`docs/architecture/macos-session-lifecycle.md` for the contract and remaining integration.

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
input and rejects ambiguous framing. `auth/graphical-authority.m` requires an
explicit role and positive native session identity, never reactivating revoked
authority. The HTTPS probe explicitly retains its desktop-only role. Public discovery,
authenticated fixed topology and an optional typed launch handler are implemented.
Discovery still advertises no ready media service. See
`docs/architecture/macos-control-plane.md` for limits and measured qualification results.

Build/test instructions: `docs/development/build/macos-build-runbook.md`. Overall architecture and
remaining gates: `docs/development/plans/macos-host.plan`.

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
tests use a non-posting sink and real native QUIC. `input/quartz-input.m` uses a
private public-API event source and existing control permission. All are now
wired into the A/V owner with a blocking native receiver, a single bounded
handoff, authorized input release and receiver drain before endpoint destruction.
The integrated owner passes 300 checks/11 scenarios. Own-window live tests pass
on the unlocked desktop, including left/right modifiers and held-state cleanup. See
`docs/architecture/macos-input.md`; do not advertise keyboard/mouse/cursor readiness from
component tests alone.

The accepted Mac cursor contract is ScreenCaptureKit's embedded system/custom
cursor, with video-path latency. It is explicitly distinct from Linux local
cursor negotiation, not a fallback or codec inference. Own-window shape/motion
pixel checks pass; ordinary Client presentation and LoginWindow input remain
gates. See `docs/architecture/macos-input.md` and the next lifecycle section in the Mac plan.
