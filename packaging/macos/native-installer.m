// SPDX-License-Identifier: GPL-3.0-or-later
// Installer-only native setup. No setuid bit, persistent privileged helper,
// shell commands, network listeners, downloadable runtime or TCC database writes.
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#include <fcntl.h>
#include <pwd.h>
#include <signal.h>
#include <sys/stat.h>
#include <sys/utsname.h>
#include <sys/resource.h>
#include <unistd.h>
#import "installer-policy.h"

#ifndef PLANK_INSTALLER_TEAM
#error Explicit signing team required
#endif
#ifndef PLANK_INSTALLER_VERSION
#error Explicit package version required
#endif

static NSString *const App = @"/Applications/PLANK Host.app";
static NSString *const Executable = @"/Applications/PLANK Host.app/Contents/MacOS/plank-host";
static NSString *const State = @"/Library/Application Support/PLANK";
static NSString *const InstallerState = @"/Library/Application Support/PLANK/Installer";
static NSString *const Machine = @"la.instinctual.PLANK.Host.machine";
static NSString *const Desktop = @"la.instinctual.PLANK.Host.desktop";
static NSString *const SignIn = @"la.instinctual.PLANK.Host.sign-in";

#ifdef PLANK_INSTALLER_UNIT_TEST
// Linked only into the non-installing test executable, never a package helper.
static NSString *(^testCommand)(NSString *, NSArray *, BOOL, int *);
static BOOL (^testAlive)(pid_t);
static NSTimeInterval (^testClock)(void);
#endif

static NSTimeInterval now(void) {
#ifdef PLANK_INSTALLER_UNIT_TEST
    if (testClock) return testClock();
#endif
    return NSProcessInfo.processInfo.systemUptime;
}

static void require(BOOL value, NSString *message) {
    if (!value) @throw [NSException exceptionWithName:@"PLANKInstaller" reason:message userInfo:nil];
}

// Command output stays in an immediately unlinked, mode0600 file. Unlike a pipe,
// launchctl output cannot deadlock a child before the bounded wait completes.
static NSString *run(NSString *program, NSArray<NSString *> *arguments, BOOL checked, int *status) {
#ifdef PLANK_INSTALLER_UNIT_TEST
    if (testCommand) return testCommand(program, arguments, checked, status);
#endif
    char name[] = "/private/tmp/plank-installer-command.XXXXXX";
    int fd = mkstemp(name); require(fd >= 0, @"Cannot create command output"); unlink(name);
    NSFileHandle *handle = [[NSFileHandle alloc] initWithFileDescriptor:fd closeOnDealloc:YES];
    NSTask *task = [NSTask new]; task.executableURL = [NSURL fileURLWithPath:program];
    task.arguments = arguments;
    task.environment = @{@"PATH":@"/usr/bin:/bin:/usr/sbin:/sbin", @"LC_ALL":@"C"};
    task.standardInput = NSFileHandle.fileHandleWithNullDevice;
    task.standardOutput = handle; task.standardError = handle;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    task.terminationHandler = ^(NSTask *ended) { (void)ended; dispatch_semaphore_signal(done); };
    require([task launchAndReturnError:NULL], @"Cannot execute required macOS tool");
    if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 30*NSEC_PER_SEC))) {
        [task terminate];
        if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC))) {
            kill(task.processIdentifier, SIGKILL); [task waitUntilExit];
        }
        require(NO, @"Installer tool timed out; installation stopped");
    }
    [handle seekToFileOffset:0]; NSData *data = [handle readDataOfLength:1024*1024];
    require(data.length < 1024*1024, @"Unexpectedly large tool output");
    NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    if (status) *status = task.terminationStatus;
    require(!checked || task.terminationStatus == 0,
        [NSString stringWithFormat:@"%@ failed (%d): %@", program.lastPathComponent, task.terminationStatus, output]);
    return output;
}

static BOOL exists(NSString *path) {
    struct stat st;
    if (!lstat(path.fileSystemRepresentation, &st)) return YES;
    require(errno == ENOENT, @"Cannot inspect installation path"); return NO;
}

// Every component is traversed without following links. Apple's /Applications
// is normally root:admin0775; only that exact OS parent permits admin writes.
static int directory(NSString *path, BOOL create, mode_t mode) {
    require(path.isAbsolutePath, @"Absolute protected directory required");
    int fd = open("/", O_RDONLY|O_DIRECTORY|O_CLOEXEC);
    require(fd >= 0, @"Cannot open filesystem root");
    @try {
        for (NSString *component in path.pathComponents) {
            if ([component isEqual:@"/"]) continue;
            require(![component isEqual:@".."] && ![component isEqual:@"."], @"Invalid path component");
            BOOL created = NO;
            if (create) {
                created = mkdirat(fd, component.fileSystemRepresentation, mode) == 0;
                require(created || errno == EEXIST, @"Cannot create protected directory");
            }
            int next = openat(fd, component.fileSystemRepresentation, O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
            require(next >= 0, @"Unsafe or missing installation directory"); close(fd); fd = next;
            struct stat st; require(!fstat(fd, &st), @"Cannot inspect directory");
            BOOL applications = [path isEqual:@"/Applications"] && [component isEqual:@"Applications"];
            require(st.st_uid == 0 && !(st.st_mode & 0002) &&
                (!(st.st_mode & 0020) || (applications && st.st_gid == 80)), @"Untrusted installation directory owner/mode");
            if (created) require(!fchmod(fd, mode), @"Cannot set protected directory mode");
        }
        if (create) {
            struct stat st; require(!fstat(fd, &st) && (st.st_mode&0777) == mode,
                @"Existing protected directory has an unexpected mode");
        }
        return fd;
    } @catch (id error) { close(fd); @throw error; }
}

static NSData *readProtected(NSString *path, mode_t mode) {
    int parent = directory(path.stringByDeletingLastPathComponent, NO, 0);
    int fd = openat(parent, path.lastPathComponent.fileSystemRepresentation, O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC);
    close(parent); require(fd >= 0, @"Cannot read protected file");
    struct stat st;
    BOOL valid = !fstat(fd, &st) && S_ISREG(st.st_mode) && st.st_uid == 0 && st.st_nlink == 1 &&
        (st.st_mode & 0777) == mode && st.st_size > 0 && st.st_size <= 32768;
    if (!valid) { close(fd); require(NO, @"Unsafe protected file metadata"); }
    NSFileHandle *handle = [[NSFileHandle alloc] initWithFileDescriptor:fd closeOnDealloc:YES];
    NSData *data = [handle readDataToEndOfFile]; require(data.length == (NSUInteger)st.st_size, @"Protected file changed");
    return data;
}

static id readPlist(NSString *path, mode_t mode) {
    return [NSPropertyListSerialization propertyListWithData:readProtected(path, mode) options:0 format:NULL error:NULL];
}

static void writeProtected(NSString *path, NSData *data, mode_t mode) {
    if (exists(path)) (void)readProtected(path, mode);
    int parent = directory(path.stringByDeletingLastPathComponent, NO, 0);
    NSString *temporary = [@".plank-" stringByAppendingString:NSUUID.UUID.UUIDString];
    int fd = openat(parent, temporary.UTF8String, O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC, mode);
    if (fd < 0) { close(parent); require(NO, @"Cannot stage protected file"); }
    BOOL ok = !fchmod(fd, mode); size_t count = 0;
    while (ok && count < data.length) {
        ssize_t n = write(fd, (const char *)data.bytes + count, data.length-count);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) { ok = NO; break; } count += (size_t)n;
    }
    ok = ok && !fsync(fd); close(fd);
    if (ok) ok = !renameat(parent, temporary.UTF8String, parent, path.lastPathComponent.fileSystemRepresentation);
    if (!ok) unlinkat(parent, temporary.UTF8String, 0);
    close(parent); require(ok, @"Cannot publish protected file");
}

static void writePlist(NSString *path, id value, mode_t mode) {
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:value format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL];
    require(data != nil, @"Cannot serialize configuration"); writeProtected(path, data, mode);
}

static void verifyApp(NSString *path, BOOL development) {
    struct stat st;
    require(!lstat(path.fileSystemRepresentation, &st) && S_ISDIR(st.st_mode) && st.st_uid == 0 && !(st.st_mode & 0022),
        @"Existing app must be a protected root-owned directory");
    SecStaticCodeRef code = NULL; SecRequirementRef requirement = NULL;
    NSString *expression = PLANKInstallerRequirement(@PLANK_INSTALLER_TEAM, development);
    OSStatus result = SecStaticCodeCreateWithPath((__bridge CFURLRef)[NSURL fileURLWithPath:path], kSecCSDefaultFlags, &code);
    if (!result) result = SecRequirementCreateWithString((__bridge CFStringRef)expression, kSecCSDefaultFlags, &requirement);
    if (!result) result = SecStaticCodeCheckValidity(code, kSecCSStrictValidate|kSecCSCheckAllArchitectures, requirement);
    if (requirement) CFRelease(requirement); if (code) CFRelease(code);
    require(result == errSecSuccess, @"Host signature/product/team mismatch; existing installation preserved");
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfURL:[NSURL fileURLWithPath:[path stringByAppendingPathComponent:@"Contents/Info.plist"]] error:NULL];
    require(PLANKInstallerVersionValid(info[@"PLANKVersion"]), @"Invalid PLANK version");
    if (!development) require([info[@"PLANKVersion"] isEqual:@PLANK_INSTALLER_VERSION], @"Installed payload version mismatch");
}

static NSDictionary *jobPaths(void) {
    return @{Machine:[@"/Library/LaunchDaemons/" stringByAppendingFormat:@"%@.plist", Machine],
        Desktop:[@"/Library/LaunchAgents/" stringByAppendingFormat:@"%@.plist", Desktop],
        SignIn:[@"/Library/LaunchAgents/" stringByAppendingFormat:@"%@.plist", SignIn]};
}

static void verifyJobs(void) {
    NSDictionary *paths = jobPaths();
    for (NSString *label in paths) if (exists(paths[label])) {
        id data = readPlist(paths[label], 0644);
        NSString *role = [label isEqual:Machine] ? @"--machine" : ([label isEqual:Desktop] ? @"--desktop" : @"--sign-in");
        require([data isKindOfClass:NSDictionary.class] && [data[@"Label"] isEqual:label] &&
            [data[@"ProgramArguments"] isEqual:@[Executable, role, Machine]], @"Unrelated launchd entry; refusing replacement");
    }
}

static NSArray<NSString *> *guiDomains(void) {
    NSMutableSet *uids = [NSMutableSet set]; setpwent(); struct passwd *account;
    while ((account = getpwent())) if (account->pw_uid) [uids addObject:@(account->pw_uid)]; endpwent();
    NSMutableArray *domains = [NSMutableArray array];
    for (NSNumber *uid in uids) {
        NSString *domain = [@"gui/" stringByAppendingString:uid.stringValue]; int status;
        NSString *output = run(@"/bin/launchctl", @[@"print", domain], NO, &status);
        if (!status) [domains addObject:domain];
        else require([output containsString:@"Could not find domain for"] ||
            [output containsString:@"125: Domain does not support specified action"], @"Cannot inspect graphical domain");
    }
    return domains;
}

static BOOL alive(pid_t pid) {
#ifdef PLANK_INSTALLER_UNIT_TEST
    if (testAlive) return testAlive(pid);
#endif
    if (!kill(pid, 0)) return YES;
    require(errno == ESRCH, @"Cannot inspect worker process"); return NO;
}

static void stopJob(NSString *job) {
    int status; NSString *output = run(@"/bin/launchctl", @[@"print", job], NO, &status);
    if (status) { require(PLANKInstallerMissingJob(output, job), @"Cannot inspect launchd job"); return; }
    NSRegularExpression *pidPattern = [NSRegularExpression regularExpressionWithPattern:@"(?m)^\\s*pid = ([1-9][0-9]*)$" options:0 error:NULL];
    NSMutableSet *pids = [NSMutableSet set];
    for (NSTextCheckingResult *match in [pidPattern matchesInString:output options:0 range:NSMakeRange(0, output.length)])
        [pids addObject:@([[output substringWithRange:[match rangeAtIndex:1]] intValue])];
    run(@"/bin/launchctl", @[@"bootout", job], NO, NULL);
    NSTimeInterval deadline = now() + 20;
    do {
        output = run(@"/bin/launchctl", @[@"print", job], NO, &status);
        if (status) require(PLANKInstallerMissingJob(output, job), @"Cannot confirm job removal");
        else for (NSTextCheckingResult *match in [pidPattern matchesInString:output options:0 range:NSMakeRange(0, output.length)])
            [pids addObject:@([[output substringWithRange:[match rangeAtIndex:1]] intValue])];
        for (NSNumber *pid in pids.allObjects) if (!alive(pid.intValue)) [pids removeObject:pid];
        if (status && !pids.count) return;
        usleep(100000);
    } while (now() < deadline);
    require(NO, @"Timed out draining Host; no forced termination or app replacement");
}

static uid_t consoleUID(void) {
    struct stat st; require(!stat("/dev/console", &st), @"Cannot determine console owner"); return st.st_uid;
}

static void stopRoles(void) {
    if (!consoleUID()) stopJob([@"loginwindow/" stringByAppendingString:SignIn]);
    for (NSString *domain in guiDomains()) stopJob([domain stringByAppendingFormat:@"/%@", Desktop]);
    // Inactive LoginWindow is not inspectable. Prove its root worker retired
    // before stopping the coordinator, as in the qualified development path.
    NSString *processes = run(@"/bin/ps", @[@"-ax", @"-o", @"pid=", @"-o", @"uid=", @"-o", @"command="], YES, NULL);
    NSMutableSet *pids = [NSMutableSet set];
    for (NSString *line in [processes componentsSeparatedByString:@"\n"]) {
        NSScanner *scanner = [NSScanner scannerWithString:line]; int pid, uid;
        if (![scanner scanInt:&pid] || ![scanner scanInt:&uid] || uid || pid <= 0) continue;
        NSString *command = [[line substringFromIndex:scanner.scanLocation] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if ([command hasPrefix:[Executable stringByAppendingString:@" --sign-in "]] ||
            [command hasPrefix:[Executable stringByAppendingString:@" --graphical "]]) [pids addObject:@(pid)];
    }
    NSTimeInterval deadline = now() + 20;
    while (pids.count) {
        for (NSNumber *pid in pids.allObjects) if (!alive(pid.intValue)) [pids removeObject:pid];
        require(!pids.count || now() < deadline, @"Root graphical worker still retiring");
        if (pids.count) usleep(100000);
    }
    stopJob([@"system/" stringByAppendingString:Machine]);
}

static void checkIdentity(NSString *path) {
    int fd = directory(path, NO, 0); struct stat st;
    BOOL mode = !fstat(fd, &st) && (st.st_mode & 0777) == 0700; close(fd);
    require(mode, @"Private identity directory must be root-only");
    for (NSString *name in @[@"cert.pem", @"key.pem", @"cert.der", @"key.der"])
        (void)readProtected([path stringByAppendingPathComponent:name], 0600);
}

static void preflight(void) {
    struct utsname machine; require(!uname(&machine) && !strcmp(machine.machine, "arm64"), @"Apple Silicon required");
    require(NSProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27, @"macOS 27 or newer required");
    require([run(@"/usr/bin/fdesetup", @[@"status"], YES, NULL) containsString:@"FileVault is Off."],
        @"Disable FileVault before installing a Host that must be available at boot");
    close(directory(@"/Applications", NO, 0));
    close(directory(@"/Library/LaunchDaemons", NO, 0)); close(directory(@"/Library/LaunchAgents", NO, 0));
    verifyJobs();
    if (exists(App)) verifyApp(App, YES); // deliberate, same-team development transition
    if (exists(State)) {
        close(directory(State, NO, 0));
        NSString *config = [State stringByAppendingPathComponent:@"host.plist"];
        if (exists(config)) require(PLANKInstallerConfigValid(readPlist(config, 0644)), @"Invalid existing Host configuration");
        NSString *identity = [State stringByAppendingPathComponent:@"SignIn"];
        if (exists(identity)) checkIdentity(identity);
    }
}

static void createIdentity(void) {
    NSString *identity = [State stringByAppendingPathComponent:@"SignIn"];
    if (exists(identity)) { checkIdentity(identity); return; }
    NSString *stage = [InstallerState stringByAppendingPathComponent:[@"identity-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    close(directory(stage, YES, 0700));
    NSString *(^file)(NSString *) = ^NSString *(NSString *name) { return [stage stringByAppendingPathComponent:name]; };
    // umask0077 is set before commands. Files are private from creation.
    run(@"/usr/bin/openssl", @[@"req", @"-x509", @"-newkey", @"rsa:3072", @"-nodes", @"-sha256", @"-days", @"365",
        @"-subj", @"/CN=PLANK Host", @"-addext", @"subjectAltName=DNS:plank-host", @"-keyout", file(@"initial.pem"), @"-out", file(@"cert.pem")], YES, NULL);
    run(@"/usr/bin/openssl", @[@"rsa", @"-in", file(@"initial.pem"), @"-out", file(@"key.pem")], YES, NULL);
    run(@"/usr/bin/openssl", @[@"rsa", @"-in", file(@"key.pem"), @"-outform", @"DER", @"-out", file(@"key.der")], YES, NULL);
    run(@"/usr/bin/openssl", @[@"x509", @"-in", file(@"cert.pem"), @"-outform", @"DER", @"-out", file(@"cert.der")], YES, NULL);
    require(!unlink(file(@"initial.pem").fileSystemRepresentation), @"Cannot retire initial private key"); checkIdentity(stage);
    require(!renamex_np(stage.fileSystemRepresentation, identity.fileSystemRepresentation, RENAME_EXCL), @"Cannot publish identity without overwrite");
}

static NSDictionary *jobDefinitions(void) {
    NSString *logs = @"/Library/Logs/PLANK";
    return @{Machine:@{@"Label":Machine, @"ProgramArguments":@[Executable,@"--machine",Machine],
            @"MachServices":@{Machine:@YES}, @"RunAtLoad":@YES,
            @"StandardOutPath":[logs stringByAppendingPathComponent:@"host-machine.log"],
            @"StandardErrorPath":[logs stringByAppendingPathComponent:@"host-machine.log"]},
        Desktop:@{@"Label":Desktop, @"ProgramArguments":@[Executable,@"--desktop",Machine],
            @"RunAtLoad":@YES, @"KeepAlive":@YES, @"ThrottleInterval":@2,
            @"LimitLoadToSessionType":@"Aqua", @"ProcessType":@"Interactive",
            @"StandardOutPath":@"/dev/null", @"StandardErrorPath":@"/dev/null", @"Umask":@077},
        SignIn:@{@"Label":SignIn, @"ProgramArguments":@[Executable,@"--sign-in",Machine],
            @"RunAtLoad":@YES, @"KeepAlive":@YES, @"ThrottleInterval":@2,
            @"LimitLoadToSessionType":@"LoginWindow", @"ProcessType":@"Interactive",
            @"StandardOutPath":[logs stringByAppendingPathComponent:@"host-sign-in.log"],
            @"StandardErrorPath":[logs stringByAppendingPathComponent:@"host-sign-in.log"]}};
}

static void startRoles(void) {
    NSDictionary *paths = jobPaths();
    run(@"/bin/launchctl", @[@"bootstrap", @"system", paths[Machine]], YES, NULL);
    for (NSString *domain in guiDomains()) run(@"/bin/launchctl", @[@"bootstrap", domain, paths[Desktop]], YES, NULL);
    if (!consoleUID()) run(@"/bin/launchctl", @[@"bootstrap", @"loginwindow", paths[SignIn]], YES, NULL);
}

static void prepare(void) {
    preflight();
    NSString *transaction = [InstallerState stringByAppendingPathComponent:@"transaction.plist"];
    require(!exists(transaction), @"An earlier installation is incomplete. Preserve its recovery copy before retrying.");
    close(directory(State, YES, 0755)); close(directory(InstallerState, YES, 0700));
    uid_t owner = consoleUID(); stopRoles();
    require(consoleUID() == owner, @"Console changed during shutdown; app replacement cancelled");
    NSString *backup = @"";
    if (exists(App)) {
        NSString *container = [InstallerState stringByAppendingPathComponent:[@"previous-" stringByAppendingString:NSUUID.UUID.UUIDString]];
        close(directory(container, YES, 0700)); backup = [container stringByAppendingPathComponent:@"PLANK Host.app"];
        run(@"/usr/bin/ditto", @[App, backup], YES, NULL); verifyApp(backup, YES);
        fprintf(stdout, "Previous Host retained at %s\n", backup.fileSystemRepresentation);
    }
    writePlist(transaction, @{@"Backup":backup, @"Version":@PLANK_INSTALLER_VERSION}, 0600);
}

static void finish(void) {
    verifyApp(App, NO); verifyJobs();
    NSString *transaction = [InstallerState stringByAppendingPathComponent:@"transaction.plist"];
    id saved = readPlist(transaction, 0600);
    require([saved isKindOfClass:NSDictionary.class] && [saved[@"Version"] isEqual:@PLANK_INSTALLER_VERSION], @"Missing install transaction");
    NSString *config = [State stringByAppendingPathComponent:@"host.plist"];
    if (!exists(config)) writePlist(config, @{@"Address":@"0.0.0.0", @"Port":@28989,
        @"Name":@"PLANK Mac Host", @"UUID":NSUUID.UUID.UUIDString}, 0644);
    require(PLANKInstallerConfigValid(readPlist(config, 0644)), @"Invalid existing configuration"); createIdentity();
    NSString *logs = @"/Library/Logs/PLANK"; close(directory(logs, YES, 0700));
    for (NSString *name in @[@"host-machine.log", @"host-sign-in.log"]) {
        int parent = directory(logs, NO, 0);
        int fd = openat(parent, name.UTF8String, O_WRONLY|O_APPEND|O_CREAT|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC, 0600);
        close(parent); struct stat st;
        BOOL safe = fd >= 0 && !fstat(fd, &st) && S_ISREG(st.st_mode) && st.st_uid == 0 && st.st_nlink == 1 && (st.st_mode&0777) == 0600;
        if (fd >= 0) close(fd); require(safe, @"Unsafe product log file");
    }
    NSDictionary *definitions = jobDefinitions(), *paths = jobPaths();
    for (NSString *label in paths) writePlist(paths[label], definitions[label], 0644);
    startRoles();
    require(!unlink(transaction.fileSystemRepresentation), @"Cannot finalize install transaction");
    puts("PLANK Host installed for LoginWindow and all Aqua users. Configuration/certificates preserved; privacy permissions were not modified.");
}

static void recover(void) {
    NSString *transaction = [InstallerState stringByAppendingPathComponent:@"transaction.plist"];
    if (!exists(transaction)) return;
    id saved = readPlist(transaction, 0600);
    require([saved isKindOfClass:NSDictionary.class] && PLANKInstallerVersionValid(saved[@"Version"]) &&
        [saved[@"Backup"] isKindOfClass:NSString.class], @"Invalid recovery transaction");
    NSString *backup = saved[@"Backup"];
    if (backup.length) {
        NSString *container = backup.stringByDeletingLastPathComponent;
        require([container.stringByDeletingLastPathComponent isEqual:InstallerState] &&
            [container.lastPathComponent hasPrefix:@"previous-"] && [backup.lastPathComponent isEqual:@"PLANK Host.app"],
            @"Recovery path outside protected installer state");
        close(directory(container, NO, 0)); verifyApp(backup, YES);
    }
    verifyJobs(); stopRoles();
    if (exists(App)) {
        // Retain even an interrupted/partially extracted payload, never erase it.
        struct stat st; require(!lstat(App.fileSystemRepresentation, &st) && S_ISDIR(st.st_mode) &&
            st.st_uid == 0 && !(st.st_mode&0022), @"Unsafe interrupted app path");
        NSString *failed = [InstallerState stringByAppendingPathComponent:[@"failed-" stringByAppendingString:NSUUID.UUID.UUIDString]];
        close(directory(failed, YES, 0700));
        require(!renamex_np(App.fileSystemRepresentation, [failed stringByAppendingPathComponent:@"PLANK Host.app"].fileSystemRepresentation, RENAME_EXCL),
            @"Cannot retain interrupted payload");
    }
    if (backup.length) { run(@"/usr/bin/ditto", @[backup, App], YES, NULL); verifyApp(App, YES); startRoles(); }
    else for (NSString *path in jobPaths().allValues) if (exists(path))
        require(!unlink(path.fileSystemRepresentation), @"Cannot remove incomplete first-install startup entry");
    require(!unlink(transaction.fileSystemRepresentation), @"Cannot complete recovery");
    puts("Previous installation state restored; interrupted files retained for diagnosis.");
}

static void uninstall(void) {
    close(directory(@"/Applications", NO, 0)); verifyJobs();
    if (exists(App)) verifyApp(App, YES);
    stopRoles();
    for (NSString *path in jobPaths().allValues) if (exists(path)) require(!unlink(path.fileSystemRepresentation), @"Cannot remove Host startup entry");
    if (exists(App)) {
        close(directory(InstallerState, YES, 0700));
        NSString *container = [InstallerState stringByAppendingPathComponent:[@"uninstalled-" stringByAppendingString:NSUUID.UUID.UUIDString]];
        close(directory(container, YES, 0700));
        NSString *backup = [container stringByAppendingPathComponent:@"PLANK Host.app"];
        require(!renamex_np(App.fileSystemRepresentation, backup.fileSystemRepresentation, RENAME_EXCL), @"Cannot retain uninstalled app");
        fprintf(stdout, "Application retained at %s\n", backup.fileSystemRepresentation);
    }
    puts("PLANK Host removed. Settings, identities, logs and macOS permissions preserved. No reboot required.");
}

#ifndef PLANK_INSTALLER_UNIT_TEST
int main(int argc, const char **argv) {
    @autoreleasepool { @try {
        require(argc == 3 && !strcmp(argv[2], "/"), @"Installer supports only the running system volume");
        require(getuid() == 0 && geteuid() == 0, @"Run through macOS Installer with administrator approval");
        struct rlimit noCore = {0, 0}; require(!setrlimit(RLIMIT_CORE, &noCore), @"Cannot disable core dumps");
        umask(0077);
        if (!strcmp(argv[1], "preflight")) preflight();
        else if (!strcmp(argv[1], "prepare")) prepare();
        else if (!strcmp(argv[1], "finish")) finish();
        else if (!strcmp(argv[1], "recover")) recover();
        else if (!strcmp(argv[1], "uninstall")) uninstall();
        else require(NO, @"Unsupported installer operation");
        return 0;
    } @catch (NSException *error) { fprintf(stderr, "PLANK installation stopped: %s\n", error.reason.UTF8String); return 1; } }
}
#endif
