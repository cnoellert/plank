# Mac service and graphical-agent ownership

Experimental macOS/SDK 27 components under `host/macos/session`. These are
production IPC/ownership modules, not a new Client transport. They are not yet
wired to a persistent Host service, remote authentication or the A/V/input
owner. Qualification launchd jobs are temporary fixtures, not package inputs.

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

`agent-connection.m` verifies the machine's signing requirement and OS-reported
UID. Its trusted local-scope predicate must remain valid. Neither registration
nor its generation grants remote capture/input; those also require a verified
principal and current desktop/session authorization. The existing Aqua-only
authentication policy has not been widened to authorize LoginWindow.

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
It tests health, retirement and explicit empty-resource cleanup, not media or
remote login. Exact results and pending contexts are in HANDOFF.

Next wire verified remote admission, fresh per-agent grants, real capture/input/
display drain and stable control availability into these components. Keep
capture/encoding out of the machine coordinator. Persistent installation,
login/logout continuity and ordinary Ubuntu Client wiring remain unqualified.
