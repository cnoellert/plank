// SPDX-License-Identifier: GPL-3.0-or-later
#import "desktop-display.h"
#import <objc/runtime.h>
#include <math.h>
#include <stdatomic.h>
#include <string.h>

// Undocumented surface isolated here, with exact SDK-27 runtime signature
// checks. No older-OS paths and no permission or capture bypass.
@interface PLANKMacDisplayDescriptor : NSObject
@property(copy) NSString *name;
@property unsigned maxPixelsWide, maxPixelsHigh, vendorID, productID, serialNum;
@property CGSize sizeInMillimeters;
@property(strong) dispatch_queue_t queue;
@end
@interface PLANKMacDisplayMode : NSObject
- (instancetype)initWithWidth:(unsigned)width height:(unsigned)height refreshRate:(double)rate;
@end
@interface PLANKMacDisplaySettings : NSObject
@property unsigned hiDPI;
@property(strong) NSArray *modes;
@end
@interface PLANKMacVirtualDisplay : NSObject
- (instancetype)initWithDescriptor:(id)descriptor;
- (BOOL)applySettings:(id)settings;
@property(readonly) unsigned displayID;
@end

static const unsigned modes[][2] = {
    {1024,2160}, {1280,2160}, {1920,1080}, {1920,1200}, {2560,1440},
    {2560,1600}, {2560,2160}, {3440,1440}, {3840,1600}, {3840,2160},
    {4096,2160}, {5120,2160}
};
BOOL PLANKMacDesktopModeSupported(unsigned width, unsigned height) {
    for (size_t i = 0; i < sizeof(modes)/sizeof(modes[0]); ++i)
        if (modes[i][0] == width && modes[i][1] == height) return YES;
    return NO;
}
static BOOL signature(NSString *name, NSString *selector, const char *encoding) {
    Method method = class_getInstanceMethod(NSClassFromString(name), NSSelectorFromString(selector));
    return method && !strcmp(method_getTypeEncoding(method), encoding);
}
static BOOL supportedAPI(void) {
    for (NSString *s in @[@"setName:", @"setQueue:"])
        if (!signature(@"CGVirtualDisplayDescriptor", s, "v24@0:8@16")) return NO;
    for (NSString *s in @[@"setMaxPixelsWide:", @"setMaxPixelsHigh:", @"setVendorID:", @"setProductID:", @"setSerialNum:"])
        if (!signature(@"CGVirtualDisplayDescriptor", s, "v20@0:8I16")) return NO;
    return signature(@"CGVirtualDisplayDescriptor", @"setSizeInMillimeters:", "v32@0:8{CGSize=dd}16") &&
        signature(@"CGVirtualDisplayMode", @"initWithWidth:height:refreshRate:", "@32@0:8I16I20d24") &&
        signature(@"CGVirtualDisplaySettings", @"setHiDPI:", "v20@0:8I16") &&
        signature(@"CGVirtualDisplaySettings", @"setModes:", "v24@0:8@16") &&
        signature(@"CGVirtualDisplay", @"initWithDescriptor:", "@24@0:8@16") &&
        signature(@"CGVirtualDisplay", @"applySettings:", "B24@0:8@16") &&
        signature(@"CGVirtualDisplay", @"displayID", "I16@0:8");
}

@implementation PLANKMacDesktopDisplay {
    PLANKMacVirtualDisplay *_display;
    atomic_uint _displayID;
    BOOL _busy;
}
- (CGDirectDisplayID)displayID { return atomic_load(&_displayID); }
- (BOOL)create {
    if (!supportedAPI()) { NSLog(@"PLANK virtual display API signature unavailable"); return NO; }
    PLANKMacDisplayDescriptor *descriptor = [[NSClassFromString(@"CGVirtualDisplayDescriptor") alloc] init];
    descriptor.name = @"PLANK Desktop";
    descriptor.maxPixelsWide = 5120; descriptor.maxPixelsHigh = 2160;
    descriptor.sizeInMillimeters = CGSizeMake(600, 340);
    descriptor.vendorID = 0xF0F0; descriptor.productID = 2; descriptor.serialNum = 1;
    descriptor.queue = dispatch_get_main_queue();
    _display = [[NSClassFromString(@"CGVirtualDisplay") alloc] initWithDescriptor:descriptor];
    if (!_display) { NSLog(@"PLANK virtual display descriptor rejected"); return NO; }
    NSMutableArray *available = [NSMutableArray array];
    for (size_t i = 0; i < sizeof(modes)/sizeof(modes[0]); ++i) {
        id mode = [[NSClassFromString(@"CGVirtualDisplayMode") alloc]
            initWithWidth:modes[i][0] height:modes[i][1] refreshRate:60];
        if (!mode) return NO;
        [available addObject:mode];
    }
    PLANKMacDisplaySettings *settings = [[NSClassFromString(@"CGVirtualDisplaySettings") alloc] init];
    settings.hiDPI = 0; settings.modes = available;
    if (![_display applySettings:settings]) { NSLog(@"PLANK virtual display modes rejected"); return NO; }
    atomic_store(&_displayID, _display.displayID);
    return self.displayID != kCGNullDirectDisplay;
}
- (BOOL)selectWidth:(unsigned)width height:(unsigned)height {
    CGDirectDisplayID display = self.displayID;
    if (!CGDisplayIsOnline(display) || CGDisplayIsInMirrorSet(display)) return NO;
    CFArrayRef available = CGDisplayCopyAllDisplayModes(display, NULL);
    BOOL selected = NO;
    if (available && CFArrayGetCount(available) < 128) {
        for (CFIndex i = 0; i < CFArrayGetCount(available); ++i) {
            CGDisplayModeRef mode = (CGDisplayModeRef)CFArrayGetValueAtIndex(available, i);
            if (CGDisplayModeGetPixelWidth(mode) == width && CGDisplayModeGetPixelHeight(mode) == height &&
                CGDisplayModeGetWidth(mode) == width && CGDisplayModeGetHeight(mode) == height &&
                fabs(CGDisplayModeGetRefreshRate(mode) - 60) < .01) {
                selected = CGDisplaySetDisplayMode(display, mode, NULL) == kCGErrorSuccess;
                break;
            }
        }
    }
    if (available) CFRelease(available);
    return selected;
}
- (void)prepareWidth:(unsigned)width height:(unsigned)height
              valid:(BOOL (^)(void))valid completion:(void (^)(BOOL))completion {
    NSAssert(NSThread.isMainThread, @"Display mutation belongs to the graphical main queue");
    if (_busy || !valid || !completion || !valid() || !PLANKMacDesktopModeSupported(width, height)) {
        if (completion) completion(NO); return;
    }
    if (!_display && ![self create]) { completion(NO); return; }
    _busy = YES;
    NSLog(@"PLANK desktop mode preparing: %ux%u display=%u", width, height, self.displayID);
    __block BOOL selected = NO;
    NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime + 6;
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, 50*NSEC_PER_MSEC, 5*NSEC_PER_MSEC);
    dispatch_source_set_event_handler(timer, ^{
        BOOL allowed = valid();
        if (allowed && !selected) selected = [self selectWidth:width height:height];
        CGDirectDisplayID display = self.displayID;
        BOOL ready = allowed && selected && CGDisplayIsActive(display) &&
            CGDisplayPixelsWide(display) == width && CGDisplayPixelsHigh(display) == height &&
            CGDisplayBounds(display).size.width == width && CGDisplayBounds(display).size.height == height;
        if (ready || !allowed || NSProcessInfo.processInfo.systemUptime >= deadline) {
            dispatch_source_cancel(timer);
            dispatch_source_set_event_handler(timer, nil);
            self->_busy = NO;
            if (ready) NSLog(@"PLANK desktop mode ready: %ux%u", width, height);
            else NSLog(@"PLANK desktop mode not ready: selected=%d authorized=%d", selected, allowed);
            completion(ready);
        }
    });
    dispatch_resume(timer);
}
@end
