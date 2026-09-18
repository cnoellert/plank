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

## Maintainer follow-up

The combined review also found and corrected:

- A manually retained `NSString` in the macOS pasteboard writer. Its ownership
  is now balanced on both successful and failed pasteboard writes; the Client
  uses manual reference counting, not ARC.
- Linux Clients advertised the clipboard feature despite having no clipboard
  implementation. The launch mask now includes it only on macOS. The shared
  topology suite checks this on both Linux and macOS builds.
- The Host's fixed 250 ms worker sleep could exhaust the five-second INCR
  deadline on valid 1 MiB text sent in 16 KiB chunks. Active transfers now wait
  on the dedicated XCB connection, including events already buffered by XCB.
  New conversions remain rate-limited, idle waits remain bounded, and the size
  and total transfer deadline are unchanged. The production-backend fixture
  covers worker cadence, idle waiting, reply wakeup and request rate limiting.
  A fixed-sleep negative control must fail the large-transfer case.
- Contributor dependency URLs were restored to the maintained PLANK repos.
  Host common-C now uses `88fd5ac594ce9fa8b7e01530a7830aba3fc0b986` and Client
  common-C uses `16a7a503b2cfafad12faeedbc67257f7a1c0deb8`, preserving the
  already-merged clipboard ABI tests and input queue fix. Current Client main,
  including its accepted mDNS dependency update, is retained. These are exact
  pins, not branch-tip dependencies.

The clipboard feature remains `0x400000`; matched physical-mode work reserves
its own bit separately. No protocol wire-format changes or new clipboard
platform claims are introduced by these follow-ups.

## Remaining acceptance

Keep the PRs under review. Do not equate the fixes or build results with Alan's
approval, and do not automatically resolve his review threads.

A scoped paired-system session must still verify both clipboard directions,
focus policy, repeated copies, disconnect into a different Host, large UTF-8
text, active desktop handoff/reconnect without a focus change, and continued
video/input operation. Machine testing and installation remain paused. No live
Flame acceptance or new macOS support claim follows from the isolated tests.
