# Rocky Host Development Package Qualification

The first unsigned `stationconnect-host` RPM was assembled on the qualified
Rocky 9 workstation from root commit `19cf657`. Its packaged Sunshine binary
reports `0.0.0-19cf657` without a dirty-tree marker and embeds
`/usr/share/stationconnect` as its asset path.

The `0.1.0-0.1.el9` x86-64 RPM is approximately 22 MiB and has SHA-256:

```text
20283a3f69eec5a7a28ccee32efde4c6e7607375c25659e0382ac18841e6bb24
```

The payload contains Sunshine, the PAM broker and launch wrapper, PAM policy,
system and user units, sysusers, udev and firewalld definitions, assets, and
license documentation. RPM automatic dependency scanning covers the
platform-owned X11, PAM, CUDA-driver-facing, and ordinary OS libraries; media
libraries in the qualified host build are linked into Sunshine.

Header/payload digests, the complete manifest, executable and configuration
modes, asset presence, launcher syntax, and the extracted Sunshine runtime
closure all passed. The package was not installed on the live workstation.
Package signing and clean-image install, upgrade, rollback, removal, and
separate debug/source artifacts remain Phase 9 release gates.
