// SPDX-License-Identifier: GPL-3.0-or-later
#import "quartz-input.h"
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <IOKit/pwr_mgt/IOPMLib.h>
#include <math.h>
#include <time.h>

double PLANKMacScrollLinesForPreference(CFTypeRef value) {
    double setting = 0;
    if (!value || CFGetTypeID(value) != CFNumberGetTypeID() ||
        !CFNumberGetValue((CFNumberRef)value, kCFNumberDoubleType, &setting) || !isfinite(setting)) return 1;
    // Eight operator-measured macOS 27 slider positions, not a linear 0..1
    // multiplier. Map positions to 1..8 lines/notch. Interpolate unusual values
    // rather than snapping across a floating-point rounding boundary. This is
    // a predictable PLANK response, not Apple's hardware acceleration curve.
    static const double positions[] = {0, 0.0735, 0.1265, 0.1838, 0.3125, 0.4412, 0.5882, 1};
    if (setting <= positions[0]) return 1;
    for (unsigned i = 1; i < sizeof(positions) / sizeof(positions[0]); ++i)
        if (setting <= positions[i])
            return i + (setting - positions[i - 1]) / (positions[i] - positions[i - 1]);
    return 8;
}

// No persistent polling timer or dedicated thread. Active scrolling requests
// at most one off-path preference refresh per second; the event uses the cached
// value immediately. Never make cfprefsd calls under the input authorization lock.
@interface PLANKMacScrollPreference : NSObject
- (double)lines;
@end

@implementation PLANKMacScrollPreference {
    NSLock *_lock;
    double _lines;
    uint64_t _lastRefresh;
    BOOL _pending;
}
- (instancetype)init {
    self = [super init];
    if (self) { _lock = [NSLock new]; _lines = 1; (void)[self lines]; }
    return self;
}
- (double)lines {
    uint64_t now = clock_gettime_nsec_np(CLOCK_MONOTONIC);
    [_lock lock];
    double result = _lines;
    BOOL refresh = !_pending && (!_lastRefresh || now - _lastRefresh >= NSEC_PER_SEC);
    if (refresh) { _pending = YES; _lastRefresh = now; }
    [_lock unlock];
    if (refresh) dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        Boolean synced = CFPreferencesSynchronize(kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPropertyListRef value = synced ? CFPreferencesCopyValue(CFSTR("com.apple.scrollwheel.scaling"),
            kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) : NULL;
        double updated = PLANKMacScrollLinesForPreference(value);
        if (value) CFRelease(value);
        [self->_lock lock];
        if (synced) self->_lines = updated; // transient read failure retains last valid policy
        self->_pending = NO;
        [self->_lock unlock];
    });
    return result;
}
@end

@implementation PLANKMacUserActivity {
    IOPMAssertionID _assertion;
    uint64_t _lastAttempt;
    BOOL _attempted, _stopped, _reportedFailure;
}
- (void)noteAtTime:(uint64_t)time {
    if (_stopped || (_attempted && (time < _lastAttempt || time - _lastAttempt < NSEC_PER_SEC))) return;
    _attempted = YES; _lastAttempt = time;
    // An interactive console needs UserIsActive, even if a virtual display is
    // already active. Remote/network-only activity does not establish that
    // console state. This does not unlock, authenticate, or bypass screen lock.
    IOReturn result = IOPMAssertionDeclareUserActivity(CFSTR("PLANK remote console input"),
        kIOPMUserActiveLocal, &_assertion);
    if (result == kIOReturnSuccess) {
        // Retain the ID when idle, but turn the assertion OFF after ten seconds.
        // The next real input re-arms it. No background tick renews activity.
        result = IOPMAssertionSetProperty(_assertion, kIOPMAssertionTimeoutActionKey,
                                         kIOPMAssertionTimeoutActionTurnOff);
        if (result == kIOReturnSuccess)
            result = IOPMAssertionSetProperty(_assertion, kIOPMAssertionTimeoutKey,
                                             (__bridge CFNumberRef)@10);
    }
    if (result != kIOReturnSuccess) {
        if (_assertion != kIOPMNullAssertionID) IOPMAssertionRelease(_assertion);
        _assertion = kIOPMNullAssertionID;
        if (!_reportedFailure) NSLog(@"PLANK console activity request failed: %d", result);
        _reportedFailure = YES;
    } else _reportedFailure = NO;
}
- (void)stop {
    _stopped = YES;
    if (_assertion != kIOPMNullAssertionID) IOPMAssertionRelease(_assertion);
    _assertion = kIOPMNullAssertionID;
}
- (void)dealloc { [self stop]; }
@end

@implementation PLANKMacQuartzInput {
    PLANKMacUserActivity *_activity;
}
- (BOOL)available { return CGPreflightPostEventAccess() && AXIsProcessTrusted(); }
- (PLANKMacInputEvents *)eventsForTopology:(NSDictionary *)topology {
    if (![self available]) {
        NSLog(@"PLANK input startup failed: Accessibility/event-posting permission required"); return nil;
    }
    NSDictionary *capture = topology[@"capture"], *bounds = capture[@"logical_bounds"];
    // The session owner has already validated the exact trusted topology.
    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStatePrivate);
    CGEventRef current = CGEventCreate(NULL);
    if (!source || !current) {
        NSLog(@"PLANK input startup failed: graphical event source unavailable");
        if (source) CFRelease(source);
        if (current) CFRelease(current);
        return nil;
    }
    PLANKMacInputEvents *events = [[PLANKMacInputEvents alloc] initWithSource:source
        bounds:CGRectMake([bounds[@"x"] doubleValue], [bounds[@"y"] doubleValue],
            [bounds[@"width"] doubleValue], [bounds[@"height"] doubleValue])
        pixels:CGSizeMake([capture[@"width"] doubleValue], [capture[@"height"] doubleValue])
        initialPosition:CGEventGetLocation(current) doubleClickInterval:NSEvent.doubleClickInterval];
    PLANKMacScrollPreference *preference = [PLANKMacScrollPreference new];
    events.scrollLinesPerNotch = ^double { return [preference lines]; };
    events.keyRepeatTiming = ^PLANKMacKeyRepeatTiming {
        return (PLANKMacKeyRepeatTiming){NSEvent.keyRepeatDelay, NSEvent.keyRepeatInterval};
    };
    CFRelease(current); CFRelease(source);
    return events;
}
- (void)postEvent:(CGEventRef)event userActivity:(BOOL)userActivity {
    if (userActivity) {
        if (!_activity) _activity = [PLANKMacUserActivity new];
        [_activity noteAtTime:clock_gettime_nsec_np(CLOCK_MONOTONIC)];
    }
    CGEventPost(kCGHIDEventTap, event);
}
- (void)stopUserActivity { [_activity stop]; }
@end
