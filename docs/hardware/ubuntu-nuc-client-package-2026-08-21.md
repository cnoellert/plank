# Ubuntu NUC Development Package Qualification

The first unsigned `stationconnect-client` DEB was assembled on the dedicated
Ubuntu 26.04 NUC from clean Moonlight commit
`d269c3b38a25d6fb8f41f4533135287b7f0ea49c`. The build explicitly exported
the private FFmpeg pkg-config and loader paths; a gate rejected an earlier
attempt that had accidentally linked Ubuntu's system FFmpeg 8.

The final `0.1.0-0.1` amd64 package is 18 MiB and has SHA-256:

```text
194a7f9b40901f0084ad2a2036d3875f1102181e153e335f855afadc1c27e431
```

It installs Moonlight under `/usr/libexec/stationconnect/`, the launcher and
desktop entry, and globally enabled graphical-session user-unit integration.
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
- two identical builds with byte-identical SHA-256 results.

The package was not installed over the live qualification client. Clean
install, upgrade, rollback, removal, signing, and a separate debug/source
artifact remain Phase 9 release gates.
