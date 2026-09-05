# Host privilege separation

## Scope and status

Work branch: `host-privilege-separation` (Host fork:
`plank/host-privilege-separation`). Baseline root: `9fe5917`; Host:
`b06b436986ced00902473f6502ea758978509586`.

The goal is a dedicated non-login media/network account without root identity
or Linux capabilities, retaining narrow privileged session, PAM, and input
boundaries. This is not a switch back to per-desktop-user machine identities.
Do not change the working capture, encoding, transport, cursor, or Wacom
algorithms as part of this effort. Do not deploy a partial identity conversion.

On 2026-09-04, read-only inspection of the shared hardware-test Host confirmed:

- Supervisor: UID/GID 0, effective/permitted/bounding capability mask `0x80004`
  (`DAC_READ_SEARCH`, `SYS_PTRACE`), no ambient/inheritable capabilities.
- Media worker: UID/GID 0, effective/permitted `0x4` (`DAC_READ_SEARCH`),
  bounding `0x80004`, no ambient/inheritable capabilities.
- Both inherit `NoNewPrivileges=1`.

That Host was subsequently identified as running PLANK2 `2.0.0-dev.11`, not
the current PLANK 1.x RPM. Treat the runtime observation as a reference, not
exact-package validation. The current PLANK 1.x source has the same explicit
worker capability reduction.

The worker does not have all capabilities, but its root identity and arbitrary
file-read capability remain meaningful exposure. No compromise was observed.

## Resource boundaries

| Resource | Current dependency | Intended boundary / qualification |
| --- | --- | --- |
| PAM | Worker opens root-only broker socket | Supervisor connects only the fixed broker endpoint and passes that connected descriptor; credentials flow directly to PAM, not through the supervisor. |
| Session/display | Root supervisor inspects logind and session processes, applies validated layouts | Retain inherited private channel, independently validate active seat/generation/owner; no arbitrary command or path requests. |
| X11 | Worker reads selected user's Xauthority | Supervisor stages only the validated session's credential; never relax home or runtime-directory permissions. |
| Native 10-bit SHM | Worker assigns SysV SHM ownership to X server's account | Qualify X11 FD-based SHM sharing before dropping UID; do not use world-accessible SHM or silently fall back to 8-bit capture. |
| NvFBC/CUDA/NVENC | Worker opens NVIDIA devices | Qualify exact GPU device access under service UID, both capture paths and every supported profile. No broad input-group membership. |
| Audio | Worker traverses protected user runtime directory and uses staged Pulse cookie | Qualify a session-scoped endpoint/descriptor arrangement; no global Pulse authorization, world-readable cookie, or audio proxy without measured necessity. |
| Keyboard/mouse/pen/Wacom | Worker/libvirtualhid owns kernel virtual-device handles and device lifecycle | Delegate only narrowly validated virtual-device operations, with detach/release on worker death. Do not grant access to arbitrary physical input devices. |
| TLS/state/config | Root-owned private files | Retain root-owned persistent identity/config; pass only required read-only identity material, move any necessary mutation behind bounded helper operations. |
| Logs | Root-only product directory | Preopen designated output handles; worker cannot create arbitrary root-owned files. Preserve fresh-install log-directory RPM gate. |

## Implementation sequence

### Reference inspection and design checkpoint

A read-only inspection of an active HP Anyware/PCoIP Graphics Agent
`26.05.3-1.el9` session on 2026-09-04 found:

| Process | Identity | Effective/permitted capabilities |
| --- | --- | --- |
| `pcoip-agent` | Dedicated `pcoip` account | `NET_BIND_SERVICE` |
| `pcoip-session-launcher` | Dedicated `pcoip` account | `CHOWN`, `KILL`, `SETGID`, `SETUID` |
| `pcoip-authentication-proxy` | Root | `DAC_READ_SEARCH`, `SETGID`, `SETUID`, `NET_BIND_SERVICE`, `IPC_LOCK`, `AUDIT_WRITE` |
| `pcoip-desktop-child` | Root | Authentication-proxy set plus `SYS_RESOURCE`, `AUDIT_CONTROL` |
| `pcoip-server` | Authenticated desktop user's real/effective/saved/filesystem UID | None |

The session server holds NVIDIA/render-node, uinput and UHID handles. UHID is
root-owned mode `0600`, with no extended ACL, despite that server being
unprivileged. This is consistent with opening before privilege drop or passing
descriptors from a privileged helper; a process snapshot does not establish
which mechanism they use. Do not claim we traced their implementation.

The main agent owns TCP listeners; the per-user server owns the UDP session
listener. `anyware-trust-agent` runs separately as `pcoip`, with `CAP_KILL`,
no-new-privileges and seccomp. The other observed PCoIP processes do not have
no-new-privileges or seccomp enabled and have broad bounding sets. This is an
architectural reference, not an endorsement of copying its complete security
policy. An unrelated Tangent udev rule makes uinput world-writable on that
machine; it must not be attributed to PCoIP or reproduced for PLANK.

**Decision before identity cutover:** consider running the PLANK media worker
as the selected active desktop/greeter user, while retaining stable machine
identity and privileged resource setup separately. That removes cross-user
Xauthority, Pulse and SysV-SHM ownership problems inherent in an unrelated
dedicated media UID. It also means a compromised worker has that user's normal
file authority; it is not equivalent to a tightly confined dedicated media
account. The earlier PLANK per-user identity defect concerned persistent
UUID/state ownership, not an inherent requirement for root media execution.
The user has requested continuing the original hardening task and deferring
dynamic PCoIP resizing; retain the dedicated-account target above unless
explicitly revised. The per-user option is reference material, not a blocker
or an approved architecture change. No PCoIP settings, services, devices or session were
modified, and no trace was attached.

1. Replace direct worker PAM socket access with private descriptor delegation.
   Keep broker filesystem permissions unchanged. Reject malformed/truncated
   messages, extra descriptors, wrong peers, timeouts, and unavailable broker.
   There is no direct-connect fallback. This stage still runs the worker as root;
   it removes one dependency, not the root security exposure itself.
2. Independently qualify native X11 FD-SHM, NVIDIA device access, audio and
   input resource lifetimes under an unprivileged UID on the hardware target.
   Probes must not alter running production service permissions or Xorg policy.
3. Implement the remaining resource boundaries and dedicated service account.
   Clear supplementary groups and all real/effective/saved IDs/capabilities,
   retain no-new-privileges, and fail startup if any drop fails. Recheck the
   parent-death signal after credential changes and close unintended inherited
   descriptors. No root fallback.
4. Update RPM ownership/account lifecycle, service restrictions, package gates,
   architecture documentation and repository policy together. Build a clean,
   branch-qualified Host candidate on linux-host-builder only.
5. Install on the hardware test Host and verify exact package hashes, runtime
   UIDs/capability sets and negative access tests before functional acceptance.

## Acceptance gates

Stage 1 source and clean Host package `1.0.26-host-privilege-separation` pass
the standalone descriptor protocol tests and package gates. A synthetic
root-to-`nobody` descriptor transfer also passed on the hardware target without
touching real PAM credentials or its running services. Live installation and
login testing await an available PLANK 1.x Host: do not overwrite the active
PLANK2 installation. This is not completion of the overall privilege drop.

- Real/effective/saved/filesystem media UID/GID are non-root; capabilities and
  supplementary groups match the minimal documented policy after actual exec.
- A worker cannot read unrelated user credentials, modify system files, reach
  the PAM listener directly, open arbitrary input devices, or spoof a root
  supervisor. Malformed helper requests cannot broaden authority.
- PAM/SSSD success/failure, root-login policy, different-user denial,
  same-account takeover, GDM-to-desktop transition and lock/unlock still work.
- Physical/headless, single/dual display and resolution changes retain exact
  restoration, with no automatic reboot as recovery.
- Both capture sources, exact RGB identity profiles, native 10-bit ramps,
  cursor shapes, audio synchronization, keyboard/buttons/wheel, normalized pen,
  raw-HID pressure/margins and mixed physical/remote Wacom models pass.
- Kill/crash/restart releases keys, pen contact, PAM conversations and devices;
  stale credentials/handles cannot survive a graphical-session generation.
- Fresh install, upgrade, removal and product-only logging pass. No installation
  on either builder. No production claim until the hardware gates pass.
