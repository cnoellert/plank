# ZeroTier Video MTU Qualification

The StationConnect host and production-workflow client both use 1500-byte
physical Ethernet MTUs. Their ZeroTier 1.16.2 interfaces advertise an inner
MTU of 2800, but ZeroTier limits each physical UDP payload to 1432 bytes and
fragments larger virtual packets internally.

The client previously failed to classify Linux interface `ztk4jiikvl` as a
VPN because Qt 6.10 reported its interface type as `Ethernet`. Moonlight then
selected its 1392-byte local default. With encrypted video, IPv4/UDP, and the
normal 38-byte ZeroTier frame envelope, each packet became 1474 bytes. A live
12-second native 5120x2160 capture observed 101,301 matching ZeroTier fragment
pairs of 1432 and 58 bytes. The second size is the 42-byte remainder plus
ZeroTier's 16-byte fragment header.

Release 0.14 recognizes Linux `ztXXXXXXXX` interface names and selects a
1328-byte Moonlight packet size. Its resulting sizes are:

- Sunshine negotiated packet size: 1296 bytes;
- encrypted Sunshine UDP payload: 1344 bytes;
- inner IPv4 packet: 1372 bytes;
- normal ZeroTier physical payload: 1410 bytes;
- extended-frame ZeroTier physical payload: 1423 bytes.

Both ZeroTier forms remain below the 1432-byte boundary. The mathematical
maximum for normal direct frames is 1344, but 1328 preserves extended-frame
compatibility for about a 1.2 percent payload-capacity cost. The client unit
test locks the interface classification and packet calculations to these
values. A post-install stream must confirm the log line
`Using StationConnect VPN packet size: 1328 bytes` and show no repeated
1432-plus-58 fragment pairs on the physical interface.

## Release Artifacts

The Ubuntu 26.04 development NUC built the client twice from clean Moonlight
commit `536eaba8` and the pinned private FFmpeg 9.0.1 runtime. Both builds were
byte-identical and passed the package manifest and runtime dependency gates.

```text
stationconnect-client_0.1.0-0.14_amd64.deb
SHA-256 630418c44b61661f23d7acf287a3a20c547f32e3739c16859882244df6bece78
```

The synchronized host RPM passed its package-binary and manifest gates. It
contains no functional host change and is not required for the packet-size
test; an installed 0.13 host honors the size negotiated by the 0.14 client.

## Native KyProto/QUIC qualification

The Datasmash transport no longer uses the Moonlight packet-size negotiation
described above. Live captures on 2026-08-30 established the corresponding
native QUIC contract. ZeroTier successfully reassembled larger inner packets,
which allowed Quinn's DPLPMTUD to report success at 1452 bytes even though the
underlay emitted fragments. Representative complete QUIC UDP payloads produced
these observed ZeroTier physical UDP payloads:

| QUIC UDP payload | Observed physical payload |
| ---: | ---: |
| 1200 | 1238 |
| 1328 | 1366 |
| 1344 | 1382 |
| 1352 | 1390 |
| 1400 | 1432 + 22-byte fragment |
| 1452 | 1432 + 74-byte fragment |

The 38-byte difference in the unfragmented samples is the normal ZeroTier
envelope. The extended-frame budget remains 51 bytes, so the native Client
uses a 1344-byte QUIC UDP ceiling only when the kernel-selected route matches
a ZeroTier interface. Including inner IPv4/UDP and the extended envelope gives
`1344 + 28 + 51 = 1423`, below the 1432-byte physical boundary. A conservative
38-byte QUIC DATAGRAM allowance and KyProto's 26-byte video FEC header leave a
1280-byte RaptorQ video symbol.

The Client supplies 1344 both as Quinn's MTU-discovery upper bound and as the
QUIC `max_udp_payload_size` transport parameter. This constrains both Client-
to-Host and Host-to-Client traffic. The old physical-path-MTU UI and GameStream
`packetSize` fields did not affect native KyProto and are removed. The
replacement manual override is the exact maximum QUIC UDP payload and therefore
feeds Quinn directly. Automatic remains the default; other route types retain
Quinn's normal discovery policy.
