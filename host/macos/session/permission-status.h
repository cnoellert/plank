// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <stdbool.h>

// A diagnostic, never an authorization token. Audio-tap consent and real
// capture/input delivery must be qualified separately in each graphical role.
static inline bool plank_macos_screen_input_ready(bool graphical, bool screen,
                                                  bool post_event, bool accessibility) {
    return graphical && screen && post_event && accessibility;
}
