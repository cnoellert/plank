# PLANK

PLANK builds one experimental Apple Silicon **Client** package for
macOS 15 and newer, including macOS 27. See
[the integration and acceptance notes](docs/development/macos15-integration-review.md).
The macOS Host remains macOS 27-only; integration does not imply release qualification.

This is a fork of Sunshine/Moonlight with deep changes relevant to secure VFX Remote Desktop workflows. 

## Status:
Linux Host/Client stable.
macOS Host is beta quality.
macOS Client is alpha.

## Hardware:
Ideal hardware for Ubuntu client would be an Intel based NUC generation 12 or higher, or an Intel N150 or higher mini-pc.  These support hardware HEVC 10bit 4:4:4 decode.

## INSTALL:
RockyLinux 9.7 Host:
dnf install ./plank-host-X.XXXX.1.el9.x86_64.rpm

## Ubuntu 26.04 Client:
apt-get install ./plank-client_1.0.89_amd64.deb


## Uninstall:
RockyLinux 9.7 Host:
dnf remove plank-host


## Ubuntu 26.04 Client:
apt-get remove plank-client


## macOS 27 Host:
sudo "/Applications/PLANK Host.app/Contents/Resources/uninstall.sh"


## Configuration:
RockyLinux 9.7 Host: /etc/plank/host.conf
[display] - If you are going to work hybrid, both in office with a physical display, and also remotely, leave startup_layout = physical.  If you are going to work purely headless, startup_layout = virtual.

Ubuntu 26.04 Client: /etc/plank/client.conf

When creating a bookmark to macOS Host on the Client, make sure to chose “macOS” in the Capture field. It defaults to NvFBC which is for Linux.

## Connectivity:
The current workflow expects a “direct connection”. There is no “broker”.  You are expected to provide your own VPN/LAN/WAN/Port Forward connection from the Client to Host.
The default is both TCP/UDP port 28989.

macOS Host has NOT been tested with Flame on Undies.  Photoshop and Pixelmator both successfully receive Wacom pressure with the PTH-8x0 series, without the need for Wacom driver on the macOS host, when connecting from Ubuntu Client.





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
histories and license notices as submodules. The Apple Silicon macOS Host
targets macOS 27; the Client targets macOS 15 and newer using SDK27. Its
qualification gates are separate from Linux. Windows is future
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
