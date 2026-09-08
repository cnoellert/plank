// SPDX-License-Identifier: GPL-3.0-or-later
// Native scope only: no capture, input, network listener or permission request.
#import "graphical-authority.h"
#include <unistd.h>

static unsigned checks;
#define CHECK(x) do { if (!(x)) { fprintf(stderr, "scope check failed line %d\n", __LINE__); return 1; } ++checks; } while (0)
int main(int argc, const char **argv) {
    BOOL background = argc == 2 && !strcmp(argv[1], "--background");
    if (argc != 1 && !background) return 2;
    alarm(10);
    @autoreleasepool {
        CHECK([PLANKMacGraphicalAuthority new] == nil);
        CHECK([[PLANKMacGraphicalAuthority alloc] initWithPhase:PLANKMacScopeUnavailable] == nil);
        CHECK([[PLANKMacGraphicalAuthority alloc] initWithPhase:(PLANKMacGraphicalPhase)99] == nil);
        for (PLANKMacGraphicalPhase phase = PLANKMacScopeSignIn; phase <= PLANKMacScopeDesktop; ++phase) {
            PLANKMacGraphicalAuthority *authority = [[PLANKMacGraphicalAuthority alloc] initWithPhase:phase];
            CHECK(authority != nil);
            BOOL expected = !background && (phase == PLANKMacScopeSignIn ? getuid() == 0 : getuid() != 0);
            PLANKMacGraphicalIdentity before = [authority snapshot];
            CHECK(before.active == expected);
            CHECK(plank_macos_graphical_identity_valid(before) == expected);
            if (expected) {
                CHECK(before.phase == phase);
                CHECK(before.account.uid == getuid());
                CHECK(plank_macos_same_graphical_scope(before, [authority snapshot]));
            }
            [authority revoke];
            CHECK(![authority snapshot].active);
            CHECK(![authority snapshot].active);
        }
        printf("macos_graphical_authority=pass checks=%u background=%d phase=%s\n", checks, background,
            background ? "none" : getuid() == 0 ? "sign-in" : "desktop");
    }
    return 0;
}
