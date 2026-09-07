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
now wired to the native HTTPS authentication adapter and live Aqua desktop
authority; it is not yet connected to QUIC stream lifetime.
LoginWindow authority, continuous stream revocation, deployment signing and
account-policy failure qualification remain gates before product acceptance.

`control/https-auth-server.m` uses Apple's Network/Security frameworks for the
existing start/respond contract over TLS 1.3. The narrow HTTP parser bounds
input and rejects ambiguous framing. `auth/desktop-authority.m` requires a real
matching Aqua session and never reactivates revoked authority. No discovery,
topology, capture or input endpoint is exposed by this adapter yet. See
`docs/macos-control-plane.md` for limits and measured qualification results.

Build/test instructions: `docs/macos-build-runbook.md`. Overall architecture and
remaining gates: `docs/macos-host.plan`. No capture, encoder or transport policy
is changed by this module.
