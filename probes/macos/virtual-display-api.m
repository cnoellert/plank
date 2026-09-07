// SPDX-License-Identifier: GPL-3.0-or-later
// Inspect runtime declarations only. This does not create a display.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>

/** Report method signatures without invoking the undocumented API. */
int main(void) {
    @autoreleasepool {
        // Reference CoreGraphics so the framework is loaded before inspection.
        (void)CGMainDisplayID();
        NSDictionary<NSString *, NSArray<NSString *> *> *checks = @{
            @"CGVirtualDisplayDescriptor": @[@"init", @"setName:",
                @"setMaxPixelsWide:", @"setMaxPixelsHigh:",
                @"setSizeInMillimeters:", @"setQueue:", @"setDispatchQueue:",
                @"setVendorID:", @"setProductID:", @"setSerialNum:"],
            @"CGVirtualDisplaySettings": @[@"init", @"setHiDPI:", @"setModes:"],
            @"CGVirtualDisplayMode": @[@"initWithWidth:height:refreshRate:"],
            @"CGVirtualDisplay": @[@"initWithDescriptor:", @"applySettings:",
                @"displayID"]
        };
        NSMutableDictionary *classes = [NSMutableDictionary dictionary];
        for (NSString *name in checks) {
            Class cls = NSClassFromString(name);
            NSMutableDictionary *methods = [NSMutableDictionary dictionary];
            for (NSString *selector in checks[name]) {
                Method method = cls ? class_getInstanceMethod(cls,
                    NSSelectorFromString(selector)) : NULL;
                methods[selector] = method ? @(method_getTypeEncoding(method))
                                          : (id)[NSNull null];
            }
            classes[name] = @{@"present": @(cls != Nil), @"methods": methods};
        }
        NSData *json = [NSJSONSerialization dataWithJSONObject:classes
            options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
        if (!json || fwrite(json.bytes, 1, json.length, stdout) != json.length ||
            fputc('\n', stdout) == EOF) {
            return 1;
        }
    }
    return 0;
}
