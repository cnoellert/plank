# Host-aware bookmark options and Mac display matching

Branch: `bookmark-host-options`, based on accepted main `d6c4598`.

## Scope

Enable Match client display(s) for the existing macOS Host, and filter Add/Edit
capture and encoding choices by a reachable Host's advertised capabilities.
This is a Client-only change. No Host, input, media, transport or decoder
policy change is required.

## Behavior

- Public PLANK metadata identifies the supported Linux/Mac contract. It is
  only a UI hint, never authentication, certificate trust or exact-format proof.
- Address entry is debounced; at most one fast-fail lookup runs at a time.
  Stale replies cannot filter another address or a closed dialog.
- Known Linux Hosts show NvFBC/native-X11 and their existing encoding models.
  Known Macs show ScreenCaptureKit and the two Apple VideoToolbox profiles.
  Unreachable, unknown and unsupported Hosts retain all manual choices.
- Mac bookmarks preserve either Match client display(s) or a fixed resolution.
  Existing fixed bookmarks remain fixed. Filtering does not rewrite bookmarks
  until the operator saves them.
- At authentication, Qt screen geometry and device pixel ratio resolve the
  native-pixel request without initializing SDL/window surfaces. The existing
  authenticated display schema 2 requests that size and the selected profile.
  Before launch, SDL's actual display modes must agree; a topology change fails
  clearly instead of launching mis-scaled video/input.
- One or two horizontally arranged client monitors map to one Mac virtual
  canvas. The existing qualified resolutions and 5120x2160 maximum apply.
  Unsupported combinations require a fixed resolution; there is no silent
  downscale, arbitrary-resolution extension or new dual-Mac-output feature.
- Reconnect uses the same native-client canvas and existing authenticated
  generation/profile validation. Linux Match Client behavior is unchanged.

## Validation and next step

linux-client-builder Qt6.10.2: topology suite 16 tests pass; shared QML capture chooser
suite 3 tests pass. Coverage includes native4K/5K, 125%/200% logical geometry,
two2560x2160 screens, oversized/stacked/empty layouts, supported/unknown feature
contracts, delayed stale discovery replies and offline/manual choices.
These are automated logical/QML checks, not physical-monitor acceptance.

Next: clean1.0.65-bookmark-host-options Client package on linux-client-builder, inspect
the complete UI and package gates, retain DEB/checksum in artifacts/packages.
Manual acceptance: edit a Mac bookmark, choose Match client display(s), verify
native Host resolution and input mapping, reconnect, then verify a Linux
bookmark and offline creation. Existing1.0.64 Mac Host remains installed.
