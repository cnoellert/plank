# PLANK

PLANK is a low-latency remote-workstation system with Linux and macOS Hosts
and Clients. This repository builds independently of private infrastructure.

The project is in late integration and production hardening. The supported
Linux baseline is currently a Rocky Linux 9.7 host with NVIDIA graphics and an
Ubuntu 26.04 client. Hardware-sensitive behavior—including exact-format video,
Wacom input, display topology, packet-loss recovery, and session takeover—must
pass the repository's qualification gates before release.

## Repository map

| Path | Purpose |
| --- | --- |
| `apps/host/linux/` | Host capture, encoding, authentication, display, and input services |
| `apps/host/macos/` | Native macOS capture, VideoToolbox encoding and session services |
| `apps/client/` | Client decoding, presentation, input, toolbar, and connection UI |
| `protocol/` | PLANK-owned transport, schemas, feature negotiation, and protocol documentation |
| `packaging/<product>/<os>/` | Product/platform installation integration |
| `artifacts/packages/` | Ignored packages grouped by version and operating system |
| `tests/` | Focused automated tests grouped by subsystem |
| `probes/` | Hardware and network qualification tools |
| `scripts/` | Reproducible build, packaging, and validation entry points |
| `docs/` | Architecture, security, build, and qualification documentation |
| `third_party/` | Pinned external source required by PLANK components |

The Linux Host and shared cross-platform Client retain their upstream Git
histories and license notices as submodules. macOS targets macOS 27 and Apple
Silicon; its qualification gates are separate from Linux. Windows is future
work, not a currently supported product. See the
[platform matrix](docs/development/platforms.md).

## Start here

- [Documentation index](docs/README.md) and [contributor guide](CONTRIBUTING.md).
- [Building a fork from source](docs/development/build/from-source.md), including macOS signing.
- [Package catalog layout](artifacts/README.md).
- [`docs/development/acceptance-criteria.md`](docs/development/acceptance-criteria.md) defines the
  current Linux product acceptance gates.
- [`protocol/`](protocol/) and the focused documents under [`docs/`](docs/)
  define the current subsystem contracts and architecture.
- [`HANDOFF.md`](HANDOFF.md) records the exact current source, artifacts,
  builder state, completed validation, and next test.
- [`docs/development/build/release-build-runbook.md`](docs/development/build/release-build-runbook.md) is mandatory
  reading before producing a candidate package.
- [`docs/development/build/builder-vm-bootstrap.md`](docs/development/build/builder-vm-bootstrap.md) defines the
  canonical Host and Client builder environments.
- [`AGENTS.md`](AGENTS.md) contains repository-specific engineering rules.

Host RPMs and Client DEBs are built on separate, dedicated builder VMs. Do not
infer build paths or dependencies from an arbitrary checkout; use the path
contract and pinned inputs documented in the builder bootstrap and release
runbook.

## Qualification

The repository qualification build and automated test suite is:

```bash
source ~/.config/plank-builder/paths.env
qualification_build="$PLANK_WORK_ROOT/qualification"
cmake -S . -B "$qualification_build" -DCMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build "$qualification_build" --parallel
ctest --test-dir "$qualification_build" --output-on-failure
```

Hardware tests and package acceptance require the additional procedures and
qualified machines documented in the release runbook.

## Licensing

PLANK contains components with different upstream histories and licenses.
Preserve the license and attribution files in each maintained fork and vendored
dependency. The PLANK transport boundary is AGPL-3.0-or-later.
