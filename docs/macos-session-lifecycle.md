# Mac service and graphical-agent ownership

Experimental macOS/SDK 27 implementation under `host/macos/session`. The native
`host-main.m` executable now joins the production IPC boundary to HTTPS remote
authentication and the A/V/input owner through `host-runtime.m`. The executable
has no qualification timeout or synthetic verifier. Automatic installation,
virtual-display creation and cross-login replacement remain unfinished.
Qualification launchd jobs are temporary fixtures, not package inputs.

## Runnable Host assembly

`plank-host --machine MACH_SERVICE` runs the root ownership coordinator.
`plank-host --graphical MACH_SERVICE desktop|sign-in PRIVATE_DIRECTORY` runs
the explicitly selected graphical role, on that actual launchd graphical domain.
Same-product signing and root machine-peer checks remain mandatory. The agent
opens HTTPS only after admission; each authentication/media/input authorization
uses the independent local scope bound to the machine's current generation.
No capture or input occurs merely because a listener starts.

The runtime owns the HTTPS server, token owner and at most one native stream.
It uses the existing HEVC Main10, stereo Opus and absolute keyboard/mouse
implementations, with embedded cursor. Shutdown closes new launch admission,
drains the stream (including authorized held-input release), then waits for the
HTTP authentication/reply lanes to drain. It does not block the graphical loop
on endpoint construction or substitute a fixed sleep for cleanup completion.

This first assembly creates no virtual display or media child process. The
machine coordinator waits for the exact graphical process's kernel exit event
before releasing its exclusive slot; an IPC retirement acknowledgment is not
enough. Do not add the virtual-display child until its independent removal proof
is integrated into this condition. The short-lived account verification child
retains its separate bounded timeout and cannot capture or post input.

The experimental role-private startup directory is owned by that role's UID,
mode 0700. `host.plist`, `cert.der`, `key.der`, `cert.pem`, `key.pem` must each be
regular, non-symlink, mode-0600 files owned by the same UID. The plist has exactly
`Address` (explicit IPv4), `Port` (1–65535), `Name`, and `UUID`. PEM and DER must
represent the same certificate and PKCS#1 RSA private key; the native Security
identity validates the key/certificate pair. This is developer startup wiring,
not the final administrator configurator. Never copy the machine service's
private key into a user-readable directory to make this work. A stable public
trust identity across graphical roles remains a deployment/integration gate.

Opening the signed PLANK Host application requests its own Screen Recording
and Accessibility consent. Probe consent does not transfer across bundle IDs.
The permission window does not start a listener or a remote session.

## Trust boundary

`agent-registry.m` is the machine side. It installs the peer signing requirement
before activation; XPC checks it on every message. UID, PID and audit-session
ID come from XPC, never request fields. Supply an immutable, role-specific
designated requirement from protected product code, not a peer or environment.
Tests derive their own exact requirement; ad-hoc signing is not distribution
signing or the final installation policy.

The machine observer verifies graphical access for the peer audit session and
agreement with the current console account/phase. This selects a candidate;
it does not prove remote-user authorization or the agent's current on-console
permission. The graphical agent must independently validate its own scope,
permissions and geometry, with latched revocation on notifications.

`auth/graphical-authority.m` provides that local session check, replacing the
desktop-only observer. Its constructor requires an explicit desktop or sign-in
role; plain init and unknown roles are denied. Both require Security graphic
access, positive CoreGraphics on-console/UID/login state, and matching console
identity. Sign-in additionally requires actual root LoginWindow and
login-complete=false. Desktop requires the non-root account and membership UUID.
Neither an absent desktop nor root Background grants access. Notifications and
per-read checks latch revocation; no object can switch roles. Input/capture
consent and topology remain separate checks, not implied by this object.

`agent-connection.m` verifies the machine's signing requirement and OS-reported
UID. Its trusted local-scope predicate must remain valid. Neither registration
nor its generation grants remote capture/input; those also require a verified
principal and current desktop/session authorization.

## Scope-bound account admission

`authenticationScope:` returns only the exact currently admitted lease's phase
and generation. A desktop account is resolved from its OS-reported UID through
membership services, not request fields. Sign-in requires the positively
identified root LoginWindow agent and has an empty desktop account. Unknown,
foreign, retired or lost leases yield no authority; scope is checked again after
directory resolution. This method belongs on the registry owner queue and is
an authentication-lane operation, not a per-frame/per-input directory lookup.

The existing authentication/token owner now accepts an explicit graphical
scope. Sign-in admits a verified non-root remote principal; a desktop admits
only its verified UID/UUID owner. Phase or generation changes invalidate pending
challenges, unclaimed tokens and active stream leases. Reusing a generation
across phases cannot preserve access. Fresh authentication is required after
replacement; no serialized opaque stream lease or inherited root authority.
The standalone HTTPS probe explicitly selects the desktop-only role.

When the auth lane synchronizes a snapshot onto the registry queue, registry
callbacks must not synchronously call back into that auth owner. Revoke local
agent authority before scheduling drain; avoid reverse queue/lock ordering.
This admission snapshot does not replace the graphical agent's own positive
session and permission checks at capture/input delivery. Those checks and real
resource cleanup still need wiring into the persistent service.

On the graphical side, compose the auth provider as
`[agent bindGraphicalScope:[authority snapshot]]`. This is the connection's sole
cross-queue method. It binds fresh local identity to the machine generation
without synchronously entering the IPC queue or invoking callbacks under its
short lock. A local generation/phase/account change remains terminal even though
the returned generation is the machine's. Its two-second freshness deadline
expires independently of the IPC queue; neither a late response nor a restored
local snapshot can renew expired admission. Revocation clears the view before
notifying its owner. Only valid service acknowledgments refresh it.

The A/V/input owner's native-QUIC lifecycle test exercises this composition:
service revocation, service loss, stalled IPC and local-generation replacement
stop input/media and the endpoint. The delayed-capture case cannot retire its
agent until the actual stream owner reports its capture/input/endpoint drain.
These tests use synthetic capture/input and a real native endpoint, not live
ScreenCaptureKit, real display retirement or an installed service.

## Typed private protocol

Exact XPC dictionary keys/types are required. Numbers are uint64, version is 1.
No passwords, images, input, paths, process IDs or shell commands are accepted.

| Operation | Additional fields | Meaning |
| --- | --- | --- |
| Register, 1 | phase: 1 LoginWindow, 2 desktop | Machine scope and kernel peer identity must agree. |
| Check, 2 | generation, sequence | Validate this connection's lease. |
| Retired, 3 | generation, sequence | Agent reports local cleanup complete. |
| Revoke, 4 | generation | Machine-to-agent notification. |

Replies contain version/status and, on success only, generation. Status 0 is
success, 1 busy, 2 revoked/retired. Generation is a random nonzero uint64 bound
to the exact connection. Sequence starts at one and increases by exactly one.
Malformed, extra, unknown, replayed or one-way requests close the peer and revoke
any lease. Linux protocols and shared feature flags are unchanged.

One exclusive agent slot, at most four admitted links, five seconds to register.
The graphical side permits one outstanding request, a two-second reply/freshness
deadline and approximately two health checks per second. Both use their owner's
serial queue, without another worker/unbounded work queue. A 250-ms backup check
does not replace notification revocation or authorization at media/input delivery.

## Replacement ordering

Revoke first, drain media/input, retire the display owner, then acknowledge
retirement. The trusted machine controller independently verifies cleanup and
calls `completeRetirement` with the exact old lease object. Only that releases
the exclusive slot. Neither peer loss nor its acknowledgment proves that old
resources disappeared. Failure to prove cleanup remains blocked; no automatic
reboot or blind timeout-based grant. Late old callbacks cannot release a new slot.

XPC interruption is terminal for the graphical lease: never allow XPC's implicit
reconnection to renew authority. A late OK reply cannot revive a revoked agent.
Normal owners call `stop` explicitly; autorelease lifetime is not synchronous
shutdown. Deallocation also invalidates/cancels. Use autorelease draining on
long-lived serial work queues.

Outgoing create* connections must be activated before final release, even when
cancelled before registration; listener-delivered peers differ. Constructor
denial, never-started and early-local-denial tests cover this. Retirement replies
use a send barrier before cancellation so synchronous controller cleanup cannot
discard the acknowledgment.

## Qualification and next integration

The component suite uses real anonymous XPC with synthetic scope failures.
Native mode also verifies actual graphical/kernel identity. A separate harness
boots a temporary system Mach service and a different process in LoginWindow
or Aqua. A signed root Background peer falsely claiming graphical scope must
be rejected by the machine observer, before a real graphical agent is accepted.
It tests health, registry-bound authentication/stream-lease invalidation and
explicit empty-resource cleanup, not media or remote login. The synthetic
verifier is linked only into that harness; no real credentials or input are
involved. Exact results and pending contexts are in HANDOFF.

Next wire verified remote admission, fresh per-agent grants, real capture/input/
display drain and stable control availability into these components. Keep
capture/encoding out of the machine coordinator. Persistent installation,
login/logout continuity and ordinary Ubuntu Client wiring remain unqualified.
