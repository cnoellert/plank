// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#import <Foundation/Foundation.h>

enum { PLANKMacHTTPHeaderLimit = 4096, PLANKMacHTTPBodyLimit = 32768 };
typedef NS_ENUM(unsigned int, PLANKMacHTTPParseResult) {
    PLANKMacHTTPIncomplete, PLANKMacHTTPComplete, PLANKMacHTTPInvalid
};

// Narrow HTTP/1.1: one bodyless GET or Content-Length-framed POST per connection.
// No chunking, pipelining, request smuggling, folded/duplicate headers or URLs
// carrying credentials. Only header values are decoded here; the body remains
// caller-owned mutable bytes until the authentication adapter consumes it.
// The target is deliberately not URL-decoded. The router validates the exact
// path and its allowed query keys; query values never establish identity.
PLANKMacHTTPParseResult PLANKMacParseControlRequest(NSData *bytes, NSString **method,
                                                  NSString **target, NSRange *body,
                                                  NSString **authorization);
