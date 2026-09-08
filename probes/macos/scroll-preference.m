// SPDX-License-Identifier: GPL-3.0-or-later
// Read-only, bounded preference qualification. Does not change preferences,
// inject input, require TCC, or inspect any unrelated preference values.
#import <Foundation/Foundation.h>
#include <unistd.h>

static void readSetting(CFStringRef application, CFStringRef key) {
    Boolean synced = CFPreferencesSynchronize(application, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPropertyListRef value = CFPreferencesCopyValue(key, application,
        kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    double number = 0;
    BOOL numeric = value && CFGetTypeID(value) == CFNumberGetTypeID() &&
        CFNumberGetValue((CFNumberRef)value, kCFNumberDoubleType, &number);
    printf(" domain=%s key=%s synced=%d present=%d numeric=%d value=%.6f",
        [(__bridge NSString *)application UTF8String], [(__bridge NSString *)key UTF8String],
        synced, value != NULL, numeric, number);
    if (value) CFRelease(value);
}

int main(void) {
    @autoreleasepool {
        setvbuf(stdout, NULL, _IONBF, 0);
        for (unsigned second = 0; second < 120; ++second) {
            printf("second=%u", second);
            readSetting(kCFPreferencesAnyApplication, CFSTR("com.apple.scrollwheel.scaling"));
            readSetting(CFSTR("com.apple.driver.AppleHIDMouse"), CFSTR("ScrollS"));
            printf("\n");
            sleep(1);
        }
    }
    return 0;
}
