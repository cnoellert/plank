# integration: experimental macOS 15 Client and matched Linux display workflow

**Draft: dependent PRs and platform/recovery gates must pass before merge.**

## Summary

Coordinate the Client presentation/input/Wacom work, bounded Linux display
matching, primary-output preservation, Pause support, explicit Mac target
selection, tests and sanitized documentation. The full change inventory,
upstream comparison, architecture boundaries and acceptance matrix are in
`docs/development/macos15-integration-review.md`.

## Dependency PRs

1. common-C: ordered absolute input (`0c82257`, base plank/client).
2. libvirtualhid: separate Pause/F15 mappings (`b0cc3c8`, base plank/main).
3. Client: review branch incorporating upstream b9e4be6.
4. Linux Host: d96eb476 plus the libvirtualhid pin.

Replace these entries with published links. Merge/fetch dependencies before
advancing canonical root gitlinks; fork-only object reachability is not a build
contract. Host source and the root display helper are one deployment unit.

## Preserving working upstream behavior

- Current root main 424204b is merged, retaining build cache, workflow, release
  and signing work. Upstream's Client native Quit bridge is preserved.
- Mac-specific capture/fullscreen policies are scoped to macOS. Shared input
  ordering and Host layout changes remain explicit regression-review surfaces.
- Default Client target stays 27.0; experimental 15.0 is opt-in. Cache identity
  includes deployment target and target-policy source. macOS Host is unchanged.
- Existing Native/Scaled-Span settings keep their meaning. Headless Host mode
  presets, authentication, TLS and exact profile negotiation remain enforced.

## Verification

Seven portable root suites, 38 CI tests, seven fullscreen/platform guards and
new-commit privacy checks across all five repositories pass. Exact candidate
build/package and earlier live evidence are listed in the integration review
and HANDOFF; build success is not a cross-platform hardware pass.

## Open gates

Ubuntu Client and supported newer-Mac build/hardware coverage; combined recovery
matrix; physical single-output live check; Retina-detail session acceptance;
Wacom permission continuity and latest-candidate pressure; sustained playback
and visual/color tests. Intermittent left-click loss remains unresolved.

No production release, permanent Xorg/global-DPI change, generic USB redirection
or older macOS Host support is included. Keep this draft unmergeable until the
required dependency, platform, restoration and maintainer-review gates pass.
