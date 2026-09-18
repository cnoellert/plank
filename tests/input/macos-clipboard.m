// SPDX-License-Identifier: GPL-3.0-or-later
#import "clipboard-sync.h"
#import <AppKit/AppKit.h>
#include "plank_clipboard_wire.h"
#include "plank_transport.h"
#include <stdatomic.h>

NSPasteboard *PLANKClipboardTestPasteboard(void) {
    static NSPasteboard *board;
    if (!board) board = [NSPasteboard pasteboardWithUniqueName];
    return board;
}
#define CHECK(x) do { if (!(x)) { fprintf(stderr, "clipboard check failed: %d\n", __LINE__); exit(1); } } while (0)
static void pump(void) {
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.03]];
}
static NSData *frame(NSString *text, uint64_t generation) {
    NSData *bytes = [text dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *result = [NSMutableData dataWithLength:32 + bytes.length];
    plank_clipboard_header(result.mutableBytes, generation, (uint32_t)bytes.length, 0, (uint32_t)bytes.length);
    memcpy((uint8_t *)result.mutableBytes + 32, bytes.bytes, bytes.length);
    return result;
}
int main(void) { @autoreleasepool {
    dispatch_queue_t queue = dispatch_queue_create("plank.clipboard.fixture", DISPATCH_QUEUE_SERIAL);
    __block BOOL allowed = YES, full = YES;
    __block unsigned sent = 0;
    PLANKMacClipboardSync *sync = [[PLANKMacClipboardSync alloc] initWithQueue:queue
        allowed:^BOOL { return allowed; } send:^int32_t(NSData *data) {
            PlankClipboardChunk chunk;
            CHECK(plank_clipboard_decode(data.bytes, data.length, PLANK_CLIPBOARD_EVENT_BYTES, &chunk));
            if (full) return PLANK_TRANSPORT_TIMEOUT;
            ++sent; return PLANK_TRANSPORT_OK;
        }];
    NSPasteboard *board = PLANKClipboardTestPasteboard();
    [board clearContents]; [board setString:@"local\nUnicode 🔥" forType:NSPasteboardTypeString];
    dispatch_sync(queue, ^{ [sync tick]; }); pump();
    dispatch_sync(queue, ^{ [sync tick]; CHECK(sent == 0); full = NO; [sync tick]; CHECK(sent == 1); });
    dispatch_sync(queue, ^{ CHECK([sync receive:frame(@"remote A", 1)]); }); pump();
    CHECK([[board stringForType:NSPasteboardTypeString] isEqual:@"remote A"]);
    dispatch_sync(queue, ^{ CHECK([sync receive:frame(@"remote B", 2)]); }); pump();
    dispatch_sync(queue, ^{ CHECK([sync receive:frame(@"remote A", 3)]); }); pump();
    CHECK([[board stringForType:NSPasteboardTypeString] isEqual:@"remote A"]);
    // Even identical text copied again belongs to the local application.
    [board clearContents]; [board setString:@"remote A" forType:NSPasteboardTypeString];
    dispatch_sync(queue, ^{ [sync stop]; }); pump();
    CHECK([[board stringForType:NSPasteboardTypeString] isEqual:@"remote A"]);
    dispatch_sync(queue, ^{ CHECK(![sync receive:frame(@"stale", 4)]); });
    PLANKMacClipboardSync *denied = [[PLANKMacClipboardSync alloc] initWithQueue:queue
        allowed:^BOOL { return NO; } send:^int32_t(NSData *data) { (void)data; CHECK(NO); return 0; }];
    dispatch_sync(queue, ^{ [denied tick]; CHECK(![denied receive:frame(@"denied", 1)]); }); pump();
    CHECK([[board stringForType:NSPasteboardTypeString] isEqual:@"remote A"]);
    [board releaseGlobally];
    puts("Mac Host clipboard: bidirectional, queue pressure, generations, ownership and denial passed");
} }
