// SPDX-License-Identifier: GPL-3.0-or-later
// Read-only session diagnosis; no capture, input, display creation or TCC request.
#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Security/AuthSession.h>
#import <SystemConfiguration/SystemConfiguration.h>
#include <unistd.h>

int main(void) {
    @autoreleasepool {
        [NSApplication.sharedApplication setActivationPolicy:NSApplicationActivationPolicyProhibited];
        SecuritySessionId identity = noSecuritySession;
        SessionAttributeBits attributes = 0;
        OSStatus result = SessionGetInfo(callerSecuritySession, &identity, &attributes);
        uid_t console = (uid_t)-1;
        NSString *name = CFBridgingRelease(SCDynamicStoreCopyConsoleUser(NULL, &console, NULL));
        NSDictionary *graphical = CFBridgingRelease(CGSessionCopyCurrentDictionary());
        NSDictionary *system = CFBridgingRelease(SCDynamicStoreCopyValue(NULL, CFSTR("State:/Users/ConsoleUser")));
        NSLog(@"uid=%u euid=%u security-result=%d session=%u attributes=0x%x console-uid=%u console-name=%@ graphical=%@ system=%@",
              getuid(), geteuid(), (int)result, (unsigned)identity, (unsigned)attributes,
              console, name, graphical, system);
    }
    return 0;
}
