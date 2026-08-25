# Active-Session Video Bitrate

StationConnect clients may change the running video encoder bitrate without
disconnecting. Sunshine advertises support with host feature flag `0x08`
(`LI_FF_DYNAMIC_VIDEO_BITRATE`) in `x-ss-general.featureFlags`. Clients must
leave the in-stream control disabled when that bit is absent.

The synchronized StationConnect protocol also advertises feature flag `0x10`
(`LI_FF_ENCODER_TARGET_ACK`) and accepts
`x-sc-video.encoderTargetKbps` in the RTSP ANNOUNCE. Unlike Moonlight's
`x-ml-video.configuredBitrateKbps` total network budget, this value is the
exact video encoder target and is not reduced for audio, packet overhead, or
FEC. It uses the same 500 through 500000 Kbps validation range. Providing the
target during setup ensures the first encoder starts at the selected toolbar
value, before the live control stream is ready.

The client sends reliable encrypted control type `0x5505` with one unsigned
32-bit little-endian bitrate in kilobits per second. The valid protocol range
is 500 through 500000 Kbps. Sunshine rejects any other payload length or value.
The host's configured `max_bitrate` remains an authoritative ceiling.

After accepting a `0x5505` request, the host replies on the
reliable encrypted control stream with type `0x5506`. Its 12-byte payload is
three unsigned 32-bit little-endian values: the requested target, the target
after the host's bitrate ceiling, and the configured encoder peak. The client
retries an unconfirmed current target no more often than once per second. An
acknowledgement for an older slider position never suppresses the latest
position. This response confirms host acceptance and scheduled application at
the next encoder frame boundary; a subsequent encoder failure still terminates
the stream normally.

On the qualified H.264 4:4:4 path, Sunshine drains pending requests at a frame
boundary and applies only the newest value. The selected bounded-ABR x264
profile cannot change its sustained average target with
`x264_encoder_reconfig()`; that API only changes the active bitrate when x264
is operating in CBR mode. Sunshine therefore keeps capture, RTP sequencing,
input, and the authenticated stream active while replacing only the encoder
instance. The first frame from the replacement encoder is an IDR frame with
fresh parameter sets.

While the slider is moving, the client waits for 250 ms of inactivity before
sending the latest snapped value. Releasing the slider sends its final value
immediately. This prevents a separate encoder replacement for every pointer
motion event while preserving interactive control.

`tests/protocol/dynamic-bitrate-v1.json` contains the canonical 100 Mbps test
vector. Host validation covers correct little-endian decoding, malformed
lengths, and both range boundaries.
