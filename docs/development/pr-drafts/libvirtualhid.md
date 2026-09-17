# linux: support portable Pause without changing F15

## Summary

Map portable Pause (`0x13`) to `KEY_PAUSE` for uinput and `XK_Pause` for XTest.
Retain the distinct F15 (`0x7E`) mappings. Extend capability, translation and
pipe-backed press/release tests and update the platform support documentation.

## Scope and dependencies

- Contribution: `b0cc3c8`; target branch: `plank/main`.
- Linux keyboard backend only; other keys, mouse and tablet paths are unchanged.
- Consumed by the linked Linux Host draft.

## Verification

Focused Linux backend tests passed in the pinned Rocky 9.7 build container.
The hardware Host recorded 23 complete Pause press/release pairs, with no
recorder errors, and the operator confirmed the expected action in Flame.
No system keymap or persistent application workaround was installed.

## Review focus

Portable versus scan-code paths, uinput advertised capabilities, and preserving
F15 as a separate key. No protocol version or privilege change is required.
