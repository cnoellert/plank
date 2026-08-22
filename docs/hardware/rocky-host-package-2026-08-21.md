# Rocky Host Development Package Qualification

The unsigned `stationconnect-host` RPM was refreshed on the qualified Rocky 9
workstation from root commit `30c4a5e`. Its packaged Sunshine binary reports
`0.0.0-30c4a5e` without a dirty-tree marker and embeds
`/usr/share/stationconnect` as its asset path.

The `0.1.0-0.4.el9` x86-64 RPM is approximately 5.6 MiB compressed and has
SHA-256:

```text
b572f12ca70d95b778a9c1fbe63642b567f472430bcbf1321c865db10ece4f2d
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
The 0.4 upgrade also installs a modules-load entry, reloads the Wacom udev
rules, loads `uhid`, and retriggers `/dev/uhid`. On hardware-test-host the node received the
`uaccess` and `seat` tags plus an `operator:rw-` ACL. The host service now starts
directly from the packaged user unit without its former `sg` development
wrapper.
An authenticated 0.4 client then opened both physical Wacom raw-HID
interfaces. Rocky created virtual `056a:0357` Pen, Pad, and Finger input nodes
under `/devices/virtual/misc/uhid/`, closing the package-level UHID regression.
Package signing and clean-image install, upgrade, rollback, removal, and a
separate debug/source artifact remain Phase 9 release gates.
