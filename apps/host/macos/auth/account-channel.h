// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#import "account-verifier.h"

// Dispatch before normal application startup. No listener or named socket.
#define PLANK_MAC_ACCOUNT_WORKER_ARGUMENT "--plank-private-account-worker"
int PLANKMacAccountWorkerMain(void);

// Run on a background authentication queue, never the GUI/event thread.
// One process-wide attempt at a time. Rejected/unavailable attempts impose a
// two-second minimum start interval; successful verification clears backoff.
// Re-execs this signed executable; its main must dispatch the argument above.
// Returns no desktop authority. Wipes password and zeroes output on failure.
PLANKMacAuthenticationResult PLANKMacVerifyAccountIsolated(
    NSString *name, NSMutableData *password, PLANKMacAccountIdentity *output);
