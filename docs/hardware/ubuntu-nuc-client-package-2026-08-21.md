# Ubuntu NUC Development Package Qualification

The unsigned `stationconnect-client` DEB was assembled on the dedicated Ubuntu
26.04 NUC and refreshed from clean Moonlight commit
`d2a5550c9eafc8cdb4334cd4c94fe5bc5b20dc3b`. The build explicitly exported
the private FFmpeg pkg-config and loader paths; a gate rejected an earlier
attempt that had accidentally linked Ubuntu's system FFmpeg 8.

The refreshed `0.1.0-0.4` amd64 package is approximately 18 MiB and has SHA-256:

```text
3b17ed4dedb04dd6c5b571d49680544f247ae59feb92583d28cfbdbdacd0140b
```

It installs Moonlight under `/usr/libexec/stationconnect/`, the launcher and
desktop entry, and globally enabled graphical-session user-unit integration.
This build includes native client-display resolution selection, direct
password-on-stdin launch, the per-workstation display selector, and cached
output topology. Scaled span remains the multi-monitor default. Opt-in A/V
clock telemetry is also present and remains disabled unless
`STATIONCONNECT_AV_SYNC_TELEMETRY=1` is set.
FFmpeg 9.0.1 SONAMEs `libavcodec.so.63`, `libavutil.so.61`,
`libswscale.so.10`, and `libswresample.so.7` are isolated in the package's
private `lib/` directory. Ubuntu's loader configuration and system FFmpeg are
not modified.

Qualification passed:

- clean-source and pinned FFmpeg archive checksum gates;
- dependency generation across Moonlight and every bundled FFmpeg ELF object;
- package extraction, ownership/mode, symlink, md5sum, and desktop-file checks;
- exact private-library resolution with no unresolved runtime dependency;
- `apt-get --simulate install` with all dependencies already satisfiable;
- an extracted-package, offscreen `--help` smoke test and simulated APT install;
- two independent package assemblies with byte-identical DEB SHA-256 results.
  Compiler file-prefix mapping removes source and build paths from the packaged
  executable.

The package was installed on the dedicated NUC and its user service restarted
successfully. The running executable is
`/usr/libexec/stationconnect/moonlight`; process mappings resolve all four
bundled FFmpeg 9 libraries from `/usr/libexec/stationconnect/lib/`. The first
packaged scaled-span session connected successfully and retained opt-in A/V
telemetry. Clean-image install, upgrade, rollback, removal, signing, and a
separate debug/source artifact remain Phase 9 release gates.

The 0.4 package intentionally retains the byte-identical qualified Moonlight
binary while synchronizing its version with the host's UHID initialization
fix. It was rebuilt against the recorded clean `d2a5550c` source and the pinned
FFmpeg archive, then installed on the NUC. The stale per-user service copy and
development-path drop-in were retired; systemd now loads only the packaged
unit and `/usr/bin/stationconnect-client` launcher.

A fresh password-on-stdin Desktop launch using only packaged executables
authenticated as session `c11`. Moonlight held file descriptors for the two
physical PTH-660 interfaces (`/dev/hidraw2` and `/dev/hidraw3`), and the host
created matching `056a:0357` Pen, Pad, and Finger devices. This confirms exact
raw-HID forwarding is restored with the synchronized 0.4 packages.

## Fresh-install dependency correction — 2026-08-22

A clean Ubuntu 26.04 Desktop installation exposed a package metadata gap in
0.7: Qt's ELF libraries were present, but `QtQuick.Controls` failed to load
because QML imports are invisible to `dpkg-shlibdeps`. Revision 0.8 explicitly
depends on the Qt Quick, Controls, Layouts, and Window QML modules. It also
uses Debian's standard user-service maintainer helpers to enable future
graphical-session launches and remove that state on purge.

The corrected DEB was assembled twice on the development NUC from clean
Moonlight commit `2404550e` and the pinned private FFmpeg 9.0.1 runtime. Both
assemblies produced SHA-256
`d6ca95a28cb925aed48c2d93ef5089dc2a161aa5d242482343752498eb2074b5`.
Manifest, private-runtime, dependency, maintainer-script syntax, and
reproducibility gates passed. The production-workflow NUC was used only for
read-only diagnosis; installation and verification are operator-owned.

Revision 0.9 additionally requires Ubuntu's open
`intel-media-va-driver`. A fresh installation had the generic `libva`
libraries, an active `i915` kernel driver, an accessible render node, and no
`iHD_drv_video.so`; without the implementation driver Moonlight correctly
reported that hardware-accelerated decoding was unavailable. The development
NUC's qualified VA-API path uses the same open driver release.
