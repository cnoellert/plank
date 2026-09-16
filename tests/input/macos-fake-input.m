// SPDX-License-Identifier: GPL-3.0-or-later
#import "macos-fake-input.h"
@implementation PLANKFakeInput
- (instancetype)init { self = [super init]; if (self) _availableFlag = YES; return self; }
- (BOOL)available { return self.availableFlag; }
- (PLANKMacInputEvents *)eventsForTopology:(NSDictionary *)topology {
    if (!self.availableFlag) return nil;
    NSDictionary *capture = topology[@"capture"], *b = capture[@"logical_bounds"];
    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStatePrivate);
    if (!source) return nil;
    CGPoint origin = CGPointMake([b[@"x"] doubleValue], [b[@"y"] doubleValue]);
    PLANKMacInputEvents *events = [[PLANKMacInputEvents alloc] initWithSource:source
        bounds:CGRectMake(origin.x, origin.y, [b[@"width"] doubleValue], [b[@"height"] doubleValue])
        pixels:CGSizeMake([capture[@"width"] doubleValue], [capture[@"height"] doubleValue])
        initialPosition:origin doubleClickInterval:0.5];
    if (self.repeatEnabled) events.keyRepeatTiming = ^PLANKMacKeyRepeatTiming {
        return (PLANKMacKeyRepeatTiming){0.25, 0.03};
    };
    CFRelease(source); return events;
}
- (void)postEvent:(CGEventRef)event userActivity:(BOOL)userActivity {
    (void)userActivity;
    self.delivered++;
    CGEventType type = CGEventGetType(event);
    if (type == kCGEventKeyUp || type == kCGEventLeftMouseUp) self.releases++;
    // No CGEventPost, recorded user input, or real device state.
}
- (void)stopUserActivity {}
@end
