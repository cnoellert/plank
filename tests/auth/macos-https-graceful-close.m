// SPDX-License-Identifier: GPL-3.0-or-later
// Negative-control fixture only; never linked into PLANK Host. Reintroduce
// graceful TCP close so the cross-UID gate must detect EADDRINUSE, rather than
// passing because a fixture never established the problematic connection.
#import <Network/Network.h>
#define nw_connection_force_cancel nw_connection_cancel
#import "../../apps/host/macos/control/https-auth-server.m"
