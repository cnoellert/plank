// SPDX-License-Identifier: GPL-3.0-or-later
// Link-time synthetic CG/IOKit/virtual-display substitutes; no real display,
// input, power assertion, account or WindowServer access.
#ifdef NDEBUG
#undef NDEBUG
#endif
#import "desktop-display.h"
#import <IOKit/pwr_mgt/IOPMLib.h>
#import <objc/runtime.h>
#include <assert.h>
#include <unistd.h>

static unsigned creations, applications, selections, wakes, releases;
static BOOL online = YES, active = YES, authorized = YES, refuseMode, revokeOnWake;
static unsigned pixelWidth = 3840, pixelHeight = 2160;

@interface FakeDescriptor : NSObject
@property(copy) NSString *name;
@property unsigned maxPixelsWide, maxPixelsHigh, vendorID, productID, serialNum;
@property CGSize sizeInMillimeters;
@property(strong) dispatch_queue_t queue;
@end
@implementation FakeDescriptor
@end
@interface FakeMode : NSObject
@property unsigned width, height;
- (instancetype)initWithWidth:(unsigned)width height:(unsigned)height refreshRate:(double)rate;
@end
@implementation FakeMode
- (instancetype)initWithWidth:(unsigned)width height:(unsigned)height refreshRate:(double)rate {
    self = [super init]; if (self) { assert(rate == 60); _width = width; _height = height; } return self;
}
@end
@interface FakeSettings : NSObject
@property unsigned hiDPI;
@property(strong) NSArray *modes;
@end
@implementation FakeSettings
@end
@interface FakeDisplay : NSObject
- (instancetype)initWithDescriptor:(id)descriptor;
- (BOOL)applySettings:(id)settings;
@property(readonly) unsigned displayID;
@end
@implementation FakeDisplay
- (instancetype)initWithDescriptor:(id)descriptor {
    self = [super init]; if (self) { assert(descriptor); creations++; } return self;
}
- (BOOL)applySettings:(id)settings { assert(settings); applications++; online = YES; return YES; }
- (unsigned)displayID { return 42; }
@end

// The fixture build renames NSClassFromString only in desktop-display.m.
Class PLANKTestClassFromString(NSString *name) {
    if ([name isEqual:@"CGVirtualDisplayDescriptor"]) return FakeDescriptor.class;
    if ([name isEqual:@"CGVirtualDisplayMode"]) return FakeMode.class;
    if ([name isEqual:@"CGVirtualDisplaySettings"]) return FakeSettings.class;
    if ([name isEqual:@"CGVirtualDisplay"]) return FakeDisplay.class;
    assert(!"unexpected class lookup"); return Nil;
}
boolean_t CGDisplayIsActive(CGDirectDisplayID display) { assert(display == 42); return active; }
boolean_t CGDisplayIsOnline(CGDirectDisplayID display) { assert(display == 42); return online; }
boolean_t CGDisplayIsInMirrorSet(CGDirectDisplayID display) { assert(display == 42); return NO; }
size_t CGDisplayPixelsWide(CGDirectDisplayID display) { assert(display == 42); return pixelWidth; }
size_t CGDisplayPixelsHigh(CGDirectDisplayID display) { assert(display == 42); return pixelHeight; }
CGRect CGDisplayBounds(CGDirectDisplayID display) { assert(display == 42); return CGRectMake(0, 0, pixelWidth, pixelHeight); }
CFArrayRef CGDisplayCopyAllDisplayModes(CGDirectDisplayID display, CFDictionaryRef options) {
    assert(display == 42 && !options);
    return CFBridgingRetain(@[[[FakeMode alloc] initWithWidth:3840 height:2160 refreshRate:60],
                             [[FakeMode alloc] initWithWidth:5120 height:2160 refreshRate:60]]);
}
size_t CGDisplayModeGetPixelWidth(CGDisplayModeRef mode) { return [(__bridge FakeMode *)mode width]; }
size_t CGDisplayModeGetPixelHeight(CGDisplayModeRef mode) { return [(__bridge FakeMode *)mode height]; }
size_t CGDisplayModeGetWidth(CGDisplayModeRef mode) { return CGDisplayModeGetPixelWidth(mode); }
size_t CGDisplayModeGetHeight(CGDisplayModeRef mode) { return CGDisplayModeGetPixelHeight(mode); }
double CGDisplayModeGetRefreshRate(CGDisplayModeRef mode) { assert(mode); return 60; }
CGError CGDisplaySetDisplayMode(CGDirectDisplayID display, CGDisplayModeRef mode, CFDictionaryRef options) {
    assert(display == 42 && !options); selections++;
    if (refuseMode) return kCGErrorFailure;
    pixelWidth = (unsigned)CGDisplayModeGetPixelWidth(mode);
    pixelHeight = (unsigned)CGDisplayModeGetPixelHeight(mode);
    active = YES; return kCGErrorSuccess;
}
IOReturn IOPMAssertionDeclareUserActivity(CFStringRef name, IOPMUserActiveType type, IOPMAssertionID *result) {
    assert(name && type == kIOPMUserActiveRemote && *result == kIOPMNullAssertionID);
    wakes++; *result = 19;
    if (revokeOnWake) authorized = NO;
    return kIOReturnSuccess;
}
IOReturn IOPMAssertionRelease(IOPMAssertionID value) { assert(value == 19); releases++; return kIOReturnSuccess; }

static void step(PLANKMacDesktopDisplay *display, unsigned index) {
    BOOL (^valid)(void) = ^BOOL { return authorized; };
    void (^next)(void) = ^{ dispatch_async(dispatch_get_main_queue(), ^{ step(display, index + 1); }); };
    switch (index) {
    case 0: {
        [display recoverWithValidity:valid completion:^(BOOL ok) { assert(!ok && !creations && !wakes); next(); }]; break;
    }
    case 1: {
        [display prepareWidth:3840 height:2160 valid:valid completion:^(BOOL ok) {
            assert(ok && creations == 1 && display.displayID == 42); next();
        }]; break;
    }
    case 2: {
        [display recoverWithValidity:valid completion:^(BOOL ok) { assert(ok && !wakes && !selections); next(); }]; break;
    }
    case 3: {
        active = NO;
        [display recoverWithValidity:valid completion:^(BOOL ok) {
            assert(ok && wakes == 1 && releases == 1 && applications == 1 && pixelWidth == 3840); next();
        }]; break;
    }
    case 4: {
        [display prepareWidth:5120 height:2160 valid:valid completion:^(BOOL ok) { assert(ok); next(); }]; break;
    }
    case 5: {
        active = online = NO; pixelWidth = 3840;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100*NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ online = YES; });
        [display recoverWithValidity:valid completion:^(BOOL ok) {
            assert(ok && pixelWidth == 5120 && creations == 1 && applications == 1 && wakes == 2 && releases == 2); next();
        }]; break;
    }
    case 6: {
        active = NO; authorized = NO;
        [display recoverWithValidity:valid completion:^(BOOL ok) { assert(!ok && wakes == 2); next(); }]; break;
    }
    case 7: {
        authorized = YES; revokeOnWake = YES;
        [display recoverWithValidity:valid completion:^(BOOL ok) {
            assert(!ok && !active && wakes == 3 && releases == 3 && applications == 1); next();
        }]; break;
    }
    case 8: {
        authorized = YES; revokeOnWake = NO; refuseMode = YES;
        NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime + .15;
        [display recoverWithValidity:^BOOL { return NSProcessInfo.processInfo.systemUptime < deadline; }
            completion:^(BOOL ok) { assert(!ok && !active && wakes == 4 && releases == 4); next(); }];
        // Another request cannot race an in-progress recovery.
        [display recoverWithValidity:valid completion:^(BOOL ok) { assert(!ok && wakes == 4); }]; break;
    }
    case 9: {
        refuseMode = NO;
        [display recoverWithValidity:valid completion:^(BOOL ok) {
            assert(ok && creations == 1 && pixelWidth == 5120 && wakes == releases);
            next();
        }]; break;
    }
    case 10: {
        active = online = NO;
        NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime + .15;
        unsigned priorSelections = selections;
        [display recoverWithValidity:^BOOL { return NSProcessInfo.processInfo.systemUptime < deadline; }
            completion:^(BOOL ok) {
                assert(!ok && applications == 1 && creations == 1 && selections == priorSelections);
                assert(wakes == releases);
                puts("macos_display_recovery=pass checks=11 synthetic_only=1"); exit(0);
            }]; break;
    }
    default: abort();
    }
}
int main(void) {
    alarm(10);
    @autoreleasepool {
        PLANKMacDesktopDisplay *display = [[PLANKMacDesktopDisplay alloc] initForSignIn];
        dispatch_async(dispatch_get_main_queue(), ^{ step(display, 0); });
        [[NSRunLoop mainRunLoop] run];
    }
    return 1;
}
