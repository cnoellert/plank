# Draft PR package

These are reviewable local drafts, not published PRs. See the
[integration review](../macos15-integration-review.md) for the full change
inventory, upstream reconciliation, evidence and remaining gates.

| Order | Target | Base | Draft body |
| --- | --- | --- | --- |
| 1 | instinctual/plank-common-c | plank/client | [Ordered input](common-c.md) |
| 2 | instinctual/plank-libvirtualhid | plank/main | [Pause](libvirtualhid.md) |
| 3 | instinctual/plank-client | main | [Mac Client](client.md) |
| 4 | instinctual/plank-host-linux | main | [Host display matching](host.md) |
| 5 | instinctual/plank | main | [Integration](root.md) |

Publish dependency branches first, replace local commit references with PR
links, and keep the parent drafts blocked until gitlinks are fetchable from
canonical upstream URLs. Refresh bases before pushing. Never force push or
change upstream default branches as part of this preparation. The accepted
installed binaries remain separate from the review candidate.

The generic launch/connection screenshots from the development record are
private captures. Do not attach them. Capture only sanitized bookmark controls
with a reserved example workstation before adding UI screenshots to the Client
or root PR. Distribution/signing material is not a PR attachment.
