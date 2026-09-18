# PLANK handoff

## Mac overlay replacement fix — in progress

The operator reported intermittent toolbar flashing while testing1.0.131 and
authorized a scoped repair. The Metal overlay updater cleared the old texture
before preparing its replacement, allowing the separate render thread to omit
the toolbar for a frame. That updater was byte-identical in1.0.124 and1.0.131;
changed timing/RTT redraws exposing it is a hypothesis, not captured live proof.
The separately reported horizontal menu-bar edge disappeared and remains
unattributed; do not claim this patch resolves it.

Candidate1.0.132-pr-integration preserves the old complete texture until the new
one is uploaded, swaps under the existing lock, and retains the old image on
allocation failure. Only explicit hide clears the slot. Host, shaders, video
geometry, transport, input and Linux runtime code are unchanged. A new headless
Mac regression exercises the production updater with controlled Metal resource
doubles; it is mandatory in the Mac Client build. Native execution, signed
hosted build, package collection and live flicker acceptance are pending.

## Combined test packages — 2026-09-18

Current package-source root is `c225083ebd27d06e63296e9df3bd55a99f92f6ed` on
`pr-integration`, for `1.0.131-pr-integration`. All remaining PRs stay on hold.
The operator requested a compact RTT column immediately left of
the Encoder Target segment. The follow-up pins Client
`261c250bb8098908f434019ba0b6363ff00bc031`. It reuses the existing once-per-second
QUIC RTT measurement for both toolbar and overlay (`Network RTT`), sharing
formatting and unavailable state. The slider and target text share measured
width reserved for all valid bitrate values; endpoints do not move while
dragging. Toolbar height and pointer routing are unchanged. Native Qt tests
cover formatting and text/slider/control spacing and pass on both Client
builders (23 toolbar results each). Host and transport code/pins remain
unchanged by this follow-up.

Baseline `1.0.130-pr-integration` uses root
`f8b76119ff3e2fa46e71ae9b68e6d74e2f06b331` (before RTT). Hosted build run
`35317481578`, signed Mac Host `35317500220`, signed Mac Client `35317502640`.
All four baseline products passed and were checksum-collected. Privacy and
clipboard checks passed. Local 43 CI-policy
tests, six portable CTest suites, release-version checks, seven fullscreen and
three Quit guards passed; follow-up source checks also pass 14 reconnect and
four interface-MTU cases. The baseline finished before the follow-up was pushed;
1.0.131 packages are fresh builds, never relabelled. No hardware acceptance yet.

The operator authorized an integration branch and all four test packages from
already-merged PRs. Work is on `pr-integration`, based on main
`4144a3d48d14e921295c4055362289a7211fe960`, with package version
`1.0.130-pr-integration` for the initial baseline. Do not merge pending display or dependency PRs,
publish a production release, or deploy these packages as part of this task.

- Baseline Client is merged `a6a97d024269aa5c8523a2e50e0a887208cf4a05`, including
  clipboard, input queue/release repair, mDNS and Mac multi-display/raw Wacom
  work. Common-C stays `16a7a503b2cfafad12faeedbc67257f7a1c0deb8`; qmdnsengine
  stays `920c097ffa742e2968290f15d4dde6693aec02e5`.
- Linux Host incorporates merged main `747a7fff22873f4cf2d1a4aac56111f970456067`
  (common build tooling and Wayland protocol updates), plus pin-only commit
  `f3ab763a31288f392fb94743cb47ee580d9cc01e` on its `pr-integration` branch
  for the already-merged dependencies below.
- Build-deps advances to `c29c4822cb96f5bfeb8640e72601c5cf4e3c3137`: reviewed
  Vulkan updates with the allocation-failure repair/tests, and x264
  `0480cb05fa188d37ae87e8f4fd8f1aea3711f7ee`. NVIDIA headers remain
  `e844e5b26f46bb77479f063029595293aa8f812d`; driver ceiling 595.91.07 remains.
  Vulkan Headers/Loader pins are `ee2ec5fd83dafce291024683b50dc89219333076` /
  `b8b96a2862bff1eed468e602d43f706beae89cf1`; other codec gitlinks are unchanged.
- libvirtualhid advances to `a0d3aa0cc4d53daa18bfa2f2fbdf848957b6d294`, including
  the merged Pause-key release fix and common tooling/documentation updates.
  Host common-C remains `88fd5ac594ce9fa8b7e01530a7830aba3fc0b986`.
  Its doxyconfig/common pins are `419127bad87f49b2d45fa957ea7302abbb49c01f` /
  `f9d91e1d29b7473f58e43acde4579da4e56c4abe`.
- Host common tooling is `f9d91e1d29b7473f58e43acde4579da4e56c4abe`, with
  Host-owned GoogleTest `52eb8108c5bdec04579160ae17225d66034bd723`.
  Plasma/Wayland protocol pins are `382dfabda886d3f2f5c067b22e5a22376685ba78` /
  `819004adb3ab7e46f3fa3caef05b96e20434b244`; other Host gitlinks are unchanged.
- Kymux advances to `6f3df8e2c9eac41d4bc0ec9d3f1fc9cbf8d1a804`, a Dependabot
  configuration-only change; transport implementation is unchanged.
- Physical-monitor mode changes and the pending Retina bookmark dropdown are
  excluded. Remaining dependency PRs are excluded. No new runtime edits are
  part of the baseline pin synchronization; RTT is the separate UI follow-up.

Final hosted run `35318811736` passed all four product jobs. Signed Mac Host
`35318811682` and signed Mac Client `35318813819` also passed, including
notarization/stapling and temporary-signing-material cleanup. Mac Client native
Qt total is126, including the23 toolbar results. Privacy and clipboard
regressions pass at the exact package-source root. All products rebuilt fresh;
dependency caches were restored and independently verified. Only the exact
reviewed `pr-integration` branch was added to the protected signing environment;
public PRs still have no signing authority. No deployment or GitHub release.

Packages are collected under
`artifacts/packages/candidates/1.0.131-pr-integration/`, with exact source,
top-level gitlinks, package sizes and SHA256 in `manifest.json` / `SHA256SUMS`.
Linux Host is Rocky9.7/x86_64, Client is Ubuntu26.04/amd64; both Mac packages
are Apple Silicon, Host27-only and one Client15+ package. The baseline1.0.130
catalog is retained separately; prefer1.0.131 for testing RTT.

Existing hardware gates below still apply, particularly Linux identity encode/
decode, input/clipboard, and the identical Mac Client package on macOS15/macOS27
with physical Wacom focus, reconnect, pressure and release recovery.

Discussion only: the operator asked about lowering the Mac Host minimum to15.
No Host target or compatibility code was changed. SDK27 plus runtime availability
checks can retain newer capabilities, but headless virtual displays, login/
logout, first-user permissions, audio and real HEVC44410/5K encoding require
separate macOS15 qualification. Do not infer Intel support or silently downgrade
encoding profiles. Keep this work separate from the current test package set.

## Mac Client integration — 2026-09-17

The operator authorized approval and merge of Client PR #3 and root PR #4.
Client #3 is merged at `a6a97d024269aa5c8523a2e50e0a887208cf4a05`; the parent
pins this exact mainline commit. Its tree is identical to tested Client
`82436e5ada0e6139c967a167a5079d6ab1cbbdcd`. This is integration approval, not a
signed release or a claim of completing the remaining hardware gates.

- One Apple Silicon Client package targets macOS 15 and newer with SDK27+,
  preserving newer capabilities with runtime availability checks. The Host
  remains macOS 27-only. Build/bootstrap/cache/DMG checks share the deployment
  policy and reject newer-minimum dependencies or unguarded newer API calls.
- Multi-display Metal presentation, native fullscreen Spaces, cross-display
  mouse/pen focus and raw USB Wacom forwarding are included. Current upstream
  Quit/Command-Q and clipboard handling are retained.
- Wacom fix `a6faf27a` preserves focus/reconnect intent after a bounded release
  wait expires, but resumes only after worker-confirmed physical release.
  Newer focus loss/reconnect/Quit requests take precedence. Stale callbacks
  remain excluded; the worker owns its lifetime after a timed-out shutdown.
- Common-C stays `16a7a503b2cfafad12faeedbc67257f7a1c0deb8`, containing the
  merged input queue ordering and release-delivery repair. Linux Host remains
  `42c1a13618b04d80ac15c2e46c9ad5e2058c700e`; other recursive pins are unchanged.
- Version base: 1.0.129. Hosted run `35312646798` passed all four product jobs
  at root `915f64a549c39d7bb79bd366d9c018b3deb979d3`. Mac Client: 124 Qt results,
  six target-validation fixtures and the native input-worker gate passed,
  including fresh SDK27 dependencies with minimum15.0. Privacy and clipboard
  jobs passed. Mac signing was disabled. The merge pin has identical source
  bytes; documentation changes do not change those results.
- Portable validation: 43 CI tests, six root CTest suites, seven fullscreen and
  three Quit guards passed. All 11 Wacom Qt results passed 30 repetitions and
  ASan/UBSan with leak detection. This is not stalled-driver fault injection.

Next release gates: the identical packaged Client on macOS15/macOS27, Ubuntu
regression, physical Wacom pressure/focus/reconnect/Quit/hotplug, sleep and
held-input recovery, and investigation of the previously intermittent live
left-click loss. Earlier live successes belong to their exact candidates, not
this final source. No installation or signed release was performed here.

Linux physical-display matching remains separate: Client
[#4](https://github.com/instinctual/plank-client/pull/4), root
[#7](https://github.com/instinctual/plank/pull/7), Host
[#2](https://github.com/instinctual/plank-host-linux/pull/2). This integration
does not package that display helper or alter physical-monitor mode policy.
See [the integration review](docs/development/macos15-integration-review.md)
and the chronological [Mac Client record](docs/development/macos15-client.md).
Earlier checkpoints below are retained as historical context.

Read AGENTS.md and the platform build runbook before work. Read the private
notes' README before machine-specific work; deployment information stays outside Git.

## Current state

- The operator authorized the combined clipboard merge. Client PR #2 is merged
  at `05445865d3f8f6d58102a4fb4c45b712545ece1e`; Linux Host PR #1 is merged at
  `42c1a13618b04d80ac15c2e46c9ad5e2058c700e`. Parent PR #3 pins those exact
  mainline commits. Both merged dependency trees are identical to the tested
  Client `f13654d329eec4c099e6eb848ae886f04050f2cc` and Host
  `7771aba399b6853c7cb37aed300bc1aefb16be36` inputs. Clipboard sync is macOS
  Client to Linux X11 Host; Linux Clients do not advertise an implementation
  they lack. Pasteboard ownership, bounded X11 INCR transfers and canonical
  dependency sources are fixed. See `docs/development/clipboard-review-followup.md`.
  Common-C Host/Client pins are
  `88fd5ac594ce9fa8b7e01530a7830aba3fc0b986` /
  `16a7a503b2cfafad12faeedbc67257f7a1c0deb8`; mDNS remains
  `920c097ffa742e2968290f15d4dde6693aec02e5`. Other recursive pins are unchanged.
  Thirteen isolated Xvfb cases, five negative controls, 42 CI policy checks and
  all five root CTest suites pass. Hosted X11 run `35290252469` and privacy
  checks pass at root `b0026c503f713016901bc5650a22371a4b7e1ef1`. The Xvfb suite
  also passes ASan/UBSan with leak detection. Hosted run `35290252364` passed
  all four products, including the Linux Host RPM, platform negotiation on both
  Clients and all 20 native clipboard Qt results (suite init/cleanup included).
  The parent merge changes dependency commit identities to their tree-identical
  merge commits and updates notes, not tested product code. These Mac builds
  were unsigned. No release publication, deployment or live paired-session
  acceptance was performed; mainline CI is separate from the completed feature
  build. Remaining paired-system checks are documented in the follow-up.

- GitHub Actions update is approved and merged through root PR #8: merge
  `7a86b907ec2e80907198cb55cf2b57f8d77de5ab`, reviewed head
  `2be3d797046df177589cb0c1b97e3cb5d109ade1`, including the merged Rustls
  update. Checkout and artifact upload move to 7.0.1; cache restore/save move
  to 6.1.0. All use Node24 and verified upstream full commit-SHA pins. The two
  existing policy tests' reviewed hashes and stale cache comments are updated;
  read-only permissions, credential persistence off, exact cache checks, PR
  cache-write exclusion and signing isolation are unchanged. Local validation:
  42 policy tests and eight negative controls pass. Hosted runs `35274932266`
  and `35274938316` both passed all four platforms plus policy/privacy checks.
  Existing Mac Host cache restore/verification and new Mac Client/Linux Client/
  Linux Host cache saves succeeded. Client cache misses preceded publication
  of their identical new mainline cache keys; they were not an Action format
  incompatibility. Downloaded DEB/RPM catalogs passed checksum, exact-source,
  gitlink and branch-qualified version checks. Mac jobs were unsigned; no
  signing, release publication, deployment or hardware qualification performed.
  No product code, dependency gitlink or package version changes in this
  CI-only update. The automatic post-merge mainline build is separate from
  these completed PR checks; do not relabel the candidate packages.

- Rustls security update is approved and merged through root PR #9: merge
  `8f1ad75bede2fc6948315cb61d7ef380d29ff4df`, reviewed head
  `617cecc6990b01967137536a744971cba94411cc`. Both production and standalone
  probe locks now select 0.23.45, addressing upstream GHSA-2mjx-qc3c-rqvc.
  A CI guard requires the two Rustls identities to remain synchronized.
  Quinn's repaired path override, RaptorQ, all product gitlinks and media
  behavior are unchanged. Package base advances to 1.0.125 for new build bytes;
  no release or deployment is authorized by this dependency change alone.
  Hosted runs `35272691429` and `35272698006` both passed all four platform
  builds plus policy/privacy checks. Post-merge main run `35274307903` also
  passed all four platforms. Mac signing is deliberately skipped for
  these candidate checks. Local Rust 1.89.0 validation passed 21 unit tests,
  the standalone probe locked check, 42 CI policy tests, native C ABI media/
  control/closure checks, 40 repeated peer-close cases, and rejection of a
  mismatched certificate fingerprint. The optimized 150 Mbps loopback loss
  matrix passed at 0.5%, 1%, 2% and 5%. An initial debug run timed out during
  concurrent local build activity; the unchanged baseline and an isolated
  candidate debug rerun passed (about 148/150 seconds), as did the optimized
  candidate (about four seconds). These are synthetic tests, not fresh
  hardware/WAN qualification. No packages were deployed or release published.
  Product pins remain Client `86682b5b596e5c31b81a6e2a4b238bb62dc6e42c`,
  Host `9329784ac41f50cbec0c9d76badfd22227ec5e5f`, and Kymux
  `912ece5c64787997f978673ca60d313898a3548c`; recursive pins are unchanged.
  The operator's NVIDIA driver ceiling remains 595.91.07; this update changes
  no NVIDIA dependency or requirement.

  Separate follow-up: Kymux's audio UnreliableFec receiver can buffer completed
  audio received before its configuration, then wait for another inbound
  message before delivering it. A receiver-only reproduction at the production
  Kymux pin demonstrates this without TLS/QUIC: config-first delivers audio;
  datagrams-first delivers config but stalls the ready audio. Inspect
  `kyproto/src/protocol/driver/av/audio_unreliable_fec.rs` before a separate fix.
  This is a possible cause of the original intermittent macOS loopback timeout,
  not proof of that run's ordering. The Rustls PR adds detailed failure output
  only; assertions and the five-second deadline remain unchanged. Do not mask
  this with retries or mix its runtime fix into a dependency-only update.

- Dependency maintenance setup adds weekly Dependabot proposals to the root,
  Host, Client, Kymux, build-deps and libvirtualhid repositories. Common-C's
  maintained branches have no dependency manifests; do not resurrect its
  inherited ENet tree to produce update PRs. Security alerts/security-fix PRs
  are enabled for all seven public repositories; auto-merge stays off and
  companion build workflows stay disabled. Build-deps/libvirtualhid proposals
  target `plank/main`, with configuration also on the inherited default branch.
  Host/Client common-C branch hints now name `plank/host` and `plank/client`.
  No production gitlinks, library versions, lockfiles or packages change.
  See `docs/development/dependency-maintenance.md` for manual pin coverage,
  Quinn/Vulkan exceptions and the next advisory/upgrade review steps.
  Validation: all six Dependabot configurations pass JSON-schema validation,
  schedule/allowlist/target-branch checks; 41 root CI tests pass. Privacy and
  whitespace checks pass. GitHub confirms alerts and security updates enabled,
  auto-merge disabled, on all seven repositories. Configuration-only commits
  are pushed (root gitlinks deliberately retain released source):

  | Repository / branch | Maintenance commit |
  | --- | --- |
  | Host / main | `6bef0d706a787a36eb456343cb4c6a719947c93c` |
  | Client / main | `174bc1ff99bf437cd84efa028590ddc481953851` |
  | Kymux / main | `6f3df8e2c9eac41d4bc0ec9d3f1fc9cbf8d1a804` |
  | Common-C / atomics (policy only) | `9707808a0a949eaa7713c02811b848ed98064221` |
  | Build-deps / plank/main | `8956f6425b0e35b4038025be682d2ba1a0225b69` |
  | Build-deps / master (activation only) | `5490628476568af75fd563ff097ad5d447ccbea3` |
  | libvirtualhid / plank/main | `a74f9694fe4bec29a4643975ced6da4cdedbf04f` |
  | libvirtualhid / master (activation only) | `62838758220d594d008d42e0c90e1210c49c1a79` |

  Initial GitHub Dependabot jobs all completed successfully: root Cargo
  `35270141576`, Actions `35270137176`, submodules `35270136847`; Host
  `35270026662`, Client `35270030228`, Kymux `35270045661`, build-deps
  `35270044386`, libvirtualhid `35270045226`. First update PRs are open on the
  intended targets; none were merged. This validates automation, not the
  proposed dependency versions. Root setup commit is
  `6377245de4a1e82b201320877c0a7858fb87054f`. No candidate build or deployment
  was needed for this configuration-only setup. Quinn automatic security-fix
  PRs are also excluded by the explicit ignore rule; alerts still require
  manual triage against the repaired production fork.

- The operator accepted 1.0.123 and authorized commit, push, merge, rebuild
  and release. Root and Client are on pushed main: package-source root
  `cb01cfe84504d7a74dfa78c5b79d701c8277bf6e`, Client merge
  `86682b5b596e5c31b81a6e2a4b238bb62dc6e42c`. Mainline 1.0.124 rebuilds all
  four Host/Client packages on GitHub-hosted builders with dependency caching:
  Linux Host 35186794247, Ubuntu Client 35186794278, signed Mac Host 35186794535,
  signed Mac Client 35186794688. All four passed, restored independently
  verified dependency caches, and produced fresh mainline packages. Both Mac
  packages passed signing/notarization/stapling/Gatekeeper; Client native suite
  totals were 19/21/7/9/8. Local 37 CI tests, five fullscreen and three lifecycle
  guards, plus all five root CTest suites passed. All downloads were
  SHA256-verified and collected under `artifacts/packages/releases/1.0.124/`.
  Published [v1.0.124](https://github.com/instinctual/plank/releases/tag/v1.0.124)
  as latest with four packages, manifest and checksums. All six GitHub asset
  digests match local files. The annotated tag pins the exact package-source
  root above, not subsequent documentation commits. No deployment performed.
  See `docs/releases/1.0.124.md`. Client
  merge contents match the accepted candidate exactly; Host/Kymux and recursive
  pins are unchanged. Do not relabel candidate artifacts. Clipboard PRs and
  unrelated primary-worktree RK3576 research remain excluded.

  | Package | SHA256 |
  | --- | --- |
  | Linux Host RPM | `fafd9624125738f688cb0336efba754088f78e56ecccadfe67be7da21d205c43` |
  | Ubuntu Client DEB | `855e9fbb1f66980d02aad5e1860f947940a17c26c08819e380be631f89e58308` |
  | macOS Host PKG | `fa05b6c8414728f49a768d2eff3784157a18d5d5e7a6de5d36e2db9f5d4bf748` |
  | macOS Client DMG | `a0c8564f3cfca02733e86b41d1dc7755a110b47778e83121f222a51f933919bf` |

- Accepted root/Client candidate branch is `macos-quit-lifecycle`, candidate
  `1.0.123-macos-quit-lifecycle`. The operator accepted 1.0.122's behavior but
  requested a fresh implementation without the contributed Quit bridge.
  That bridge is deleted, not layered over. MacApplication explicitly owns
  application exit: cancel active/startup/reconnecting sessions once, retain
  Qt until queued readyForDeletion completes, then perform normal Qt Quit.
  The SDL loop observes explicit exit state, not an injected SDL Quit event.
  Ordinary disconnect remains independent. The tested native Command-Q guard
  is unchanged. Linux, Host, transport and protocol behavior are unchanged.
  See `docs/development/plans/macos-quit-lifecycle.plan`. Local 37 CI, five
  fullscreen and three lifecycle source guards plus five root CTest suites
  pass. Hosted run 35185516514 compiled the application and passed existing
  topology/toolbar/desktop-stage tests, then caught a missing direct SDL include
  in the retained shortcut test after bridge removal. That test dependency is
  corrected; no package was produced by that failed run. Corrected signed run
  `35185783350` passed from root `be387875a3fde8dd87c5a3b4c046d368f1a58457`,
  Client `be8a1e06cba05299f939cea2bc4f440bef1a9196`. Dependency cache restored
  and independently verified. Native suite totals: topology 19, toolbar 21,
  desktop-stage 7, shortcut 9, application lifecycle 8 (totals include suite
  init/cleanup; the latter two have seven and six actual cases). All passed.
  Signing/notarization/stapling/Gatekeeper and signing cleanup passed. Verified
  86,548,985-byte DMG is collected under
  `artifacts/packages/candidates/1.0.123-macos-quit-lifecycle/macos/` as
  `plank-client_1.0.123-macos-quit-lifecycle_arm64.dmg`; SHA256:
  `58847e6616f240a98eb0a8180edefadaf1106ad19653e6f53f854e819f719a8c`.
  Host/Kymux and recursive Client pins remain those recorded below. Live
  acceptance of the rewrite was given by the operator; mainline rebuild and
  release are now authorized. No agent deployment. Preserve the
  original checkpoint branch and unrelated primary-worktree research.

- Accepted behavioral checkpoint: `1.0.122-macos-command-q`. Client commit
  `aaaa6b2ba17fa6e3b212b61a0eb8d938046b8f58` and package source root
  `70928380313edd7ab129bef10524384dd0ce3f39` are pushed. Signed hosted run
  `35183839235` passed with a verified dependency-cache hit, all existing Mac
  suites and eight new `macquitshortcut` test cases (10 Qt results including
  init/cleanup). These native tests run in every Mac Client build. Signing,
  notarization, stapling and Gatekeeper passed. The verified 86,124,020-byte DMG
  is collected at `artifacts/packages/candidates/1.0.122-macos-command-q/macos/`
  as `plank-client_1.0.122-macos-command-q_arm64.dmg`; SHA256:
  `252b4f25ed05aa164b041fe48597d98bb4d2b894ef738cb38c1c356972b0bdbf`.
  Unchanged Host, Kymux and recursive Client dependencies are recorded below.
  Local CI tests (37), fullscreen tests (5), shell syntax and whitespace checks
  pass. The operator reports this works as intended. That broad acceptance
  does not prove every lifecycle scenario; the rewritten candidate needs fresh
  menu/Dock, captured Command-Q and disconnect acceptance. No merge or release
  publication of this checkpoint.

- Mainline 1.0.121 package rebuild completed from pushed root
  `41961fb5e9ef8329711e04d1adf75cc4b2968ce3`. Client PR #1 is approved and
  merged at `b9e4be6b374001bef08ac4753764bc12edcb8357`; the root Client pin
  now includes the macOS native application Quit bridge. Linux Host and Kymux
  pins are unchanged. Clipboard PRs are not included: their reviews requested
  changes. All four hosted builds and package gates passed: Linux Host
  `35166761486`, Ubuntu Client `35166763396`, signed Mac Host `35166765361`,
  signed Mac Client `35166767426`. Both Mac packages passed notarization,
  stapling and Gatekeeper. All downloaded packages passed SHA256 verification
  and are collected under `artifacts/packages/releases/1.0.121/`, with manifest
  and checksums. Both Clients and Mac Host restored verified dependency caches.
  Linux Host had a cold miss because NVIDIA's two CUDA config-common RPMs
  advanced from 13.4.49 to 13.4.92; its successful build saved the new cache.
  Local CI tests (37) and package-collection tests (6) passed. See
  `docs/releases/1.0.121.md` for build links and validation scope. Published as
  [v1.0.121](https://github.com/instinctual/plank/releases/tag/v1.0.121)
  at the operator's request. Its annotated tag identifies the exact package
  source above, not the subsequent documentation commits. Server-side SHA256
  digests match all four packages, manifest and release checksum file. No
  installation or native hardware acceptance was performed. Unchanged Linux Host is
  `9329784ac41f50cbec0c9d76badfd22227ec5e5f`; Kymux is
  `912ece5c64787997f978673ca60d313898a3548c`. Client common-c is
  `b9650552f98d97f6e30c9f007115c6246f0809e5`; qmdnsengine is
  `b7a5a9f225d5e14b39f9fd1f905c4f505cf2ee99`. Host recursive pins remain
  as recorded below.
  Source review found no actionable defect in the Quit bridge, but native
  menu/Dock Quit during streaming/reconnect and physical Command-Q ownership
  remain live validation follow-ups. The author's reported eight lifecycle
  scenarios are not committed tests and were not independently rerun.
  Preserve the primary worktree's unrelated RK3576 research.

- Dependency-cache follow-up is merged and pushed to main at
  `4bd87fbcf5c96d177006ac0ea0c99b532396d5b5` (based on main `4001161`).
  All four hosted products are wired for exact-input caches; the previously
  qualified Mac Client cache format is unchanged. New Linux Host/Client caches
  retain prepared FFmpeg and patch-verification sources; Host also retains
  Boost. Those products and Mac Host cache Rust toolchains/downloaded Cargo
  inputs, never application/transport objects or credentials. Installed Linux
  package/compiler versions and dependency scripts/pins/patches invalidate keys.
  Pull requests cannot save caches; clean bootstrap bypasses restore and save.
  Local 37 CI tests and all five root CTest suites pass. Hosted cold/warm
  qualification passed for all four products; exact runs and phase timings are
  in `docs/development/build/github-builds.md`. Linux Host cold/warm used
  `35144970937` attempts 1/2 at `478edad0ee302c22c713df1cb67b4c4c185340a5`.
  The Ubuntu-specific archive correction is `64f368a4fdb58cc0de267bc8f59ec108a8f43be8`;
  its cold/warm runs `35146540028` / `35147537196` both passed. Initial warm
  run `35146202369` was correctly stopped by the source audit because the cache
  omitted the pristine FFmpeg archive. The archive is now cached and required
  by completeness tests; no source/patch gate was weakened. Mac Host warm run
  `35145530809`, Mac Client warm run `35145993419`, and an additional Mac Host
  cold build at the corrected source (`35146543166`) passed.
  The Ubuntu correction changes cache keys but not the qualified Host cache
  contents/logic. Application and transport source revisions remain identical
  to the 1.0.120 release below. No runtime change, version bump or deployment.
  Post-merge hosted run `35148481593` passed all four products at that exact
  merge SHA and populated main's branch-scoped caches. Do not relabel the CI test packages
  or replace the published 1.0.120 assets. No additional deployment requested.
  Completed root branches `dependency-cache`, `macos-auth-recovery`,
  `macos-fullscreen` and `reconnect-lifecycle`, plus the Client's three matching
  macOS/reconnect branches, were deleted locally and remotely after ancestry
  checks against pushed main. Their commits remain in main. Root, Client,
  Linux Host and Kymux remotes now have only main. Preserve the local
  `rk3576-client` research branch and its dirty primary worktree; it is not
  disposable merely because its committed starting point is an ancestor of main.

- Operator accepted Client 1.0.119-macos-fullscreen and authorized commit,
  push, merge and a full rebuild. Root merge `53c7c3988f88a440f1cffeda0ce61ed526de6c43`
  and Client merge `95060dee8fa63e0da98dfa83e7ddd8185731a837` are pushed to main.
  All four Host/Client packages rebuilt successfully as 1.0.120 from that exact
  root on disposable GitHub-hosted builders with `clean_bootstrap=true`.
  Successful runs: Linux Host `35137573043`, Ubuntu Client `35137572752`,
  signed Mac Host `35137572797`, signed Mac Client `35137572549`.
  Package, dependency, version and platform regression gates passed; both Mac
  packages passed Developer ID signing, notarization, stapling and Gatekeeper.
  All four downloaded packages passed SHA256 verification and collection with
  exact source provenance under `artifacts/packages/releases/1.0.120/`.
  At the operator's subsequent request, all four packages were published as
  [v1.0.120](https://github.com/instinctual/plank/releases/tag/v1.0.120).
  The annotated tag identifies the exact package source above. Server-side
  SHA256 digests match all four packages, manifest and release checksum file.
  Notes are in `docs/releases/1.0.120.md`. No installation or new hardware
  acceptance was performed. Preserve unrelated primary-worktree research. Earlier candidate
  packages below are historical evidence, not the current mainline artifacts.
  Normal full application rebuilds may reuse verified dependency caches;
  reserve cold bootstrap for explicit qualification. At this release's source,
  caching existed only for the macOS Client; the follow-up above extends it.

  | Package (relative to the 1.0.120 catalog) | SHA256 |
  | --- | --- |
  | `linux/plank-host-1.0.120-1.el9.x86_64.rpm` | `b74fd2486ab5864fb332d77d594b03c24ce76355c7651d24c3de3c05f49aa046` |
  | `linux/plank-client_1.0.120_amd64.deb` | `dea73b7f9ac840010ce02f15154b4ae2d4020ef61e925bc787ad0fb821074b53` |
  | `macos/plank-host_1.0.120_arm64.pkg` | `0fc01ce11172d075d864841d26a997c8bb5f5911032afff8536f43d98e244b35` |
  | `macos/plank-client_1.0.120_arm64.dmg` | `618a42f6ff8c86765f3a692b918c852ab7557a79e1733e0294999a219466765e` |

  Root and Client merge SHAs above pin the complete source tree; unchanged
  gitlinks are listed with the accepted evidence below. Linux Host common-c
  is `775943b5ac5e5100a3c2b1b89d9e21151dea4f29` and build-deps is
  `caf0495d5e6baff94f349853d4a59e3779a451a0`.

- Accepted Client 1.0.119-macos-fullscreen evidence:
  Operator tested all five standalone AppKit modes: no side borders, same
  system-owned top notch strip. Operator accepts that strip and native Spaces.
  New policy: Mac-to-Mac fullscreen Match Client uses NSScreen's dynamic top
  camera inset and preserves compositor backing density. Zero inset leaves
  non-notched displays unchanged. Windowed/manual sizing stays unchanged.
  Authentication, startup validation and reconnect use the same viewport;
  original display bounds remain separate for window placement/identity.
  Removed ineffective SDL content-size patch/hint/helper. Bootstrap/cache inputs
  changed, forcing fresh upstream SDL dependencies; FFmpeg patch gates remain.
  Local five fullscreen tests (including compiled geometry), 26 CI tests,
  14 reconnect guards and five root CTest suites pass. Signed hosted run
  `35131997746` passed from root `9167fd8412172fee9d47be9eb2bc67cc155d7750`,
  Client `6f0c25269c5a8bf1051814317440f2cd57fda005`: cold dependency bootstrap,
  SDK27 native compile, 19 topology / 21 toolbar / seven desktop-stage tests,
  package/version/dependency gates, Developer ID signing, notarization, staple,
  Gatekeeper and signing-material cleanup. New dependency cache sealed.
  Operator reports the fix works and accepts it. This is not a claim that every
  display/input combination was individually tested. No Host behavior change.
  Start a fresh fullscreen connection; toggling window mode alone does not
  renegotiate an existing Host resolution.
  Hash-verified DMG (85,582,956 bytes):
  `artifacts/packages/candidates/1.0.119-macos-fullscreen/macos/plank-client_1.0.119-macos-fullscreen_arm64.dmg`.
  SHA256: `58f8d4b56b6f68e3490e5c54b066030525e7ebee074ababcaccba96eaba709c9`.
  Unchanged gitlinks: Linux Host `9329784ac41f50cbec0c9d76badfd22227ec5e5f`,
  Kymux `912ece5c64787997f978673ca60d313898a3548c`; Client common-c
  `b9650552f98d97f6e30c9f007115c6246f0809e5`, qmdnsengine
  `b7a5a9f225d5e14b39f9fd1f905c4f505cf2ee99`.

- Superseded fullscreen evidence: Client 1.0.117 (root `aea1ab33`,
  Client `509f2fc7`, signed run `35124970815`) restored swipes but retained
  side borders; AppKit ignored the requested full-panel content size. The
  standalone 1.0.118 probe (root `21c29544`, signed run `35129303592`) passed
  build/signing and the operator compared all five modes. That probe is NOT
  Client 1.0.118. Its retained diagnostic DMG is under
  `artifacts/diagnostics/1.0.118-macos-fullscreen/macos/`; SHA256
  `8e391cf9c07ed7df9faaad1964f5319626e84a3f521c6527d8bec360600f06a9`.
  Full-panel override experiments are retired. See
  `docs/development/plans/macos-fullscreen.plan` for findings and acceptance gates.

- The operator authorized merging the reconnect follow-up into main after
  manually installing Host 1.0.116. Reconnect implementation root `4173138`
  and Client `e8fc0cc0` extend the previously accepted root `d34a110` / Client
  `060e6424`. The separate worktree (directory still named macos-auth-recovery)
  contains the continuation work; preserve unrelated primary-worktree research.
  Host and Client candidates 1.0.116 retain valid setup authorization across readiness retries,
  stop rejected authentication/TLS/permission failures, and gate new requests
  on the configured Ask/Disconnect deadline. Keep Waiting explicitly resumes.
  Mac Host retains authorized topology/display HTTP503 contexts within their
  unchanged original expiry; cancellation/rejection/failed launch still revoke.
  Linux Host is unchanged. See `docs/development/plans/client-reconnect-lifecycle.plan`.
  Local executable deadline/status checks, 14 reconnect source guards and 22
  CI tests and all five root CTest suites pass. Hosted compile/package gates
  now pass; live recovery acceptance remains pending. Host installation was
  operator-reported, not agent-verified; the agent only transferred and checked
  the package signature/notarization/hash. No release was published. Existing
  branch-qualified artifacts remain candidates; mainline packages require a
  fresh build and must not be relabeled.
  Host run 35074146670 at root f34ca0f passed same-token readiness/recovery
  tests but failed the cancellation gate: a deadline could expire before the
  network queue set its cancellation flag. Explicit monotonic deadline checks
  now revoke that context too; no 1.0.115 package was produced. Initial Client
  runs 35074149761 / 35074153250 were cancelled to include two review fixes:
  restart an authentication conversation paused behind Ask (its challenge can
  expire), and discard a transport completing after the deadline rather than
  keeping it hidden behind the unanswered prompt.
  Run 35074552628 passed the corrected cancellation gate but caught an unused
  synthetic-fixture counter; final Host run below includes that test-only fix.
  The primary worktree's `rk3576-client` research branch and uncommitted notes
  remain untouched. Published mainline remains Host 1.0.106, other products
  1.0.105. Do not select an old candidate paragraph as the current source.

- Current test packages are hash-verified under
  `artifacts/packages/candidates/1.0.116-reconnect-lifecycle/`:

  | Product | Source root | Hosted run | SHA256 |
  | --- | --- | --- | --- |
  | macOS Host PKG (6,611,153 bytes) | `4173138223c1d0b0a57ddac1977255ee6ea92b6a` | 35074853150 | `e443bc305bf3e03e3386378031d1cb40bce0de803bdba41bf77dfaa3c83a7717` |
  | macOS Client DMG (86,380,741 bytes) | `3a99c4489ddf40e6ab1557f88f012f711f7141bc` | 35074420641 | `92531ccd820e178245f91b532e0f4d208ac01ea2600a0d277176be08ebbac1d7` |
  | Ubuntu Client DEB (15,447,236 bytes) | `3a99c4489ddf40e6ab1557f88f012f711f7141bc` | 35074423798 | `e4873cfe03d8760ab4855c13429bd91bfcc7cddf359b0a799e6ea280382b1657` |

  Both roots use Client `e8fc0cc0c1d73d7cb78c81524fc0ee425c24ff05`;
  Linux Host, Kymux and recursive dependency revisions remain unchanged from
  the accepted work. The catalog records per-package source provenance.
  Mac Host passed seven real-TLS synthetic recovery scenarios (including 32
  repeated readiness requests using one authorization, ready-after-retry,
  cancellation and ownership revocation), 29 display cases, 128 permission-
  denial cleanup cycles, native input/audio/installer gates. Mac Client passed
  18 topology, 21 toolbar and seven desktop-stage/reconnect-policy cases.
  Ubuntu passed its desktop-stage/reconnect guards, exact dependencies, private
  FFmpeg, visible version and no-autostart gates. Both Mac packages passed
  Developer ID/notarization/Gatekeeper and signing-keychain cleanup.
  Next operator test: normal login/logout, temporary outage through Ask timeout,
  Keep Waiting followed by recovery, and Disconnect while paused. Definitive
  authentication/TLS/permission rejection must stop, not resubmit credentials.
  Do not induce production account lockouts for a test.

- Previously accepted Mac Client 1.0.114: root
  `ba91a32413b6d94e611bb48a873746e182209fea`, Client
  `060e6424ee9323f02ce53ce4e00e47427c0b6de8`. Signed hosted run 35071410245
  passed 18 topology/request cases and 21 toolbar-logic cases, dependency and
  version gates, signing, notarization, Gatekeeper, and credential cleanup.
  DMG SHA256 `0a986e97a2932b8e94f49ba95172d65f00df44245e13030a45252c97669d326e`.
  Size 86,349,889 bytes; hash-verified and collected under
  `artifacts/packages/candidates/1.0.114-macos-auth-recovery/macos/`.
  Manually installed and accepted by the operator; not installed by the agent.
  Pair with Host 1.0.113; no Host code/protocol change or Linux package required.
  Full-panel fullscreen correction is operator-accepted.

- Candidate 1.0.113 adds Retina-aware Mac Match Client: current logical desktop
  size AND current compositor backing pixels, for example 1710x1107 points at
  3420x2214 pixels. Display preparation is schema 3 with explicit integer 1x/2x
  scale; matching Host/Client builds are required. Manual modes and Linux
  Client Match Client remain 1x; Linux Host/EDID are unchanged. Mixed-scale
  dual displays fail explicitly. Mac Match Client preserves its measured
  fullscreen mode and uses backing-pixel presentation tiles.
  See `docs/development/plans/macos-retina-match-client.plan`.

- Signed Host 1.0.113 passed hosted run 35067335971 at
  `527cd5236e832396b6ed410fde4d9f00b345cefa`. Gates include 29 synthetic
  display/recovery cases, authenticated TLS schema-3 preparation/negative cases,
  real-QUIC no-media setup/teardown, 128 permission-denied setup cleanup cycles,
  129 non-waking activity checks, 216 native-input checks across eight scenarios,
  existing audio/installer tests and signing/notarization. Collected under
  `artifacts/packages/candidates/1.0.113-macos-auth-recovery/macos/`.
  PKG size 6,611,113; SHA256
  `2d40969bb830ae761f2f5581ed3db0f97404a2b3b440f7bf1ec55f465ed7f496`.
  Operator-installed Host/Client 1.0.113 are now observed in supplied logs;
  the subsequent Client 1.0.114 fullscreen correction is operator-accepted.

- Client 1.0.113 source is `ec17fc4`, Client gitlink
  `eb2d5ac1cc00630bd448b16976a15f93443ee15e`.
  Signed Mac run 35067619279 and Ubuntu run 35067622416 passed. The Mac job
  passed all 18 topology/request tests plus dependency/version/signing/notary
  gates; Ubuntu passed dependency, version, private-FFmpeg and autostart gates.
  Both packages are collected under the same version/platform catalog.
  DMG SHA256 `a260b5d42ae87dc8d70a72dec786b461e0381c2a3d2ea09e5721d96bf7ecd4aa`;
  DEB SHA256 `40ac84f2077f12573345283c8d27e42283f32226e29261c7e124a68f4f27b50a`.
  Earlier Client runs 35067338936/35067341704 were deliberately cancelled before
  producing packages to include the fullscreen/presentation correction.
  Host source is unchanged between those two root revisions. Do not rebuild
  or relabel the already-collected Host just to equalize provenance hashes.
  Local CI policy checks (14), bundle permission tests (seven pass/one Mac-only
  skip), Python syntax and shell/diff checks passed. An unsupported local Qt5
  attempt did not compile; no Qt5 compatibility was added. Required Qt6.10.2
  runner tests, not that attempt, are the Client compile gate.

- Secure-unlock fix is included: nine native lock-screen password rejections
  logged `The user did not become active for authentication. Fail the auth`
  after a five-second wait. Separate account verification succeeded; changing
  Shift/Caps did not help. A temporary `caffeinate -u -t 180` changed
  UserIsActive from 0 to 1 and the operator unlocked normally, with native
  `checkAuth result: 1`. The temporary assertion was explicitly stopped.
  Root `8a60ee3` (1.0.112, signed run 35066026592 passed) now reports only
  authorized real input as local console activity, at most once per second,
  with a ten-second OS timeout and immediate teardown release. No permanent
  power setting, TCC change, password logging or synthetic repeat/cleanup wake.
  The permanent implementation is not yet live-qualified.

- Earlier fixes on this branch: abandoned setup-token replacement/cleanup,
  bounded verifier diagnostics and successful-auth cooldown reset; authenticated
  bootstrap wake and bounded topology-settle wait; dynamic exact Mac display
  dimensions. See the auth/media/display recovery plans and Git history.
  Before the operator's upgrade, Host 1.0.111 real authenticated display preparation
  passed 3024x1964, 3456x2234, 2880x1864 and 5120x2160, then restored 1920x1080.
  These are geometry checks, not full streamed acceptance. Client retry
  lifecycle changes are now in the separate 1.0.116 candidate above.

- Supplied Retina screenshot/logs confirm Match Client negotiates and receives
  3420x2214, but a notched laptop's settled fullscreen drawable is 3420x2146
  (logical 1710x1073 instead of 1710x1107). This explains the top strip and
  aspect-preserving side borders; do not change Host Retina negotiation or
  stretch the stream to conceal the mismatch. The accepted correction keeps
  toolbar controls reachable around the camera housing. Candidate 1.0.114 implements SDL
  borderless desktop fullscreen without modesetting/Spaces and dynamically
  places the toolbar beside the camera housing. Hosted build passed and the
  operator accepted the correction. Mac fullscreen now uses the current desktop rather than a
  separate AppKit Space or an exclusive mode; test minimize and teardown too.
  Raw screenshots/logs remain outside Git.

- Next: operator qualification of the separate reconnect candidate. Broad acceptance
  of 1.0.114 is not a claim that every sleep,
  ownership, manual-mode and secure-unlock scenario was tested. Private deployment
  details and captures remain outside Git.

- Exact-input Mac Client dependency/Qt caching is committed as `8730581`;
  22 local CI tests pass. Hosted cold run 35070457888 passed and saved its
  dependency cache; signed Client 1.0.114 run 35071410245 restored the exact same
  key across the application change and independently verified its patch/receipt.
  Dependency bootstrap fell from 6m32s to 19s, plus 29s cache restore. The cold
  run was unsigned and the warm run signed, so their total job durations are
  not like-for-like benchmarks. Application/Rust compilation and all signing/
  notary gates still run fresh. Never cache application
  builds or signing material; `--clean-bootstrap` bypasses restore/save. This
  CI-only follow-up does not change the application version.

## Release evidence

Latest published release is **v1.0.124**, all four products, recorded above.
The merged dependency-cache work extends hosted caches without runtime changes;
qualification runs are separate from the published package source.

Historical Host-only release: [v1.0.106](https://github.com/instinctual/plank/releases/tag/v1.0.106),
mainline source `4b634071d0aa96c5568e90068f5f42b7cd953365`, signed run
35035036281. Catalog `releases/1.0.106/macos/plank-host_1.0.106_arm64.pkg`;
SHA256 `bdb59fb5ddf2df0afb4704920684b83d81c9b8975602e3d643bed5dd1c8d3e49`.
GitHub asset hashes match the local catalog. The other three products retain
1.0.105 below. Feature candidates in Current state do not replace published main.

All four exact-source runs passed:

| Product | GitHub run |
| --- | --- |
| Linux Host RPM | [35018358540](https://github.com/instinctual/plank/actions/runs/35018358540) |
| Linux Client DEB | [35018361548](https://github.com/instinctual/plank/actions/runs/35018361548) |
| Signed macOS Host PKG | [35018364501](https://github.com/instinctual/plank/actions/runs/35018364501) |
| Signed macOS Client DMG | [35018367944](https://github.com/instinctual/plank/actions/runs/35018367944) |

Verified SHA-256 values:

- Host RPM: `7aa4a71077ba22b836738ec53152c966af76555375da1514cc811065f3efb1be`
- Client DEB: `eb4c918e0c5c52fc3d5b0ef0bc16d340a89393971b71c8384f5491be0ec44985`
- Host PKG: `6e99f7509e31a17a097ee56c9f295f267bea5cd5a00dabf09582433646b94f92`
- Client DMG: `e88a62aee26d553d836ed7dbe6266441bf8037fa1623a27c307d4e602ea6fa54`

The collector verified transfers and retained source/gitlinks and sizes.
Local checksum verification passed; GitHub asset digests matched all four
packages, manifest and release checksum file. Published checksums use flat
asset filenames; local catalog checksums use platform subdirectories.
Temporary download/upload staging was removed after verification.

Both Mac packages passed Developer ID signing, notarization, stapling,
Gatekeeper and temporary-keychain cleanup. The Mac Host passed ten synthetic
recovery tests, four real TLS recovery scenarios, eight permission tests and
29 installer checks. Linux Client exact-decoder, private-FFmpeg, dependency,
version, reconnect and no-autostart gates passed. Host RPM manifest and
log-directory gates passed. Linux Host retains BUILD_TESTS=OFF and complete
CUDA architecture coverage. Local CI/version, package-collection, build-path
and bootstrap-input tests passed. These are not hardware acceptance results.

## Accepted fixes

Authenticated macOS topology requests can recover an inactive PLANK-owned
virtual display, with bounded authority/ownership checks and retained real
geometry. No physical mode changes, duplicate displays, TCC mutation or active
stream recovery. See `docs/development/plans/macos-display-recovery.plan`.

Host 1.0.103 had owner-only app directories/resources: ordinary users could see
a prohibited icon or "damaged or incomplete" launch error despite notarization.
Assembly now uses public distribution permissions, independently checked in the
app, staging and final PKG BOM/extraction. Never broaden private keys/state to
repair app access.

The operator accepted candidate 1.0.104-macos-display-recovery; merge commit:
`13e0c3248d223fd63d84919517df092d3e6d41ef`. Candidate source:
`ca36e48123d58cc84104f6fab5df59c35d14f05e`, signed run `35011167754`.
The Host-only mainline 1.0.104 used
`9284c204b6974e322e480442a0b0b91767420d2a`, run `35013030130`.
Those packages remain separately cataloged; 1.0.105 supersedes them.
Broad acceptance does not imply exhaustive sleep/ownership-transition tests.

Linux Host, shared Client and transport dependency revisions are unchanged
from 1.0.103. The corresponding 1.0.105 packages are rebuilds, not renamed files.

## Build and signing policy

Use GitHub-hosted workers for the requested releases, not a local Mac fallback.
All four clean hosted build paths and both signed Mac package paths are
qualified. Local builders have not been retired; hardware test roles remain
separate. Read `docs/development/build/github-builds.md` and the release build
runbook before the next build.

Signing is an explicitly dispatched direct job in `build.yml`, selected with
`signed=true`; ordinary push/PR builds never receive signing credentials.
At the operator's request, `macos-signing` has no reviewers or wait timer.
Custom branch restrictions are `main`, `macos-display-recovery` and the explicit
`macos-media-recovery`, `macos-auth-recovery` and `reconnect-lifecycle` candidates, not a
wildcard. Certificate exports, passwords and notarization credentials remain
environment secrets. Temporary runner keychains are removed on success/failure.

Do not restore the initial reusable-workflow wrapper: it received empty
environment secret values; the direct protected job is qualified. Missing
secrets fail before bootstrap. No per-run human approval is needed.
Exact-input Mac Client dependency caching is qualified as described above;
clean-bootstrap builds remain available to bypass it.

## Maintained inputs (unchanged from 1.0.105 through 1.0.106)

| Maintained input | Package source commit |
| --- | --- |
| Linux Host | `9329784ac41f50cbec0c9d76badfd22227ec5e5f` |
| Shared Client | `c032da3ae0d7e816a7a6f9bb9a51dd489d4d369c` |
| Transport | `912ece5c64787997f978673ca60d313898a3548c` |
| Host common-C | `775943b5ac5e5100a3c2b1b89d9e21151dea4f29` |
| Client common-C | `b9650552f98d97f6e30c9f007115c6246f0809e5` |
| Client mDNS engine | `b7a5a9f225d5e14b39f9fd1f905c4f505cf2ee99` |
| Host build dependencies | `caf0495d5e6baff94f349853d4a59e3779a451a0` |
| Host virtual HID | `93d57db99a5bf4b1a9fbbc7ad1371671725b7e97` |

The local checkout need not initialize every recursive dependency for notes;
builders initialize exact product inputs. Uninitialized local submodules do
not imply missing release dependencies.

## Remaining gates and publication boundaries

Mainline macOS Host 1.0.106 is published, collected and checksum-verified.
Its completed `macos-media-recovery` branch was deleted. The subsequently
accepted authentication, reconnect, fullscreen and dependency-cache work is
merged, and its completed feature branches are deleted. Unrelated local
RK3576 research remains separate.
Volume/mute is operator-validated. Longer app/alert audio, device changes,
sleep/reconnect/topology and login/logout remain follow-up coverage, not
blockers invented beyond the operator's merge approval. Inspect the new audio
reason/overrun/restart logs if it fails.
The initial failure cause is not proven; overflow no longer permanently
disables audio. An offline display that never returns still fails boundedly
rather than forcing settings into WindowServer. Do not interrupt a production
session to install. Acceptance
criteria still apply, including final macOS release revalidation and live
recovery/ownership transitions.

Treat tracked files/messages as public. See `docs/security/private-information.md`
and `docs/security/publication-review.md`. Source audits were bounded, not
proof against unknown/encoded secrets; credential rotation remains the operator's
responsibility. Do not reimport private historical development commits or publish
old 1.0.100/1.0.101 preparation packages: newer build-path fixes do not repair
their metadata retroactively. Never patch signed bytes or relabel packages.

ENet/nanors and inherited transports remain absent from current builds.
Host common-C is header-only; Client common-C is a separate maintained branch.
Preserve attribution without restoring retired code. Private infrastructure,
PLANK2 and historical backups remain independent of the public Host/Client
repository and release. Historical validation detail remains in Git history,
focused documentation and the earlier artifact manifests.
