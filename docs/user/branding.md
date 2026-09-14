# PLANK Product Identity

PLANK is the product name shown to end users and administrators. Upstream
Moonlight and Sunshine names remain only where required for source provenance,
license notices, and accurate historical documentation.

## Canonical identities

- Product display name: `PLANK`
- Client display name: `PLANK Client`
- Client application ID: `la.instinctual.Plank.Client`
- Client desktop entry: `la.instinctual.Plank.Client.desktop`
- Client executable and package: `plank-client`
- Host display name: `PLANK Host`
- Host application ID: `la.instinctual.Plank.Host`
- Host executable, package, and service: `plank-host`

The host has no desktop, D-Bus, Flatpak, or AppStream surface. Its canonical
application ID is retained as systemd unit metadata so package and service
inspection distinguish it from a co-installed client. Any future graphical
host application or D-Bus API must use the same canonical host ID.

## Clean-break boundaries

The client uses `Instinctual`, `instinctual.la`, and `PLANK` for its Qt
organization, domain, and application settings namespace. The project has no
deployed legacy clients, so no Moonlight settings migration or compatibility
fallback is carried. Development machines may retain an unused upstream
settings file on disk; new builds neither read nor modify it.

## Artwork

The canonical PLANK artwork set is stored in `branding/assets/`:

- `plank-logo.png` is the approved transparent production icon.
- `plank-logo.pxd` is its editable source project.
- The retired StationConnect wordmark sources remain available in Git history;
  they are intentionally absent from the active PLANK asset set.

The client submodule carries the required runtime copy at
`apps/client/app/res/plank-logo.png`; the application
embeds it and the Debian package installs it in the hicolor icon theme. Keep
that copy byte-for-byte identical to the canonical production PNG. The
inherited Sunshine artwork remains temporary until approved host artwork and
usage rules are available. Do not create unrelated visual variants
independently in each fork; keep one approved source asset set and derive
platform formats from it.
