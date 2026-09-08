// SPDX-License-Identifier: GPL-3.0-or-later
#import "server-information.h"

static BOOL publicText(NSString *value, NSUInteger maximum) {
    if (!value.length || [value lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > maximum) return NO;
    for (NSUInteger index = 0; index < value.length; ++index) {
        unichar c = [value characterAtIndex:index];
        if (c < 32 || c == 127 || c == 0xfffe || c == 0xffff) return NO;
    }
    return [value canBeConvertedToEncoding:NSUTF8StringEncoding];
}

@implementation PLANKMacServerInformation {
    NSString *_name;
    NSUUID *_uuid;
    NSString *_version;
    BOOL _streaming;
}

- (instancetype)initWithName:(NSString *)name workstationUUID:(NSUUID *)uuid version:(NSString *)version {
    return [self initWithName:name workstationUUID:uuid version:version streaming:NO];
}
- (instancetype)initWithName:(NSString *)name workstationUUID:(NSUUID *)uuid version:(NSString *)version
                  streaming:(BOOL)streaming {
    if (!uuid || !publicText(name, 255) || !publicText(version, 128)) return nil;
    uuid_t bytes;
    [uuid getUUIDBytes:bytes];
    const uuid_t zero = {0};
    if (!memcmp(bytes, zero, sizeof(bytes))) return nil;
    self = [super init];
    if (self) { _name = [name copy]; _uuid = [uuid copy]; _version = [version copy]; _streaming = streaming; }
    return self;
}

- (NSData *)XMLForControlPort:(uint16_t)port {
    return [self XMLForControlPort:port authorized:NO];
}
- (NSData *)XMLForControlPort:(uint16_t)port authorized:(BOOL)authorized {
    if (!port) return nil;
    NSXMLElement *root = [NSXMLElement elementWithName:@"root"];
    [root addAttribute:[NSXMLNode attributeWithName:@"status_code" stringValue:@"200"]];
    // Explicit zero is essential: an omitted codec mask makes the current
    // Client assume H.264. No media capability is advertised until native
    // stream claim, exact format negotiation and lifetime revocation exist.
    NSArray *fields = @[
        @[@"hostname", _name], @[@"uniqueid", _uuid.UUIDString.lowercaseString],
        @[@"HttpsPort", [NSString stringWithFormat:@"%u", port]],
        @[@"PlankHostMetadataVersion", @"1"], @[@"PlankHostVersion", _version],
        @[@"PlankAuth", @"1"], @[@"ServerCodecModeSupport", _streaming ? @"512" : @"0"],
        @[@"PlankTopologyVersion", _streaming ? @"13" : @"0"],
        @[@"PlankFeatureFlags", _streaming ? @"524401" : @"0"],
        @[@"PairStatus", authorized ? @"1" : @"0"]
    ];
    for (NSArray *field in fields)
        [root addChild:[NSXMLNode elementWithName:field[0] stringValue:field[1]]];
    return [[[NSXMLDocument alloc] initWithRootElement:root] XMLData];
}
@end

static BOOL targetMatches(NSString *target, NSString *path) {
    if ([target isEqual:path]) return YES;
    NSString *prefix = [path stringByAppendingString:@"?"];
    if (![target hasPrefix:prefix] || target.length > 1024) return NO;
    NSString *query = [target substringFromIndex:prefix.length];
    NSMutableSet *seen = [NSMutableSet set];
    for (NSString *part in [query componentsSeparatedByString:@"&"]) {
        NSArray *pair = [part componentsSeparatedByString:@"="];
        if (pair.count != 2) return NO;
        NSString *key = pair[0], *value = pair[1];
        if ((! [key isEqual:@"uniqueid"] && ![key isEqual:@"uuid"]) || [seen containsObject:key] ||
            !value.length || value.length > 64) return NO;
        for (NSUInteger index = 0; index < value.length; ++index) {
            unichar c = [value characterAtIndex:index];
            if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') ||
                  (c >= 'A' && c <= 'F') || c == '-')) return NO;
        }
        [seen addObject:key];
    }
    return YES;
}

BOOL PLANKMacIsServerInformationTarget(NSString *target) { return targetMatches(target, @"/serverinfo"); }
BOOL PLANKMacIsTopologyTarget(NSString *target) { return targetMatches(target, @"/plank/topology"); }
BOOL PLANKMacIsDesktopTarget(NSString *target) { return targetMatches(target, @"/applist"); }
