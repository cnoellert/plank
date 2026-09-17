# Published draft PR package

Five linked draft PRs are published. The files here retain their review bodies.
See the [integration review](../macos15-integration-review.md) for the full
change inventory, upstream reconciliation, evidence and remaining gates.

| Order | Target | Base | Published draft | Body |
| --- | --- | --- | --- | --- |
| 1 | instinctual/plank-common-c | plank/client | [#3](https://github.com/instinctual/plank-common-c/pull/3) | [Ordered input](common-c.md) |
| 2 | instinctual/plank-libvirtualhid | plank/main | [#1](https://github.com/instinctual/plank-libvirtualhid/pull/1) | [Pause](libvirtualhid.md) |
| 3 | instinctual/plank-client | main | [#3](https://github.com/instinctual/plank-client/pull/3) | [Mac Client](client.md) |
| 4 | instinctual/plank-host-linux | main | [#2](https://github.com/instinctual/plank-host-linux/pull/2) | [Host display matching](host.md) |
| 5 | instinctual/plank | main | [#4](https://github.com/instinctual/plank/pull/4) | [Integration](root.md) |

Branches were published to contributor forks in dependency order after checking
all five upstream bases. Parent drafts remain blocked until the pinned commits
are available from canonical upstream URLs and the documented qualification
gates pass. Refresh bases before final merge. No upstream merge or release was
performed; the accepted installed binaries remain separate from the review
candidate. GitHub reporting a conflict-free merge is not test acceptance.

The generic launch/connection screenshots from the development record are
private captures. Do not attach them. Capture only sanitized bookmark controls
with a reserved example workstation before adding UI screenshots to the Client
or root PR. Distribution/signing material is not a PR attachment.
