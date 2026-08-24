# Upstream Commit Audit

This file records upstream Sunshine and Moonlight commits that StationConnect
has evaluated. Consult it before rebasing either fork so already-resolved work
is not reintroduced or silently allowed to override a qualified product path.

Use these dispositions:

- `ported` — StationConnect contains the relevant behavior, possibly adapted
  rather than cherry-picked. Record the local implementing commit.
- `skipped` — reviewed and deliberately not adopted. Preserve the reason when
  resolving a future rebase.
- `superseded` — useful idea, but a later upstream implementation was selected.
- `pending` — evaluated but still needs a product decision or validation.

## Moonlight-Qt

| Upstream commit | Subject | Disposition | StationConnect decision |
| --- | --- | --- | --- |
| `a903c5cef2c54f10974943254357f641f09ea3ef` | Explicitly request limited range for renderers that require it | skipped | Part of the renderer color-range series below. Do not let its generic renderer defaults override StationConnect's explicit identity-GBR and VA-API range behavior. |
| `4570fba87d5a2dc1e087cc0211f493b74224c1d2` | Add full range handling to SdlRenderer | skipped | Applies to SDL CPU color conversion, not the qualified StationConnect presentation path. It is unnecessary for the proven H.264 High 10 4:4:4 identity path. |
| `3f26217df7ea00b78a012950e0e768c5df6ed69f` | Select color range based on plane COLOR_RANGE property values | skipped | DRM-plane behavior is outside the qualified Wayland software-decode identity path and was not adopted. |
| `b2f0828df8de1b8baf6c646bc02dd806f2dde183` | Use requested color range as a fallback in `isFrameFullRange()` | skipped | Reviewed with the range series. The qualified StationConnect path supplies an explicit full-range identity decision instead of relying on generic fallback metadata. |
| `c1623ff44e4e3059bd5b34626bcbf957e4efc397` | Switch the default renderer color range to full | skipped | Redundant: StationConnect's `FFmpegVideoDecoder` already explicitly requests full range for identity GBR. |
| `e596c2dcdc9aaeaa6fef1f32a1bf639e29f83f45` | Update moonlight-common-c with SIMD acceleration for FEC | superseded | The early SIMDe-wrapper implementation was not cherry-picked. StationConnect selected the later native runtime-dispatch implementation represented by `0c897036`. |
| `0c8970364c5db84a6804861fbc7575fedadfa7c4` | Switch to upstream nanors with native SIMD and GFNI runtime dispatching | ported | Adapted into StationConnect Moonlight commit `bb86a9ffd40521f05d699ce9a21ae07d95bce3cd`, preserving private common-c protocol and FEC-accounting changes. Candidate version: 0.61. |

## moonlight-common-c

The early optimized-FEC sequence `de364b6`, `5551d29`, `a063522`, `3872285`,
`b187204`, `1fddbcb`, and `99c45d3` was evaluated but not replayed. It is
superseded by the cleaner upstream nanors-submodule integration below.

| Upstream commit | Subject | Disposition | StationConnect decision |
| --- | --- | --- | --- |
| `1f764276e848ae2ec7815ef90d1c1748272e074a` | Switch to upstream nanors with native SIMD and GFNI runtime dispatching | ported | Adapted into private common-c commit `36271a91778c9ed80c3fa6dabd1c51c428db1570`. The port removes the scalar `reedsolomon` implementation while preserving StationConnect's extended-block recovery, byte validation, and recovery statistics. |
| `2ea47752c3051d72a64bcca190024e8b354fa1ef` | Bump nanors from `c3529fd` to `17fc7d6` | superseded | Included through the later pinned nanors revision. |
| `e41355ea01670fd4c830b384009d31dd0339a705` | Bump nanors from `17fc7d6` to `b1e3c22` | ported | StationConnect pins nanors `b1e3c22ca0cdc0bb83e3cd6ed1a2fc77869ed99a`, matching this upstream endpoint. |

## Updating this audit

For every reviewed upstream commit or related series, record the exact full
hash, subject, disposition, reason, and local implementing commit when one
exists. Group related commits, but do not omit intermediate fixes that may
reappear as rebase conflicts. Update this file in the same candidate that
adopts or rejects the upstream behavior.
