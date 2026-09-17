# Clipboard review follow-up

Alan's September 17 review identified four Client and four Linux Host blockers.
The earlier green package builds did not demonstrate that these bugs were fixed.
The focused contributions remain in [Client PR #2](https://github.com/instinctual/plank-client/pull/2),
[Host PR #1](https://github.com/instinctual/plank-host-linux/pull/1), and
[parent PR #3](https://github.com/instinctual/plank/pull/3).

| Finding | Change | Regression evidence |
|---|---|---|
| Remote text crosses Client sessions | Track the remote pasteboard change count; clear only the still-owned remote value on the main thread. Worker teardown queues value-only cleanup, which a new session drains before reading. | Stop/start and fresh-object transitions; later local copies survive, including identical text. |
| Local A–B–A loses the second A | Treat a new pasteboard change count as local ownership; remove string-only echo suppression. | Both B and the subsequent A produce outbound offers. |
| Pending B survives newer Host A | Every newer complete offer replaces pending work; deduplicate against the current pasteboard on the main thread. | Applied A, queued B, newer A leaves A. A repeated after an unpolled local change is applied again. |
| Reconnect stops polling permanently | Restart the production SDL timer after successful Session reconnect; retain teardown cancellation. | Real timer and private pasteboard test sends a new copy after restart without a focus change; source guard checks the Session call sites. |
| Vanished X11 requestor exits the worker | Give clipboard traffic a dedicated XCB connection and consume checked property/notification errors. No process-wide Xlib handler is installed or changed. | Destroy requestors before servicing queued requests; subsequent paste succeeds; unrelated Xlib handler remains intact. |
| Losing PRIMARY erases CLIPBOARD | Keep shared text while either selection is still owned. | Another client claims PRIMARY; CLIPBOARD still pastes the remote value. |
| A 150 ms reply is discarded | Keep an outstanding conversion across 250 ms polls, correlated by a distinct requestor window, selection, target and property. | Delayed reply is forwarded; mismatched notifications are ignored. |
| Standard INCR receive is unsupported | Receive property chunks asynchronously, acknowledge deletion, complete on the zero-length terminator, and enforce the 1 MiB aggregate cap and five-second total deadline. | Exact-limit transfer, oversized advertisement, aggregate overflow, timeout and recovery. |

The standalone Host harness compiles the production backend and uses Xvfb on a
disposable Rocky 9.7 builder. Its only production stub is logging; the reviewed
baseline also receives a string-view-only common-header shim. X11 operations are
real. Four negative controls compile the exact reviewed Host revision and require
its requestor, ownership, delayed-reply and INCR cases to fail.

The Client suite uses a private named NSPasteboard. The timer test exercises the
production timer and clipboard bridge, while the Session source check guards
wiring; neither substitutes for a real network/renderer desktop handoff.

## Remaining acceptance

Keep the PRs under review. Do not equate the fixes or build results with Alan's
approval, and do not automatically resolve his review threads.

A scoped paired-system session must still verify both clipboard directions,
focus policy, repeated copies, disconnect into a different Host, large UTF-8
text, active desktop handoff/reconnect without a focus change, and continued
video/input operation. Machine testing and installation remain paused. No live
Flame acceptance or new macOS support claim follows from the isolated tests.
