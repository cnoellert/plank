# Ubuntu NUC Development Package Qualification

The unsigned `stationconnect-client` DEB was assembled on the dedicated Ubuntu
26.04 NUC and refreshed from clean Moonlight commit
`d2a5550c9eafc8cdb4334cd4c94fe5bc5b20dc3b`. The build explicitly exported
the private FFmpeg pkg-config and loader paths; a gate rejected an earlier
attempt that had accidentally linked Ubuntu's system FFmpeg 8.

The refreshed `0.1.0-0.3` amd64 package is approximately 18 MiB and has SHA-256:

```text
bd5ca8655c0d5d7759e24557cffe8d274f3411527cabcf0402d1160d643121f9
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

The package was not installed over the live qualification client. Clean
install, upgrade, rollback, removal, signing, and a separate debug/source
artifact remain Phase 9 release gates.
