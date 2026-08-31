# Code review — 2026-08-31

## Scope

This pass reviewed the packaged Rocky Linux host and Ubuntu client surfaces,
their first-party build definitions, package dependencies, network contacts,
credential creation, and inherited automation. The review deliberately avoids
broad renaming or removal of dormant non-Linux backends that are not compiled
into the qualified packages and may be useful for the planned macOS work.

## Removed surfaces

- Removed inherited GitHub workflows and bot configuration from both forks.
  They targeted unsupported AppImage, Steam Link, Windows, macOS, distribution,
  and upstream publication jobs and were the source of recurring failed-build
  notifications.
- Removed client calls to Moonlight compatibility, connection-test, and STUN
  services. Bookmark reachability and route-MTU selection remain local to the
  configured workstation path.
- Removed all client actions that opened upstream Help pages, plus the unused
  browser capability and Help-button plumbing.
- Removed the hidden game catalog, box-art manager, app-list CLI, and their
  unused QML/resources. The single `Desktop` application record remains part of
  the active launch/resume contract and is not a game catalog.
- Removed NVIDIA GeForce Experience version heuristics. Exact StationConnect
  host/profile capability negotiation remains authoritative.
- Removed the host's unused remote-file downloader, libcurl dependency,
  mutable application-art endpoint, and related tests and packaging inputs.
- Removed the host's shared-temporary first-run credential path. Credentials
  are created only at their configured private location.

## Security results

- TLS private keys are now opened with symlink rejection and mode `0600` from
  creation. The certificate is created as `0644`. Focused tests verify exact
  permissions and rejection of a symbolic-link destination.
- HTTP debug logging already redacts `Authorization` and `Cookie` headers. PAM
  passwords and bearer-token response bodies are not written by that logger.
- The root PAM broker remains the only PAM-broker client. Existing package
  gates continue to require private broker directories/sockets and prohibit an
  application-specific authorization group or user allowlist.
- No new high-severity issue remains open from this pass. Hardware-sensitive
  behavior still requires the normal candidate and live acceptance matrix.

## Retained by design

- Boost remains an active host dependency for logging, program options,
  networking utilities, locale, and other compiled host paths.
- `NvApp`, `/applist`, and the stable Desktop application ID remain because the
  client uses them to reserve and start the one authenticated Desktop session.
- mDNS remains an optional, administrator-controlled feature, defaulting off.
- Source comments that cite upstream bug reports or standards remain; they are
  engineering provenance and do not create runtime Help links or network
  traffic.
- Dormant Windows and macOS source is not part of the qualified Linux package.
  It is retained for future platform work and should be reviewed when those
  targets become active.

## Client media driver

The Ubuntu package now depends on `intel-media-va-driver-non-free`. It conflicts
with and replaces the free variant and requires Ubuntu's `multiverse`
component. The Development NUC exposes a matching 26.1.2 package. This does not
change exact-format decoder policy: H.264 High 10 4:4:4 identity still uses the
qualified FFmpeg software decoder because the Intel VA-API driver does not
expose that exact profile; supported exact HEVC profiles may use hardware.

## Validation completed before packaging

- Host package-binary build gates passed on `hardware-test-host`, including legacy HTTP
  surface absence and secure credential-write gates.
- The host, PAM broker, and supervisor compiled with GCC Toolset 14, CUDA 13.0,
  the retained Boost 1.89.0 source, and the prepared host FFmpeg tree.
- Thirty focused host tests covering file handling, PAM broker framing,
  web-auth lifetime/binding, and the fixed Desktop identity passed.
- Client and host diffs passed whitespace validation. The clean Development NUC
  client build/install and final RPM packaging remain release gates for the
  candidate commit.
