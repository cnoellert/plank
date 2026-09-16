// Standalone AppKit geometry experiment. Not linked into either product.
#import <AppKit/AppKit.h>
#include <fcntl.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static FILE *probeLog;
static NSDateFormatter *clockFormat;

static void Record(NSString *message)
{
    if (probeLog) {
        fprintf(probeLog, "%s %s\n", [[clockFormat stringFromDate:NSDate.date] UTF8String],
                message.UTF8String);
        fflush(probeLog);
    }
}

typedef NS_ENUM(NSInteger, ProbeMode) {
    Stock, ContentSize, ContentAndConstraint, Animation, AnimationAndConstraint
};

@interface ProbeWindow : NSWindow
@property BOOL fullPanelConstraint;
@property BOOL fullscreenIntent;
@end

@implementation ProbeWindow
- (NSRect)constrainFrameRect:(NSRect)frame toScreen:(NSScreen *)screen
{
    NSRect normal = [super constrainFrameRect:frame toScreen:screen];
    BOOL bypass = self.fullPanelConstraint && self.fullscreenIntent;
    Record([NSString stringWithFormat:@"constraint proposed=%@ normal=%@ bypass=%d",
            NSStringFromRect(frame), NSStringFromRect(normal), bypass]);
    return bypass ? frame : normal;
}
@end

@interface ProbeView : NSView
@end
@implementation ProbeView
- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    [[NSColor colorWithSRGBRed:0.04 green:0.28 blue:0.48 alpha:1] setFill];
    NSRectFill(self.bounds);
    // Edge markers must reach the visible panel edges, not just a larger
    // reported frame. The camera housing itself naturally obscures pixels.
    [[NSColor systemYellowColor] setFill];
    NSRectFill(NSMakeRect(0, NSMaxY(self.bounds) - 8, self.bounds.size.width, 8));
    [[NSColor systemGreenColor] setFill];
    NSRectFill(NSMakeRect(0, 0, 8, self.bounds.size.height));
    [[NSColor systemPinkColor] setFill];
    NSRectFill(NSMakeRect(NSMaxX(self.bounds) - 8, 0, 8, self.bounds.size.height));
    [[NSColor systemOrangeColor] setFill];
    NSRectFill(NSMakeRect(0, 0, self.bounds.size.width, 8));
}
@end

@interface ProbeController : NSObject <NSApplicationDelegate, NSWindowDelegate>
@property(strong) ProbeWindow *window;
@property(strong) NSPopUpButton *modes;
@property(strong) NSButton *toggle;
@property(strong) NSTextField *status;
@property(strong) NSTimer *sampler;
@property NSRect savedFrame;
@property BOOL transitioning;
@property(copy) NSString *lastSample;
@property(copy) NSString *logPath;
- (void)snapshot:(NSString *)reason;
@end

@implementation ProbeController
- (BOOL)customAnimation
{
    return self.modes.indexOfSelectedItem >= Animation;
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    (void)notification;
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"PLANKVersion"];
    Record([NSString stringWithFormat:@"probe=%@ os=%@", version,
            NSProcessInfo.processInfo.operatingSystemVersionString]);
    NSMenu *menu = [NSMenu new];
    NSMenuItem *applicationItem = [NSMenuItem new];
    [menu addItem:applicationItem];
    NSMenu *applicationMenu = [NSMenu new];
    [applicationMenu addItemWithTitle:@"Quit Fullscreen Probe" action:@selector(terminate:) keyEquivalent:@"q"];
    applicationItem.submenu = applicationMenu;
    NSApp.mainMenu = menu;
    self.window = [[ProbeWindow alloc] initWithContentRect:NSMakeRect(0, 0, 900, 560)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                  NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    self.window.releasedWhenClosed = NO;
    self.window.title = [@"PLANK Fullscreen Probe " stringByAppendingString:version];
    self.window.minSize = NSMakeSize(800, 520);
    self.window.collectionBehavior = NSWindowCollectionBehaviorFullScreenPrimary;
    self.window.delegate = self;
    self.window.contentView = [[ProbeView alloc] initWithFrame:NSMakeRect(0, 0, 900, 560)];
    NSTextField *title = [NSTextField labelWithString:self.window.title];
    title.font = [NSFont boldSystemFontOfSize:22];
    NSTextField *instructions = [NSTextField wrappingLabelWithString:
        @"Select a mode, then Enter Fullscreen. Swipe away and back.\n"
         "Check the colored edges, including yellow beside the camera notch.\n"
         "Press Escape to return; choose the next mode and repeat.\n"
         "No network, capture, input forwarding or system settings are used."];
    self.modes = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.modes addItemsWithTitles:@[@"1 — Standard native fullscreen",
        @"2 — Full-size content request (.117 approach)",
        @"3 — Full-size request + frame-constraint override",
        @"4 — Custom animation only",
        @"5 — Custom animation + frame-constraint override"]];
    self.modes.target = self;
    self.modes.action = @selector(modeChanged:);
    self.toggle = [NSButton buttonWithTitle:@"Enter Fullscreen" target:self action:@selector(toggleFullscreen:)];
    NSButton *logs = [NSButton buttonWithTitle:@"Show Log in Finder" target:self action:@selector(showLog:)];
    NSButton *quit = [NSButton buttonWithTitle:@"Quit" target:NSApp action:@selector(terminate:)];
    NSStackView *buttons = [NSStackView stackViewWithViews:@[self.toggle, logs, quit]];
    buttons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttons.spacing = 12;
    self.status = [NSTextField wrappingLabelWithString:@"Waiting for geometry"];
    self.status.font = [NSFont monospacedSystemFontOfSize:14 weight:NSFontWeightRegular];
    NSStackView *stack = [NSStackView stackViewWithViews:@[title, instructions, self.modes, buttons, self.status]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 22;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.window.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.centerXAnchor constraintEqualToAnchor:self.window.contentView.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:self.window.contentView.centerYAnchor],
        [stack.widthAnchor constraintEqualToConstant:720],
        [instructions.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [self.status.widthAnchor constraintEqualToAnchor:stack.widthAnchor]]];
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activate];
    // Measurement only: never resize a window from this timer.
    __weak ProbeController *weakSelf = self;
    self.sampler = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) {
        (void)timer;
        [weakSelf snapshot:@"sample"];
    }];
    [self modeChanged:nil];
}
- (void)modeChanged:(id)sender
{
    (void)sender;
    ProbeMode mode = self.modes.indexOfSelectedItem;
    self.window.fullPanelConstraint = mode == ContentAndConstraint || mode == AnimationAndConstraint;
    Record([@"mode=" stringByAppendingString:self.modes.titleOfSelectedItem]);
    [self snapshot:@"mode-selected"];
}
- (void)toggleFullscreen:(id)sender
{
    if (!self.transitioning) [self.window toggleFullScreen:sender];
}
- (void)showLog:(id)sender
{
    (void)sender;
    [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:self.logPath]]];
}
- (void)snapshot:(NSString *)reason
{
    if (!self.window.screen || !self.window.contentView) return;
    NSRect panel = self.window.screen.frame;
    NSRect frame = self.window.frame;
    NSRect content = self.window.contentView.bounds;
    NSRect pixels = [self.window.contentView convertRectToBacking:content];
    BOOL native = (self.window.styleMask & NSWindowStyleMaskFullScreen) != 0;
    BOOL fullPanel = fabs(frame.origin.x-panel.origin.x) < 0.5 &&
        fabs(frame.origin.y-panel.origin.y) < 0.5 &&
        fabs(frame.size.width-panel.size.width) < 0.5 &&
        fabs(frame.size.height-panel.size.height) < 0.5;
    NSString *sample = [NSString stringWithFormat:
        @"mode=%ld native=%d transition=%d active=%d visible=%d occlusion-visible=%d\n"
         "panel=%@ frame=%@\ncontent=%@ backing=%@ scale=%.2f notch=%.1f frame-matches-panel=%d",
        (long)self.modes.indexOfSelectedItem + 1, native, self.transitioning,
        NSApp.active, self.window.visible,
        (self.window.occlusionState & NSWindowOcclusionStateVisible) != 0,
        NSStringFromRect(panel), NSStringFromRect(frame), NSStringFromRect(content),
        NSStringFromRect(pixels), self.window.backingScaleFactor,
        self.window.screen.safeAreaInsets.top, fullPanel];
    self.status.stringValue = sample;
    if (![reason isEqualToString:@"sample"] || ![sample isEqualToString:self.lastSample]) {
        Record([NSString stringWithFormat:@"event=%@ %@", reason,
            [sample stringByReplacingOccurrencesOfString:@"\n" withString:@" "]]);
        self.lastSample = sample;
    }
}
- (void)windowWillEnterFullScreen:(NSNotification *)notification
{
    (void)notification;
    self.savedFrame = self.window.frame;
    self.window.fullscreenIntent = YES;
    self.transitioning = YES;
    self.modes.enabled = NO;
    self.toggle.enabled = NO;
    [self snapshot:@"will-enter"];
}
- (void)windowDidEnterFullScreen:(NSNotification *)notification
{
    (void)notification;
    self.transitioning = NO;
    self.toggle.enabled = YES;
    self.toggle.title = @"Exit Fullscreen (Escape)";
    self.toggle.keyEquivalent = @"\033";
    [self snapshot:@"did-enter"];
}
- (void)windowWillExitFullScreen:(NSNotification *)notification
{
    (void)notification;
    self.transitioning = YES;
    self.toggle.enabled = NO;
    [self snapshot:@"will-exit"];
}
- (void)windowDidExitFullScreen:(NSNotification *)notification
{
    (void)notification;
    self.window.fullscreenIntent = NO;
    self.transitioning = NO;
    self.modes.enabled = YES;
    self.toggle.enabled = YES;
    self.toggle.title = @"Enter Fullscreen";
    self.toggle.keyEquivalent = @"";
    [self snapshot:@"did-exit"];
}
- (void)windowDidFailToEnterFullScreen:(NSWindow *)window
{
    (void)window;
    [self windowDidExitFullScreen:[NSNotification notificationWithName:NSWindowDidExitFullScreenNotification object:window]];
    [self snapshot:@"failed-enter"];
}
- (void)windowDidFailToExitFullScreen:(NSWindow *)window
{
    (void)window;
    [self windowDidEnterFullScreen:[NSNotification notificationWithName:NSWindowDidEnterFullScreenNotification object:window]];
    [self snapshot:@"failed-exit"];
}
- (NSSize)window:(NSWindow *)window willUseFullScreenContentSize:(NSSize)size
{
    ProbeMode mode = self.modes.indexOfSelectedItem;
    NSSize requested = (mode == ContentSize || mode == ContentAndConstraint) && window.screen
        ? window.screen.frame.size : size;
    Record([NSString stringWithFormat:@"content proposed=%@ requested=%@",
            NSStringFromSize(size), NSStringFromSize(requested)]);
    return requested;
}
- (NSArray<NSWindow *> *)customWindowsToEnterFullScreenForWindow:(NSWindow *)window
{
    return self.customAnimation ? @[window] : nil;
}
- (NSArray<NSWindow *> *)customWindowsToExitFullScreenForWindow:(NSWindow *)window
{
    return self.customAnimation ? @[window] : nil;
}
- (void)window:(NSWindow *)window startCustomAnimationToEnterFullScreenOnScreen:(NSScreen *)screen
    withDuration:(NSTimeInterval)duration
{
    Record([NSString stringWithFormat:@"custom-enter target=%@", NSStringFromRect(screen.frame)]);
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = duration;
        [[window animator] setFrame:screen.frame display:YES];
    } completionHandler:nil];
}
- (void)window:(NSWindow *)window startCustomAnimationToEnterFullScreenWithDuration:(NSTimeInterval)duration
{
    [self window:window startCustomAnimationToEnterFullScreenOnScreen:window.screen withDuration:duration];
}
- (void)window:(NSWindow *)window startCustomAnimationToExitFullScreenWithDuration:(NSTimeInterval)duration
{
    Record([NSString stringWithFormat:@"custom-exit target=%@", NSStringFromRect(self.savedFrame)]);
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = duration;
        [[window animator] setFrame:self.savedFrame display:YES];
    } completionHandler:nil];
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    (void)sender;
    return YES;
}
- (void)applicationWillTerminate:(NSNotification *)notification
{
    (void)notification;
    [self.sampler invalidate];
    Record(@"quit");
}
@end

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        if (argc == 2 && strcmp(argv[1], "--version") == 0) {
            puts([[NSBundle.mainBundle objectForInfoDictionaryKey:@"PLANKVersion"] UTF8String]);
            return 0;
        }
        NSString *directory = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/PLANK/FullscreenProbe"];
        NSError *error = nil;
        if (![NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES
            attributes:@{NSFilePosixPermissions:@0700} error:&error]) return 1;
        NSString *path = [directory stringByAppendingPathComponent:
            [NSString stringWithFormat:@"fullscreen-%@.log", NSUUID.UUID.UUIDString]];
        int fd = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
        if (fd < 0) return 1;
        probeLog = fdopen(fd, "w");
        if (!probeLog) { close(fd); return 1; }
        clockFormat = [NSDateFormatter new];
        clockFormat.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        clockFormat.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ";
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        // NSApplication does not own its delegate. Keep it alive through run(),
        // including optimized builds where the last assignment precedes run().
        __attribute__((objc_precise_lifetime)) ProbeController *controller = [ProbeController new];
        controller.logPath = path;
        NSApp.delegate = controller;
        [NSApp run];
        fclose(probeLog);
        probeLog = NULL;
    }
    return 0;
}
