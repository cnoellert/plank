// SPDX-License-Identifier: GPL-3.0-or-later
#include "permission-status.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    for (unsigned state = 0; state < 16; state++) {
        assert(plank_macos_screen_input_ready(state & 1, state & 2, state & 4, state & 8)
               == (state == 15));
    }
    puts("macOS permission readiness: 16 states passed");
}
