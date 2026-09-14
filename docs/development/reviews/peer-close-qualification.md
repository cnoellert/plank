# Native peer-close qualification

September 13, 2026. Follow-up to the [fresh bootstrap](full-bootstrap-validation.md).
Runtime fix: `faa316a`; repeat runner: `3b8550f`. Shared package version1.0.98.

## Cause

The unchanged .97 Mac archive reproduced `result=1 state=7` in the real C ABI
loopback: `TIMEOUT`, endpoint `Stopped`, with no recorded error. This was not
evidence that QUIC failed to deliver its close packet.

KyNet's Quinn adapter maps orderly `ApplicationClosed` to `Ok(())`. Depending
on select ordering, PLANK either observed a failing receiver or successful
completion of `connection.closed()`. The worker classified that successful
completion as `Stopped`, even when no local stop had been requested. Receive
functions then returned `TIMEOUT` instead of the terminal runtime error. The
test correctly caught a runtime state-classification bug.

## Fix and boundaries

One shared worker-completion function now reserves `Stopped` for an explicitly
requested local stop. Otherwise it retains the original transport error or
reports orderly peer closure as a terminal failure. Existing failure handling
wakes waiters. Already queued control is still delivered before the error.
This covers active and authentication/setup endpoints on Linux and macOS.

No wire/ABI changes, new compatibility path, queue policy change, retry,
timeout increase or modification to Kyber/Quinn is involved. Encoding, media
submission, FEC, MTU and pacing remain unchanged.

## Validation

- Four deterministic regression tests: orderly closure during every live
  phase, explicit local shutdown, original error preservation, and queued
  control before terminal state.
- Linux transport suite: 21 pass, 2 existing integration tests ignored.
- macOS source-first suite: 23 pass, 2 existing integration tests ignored;
  2 source-first FEC tests pass.
- Real C ABI stress: **100/100 Linux and 100/100 macOS cases pass**, split
  equally between fingerprint-trusted active connections and certificate-
  approved setup connections promoted to media sessions.
- Each case checks video/audio/input/control delivery, final queued control,
  and terminal peer closure within the unchanged2-second bound. The runner
  stops at its first failure; it never retries a failed case.

Reproduce with the exact freshly compiled archive on the appropriate builder:

```bash
bash scripts/test/run-peer-close-stress.sh \
  /absolute/transport/release/libplank_transport.a /absolute/new-output 50
```

The earlier bootstrap failures remain in its evidence record. This follow-up
resolves them; do not retroactively relabel the old build as passing.
Evidence is retained outside Git under
`artifacts/qualification/peer-close-1.0.98/`.
No live Host session, privacy permission, install, reboot or loss injection was
used. Mainline package rebuild/transfer results are recorded in HANDOFF after
completion; transport tests are not full hardware/interactive acceptance.
