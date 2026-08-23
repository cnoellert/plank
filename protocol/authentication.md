# PAM Authentication Protocol

## Security Boundary

StationConnect replaces persistent GameStream pairing with authentication for
every new connection. The network-facing Sunshine process never links to PAM,
runs PAM modules, or stores a password. A root-owned
`stationconnect-pam-broker` performs PAM operations through the dedicated
`remote-desktop` service and exposes only a Unix socket at
`/run/stationconnect/pam/auth.sock`. The socket is mode `0660`, owned by root and
the `stationconnect-auth` group.

The broker accepts only local `AF_UNIX` peers, records their kernel-supplied
UID, denies root login in code, and relies on the PAM service for the
`remote-desktop-users` allow group and host account policy. Prompt responses
must never appear in logs, process arguments, environment variables, URLs, or
crash reports.

## Broker Framing

Every message starts with the packed 20-byte header in
`src/auth/pam_broker_protocol.h`. Integer fields are little-endian. The header
carries magic `SCAP`, version `1`, message type, a nonzero 64-bit transaction
ID, and payload length. Payloads are capped at 64 KiB, individual strings at
4096 bytes, and lists at 64 entries.

The ordered lifecycle is:

1. Sunshine sends `begin` with length-prefixed username, remote-host label,
   and logical TTY strings.
2. The broker calls `pam_start()` and emits `challenge` messages containing
   every PAM prompt, error, and informational message with its original style.
3. Sunshine returns one `response` entry per message. Responses for
   informational messages are empty.
4. The broker calls `pam_authenticate()`, `pam_acct_mgmt()`,
   `pam_setcred(PAM_ESTABLISH_CRED)`, and `pam_open_session()` in order.
5. A `result` reports the failing phase and PAM status, or authenticated
   success. The socket remains open for the lifetime of a successful session.
6. `cancel`, EOF, or process death closes the PAM session, deletes credentials,
   and calls `pam_end()`.

Malformed, oversized, stale-transaction, or out-of-order messages terminate
the local connection. The local socket is not a client-facing API.

## HTTPS Authentication

When the broker socket is available, Sunshine disables pairing and client
certificates, requires TLS 1.3, and exposes `POST /stationconnect/auth/start`
and `POST /stationconnect/auth/respond`. The first body contains `username`;
the second contains an opaque `conversation_id` and a `responses` array.
Replies are non-cacheable JSON with `challenge`, `authenticated`, or `denied`
state. Successful authentication returns a 256-bit random bearer token bound
to the client address. Application list, asset, launch, resume, and cancel
requests require that token.

The first launch transfers the open PAM session into the RTSP stream lifetime.
Concurrent streams may share it. Releasing the last stream closes PAM and
invalidates the token; a later resume requires a new login. Pending
conversations expire after 120 seconds, and unclaimed tokens after 300 seconds.

## TLS and VPN Gate

Generate an RSA-3072/SHA-256 certificate with a DNS-only SAN using
`scripts/generate-stationconnect-certificate.sh`. The client accepts that
self-signed profile only when the kernel route uses the configured VPN
interface. Production deployments must set Sunshine's `bind_address` to the
VPN address and apply matching interface-scoped firewall rules. The
`STATIONCONNECT_VPN_INTERFACE` environment variable exists for explicit
qualification on a named non-ZeroTier interface; do not set it in production.
