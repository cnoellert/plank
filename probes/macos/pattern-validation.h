// SPDX-License-Identifier: GPL-3.0-or-later
#import <AppKit/AppKit.h>
#import <VideoToolbox/VideoToolbox.h>

NSWindow *PLANKCreatePatternWindow(CGDirectDisplayID display, BOOL mixedCadence);
NSArray<NSNumber *> *PLANKReadPatternSamples(CVPixelBufferRef pixel);
double PLANKPatternReferenceError(NSArray<NSNumber *> *samples, BOOL tenBit, BOOL bt601);
NSArray<NSNumber *> *PLANKPatternMap601To709(NSArray<NSNumber *> *samples, BOOL tenBit);

@interface PLANKPatternValidator : NSObject
@property(nonatomic, readonly) BOOL complete;
@property(nonatomic, readonly) BOOL passed;
- (void)decode:(CMSampleBufferRef)sample reference:(NSArray<NSNumber *> *)reference
    pixelFormat:(OSType)format queue:(dispatch_queue_t)queue completion:(void (^)(void))completion;
- (void)invalidate;
@end
