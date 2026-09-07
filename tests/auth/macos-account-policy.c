// SPDX-License-Identifier: GPL-3.0-or-later
#include "account-policy.h"
#ifdef NDEBUG
#undef NDEBUG
#endif
#include <assert.h>
#include <stdio.h>

int main(void) {
    PLANKMacAccountIdentity user = {501, {1}};
    PLANKMacDesktopIdentity desktop = {true, 10, {501, {1}}};
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
    PLANKMacDesktopIdentity changed = desktop;
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
    puts("macos_account_policy=pass cases=12");
    return 0;
}
