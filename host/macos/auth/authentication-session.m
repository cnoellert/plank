// SPDX-License-Identifier: GPL-3.0-or-later
#import "authentication-session.h"
#import <Security/Security.h>
#include <time.h>

@interface PLANKMacAuthRecord : NSObject
@property(copy) NSData *peer;
@property(copy) NSString *username;
@property uint64_t expires;
@property PLANKMacDesktopIdentity desktop;
@property PLANKMacAccountIdentity account;
@end
@implementation PLANKMacAuthRecord
@end

@implementation PLANKMacAuthenticationSession {
    PLANKMacDesktopSnapshot _snapshot;
    NSMutableDictionary<NSString *, PLANKMacAuthRecord *> *_pending;
    NSMutableDictionary<NSString *, PLANKMacAuthRecord *> *_tokens;
}

static uint64_t monotonicSeconds(void) {
    return clock_gettime_nsec_np(CLOCK_MONOTONIC) / 1000000000ULL;
}

static NSString *randomToken(void) {
    unsigned char bytes[32];
    if (SecRandomCopyBytes(kSecRandomDefault, sizeof(bytes), bytes) != errSecSuccess) return nil;
    // Base64 is opaque JSON/header data, never a URL parameter or log field.
    NSString *token = [[NSData dataWithBytes:bytes length:sizeof(bytes)] base64EncodedStringWithOptions:0];
    volatile unsigned char *p = bytes;
    for (size_t i = 0; i < sizeof(bytes); ++i) p[i] = 0;
    return token;
}

static BOOL validPeer(NSData *peer) {
    return [peer isKindOfClass:NSData.class] && (peer.length == 4 || peer.length == 16);
}

static NSDictionary *denied(void) { return @{@"state": @"denied"}; }

- (instancetype)init { return nil; }

- (instancetype)initWithDesktopSnapshot:(PLANKMacDesktopSnapshot)snapshot {
    if (!snapshot) return nil;
    self = [super init];
    if (self) {
        _snapshot = [snapshot copy];
        _pending = [NSMutableDictionary dictionary];
        _tokens = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)prune {
    uint64_t now = monotonicSeconds();
    PLANKMacDesktopIdentity current = _snapshot();
    for (NSMutableDictionary *records in @[_pending, _tokens]) {
        for (NSString *key in records.allKeys) {
            PLANKMacAuthRecord *record = records[key];
            if (record.expires <= now || !plank_macos_account_may_attach(
                    record.desktop.account, record.desktop, current))
                [records removeObjectForKey:key];
        }
    }
}

- (NSDictionary *)startForPeer:(NSData *)peer username:(NSString *)username {
    @synchronized(self) {
        if (!validPeer(peer) || ![username isKindOfClass:NSString.class]) return denied();
        NSData *nameBytes = [username dataUsingEncoding:NSUTF8StringEncoding];
        if (!nameBytes.length || nameBytes.length > 255 || memchr(nameBytes.bytes, 0, nameBytes.length))
            return denied();
        [self prune];
        if (_pending.count >= 16 || _tokens.count >= 16) return denied();
        PLANKMacDesktopIdentity desktop = _snapshot();
        if (!plank_macos_account_may_attach(desktop.account, desktop, desktop)) return denied();
        NSString *conversation = randomToken();
        if (!conversation || _pending[conversation]) return denied();
        PLANKMacAuthRecord *record = [PLANKMacAuthRecord new];
        record.peer = peer;
        record.username = username;
        record.expires = monotonicSeconds() + 120;
        record.desktop = desktop;
        _pending[conversation] = record;
        return @{@"state": @"challenge", @"conversation_id": conversation,
            @"messages": @[@{@"style": @1, @"text": @"Password:"}]};
    }
}

- (NSDictionary *)respondForPeer:(NSData *)peer conversation:(NSString *)conversation
                       password:(NSMutableData *)password {
    @try {
        @synchronized(self) {
            if (!validPeer(peer) || ![conversation isKindOfClass:NSString.class] || conversation.length != 44)
                return denied();
            [self prune];
            PLANKMacAuthRecord *record = _pending[conversation];
            if (!record || ![record.peer isEqual:peer]) return denied();
            // Consume BEFORE any verification. A response can never be replayed.
            [_pending removeObjectForKey:conversation];
            PLANKMacAccountIdentity account = {0};
            if (_tokens.count >= 16 || PLANKMacVerifyAccountIsolated(record.username, password, &account) !=
                    PLANKMacAuthenticationVerified ||
                !plank_macos_account_may_attach(account, record.desktop, _snapshot())) return denied();
            NSString *token = randomToken();
            if (!token || _tokens[token]) return denied();
            record.account = account;
            record.username = nil;
            record.expires = monotonicSeconds() + 300;
            _tokens[token] = record;
            return @{@"state": @"authenticated", @"session_token": token};
        }
    } @finally {
        [password resetBytesInRange:NSMakeRange(0, password.length)];
    }
}

- (BOOL)authorizeToken:(NSString *)token peer:(NSData *)peer identity:(PLANKMacAccountIdentity *)identity {
    if (identity) memset(identity, 0, sizeof(*identity));
    @synchronized(self) {
        if (!identity || !validPeer(peer) || ![token isKindOfClass:NSString.class] || token.length != 44)
            return NO;
        [self prune];
        PLANKMacAuthRecord *record = _tokens[token];
        if (!record || ![record.peer isEqual:peer] ||
            !plank_macos_account_may_attach(record.account, record.desktop, _snapshot())) return NO;
        *identity = record.account;
        return YES;
    }
}

- (void)revokeAll {
    @synchronized(self) {
        [_pending removeAllObjects];
        [_tokens removeAllObjects];
    }
}

- (void)revokeToken:(NSString *)token {
    @synchronized(self) {
        if ([token isKindOfClass:NSString.class]) [_tokens removeObjectForKey:token];
    }
}
@end
