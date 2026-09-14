// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <stdbool.h>
#include <sys/types.h>

// HAL object IDs are selected only after resolving their PID through the
// kernel. Never infer ownership from an application name or bundle identifier.
static inline bool PLANKTapProcessOwned(uid_t owner, pid_t caller, pid_t candidate,
                                        uid_t effective, uid_t real) {
    return owner != 0 && candidate > 0 && candidate != caller &&
        effective == owner && real == owner;
}
