// SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

static BOOL PLANKInstallerVersionValid(NSString *value) {
    if (![value isKindOfClass:NSString.class]) return NO;
    NSRegularExpression *pattern = [NSRegularExpression regularExpressionWithPattern:
        @"\\A[0-9]+\\.[0-9]+\\.[0-9]+(?:-[a-z][a-z0-9.-]*)?\\z" options:0 error:NULL];
    return [pattern numberOfMatchesInString:value options:0 range:NSMakeRange(0, value.length)] == 1;
}

static BOOL PLANKInstallerConfigValid(id config) {
    if (![config isKindOfClass:NSDictionary.class] || [config count] != 4) return NO;
    id port = config[@"Port"];
    return [config[@"Address"] isEqual:@"0.0.0.0"] &&
        [config[@"Name"] isKindOfClass:NSString.class] && [config[@"Name"] length] > 0 &&
        [config[@"UUID"] isKindOfClass:NSString.class] &&
        [[NSUUID alloc] initWithUUIDString:config[@"UUID"]] != nil &&
        [port isKindOfClass:NSNumber.class] &&
        CFGetTypeID((__bridge CFTypeRef)port) != CFBooleanGetTypeID() &&
        [port doubleValue] == [port unsignedShortValue] && [port unsignedShortValue] != 0;
}

static BOOL PLANKInstallerMissingJob(NSString *output, NSString *job) {
    NSString *label = job.lastPathComponent;
    return [output containsString:[NSString stringWithFormat:@"Could not find service \"%@\"", label]] ||
        [output containsString:@"Could not find domain for"];
}

static NSString *PLANKInstallerRequirement(NSString *team, BOOL allowDevelopment) {
    return [NSString stringWithFormat:
        @"identifier \"la.instinctual.PLANK.Host\" and anchor apple generic and "
         "certificate leaf[subject.OU] = \"%@\" and "
         "(certificate leaf[field.1.2.840.113635.100.6.1.13] exists%@)", team,
        allowDevelopment ? @" or certificate leaf[field.1.2.840.113635.100.6.1.12] exists" : @""];
}
