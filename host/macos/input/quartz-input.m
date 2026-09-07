// SPDX-License-Identifier: GPL-3.0-or-later
#import "quartz-input.h"
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>

@implementation PLANKMacQuartzInput
- (BOOL)available { return CGPreflightPostEventAccess() && AXIsProcessTrusted(); }
- (PLANKMacInputEvents *)eventsForTopology:(NSDictionary *)topology {
    if (![self available]) return nil;
    NSDictionary *capture = topology[@"capture"], *bounds = capture[@"logical_bounds"];
    // The session owner has already validated the exact trusted topology.
    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStatePrivate);
    CGEventRef current = CGEventCreate(NULL);
    if (!source || !current) {
        if (source) CFRelease(source);
        if (current) CFRelease(current);
        return nil;
    }
    PLANKMacInputEvents *events = [[PLANKMacInputEvents alloc] initWithSource:source
        bounds:CGRectMake([bounds[@"x"] doubleValue], [bounds[@"y"] doubleValue],
            [bounds[@"width"] doubleValue], [bounds[@"height"] doubleValue])
        pixels:CGSizeMake([capture[@"width"] doubleValue], [capture[@"height"] doubleValue])
        initialPosition:CGEventGetLocation(current) doubleClickInterval:NSEvent.doubleClickInterval];
    CFRelease(current); CFRelease(source);
    return events;
}
- (void)postEvent:(CGEventRef)event { CGEventPost(kCGHIDEventTap, event); }
@end
