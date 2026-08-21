# Ubuntu NUC Development Package Qualification

The first unsigned `stationconnect-client` DEB was assembled on the dedicated
Ubuntu 26.04 NUC and refreshed from clean Moonlight commit
`d543d89be2026ba7376260a5159b727f65870d37`. The build explicitly exported
the private FFmpeg pkg-config and loader paths; a gate rejected an earlier
attempt that had accidentally linked Ubuntu's system FFmpeg 8.

The final `0.1.0-0.1` amd64 package is 18 MiB and has SHA-256:

```text
99f1d605c6a657f2171257eda4bc947d31e89aaefdf5db9f8d6d2b610fedbf8d
```

It installs Moonlight under `/usr/libexec/stationconnect/`, the launcher and
desktop entry, and globally enabled graphical-session user-unit integration.
This build includes native client-display resolution selection and its saved
explicit-override control.
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
