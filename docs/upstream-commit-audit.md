# Upstream Commit Audit

This file records upstream Sunshine and Moonlight commits that PLANK
has evaluated. Consult it before rebasing either fork so already-resolved work
is not reintroduced or silently allowed to override a qualified product path.

Use these dispositions:

- `ported` — PLANK contains the relevant behavior, possibly adapted
  rather than cherry-picked. Record the local implementing commit.
- `skipped` — reviewed and deliberately not adopted. Preserve the reason when
  resolving a future rebase.
- `superseded` — useful idea, but a later upstream implementation was selected.
- `pending` — evaluated but still needs a product decision or validation.

## Moonlight-Qt

| Upstream commit | Subject | Disposition | PLANK decision |
| --- | --- | --- | --- |
| `a903c5cef2c54f10974943254357f641f09ea3ef` | Explicitly request limited range for renderers that require it | skipped | Part of the renderer color-range series below. Do not let its generic renderer defaults override PLANK's explicit identity-GBR and VA-API range behavior. |
| `4570fba87d5a2dc1e087cc0211f493b74224c1d2` | Add full range handling to SdlRenderer | skipped | Applies to SDL CPU color conversion, not the qualified PLANK presentation path. It is unnecessary for the proven H.264 High 10 4:4:4 identity path. |
| `3f26217df7ea00b78a012950e0e768c5df6ed69f` | Select color range based on plane COLOR_RANGE property values | skipped | DRM-plane behavior is outside the qualified Wayland software-decode identity path and was not adopted. |
| `b2f0828df8de1b8baf6c646bc02dd806f2dde183` | Use requested color range as a fallback in `isFrameFullRange()` | skipped | Reviewed with the range series. The qualified PLANK path supplies an explicit full-range identity decision instead of relying on generic fallback metadata. |
| `c1623ff44e4e3059bd5b34626bcbf957e4efc397` | Switch the default renderer color range to full | skipped | Redundant: PLANK's `FFmpegVideoDecoder` already explicitly requests full range for identity GBR. |
| `e596c2dcdc9aaeaa6fef1f32a1bf639e29f83f45` | Update moonlight-common-c with SIMD acceleration for FEC | superseded | The early SIMDe-wrapper implementation was not cherry-picked. PLANK selected the later native runtime-dispatch implementation represented by `0c897036`. |
| `0c8970364c5db84a6804861fbc7575fedadfa7c4` | Switch to upstream nanors with native SIMD and GFNI runtime dispatching | ported | Adapted into PLANK Moonlight commit `bb86a9ffd40521f05d699ce9a21ae07d95bce3cd`, preserving private common-c protocol and FEC-accounting changes. Candidate version: 0.61. |
| `e1bbf8144e94bd22c3151a499cbf33c629ef547d` | Switch AppImage to SDL3+SDL2-compat | skipped | AppImage-only packaging is outside PLANK's DEB workflow. Its dependency approach informed the later general migration but this commit itself is not applicable. |
| `9813932c1b8e0f5e3bc24d280d6f574ff04a8e78` | Switch to SDL3+SDL2-compat | superseded | Included in the upstream merge at local commit `4d003523`, then superseded by PLANK's native SDL3 API migration beginning at `c64000b9`. The Linux candidate links directly to SDL3 with no compatibility ABI. |
| `f2a512d3aa46abe81e92c0cb745f379ee76cbbe1` | Update libplacebo, sdl2-compat, OpenSSL, and SDL3 | superseded | Included through the current-upstream merge. PLANK retained its pinned FFmpeg 9.0.1 and system libplacebo while replacing the compatibility layer with native SDL3 3.4.2 APIs. |
| `8795fb54f493e594ec77fff66187a6f8f221fb2f` | Fix double-free in Vulkan renderer when an overlay is disabled | ported | Cherry-picked as local client commit `0429ca92`. This directly protects PLANK's Vulkan toolbar and statistics overlays. |
| `476414ea7122ef2333611825502a5ababce2a560` | Fix a rare race where an overlay surface can leak | ported | Retained through the native overlay port in local client commit `e9109384`: the new surface is atomically exchanged before renderer notification and the old surface is destroyed only afterward. |
| `88b4a17fe13ffed42130ec7dabdb45a8f664dc47` | Use `AV_CODEC_RECEIVE_FRAME_FLAG_SYNCHRONOUS` for decoder probing on FFmpeg 8.1 | ported | Cherry-picked as local client commit `e5ebce33`; the version guard also applies to the pinned FFmpeg 9.0.1 decoder probe. |
| `5020fc6f48f76403ec3156c5b64815601aba7067` | Do not reset the renderer on `SDL_RENDER_TARGETS_RESET` | ported | Adapted to native SDL3 event names in local client commit `586cd6a2`. Renderer failures now request `SDL_EVENT_RENDER_DEVICE_RESET`; target-only resets no longer rebuild the decoder. |
| `d2f6990be699197385a6458e1231d070da83e665` | Current upstream master endpoint at migration start | ported | Merged as local client commit `4d003523`. PLANK product removals and the qualified High 10 4:4:4 identity path remain authoritative. Renderer improvements overwritten while resolving the native port must be reviewed individually rather than assumed present merely because this merge is in history. |

## moonlight-common-c

The early optimized-FEC sequence `de364b6`, `5551d29`, `a063522`, `3872285`,
`b187204`, `1fddbcb`, and `99c45d3` was evaluated but not replayed. It is
superseded by the cleaner upstream nanors-submodule integration below.

| Upstream commit | Subject | Disposition | PLANK decision |
| --- | --- | --- | --- |
| `1f764276e848ae2ec7815ef90d1c1748272e074a` | Switch to upstream nanors with native SIMD and GFNI runtime dispatching | ported | Adapted into private common-c commit `36271a91778c9ed80c3fa6dabd1c51c428db1570`. The port removes the scalar `reedsolomon` implementation while preserving PLANK's extended-block recovery, byte validation, and recovery statistics. |
| `2ea47752c3051d72a64bcca190024e8b354fa1ef` | Bump nanors from `c3529fd` to `17fc7d6` | superseded | Included through the later pinned nanors revision. |
| `e41355ea01670fd4c830b384009d31dd0339a705` | Bump nanors from `17fc7d6` to `b1e3c22` | ported | PLANK pins nanors `b1e3c22ca0cdc0bb83e3cd6ed1a2fc77869ed99a`, matching this upstream endpoint. |

## Updating this audit

For every reviewed upstream commit or related series, record the exact full
hash, subject, disposition, reason, and local implementing commit when one
exists. Group related commits, but do not omit intermediate fixes that may
reappear as rebase conflicts. Update this file in the same candidate that
adopts or rejects the upstream behavior.
