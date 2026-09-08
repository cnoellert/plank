// SPDX-License-Identifier: GPL-3.0-or-later
// Dedicated development Mac only, launched in its real Aqua session.
#import "desktop-display.h"
#import "graphical-authority.h"
#include <unistd.h>

static void nextMode(PLANKMacDesktopDisplay *display, PLANKMacGraphicalAuthority *authority,
                     PLANKMacGraphicalIdentity initial, unsigned index) {
    const unsigned sizes[][2] = {{3840,2160}, {1920,1080}, {2560,1600}, {3840,2160}};
    if (index == 4) {
        printf("macos_desktop_modes=pass display=%u same_owner=1 changes=4\n", display.displayID);
        fflush(stdout); exit(0);
    }
    [display prepareWidth:sizes[index][0] height:sizes[index][1]
        valid:^BOOL { return plank_macos_same_graphical_scope(initial, [authority snapshot]); }
        completion:^(BOOL ready) {
            if (!ready) { fprintf(stderr, "macos_desktop_modes=fail stage=%u\n", index); exit(1); }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250*NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                nextMode(display, authority, initial, index + 1);
            });
        }];
}
int main(void) {
    @autoreleasepool {
        PLANKMacGraphicalAuthority *authority = [[PLANKMacGraphicalAuthority alloc] initWithPhase:PLANKMacScopeDesktop];
        PLANKMacGraphicalIdentity initial = [authority snapshot];
        if (!plank_macos_graphical_identity_valid(initial)) return 2;
        PLANKMacDesktopDisplay *display = [PLANKMacDesktopDisplay new];
        nextMode(display, authority, initial, 0);
        [[NSRunLoop mainRunLoop] run];
    }
    return 1;
}
