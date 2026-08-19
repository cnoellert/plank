# Intel NUC Client Qualification

Run this gate on every supported NUC generation with its production Ubuntu
kernel, `intel-media-va-driver` (`iHD`), libva, FFmpeg, compositor, and display.
Copy both the Ada driver-auto and SFE-disabled HEVC test streams from
`artifacts/qualification/video/` to the NUC.

```bash
./scripts/probe-intel-vaapi-decode.sh \
  artifacts/qualification/video/stationconnect-flame-loop-150s-sfe-auto-paired.hevc \
  9000

./scripts/probe-intel-vaapi-decode.sh \
  artifacts/qualification/video/stationconnect-flame-loop-150s-sfe-disabled.hevc \
  9000
```

The script fails unless VA-API exposes `VAProfileHEVCMain444_10` with the VLD
entry point, the stream retains the full-range GBR identity metadata, FFmpeg
keeps decoded frames in VA-API hardware surfaces, all requested frames decode,
and average throughput reaches 60 fps. For the current long-loop vectors:

```text
auto_sha256=21c2007a97c7fc777b98dd24e5aba9fc1b62f2f2b3453f8bc9d72f1d62118fe1
disabled_sha256=261157e974092e704b6ec4b799a1dabddfd3efbfc86ca6286b6e7a0282dfcad1
frames=9000
resolution=3840x2160
codec=HEVC Rext 10-bit 4:4:4
```

This is only the decoder gate. The client implementation must additionally
import the 10-bit 4:4:4 VA surface into Vulkan/EGL without an 8-bit copy, reverse
the `Y=G,U=B,V=R` identity mapping in its shader, verify channel order with pixel
patterns, and measure decode-to-presentation p95 against the 8 ms target.
