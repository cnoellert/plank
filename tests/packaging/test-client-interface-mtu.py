#!/usr/bin/env python3
"""Source wiring gates complement the compiled planknetwork policy tests."""
import pathlib
import sys
import unittest

source = pathlib.Path(sys.argv.pop(1))
session = (source / "app/streaming/session.cpp").read_text()
computer = (source / "app/backend/nvcomputer.cpp").read_text()


class InterfaceMtu(unittest.TestCase):
    def test_route_lookup_is_not_skipped_for_manual_settings(self):
        selection = session.split("quint32 routeInterfaceMtu = 0;", 1)[1].split("    try {", 1)[0]
        self.assertLess(selection.index("getActiveAddressReachability("),
                        selection.index("quicUdpPayloadMtuForRoute("))
        self.assertIn("configuredMtu, routeReachability == NvComputer::RI_ZEROTIER,", selection)
        self.assertIn("routeInterfaceMtu, routeIsIpv6", selection)

    def test_rejection_precedes_launch(self):
        selection = session.split("quint32 routeInterfaceMtu = 0;", 1)[1].split("    try {", 1)[0]
        rejection = selection.split("if (quicUdpPayloadMtu == 0)", 1)[1]
        self.assertIn("emit displayLaunchError", rejection)
        self.assertIn("return false;", rejection)
        self.assertNotIn("startMacPreview(", selection)
        self.assertNotIn("startApp(", selection)

    def test_both_hosts_and_transport_receive_selected_ceiling(self):
        self.assertIn("startMacPreview(topology, pin, m_StreamConfig.bitrate, quicUdpPayloadMtu)", session)
        self.assertIn("config.max_udp_payload_size = quicUdpPayloadMtu;", session)
        self.assertIn("                          quicUdpPayloadMtu,", session)
        self.assertIn("                                 quicUdpPayloadMtu))", session)

    def test_interface_mtu_is_live_and_nonnegative(self):
        lookup = computer.split("NvComputer::ReachabilityType NvComputer::getActiveAddressReachability(", 1)[1]
        self.assertIn("QNetworkInterface::allInterfaces()", lookup)
        self.assertIn("addr.ip() == s.localAddress()", lookup)
        self.assertIn("*interfaceMtu = qMax(0, nic.maximumTransmissionUnit());", lookup)


unittest.main()
