# Security and reliability backlog

Captured September 21, 2026 from Alan's cross-repository review. These are
reported findings awaiting independent reproduction and implementation review.
Temporary worktree prefixes from the review have been removed; paths below are
relative to the PLANK root checkout.

## Priority order

| ID | Severity | Area | Finding | State |
| --- | --- | --- | --- | --- |
| SR-1 | High | Client trust | Host identity is not established before credentials are sent | Backlog |
| SR-2 | High | Kymux reliable data | Peer length can request an excessive allocation | Backlog |
| SR-3 | High | Linux authentication | A stalled PAM operation can block other authentication work | Backlog |
| SR-4 | High | Client rendering | Renderer shutdown can lose its wake and hang indefinitely | Backlog |
| SR-5 | Medium | Native transport | Queue overflow can make receive discard the wrong item | Backlog |
| SR-6 | Medium | FEC receiver | Malformed FEC input can panic the receiver | Backlog |
| SR-7 | Medium | Native transport | Cancellation does not interrupt connection establishment | Backlog |

## SR-1 — Verify Host identity before authentication

The Client accepts a self-signed certificate that matches the PLANK certificate
profile while ignoring hostname mismatch. An attacker who can redirect the
initial connection may present another matching certificate and receive the
authentication exchange. Pinning the certificate after authentication does not
protect the credentials already sent.

- Source: `apps/client/app/backend/nvhttp.cpp:491`
- Recommended direction: require administrator-provisioned trust or an explicit
  verified first-use decision before transmitting credentials.
- Acceptance boundary: a new or changed Host identity cannot receive a username,
  password or authentication token before the user or administrator establishes
  trust; reconnects still work without weakening pin validation.

## SR-2 — Bound reliable-data allocations and queued bytes

The reliable-data decoder reads a peer-controlled 32-bit payload length and
allocates it immediately. The outgoing PLANK size limit does not constrain this
incoming parser, allowing a malicious or faulty peer to request an allocation
approaching 4 GiB.

- Source: `third_party/kyber-kymux/kymux-types/src/data.rs:42`
- Recommended direction: reject oversized lengths before allocation and enforce
  a total queued-byte budget in addition to packet-count limits.
- Acceptance boundary: boundary and oversized lengths fail deterministically
  without large allocation, queue growth or process termination.

## SR-3 — Remove blocking PAM work from the shared authentication lock

Authentication holds the shared authentication-manager mutex while waiting for
the PAM broker. The broker read has no operation deadline. A stalled PAM or SSSD
backend can therefore block later authentication and token operations even after
the Client gives up.

- Sources: `apps/host/linux/src/auth/web_auth.cpp:97` and
  `apps/host/linux/src/auth/pam_broker_protocol.h:273`
- Recommended direction: perform blocking PAM work outside the shared state
  lock, with a bounded deadline and cancellation.
- Acceptance boundary: a deliberately stalled PAM exchange times out, releases
  resources and does not block an independent authentication or token request.

## SR-4 — Make renderer shutdown wake and join safely

The renderer destructor changes an ordinary stop flag without the queue mutex,
wakes the render thread and joins it. The worker can check the predicate, miss
the wake and enter an unbounded wait. The unsynchronized flag also creates a C++
data race.

- Source: `apps/client/app/streaming/video/ffmpeg-renderers/pacer/pacer.cpp:88`
- Recommended direction: protect the stop predicate with the same mutex used by
  the condition variable and make predicate update plus wake follow the standard
  condition-variable protocol. Making only the Boolean atomic is insufficient.
- Acceptance boundary: repeated destruction at every wait boundary completes
  within a fixed deadline under thread sanitizer or an equivalent stress test.

## SR-5 — Atomically claim receive-queue entries

Video and audio receive currently clone the front item, release the lock, copy
its payload, then reacquire the lock and remove the front item. A producer can
evict the cloned item during overflow, causing the consumer to remove a different
entry and create unreported extra loss.

- Source: `protocol/plank-transport/src/native_ffi.rs:1562`
- Recommended direction: validate caller capacity and claim the same queue item
  atomically, then copy the claimed payload outside the lock.
- Acceptance boundary: a deterministic overflow interleaving delivers or drops
  each identity once and all drops are represented in telemetry.

## SR-6 — Reject malformed FEC packets without panic

The router accepts a datagram containing an endpoint identifier while the FEC
receiver assumes the complete header exists. Peer-provided RaptorQ parameters
also reach decoder construction without sufficient validation; a zero symbol
size is one known bad input.

- Source:
  `third_party/kyber-kymux/kyproto/src/protocol/driver/av/video_unreliable_fec.rs:623`
- Recommended direction: validate header length, parameter ranges, internal
  consistency and allocation bounds before decoder construction.
- Acceptance boundary: truncated headers, zero or extreme symbol sizes and
  inconsistent parameters return controlled protocol errors under fuzzing and
  targeted regression tests.

## SR-7 — Extend cancellation through connection establishment

Stopping a native transport sets a flag and joins the worker, but handshake and
connection establishment do not observe that cancellation. Disconnect during
startup can therefore wait for handshake deadlines.

- Source: `protocol/plank-transport/src/native_ffi.rs:1920`
- Recommended direction: race establishment against the same cancellation path
  used by active streaming while retaining the bounded connection-close drain.
- Acceptance boundary: cancellation during DNS, socket setup, TLS and protocol
  handshake returns within a fixed short deadline without leaking a worker.

## Suggested execution slices

1. **Trust boundary:** SR-1, including migration behavior for existing pins.
2. **Untrusted input bounds:** SR-2 and SR-6, with allocation and fuzz tests.
3. **Bounded shutdown and authentication:** SR-3, SR-4 and SR-7.
4. **Queue correctness:** SR-5 with deterministic overflow interleavings and
   telemetry assertions.

Each slice should land in its owning repository or dependency first, followed
by root gitlink updates and cross-platform qualification. Do not combine these
fixes with the visionOS client feature series.
