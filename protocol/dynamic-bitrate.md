# Active-Session Video Bitrate

StationConnect clients may change the running video encoder bitrate without
disconnecting. Sunshine advertises support with host feature flag `0x08`
(`LI_FF_DYNAMIC_VIDEO_BITRATE`) in `x-ss-general.featureFlags`. Clients must
leave the in-stream control disabled when that bit is absent.

The client sends reliable encrypted control type `0x5505` with one unsigned
32-bit little-endian bitrate in kilobits per second. The valid protocol range
is 500 through 500000 Kbps. Sunshine rejects any other payload length or value.
The host's configured `max_bitrate` remains an authoritative ceiling.

On the qualified H.264 4:4:4 path, Sunshine updates the open FFmpeg/libx264
context at a frame boundary. FFmpeg detects the changed average rate, VBV peak,
and VBV buffer fields and invokes `x264_encoder_reconfig()`; RTP sequencing and
the authenticated stream remain active. Control updates are rate-limited by
the client while the slider is dragged and the final snapped value is sent on
release.

`tests/protocol/dynamic-bitrate-v1.json` contains the canonical 100 Mbps test
vector. Host validation covers correct little-endian decoding, malformed
lengths, and both range boundaries.
