// SPDX-License-Identifier: GPL-3.0-or-later
#include "account-policy.h"
#ifdef NDEBUG
#undef NDEBUG
#endif
#include <assert.h>
#include <stdio.h>

int main(void) {
    PLANKMacAccountIdentity user = {501, {1}};
    PLANKMacGraphicalIdentity desktop = {true, 10, {501, {1}}, PLANKMacScopeDesktop};
    assert(plank_macos_account_may_attach(user, desktop, desktop));
    PLANKMacAccountIdentity wrong = user;
    wrong.uid++;
    assert(!plank_macos_account_may_attach(wrong, desktop, desktop));
    wrong = user; wrong.uuid[0]++;
    assert(!plank_macos_account_may_attach(wrong, desktop, desktop));
    wrong = user; wrong.uid = 0;
    assert(!plank_macos_account_may_attach(wrong, desktop, desktop));
    wrong = user; wrong.uid = UINT32_MAX;
    assert(!plank_macos_account_identity_valid(wrong));
    wrong = user; memset(wrong.uuid, 0, sizeof(wrong.uuid));
    assert(!plank_macos_account_identity_valid(wrong));
    PLANKMacGraphicalIdentity changed = desktop;
    changed.generation++;
    assert(!plank_macos_account_may_attach(user, desktop, changed));
    changed = desktop; changed.active = false;
    assert(!plank_macos_account_may_attach(user, desktop, changed));
    assert(!plank_macos_account_may_attach(user, changed, desktop));
    changed = desktop; changed.account.uuid[0]++;
    assert(!plank_macos_account_may_attach(user, desktop, changed));
    changed = desktop; changed.account.uid++;
    assert(!plank_macos_account_may_attach(user, desktop, changed));
    changed = desktop; changed.generation = 0;
    assert(!plank_macos_account_may_attach(user, changed, changed));
    PLANKMacGraphicalIdentity signIn = {true, 20, {0, {0}}, PLANKMacScopeSignIn};
    assert(plank_macos_graphical_identity_valid(signIn));
    assert(plank_macos_account_may_attach(user, signIn, signIn));
    wrong = user; wrong.uid++;
    assert(plank_macos_account_may_attach(wrong, signIn, signIn));
    wrong.uid = 0;
    assert(!plank_macos_account_may_attach(wrong, signIn, signIn));
    wrong = user; memset(wrong.uuid, 0, sizeof(wrong.uuid));
    assert(!plank_macos_account_may_attach(wrong, signIn, signIn));
    // Even accidental generation reuse cannot bridge sign-in and a desktop.
    changed = desktop; changed.generation = signIn.generation;
    assert(!plank_macos_account_may_attach(user, signIn, changed));
    assert(!plank_macos_account_may_attach(user, changed, signIn));
    changed = signIn; changed.generation++;
    assert(!plank_macos_account_may_attach(user, signIn, changed));
    changed = signIn; changed.account = user;
    assert(!plank_macos_graphical_identity_valid(changed));
    changed = signIn; changed.account.uuid[0] = 1;
    assert(!plank_macos_graphical_identity_valid(changed));
    changed = signIn; changed.active = false;
    assert(!plank_macos_graphical_identity_valid(changed));
    changed = signIn; changed.generation = 0;
    assert(!plank_macos_graphical_identity_valid(changed));
    changed = signIn; changed.phase = PLANKMacScopeUnavailable;
    assert(!plank_macos_graphical_identity_valid(changed));
    changed = signIn; changed.phase = (PLANKMacGraphicalPhase)99;
    assert(!plank_macos_graphical_identity_valid(changed));
    changed = desktop; changed.account.uid = 0;
    assert(!plank_macos_graphical_identity_valid(changed));
    puts("macos_account_policy=pass cases=27");
    return 0;
}
