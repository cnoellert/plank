# Qualification Artifacts

Large generated video streams are stored under `video/` for transfer to target
client hardware. HEVC files in that directory are intentionally ignored by Git.
Do not remove them until the corresponding client qualification is complete.

| File | Split mode | SHA-256 |
| --- | --- | --- |
| `video/stationconnect-flame-loop-150s-sfe-auto-paired.hevc` | Driver-auto | `21c2007a97c7fc777b98dd24e5aba9fc1b62f2f2b3453f8bc9d72f1d62118fe1` |
| `video/stationconnect-flame-loop-150s-sfe-disabled.hevc` | Disabled | `261157e974092e704b6ec4b799a1dabddfd3efbfc86ca6286b6e7a0282dfcad1` |
| `video/stationconnect-flame-fullscreen-loop-150s-sfe-auto.hevc` | Driver-auto | `7a60394a6d3ee2bd1de948ef673bb2204d9d8c465d25ae1b9def663fa3593156` |
| `video/stationconnect-flame-fullscreen-loop-150s-sfe-disabled.hevc` | Disabled | `cf0ce9cb7035c62e49d872f3a6b718f9cd441f3860753525364d9a93d0aba185` |

All streams contain 9,000 frames of 3840×2160/60 HEVC Rext 10-bit 4:4:4
with full-range GBR identity signaling. Validate checksums after transferring
them to a NUC.

Use the fullscreen pair for stress and regression testing. The original pair
retains more static Flame UI and is useful as a lower-motion comparison.
