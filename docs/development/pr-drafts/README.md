# Draft contribution set

The Mac Client review is three coordinated draft PRs:

| Order | Repository | Draft | Purpose |
| --- | --- | --- | --- |
| 1 | common-C | [#3](https://github.com/instinctual/plank-common-c/pull/3) | Keep mouse positions ordered and deliver releases under position bursts |
| 2 | Client | [#3](https://github.com/instinctual/plank-client/pull/3) | macOS 15 target, two-screen presentation, input and USB Wacom |
| 3 | root | [#4](https://github.com/instinctual/plank/pull/4) | Pin the Client and its common-C dependency; build gates and evidence |

[libvirtualhid #1](https://github.com/instinctual/plank-libvirtualhid/pull/1)
is an independent approved Pause-key fix. The physical-display work is in
[Client #4](https://github.com/instinctual/plank-client/pull/4),
[root #7](https://github.com/instinctual/plank/pull/7) and
[Linux Host #2](https://github.com/instinctual/plank-host-linux/pull/2).
It is not a dependency of the Mac Client review. The display series remains
draft pending recovery and final Host-package qualification.

The [integration review](../macos15-integration-review.md) has the current
scope, evidence and gates. No upstream merge or release has occurred.
