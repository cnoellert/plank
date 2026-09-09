// SPDX-License-Identifier: GPL-3.0-or-later
// Read-only HAL inventory plus three deliberate system alerts in the current
// desktop. No tap, capture, microphone, device/volume/permission changes.
#include <CoreAudio/CoreAudio.h>
#include <AudioToolbox/AudioToolbox.h>
#include <CoreFoundation/CoreFoundation.h>
#include <Security/Security.h>
#include "audio-tap-system-alerts.h"
#include <libproc.h>
#include <sys/stat.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

static OSStatus get(AudioObjectID object, AudioObjectPropertySelector key, UInt32 *size, void *out) {
    AudioObjectPropertyAddress address = {key, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    return AudioObjectGetPropertyData(object, &address, 0, NULL, size, out);
}
int main(int argc, const char **argv) {
    bool identityOnly = argc == 2 && !strcmp(argv[1], "--identity-only");
    if (argc != 1 && !identityOnly) return 2;
    struct stat console;
    if (!getuid() || getuid() != geteuid() || stat("/dev/console", &console) || console.st_uid != getuid()) return 2;
    setbuf(stdout, NULL);
    alarm(20);
    uint64_t origin = clock_gettime_nsec_np(CLOCK_MONOTONIC);
    printf("alert_inventory uid=%u capture=0 permission_requests=0 alerts=%u duration=%u\n", getuid(), identityOnly ? 0 : 3, identityOnly ? 0 : 12);
    struct { AudioObjectID object; pid_t pid; UInt32 running; } previous[1024] = {0};
    size_t priorCount = 0;
    unsigned alerts = 0;
    unsigned verifiedAlerts = 0;
    for (;;) {
        double elapsed = (clock_gettime_nsec_np(CLOCK_MONOTONIC) - origin) / 1e9;
        if (elapsed >= 12) break;
        if (stat("/dev/console", &console) || console.st_uid != getuid()) return 3;
        if (alerts < 3 && elapsed >= (alerts + 1) * 3) {
            ++alerts;
            printf("ALERT t=%.1f\n", elapsed);
            AudioServicesPlayAlertSound(kUserPreferredAlert);
        }
        AudioObjectID objects[1024]; UInt32 bytes = sizeof(objects);
        if (get(kAudioObjectSystemObject, kAudioHardwarePropertyProcessObjectList, &bytes, objects) || bytes % sizeof(*objects)) return 4;
        for (size_t i = 0; i < bytes / sizeof(*objects); i++) {
            pid_t pid = 0; UInt32 size = sizeof(pid), running = 0;
            if (get(objects[i], kAudioProcessPropertyPID, &size, &pid)) continue;
            size = sizeof(running);
            if (get(objects[i], kAudioProcessPropertyIsRunningOutput, &size, &running)) continue;
            size_t entry;
            for (entry = 0; entry < priorCount && previous[entry].object != objects[i]; entry++) {}
            if (entry == priorCount) { if (priorCount == 1024) return 5; priorCount++; }
            else if (previous[entry].pid == pid && previous[entry].running == running) continue;
            previous[entry].object = objects[i]; previous[entry].pid = pid; previous[entry].running = running;
            struct proc_bsdinfo info = {0};
            int known = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, sizeof(info)) == sizeof(info);
            char name[128] = {0}; proc_name(pid, name, sizeof(name));
            for (size_t c = 0; c < strlen(name); ++c) if (name[c] < 32 || name[c] > 126) name[c] = '?';
            printf("process t=%.1f object=%u pid=%d owner_known=%d uid=%u ruid=%u output=%u name=%s\n",
                elapsed, objects[i], pid, known, info.pbi_uid, info.pbi_ruid, running, name);
            if (!known) {
                bool verified = PLANKTapSystemAlertProcess(getuid(), pid);
                printf("identity pid=%d system_alert_verified=%d\n", pid, verified);
                verifiedAlerts += verified;
            }
        }
        if (identityOnly) {
            printf("system_alert_identity_matches=%u\n", verifiedAlerts);
            return verifiedAlerts == 1 ? 0 : 6;
        }
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, false);
    }
    puts("alert_inventory_complete=1");
    return 0;
}
