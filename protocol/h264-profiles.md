# StationConnect H.264 profile negotiation

Each StationConnect workstation bookmark stores one H.264 encoding profile.
When that bookmark starts a session, the client advertises exactly its saved
profile. The host must either advertise and produce that exact profile or
reject the launch; bit depth and chroma sampling never fall back silently.

| Client profile | Video format | Chroma type | Dynamic range | Color transform |
| --- | --- | ---: | ---: | --- |
| H.264 8-bit 4:2:2 | `0x0002` | 2 | 0 | Full-range BT.709 YCbCr |
| H.264 8-bit 4:4:4 | `0x0004` | 1 | 0 | Identity GBR (`Y=G`, `U=B`, `V=R`) |
| H.264 10-bit 4:2:2 | `0x0010` | 2 | 1 | Full-range BT.709 YCbCr |
| H.264 10-bit 4:4:4 | `0x0008` | 1 | 1 | Identity GBR (`Y=G`, `U=B`, `V=R`) |

The existing 10-bit 4:4:4 identity profile remains the default and qualified
production profile. The selectable alternatives require their own image,
latency, and sustained-frame-rate qualification before production use.
Encoding profile is intentionally absent from global Client Configuration;
it is selected when creating a bookmark and can be changed with
`Edit bookmark…`.

The qualified Intel NUC does not expose VA-API H.264 High 4:2:2 or High 4:2:2
10-bit decode profiles. Both 4:2:2 modes therefore use the pinned FFmpeg
software decoder, followed by the Vulkan upload, color conversion, scaling,
and presentation path.

For 4:2:2, the host converts NvFBC BGRA on CUDA. Each horizontal pixel pair
retains independent luma samples and uses the rounded average of its two
full-precision chroma values. The 10-bit converter writes native LSB-aligned
planar samples directly instead of first quantizing the matrix result to
8-bit. FFmpeg/x264 metadata identifies BT.709 primaries, transfer, and matrix
with PC/full range.
