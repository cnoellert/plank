# input: preserve absolute pointer positions across button and key barriers

## Summary

Replace the shared mutable absolute-pointer sample with positions stored in each
queued packet. The sender coalesces consecutive absolute moves only, stopping at
button/key barriers. A queued press can no longer inherit a later pointer
position, which previously broke rapid window dragging.

## Scope and dependencies

- Contribution: `0c82257`; target branch: `plank/client`.
- Relative mouse, keyboard encoding and transport framing are unchanged.
- This intentionally affects every Client using this shared input worker.
- The linked Client/root drafts consume this commit. Regression fixture:
  root `tests/session/native-input-wire.c`, exercised against the real worker.

## Verification

The native worker test checks queued press/move/release ordering, coordinates,
buttons, modifiers and scroll delivery. Live Mac-to-Linux cross-display dragging
works in both directions. Linux Client build/hardware regression and high-rate
motion saturation remain review gates; there is no blanket cross-platform pass.

## Review focus

Queue limits, allocation/error paths, sole-consumer assumptions and preservation
of ordering under producer concurrency. No credentials, privilege changes or
wire-format additions are involved.
