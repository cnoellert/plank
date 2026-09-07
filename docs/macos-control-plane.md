# macOS native control interface

Status: authentication-only component qualified over loopback TLS 1.3, including
a real account in the live Aqua session. Not an installable Mac Host or an
existing-Client streaming connection. Linux Host/Client behavior is unchanged.

## Native interface

`host/macos/control/https-auth-server.m` uses Network.framework and
Security.framework, not a port of the Linux HTTPS server. It accepts a supplied
administrator-controlled TLS identity and explicit local IPv4 address/port.
There is no implicit wildcard listener, plaintext fallback or automatic firewall
change. TLS is exactly 1.3 and the advertised application protocol is HTTP/1.1.
Core dumps must be disabled before constructing the interface.

Only `POST /plank/auth/start` and `POST /plank/auth/respond` are implemented.
The response JSON retains the current Client contract. Peer binding comes from
the accepted connection's actual IP address; IPv4-mapped IPv6 is normalized.
Forwarded headers cannot select the peer identity. No request, account, password
or token is logged. Responses use `Cache-Control: no-store`, `Pragma: no-cache`
and `Connection: close`.

The parser accepts one HTTP/1.1 POST with a decimal Content-Length and
`application/json`, with a 4096-byte header cap and 32768-byte body cap. The body
bound accommodates escaped JSON for the verifier's 4096-byte UTF-8 password
limit. It rejects duplicate/folded headers, ambiguous framing, Transfer-Encoding,
Expect, protocol upgrades, invalid header bytes and coalesced trailing requests.
It never serves a second request on a connection. Unknown paths and malformed
schemas fail without accessing desktop content.

There are at most eight admitted connections and one authentication operation
in flight; extra authentication work is rejected instead of accumulated in a
worker queue. A single watchdog closes expired connections after approximately
five seconds (100-ms checks). Worker verification itself is bounded to four
seconds. Failed sends/disconnected requests revoke newly issued tokens; stop
revokes all tokens after in-flight work. Completion clears mutable buffers and
breaks connection callback ownership cycles. Foundation/Network may retain
internal plaintext copies temporarily; complete framework-memory wiping is not
claimed. No raw request is persisted.

## Desktop authority

`host/macos/auth/desktop-authority.m` runs in the graphical user's Aqua context.
It requires agreement between Security session graphic access, CoreGraphics
console/login-complete state, the process UID, SystemConfiguration's console
user and membership UUID. An SSH invocation correctly receives no authority.

Each authority gets a random, nonzero lifetime generation. Every snapshot checks
the live OS state. A 250-ms watchdog and session-resignation/sleep notifications
provide additional revocation. A distributed screen-lock notification can only
revoke; it is defense-in-depth, not a public guarantee of lock-state detection
or proof that a newly launched process is on an unlocked screen. Notifications
cannot grant or reactivate authority. Once revoked or once identity diverges,
the object never re-arms: replacement requires a fresh agent and authentication.

This is a desktop-preview boundary, not the final machine-service/graphical-agent
authorization IPC. It does not log into macOS, unlock the screen, grant
LoginWindow access or complete continuous stream revocation. Lock/unlock,
fast-user switching, logout/relogin races and graphical-agent replacement still
need lifecycle qualification before product acceptance. Existing session-handoff
probe results do not automatically qualify this new integration.

## Qualification

Build with `scripts/build-macos-control.sh` as documented in the macOS build
runbook. It also runs the previous authentication tests. Current gates pass:

- 120 framing assertions, including every truncated prefix of a valid request;
- 53 authentication-state assertions, including individual-token revocation;
- TLS 1.3 authentication, rejection of TLS 1.2/plaintext/untrusted certificates,
  replay and malformed requests, slow-request expiry, eight-connection admission
  and recovery afterward, using a synthetic verifier only;
- real account verification through the isolated helper over loopback TLS in
  the actual Aqua context, with live owner matching and replay denial;
- actual Aqua authority present, explicit revocation latched, and SSH denied.

The qualification executable binds only `127.0.0.1` on an ephemeral port and
expires after 60 seconds. The runner removes its own temporary job, certificates,
keys and output files. The fixtures have the product's RSA-3072/SHA-256,
self-signed CA and DNS-only SAN shape; none enters the keychain/trust store.
The test client trusts the exact generated fixture through the OS OpenSSL CLI.
It is not the PLANK Client and does not qualify the Client's certificate-approval
UI, hostname policy or native QUIC launch.

## Next integration gate

Implement discovery/server information, topology and the explicit Apple
VideoToolbox HEVC Main10 **4:2:0** capability in the existing Client contract.
Then claim the authenticated session into native QUIC stream lifetime and feed
the qualified capture/encode path. Do not label Apple output as NVENC, 4:4:4 or
RGB identity. Keep takeover, input ownership and cleanup gates explicit.
Persistent administrator configuration, protected TLS-key loading, packaged
signing and required LoginWindow lifecycle remain unfinished.
