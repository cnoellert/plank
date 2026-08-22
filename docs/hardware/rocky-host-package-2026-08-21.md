# Rocky Host Development Package Qualification

The unsigned `stationconnect-host` RPM was refreshed on the qualified Rocky 9
workstation from root commit `5aeea7c`. Its packaged Sunshine binary reports
`0.0.0-5aeea7c` without a dirty-tree marker and embeds
`/usr/share/stationconnect` as its asset path.

The `0.1.0-0.3.el9` x86-64 RPM is approximately 5.7 MiB compressed and has
SHA-256:

```text
d03648331951b549a5ef6acc595bef9b82e74b5b03c2507ae8837f68f1f239ed
```

The payload contains Sunshine, the PAM broker and launch wrapper, PAM policy,
system and user units, sysusers, udev and firewalld definitions, assets, and
license documentation. RPM automatic dependency scanning covers the
platform-owned X11, PAM, CUDA-driver-facing, and ordinary OS libraries; media
libraries in the qualified host build are linked into Sunshine.

Header/payload digests, the complete manifest, executable and configuration
modes, asset presence, launcher syntax, and the extracted Sunshine runtime
closure all passed. Installation on hardware-test-host replaced the obsolete
`plome-pam-helper` package in the same DNF transaction, preserving the
identical PAM policy. The packaged PAM broker and Sunshine user service then
restarted successfully; Sunshine runs from `/usr/libexec/stationconnect/`.
Package signing and clean-image install, upgrade, rollback, removal, and a
separate debug/source artifact remain Phase 9 release gates.
