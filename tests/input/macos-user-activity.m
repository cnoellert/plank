// SPDX-License-Identifier: GPL-3.0-or-later
// Test-link IOKit replacements: no real assertion, input posting or wake.
#import "quartz-input.h"
#import <IOKit/pwr_mgt/IOPMLib.h>

static unsigned checks, declarations, properties, releases;
static unsigned failure; // 1=declare, 2=timeout action, 3=timeout duration
static BOOL enabled;
static IOPMAssertionID current;
#define CHECK(x) do { if (!(x)) { fprintf(stderr, "failed line %d: %s\n", __LINE__, #x); exit(1); } ++checks; } while (0)

IOReturn IOPMAssertionDeclareUserActivity(CFStringRef name, IOPMUserActiveType type, IOPMAssertionID *assertion) {
    CHECK(CFEqual(name, CFSTR("PLANK remote console input")));
    CHECK(type == kIOPMUserActiveLocal);
    CHECK(*assertion == current);
    ++declarations;
    if (failure == 1) return kIOReturnError;
    if (!current) current = 42;
    *assertion = current; enabled = YES;
    return kIOReturnSuccess;
}
IOReturn IOPMAssertionSetProperty(IOPMAssertionID assertion, CFStringRef key, CFTypeRef value) {
    CHECK(assertion == current && current != kIOPMNullAssertionID);
    ++properties;
    if (CFEqual(key, kIOPMAssertionTimeoutActionKey)) {
        CHECK(CFEqual(value, kIOPMAssertionTimeoutActionTurnOff));
        return failure == 2 ? kIOReturnError : kIOReturnSuccess;
    }
    CHECK(CFEqual(key, kIOPMAssertionTimeoutKey));
    int duration = 0;
    CHECK(CFGetTypeID(value) == CFNumberGetTypeID());
    CHECK(CFNumberGetValue(value, kCFNumberIntType, &duration) && duration == 10);
    return failure == 3 ? kIOReturnError : kIOReturnSuccess;
}
IOReturn IOPMAssertionRelease(IOPMAssertionID assertion) {
    CHECK(assertion == current && current != kIOPMNullAssertionID);
    ++releases; current = kIOPMNullAssertionID; enabled = NO;
    return kIOReturnSuccess;
}
int main(void) {
    @autoreleasepool {
        PLANKMacUserActivity *activity = [PLANKMacUserActivity new];
        CHECK(declarations == 0); // creation, discovery and idle do not wake
        [activity noteAtTime:0];
        CHECK(declarations == 1 && properties == 2 && enabled);
        for (uint64_t now = 1; now < NSEC_PER_SEC; now += 1000000) [activity noteAtTime:now];
        CHECK(declarations == 1); // including initial timestamp zero
        [activity noteAtTime:NSEC_PER_SEC];
        CHECK(declarations == 2 && properties == 4 && releases == 0);
        [activity noteAtTime:0]; CHECK(declarations == 2); // backwards time
        enabled = NO; // simulate OS timeout; ID is retained, not leaked/released twice
        [activity noteAtTime:20 * NSEC_PER_SEC];
        CHECK(declarations == 3 && enabled);
        [activity stop];
        CHECK(releases == 1 && !enabled && current == 0);
        [activity stop]; [activity noteAtTime:30 * NSEC_PER_SEC];
        activity = nil;
        CHECK(releases == 1 && declarations == 3); // stopped is terminal

        for (unsigned stage = 1; stage <= 3; ++stage) {
            activity = [PLANKMacUserActivity new];
            [activity noteAtTime:0]; // establish an existing assertion
            failure = stage;
            unsigned oldReleases = releases, oldDeclarations = declarations;
            [activity noteAtTime:NSEC_PER_SEC];
            CHECK(releases == oldReleases + 1 && current == 0 && !enabled);
            for (unsigned i = 0; i < 100; ++i) [activity noteAtTime:NSEC_PER_SEC + i];
            CHECK(declarations == oldDeclarations + 1); // errors cannot flood powerd
            failure = 0;
            [activity noteAtTime:2 * NSEC_PER_SEC]; CHECK(enabled);
            activity = nil; CHECK(current == 0 && !enabled); // dealloc cleanup
        }
        // Failure before an assertion exists must not release a nonexistent ID.
        activity = [PLANKMacUserActivity new]; failure = 1;
        unsigned oldReleases = releases;
        [activity noteAtTime:0]; [activity stop]; activity = nil;
        CHECK(releases == oldReleases && !enabled);
        printf("macos_user_activity checks=%u real_wakes=0\n", checks);
    }
    return 0;
}
