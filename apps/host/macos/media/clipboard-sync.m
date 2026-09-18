// SPDX-License-Identifier: GPL-3.0-or-later
#import "clipboard-sync.h"
#import <AppKit/AppKit.h>
#include "plank_clipboard_wire.h"
#include "plank_transport.h"
#include <stdatomic.h>
#include <time.h>

#ifdef PLANK_CLIPBOARD_TEST_PASTEBOARD
extern NSPasteboard *PLANKClipboardTestPasteboard(void);
#endif
static NSPasteboard *pasteboard(void) {
#ifdef PLANK_CLIPBOARD_TEST_PASTEBOARD
    return PLANKClipboardTestPasteboard();
#else
    return NSPasteboard.generalPasteboard;
#endif
}

@implementation PLANKMacClipboardSync {
    dispatch_queue_t _queue;
    BOOL (^_allowed)(void);
    int32_t (^_send)(NSData *);
    atomic_bool _stopped;
    BOOL _mainPending;
    uint64_t _nextPoll, _inGeneration, _lastGeneration, _outGeneration, _revision;
    uint32_t _inTotal, _outOffset;
    NSMutableData *_assembly;
    NSData *_pendingRemote, *_outgoing;
    // Accessed only on the main queue, including asynchronous stop cleanup.
    NSInteger _lastChange, _ownedChange;
}
- (instancetype)initWithQueue:(dispatch_queue_t)queue allowed:(BOOL (^)(void))allowed
                        send:(int32_t (^)(NSData *))send {
    self = [super init];
    if (!self || !queue || !allowed || !send) return nil;
    _queue = queue; _allowed = [allowed copy]; _send = [send copy];
    _lastChange = _ownedChange = -1;
    return self;
}
- (BOOL)receive:(NSData *)frame {
    if (atomic_load(&_stopped) || !_allowed()) return NO;
    PlankClipboardChunk chunk;
    if (!plank_clipboard_decode(frame.bytes, frame.length, PLANK_CLIPBOARD_INPUT_BYTES, &chunk)) return NO;
    if (chunk.generation <= _lastGeneration) return YES;
    if (chunk.flags & PLANK_CLIPBOARD_FIRST) {
        _assembly = [NSMutableData dataWithCapacity:chunk.total];
        _inGeneration = chunk.generation; _inTotal = chunk.total;
    }
    if (!_assembly || chunk.generation != _inGeneration || chunk.total != _inTotal ||
        chunk.offset != _assembly.length) return NO;
    [_assembly appendBytes:chunk.bytes length:chunk.size];
    if (!(chunk.flags & PLANK_CLIPBOARD_LAST)) return YES;
    if (!plank_clipboard_valid_text(_assembly.bytes, _assembly.length)) return NO;
    _lastGeneration = chunk.generation;
    _pendingRemote = _assembly; _assembly = nil;
    ++_revision;
    _outgoing = nil; _outOffset = 0;
    [self tick];
    return YES;
}
- (void)tick {
    if (atomic_load(&_stopped) || !_allowed()) { [self stop]; return; }
    // Control/cursor/audio are not held behind a clipboard burst. A full native
    // queue retains the exact unsent offset; it is not a session failure.
    for (unsigned i = 0; _outgoing && i < 2; ++i) {
        uint32_t count = MIN(PLANK_CLIPBOARD_EVENT_BYTES, _outgoing.length - _outOffset);
        NSMutableData *frame = [NSMutableData dataWithLength:PLANK_CLIPBOARD_HEADER_BYTES + count];
        plank_clipboard_header(frame.mutableBytes, _outGeneration, (uint32_t)_outgoing.length, _outOffset, count);
        memcpy((uint8_t *)frame.mutableBytes + PLANK_CLIPBOARD_HEADER_BYTES,
               (const uint8_t *)_outgoing.bytes + _outOffset, count);
        int32_t result = _send(frame);
        if (result == PLANK_TRANSPORT_TIMEOUT) break;
        if (result != PLANK_TRANSPORT_OK) { [self stop]; return; }
        _outOffset += count;
        if (_outOffset == _outgoing.length) { _outgoing = nil; _outOffset = 0; }
    }
    uint64_t now = clock_gettime_nsec_np(CLOCK_MONOTONIC);
    if (_mainPending || (!_pendingRemote && now < _nextPoll)) return;
    _nextPoll = now + 250 * NSEC_PER_MSEC; _mainPending = YES;
    NSData *incoming = _pendingRemote; _pendingRemote = nil;
    uint64_t revision = _revision;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSData *local = nil;
        if (!atomic_load(&self->_stopped) && self->_allowed()) {
            NSPasteboard *board = pasteboard();
            if (incoming) {
                NSString *text = [[NSString alloc] initWithData:incoming encoding:NSUTF8StringEncoding];
                if (text && !atomic_load(&self->_stopped) && self->_allowed()) {
                    [board clearContents];
                    if ([board setString:text forType:NSPasteboardTypeString])
                        self->_lastChange = self->_ownedChange = board.changeCount;
                }
            } else if (board.changeCount != self->_lastChange &&
                       board.accessBehavior != NSPasteboardAccessBehaviorAlwaysDeny) {
                NSInteger count = board.changeCount;
                NSString *text = [board stringForType:NSPasteboardTypeString];
                NSUInteger length = [text lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
                if (length && length <= PLANK_CLIPBOARD_TEXT_LIMIT) {
                    NSData *bytes = [text dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:NO];
                    if (plank_clipboard_valid_text(bytes.bytes, bytes.length)) local = bytes;
                }
                if (board.changeCount == count) {
                    self->_lastChange = count; self->_ownedChange = -1;
                } else local = nil;
            }
        }
        dispatch_async(self->_queue, ^{
            self->_mainPending = NO;
            if (atomic_load(&self->_stopped) || !self->_allowed()) return;
            if (local && revision == self->_revision) {
                self->_outgoing = local; self->_outOffset = 0; ++self->_outGeneration;
            }
        });
    });
}
- (void)stop {
    if (atomic_exchange(&_stopped, true)) return;
    _assembly = nil; _pendingRemote = nil; _outgoing = nil;
    // Same user process/main queue: a newer local copy is never removed. A
    // queued read/write checks revocation before access and cannot transmit.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_ownedChange >= 0) {
            NSPasteboard *board = pasteboard();
            if (board.changeCount == self->_ownedChange) [board clearContents];
        }
        self->_ownedChange = -1;
    });
}
@end
