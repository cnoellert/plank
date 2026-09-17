# macOS 15 Client integration

**Draft: dependency and qualification gates remain open.**

This root PR pins the Mac Client contribution and its common-C input-ordering
dependency, adds the explicit macOS 15 build option, and runs focused input,
fullscreen, target and packaging checks. It preserves the default macOS 27
build target and current upstream Quit/build behavior.

The Client adds two-screen Metal presentation, native fullscreen cleanup,
mouse/pen focus transfer and allowlisted USB Wacom forwarding. The common-C
change also prevents a burst of queued mouse positions from excluding mouse
and key releases. A deterministic worker test reproduces that failure on the
prior common-C PR head and passes on the fix.

Linux physical-monitor matching is not part of this PR. Its Host changes,
display helper, mode/primary negotiation, protocol vectors and packaging will
be reviewed together in separate draft [Client #4](https://github.com/instinctual/plank-client/pull/4)
and [root #7](https://github.com/instinctual/plank/pull/7) PRs. The independent
Pause-key library PR can be reviewed on its own.

The split Mac Client built on Apple Silicon/macOS 15 with 97 passing Qt results
and the native input-worker test. Earlier exact candidates passed live Mac
fullscreen drag/focus and Flame Wacom pressure/focus. Remaining gates include
bounded Wacom shutdown, intermittent left-click diagnosis, Ubuntu and macOS 27
qualification, reconnection/hotplug recovery, and final hosted builds. No
upstream merge or release has been performed.

See the [integration review](https://github.com/cnoellert/plank/blob/codex/macos15-pr-review/docs/development/macos15-integration-review.md) for the full
scope and evidence.
