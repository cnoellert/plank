// SPDX-License-Identifier: GPL-3.0-or-later
#import "http-request.h"

static BOOL token(NSString *value) {
    if (!value.length) return NO;
    const char *characters = value.UTF8String;
    for (NSUInteger i = 0; characters[i]; ++i) {
        unsigned char c = characters[i];
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
            (c >= '0' && c <= '9') || strchr("!#$%&'*+-.^_`|~", c))) return NO;
    }
    return YES;
}

PLANKMacHTTPParseResult PLANKMacParseAuthRequest(NSData *bytes, NSString **path, NSRange *body) {
    if (path) *path = nil;
    if (body) *body = NSMakeRange(0, 0);
    if (!path || !body || bytes.length > PLANKMacHTTPHeaderLimit + PLANKMacHTTPBodyLimit)
        return PLANKMacHTTPInvalid;
    NSRange delimiter = [bytes rangeOfData:[NSData dataWithBytes:"\r\n\r\n" length:4]
                                 options:0 range:NSMakeRange(0, MIN(bytes.length, PLANKMacHTTPHeaderLimit))];
    if (delimiter.location == NSNotFound)
        return bytes.length >= PLANKMacHTTPHeaderLimit ? PLANKMacHTTPInvalid : PLANKMacHTTPIncomplete;
    const unsigned char *raw = bytes.bytes;
    for (NSUInteger i = 0; i < delimiter.location; ++i)
        if ((raw[i] < 32 && raw[i] != '\r' && raw[i] != '\n' && raw[i] != '\t') || raw[i] > 126)
            return PLANKMacHTTPInvalid;
    NSString *head = [[NSString alloc] initWithBytes:raw length:delimiter.location encoding:NSASCIIStringEncoding];
    NSArray<NSString *> *lines = [head componentsSeparatedByString:@"\r\n"];
    NSArray *request = [lines.firstObject componentsSeparatedByString:@" "];
    if (request.count != 3 || ![request[0] isEqual:@"POST"] || ![request[2] isEqual:@"HTTP/1.1"] ||
        [request[1] length] > 1024 || ![request[1] hasPrefix:@"/"] ||
        [request[1] rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound)
        return PLANKMacHTTPInvalid;
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    for (NSUInteger i = 1; i < lines.count; ++i) {
        NSString *line = lines[i];
        NSRange colon = [line rangeOfString:@":"];
        if (colon.location == NSNotFound) return PLANKMacHTTPInvalid;
        NSString *name = [[line substringToIndex:colon.location] lowercaseString];
        NSString *value = [[line substringFromIndex:colon.location + 1]
            stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" \t"]];
        if (!token(name) || headers[name] ||
            [value rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location != NSNotFound)
            return PLANKMacHTTPInvalid;
        headers[name] = value;
    }
    NSString *length = headers[@"content-length"];
    if (![headers[@"host"] length] || ![headers[@"content-type"] isEqual:@"application/json"] ||
        headers[@"transfer-encoding"] || headers[@"expect"] || headers[@"upgrade"] ||
        !length.length || length.length > 5) return PLANKMacHTTPInvalid;
    NSUInteger contentLength = 0;
    for (NSUInteger i = 0; i < length.length; ++i) {
        unichar c = [length characterAtIndex:i];
        if (c < '0' || c > '9') return PLANKMacHTTPInvalid;
        contentLength = contentLength * 10 + c - '0';
    }
    if (!contentLength || contentLength > PLANKMacHTTPBodyLimit) return PLANKMacHTTPInvalid;
    NSUInteger start = NSMaxRange(delimiter);
    if (bytes.length > start + contentLength) return PLANKMacHTTPInvalid;
    if (bytes.length < start + contentLength) return PLANKMacHTTPIncomplete;
    *path = request[1];
    *body = NSMakeRange(start, contentLength);
    return PLANKMacHTTPComplete;
}
