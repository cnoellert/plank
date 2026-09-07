// SPDX-License-Identifier: GPL-3.0-or-later
#import "account-verifier.h"
#import <OpenDirectory/OpenDirectory.h>
#include <membership.h>
#include <uuid/uuid.h>

static BOOL readIdentity(ODRecord *record, PLANKMacAccountIdentity *identity) {
    NSArray *uids = [record valuesForAttribute:kODAttributeTypeUniqueID error:NULL];
    NSArray *uuids = [record valuesForAttribute:kODAttributeTypeGUID error:NULL];
    if (uids.count != 1 || uuids.count != 1 ||
        ![uids.firstObject isKindOfClass:NSString.class] ||
        ![uuids.firstObject isKindOfClass:NSString.class]) return NO;
    NSString *uidText = uids.firstObject;
    if (!uidText.length || uidText.length > 10) return NO;
    uint64_t uid = 0;
    for (NSUInteger i = 0; i < uidText.length; ++i) {
        unichar c = [uidText characterAtIndex:i];
        if (c < '0' || c > '9') return NO;
        uid = uid * 10 + c - '0';
        if (uid >= UINT32_MAX) return NO;
    }
    NSUUID *guid = [[NSUUID alloc] initWithUUIDString:uuids.firstObject];
    if (!guid || uid == 0) return NO;
    identity->uid = (uint32_t)uid;
    [guid getUUIDBytes:identity->uuid];
    // A directory record with a colliding UID must not acquire another local
    // account's desktop. Confirm macOS resolves that UID to the same identity.
    uuid_t resolved;
    return plank_macos_account_identity_valid(*identity) &&
        mbr_uid_to_uuid((uid_t)uid, resolved) == 0 &&
        memcmp(resolved, identity->uuid, sizeof(resolved)) == 0;
}

PLANKMacAuthenticationResult PLANKMacVerifyAccount(
        NSString *name, NSMutableData *password, PLANKMacAccountIdentity *output) {
    if (output) memset(output, 0, sizeof(*output));
    @try {
        @autoreleasepool {
            NSData *nameBytes = [name dataUsingEncoding:NSUTF8StringEncoding];
            if (!output || !nameBytes.length || nameBytes.length > 255 ||
                memchr(nameBytes.bytes, 0, nameBytes.length) ||
                !password.length || password.length > 4096 ||
                memchr(password.bytes, 0, password.length)) return PLANKMacAuthenticationDenied;
            NSString *secret = [[NSString alloc] initWithBytes:password.bytes
                length:password.length encoding:NSUTF8StringEncoding];
            if (!secret) return PLANKMacAuthenticationDenied;
            ODNode *node = [ODNode nodeWithSession:ODSession.defaultSession
                type:kODNodeTypeAuthentication error:NULL];
            if (!node) return PLANKMacAuthenticationUnavailable;
            ODRecord *record = [node recordWithRecordType:kODRecordTypeUsers name:name
                attributes:@[kODAttributeTypeUniqueID, kODAttributeTypeGUID] error:NULL];
            PLANKMacAccountIdentity identity = {0};
            if (!record || !readIdentity(record, &identity)) return PLANKMacAuthenticationDenied;
            // SDK 27 documents that verifyPassword already evaluates record and
            // node authentication/password policies. Do not duplicate policy or
            // turn a password-expired/disabled result into successful access.
            if (![record verifyPassword:secret error:NULL]) return PLANKMacAuthenticationDenied;
            PLANKMacAccountIdentity confirmed = {0};
            if (!readIdentity(record, &confirmed) || confirmed.uid != identity.uid ||
                memcmp(confirmed.uuid, identity.uuid, sizeof(identity.uuid)))
                return PLANKMacAuthenticationDenied;
            *output = identity;
            return PLANKMacAuthenticationVerified;
        }
    } @catch (NSException *exception) {
        (void)exception; // Never log directory/framework credential-bearing text.
        if (output) memset(output, 0, sizeof(*output));
        return PLANKMacAuthenticationUnavailable;
    } @finally {
        [password resetBytesInRange:NSMakeRange(0, password.length)];
    }
}
