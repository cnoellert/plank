# Ubuntu NUC Development Package Qualification

The unsigned `stationconnect-client` DEB was assembled on the dedicated Ubuntu
26.04 NUC and refreshed from clean Moonlight commit
`745317e1020fe04da17591af7e91a8d369b88f30`. The build explicitly exported
the private FFmpeg pkg-config and loader paths; a gate rejected an earlier
attempt that had accidentally linked Ubuntu's system FFmpeg 8.

The refreshed `0.1.0-0.2` amd64 package is approximately 18 MiB and has SHA-256:

```text
5d4f39cfdbc9183d60eea53ea84a3bc0cc396caa2f703501554fa2cc6e0913e8
```

It installs Moonlight under `/usr/libexec/stationconnect/`, the launcher and
desktop entry, and globally enabled graphical-session user-unit integration.
This build includes native client-display resolution selection, direct
password-on-stdin launch, the per-workstation display selector, and cached
output topology. Scaled span remains the multi-monitor default.
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
- two builds from differently named clean directories with byte-identical
  binaries and DEB SHA-256 results. Compiler file-prefix mapping removes source
  and build paths from the packaged executable.

The package was not installed over the live qualification client. Clean
install, upgrade, rollback, removal, signing, and a separate debug/source
artifact remain Phase 9 release gates.
