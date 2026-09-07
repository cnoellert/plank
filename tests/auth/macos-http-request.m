// SPDX-License-Identifier: GPL-3.0-or-later
#ifdef NDEBUG
#undef NDEBUG
#endif
#include <assert.h>
#import "http-request.h"

static unsigned checks;
static void check(NSData *bytes, PLANKMacHTTPParseResult expected) {
    NSString *path = @"old";
    NSString *method = @"old";
    NSString *authorization = @"old";
    NSRange body = NSMakeRange(999, 999);
    assert(PLANKMacParseControlRequest(bytes, &method, &path, &body, &authorization) == expected);
    if (expected != PLANKMacHTTPComplete) assert(!method && !path && !body.length && !authorization);
    ++checks;
}

int main(void) {
    @autoreleasepool {
        NSString *valid = @"POST /plank/auth/start HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n{}";
        NSData *bytes = [valid dataUsingEncoding:NSUTF8StringEncoding];
        for (NSUInteger length = 0; length < bytes.length; ++length)
            check([bytes subdataWithRange:NSMakeRange(0, length)], PLANKMacHTTPIncomplete);
        check(bytes, PLANKMacHTTPComplete);
        NSString *path, *method, *authorization;
        NSRange body;
        assert(PLANKMacParseControlRequest(bytes, &method, &path, &body, &authorization) == PLANKMacHTTPComplete);
        assert([method isEqual:@"POST"] && [path isEqual:@"/plank/auth/start"] && body.length == 2 &&
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
        NSString *get = @"GET /serverinfo?uniqueid=0123456789ABCDEF&uuid=abcdef HTTP/1.1\r\nHost: localhost\r\n\r\n";
        NSData *getBytes = [get dataUsingEncoding:NSUTF8StringEncoding];
        for (NSUInteger length = 0; length < getBytes.length; ++length)
            check([getBytes subdataWithRange:NSMakeRange(0, length)], PLANKMacHTTPIncomplete);
        check(getBytes, PLANKMacHTTPComplete);
        assert(PLANKMacParseControlRequest(getBytes, &method, &path, &body, &authorization) == PLANKMacHTTPComplete);
        assert([method isEqual:@"GET"] && [path hasPrefix:@"/serverinfo?"] && body.length == 0);
        check([[get stringByReplacingOccurrencesOfString:@"Host: localhost" withString:
                @"Host: localhost\r\nContent-Length: 0"] dataUsingEncoding:NSUTF8StringEncoding], PLANKMacHTTPComplete);
        for (NSString *extra in @[@"Content-Length: 1", @"Content-Length:", @"Content-Length: -1",
                @"Transfer-Encoding: chunked", @"Expect: 100-continue", @"Upgrade: h2c",
                @"Content-Length: 0\r\nContent-Length: 0"]) {
            check([[get stringByReplacingOccurrencesOfString:@"Host: localhost" withString:
                [@"Host: localhost\r\n" stringByAppendingString:extra]] dataUsingEncoding:NSUTF8StringEncoding],
                PLANKMacHTTPInvalid);
        }
        check([[get stringByAppendingString:@"x"] dataUsingEncoding:NSUTF8StringEncoding], PLANKMacHTTPInvalid);
        NSString *authorized = [get stringByReplacingOccurrencesOfString:@"Host: localhost" withString:
            @"Host: localhost\r\nAuthorization: Bearer synthetic-test-token"];
        assert(PLANKMacParseControlRequest([authorized dataUsingEncoding:NSUTF8StringEncoding],
            &method, &path, &body, &authorization) == PLANKMacHTTPComplete);
        assert([authorization isEqual:@"Bearer synthetic-test-token"]);
        check([[authorized stringByReplacingOccurrencesOfString:@"Host: localhost" withString:
            @"Host: localhost\r\nAuthorization: Bearer duplicate"] dataUsingEncoding:NSUTF8StringEncoding], PLANKMacHTTPInvalid);
        check([[get stringByReplacingOccurrencesOfString:@"GET " withString:@"HEAD "]
                dataUsingEncoding:NSUTF8StringEncoding], PLANKMacHTTPInvalid);
        printf("macos_http_request=pass checks=%u\n", checks);
    }
}
