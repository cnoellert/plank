# Raw Wacom HID Redirection

## Goal

Mirror the Wacom tablet selected on the client instead of presenting a fixed
StationConnect tablet profile. The host must receive the client's HID report
descriptors and USB identity, create one UHID endpoint per HID interface, and
let the stock `hid-wacom` stack interpret reports. Never scale or reinterpret
raw report fields in this path.

## Device Group

The client groups HID interfaces by their common USB device parent. An attach
transaction carries a session-local device ID, generation, bus, vendor,
product, version, country code, name, physical path, serial-presence flag, and
the original descriptor for every interface. Descriptor size is limited to
`HID_MAX_DESCRIPTOR_SIZE`; report payloads are limited to `UHID_DATA_MAX`.
The serial value is sensitive and must remain inside the authenticated,
encrypted session.

The host creates every interface with the same physical group ID. It accepts
the group only when all descriptors validate and every UHID endpoint reaches
`UHID_START`; otherwise it destroys the entire group and selects the normalized
core-pen fallback.

## Ordered Messages

All lifecycle and control messages are reliable and ordered:

- `tablet-attach` / `tablet-attach-result`
- `tablet-input-report` with interface ID, sequence, client timestamp, and the
  unchanged report bytes
- `tablet-get-report` / `tablet-get-report-result`, correlated by transaction ID
- `tablet-set-report` / `tablet-set-report-result`, correlated by transaction ID
- `tablet-output-report` for host-to-client `UHID_OUTPUT`
- `tablet-open`, `tablet-close`, and `tablet-detach`

The client answers control requests with `HIDIOCGFEATURE`, `HIDIOCSFEATURE`, or
the corresponding input/output-report ioctl on the original `hidraw` node.
Errors and returned lengths must be preserved. The host must never synthesize a
successful feature reply.

## Ownership and Cleanup

Raw access is granted only to the active local session. Once attach succeeds,
the client exclusively grabs every pen, pad, and touch event node belonging to
the USB group so local desktop input cannot occur in parallel. On disconnect,
timeout, generation change, or hot-unplug, the host sends `UHID_DESTROY` for all
interfaces and the client releases all grabs. Stale reports from an older
generation are discarded.

## Acceptance

Compare physical-client and virtual-host nodes for VID/PID/version, interface
count, axis ranges and resolution, pressure, tilt, distance, tool identity,
pad controls, and touch geometry. Exercise feature/output reports, pen and
eraser proximity, ExpressKeys, ring, multitouch, hot-unplug, reconnect, and
abrupt network loss. Flame Tablet Margins and edge gestures must work without
pre-scaling coordinates, preference watchers, or Xorg changes.
