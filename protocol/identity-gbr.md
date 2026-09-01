# Identity GBR Video Mode

PLANK transports the approved 8-bit NvFBC BGRA source in an HEVC
Range Extensions 10-bit 4:4:4 stream without a YUV color transform. The CUDA
conversion writes `Y=G`, `U=B`, and `V=R`. Each 8-bit component is expanded to
an MSB-aligned 10-bit value using `round(value * 1023 / 255) << 6`.

The HEVC VUI must signal full range, matrix coefficients `0` (identity), BT.709
primaries, and sRGB transfer. Diagnostics must label this path
`8-bit-source/up-converted`; it is not native 10-bit capture.

## Negotiation

The shared Sunshine/Moonlight protocol fork reserves these values:

- `COLORSPACE_IDENTITY_GBR = 3`
- `SCM_IDENTITY_GBR_444 = 0x00800000`
- `ML_FF_IDENTITY_GBR_444 = 0x04`

The host advertises `SCM_IDENTITY_GBR_444` only when the complete capture and
HEVC Rext10 4:4:4 encode path is available. A client requests the mode with
colorspace `3`, full range, 10-bit dynamic range, 4:4:4 chroma, and the
`ML_FF_IDENTITY_GBR_444` feature bit. The client must only request it when its
decoder and presentation path can reverse the plane mapping without an 8-bit
copy.

Reject a partial or inconsistent request rather than treating colorspace `3`
as Rec. 709. Older clients and hosts continue using existing colorspace values
and never activate this mode.

## Presentation

On the qualified Intel path, VA-API decodes to Y410. Import the DMA-BUF into
EGL using its native layout, reinterpret the packed components as RGB identity,
and present to an XR30/XB30 10-bit surface. Validate channel order and exact
pixel values before enabling the host capability bit.
