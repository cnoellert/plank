# Vulkan Loader 1.4.362 qualification

September 17, 2026. Build-deps PR #1 adds a required ID-filter allocation
repair to the paired Vulkan Headers/Loader upgrade. This is not an NVENC SDK
or driver upgrade. NVIDIA driver qualification remains capped at 595.91.07.

## Source and reproducibility

- Build-deps: `9f2ea61423fb1dd1c1b0eda463b3260837630064`.
- Headers: `ee2ec5fd83dafce291024683b50dc89219333076`.
- Loader: `b8b96a2862bff1eed468e602d43f706beae89cf1`, with the tracked repair.
- Host candidate: `4d80cf9594cfe58483422449346f46dbcb50f05f` (dependency pin only).
- Root package source: `bf72318baaedcbff1d93edaf87bebd73010e4cc5`,
  `1.0.126-vulkan-loader-repair`.
- Client and transport pins are unchanged.

The required production patch is applied independently of optional FFmpeg
patch switches. A source/patch mismatch is fatal. The package preflight checks
reverse application, expected tracked modifications, and patch reject/backup
residue independently of bootstrap. Upstream dependency preparation omits
`Vulkan-Loader/tests/`; only tracked deletions inside that directory are
permitted. Modified test files and deleted production files remain failures.

Fresh and repeated application, mismatch rejection, and a second clean Loader
source reproduced the expected repair. Ten root preflight tests pass. The first
cache-bypassed hosted bootstrap (`35278812273`) compiled the fresh dependencies
and applied the patch, then caught the new verifier's missing allowance for
that deliberately omitted test directory. Root `b349689` corrects it with
specific regression coverage. Rerun `35279985121` found a quoted emoji test
filename still counted as a production change. The verifier now consumes
NUL-delimited paths and the test fixture includes a non-ASCII name. Reproduction
with the exact upstream source and actual CMake copy exclusion passes all nine
required patches, repeatedly. Replacement cache-bypassed run `35281178139`
passes the complete fresh dependency bootstrap, Host compile and RPM gates.

## Completed isolated Loader checks

- Fresh GCC Toolset 14 build: all 713 upstream and added tests pass.
- Twelve added cases: both physical-device enumeration APIs, count-only and
  output-array calls, three ID-filter allocations, cleanup and successful retry.
- Negative control: all twelve cases crash against the same unpatched Loader.
- NVIDIA RTX 6000 Ada / 595.91.07: filtered enumeration and 100 repeated
  instance/device/device-group enumeration/teardown cycles pass.
- FFmpeg using the isolated repaired shared Loader: 120 3840x2160 RGBA frames
  survive GPU upload/download byte-for-byte.
- The same check with twelve packed XR30 frames generated from a changing
  10-bit RGB ramp is byte-identical. Direct planar `gbrp10le` transfer is not
  supported by the installed diagnostic FFmpeg path; the XR30 result is not
  being claimed as planar transfer support or encoder fidelity qualification.

No system Loader or driver was replaced. The dependency's old
`BUILD_STATIC_LOADER` setting is not consumed by upstream on Linux: the actual
result is a shared Loader. This candidate does not invent a static-linking
implementation. Production Host Vulkan encoding remains disabled by its
existing build policy; these isolated checks do not claim that the Host RPM
ships or loads this private Loader in a normal NVENC/x264 session.

## Hardware baseline checks and limits

The exact candidate source was checked out on the authorized hardware test
Host. Read-only KMS inventory, Wacom inventory and PAM account-policy checks
pass. NvFBC completed 600 forced-refresh capture calls at 60.00 fps with no
driver-missed frames. The desktop was mostly static; this is not a moving-video
soak. The unchanged installed diagnostic FFmpeg encoded 120 2160p60 frames as
HEVC Rext `yuv444p10le`, with intra-refresh, successfully.

The standalone NVENC capability probe passes against the unchanged SDK 13.0
headers when compiled with an explicit `-include cstdint`; its source lacks
that required direct include. Two other pre-existing standalone CUDA probes
refer to functions absent from the pinned `CudaFunctions` structure, blocking
the complete root qualification build and its video-pipeline self-test.

After installing the missing test-only `ripgrep` tool and setting the explicit
detached branch context, 28 root CTest entries pass. One remaining source guard
expects the retired unbounded Client reconnect loop; the current Client uses
`waitForPlankReconnectRequest()`. The other unavailable test is the above
video-pipeline self-test. Neither is caused by a Vulkan source change, but the
complete root suite is **not** recorded as passing. Repair these qualification
harness issues separately rather than restoring retired Client behavior or
raising the NVIDIA SDK requirement.

## Package and installed-state checks

Hosted run [35281178139](https://github.com/instinctual/plank/actions/runs/35281178139)
passes on a fresh Rocky Linux 9.7 container with both dependency cache restore
and cache save bypassed. Bootstrap and package preflight each prove all nine
required dependency patches. The application build uses `BUILD_TESTS=OFF`,
as required for normal candidate package construction.

The 8,569,293-byte RPM is collected under
`artifacts/packages/candidates/1.0.126-vulkan-loader-repair/linux/`:
`plank-host-1.0.126-0.vulkan_loader_repair.1.el9.x86_64.rpm`.
SHA256: `91ee34acda624b723fc116d48fdbc1e41e438e60d31e01e5748d306e6f7677e7`.
Source/branch/version, payload paths, runtime closure, required log-directory
ownership, manifest, privacy-path and absence gates pass. The private Loader
is not included in this RPM and is not a new ELF dependency.

The exact hash-verified RPM was installed on the authorized hardware test Host
after confirming no active PLANK transport socket. Media, supervisor and broker
binary hashes match the extracted RPM. Both services are active; discovery
reports `1.0.126-vulkan-loader-repair` and all seven expected encoding modes.
The service restart count is zero, systemd verification succeeds, and the
administrator configuration checksum is unchanged. NVIDIA remains 595.91.07.
No desktop-manager/display-prepare restart or reboot was performed.

No interactive Client, Wacom-event, audio/WAN or long-soak acceptance is implied
by these checks. The full root qualification blockers above remain open.
After recording these limits, the operator authorized merging build-deps PR #1.
Its merge into `plank/main` is `1078cb1d688397480915ee9904308ed76c9bb3d0`;
the merge tree matches the tested PR head exactly. At that qualification point,
Host/root companion branches remained unmerged, and no release was performed. Existing package provenance
continues to name its exact pre-merge source. Deployment endpoints, account
details and raw hardware reports remain outside public Git.

## Current-main verification integration

The current Host already pins build-deps
`c29c4822cb96f5bfeb8640e72601c5cf4e3c3137`, which includes both the Loader
repair above and the subsequent x264 update. Keep that pin, the current Host
gitlink and package version; the earlier candidate pins are historical evidence,
not replacements for current inputs.

The parent integration preserves the old branch's history while carrying forward
only its independent Loader preflight, CTest registration, regression suite and
qualification notes. It also corrects the obsolete dependency-maintenance entry.
The twelve preflight cases include the original ten plus rejection of production
source moved under `tests/` and proof that the test-directory deletion exception
does not apply to FFmpeg. CTest registers this Linux Host-specific suite only on
Linux; it does not impose Bash/GNU tooling on macOS checkouts. No capture,
encoding, presentation or driver code changes.
Hosted [run 35360266594](https://github.com/instinctual/plank/actions/runs/35360266594)
at root `0865e02adf82598156b137642e1f35a2465ab7e4` passes a cache-cold
dependency bootstrap, fresh Host compile and RPM packaging. Bootstrap, package
preflight and cache sealing each verify all nine required patches. A negative
control confirms the old verifier accepts an unpatched Loader fixture which the
new verifier rejects. Local regression/portable suites pass; the subsequent
Linux-only CTest-registration refinement changes no product build input.
Package provenance and current integration state are in HANDOFF; the historical
hardware checks above must not be presented as a new interactive qualification.
