// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

typedef NS_ENUM(NSInteger, PLANKMacInputResult) {
    PLANKMacInputEvent,
    PLANKMacInputNoEvent,
    PLANKMacInputUnsupported,
    PLANKMacInputMalformed,
    PLANKMacInputStopped,
    PLANKMacInputDenied,
};

typedef struct { NSTimeInterval delay, interval; } PLANKMacKeyRepeatTiming;

// Native input packet -> public Quartz event. No posting, event taps, permission
// prompts, worker, transport, or authentication bypass lives in this component.
// The owner calls on one serial queue, inside its authorized delivery boundary,
// and destroys/recreates the mapper when the captured topology changes.
@interface PLANKMacInputEvents : NSObject
// Local, nonblocking cached policy supplied by the graphical owner. Invoked
// only for validated nonzero scroll input; nil keeps the one-line baseline.
@property(nonatomic, copy) double (^scrollLinesPerNotch)(void);
// Read when a new repeatable key is pressed; nil disables repeat in fixtures.
@property(nonatomic, copy) PLANKMacKeyRepeatTiming (^keyRepeatTiming)(void);
@property(nonatomic, readonly) uint64_t nextRepeatTime;
- (PLANKMacInputResult)repeatAtTime:(uint64_t)time accept:(BOOL (^)(CGEventRef))accept;
// Bounds are global Quartz points; pixels are the captured display's physical
// pixels, not a client window size or a guessed Retina scale. Source is retained.
- (instancetype)initWithSource:(CGEventSourceRef)source bounds:(CGRect)bounds
                        pixels:(CGSize)pixels initialPosition:(CGPoint)position
           doubleClickInterval:(NSTimeInterval)interval;
// time is the owner's monotonic nanosecond clock, never a remote timestamp.
// accept receives a borrowed event and must synchronously return whether it was
// accepted. False rolls back ALL packet state; no cleanup release will be made
// for an event that was never delivered. No recursive calls from this callback.
// Unsupported/malformed packets do not invoke accept or change input state.
- (PLANKMacInputResult)consumeType:(uint8_t)type payload:(NSData *)payload
                           time:(uint64_t)time accept:(BOOL (^)(CGEventRef))accept;
// One-shot: construct releases only for this mapper's held keys/buttons, then
// refuse all further packets. Returned objects are CGEvents owned by the array.
// This does NOT grant permission to post into a different user's desktop. The
// graphical-session owner must decide whether safe delivery is still possible.
- (NSArray *)stopAndCopyReleaseEvents;
@end
