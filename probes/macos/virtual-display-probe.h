// SPDX-License-Identifier: GPL-3.0-or-later
// Experimental private-API qualification, never linked into the Host package.
#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#include <math.h>
#include <string.h>

// Signatures independently inspected on the development Mac. Runtime checks
// below reject differences before invoking any private selector.
@interface PLANKDisplayDescriptor : NSObject
@property(nonatomic, copy) NSString *name;
@property(nonatomic) unsigned int maxPixelsWide;
@property(nonatomic) unsigned int maxPixelsHigh;
@property(nonatomic) CGSize sizeInMillimeters;
@property(nonatomic) unsigned int vendorID;
@property(nonatomic) unsigned int productID;
@property(nonatomic) unsigned int serialNum;
@property(nonatomic, strong) dispatch_queue_t queue;
@end
@interface PLANKDisplayMode : NSObject
- (instancetype)initWithWidth:(unsigned int)width height:(unsigned int)height
                  refreshRate:(double)rate;
@end
@interface PLANKDisplaySettings : NSObject
@property(nonatomic) unsigned int hiDPI;
@property(nonatomic, strong) NSArray *modes;
@end
@interface PLANKVirtualDisplay : NSObject
- (instancetype)initWithDescriptor:(id)descriptor;
- (BOOL)applySettings:(id)settings;
@property(nonatomic, readonly) unsigned int displayID;
@end

/** Fail closed on a missing or different runtime selector signature. */
static BOOL matches(NSString *name, NSString *selector, const char *encoding) {
    Method method = class_getInstanceMethod(NSClassFromString(name),
                                            NSSelectorFromString(selector));
    if (!method || strcmp(method_getTypeEncoding(method), encoding) != 0) {
        fprintf(stderr, "Unsupported runtime signature: %s %s\n",
                name.UTF8String, selector.UTF8String);
        return NO;
    }
    return YES;
}

/** Validate the limited API surface used by this experiment. */
static BOOL validateAPI(void) {
    BOOL valid = YES;
    for (NSString *selector in @[@"setName:", @"setQueue:"]) {
        valid &= matches(@"CGVirtualDisplayDescriptor", selector, "v24@0:8@16");
    }
    for (NSString *selector in @[@"setMaxPixelsWide:", @"setMaxPixelsHigh:",
                                @"setVendorID:", @"setProductID:", @"setSerialNum:"]) {
        valid &= matches(@"CGVirtualDisplayDescriptor", selector, "v20@0:8I16");
    }
    valid &= matches(@"CGVirtualDisplayDescriptor", @"setSizeInMillimeters:",
                     "v32@0:8{CGSize=dd}16");
    valid &= matches(@"CGVirtualDisplayMode", @"initWithWidth:height:refreshRate:",
                     "@32@0:8I16I20d24");
    valid &= matches(@"CGVirtualDisplaySettings", @"setHiDPI:", "v20@0:8I16");
    valid &= matches(@"CGVirtualDisplaySettings", @"setModes:", "v24@0:8@16");
    valid &= matches(@"CGVirtualDisplay", @"initWithDescriptor:", "@24@0:8@16");
    valid &= matches(@"CGVirtualDisplay", @"applySettings:", "B24@0:8@16");
    valid &= matches(@"CGVirtualDisplay", @"displayID", "I16@0:8");
    return valid;
}

/** Return membership only after successful bounded graphical enumeration. */
static int onlineState(CGDirectDisplayID display) {
    CGDirectDisplayID displays[32];
    uint32_t count = 0;
    CGError error = CGGetOnlineDisplayList(32, displays, &count);
    if (error != kCGErrorSuccess || count >= 32) return -1;
    for (uint32_t i = 0; i < count; ++i) {
        if (displays[i] == display) return 1;
    }
    return 0;
}

/** Log measured geometry; requested dimensions are never called actual. */
static inline BOOL report(CGDirectDisplayID display, unsigned int width, unsigned int height) {
    CGDisplayModeRef mode = CGDisplayCopyDisplayMode(display);
    size_t pixelWidth = mode ? CGDisplayModeGetPixelWidth(mode) : 0;
    size_t pixelHeight = mode ? CGDisplayModeGetPixelHeight(mode) : 0;
    double rate = mode ? CGDisplayModeGetRefreshRate(mode) : 0;
    printf("display=%u online=%d active=%d actual=%zux%zu refresh=%.3f\n",
           display, CGDisplayIsOnline(display), CGDisplayIsActive(display),
           pixelWidth, pixelHeight, rate);
    BOOL ready = onlineState(display) == 1 && CGDisplayIsActive(display) == 1 &&
                 pixelWidth == width && pixelHeight == height && fabs(rate - 60) < 0.01;
    if (mode) CGDisplayModeRelease(mode);
    return ready;
}

/** Shared experimental creator; dimensions are explicit qualification inputs. */
static PLANKVirtualDisplay *createProbeDisplayWithIdentity(unsigned int width, unsigned int height,
                                                          unsigned int product, unsigned int serial) {
    if (!width || !height || width > 8192 || height > 8192 || !serial || !validateAPI()) return nil;
    PLANKDisplayDescriptor *descriptor =
        [[NSClassFromString(@"CGVirtualDisplayDescriptor") alloc] init];
    descriptor.name = @"PLANK Feasibility Probe";
    descriptor.maxPixelsWide = width;
    descriptor.maxPixelsHigh = height;
    descriptor.sizeInMillimeters = CGSizeMake(508, 285.75);
    descriptor.vendorID = 0xF0F0;
    descriptor.productID = product;
    descriptor.serialNum = serial;
    descriptor.queue = dispatch_get_main_queue();
    PLANKVirtualDisplay *display =
        [[NSClassFromString(@"CGVirtualDisplay") alloc] initWithDescriptor:descriptor];
    if (!display) { fprintf(stderr, "Display creation refused\n"); return nil; }
    PLANKDisplayMode *mode = [[NSClassFromString(@"CGVirtualDisplayMode") alloc]
        initWithWidth:width height:height refreshRate:60];
    PLANKDisplaySettings *settings =
        [[NSClassFromString(@"CGVirtualDisplaySettings") alloc] init];
    if (!mode || !settings) return nil;
    settings.hiDPI = 0;
    settings.modes = @[mode];
    if (![display applySettings:settings]) {
        fprintf(stderr, "Display settings refused\n");
        return nil;
    }
    return display;
}

/** Keep the original bounded diagnostic identity; geometry-specific identity
 * experiments did not guarantee the requested initial mode on macOS 27.
 * No per-run/random identity: macOS retains monitor profiles after removal.
 */
static inline PLANKVirtualDisplay *createProbeDisplay(unsigned int width, unsigned int height) {
    if (!width || !height || width > 8192 || height > 8192) return nil;
    return createProbeDisplayWithIdentity(width, height, 1, 1);
}
