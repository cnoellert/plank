// SPDX-License-Identifier: GPL-3.0-or-later
// Synthetic protocol-state tests: no network, Open Directory or real credentials.
#ifdef NDEBUG
#undef NDEBUG
#endif
#include <assert.h>
#import "authentication-session.h"

static PLANKMacDesktopIdentity desktop = {true, 1, {123, {1}}};
static unsigned verifications;
static unsigned checks;
#define CHECK(value) do { assert((value)); ++checks; } while (0)

PLANKMacAuthenticationResult PLANKMacVerifyAccountIsolated(
        NSString *name, NSMutableData *password, PLANKMacAccountIdentity *output) {
    ++verifications;
    [password resetBytesInRange:NSMakeRange(0, password.length)];
    *output = (PLANKMacAccountIdentity){123, {1}};
    if ([name isEqualToString:@"wrong-owner"]) output->uid = 456;
    if ([name isEqualToString:@"replace"]) ++desktop.generation;
    return PLANKMacAuthenticationVerified;
}

static NSDictionary *respond(PLANKMacAuthenticationSession *sessions, NSData *peer, NSString *id) {
    NSMutableData *password = [NSMutableData dataWithBytes:"test" length:4];
    NSDictionary *response = [sessions respondForPeer:peer conversation:id password:password];
    static const unsigned char empty[4] = {0};
    CHECK(!memcmp(password.bytes, empty, 4));
    return response;
}

int main(void) {
    @autoreleasepool {
        NSData *peer = [NSData dataWithBytes:"abcd" length:4];
        NSData *other = [NSData dataWithBytes:"efgh" length:4];
        PLANKMacAuthenticationSession *sessions = [[PLANKMacAuthenticationSession alloc]
            initWithDesktopSnapshot:^{ return desktop; }];
        CHECK(sessions != nil);
        CHECK([[sessions startForPeer:[NSData data] username:@"test"][@"state"] isEqual:@"denied"]);
        CHECK([[sessions startForPeer:peer username:@""][@"state"] isEqual:@"denied"]);
        NSDictionary *start = [sessions startForPeer:peer username:@"test"];
        CHECK([start[@"state"] isEqual:@"challenge"]);
        CHECK([start[@"conversation_id"] length] == 44);
        CHECK([start[@"messages"][0][@"style"] intValue] == 1);
        CHECK([NSJSONSerialization isValidJSONObject:start]);
        CHECK([respond(sessions, other, start[@"conversation_id"])[@"state"] isEqual:@"denied"]);
        CHECK(verifications == 0);
        NSDictionary *success = respond(sessions, peer, start[@"conversation_id"]);
        CHECK([success[@"state"] isEqual:@"authenticated"]);
        NSString *token = success[@"session_token"];
        CHECK(token.length == 44 && [NSJSONSerialization isValidJSONObject:success]);
        CHECK([respond(sessions, peer, start[@"conversation_id"])[@"state"] isEqual:@"denied"]);
        CHECK(verifications == 1);
        PLANKMacAccountIdentity identity = {0};
        CHECK([sessions authorizeToken:token peer:peer identity:&identity] && identity.uid == 123);
        CHECK(![sessions authorizeToken:token peer:other identity:&identity] && identity.uid == 0);
        ++desktop.generation;
        CHECK(![sessions authorizeToken:token peer:peer identity:&identity]);
        for (NSString *name in @[@"wrong-owner", @"replace"]) {
            start = [sessions startForPeer:peer username:name];
            CHECK([respond(sessions, peer, start[@"conversation_id"])[@"state"] isEqual:@"denied"]);
        }
        start = [sessions startForPeer:peer username:@"test"];
        unsigned previous = verifications;
        ++desktop.generation;
        CHECK([respond(sessions, peer, start[@"conversation_id"])[@"state"] isEqual:@"denied"]);
        CHECK(verifications == previous);
        start = [sessions startForPeer:peer username:@"test"];
        // KVC test-only access: avoid a product clock/expiration bypass API.
        id pending = [sessions valueForKey:@"pending"];
        [pending[start[@"conversation_id"]] setValue:@0 forKey:@"expires"];
        CHECK([respond(sessions, peer, start[@"conversation_id"])[@"state"] isEqual:@"denied"]);
        CHECK(verifications == previous);
        start = [sessions startForPeer:peer username:@"test"];
        token = respond(sessions, peer, start[@"conversation_id"])[@"session_token"];
        id tokens = [sessions valueForKey:@"tokens"];
        [tokens[token] setValue:@0 forKey:@"expires"];
        CHECK(![sessions authorizeToken:token peer:peer identity:&identity]);
        start = [sessions startForPeer:peer username:@"test"];
        token = respond(sessions, peer, start[@"conversation_id"])[@"session_token"];
        [sessions revokeToken:token];
        CHECK(![sessions authorizeToken:token peer:peer identity:&identity]);
        start = [sessions startForPeer:peer username:@"test"];
        token = respond(sessions, peer, start[@"conversation_id"])[@"session_token"];
        [sessions revokeAll];
        CHECK(![sessions authorizeToken:token peer:peer identity:&identity]);
        desktop.active = false;
        CHECK([[sessions startForPeer:peer username:@"test"][@"state"] isEqual:@"denied"]);
        desktop.active = true;
        for (int i = 0; i < 16; ++i)
            CHECK([[sessions startForPeer:peer username:@"test"][@"state"] isEqual:@"challenge"]);
        CHECK([[sessions startForPeer:peer username:@"test"][@"state"] isEqual:@"denied"]);
        [sessions revokeAll];
        printf("macos_authentication_session=pass checks=%u synthetic_only=1\n", checks);
    }
}
