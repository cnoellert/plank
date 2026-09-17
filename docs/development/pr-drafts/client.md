# macOS Client: two-screen presentation and USB Wacom

**Draft: Wacom shutdown, live input and cross-platform qualification remain open.**

This Client PR lets an Apple Silicon Mac running macOS 15 connect to PLANK as
a Client. It presents one Linux desktop across two Mac displays, including a
Retina screen, with native fullscreen windows. It also forwards an allowlisted
USB Wacom tablet to the Host for Flame pressure input. Mouse and pen focus can
follow the active fullscreen screen, and a held window drag can cross between
screens. The default macOS 27 target and upstream Quit behavior remain.

The linked [common-C PR #3](https://github.com/instinctual/plank-common-c/pull/3)
keeps mouse positions ordered around clicks and keys. Its latest queue fix
combines pending position updates before a burst can crowd out a button or key
release. The Linux Client must also be checked because this part is shared.

This PR does not change Linux Host physical monitors or add a Retina size
bookmark choice. Those changes are moving to a separate display series.

Earlier exact candidates passed live two-screen dragging, right-click focus,
window cleanup, and Flame pressure/pen focus. The split review branch built on
macOS 15 and passed 97 Qt results plus the actual input-worker fixture. The
latest source still needs final live acceptance, an Ubuntu Client regression,
macOS 27 qualification, interruption/hotplug tests, and a bounded asynchronous
Wacom shutdown path. Intermittent left-click loss remains under investigation.

See the [integration review](https://github.com/cnoellert/plank/blob/codex/macos15-pr-review/docs/development/macos15-integration-review.md) for commit and
test evidence. Keep this PR draft until those gates pass.
