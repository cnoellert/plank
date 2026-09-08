// SPDX-License-Identifier: GPL-3.0-or-later
// Cross-process qualification of production IPC modules, not an installed Host.
#import "agent-registry.h"
#import "agent-connection.h"
#import "session-boundary.h"
#import "authentication-session.h"

// Synthetic verifier ONLY in this local IPC harness. Exercise the production
// conversation/lease owner without credentials, Open Directory or OS input.
static PLANKMacAccountIdentity testPrincipal;
PLANKMacAuthenticationResult PLANKMacVerifyAccountIsolated(
        NSString *name, NSMutableData *password, PLANKMacAccountIdentity *identity) {
    BOOL accepted = [name isEqual:@"qualification"] && password.length == 4 && !memcmp(password.bytes, "test", 4);
    [password resetBytesInRange:NSMakeRange(0, password.length)];
    *identity = accepted ? testPrincipal : (PLANKMacAccountIdentity){0};
    return accepted ? PLANKMacAuthenticationVerified : PLANKMacAuthenticationDenied;
}

int main(int argc, const char **argv) {
    if (argc != 3 || strlen(argv[2]) > 180) return 2;
    alarm(35); setbuf(stdout, NULL);
    @autoreleasepool {
        NSString *requirement = PLANKMacOwnSigningRequirement();
        if (!requirement) return 2;
        dispatch_queue_t queue = dispatch_get_main_queue();
        if (!strcmp(argv[1], "--service")) {
            if (getuid() != 0) return 2;
            __block __weak PLANKMacAgentRegistry *weakRegistry = nil;
            __block PLANKMacAuthenticationSession *auth = nil;
            __block PLANKMacStreamLease *stream = nil;
            PLANKMacAgentRegistry *registry = [[PLANKMacAgentRegistry alloc] initWithQueue:queue requirement:requirement
                scope:^PLANKMacAgentPhase(PLANKMacAgentPeer peer) {
                    PLANKMacAgentPhase phase = PLANKMacObserveAgentScope(peer);
                    if (phase == PLANKMacAgentUnavailable) printf("agent_service_scope_denied=1\n");
                    return phase;
                } event:^(PLANKMacAgentLease *lease, PLANKMacAgentEvent event) {
                    if (event == PLANKMacAgentAttached) {
                        if (lease.peer.pid == getpid()) _exit(3);
                        printf("agent_service_attached=1 cross_process=1 phase=%u\n", lease.phase);
                        PLANKMacGraphicalIdentity scope = [weakRegistry authenticationScope:lease];
                        if (!plank_macos_graphical_identity_valid(scope) || scope.generation != lease.generation ||
                            (scope.phase == PLANKMacScopeSignIn) != (lease.phase == PLANKMacAgentLoginWindow)) _exit(6);
                        testPrincipal = scope.phase == PLANKMacScopeDesktop ? scope.account :
                            (PLANKMacAccountIdentity){123, {1}};
                        // Same serial queue in this bounded test; no sync calls
                        // into the auth owner from another registry queue.
                        auth = [[PLANKMacAuthenticationSession alloc] initWithGraphicalSnapshot:^{
                            return [weakRegistry authenticationScope:lease];
                        }];
                        NSData *peer = [NSData dataWithBytes:"test" length:4];
                        NSDictionary *challenge = [auth startForPeer:peer username:@"qualification"];
                        NSMutableData *password = [NSMutableData dataWithBytes:"test" length:4];
                        NSDictionary *response = [auth respondForPeer:peer conversation:challenge[@"conversation_id"] password:password];
                        stream = [auth claimToken:response[@"session_token"] peer:peer];
                        if (![auth activateStreamLease:stream] ||
                            ![auth performWithStreamLease:stream action:^{}]) _exit(7);
                        puts("agent_service_admission=1 synthetic_verification=1");
                    }
                    if (event == PLANKMacAgentRevoked) {
                        // Snapshot invalidation, not a manually invoked revokeAll,
                        // must end access and erase the native transport token.
                        if ([auth performWithStreamLease:stream action:^{}] || stream.transportToken) _exit(8);
                        puts("agent_service_admission_revoked=1");
                    }
                    if (event == PLANKMacAgentRetired) {
                        // Test owns no media/input/displays. Real controller must
                        // independently drain those resources before this call.
                        BOOL done = [weakRegistry completeRetirement:lease];
                        printf("agent_service_empty_cleanup=%d\n", done);
                        if (!done) _exit(4);
                    }
                }];
            if (!registry) return 2;
            weakRegistry = registry;
            xpc_connection_t listener = xpc_connection_create_mach_service(argv[2], queue, XPC_CONNECTION_MACH_SERVICE_LISTENER);
            xpc_connection_set_event_handler(listener, ^(xpc_object_t peer) {
                if (xpc_get_type(peer) == XPC_TYPE_CONNECTION) [registry accept:peer];
            });
            xpc_connection_activate(listener);
            printf("agent_service_ready=1\n");
            CFRunLoopRun();
            [registry stop]; xpc_connection_cancel(listener); return 0;
        }
        BOOL background = !strcmp(argv[1], "--background-peer");
        if (!background && strcmp(argv[1], "--agent")) return 2;
        PLANKGraphicalSession initial = PLANKReadGraphicalSession();
        if (!background && initial.phase == PLANKSessionUnavailable) return 2;
        if (background && initial.phase != PLANKSessionUnavailable) return 2;
        PLANKMacAgentPhase phase = initial.phase == PLANKSessionDesktop ? PLANKMacAgentDesktop : PLANKMacAgentLoginWindow;
        xpc_connection_t peer = xpc_connection_create_mach_service(argv[2], queue, XPC_CONNECTION_MACH_SERVICE_PRIVILEGED);
        __block __weak PLANKMacAgentConnection *weakAgent = nil;
        __block int result = 5;
        PLANKMacAgentConnection *agent = [[PLANKMacAgentConnection alloc] initWithPeer:peer queue:queue
            requirement:requirement serverUID:0 phase:phase valid:^BOOL {
                // Deliberately false claimed scope in the negative TEST peer;
                // the real machine observer must reject its kernel audit ID.
                return background || PLANKSessionMatches(initial, PLANKReadGraphicalSession());
            } event:^(PLANKMacAgentConnectionState state, uint64_t generation) {
                (void)generation;
                if (state == PLANKMacAgentReady) {
                    if (background) { result = 3; CFRunLoopStop(CFRunLoopGetMain()); return; }
                    printf("graphical_agent_ready=1 phase=%u\n", phase);
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), queue, ^{
                        if (![weakAgent authorized]) { result = 4; CFRunLoopStop(CFRunLoopGetMain()); return; }
                        [weakAgent retire];
                    });
                }
                if (state == PLANKMacAgentFinished || state == PLANKMacAgentDisconnected) {
                    result = (background ? state == PLANKMacAgentDisconnected : state == PLANKMacAgentFinished) ? 0 : 5;
                    printf("graphical_agent_complete=%d background_rejected=%d\n", result == 0, background);
                    CFRunLoopStop(CFRunLoopGetMain());
                }
            }];
        if (!agent) return 2;
        weakAgent = agent;
        if (![agent start]) return 2;
        CFRunLoopRun(); [agent stop]; return result;
    }
}
