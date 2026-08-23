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
