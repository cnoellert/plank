// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#import <Foundation/Foundation.h>

// One authenticated desktop stream. Methods run on the supplied serial queue;
// AppKit work is bounded to one main-queue operation and never blocks that queue.
// The authority callback must also be safe on the main queue. No token/content
// logging, root pasteboard, new listener or permissions manipulation.
@interface PLANKMacClipboardSync : NSObject
- (instancetype)initWithQueue:(dispatch_queue_t)queue
                     allowed:(BOOL (^)(void))allowed
                        send:(int32_t (^)(NSData *frame))send;
- (BOOL)receive:(NSData *)frame;
- (void)tick;
- (void)stop;
@end
