# Fresh Client Wacom Permission Fix

## Symptom

StationConnect Client 0.1.0-0.14 on the fresh Ubuntu 26.04 end-user NUC
could stream video, but a connected Wacom PTH-860 (`056a:0358`) produced no
pointer movement. The same workflow had passed on the development NUC.

## Root Cause

The client process had no open `/dev/hidraw*` or `/dev/input/event*` Wacom
descriptors. The Wacom hidraw nodes were `root:root` mode `0600`, carried only
the `seat` udev tag, and had no active-user ACL. The repository already had a
Wacom access rule for host packaging, but `build-client-deb.sh` did not place a
corresponding rule in the client DEB. Development-machine state had masked the
fresh-install omission.

## Correction

Client 0.1.0-0.15 installs
`/usr/lib/udev/rules.d/70-stationconnect-client-wacom.rules`. It adds
`uaccess` only to Wacom (`056a`) input and hidraw devices, leaving access bound
to the active local login session. The package depends on `udev`; its
maintainer scripts reload the rules and retrigger input/hidraw devices during
installation and purge. The host's separate rule retains `/dev/uhid` access
for virtual-tablet creation.

After installation, reboot both endpoints and verify pointer movement, pen
clicks, pressure, and Flame Tablet Margins before accepting the package.
