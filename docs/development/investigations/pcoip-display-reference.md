# PCoIP dynamic display reference

Read-only inspection, 2026-09-04: HP Anyware/PCoIP Graphics Agent
26.05.3-1.el9, NVIDIA RTX A4500, NVIDIA driver 580.159.04. The user resized
their connected client window; no agent configuration, service, or mode was
changed by the inspection. No tracing or process attachment was used.

## Observed mechanism

The session launcher starts a separate NVIDIA Xorg server on display `:100`
using a generated `/tmp/xorg.pcoip.*.conf`, not the normal physical-desktop
`/etc/X11/xorg.conf`. Its Screen has `DefaultDepth 24`. Its Device contains:

```text
UseDisplayDevice = Connector-0,Connector-1,Connector-2,Connector-3
ConnectedMonitor = Connector-0,Connector-1,Connector-2,Connector-3
ModeValidation = AllowNonEdidModes, NoXServerModes, NoVesaModes, NoEdidMaxPClkCheck
UseEdidFreqs = FALSE
UseHotplugEvents = FALSE
CustomEDID = CRT:/usr/share/pcoip-agent/1024x768.bin; DFP:/usr/share/pcoip-agent/1024x768.bin
```

The above is a readable inventory, not a ready-to-install Xorg configuration.
The Monitor sections specify broad frequency ranges and no fixed mode list.
NVIDIA maps the connector aliases to DFP-0/2/4/6 on this GPU. These names are
not a portable connector mapping for PLANK.

PCoIP **does use a fixed EDID**, but the file is only 128 bytes and advertises
a 1024x768 startup mode, rather than enumerating every future desktop size.
Xorg initially configured four 1024x768 outputs as a 4096x768 canvas. During
the inspected single-monitor session, only DP-0 was active; the other three
virtual DisplayPort outputs remained connected but inactive.

The actual session uses additional dynamically named RandR modes. Both logs
and server-side queries confirmed the user's resize:

| State | Client topology request | Applied Host mode |
| --- | --- | --- |
| Initial | 1366x776 | 1360x776 |
| Intermediate | Not captured here | 1392x792 |
| After resize | 1702x941 | 1696x936 |

The two captured request/result pairs are consistent with rounding dimensions
down to multiples of eight. This is an observation, not a proven universal
PCoIP constraint or a policy to copy into PLANK.

The post-resize NVIDIA MetaMode reports `source=RandR`, mode name
`1696x936_30396wkhlx_541_c`, matching `ViewPortIn=1696x936` and
`ViewPortOut=1696x936+0+0`. Thus this is a real Host desktop mode change, not
merely client-side scaling. The Xorg PID/start time stayed unchanged.
The DP-0 EDID hex contents before/after were identical. SHA-256 of its
concatenated lowercase hex representation (no newline):
`adb151d5d1a62850bd85b617dfe667c03fb0ff9fd0ac8e34e448a53bff3d46a1`.
The packaged raw EDID file SHA-256 is
`4171e75897bf7f2c4977dbd9e34becac278ebb4d00204d937a3ebbf7a9659bd2`.

These observations establish runtime RandR mode application outside the EDID
list. They do not establish the proprietary application's precise mode-
creation API sequence or timing-generation algorithm. The active custom mode
reported about 59.87 Hz despite the topology log requesting 60 Hz; do not treat
that as proof of PLANK's exact 60.000 Hz requirement.

## Implication for PLANK

A small startup EDID plus validated runtime modes is a plausible alternative
to storing every qualified resolution in EDID. NVIDIA explicitly documents
`AllowNonEdidModes` as disabling the relevant rejection of non-EDID modes;
other mode/hardware constraints still apply. See the
[matching driver documentation](https://download.nvidia.com/XFree86/Linux-x86_64/580.159.04/README/xconfigoptions.html).

This remains a separate display experiment, not a change bundled into Host
privilege separation. The current PLANK contract deliberately uses qualified
EDID modes (`docs/development/plans/headless-display-plan.md`), and this inspection does not
supersede it. Before changing that contract, qualify:

- depth-30 rendering and both capture sources, preserving exact RGB identity;
- exact requested geometry and refresh, codec limits and aggregate canvas size;
- single/dual and unequal-size outputs, including real GNOME monitor topology;
- attachment to the existing physical desktop, restoring physical monitor modes
  on disconnect without restarting a user's Xorg or launching a second desktop;
- no unintended synthetic timings applied to real physical panels; and
- reconnect, takeover, Wacom margins/cursor/input transforms and failure cleanup.

Do not copy PCoIP's depth-24 setting, Xorg TCP/access-control flags, or global
mode-validation overrides into PLANK. Its independent-session lifecycle is
different from PLANK's shared physical/remote workstation workflow.
