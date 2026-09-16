# macOS Client Wacom read probe

This standalone Apple Silicon probe checks the local half of the existing
[raw Wacom protocol](../../protocol/wacom-hid.md). It does not forward input or
modify the Client. It is separate from the macOS Host tablet probes.

## Build and run

On the authorized development Mac, load the local Client environment, then
choose a new output directory outside the checkout:

```sh
export PLANK_MAC_CLIENT_MIN_MACOS=15.0
bash "$PLANK_SOURCE_ROOT/scripts/test/build-macos-client-hid-probe.sh" \
  "$PLANK_SOURCE_ROOT" "$PLANK_WORK_ROOT/client-hid-probe"
probe="$PLANK_WORK_ROOT/client-hid-probe/macos-client-hid"
umask 077
"$probe" > "$PLANK_AUDIT_ROOT/tablet-inventory.jsonl"
"$probe" --watch 60 > "$PLANK_AUDIT_ROOT/tablet-activity.jsonl"
```

The build uses the installed Apple SDK, validates the deployment target, and
ad-hoc signs the executable. No additional libraries or drivers are installed.
The output directory must not already exist. Audit directories must be private
and outside Git, following the repository's private-information policy.

During the bounded watch, hover and move the pen, vary pressure in a safe area,
try the eraser and side buttons, and exercise tablet touch/ring if enabled.
Local applications still receive normal input. Coordinate the start with the
operator: an idle capture cannot establish whether pen events are accessible.

For a single feature GET, inspect `report_inventory` first and select a declared
feature report from the intended interface:

```sh
"$probe" --get-feature "$interface_index" "$report_id" \
  > "$PLANK_AUDIT_ROOT/tablet-feature.jsonl"
```

Both arguments are decimal integers. Indices are local to each enumeration;
check the inventory after reconnecting hardware. The GET has a five-second
process watchdog because the synchronous IOKit API has no timeout argument.
A watchdog termination produces no `feature_end` record and is not a pass.

## Scope and evidence

- Inventory matches USB Wacom VID `0x056a`, groups interfaces by their common
  USB parent, records interface numbers and hashes exact report descriptors.
  It does not open devices.
- Watch and GET require already-granted IOHID listen access. The probe never
  requests permission. Access granted to this launch context does not establish
  permission for a packaged Client with another executable identity.
- Opens are nonexclusive. The probe never seizes devices, stops a driver,
  sends SET/output reports, injects events, or uses the network.
- Input payloads and feature response bytes are not written to disk. Records
  contain report IDs, counts, lengths and change counts. A previous input
  report is retained in memory only to compare successive values. Serial
  numbers and device paths are not collected; registry IDs are ephemeral.
- A report's change count proves byte variation only. It does not decode
  pressure, tilt, eraser or touch semantics. A successful feature GET does not
  prove feature SET or Host driver initialization.
- Descriptor and report buffers use the protocol's 4096-byte cap; interface
  count is capped at 16 for opening. Do not size vendor feature response
  buffers solely from `MaxFeatureReportSize`: a live interface advertising
  two bytes returned a successful 15-byte response.
- Normal completion and SIGINT/SIGTERM during watch unregister callbacks,
  unschedule devices and close handles. Watch success means at least one
  interface opened; inspect every interface's open, callback and close results
  before drawing a complete-device conclusion. No devices, no opened watch
  interface, or an unsuccessful GET returns status 1; invalid arguments return 2.

## Initial result and remaining gates

The initial macOS 15.7.4 test with a USB Intuos Pro M (`056a:0357`) finds two
interfaces with 549-byte and 949-byte descriptors under one USB parent.
Both nonexclusive opens and closes succeed with the installed Wacom driver
running. Feature GET succeeds on both interfaces. The first unconfirmed activity
window receives only periodic, unchanged ID 19 status reports.

A later coordinated 60-second watch receives 5,548 input reports on ID 16
(27 bytes each, 5,409 changed) and seven on ID 17 (nine bytes each, six changed).
Every report retains its ID prefix; both interfaces open and close successfully,
with no callback errors. Thirty unchanged ID 19 status reports are also seen.
This establishes active raw-report access alongside the installed Wacom driver.
The separate touch interface receives no reports. The exact controls exercised
still await operator confirmation; pressure/tilt/button semantics are not decoded
by this probe, and touch delivery remains unverified.

Before integrating a Mac capture backend, establish:

1. Real pen/touch activity reaches the expected interfaces with intact report
   IDs and lengths, including any needed native device mode.
2. A deliberate ownership policy can support feature SET/output exchanges and
   avoid competing with the local Wacom driver; nonexclusive GET alone does
   not establish this.
3. Complete attach, detach, unplug and reconnect follow the existing grouped
   device protocol and preserve honest errors.
4. The Linux Host recreates the device correctly and target applications
   receive pressure, eraser/buttons and intended screen mapping.

If raw access cannot meet those gates, native macOS pen events remain the
normalized-input fallback to investigate. There is no end-to-end Mac tablet
acceptance yet.
