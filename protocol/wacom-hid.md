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

## Wire Framing

Production messages use protocol version 2 and begin with the packed 20-byte
`SC_RAW_HID_WIRE_HEADER` from `StationConnect.h`. All integer fields are
little-endian. The header carries magic `SCWH`, message type, interface index,
device generation, transaction ID, and payload length. The client sends the
variable frame through Moonlight's reliable generic input channel with magic
`0x55000008`; Sunshine replies with reliable control type `0x5504`. Both paths
require the authenticated encrypted control stream. Descriptors and reports
are capped at 4096 bytes, a group at 16 interfaces, and stale generations are
rejected.

## Ordered Messages

All lifecycle and control messages are reliable and ordered:

- `tablet-attach` / `tablet-attach-result`
- `tablet-input-report` with interface ID, sequence, client timestamp, and the
  unchanged report bytes
- `tablet-get-report` / `tablet-get-report-result`, correlated by transaction ID
- `tablet-set-report` / `tablet-set-report-result`, correlated by transaction ID
- `tablet-output-report` for host-to-client `UHID_OUTPUT`
- `tablet-open`, `tablet-close`, and `tablet-detach`
- `tablet-suspend`, which stops transport delivery without removing the host
  UHID endpoints

The client answers control requests with `HIDIOCGFEATURE`, `HIDIOCSFEATURE`, or
the corresponding input/output-report ioctl on the original `hidraw` node.
Errors and returned lengths must be preserved. The host must never synthesize a
successful feature reply.

## First-generation Intuos Pro fallback

Linux UHID cannot reproduce the USB-interface type required by `hid-wacom` for
the first-generation Intuos Pro S/M/L family. The client therefore recognizes
the complete PTH-x51 USB product family (`056a:0314`, `056a:0315`, and
`056a:0317`) and selects the normalized core-pen path instead of attempting an
unusable raw attachment. That fallback carries absolute position, tip,
pressure, tilt, eraser, and up to three pen buttons. It intentionally does not
represent ExpressKeys, the ring, or touch. Other in-scope Wacom product IDs are
treated as newer descriptor-driven devices and continue through exact raw-HID
forwarding; pre-Intuos-Pro devices are outside the product scope.

## Ownership and Cleanup

Raw access is granted only to the active local session. Once attach succeeds,
the client exclusively grabs every pen, pad, and touch event node belonging to
the USB group so local desktop input cannot occur in parallel. Client focus
loss sends `tablet-suspend`, releases the local grabs, and closes the physical
nodes while the host keeps its UHID endpoints and XInput identities. Focus
return starts a new generation; byte-identical USB identity and descriptors
reactivate the retained endpoints without recreating them. This is required
because Autodesk Flame caches XInput device IDs.

A physical hot-unplug, HID I/O error, changed USB identity or descriptor, or
explicit final device teardown remains destructive and sends `tablet-detach`.
An ordinary resumable stream disconnect also suspends transport and retains the
same endpoints. Stale reports from an older or suspended generation are
discarded.

## Reconnect Barrier

Before replacing a StationConnect control stream, the client suspends raw-HID
delivery and closes its physical tablet handles while the old reliable channel
still exists. The raw-tablet worker remains behind a reconnect barrier during
authentication, host display transitions, and input-stream initialization. It
may start one fresh attachment only after the replacement connection reports
success. This ordering prevents an early valid attachment from being discarded
by reconnect cleanup.

Each attachment waits at most three seconds for `tablet-attach-result`. If that
reliable acknowledgement is unavailable, the client closes the local
transaction and retries with a new generation. The retained host endpoints are
reused when identity and descriptors match, so acknowledgement recovery does
not change the application-visible XInput device identity.

## Acceptance

Compare physical-client and virtual-host nodes for VID/PID/version, interface
count, axis ranges and resolution, pressure, tilt, distance, tool identity,
pad controls, and touch geometry. Exercise feature/output reports, pen and
eraser proximity, ExpressKeys, ring, multitouch, hot-unplug, reconnect, and
abrupt network loss. Flame Tablet Margins and edge gestures must work without
pre-scaling coordinates, preference watchers, or Xorg changes.

## Qualification Bridge

`connect-wacom-raw-bridge` implements this lifecycle as a one-client hardware
probe. Its TCP transport is intentionally rejected as a production boundary:
it is plaintext, has no session authentication, and must run only on an
isolated qualification network. The PTH-660 live test passed descriptor,
input, feature, output, exclusive-grab, and disconnect behavior through this
bridge. Production code must reuse the behavior, limits, and cleanup rules
above inside Sunshine/Moonlight's authenticated encrypted control stream.
