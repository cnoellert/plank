// Read-only Mac Client feasibility probe. No report writes, exclusive opens,
// event injection, permission requests, serial collection or network transport.
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#import <IOKit/hid/IOHIDManager.h>
#import <IOKit/hid/IOHIDKeys.h>
#import <IOKit/hidsystem/IOHIDLib.h>
#import <mach/mach_error.h>
#include <signal.h>
#include <unistd.h>
#include <errno.h>

static volatile sig_atomic_t interrupted;
static void interruptProbe(int number) { (void)number; interrupted = 1; }

static BOOL parseNumber(const char *text, unsigned maximum, unsigned *number)
{
    char *end = NULL;
    errno = 0;
    unsigned long value = strtoul(text, &end, 10);
    if (errno || text[0] == '-' || end == text || *end || value > maximum) return NO;
    *number = (unsigned)value;
    return YES;
}

static id property(IOHIDDeviceRef device, CFStringRef key)
{
    return (__bridge id)IOHIDDeviceGetProperty(device, key);
}

static NSDictionary *resultInfo(IOReturn result)
{
    return @{ @"code": [NSString stringWithFormat:@"0x%08x", (unsigned)result],
              @"description": @(mach_error_string(result)),
              @"success": @(result == kIOReturnSuccess) };
}

static void emitJSON(NSDictionary *record)
{
    NSData *data = [NSJSONSerialization dataWithJSONObject:record options:NSJSONWritingSortedKeys error:nil];
    fwrite(data.bytes, 1, data.length, stdout);
    putchar('\n');
    fflush(stdout);
}

static NSString *descriptorHash(NSData *data)
{
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *text = [NSMutableString string];
    for (unsigned i = 0; i < sizeof(digest); ++i) [text appendFormat:@"%02x", digest[i]];
    return text;
}

static uint64_t registryID(IOHIDDeviceRef device)
{
    uint64_t value = 0;
    IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &value);
    return value;
}

static NSDictionary *usbGroup(IOHIDDeviceRef device)
{
    io_registry_entry_t entry = IOHIDDeviceGetService(device);
    IOObjectRetain(entry);
    NSMutableDictionary *group = [NSMutableDictionary dictionary];
    for (unsigned depth = 0; entry && depth < 16; ++depth) {
        NSNumber *number = CFBridgingRelease(IORegistryEntryCreateCFProperty(
            entry, CFSTR("bInterfaceNumber"), kCFAllocatorDefault, 0));
        if (number && !group[@"interface_number"]) group[@"interface_number"] = number;
        if (IOObjectConformsTo(entry, "IOUSBHostDevice") || IOObjectConformsTo(entry, "IOUSBDevice")) {
            uint64_t value = 0;
            IORegistryEntryGetRegistryEntryID(entry, &value);
            group[@"usb_parent_registry_id"] = @(value);
            break;
        }
        io_registry_entry_t parent = IO_OBJECT_NULL;
        IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent);
        IOObjectRelease(entry);
        entry = parent;
    }
    if (entry) IOObjectRelease(entry);
    return group;
}

static NSDictionary *reportInventory(IOHIDDeviceRef device)
{
    NSMutableDictionary *reports = [NSMutableDictionary dictionary];
    NSArray *elements = CFBridgingRelease(IOHIDDeviceCopyMatchingElements(device, NULL, 0));
    for (id item in elements) {
        IOHIDElementRef element = (__bridge IOHIDElementRef)item;
        IOHIDElementType type = IOHIDElementGetType(element);
        NSString *kind;
        if (type >= kIOHIDElementTypeInput_Misc && type <= kIOHIDElementTypeInput_ScanCodes) kind = @"input";
        else if (type == kIOHIDElementTypeOutput) kind = @"output";
        else if (type == kIOHIDElementTypeFeature) kind = @"feature";
        else continue;
        NSString *key = [NSString stringWithFormat:@"%@:%u", kind, IOHIDElementGetReportID(element)];
        NSMutableDictionary *report = reports[key];
        if (!report) {
            report = [@{ @"kind": kind, @"id": @(IOHIDElementGetReportID(element)),
                         @"element_count": @0, @"usage_pages": [NSMutableArray array] } mutableCopy];
            reports[key] = report;
        }
        report[@"element_count"] = @([report[@"element_count"] unsignedIntValue] + 1);
        NSMutableArray *pages = report[@"usage_pages"];
        NSNumber *page = @(IOHIDElementGetUsagePage(element));
        if (![pages containsObject:page]) [pages addObject:page];
    }
    return reports;
}

@interface ProbeDevice : NSObject
@property(nonatomic, assign) IOHIDDeviceRef device;
@property(nonatomic) NSMutableDictionary *record;
@property(nonatomic) NSMutableDictionary<NSString *, NSMutableDictionary *> *reports;
@property(nonatomic) NSMutableDictionary<NSString *, NSData *> *previous;
@property(nonatomic) NSMutableData *buffer;
@property(nonatomic) BOOL opened;
@end
@implementation ProbeDevice
@end

static void inputReport(void *context, IOReturn result, void *sender,
                        IOHIDReportType type, uint32_t reportID,
                        uint8_t *report, CFIndex length)
{
    (void)sender;
    ProbeDevice *probe = (__bridge ProbeDevice *)context;
    if (result != kIOReturnSuccess || length < 0 || length > (CFIndex)probe.buffer.length) {
        probe.record[@"callback_errors"] = @([probe.record[@"callback_errors"] unsignedIntValue] + 1);
        probe.record[@"last_callback_result"] = resultInfo(result);
        return;
    }
    NSString *key = [NSString stringWithFormat:@"%u:%u", type, reportID];
    NSMutableDictionary *stats = probe.reports[key];
    if (!stats) {
        stats = [@{ @"type": @(type), @"id": @(reportID), @"count": @0,
                    @"changed_reports": @0, @"minimum_length": @(length),
                    @"maximum_length": @(length), @"id_prefix_matches": @0 } mutableCopy];
        probe.reports[key] = stats;
    }
    stats[@"count"] = @([stats[@"count"] unsignedLongLongValue] + 1);
    stats[@"minimum_length"] = @(MIN(length, [stats[@"minimum_length"] longLongValue]));
    stats[@"maximum_length"] = @(MAX(length, [stats[@"maximum_length"] longLongValue]));
    if (reportID && length && report[0] == reportID) {
        stats[@"id_prefix_matches"] = @([stats[@"id_prefix_matches"] unsignedLongLongValue] + 1);
    }
    NSData *bytes = [NSData dataWithBytes:report length:(NSUInteger)length];
    if (probe.previous[key] && ![probe.previous[key] isEqualToData:bytes]) {
        stats[@"changed_reports"] = @([stats[@"changed_reports"] unsignedLongLongValue] + 1);
    }
    // One previous packet per report stays in memory only, for change counts.
    probe.previous[key] = bytes;
}

int main(int argc, const char **argv)
{
    @autoreleasepool {
        unsigned seconds = 0;
        int featureIndex = -1;
        unsigned featureID = 0;
        if (argc == 3 && strcmp(argv[1], "--watch") == 0) {
            if (!parseNumber(argv[2], 60, &seconds) || !seconds) return 2;
        } else if (argc == 4 && strcmp(argv[1], "--get-feature") == 0) {
            unsigned index;
            if (!parseNumber(argv[2], 15, &index) || !parseNumber(argv[3], 255, &featureID)) return 2;
            featureIndex = (int)index;
        } else if (argc != 1) {
            fprintf(stderr, "usage: macos-client-hid [--watch SECONDS(1..60) | --get-feature INDEX REPORT_ID]\n");
            return 2;
        }
        signal(SIGINT, interruptProbe);
        signal(SIGTERM, interruptProbe);
        IOHIDAccessType access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent);
        NSString *accessName = access == kIOHIDAccessTypeGranted ? @"granted" :
            access == kIOHIDAccessTypeDenied ? @"denied" : @"unknown";
        IOHIDManagerRef manager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDManagerOptionNone);
        if (!manager) return 1;
        NSDictionary *matching = @{ @kIOHIDVendorIDKey: @0x056a, @kIOHIDTransportKey: @"USB" };
        IOHIDManagerSetDeviceMatching(manager, (__bridge CFDictionaryRef)matching);
        CFSetRef devices = IOHIDManagerCopyDevices(manager);
        NSArray *ordered = devices ? [(__bridge NSSet *)devices allObjects] : @[];
        ordered = [ordered sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
            uint64_t x = registryID((__bridge IOHIDDeviceRef)a), y = registryID((__bridge IOHIDDeviceRef)b);
            return x < y ? NSOrderedAscending : x > y ? NSOrderedDescending : NSOrderedSame;
        }];
        NSMutableArray<ProbeDevice *> *probes = [NSMutableArray array];
        NSMutableArray *records = [NSMutableArray array];
        for (id item in ordered) {
            IOHIDDeviceRef device = (__bridge IOHIDDeviceRef)item;
            ProbeDevice *probe = [ProbeDevice new];
            probe.device = device;
            probe.reports = [NSMutableDictionary dictionary];
            probe.previous = [NSMutableDictionary dictionary];
            probe.record = [@{ @"index": @(probes.count), @"registry_id": @(registryID(device)),
                              @"usb_group": usbGroup(device), @"callback_errors": @0,
                              @"report_inventory": reportInventory(device) } mutableCopy];
            for (NSString *key in @[@kIOHIDProductKey, @kIOHIDVendorIDKey, @kIOHIDProductIDKey,
                                    @kIOHIDVersionNumberKey, @kIOHIDTransportKey,
                                    @kIOHIDPrimaryUsagePageKey, @kIOHIDPrimaryUsageKey,
                                    @kIOHIDMaxInputReportSizeKey, @kIOHIDMaxOutputReportSizeKey,
                                    @kIOHIDMaxFeatureReportSizeKey]) {
                id value = property(device, (__bridge CFStringRef)key);
                if ([value isKindOfClass:NSString.class] || [value isKindOfClass:NSNumber.class]) probe.record[key] = value;
            }
            NSData *descriptor = property(device, CFSTR(kIOHIDReportDescriptorKey));
            BOOL descriptorValid = [descriptor isKindOfClass:NSData.class] && descriptor.length > 0 && descriptor.length <= 4096;
            probe.record[@"descriptor_within_transport_limit"] = @(descriptorValid);
            if (descriptorValid) {
                probe.record[@"descriptor_length"] = @(descriptor.length);
                probe.record[@"descriptor_sha256"] = descriptorHash(descriptor);
            }
            if ((seconds || featureIndex == (int)probes.count) &&
                    access == kIOHIDAccessTypeGranted && descriptorValid && ordered.count <= 16) {
                IOReturn result = IOHIDDeviceOpen(device, kIOHIDOptionsTypeNone);
                probe.record[@"nonexclusive_open"] = resultInfo(result);
                if (result == kIOReturnSuccess) {
                    probe.opened = YES;
                    probe.buffer = [NSMutableData dataWithLength:4096];
                    if (seconds) {
                        IOHIDDeviceRegisterInputReportCallback(device, probe.buffer.mutableBytes,
                            (CFIndex)probe.buffer.length, inputReport, (__bridge void *)probe);
                        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
                    }
                }
            }
            [probes addObject:probe];
            [records addObject:probe.record];
        }
        NSMutableDictionary *summary = [@{ @"event": seconds ? @"capture_start" : featureIndex >= 0 ? @"feature_start" : @"inventory",
            @"listen_access": accessName, @"interfaces": records, @"requested_seconds": @(seconds),
            @"exclusive": @NO, @"report_writes": @NO, @"permission_requests": @NO,
            @"raw_report_payloads_recorded": @NO } mutableCopy];
        emitJSON(summary);
        BOOL opened = NO;
        for (ProbeDevice *probe in probes) opened |= probe.opened;
        CFAbsoluteTime started = CFAbsoluteTimeGetCurrent();
        BOOL featureSuccess = NO;
        if (featureIndex >= 0) {
            NSString *key = [NSString stringWithFormat:@"feature:%u", featureID];
            if ((NSUInteger)featureIndex >= probes.count ||
                    !probes[featureIndex].opened ||
                    !probes[featureIndex].record[@"report_inventory"][key]) {
                summary[@"feature_read"] = @{ @"error": @"Selected interface is unavailable or report is not declared" };
            } else {
                ProbeDevice *probe = probes[featureIndex];
                uint8_t *buffer = probe.buffer.mutableBytes;
                buffer[0] = (uint8_t)featureID;
                CFIndex length = (CFIndex)probe.buffer.length;
                // The synchronous API has no timeout argument. A process-level
                // watchdog bounds this one read; process exit closes its handles.
                alarm(5);
                IOReturn result = IOHIDDeviceGetReport(probe.device,
                    kIOHIDReportTypeFeature, featureID, buffer, &length);
                alarm(0);
                featureSuccess = result == kIOReturnSuccess;
                summary[@"feature_read"] = @{ @"index": @(featureIndex), @"id": @(featureID),
                    @"result": resultInfo(result), @"returned_length": @(length),
                    @"id_prefix_matches": @(featureSuccess && length > 0 && buffer[0] == featureID),
                    @"payload_recorded": @NO };
            }
        }
        while (opened && !interrupted && CFAbsoluteTimeGetCurrent() - started < seconds) {
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, true);
        }
        for (ProbeDevice *probe in probes) {
            if (probe.opened) {
                if (seconds) {
                    IOHIDDeviceRegisterInputReportCallback(probe.device, probe.buffer.mutableBytes,
                        (CFIndex)probe.buffer.length, NULL, NULL);
                    IOHIDDeviceUnscheduleFromRunLoop(probe.device, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
                }
                probe.record[@"close"] = resultInfo(IOHIDDeviceClose(probe.device, 0));
            }
            probe.record[@"observed_reports"] = probe.reports;
            [probe.previous removeAllObjects];
        }
        if (seconds || featureIndex >= 0) {
            summary[@"event"] = seconds ? @"capture_end" : @"feature_end";
            summary[@"elapsed_seconds"] = @(CFAbsoluteTimeGetCurrent() - started);
            summary[@"interrupted"] = @(interrupted != 0);
            emitJSON(summary);
        }
        if (devices) CFRelease(devices);
        CFRelease(manager);
        return records.count == 0 || (seconds && !opened) ||
            (featureIndex >= 0 && !featureSuccess) ? 1 : 0;
    }
}
