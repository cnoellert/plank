# input: preserve absolute pointer positions across button and key barriers

## Summary

Replace the shared mutable absolute-pointer sample with positions stored in each
queued packet. The sender coalesces consecutive absolute moves only, stopping at
button/key barriers. A queued press can no longer inherit a later pointer
position, which previously broke rapid window dragging.

## Scope and dependencies

- Contribution: `b2b2b29` (following `0c82257`); target branch: `plank/client`.
- Relative mouse, keyboard encoding and transport framing are unchanged.
- This intentionally affects every Client using this shared input worker.
- The linked Client/root drafts consume this commit. Regression fixture:
  root `tests/session/native-input-wire.c`, exercised against the real worker.

## Verification

The native worker test checks queued press/move/release ordering, coordinates,
buttons, modifiers and scroll delivery. It also stalls the sender and queues
150 absolute moves before mouse/key releases. That case fails on `0c82257`
and passes with enqueue-time tail coalescing in `b2b2b29`, including 50
repeated runs and AddressSanitizer. Live Mac-to-Linux cross-display dragging
works in both directions. Linux Client build/hardware regression remains open;
the queue fix has not been established as the cause of every live click loss.

## Review focus

Queue limits, allocation/error paths, sole-consumer assumptions and preservation
of ordering under producer concurrency. No credentials, privilege changes or
wire-format additions are involved.

## Contribution set

Tracked by [integration PR #4](https://github.com/instinctual/plank/pull/4); [change inventory and verification record](https://github.com/cnoellert/plank/blob/codex/macos15-pr-review/docs/development/macos15-integration-review.md).
Consumed by [Client PR #3](https://github.com/instinctual/plank-client/pull/3).
