// SPDX-License-Identifier: GPL-3.0-or-later
// Synthetic protocol-state tests: no network, Open Directory or real credentials.
#ifdef NDEBUG
#undef NDEBUG
#endif
#include <assert.h>
#include <unistd.h>
#include <dispatch/dispatch.h>
#import "authentication-session.h"

static PLANKMacGraphicalIdentity desktop = {true, 1, {123, {1}}, PLANKMacScopeDesktop};
static unsigned verifications;
static unsigned checks;
static dispatch_semaphore_t verificationEntered, verificationRelease;
#define CHECK(value) do { assert((value)); ++checks; } while (0)

PLANKMacAuthenticationResult PLANKMacVerifyAccountIsolated(
        NSString *name, NSMutableData *password, PLANKMacAccountIdentity *output) {
    ++verifications;
    [password resetBytesInRange:NSMakeRange(0, password.length)];
    *output = (PLANKMacAccountIdentity){123, {1}};
    if ([name isEqualToString:@"wrong-owner"]) output->uid = 456;
    if ([name isEqualToString:@"root"]) output->uid = 0;
    if ([name isEqualToString:@"phase-change"]) desktop.phase = PLANKMacScopeDesktop;
    if ([name isEqualToString:@"replace"]) ++desktop.generation;
    if ([name isEqualToString:@"blocked"]) {
        dispatch_semaphore_signal(verificationEntered);
        dispatch_semaphore_wait(verificationRelease, DISPATCH_TIME_FOREVER);
    }
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
    alarm(15);
    @autoreleasepool {
        NSData *peer = [NSData dataWithBytes:"abcd" length:4];
        NSData *other = [NSData dataWithBytes:"efgh" length:4];
        PLANKMacAuthenticationSession *sessions = [[PLANKMacAuthenticationSession alloc]
            initWithGraphicalSnapshot:^{ return desktop; }];
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
        CHECK([success[@"desktop_stage"] isEqual:@"desktop"]);
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
        CHECK([[sessions startForPeer:peer username:@"test"][@"state"] isEqual:@"busy"]);
        [sessions revokeAll];

        // Capacity is not a credential failure; revoking one abandoned setup
        // immediately restores admission without changing the bounded limit.
        for (int i = 0; i < 16; ++i) {
            start = [sessions startForPeer:peer username:@"test"];
            token = respond(sessions, peer, start[@"conversation_id"])[@"session_token"];
            CHECK(token != nil);
        }
        CHECK([[sessions startForPeer:peer username:@"test"][@"state"] isEqual:@"busy"]);
        [sessions revokeToken:token];
        start = [sessions startForPeer:peer username:@"test"];
        CHECK([respond(sessions, peer, start[@"conversation_id"])[@"state"] isEqual:@"authenticated"]);
        [sessions revokeAll];

        start = [sessions startForPeer:peer username:@"test"];
        token = respond(sessions, peer, start[@"conversation_id"])[@"session_token"];
        CHECK([sessions claimToken:token peer:other] == nil);
        CHECK([sessions authorizeToken:token peer:peer identity:&identity]);
        PLANKMacStreamLease *lease = [sessions claimToken:token peer:peer];
        CHECK(lease != nil && lease.transportToken.length == 44);
        CHECK(![lease.transportToken isEqual:token]);
        CHECK(![sessions authorizeToken:token peer:peer identity:&identity]);
        CHECK([sessions claimToken:token peer:peer] == nil);
        CHECK(![sessions authorizeStreamLease:lease identity:&identity] && identity.uid == 0);
        CHECK(![sessions activateStreamLease:[PLANKMacStreamLease new]]);
        CHECK([sessions activateStreamLease:lease]);
        CHECK(![sessions activateStreamLease:lease]);
        __block unsigned enqueues = 0;
        CHECK([sessions performWithStreamLease:lease action:^{ ++enqueues; }]);
        CHECK(enqueues == 1);
        CHECK([sessions authorizeStreamLease:lease identity:&identity] && identity.uid == 123);
        // A claimed lease must not inherit the five-minute setup-token expiry.
        [[lease valueForKey:@"record"] setValue:@0 forKey:@"expires"];
        [lease setValue:@0 forKey:@"activateBefore"];
        CHECK([sessions authorizeStreamLease:lease identity:&identity]);
        start = [sessions startForPeer:peer username:@"test"];
        NSString *second = respond(sessions, peer, start[@"conversation_id"])[@"session_token"];
        CHECK([sessions claimToken:second peer:peer] == nil); // no implicit takeover
        [sessions endStreamLease:[PLANKMacStreamLease new]];
        CHECK([sessions authorizeStreamLease:lease identity:&identity]);
        [sessions revokeToken:token]; // failed launch response still revokes its claim
        CHECK(![sessions performWithStreamLease:lease action:^{ ++enqueues; }]);
        CHECK(enqueues == 1);
        CHECK(![sessions authorizeStreamLease:lease identity:&identity]);
        CHECK(lease.transportToken == nil);
        lease = [sessions claimToken:second peer:peer];
        CHECK(lease != nil);
        [lease setValue:@0 forKey:@"activateBefore"];
        CHECK(![sessions activateStreamLease:lease]);
        CHECK(lease.transportToken == nil);
        CHECK([sessions claimToken:second peer:peer] == nil);

        start = [sessions startForPeer:peer username:@"test"];
        token = respond(sessions, peer, start[@"conversation_id"])[@"session_token"];
        lease = [sessions claimToken:token peer:peer];
        CHECK([sessions activateStreamLease:lease]);
        ++desktop.generation;
        CHECK(![sessions authorizeStreamLease:lease identity:&identity]);
        --desktop.generation;
        CHECK(![sessions authorizeStreamLease:lease identity:&identity]); // revoked stays revoked

        start = [sessions startForPeer:peer username:@"test"];
        token = respond(sessions, peer, start[@"conversation_id"])[@"session_token"];
        lease = [sessions claimToken:token peer:peer];
        CHECK([sessions activateStreamLease:lease]);
        verificationEntered = dispatch_semaphore_create(0);
        verificationRelease = dispatch_semaphore_create(0);
        dispatch_semaphore_t verificationFinished = dispatch_semaphore_create(0);
        start = [sessions startForPeer:peer username:@"blocked"];
        __block NSDictionary *lateResponse;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            NSMutableData *password = [NSMutableData dataWithBytes:"test" length:4];
            lateResponse = [sessions respondForPeer:peer conversation:start[@"conversation_id"] password:password];
            dispatch_semaphore_signal(verificationFinished);
        });
        CHECK(dispatch_semaphore_wait(verificationEntered, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)) == 0);
        // This must complete while verification is blocked, not wait for the
        // helper's multi-second timeout. The outer alarm detects a lock regression.
        CHECK([sessions authorizeStreamLease:lease identity:&identity]);
        [sessions revokeAll];
        CHECK(![sessions authorizeStreamLease:lease identity:&identity]);
        dispatch_semaphore_signal(verificationRelease);
        CHECK(dispatch_semaphore_wait(verificationFinished, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)) == 0);
        CHECK([lateResponse[@"state"] isEqual:@"denied"]); // no grant after revokeAll
        CHECK([[sessions valueForKey:@"tokens"] count] == 0);
        start = [sessions startForPeer:peer username:@"test"];
        CHECK([respond(sessions, peer, start[@"conversation_id"])[@"state"] isEqual:@"authenticated"]);
        [sessions revokeAll];
        // Sign-in requires explicit valid scope. Absence of a desktop is not a
        // sign-in grant, and a remote principal is never the root GUI agent.
        desktop = (PLANKMacGraphicalIdentity){0};
        CHECK([[sessions startForPeer:peer username:@"test"][@"state"] isEqual:@"denied"]);
        desktop = (PLANKMacGraphicalIdentity){true, 40, {0, {0}}, PLANKMacScopeSignIn};
        for (NSString *name in @[@"root", @"replace", @"phase-change"]) {
            desktop.phase = PLANKMacScopeSignIn;
            start = [sessions startForPeer:peer username:name];
            CHECK([start[@"state"] isEqual:@"challenge"]);
            CHECK([respond(sessions, peer, start[@"conversation_id"])[@"state"] isEqual:@"denied"]);
        }
        desktop.phase = PLANKMacScopeSignIn;
        start = [sessions startForPeer:peer username:@"wrong-owner"];
        success = respond(sessions, peer, start[@"conversation_id"]);
        CHECK([success[@"desktop_stage"] isEqual:@"greeter"]);
        token = success[@"session_token"];
        CHECK([sessions authorizeToken:token peer:peer identity:&identity] && identity.uid == 456);
        lease = [sessions claimToken:token peer:peer];
        CHECK([sessions activateStreamLease:lease]);
        CHECK([sessions performWithStreamLease:lease action:^{ ++enqueues; }]);
        // Any phase change ends access, even when the verified user becomes the
        // desktop owner and a faulty fixture reuses the generation.
        PLANKMacGraphicalIdentity signIn = desktop;
        desktop.phase = PLANKMacScopeDesktop;
        desktop.account = identity;
        CHECK(![sessions authorizeStreamLease:lease identity:&identity]);
        CHECK(lease.transportToken == nil);
        desktop = signIn;
        CHECK(![sessions authorizeStreamLease:lease identity:&identity]);
        CHECK(![sessions authorizeToken:token peer:peer identity:&identity]);
        // Pending challenge cannot follow login either, even for the same user.
        start = [sessions startForPeer:peer username:@"test"];
        desktop = (PLANKMacGraphicalIdentity){true, signIn.generation, {123, {1}}, PLANKMacScopeDesktop};
        previous = verifications;
        CHECK([respond(sessions, peer, start[@"conversation_id"])[@"state"] isEqual:@"denied"]);
        CHECK(verifications == previous);
        start = [sessions startForPeer:peer username:@"test"];
        token = respond(sessions, peer, start[@"conversation_id"])[@"session_token"];
        CHECK([sessions authorizeToken:token peer:peer identity:&identity]);
        desktop = signIn;
        CHECK(![sessions authorizeToken:token peer:peer identity:&identity]);
        start = [sessions startForPeer:peer username:@"test"];
        token = respond(sessions, peer, start[@"conversation_id"])[@"session_token"];
        ++desktop.generation; // replacement LoginWindow agent
        CHECK(![sessions authorizeToken:token peer:peer identity:&identity]);
        [sessions revokeAll];
        printf("macos_authentication_session=pass checks=%u synthetic_only=1\n", checks);
    }
}
