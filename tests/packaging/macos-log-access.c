// SPDX-License-Identifier: GPL-3.0-or-later
// Isolated installer fixture only. Drop all root authority before checking
// effective log/key access; do not edit accounts, groups, ACLs or sudo policy.
#include <grp.h>
#include <pwd.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc != 5 || getuid() != 0 ||
        (strcmp(argv[4], "admin") && strcmp(argv[4], "wheel"))) return 2;
    struct passwd *account = getpwnam("nobody");
    if (!account) return 2;
    uid_t uid = account->pw_uid;
    struct group *group = getgrnam(argv[4]);
    if (!group || !uid) return 2;
    gid_t gid = group->gr_gid;
    int admin = !strcmp(argv[4], "admin");
    if (setgroups(1, &gid) || setgid(gid) || setuid(uid) || geteuid() != uid || getegid() != gid) return 2;

    // argv: product log directory, one log file, private key, selected group.
    // access() uses the real IDs, which setuid/setgid also dropped above.
    if ((access(argv[1], R_OK | X_OK) == 0) != admin ||
        (access(argv[2], R_OK) == 0) != admin ||
        access(argv[1], W_OK) == 0 || access(argv[2], W_OK) == 0 ||
        access(argv[3], R_OK) == 0) return 1;
    puts(admin ? "macos_log_access=admin-read-only" : "macos_log_access=non-admin-denied");
    return 0;
}
