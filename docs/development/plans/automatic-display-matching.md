# Automatic display matching

Extend the existing bookmark controls: Match client displays, Physical displays,
one/two virtual displays, and Native/Scaled-Span. Preserve scaling semantics;
the operator selected a separate Retina size choice under Match client displays.
On macOS distinguish panel-native pixels, current compositor backing pixels and
logical workspace size. Use the measured native-fullscreen camera inset even
when connecting windowed, so entering fullscreen does not change the contract.

The qualified Linux X11 desktop reports `global-scale-required=true`; mixed
per-monitor UI scaling is unavailable. Matching logical workspace dimensions can
preserve familiar UI size with an upscale on Retina. Matching backing pixels
preserves detail but does not imply a per-monitor Linux UI scale.

Negotiate optional feature `0x400000` for bounded real display modes in a
temporary physical-layout lease. Retain schema 13 and the preset-only headless
startup contract. Validate canonical even dimensions and an 8192-pixel canvas
limit at every request boundary. Generate timing data on the Host, execute as
the active desktop owner, verify XRandR and Mutter geometry, and restore the
pre-session layout after failure or disconnect. Never restart the display
manager to match an active physical desktop.

Optional feature `0x800000` carries the Client OS primary display as a bounded
left-to-right index. Verify primary in both XRandR and Mutter; save and restore
the original XRandR primary property alongside the MetaMode. Read restoration
back instead of trusting NVIDIA's exit status. The experimental macOS 15 Client
includes the measured five-point native-fullscreen margin below the camera,
qualified against the settled drawable. Newer OS versions retain their existing
geometry until independently measured.

When primary matching is negotiated, preserve the active Host primary output's
connector identity and assign it to the Client primary's requested position.
If the saved primary property names an inactive output, retain the first active
output instead. Select the remaining connected outputs in desktop order. This
keeps applications with independent physical-output enumeration on the intended
primary display across single-output and matched-output sessions. The Client's
left-to-right geometry and the exact pre-session restoration contract remain.

Qualification: parser and mode-boundary tests on both products; transaction
failure/rollback/cleanup tests; clean pinned builds; live logical and backing
matching, input mapping across both displays, and exact disconnect restoration.
Keep the accepted Client artifact available until the new candidate is accepted.
