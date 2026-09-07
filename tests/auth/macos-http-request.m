// SPDX-License-Identifier: GPL-3.0-or-later
#ifdef NDEBUG
#undef NDEBUG
#endif
#include <assert.h>
#import "http-request.h"

static unsigned checks;
static void check(NSData *bytes, PLANKMacHTTPParseResult expected) {
    NSString *path = @"old";
    NSRange body = NSMakeRange(999, 999);
    assert(PLANKMacParseAuthRequest(bytes, &path, &body) == expected);
    if (expected != PLANKMacHTTPComplete) assert(!path && !body.length);
    ++checks;
}

int main(void) {
    @autoreleasepool {
        NSString *valid = @"POST /plank/auth/start HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n{}";
        NSData *bytes = [valid dataUsingEncoding:NSUTF8StringEncoding];
        for (NSUInteger length = 0; length < bytes.length; ++length)
            check([bytes subdataWithRange:NSMakeRange(0, length)], PLANKMacHTTPIncomplete);
        check(bytes, PLANKMacHTTPComplete);
        NSString *path;
        NSRange body;
        assert(PLANKMacParseAuthRequest(bytes, &path, &body) == PLANKMacHTTPComplete);
        assert([path isEqual:@"/plank/auth/start"] && body.length == 2 &&
            !memcmp((const char *)bytes.bytes + body.location, "{}", 2));
        NSArray *invalid = @[
            [valid stringByReplacingOccurrencesOfString:@"HTTP/1.1" withString:@"HTTP/1.0"],
            [valid stringByReplacingOccurrencesOfString:@"POST " withString:@"GET "],
            [valid stringByReplacingOccurrencesOfString:@"Content-Length: 2" withString:@"Content-Length: -1"],
            [valid stringByReplacingOccurrencesOfString:@"Content-Length: 2" withString:@"Content-Length: 32769"],
            [valid stringByReplacingOccurrencesOfString:@"Content-Length: 2" withString:@"Content-Length: 2\r\ncontent-length: 2"],
            [valid stringByReplacingOccurrencesOfString:@"Content-Length: 2" withString:@"Content-Length: 2\r\nTransfer-Encoding: chunked"],
            [valid stringByReplacingOccurrencesOfString:@"Content-Length: 2" withString:@"Content-Length: 2\r\nExpect: 100-continue"],
            [valid stringByReplacingOccurrencesOfString:@"Host:" withString:@" Host:"],
            [valid stringByReplacingOccurrencesOfString:@"Host: localhost\r\n" withString:@""],
            [valid stringByReplacingOccurrencesOfString:@"application/json" withString:@"text/plain"],
            [valid stringByReplacingOccurrencesOfString:@"Host: localhost" withString:@"Host: localhost\nInjected: x"],
            [valid stringByAppendingString:@"POST /second HTTP/1.1\r\n"]
        ];
        for (NSString *text in invalid) check([text dataUsingEncoding:NSUTF8StringEncoding], PLANKMacHTTPInvalid);
        NSMutableData *oversized = [NSMutableData dataWithLength:PLANKMacHTTPHeaderLimit];
        memset(oversized.mutableBytes, 'x', oversized.length);
        check(oversized, PLANKMacHTTPInvalid);
        NSMutableData *nul = [bytes mutableCopy];
        ((char *)nul.mutableBytes)[5] = 0;
        check(nul, PLANKMacHTTPInvalid);
        printf("macos_http_request=pass checks=%u\n", checks);
    }
}
