// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>

// One-shot desktop audio capture. Public methods and delivered callbacks use
// the supplied serial owner queue. HAL lifecycle work is off that queue.
// Audio is limited to this non-root user's processes, excluding the Host.
// stop drops buffered audio and completes only after HAL objects are destroyed.
@interface PLANKMacAudioTap : NSObject
- (instancetype)initWithQueue:(dispatch_queue_t)queue
                        sample:(BOOL (^)(CMSampleBufferRef sample))sample
                        failed:(void (^)(void))failed;
- (void)startWithCompletion:(void (^)(BOOL ready))completion;
- (void)stopWithCompletion:(void (^)(void))completion;
@end
