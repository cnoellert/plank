// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <Security/Security.h>
#include <stdbool.h>
#include <sys/stat.h>
#include <unistd.h>

// System alerts belong to the active physical desktop in PLANK's single-user
// Mac deployment. Never allow arbitrary privileged audio or trust a HAL bundle
// name/PID alone. Validate the running Apple-signed service, not an on-disk file.
static inline bool PLANKTapSystemAlertProcess(uid_t owner, pid_t pid) {
    struct stat console;
    if (!owner || owner != getuid() || geteuid() != owner || pid <= 0 || pid == getpid() ||
        stat("/dev/console", &console) || console.st_uid != owner) return false;
    SecRequirementRef requirement = NULL;
    SecCodeRef code = NULL;
    CFNumberRef number = CFNumberCreate(NULL, kCFNumberIntType, &pid);
    if (!number) return false;
    const void *keys[] = {kSecGuestAttributePid}, *values[] = {number};
    CFDictionaryRef attributes = CFDictionaryCreate(NULL, keys, values, 1,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    bool valid = attributes &&
        SecRequirementCreateWithString(CFSTR("identifier \"com.apple.systemsoundserverd\" and anchor apple"),
            kSecCSDefaultFlags, &requirement) == errSecSuccess &&
        SecCodeCopyGuestWithAttributes(NULL, attributes, kSecCSDefaultFlags, &code) == errSecSuccess &&
        SecCodeCheckValidity(code, kSecCSStrictValidate, requirement) == errSecSuccess;
    if (code) CFRelease(code);
    if (requirement) CFRelease(requirement);
    if (attributes) CFRelease(attributes);
    CFRelease(number);
    return valid;
}
