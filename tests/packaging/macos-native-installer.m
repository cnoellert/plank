// SPDX-License-Identifier: GPL-3.0-or-later
#define PLANK_INSTALLER_UNIT_TEST 1
#import "../../packaging/macos/native-installer.m"

int main(int argc, const char **argv) {
    @autoreleasepool {
        unsigned checks = 0;
#define CHECK(value) do { if (!(value)) { fprintf(stderr, "FAIL line %d\n", __LINE__); return 1; } ++checks; } while (0)
        for (NSString *version in @[@"1.0.80", @"1.0.80-macos-installer", @"10.20.30-test.2"])
            CHECK(PLANKInstallerVersionValid(version));
        for (id version in @[@"", @"1.0", @"1.0.80/other", @"1.0.80\n", @"1.0.80-UPPER", @1])
            CHECK(!PLANKInstallerVersionValid(version));
        NSMutableDictionary *config = [@{@"Address":@"0.0.0.0", @"Port":@28989, @"Name":@"Test",
            @"UUID":@"10d580de-73fa-4139-95ec-891804686ee2"} mutableCopy];
        CHECK(PLANKInstallerConfigValid(config));
        for (id port in @[@0,@(-1),@65536,@YES,@1.5,@"28989"] ) { config[@"Port"] = port; CHECK(!PLANKInstallerConfigValid(config)); }
        for (NSNumber *port in @[@1,@28989,@65535]) { config[@"Port"] = port; CHECK(PLANKInstallerConfigValid(config)); }
        config[@"Address"] = @"127.0.0.1"; CHECK(!PLANKInstallerConfigValid(config));
        config[@"Address"] = @"0.0.0.0"; config[@"UUID"] = @"bad"; CHECK(!PLANKInstallerConfigValid(config));
        CHECK(!PLANKInstallerConfigValid(@[]));
        CHECK(PLANKInstallerMissingJob(@"Could not find service \"job\" in domain", @"system/job"));
        CHECK(!PLANKInstallerMissingJob(@"Permission denied", @"system/job"));
        CHECK(!PLANKInstallerMissingJob(@"Could not find service \"other\"", @"system/job"));
        CHECK(PLANKInstallerMissingJob(@"Could not find domain for user", @"gui/501/job"));
        SecRequirementRef parsed = NULL;
        CHECK(SecRequirementCreateWithString((__bridge CFStringRef)PLANKInstallerRequirement(@PLANK_INSTALLER_TEAM, NO), 0, &parsed) == errSecSuccess);
        CFRelease(parsed); parsed = NULL;
        CHECK(SecRequirementCreateWithString((__bridge CFStringRef)PLANKInstallerRequirement(@PLANK_INSTALLER_TEAM, YES), 0, &parsed) == errSecSuccess);
        CFRelease(parsed);
        CHECK(![PLANKInstallerRequirement(@PLANK_INSTALLER_TEAM, NO) containsString:@"100.6.1.12"]);
        CHECK([PLANKInstallerRequirement(@PLANK_INSTALLER_TEAM, YES) containsString:@"100.6.1.12"]);
        NSDictionary *paths = jobPaths(), *definitions = jobDefinitions(); CHECK(paths.count == 3 && definitions.count == 3);
        for (NSString *label in paths) {
            CHECK([definitions[label][@"Label"] isEqual:label]);
            CHECK([definitions[label][@"ProgramArguments"][0] isEqual:Executable]);
            CHECK([paths[label] hasPrefix:@"/Library/Launch"]);
        }
        CHECK([definitions[Desktop][@"StandardOutPath"] isEqual:@"/dev/null"]);
        CHECK([definitions[SignIn][@"LimitLoadToSessionType"] isEqual:@"LoginWindow"]);
        CHECK([definitions[Desktop][@"LimitLoadToSessionType"] isEqual:@"Aqua"]);
        // Invalid paths fail before opening/creating a file. No root, services,
        // accounts, privacy changes or event posting in this test executable.
        BOOL caught = NO; @try { directory(@"relative", YES, 0700); } @catch (id error) { (void)error; caught = YES; }
        CHECK(caught);
        __block unsigned prints = 0, bootouts = 0, aliveCalls = 0;
        testCommand = ^NSString *(NSString *program, NSArray *arguments, BOOL checked, int *status) {
            (void)checked; require([program isEqual:@"/bin/launchctl"], @"Unexpected test command");
            if ([arguments[0] isEqual:@"bootout"]) { ++bootouts; return @""; }
            require([arguments[0] isEqual:@"print"], @"Unexpected launchctl operation"); ++prints;
            if (status) *status = prints == 1 ? 0 : 113;
            return prints == 1 ? @"state = running\n pid = 42\n" : @"Could not find service \"test\"";
        };
        testAlive = ^BOOL(pid_t pid) { require(pid == 42, @"Unexpected PID"); return ++aliveCalls == 1; };
        stopJob(@"system/test"); CHECK(prints == 3 && bootouts == 1 && aliveCalls == 2);
        testCommand = ^NSString *(NSString *program, NSArray *arguments, BOOL checked, int *status) {
            (void)program; (void)arguments; (void)checked; if (status) *status = 1; return @"Permission denied";
        };
        caught = NO; @try { stopJob(@"system/test"); } @catch (id error) { (void)error; caught = YES; }
        CHECK(caught);
        __block NSTimeInterval time = 0;
        testClock = ^NSTimeInterval { time += 11; return time; };
        testAlive = ^BOOL(pid_t pid) { (void)pid; return YES; };
        testCommand = ^NSString *(NSString *program, NSArray *arguments, BOOL checked, int *status) {
            (void)program; (void)arguments; (void)checked; if (status) *status = 0; return @"state = running\n pid = 42\n";
        };
        caught = NO; @try { stopJob(@"system/test"); } @catch (id error) { (void)error; caught = YES; }
        CHECK(caught);
        testCommand = nil; testAlive = nil; testClock = nil;
        if (argc == 2 && !strcmp(argv[1], "--filesystem")) {
            CHECK(getuid() == 0);
            NSString *fixture = [@"/Library/Application Support/" stringByAppendingString:
                [@"plank-installer-test-" stringByAppendingString:NSUUID.UUID.UUIDString]];
            umask(0077);
            @try {
                close(directory(fixture, YES, 0755));
                struct stat st; CHECK(!lstat(fixture.fileSystemRepresentation, &st) && (st.st_mode&0777) == 0755);
                NSString *file = [fixture stringByAppendingPathComponent:@"config.plist"];
                NSData *original = [@"original" dataUsingEncoding:NSUTF8StringEncoding];
                writeProtected(file, original, 0644); CHECK([readProtected(file, 0644) isEqual:original]);
                writeProtected(file, [@"replaced" dataUsingEncoding:NSUTF8StringEncoding], 0644);
                CHECK([[[NSString alloc] initWithData:readProtected(file, 0644) encoding:NSUTF8StringEncoding] isEqual:@"replaced"]);
                NSString *link = [fixture stringByAppendingPathComponent:@"symlink"];
                CHECK(!symlink(file.fileSystemRepresentation, link.fileSystemRepresentation));
                caught = NO; @try { writeProtected(link, original, 0644); } @catch (id error) { (void)error; caught = YES; }
                CHECK(caught);
                CHECK([[[NSString alloc] initWithData:readProtected(file, 0644) encoding:NSUTF8StringEncoding] isEqual:@"replaced"]);
                NSString *hard = [fixture stringByAppendingPathComponent:@"hardlink"];
                CHECK(!linkat(AT_FDCWD, file.fileSystemRepresentation, AT_FDCWD, hard.fileSystemRepresentation, 0));
                caught = NO; @try { readProtected(file, 0644); } @catch (id error) { (void)error; caught = YES; }
                CHECK(caught); CHECK(!unlink(hard.fileSystemRepresentation));
                CHECK(!chmod(file.fileSystemRepresentation, 0666));
                caught = NO; @try { readProtected(file, 0644); } @catch (id error) { (void)error; caught = YES; }
                CHECK(caught); CHECK(!chmod(file.fileSystemRepresentation, 0644));
                NSString *dirlink = [fixture stringByAppendingPathComponent:@"linked-directory"];
                CHECK(!symlink(fixture.fileSystemRepresentation, dirlink.fileSystemRepresentation));
                caught = NO; @try { directory(dirlink, NO, 0); } @catch (id error) { (void)error; caught = YES; }
                CHECK(caught);
                int status = -1; CHECK([run(@"/usr/bin/true", @[], YES, &status) isEqual:@""] && status == 0);
                run(@"/usr/bin/false", @[], NO, &status); CHECK(status != 0);
                caught = NO; @try { run(@"/usr/bin/false", @[], YES, NULL); } @catch (id error) { (void)error; caught = YES; }
                CHECK(caught);
            } @finally {
                NSError *error = nil;
                require([NSFileManager.defaultManager removeItemAtPath:fixture error:&error], @"Cannot remove exact test fixture");
            }
            printf("macos_native_installer_filesystem=pass checks=%u fixture_removed=1 service_changes=0\n", checks);
        }
        printf("macos_native_installer_policy=pass checks=%u system_mutations=0\n", checks);
    } return 0;
}
