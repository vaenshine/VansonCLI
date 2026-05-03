/**
 * VCTraceManager -- lightweight runtime trace sessions for AI analysis
 */

#import "VCTraceManager.h"
#import "../Core/VCConfig.h"
#import "../Core/VCCapabilityManager.h"
#import "../Hook/VCHookManager.h"
#import "../Network/VCNetMonitor.h"
#import "../Network/VCNetRecord.h"
#import "../Network/VCURLProtocol.h"
#import "../Patches/VCHookItem.h"
#import "../Process/VCProcessInfo.h"
#import "../UIInspector/VCUIInspector.h"
#import "../AI/Security/VCPromptLeakGuard.h"
#import "../Runtime/VCValueReader.h"
#import <mach/mach.h>

static NSString *VCTraceSafeString(id value) {
    if ([value isKindOfClass:[NSString class]]) {
        return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        return [[(NSNumber *)value stringValue] copy];
    }
    return @"";
}

static BOOL VCTraceSafeBool(id value, BOOL fallbackValue) {
    if ([value respondsToSelector:@selector(boolValue)]) return [value boolValue];
    return fallbackValue;
}

static NSUInteger VCTraceSafeUnsigned(id value, NSUInteger fallbackValue, NSUInteger maxValue) {
    if ([value respondsToSelector:@selector(unsignedIntegerValue)]) {
        return MIN([value unsignedIntegerValue], maxValue);
    }
    return MIN(fallbackValue, maxValue);
}

static uintptr_t VCTraceSafeAddress(id value) {
    if ([value isKindOfClass:[NSNumber class]]) {
        return (uintptr_t)[(NSNumber *)value unsignedLongLongValue];
    }
    NSString *text = VCTraceSafeString(value);
    if (text.length == 0) return 0;
    return (uintptr_t)strtoull(text.UTF8String, NULL, 0);
}

static NSString *VCTraceHexAddress(uint64_t address) {
    return [NSString stringWithFormat:@"0x%llx", (unsigned long long)address];
}

static NSString *VCTraceTimestampString(NSTimeInterval timestamp) {
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:timestamp];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"HH:mm:ss.SSS";
    return [formatter stringFromDate:date];
}

static NSString *VCTraceMermaidAlias(NSString *label, NSMutableDictionary<NSString *, NSString *> *aliases) {
    NSString *safeLabel = VCTraceSafeString(label);
    if (safeLabel.length == 0) safeLabel = @"Node";
    NSString *existing = aliases[safeLabel];
    if (existing.length > 0) return existing;
    NSString *alias = [NSString stringWithFormat:@"N%lu", (unsigned long)aliases.count + 1];
    aliases[safeLabel] = alias;
    return alias;
}

static NSTimeInterval VCTraceEventSortTimestamp(NSDictionary *event) {
    id startedAt = event[@"startedAt"];
    if ([startedAt respondsToSelector:@selector(doubleValue)] && [startedAt doubleValue] > 0) {
        return [startedAt doubleValue];
    }
    id timestamp = event[@"timestamp"];
    if ([timestamp respondsToSelector:@selector(doubleValue)]) {
        return [timestamp doubleValue];
    }
    return 0;
}

static NSString *VCTraceEventKind(NSDictionary *event) {
    return VCTraceSafeString(event[@"kind"]).lowercaseString;
}

static NSString *VCTraceMethodDisplayName(NSDictionary *event) {
    NSString *className = VCTraceSafeString(event[@"className"]);
    NSString *selector = VCTraceSafeString(event[@"selector"]);
    NSString *prefix = [event[@"isClassMethod"] boolValue] ? @"+" : @"-";
    if (className.length == 0 || selector.length == 0) {
        return VCTraceSafeString(event[@"title"]);
    }
    return [NSString stringWithFormat:@"%@[%@ %@]", prefix, className, selector];
}

static NSString *VCTraceMermaidEscaped(NSString *value) {
    NSString *safeValue = VCTraceSafeString(value);
    safeValue = [safeValue stringByReplacingOccurrencesOfString:@"\"" withString:@"'"];
    safeValue = [safeValue stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    return safeValue;
}

static NSString *VCTraceRelatedInvocationID(NSDictionary *event) {
    NSString *invocationID = VCTraceSafeString(event[@"relatedInvocationID"]);
    if (invocationID.length > 0) return invocationID;
    return VCTraceSafeString(event[@"invocationID"]);
}

static NSString *VCTraceRelatedDisplayName(NSDictionary *event) {
    NSString *displayName = VCTraceSafeString(event[@"relatedDisplayName"]);
    if (displayName.length > 0) return displayName;
    return VCTraceMethodDisplayName(event);
}

static BOOL VCTraceStringEqualsFolded(NSString *lhs, NSString *rhs) {
    NSString *left = VCTraceSafeString(lhs);
    NSString *right = VCTraceSafeString(rhs);
    if (left.length == 0 || right.length == 0) return NO;
    return [left caseInsensitiveCompare:right] == NSOrderedSame;
}

static BOOL VCTraceStringContainsFolded(NSString *value, NSString *query) {
    NSString *source = VCTraceSafeString(value);
    NSString *needle = VCTraceSafeString(query);
    if (source.length == 0 || needle.length == 0) return NO;
    return [source rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static NSDictionary *VCTraceFrozenCallNode(NSDictionary *node);
static NSDictionary *VCTraceFrozenRelatedEvent(NSDictionary *event);

static NSArray<NSDictionary *> *VCTraceFrozenRelatedEvents(NSArray<NSDictionary *> *events) {
    NSMutableArray<NSDictionary *> *result = [NSMutableArray new];
    for (NSDictionary *event in events ?: @[]) {
        if (![event isKindOfClass:[NSDictionary class]]) continue;
        [result addObject:VCTraceFrozenRelatedEvent(event)];
    }
    return [result copy];
}

static NSDictionary *VCTraceFrozenRelatedEvent(NSDictionary *event) {
    return [event isKindOfClass:[NSDictionary class]] ? [event copy] : @{};
}

static NSArray<NSDictionary *> *VCTraceFrozenCallNodes(NSArray<NSDictionary *> *nodes) {
    NSMutableArray<NSDictionary *> *result = [NSMutableArray new];
    for (NSDictionary *node in nodes ?: @[]) {
        if (![node isKindOfClass:[NSDictionary class]]) continue;
        [result addObject:VCTraceFrozenCallNode(node)];
    }
    return [result copy];
}

static NSDictionary *VCTraceFrozenCallNode(NSDictionary *node) {
    NSMutableDictionary *copy = [node mutableCopy] ?: [NSMutableDictionary new];
    copy[@"relatedEvents"] = VCTraceFrozenRelatedEvents(node[@"relatedEvents"]);
    copy[@"children"] = VCTraceFrozenCallNodes(node[@"children"]);
    return [copy copy];
}

@interface VCTraceManager ()
@property (nonatomic, strong) NSMutableArray<NSMutableDictionary *> *sessions;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *eventsBySession;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSArray<VCHookItem *> *> *hooksBySession;
@property (nonatomic, copy) NSString *activeSessionID;
@end

@implementation VCTraceManager

+ (instancetype)shared {
    static VCTraceManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VCTraceManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _sessions = [NSMutableArray new];
        _eventsBySession = [NSMutableDictionary new];
        _hooksBySession = [NSMutableDictionary new];
        [self _ensureTraceDirectory];
        [self _loadState];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_handleHookInvocation:)
                                                     name:kVCHookManagerDidCaptureInvocationNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_handleNetworkRecord:)
                                                     name:kVCURLProtocolDidCaptureRecord
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_handleUISelection:)
                                                     name:kVCUIInspectorDidSelectViewNotification
                                                   object:nil];
    }
    return self;
}

- (VCMemRegion *)_memoryRegionContainingAddress:(uintptr_t)address {
    if (address == 0) return nil;
    for (VCMemRegion *region in [[VCProcessInfo shared] memoryRegions] ?: @[]) {
        if (address >= region.start && address < region.end) {
            return region;
        }
    }
    return nil;
}

- (NSDictionary *)_memoryRegionPayload:(VCMemRegion *)region {
    if (!region) return @{};
    return @{
        @"start": VCTraceHexAddress(region.start),
        @"end": VCTraceHexAddress(region.end),
        @"size": @(region.size),
        @"protection": region.protection ?: @"---"
    };
}

- (NSData *)_safeReadDataAtAddress:(uintptr_t)address length:(NSUInteger)length errorMessage:(NSString **)errorMessage {
    if (address == 0 || length == 0) {
        if (errorMessage) *errorMessage = @"A non-zero address and length are required.";
        return nil;
    }

    VCMemRegion *region = [self _memoryRegionContainingAddress:address];
    if (!region || [region.protection rangeOfString:@"r"].location == NSNotFound) {
        if (errorMessage) *errorMessage = [NSString stringWithFormat:@"Address %@ is not inside readable memory.", VCTraceHexAddress(address)];
        return nil;
    }
    if ((uint64_t)address + length > region.end) {
        if (errorMessage) *errorMessage = [NSString stringWithFormat:@"Address %@ plus %@ bytes crosses the current region boundary.", VCTraceHexAddress(address), @(length)];
        return nil;
    }

    NSMutableData *buffer = [NSMutableData dataWithLength:length];
    vm_size_t outSize = 0;
    kern_return_t kr = vm_read_overwrite(mach_task_self(),
                                         (vm_address_t)address,
                                         (vm_size_t)length,
                                         (vm_address_t)buffer.mutableBytes,
                                         &outSize);
    if (kr != KERN_SUCCESS || outSize == 0) {
        if (errorMessage) *errorMessage = [NSString stringWithFormat:@"vm_read_overwrite failed for %@ (kr=%d)", VCTraceHexAddress(address), kr];
        return nil;
    }

    if (outSize < length) {
        return [buffer subdataWithRange:NSMakeRange(0, (NSUInteger)outSize)];
    }
    return [buffer copy];
}

- (NSString *)_hexDumpStringForData:(NSData *)data startAddress:(uintptr_t)address {
    if (![data isKindOfClass:[NSData class]] || data.length == 0) return @"";
    NSMutableArray<NSString *> *lines = [NSMutableArray new];
    const unsigned char *bytes = (const unsigned char *)data.bytes;
    NSUInteger offset = 0;
    while (offset < data.length) {
        NSUInteger lineLength = MIN(16, data.length - offset);
        NSMutableString *hexPart = [NSMutableString new];
        NSMutableString *asciiPart = [NSMutableString new];
        for (NSUInteger idx = 0; idx < 16; idx++) {
            if (idx < lineLength) {
                unsigned char byte = bytes[offset + idx];
                [hexPart appendFormat:@"%02x ", byte];
                [asciiPart appendFormat:@"%c", (byte >= 32 && byte <= 126) ? byte : '.'];
            } else {
                [hexPart appendString:@"   "];
            }
        }
        [lines addObject:[NSString stringWithFormat:@"%@  %@ %@",
                          VCTraceHexAddress(address + offset),
                          hexPart,
                          asciiPart]];
        offset += lineLength;
    }
    return [lines componentsJoinedByString:@"\n"];
}

- (NSString *)_typedValueForData:(NSData *)data typeEncoding:(NSString *)typeEncoding {
    NSString *encoding = VCTraceSafeString(typeEncoding);
    if (!VCTraceEncodingIsSafeForRawRead(encoding)) return @"";
    NSUInteger byteSize = VCTraceByteSizeForEncoding(encoding);
    if (byteSize == 0 || data.length < byteSize) return @"";

    void *buffer = calloc(1, byteSize);
    if (!buffer) return @"";
    [data getBytes:buffer length:byteSize];
    NSString *value = [VCValueReader readValueAtAddress:(uintptr_t)buffer typeEncoding:encoding] ?: @"";
    free(buffer);
    return value ?: @"";
}

- (NSDictionary *)_memorySnapshotPayloadForAddress:(uintptr_t)address
                                              data:(NSData *)data
                                        moduleName:(NSString *)moduleName
                                               rva:(uint64_t)rva
                                      typeEncoding:(NSString *)typeEncoding {
    VCMemRegion *region = [self _memoryRegionContainingAddress:address];
    NSMutableDictionary *payload = [@{
        @"capturedAt": @([[NSDate date] timeIntervalSince1970]),
        @"address": VCTraceHexAddress(address),
        @"length": @(data.length),
        @"moduleName": moduleName ?: @"",
        @"rva": rva > 0 ? VCTraceHexAddress(rva) : @"",
        @"region": [self _memoryRegionPayload:region],
        @"bytesHex": VCTraceHexStringFromData(data) ?: @"",
        @"hexDump": [self _hexDumpStringForData:data startAddress:address] ?: @""
    } mutableCopy];

    NSString *encoding = VCTraceSafeString(typeEncoding);
    NSString *typedValue = [self _typedValueForData:data typeEncoding:encoding];
    if (encoding.length > 0 && typedValue.length > 0) {
        payload[@"typeEncoding"] = encoding;
        payload[@"typedValue"] = typedValue;
    }
    return [payload copy];
}

- (NSDictionary *)_memoryWatchDiffFromBaseline:(NSDictionary *)baseline
                                    comparison:(NSDictionary *)comparison {
    NSData *beforeBytes = VCTraceDataFromHexString(baseline[@"bytesHex"]);
    NSData *afterBytes = VCTraceDataFromHexString(comparison[@"bytesHex"]);
    if (beforeBytes.length == 0 || afterBytes.length == 0) return nil;

    const unsigned char *before = (const unsigned char *)beforeBytes.bytes;
    const unsigned char *after = (const unsigned char *)afterBytes.bytes;
    NSUInteger maxLength = MAX(beforeBytes.length, afterBytes.length);
    NSMutableArray<NSDictionary *> *changes = [NSMutableArray new];
    NSUInteger changedByteCount = 0;
    uintptr_t baseAddress = VCTraceSafeAddress(baseline[@"address"]);
    for (NSUInteger idx = 0; idx < maxLength; idx++) {
        BOOL hasBefore = idx < beforeBytes.length;
        BOOL hasAfter = idx < afterBytes.length;
        unsigned char beforeByte = hasBefore ? before[idx] : 0;
        unsigned char afterByte = hasAfter ? after[idx] : 0;
        if (!hasBefore || !hasAfter || beforeByte != afterByte) {
            changedByteCount++;
            if (changes.count < 64) {
                [changes addObject:@{
                    @"offset": @(idx),
                    @"address": baseAddress > 0 ? VCTraceHexAddress(baseAddress + idx) : @"",
                    @"before": hasBefore ? [NSString stringWithFormat:@"%02x", beforeByte] : @"--",
                    @"after": hasAfter ? [NSString stringWithFormat:@"%02x", afterByte] : @"--"
                }];
            }
        }
    }

    NSMutableDictionary *payload = [@{
        @"changedByteCount": @(changedByteCount),
        @"changes": changes,
        @"beforeHexDump": baseline[@"hexDump"] ?: @"",
        @"afterHexDump": comparison[@"hexDump"] ?: @""
    } mutableCopy];
    NSString *encoding = VCTraceSafeString(comparison[@"typeEncoding"]);
    if (encoding.length == 0) encoding = VCTraceSafeString(baseline[@"typeEncoding"]);
    NSString *beforeValue = VCTraceSafeString(baseline[@"typedValue"]);
    NSString *afterValue = VCTraceSafeString(comparison[@"typedValue"]);
    if (encoding.length > 0 && beforeValue.length > 0 && afterValue.length > 0) {
        payload[@"typeEncoding"] = encoding;
        payload[@"typedBefore"] = beforeValue;
        payload[@"typedAfter"] = afterValue;
        payload[@"typedChanged"] = @(![beforeValue isEqualToString:afterValue]);
    }
    return [payload copy];
}

- (NSDictionary *)_relatedContextForSession:(NSMutableDictionary *)session
                   preferCurrentThreadContext:(BOOL)preferCurrentThreadContext {
    NSDictionary *currentContext = preferCurrentThreadContext ? [[VCHookManager shared] currentTraceContextSnapshot] : nil;
    NSString *currentInvocationID = VCTraceSafeString(currentContext[@"currentInvocationID"]);
    if (currentInvocationID.length > 0) {
        return @{
            @"relatedInvocationID": currentInvocationID,
            @"relatedParentInvocationID": VCTraceSafeString(currentContext[@"parentInvocationID"]),
            @"relatedDisplayName": VCTraceSafeString(currentContext[@"currentDisplayName"]),
            @"relatedThreadID": currentContext[@"threadID"] ?: @0,
            @"relatedEventID": @"",
            @"correlationType": @"captured_context"
        };
    }

    NSString *sessionID = VCTraceSafeString(session[@"sessionID"]);
    NSArray<NSDictionary *> *events = self.eventsBySession[sessionID] ?: @[];
    for (NSDictionary *event in [events reverseObjectEnumerator]) {
        if (![VCTraceEventKind(event) isEqualToString:@"method"]) continue;
        NSString *invocationID = VCTraceSafeString(event[@"invocationID"]);
        if (invocationID.length == 0) continue;
        return @{
            @"relatedInvocationID": invocationID,
            @"relatedParentInvocationID": VCTraceSafeString(event[@"parentInvocationID"]),
            @"relatedDisplayName": VCTraceMethodDisplayName(event),
            @"relatedThreadID": event[@"threadID"] ?: @0,
            @"relatedEventID": VCTraceSafeString(event[@"eventID"]),
            @"correlationType": @"latest_method"
        };
    }
    return @{};
}

- (NSDictionary *)_memoryEventForWatch:(NSDictionary *)watch
                                  diff:(NSDictionary *)diff
                             timestamp:(NSTimeInterval)timestamp
                         checkpointLabel:(NSString *)checkpointLabel
                                context:(NSDictionary *)context {
    NSString *watchLabel = VCTraceSafeString(watch[@"label"]);
    NSString *label = checkpointLabel.length > 0 ? [NSString stringWithFormat:@"%@ · %@", checkpointLabel, watchLabel] : watchLabel;
    if (label.length == 0) label = @"Memory Watch";
    return @{
        @"eventID": [[NSUUID UUID] UUIDString],
        @"kind": @"memory",
        @"timestamp": @(timestamp),
        @"address": watch[@"address"] ?: @"",
        @"label": watchLabel ?: @"Memory Watch",
        @"checkpointLabel": checkpointLabel ?: @"",
        @"moduleName": watch[@"moduleName"] ?: @"",
        @"typeEncoding": diff[@"typeEncoding"] ?: watch[@"typeEncoding"] ?: @"",
        @"changedByteCount": diff[@"changedByteCount"] ?: @0,
        @"typedBefore": diff[@"typedBefore"] ?: @"",
        @"typedAfter": diff[@"typedAfter"] ?: @"",
        @"typedChanged": diff[@"typedChanged"] ?: @NO,
        @"relatedInvocationID": context[@"relatedInvocationID"] ?: @"",
        @"relatedParentInvocationID": context[@"relatedParentInvocationID"] ?: @"",
        @"relatedDisplayName": context[@"relatedDisplayName"] ?: @"",
        @"relatedThreadID": context[@"relatedThreadID"] ?: @0,
        @"relatedEventID": context[@"relatedEventID"] ?: @"",
        @"triggeringEventID": context[@"triggeringEventID"] ?: @"",
        @"triggeringEventKind": context[@"triggeringEventKind"] ?: @"",
        @"triggeringEventTitle": context[@"triggeringEventTitle"] ?: @"",
        @"correlationType": context[@"correlationType"] ?: @"none",
        @"title": label,
        @"summary": [NSString stringWithFormat:@"%@ changed %@ bytes",
                     label,
                     diff[@"changedByteCount"] ?: @0]
    };
}

- (NSDictionary *)_contextForSourceEvent:(NSDictionary *)sourceEvent
                           fallbackSession:(NSMutableDictionary *)session {
    if ([sourceEvent isKindOfClass:[NSDictionary class]]) {
        NSString *kind = VCTraceEventKind(sourceEvent);
        NSString *relatedInvocationID = @"";
        NSString *relatedParentInvocationID = @"";
        NSString *relatedDisplayName = @"";
        NSNumber *relatedThreadID = sourceEvent[@"threadID"] ?: sourceEvent[@"relatedThreadID"] ?: @0;
        NSString *correlationType = @"source_event";
        if ([kind isEqualToString:@"method"]) {
            relatedInvocationID = VCTraceSafeString(sourceEvent[@"invocationID"]);
            relatedParentInvocationID = VCTraceSafeString(sourceEvent[@"parentInvocationID"]);
            relatedDisplayName = VCTraceMethodDisplayName(sourceEvent);
        } else {
            relatedInvocationID = VCTraceRelatedInvocationID(sourceEvent);
            relatedParentInvocationID = VCTraceSafeString(sourceEvent[@"relatedParentInvocationID"]);
            relatedDisplayName = VCTraceRelatedDisplayName(sourceEvent);
            if (relatedInvocationID.length == 0) {
                correlationType = @"source_event_detached";
            }
        }

        if (relatedInvocationID.length > 0 || VCTraceSafeString(sourceEvent[@"eventID"]).length > 0) {
            return @{
                @"relatedInvocationID": relatedInvocationID ?: @"",
                @"relatedParentInvocationID": relatedParentInvocationID ?: @"",
                @"relatedDisplayName": relatedDisplayName ?: @"",
                @"relatedThreadID": relatedThreadID ?: @0,
                @"relatedEventID": VCTraceSafeString(sourceEvent[@"eventID"]),
                @"triggeringEventID": VCTraceSafeString(sourceEvent[@"eventID"]),
                @"triggeringEventKind": kind ?: @"",
                @"triggeringEventTitle": VCTraceSafeString(sourceEvent[@"title"]),
                @"correlationType": correlationType
            };
        }
    }

    return [self _relatedContextForSession:session preferCurrentThreadContext:YES];
}

- (NSDictionary *)_checkpointEventForLabel:(NSString *)label
                           checkpointIndex:(NSUInteger)checkpointIndex
                          changedWatchCount:(NSUInteger)changedWatchCount
                                 watchCount:(NSUInteger)watchCount
                                  timestamp:(NSTimeInterval)timestamp
                                    context:(NSDictionary *)context
                                    trigger:(NSDictionary *)trigger
                                sourceEvent:(NSDictionary *)sourceEvent
                               resetBaseline:(BOOL)resetBaseline {
    NSString *safeLabel = VCTraceSafeString(label);
    if (safeLabel.length == 0) safeLabel = [NSString stringWithFormat:@"Checkpoint %lu", (unsigned long)checkpointIndex];
    NSString *triggerKind = VCTraceSafeString(trigger[@"kind"]);
    BOOL automatic = [trigger isKindOfClass:[NSDictionary class]] && trigger.count > 0;
    NSString *sourceKind = VCTraceEventKind(sourceEvent);
    NSString *sourceTitle = VCTraceSafeString(sourceEvent[@"title"]);
    NSString *summary = changedWatchCount > 0
        ? [NSString stringWithFormat:@"%@ captured %@ changed watches", safeLabel, @(changedWatchCount)]
        : [NSString stringWithFormat:@"%@ captured %@ watches with no diff", safeLabel, @(watchCount)];
    if (automatic && sourceTitle.length > 0) {
        summary = [summary stringByAppendingFormat:@" after %@", sourceTitle];
    }

    return @{
        @"eventID": [[NSUUID UUID] UUIDString],
        @"kind": @"checkpoint",
        @"timestamp": @(timestamp),
        @"label": safeLabel,
        @"checkpointIndex": @(checkpointIndex),
        @"watchCount": @(watchCount),
        @"changedWatchCount": @(changedWatchCount),
        @"automatic": @(automatic),
        @"resetBaseline": @(resetBaseline),
        @"triggerID": trigger[@"triggerID"] ?: @"",
        @"triggerKind": triggerKind ?: @"",
        @"triggeringEventID": VCTraceSafeString(sourceEvent[@"eventID"]),
        @"triggeringEventKind": sourceKind ?: @"",
        @"triggeringEventTitle": sourceTitle ?: @"",
        @"relatedInvocationID": context[@"relatedInvocationID"] ?: @"",
        @"relatedParentInvocationID": context[@"relatedParentInvocationID"] ?: @"",
        @"relatedDisplayName": context[@"relatedDisplayName"] ?: @"",
        @"relatedThreadID": context[@"relatedThreadID"] ?: @0,
        @"relatedEventID": context[@"relatedEventID"] ?: @"",
        @"correlationType": context[@"correlationType"] ?: @"none",
        @"title": safeLabel,
        @"summary": summary
    };
}

- (NSArray<NSDictionary *> *)_mergedMemoryWatches:(NSArray<NSDictionary *> *)existingWatches
                                         additions:(NSArray<NSDictionary *> *)newWatches {
    NSMutableArray<NSDictionary *> *merged = [NSMutableArray arrayWithArray:existingWatches ?: @[]];
    NSMutableSet<NSString *> *keys = [NSMutableSet new];
    for (NSDictionary *watch in merged) {
        NSString *key = [NSString stringWithFormat:@"%@|%@",
                         VCTraceSafeString(watch[@"address"]),
                         VCTraceSafeString(watch[@"typeEncoding"])];
        if (key.length > 1) [keys addObject:key];
    }

    for (NSDictionary *watch in newWatches ?: @[]) {
        NSString *key = [NSString stringWithFormat:@"%@|%@",
                         VCTraceSafeString(watch[@"address"]),
                         VCTraceSafeString(watch[@"typeEncoding"])];
        if ([keys containsObject:key]) continue;
        [merged addObject:watch];
        if (key.length > 1) [keys addObject:key];
    }
    return [merged copy];
}

- (NSArray<NSDictionary *> *)_memoryWatchSpecsFromOptions:(NSDictionary *)options {
    NSArray *rawWatches = [options[@"memoryWatches"] isKindOfClass:[NSArray class]] ? options[@"memoryWatches"] : @[];
    NSMutableArray<NSDictionary *> *items = [NSMutableArray new];
    for (NSDictionary *rawWatch in rawWatches) {
        if (![rawWatch isKindOfClass:[NSDictionary class]]) continue;
        uintptr_t address = VCTraceSafeAddress(rawWatch[@"address"]);
        if (address == 0) continue;

        NSString *moduleName = nil;
        uint64_t rva = [[VCProcessInfo shared] runtimeToRva:(uint64_t)address module:&moduleName];
        NSString *blockedReason = [VCPromptLeakGuard blockedToolReasonForMemoryModuleName:moduleName address:(unsigned long long)address];
        if (blockedReason.length > 0) continue;

        NSString *typeEncoding = VCTraceSafeString(rawWatch[@"typeEncoding"]);
        NSUInteger length = VCTraceSafeUnsigned(rawWatch[@"length"], 32, 128);
        if (typeEncoding.length > 0 && VCTraceEncodingIsSafeForRawRead(typeEncoding)) {
            NSUInteger typedLength = VCTraceByteSizeForEncoding(typeEncoding);
            if (typedLength > 0) length = MIN(MAX(length, typedLength), 128);
        }

        NSString *readError = nil;
        NSData *baselineBytes = [self _safeReadDataAtAddress:address length:length errorMessage:&readError];
        if (!baselineBytes) continue;

        NSString *label = VCTraceSafeString(rawWatch[@"label"]);
        if (label.length == 0) label = [NSString stringWithFormat:@"Watch %@", VCTraceHexAddress(address)];
        NSDictionary *baseline = [self _memorySnapshotPayloadForAddress:address
                                                                   data:baselineBytes
                                                             moduleName:moduleName
                                                                    rva:rva
                                                           typeEncoding:typeEncoding];
        [items addObject:@{
            @"watchID": [[NSUUID UUID] UUIDString],
            @"label": label,
            @"address": VCTraceHexAddress(address),
            @"length": @(baselineBytes.length),
            @"moduleName": moduleName ?: @"",
            @"rva": rva > 0 ? VCTraceHexAddress(rva) : @"",
            @"typeEncoding": typeEncoding ?: @"",
            @"baseline": baseline ?: @{},
            @"status": @"watching"
        }];
        if (items.count >= 6) break;
    }
    return [items copy];
}

- (NSArray<NSDictionary *> *)_checkpointTriggerSpecsFromOptions:(NSDictionary *)options {
    NSArray *rawTriggers = [options[@"checkpointTriggers"] isKindOfClass:[NSArray class]] ? options[@"checkpointTriggers"] : @[];
    NSMutableArray<NSDictionary *> *items = [NSMutableArray new];
    for (NSDictionary *rawTrigger in rawTriggers) {
        if (![rawTrigger isKindOfClass:[NSDictionary class]]) continue;

        NSString *kind = VCTraceSafeString(rawTrigger[@"kind"]).lowercaseString;
        if (kind.length == 0) {
            if (VCTraceSafeString(rawTrigger[@"selector"]).length > 0) {
                kind = @"method";
            } else if (VCTraceSafeString(rawTrigger[@"httpMethod"]).length > 0 ||
                       VCTraceSafeString(rawTrigger[@"host"]).length > 0 ||
                       VCTraceSafeString(rawTrigger[@"pathContains"]).length > 0 ||
                       rawTrigger[@"statusCode"] != nil) {
                kind = @"network";
            } else if (VCTraceSafeString(rawTrigger[@"viewClassName"]).length > 0 ||
                       VCTraceSafeString(rawTrigger[@"address"]).length > 0) {
                kind = @"ui";
            }
        }
        if (![@[@"method", @"network", @"ui"] containsObject:kind]) continue;

        NSString *label = VCTraceSafeString(rawTrigger[@"label"]);
        BOOL once = rawTrigger[@"once"] ? VCTraceSafeBool(rawTrigger[@"once"], YES) : YES;
        NSUInteger requestedMaxCount = [rawTrigger[@"maxCount"] respondsToSelector:@selector(unsignedIntegerValue)] ? [rawTrigger[@"maxCount"] unsignedIntegerValue] : 0;
        NSUInteger maxCount = requestedMaxCount > 0 ? MIN(requestedMaxCount, 20) : (once ? 1 : 3);
        if (once) maxCount = 1;

        NSMutableDictionary *trigger = [@{
            @"triggerID": [[NSUUID UUID] UUIDString],
            @"kind": kind,
            @"label": label ?: @"",
            @"once": @(once),
            @"maxCount": @(maxCount),
            @"firedCount": @0,
            @"resetBaseline": @(VCTraceSafeBool(rawTrigger[@"resetBaseline"], YES)),
            @"titleContains": VCTraceSafeString(rawTrigger[@"titleContains"]),
            @"summaryContains": VCTraceSafeString(rawTrigger[@"summaryContains"]),
            @"onlyWhenChanged": @((rawTrigger[@"onlyWhenChanged"] || rawTrigger[@"whenChanged"]) ? VCTraceSafeBool(rawTrigger[@"onlyWhenChanged"] ?: rawTrigger[@"whenChanged"], YES) : NO),
            @"requireTypedChange": @((rawTrigger[@"requireTypedChange"] || rawTrigger[@"typedChanged"]) ? VCTraceSafeBool(rawTrigger[@"requireTypedChange"] ?: rawTrigger[@"typedChanged"], YES) : NO),
            @"watchAddress": VCTraceSafeString(rawTrigger[@"watchAddress"]),
            @"watchLabel": VCTraceSafeString(rawTrigger[@"watchLabel"]),
            @"typedEquals": VCTraceSafeString(rawTrigger[@"typedEquals"] ?: rawTrigger[@"typedAfterEquals"] ?: rawTrigger[@"valueEquals"]),
            @"typedContains": VCTraceSafeString(rawTrigger[@"typedContains"] ?: rawTrigger[@"typedAfterContains"] ?: rawTrigger[@"valueContains"]),
            @"memoryWatches": [self _memoryWatchSpecsFromOptions:@{@"memoryWatches": rawTrigger[@"memoryWatches"] ?: @[]}] ?: @[]
        } mutableCopy];
        if ([rawTrigger[@"changedBytesAtLeast"] respondsToSelector:@selector(unsignedIntegerValue)]) {
            trigger[@"changedBytesAtLeast"] = @(MIN([rawTrigger[@"changedBytesAtLeast"] unsignedIntegerValue], 4096));
        }

        if ([kind isEqualToString:@"method"]) {
            NSString *className = VCTraceSafeString(rawTrigger[@"className"]);
            if (className.length > 0 &&
                [VCPromptLeakGuard blockedToolReasonForClassName:className moduleName:nil].length > 0) {
                continue;
            }
            trigger[@"className"] = className ?: @"";
            trigger[@"selector"] = VCTraceSafeString(rawTrigger[@"selector"]);
            trigger[@"hasIsClassMethod"] = @(rawTrigger[@"isClassMethod"] != nil);
            trigger[@"isClassMethod"] = @(VCTraceSafeBool(rawTrigger[@"isClassMethod"], NO));
        } else if ([kind isEqualToString:@"network"]) {
            trigger[@"httpMethod"] = VCTraceSafeString(rawTrigger[@"httpMethod"]).uppercaseString ?: @"";
            trigger[@"host"] = VCTraceSafeString(rawTrigger[@"host"]);
            trigger[@"pathContains"] = VCTraceSafeString(rawTrigger[@"pathContains"]);
            if ([rawTrigger[@"statusCode"] respondsToSelector:@selector(integerValue)]) {
                trigger[@"statusCode"] = @([rawTrigger[@"statusCode"] integerValue]);
            }
        } else if ([kind isEqualToString:@"ui"]) {
            NSString *viewClassName = VCTraceSafeString(rawTrigger[@"viewClassName"]);
            if (viewClassName.length == 0) viewClassName = VCTraceSafeString(rawTrigger[@"className"]);
            if (viewClassName.length > 0 &&
                [VCPromptLeakGuard blockedToolReasonForClassName:viewClassName moduleName:nil].length > 0) {
                continue;
            }
            trigger[@"viewClassName"] = viewClassName ?: @"";
            trigger[@"address"] = VCTraceSafeString(rawTrigger[@"address"]);
        }

        [items addObject:[trigger copy]];
        if (items.count >= 8) break;
    }
    return [items copy];
}

- (NSString *)_autoCheckpointLabelForTrigger:(NSDictionary *)trigger
                                       event:(NSDictionary *)event
                                   fireIndex:(NSUInteger)fireIndex {
    NSString *baseLabel = VCTraceSafeString(trigger[@"label"]);
    NSString *kind = VCTraceSafeString(trigger[@"kind"]);
    if (baseLabel.length == 0) {
        if ([kind isEqualToString:@"method"]) {
            baseLabel = [NSString stringWithFormat:@"Auto %@", VCTraceMethodDisplayName(event)];
        } else if ([kind isEqualToString:@"network"]) {
            NSString *method = VCTraceSafeString(event[@"method"]);
            NSString *path = VCTraceSafeString(event[@"path"]);
            baseLabel = [NSString stringWithFormat:@"Auto %@ %@", method.length > 0 ? method : @"REQ", path.length > 0 ? path : @"/"];
        } else if ([kind isEqualToString:@"ui"]) {
            NSString *className = VCTraceSafeString(event[@"className"]);
            baseLabel = className.length > 0 ? [NSString stringWithFormat:@"Auto %@", className] : @"Auto UI Checkpoint";
        } else {
            baseLabel = @"Auto Checkpoint";
        }
    }

    NSUInteger maxCount = VCTraceSafeUnsigned(trigger[@"maxCount"], 1, 20);
    if (maxCount > 1) {
        return [NSString stringWithFormat:@"%@ #%lu", baseLabel, (unsigned long)fireIndex];
    }
    return baseLabel;
}

- (BOOL)_event:(NSDictionary *)event matchesCheckpointTrigger:(NSDictionary *)trigger {
    NSString *kind = VCTraceSafeString(trigger[@"kind"]);
    if (kind.length == 0 || ![kind isEqualToString:VCTraceEventKind(event)]) return NO;

    NSUInteger firedCount = VCTraceSafeUnsigned(trigger[@"firedCount"], 0, 1000);
    NSUInteger maxCount = VCTraceSafeUnsigned(trigger[@"maxCount"], 1, 20);
    if (maxCount > 0 && firedCount >= maxCount) return NO;

    NSString *titleContains = VCTraceSafeString(trigger[@"titleContains"]);
    if (titleContains.length > 0 && !VCTraceStringContainsFolded(event[@"title"], titleContains)) return NO;
    NSString *summaryContains = VCTraceSafeString(trigger[@"summaryContains"]);
    if (summaryContains.length > 0 && !VCTraceStringContainsFolded(event[@"summary"], summaryContains)) return NO;

    if ([kind isEqualToString:@"method"]) {
        NSString *className = VCTraceSafeString(trigger[@"className"]);
        if (className.length > 0 && !VCTraceStringEqualsFolded(event[@"className"], className)) return NO;
        NSString *selector = VCTraceSafeString(trigger[@"selector"]);
        if (selector.length > 0 && !VCTraceStringEqualsFolded(event[@"selector"], selector)) return NO;
        if ([trigger[@"hasIsClassMethod"] boolValue] &&
            [event[@"isClassMethod"] boolValue] != [trigger[@"isClassMethod"] boolValue]) return NO;
        return YES;
    }

    if ([kind isEqualToString:@"network"]) {
        NSString *httpMethod = VCTraceSafeString(trigger[@"httpMethod"]);
        if (httpMethod.length > 0 && !VCTraceStringEqualsFolded(event[@"method"], httpMethod)) return NO;
        NSString *host = VCTraceSafeString(trigger[@"host"]);
        if (host.length > 0 && !VCTraceStringContainsFolded(event[@"host"], host)) return NO;
        NSString *pathContains = VCTraceSafeString(trigger[@"pathContains"]);
        if (pathContains.length > 0 && !VCTraceStringContainsFolded(event[@"path"], pathContains)) return NO;
        if ([trigger[@"statusCode"] respondsToSelector:@selector(integerValue)] &&
            [event[@"statusCode"] respondsToSelector:@selector(integerValue)] &&
            [trigger[@"statusCode"] integerValue] > 0 &&
            [event[@"statusCode"] integerValue] != [trigger[@"statusCode"] integerValue]) return NO;
        return YES;
    }

    if ([kind isEqualToString:@"ui"]) {
        NSString *viewClassName = VCTraceSafeString(trigger[@"viewClassName"]);
        if (viewClassName.length > 0 && !VCTraceStringEqualsFolded(event[@"className"], viewClassName)) return NO;
        NSString *address = VCTraceSafeString(trigger[@"address"]);
        if (address.length > 0 && !VCTraceStringEqualsFolded(event[@"address"], address)) return NO;
        return YES;
    }

    return NO;
}

- (NSDictionary *)_checkpointConditionResultForTrigger:(NSDictionary *)trigger
                                          watchResults:(NSArray<NSDictionary *> *)watchResults
                                      changedWatchCount:(NSUInteger)changedWatchCount {
    BOOL onlyWhenChanged = [trigger[@"onlyWhenChanged"] boolValue];
    BOOL requireTypedChange = [trigger[@"requireTypedChange"] boolValue];
    NSUInteger changedBytesAtLeast = VCTraceSafeUnsigned(trigger[@"changedBytesAtLeast"], 0, 4096);
    NSString *watchAddress = VCTraceSafeString(trigger[@"watchAddress"]);
    NSString *watchLabel = VCTraceSafeString(trigger[@"watchLabel"]);
    NSString *typedEquals = VCTraceSafeString(trigger[@"typedEquals"]);
    NSString *typedContains = VCTraceSafeString(trigger[@"typedContains"]);

    BOOL hasConditions = onlyWhenChanged || requireTypedChange || changedBytesAtLeast > 0 ||
                         watchAddress.length > 0 || watchLabel.length > 0 ||
                         typedEquals.length > 0 || typedContains.length > 0;
    if (!hasConditions) {
        return @{@"matched": @YES};
    }

    NSArray<NSDictionary *> *results = [watchResults isKindOfClass:[NSArray class]] ? watchResults : @[];
    NSMutableArray<NSDictionary *> *candidateWatches = [NSMutableArray new];
    for (NSDictionary *watch in results) {
        if (![watch isKindOfClass:[NSDictionary class]]) continue;
        if (watchAddress.length > 0 && !VCTraceStringEqualsFolded(watch[@"address"], watchAddress)) continue;
        if (watchLabel.length > 0 && !VCTraceStringEqualsFolded(watch[@"label"], watchLabel)) continue;
        [candidateWatches addObject:watch];
    }

    if (candidateWatches.count == 0) {
        NSString *reason = watchAddress.length > 0 || watchLabel.length > 0
            ? @"No watched memory region matched the trigger's watch selector."
            : @"The trigger did not have any captured watch results to evaluate.";
        return @{
            @"matched": @NO,
            @"reason": reason
        };
    }

    for (NSDictionary *watch in candidateWatches) {
        NSString *status = VCTraceSafeString(watch[@"status"]);
        if (![status isEqualToString:@"captured"]) continue;

        NSDictionary *diff = [watch[@"diff"] isKindOfClass:[NSDictionary class]] ? watch[@"diff"] : @{};
        NSDictionary *comparison = [watch[@"comparison"] isKindOfClass:[NSDictionary class]] ? watch[@"comparison"] : @{};
        NSUInteger changedByteCount = [diff[@"changedByteCount"] respondsToSelector:@selector(unsignedIntegerValue)] ? [diff[@"changedByteCount"] unsignedIntegerValue] : 0;
        BOOL typedChanged = [diff[@"typedChanged"] boolValue];
        BOOL didChange = changedByteCount > 0 || typedChanged;
        NSString *typedAfter = VCTraceSafeString(diff[@"typedAfter"]);
        if (typedAfter.length == 0) typedAfter = VCTraceSafeString(comparison[@"typedValue"]);

        if (onlyWhenChanged && !didChange) continue;
        if (changedBytesAtLeast > 0 && changedByteCount < changedBytesAtLeast) continue;
        if (requireTypedChange && !typedChanged) continue;
        if (typedEquals.length > 0 && !VCTraceStringEqualsFolded(typedAfter, typedEquals)) continue;
        if (typedContains.length > 0 && !VCTraceStringContainsFolded(typedAfter, typedContains)) continue;

        NSMutableDictionary *result = [@{
            @"matched": @YES,
            @"matchedWatchID": VCTraceSafeString(watch[@"watchID"]),
            @"matchedWatchLabel": VCTraceSafeString(watch[@"label"]),
            @"matchedWatchAddress": VCTraceSafeString(watch[@"address"]),
            @"changedByteCount": @(changedByteCount),
            @"typedChanged": @(typedChanged),
            @"typedAfter": typedAfter ?: @"",
            @"changedWatchCount": @(changedWatchCount)
        } mutableCopy];
        NSString *summary = VCTraceSafeString(watch[@"label"]);
        if (summary.length == 0) summary = VCTraceSafeString(watch[@"address"]);
        if (typedAfter.length > 0) {
            summary = [NSString stringWithFormat:@"%@ => %@", summary.length > 0 ? summary : @"watch", typedAfter];
        }
        result[@"conditionSummary"] = summary ?: @"";
        return [result copy];
    }

    NSMutableArray<NSString *> *parts = [NSMutableArray new];
    if (onlyWhenChanged) [parts addObject:@"no watched value changed"];
    if (changedBytesAtLeast > 0) [parts addObject:[NSString stringWithFormat:@"no watch changed at least %@ bytes", @(changedBytesAtLeast)]];
    if (requireTypedChange) [parts addObject:@"no watched typed value changed"];
    if (typedEquals.length > 0) [parts addObject:[NSString stringWithFormat:@"no watched typed value matched %@", typedEquals]];
    if (typedContains.length > 0) [parts addObject:[NSString stringWithFormat:@"no watched typed value contained %@", typedContains]];
    NSString *reason = parts.count > 0 ? [parts componentsJoinedByString:@"; "] : @"No watch satisfied the trigger condition.";
    return @{
        @"matched": @NO,
        @"reason": reason
    };
}

- (NSDictionary *)_captureCheckpointForSessionLocked:(NSMutableDictionary *)session
                                             options:(NSDictionary *)options
                                         sourceEvent:(NSDictionary *)sourceEvent
                                             trigger:(NSMutableDictionary *)trigger
                                        errorMessage:(NSString **)errorMessage {
    if (![options isKindOfClass:[NSDictionary class]]) options = @{};
    if (!session || ![session[@"active"] boolValue]) {
        if (errorMessage) *errorMessage = @"Trace session is not active.";
        return nil;
    }

    NSArray<NSDictionary *> *newWatches = [self _memoryWatchSpecsFromOptions:options];
    NSArray<NSDictionary *> *existingWatches = [session[@"memoryWatches"] isKindOfClass:[NSArray class]] ? session[@"memoryWatches"] : @[];
    NSArray<NSDictionary *> *mergedWatches = [self _mergedMemoryWatches:existingWatches additions:newWatches];
    BOOL resetBaseline = VCTraceSafeBool(options[@"resetBaseline"], YES);
    NSUInteger checkpointIndex = VCTraceSafeUnsigned(session[@"checkpointCount"], 0, 1000000) + 1;
    NSUInteger fireIndex = VCTraceSafeUnsigned(trigger[@"firedCount"], 0, 1000000) + 1;
    NSString *label = VCTraceSafeString(options[@"label"]);
    if (label.length == 0) {
        label = trigger ? [self _autoCheckpointLabelForTrigger:trigger event:sourceEvent fireIndex:fireIndex] : @"";
    }
    if (label.length == 0) label = [NSString stringWithFormat:@"Checkpoint %lu", (unsigned long)checkpointIndex];

    NSDictionary *context = [self _contextForSourceEvent:sourceEvent fallbackSession:session];
    NSTimeInterval timestamp = [[NSDate date] timeIntervalSince1970];
    NSMutableArray<NSDictionary *> *updatedWatches = [NSMutableArray new];
    NSMutableArray<NSDictionary *> *watchResults = [NSMutableArray new];
    NSMutableArray<NSDictionary *> *pendingMemoryEvents = [NSMutableArray new];
    NSUInteger changedWatchCount = 0;

    for (NSDictionary *watch in mergedWatches) {
        NSMutableDictionary *watchCopy = [watch mutableCopy];
        uintptr_t address = VCTraceSafeAddress(watch[@"address"]);
        NSUInteger length = VCTraceSafeUnsigned(watch[@"length"], 32, 128);
        NSString *typeEncoding = VCTraceSafeString(watch[@"typeEncoding"]);
        NSString *moduleName = nil;
        uint64_t rva = [[VCProcessInfo shared] runtimeToRva:(uint64_t)address module:&moduleName];
        NSString *blockedReason = [VCPromptLeakGuard blockedToolReasonForMemoryModuleName:moduleName address:(unsigned long long)address];
        if (blockedReason.length > 0) {
            watchCopy[@"status"] = @"redacted";
            watchCopy[@"error"] = blockedReason;
            [updatedWatches addObject:[watchCopy copy]];
            [watchResults addObject:[watchCopy copy]];
            continue;
        }

        NSString *readError = nil;
        NSData *comparisonBytes = [self _safeReadDataAtAddress:address length:length errorMessage:&readError];
        if (!comparisonBytes) {
            watchCopy[@"status"] = @"unavailable";
            watchCopy[@"error"] = readError ?: @"Could not read memory for checkpoint.";
            [updatedWatches addObject:[watchCopy copy]];
            [watchResults addObject:[watchCopy copy]];
            continue;
        }

        NSDictionary *comparison = [self _memorySnapshotPayloadForAddress:address
                                                                     data:comparisonBytes
                                                               moduleName:moduleName
                                                                      rva:rva
                                                             typeEncoding:typeEncoding];
        NSDictionary *baseline = [watch[@"baseline"] isKindOfClass:[NSDictionary class]] ? watch[@"baseline"] : comparison;
        NSDictionary *diff = [self _memoryWatchDiffFromBaseline:baseline comparison:comparison] ?: @{};
        BOOL typedChanged = [diff[@"typedChanged"] boolValue];
        NSUInteger changedByteCount = [diff[@"changedByteCount"] respondsToSelector:@selector(unsignedIntegerValue)] ? [diff[@"changedByteCount"] unsignedIntegerValue] : 0;
        if (changedByteCount > 0 || typedChanged) changedWatchCount++;

        watchCopy[@"comparison"] = comparison ?: @{};
        watchCopy[@"diff"] = diff ?: @{};
        watchCopy[@"status"] = @"captured";
        watchCopy[@"lastCheckpointLabel"] = label;
        watchCopy[@"lastCheckpointAt"] = @(timestamp);
        watchCopy[@"checkpointCount"] = @(VCTraceSafeUnsigned(watch[@"checkpointCount"], 0, 1000000) + 1);
        if (resetBaseline) {
            watchCopy[@"baseline"] = comparison ?: @{};
        }
        [updatedWatches addObject:[watchCopy copy]];
        [watchResults addObject:[watchCopy copy]];

        if (changedByteCount > 0 || typedChanged) {
            NSDictionary *event = [self _memoryEventForWatch:watchCopy
                                                        diff:diff
                                                   timestamp:timestamp
                                             checkpointLabel:label
                                                      context:context];
            [pendingMemoryEvents addObject:event];
        }
    }

    NSDictionary *conditionResult = [self _checkpointConditionResultForTrigger:trigger
                                                                  watchResults:watchResults
                                                              changedWatchCount:changedWatchCount];
    if ([trigger isKindOfClass:[NSDictionary class]] && ![conditionResult[@"matched"] boolValue]) {
        trigger[@"lastSkippedAt"] = @(timestamp);
        trigger[@"lastSkipReason"] = conditionResult[@"reason"] ?: @"Checkpoint trigger condition was not satisfied.";
        trigger[@"skipCount"] = @(VCTraceSafeUnsigned(trigger[@"skipCount"], 0, 1000000) + 1);
        return @{
            @"sessionID": VCTraceSafeString(session[@"sessionID"]),
            @"label": label,
            @"timestamp": @(timestamp),
            @"watchCount": @(updatedWatches.count),
            @"changedWatchCount": @(changedWatchCount),
            @"automatic": @YES,
            @"skipped": @YES,
            @"skippedReason": trigger[@"lastSkipReason"] ?: @"",
            @"triggerID": trigger[@"triggerID"] ?: @"",
            @"triggerKind": trigger[@"kind"] ?: @""
        };
    }

    session[@"memoryWatches"] = [updatedWatches copy];
    session[@"memoryWatchCount"] = @(updatedWatches.count);
    session[@"checkpointCount"] = @(checkpointIndex);
    session[@"lastCheckpointLabel"] = label;
    session[@"lastCheckpointAt"] = @(timestamp);
    if (trigger) {
        trigger[@"firedCount"] = @(fireIndex);
        trigger[@"lastFiredAt"] = @(timestamp);
        trigger[@"lastMatchedEventID"] = VCTraceSafeString(sourceEvent[@"eventID"]);
        trigger[@"lastMatchedKind"] = VCTraceEventKind(sourceEvent);
        trigger[@"lastLabel"] = label;
        session[@"autoCheckpointCount"] = @(VCTraceSafeUnsigned(session[@"autoCheckpointCount"], 0, 1000000) + 1);
    }

    NSDictionary *checkpointEvent = [self _checkpointEventForLabel:label
                                                   checkpointIndex:checkpointIndex
                                                  changedWatchCount:changedWatchCount
                                                         watchCount:updatedWatches.count
                                                          timestamp:timestamp
                                                            context:context
                                                            trigger:trigger
                                                        sourceEvent:sourceEvent
                                                       resetBaseline:resetBaseline];
    [self _appendEvent:checkpointEvent toSession:session];
    for (NSDictionary *memoryEvent in pendingMemoryEvents) {
        [self _appendEvent:memoryEvent toSession:session];
    }
    [self _saveState];

    NSMutableDictionary *payload = [@{
        @"sessionID": VCTraceSafeString(session[@"sessionID"]),
        @"label": label,
        @"checkpointIndex": @(checkpointIndex),
        @"timestamp": @(timestamp),
        @"watchCount": @(updatedWatches.count),
        @"changedWatchCount": @(changedWatchCount),
        @"resetBaseline": @(resetBaseline),
        @"automatic": @([trigger isKindOfClass:[NSDictionary class]] && trigger.count > 0),
        @"watches": watchResults,
        @"checkpointEventID": checkpointEvent[@"eventID"] ?: @""
    } mutableCopy];
    if ([sourceEvent isKindOfClass:[NSDictionary class]]) {
        payload[@"triggeredByEventID"] = VCTraceSafeString(sourceEvent[@"eventID"]);
        payload[@"triggeredByKind"] = VCTraceEventKind(sourceEvent);
        payload[@"triggeredByTitle"] = VCTraceSafeString(sourceEvent[@"title"]);
    }
    if ([trigger isKindOfClass:[NSDictionary class]] && trigger.count > 0) {
        payload[@"triggerID"] = trigger[@"triggerID"] ?: @"";
        payload[@"triggerKind"] = trigger[@"kind"] ?: @"";
        payload[@"triggerFireCount"] = trigger[@"firedCount"] ?: @0;
    }
    if ([conditionResult isKindOfClass:[NSDictionary class]] && [conditionResult[@"matched"] boolValue]) {
        payload[@"conditionSummary"] = conditionResult[@"conditionSummary"] ?: @"";
        payload[@"matchedWatchID"] = conditionResult[@"matchedWatchID"] ?: @"";
        payload[@"matchedWatchLabel"] = conditionResult[@"matchedWatchLabel"] ?: @"";
        payload[@"matchedWatchAddress"] = conditionResult[@"matchedWatchAddress"] ?: @"";
        payload[@"matchedTypedAfter"] = conditionResult[@"typedAfter"] ?: @"";
    }
    return [payload copy];
}

- (void)_evaluateCheckpointTriggersForSession:(NSMutableDictionary *)session event:(NSDictionary *)event {
    NSArray<NSDictionary *> *triggerList = [session[@"checkpointTriggers"] isKindOfClass:[NSArray class]] ? session[@"checkpointTriggers"] : @[];
    if (triggerList.count == 0 || ![event isKindOfClass:[NSDictionary class]]) return;

    NSMutableArray<NSDictionary *> *updatedTriggers = [NSMutableArray new];
    BOOL didUpdate = NO;
    for (NSDictionary *triggerEntry in triggerList) {
        NSMutableDictionary *trigger = [triggerEntry mutableCopy] ?: [NSMutableDictionary new];
        if ([self _event:event matchesCheckpointTrigger:trigger]) {
            NSDictionary *options = @{
                @"label": [self _autoCheckpointLabelForTrigger:trigger
                                                         event:event
                                                     fireIndex:VCTraceSafeUnsigned(trigger[@"firedCount"], 0, 1000000) + 1] ?: @"",
                @"resetBaseline": trigger[@"resetBaseline"] ?: @YES,
                @"memoryWatches": trigger[@"memoryWatches"] ?: @[]
            };
            [self _captureCheckpointForSessionLocked:session
                                             options:options
                                         sourceEvent:event
                                             trigger:trigger
                                        errorMessage:nil];
            didUpdate = YES;
        }
        [updatedTriggers addObject:[trigger copy]];
    }

    if (didUpdate) {
        session[@"checkpointTriggers"] = [updatedTriggers copy];
        session[@"checkpointTriggerCount"] = @(updatedTriggers.count);
        [self _saveState];
    }
}

- (void)_finalizeMemoryWatchesForSession:(NSMutableDictionary *)session {
    NSArray<NSDictionary *> *watchList = [session[@"memoryWatches"] isKindOfClass:[NSArray class]] ? session[@"memoryWatches"] : @[];
    if (watchList.count == 0) return;

    NSMutableArray<NSDictionary *> *finalized = [NSMutableArray new];
    NSTimeInterval timestamp = [[NSDate date] timeIntervalSince1970];
    NSDictionary *context = [self _relatedContextForSession:session preferCurrentThreadContext:YES];
    for (NSDictionary *watch in watchList) {
        NSMutableDictionary *watchCopy = [watch mutableCopy];
        uintptr_t address = VCTraceSafeAddress(watch[@"address"]);
        NSUInteger length = VCTraceSafeUnsigned(watch[@"length"], 32, 128);
        NSString *typeEncoding = VCTraceSafeString(watch[@"typeEncoding"]);
        NSString *moduleName = nil;
        uint64_t rva = [[VCProcessInfo shared] runtimeToRva:(uint64_t)address module:&moduleName];
        NSString *blockedReason = [VCPromptLeakGuard blockedToolReasonForMemoryModuleName:moduleName address:(unsigned long long)address];
        if (blockedReason.length > 0) {
            watchCopy[@"status"] = @"redacted";
            watchCopy[@"error"] = blockedReason;
            [finalized addObject:[watchCopy copy]];
            continue;
        }

        NSString *readError = nil;
        NSData *comparisonBytes = [self _safeReadDataAtAddress:address length:length errorMessage:&readError];
        if (!comparisonBytes) {
            watchCopy[@"status"] = @"unavailable";
            watchCopy[@"error"] = readError ?: @"Could not read memory at trace stop.";
            [finalized addObject:[watchCopy copy]];
            continue;
        }

        NSDictionary *comparison = [self _memorySnapshotPayloadForAddress:address
                                                                     data:comparisonBytes
                                                               moduleName:moduleName
                                                                      rva:rva
                                                             typeEncoding:typeEncoding];
        NSDictionary *diff = [self _memoryWatchDiffFromBaseline:watch[@"baseline"] comparison:comparison];
        watchCopy[@"comparison"] = comparison ?: @{};
        watchCopy[@"diff"] = diff ?: @{};
        watchCopy[@"status"] = @"captured";
        watchCopy[@"lastCheckpointLabel"] = @"Trace Stop";
        watchCopy[@"lastCheckpointAt"] = @(timestamp);
        [finalized addObject:[watchCopy copy]];

        BOOL typedChanged = [diff[@"typedChanged"] boolValue];
        NSUInteger changedByteCount = [diff[@"changedByteCount"] respondsToSelector:@selector(unsignedIntegerValue)] ? [diff[@"changedByteCount"] unsignedIntegerValue] : 0;
        if (changedByteCount > 0 || typedChanged) {
            NSDictionary *event = [self _memoryEventForWatch:watchCopy
                                                        diff:diff
                                                   timestamp:timestamp
                                             checkpointLabel:@"Trace Stop"
                                                      context:context];
            [self _appendEvent:event toSession:session];
        }
    }

    session[@"memoryWatches"] = [finalized copy];
    session[@"memoryWatchCount"] = @(finalized.count);
}

- (NSDictionary *)captureCheckpointForSession:(NSString *)sessionID
                                      options:(NSDictionary *)options
                                 errorMessage:(NSString **)errorMessage {
    if (![options isKindOfClass:[NSDictionary class]]) options = @{};

    @synchronized (self) {
        NSString *resolvedSessionID = VCTraceSafeString(sessionID);
        if (resolvedSessionID.length == 0) resolvedSessionID = self.activeSessionID;
        if (resolvedSessionID.length == 0) {
            if (errorMessage) *errorMessage = @"No active trace session.";
            return nil;
        }

        NSMutableDictionary *session = [self _mutableSessionForID:resolvedSessionID];
        if (!session || ![session[@"active"] boolValue]) {
            if (errorMessage) *errorMessage = @"Trace session is not active.";
            return nil;
        }
        return [self _captureCheckpointForSessionLocked:session
                                                options:options
                                            sourceEvent:nil
                                                trigger:nil
                                           errorMessage:errorMessage];
    }
}

- (NSDictionary *)startTraceWithOptions:(NSDictionary *)options errorMessage:(NSString **)errorMessage {
    if (![options isKindOfClass:[NSDictionary class]]) options = @{};

    @synchronized (self) {
        BOOL stopExisting = VCTraceSafeBool(options[@"stopExisting"], YES);
        if (self.activeSessionID.length > 0) {
            if (!stopExisting) {
                NSDictionary *snapshot = [self activeSessionSnapshot];
                if (errorMessage) *errorMessage = @"A trace session is already active.";
                return snapshot;
            }
            [self stopTraceSession:self.activeSessionID errorMessage:nil];
        }

        NSArray *rawTargets = [options[@"methodTargets"] isKindOfClass:[NSArray class]] ? options[@"methodTargets"] : @[];
        NSMutableArray<NSDictionary *> *targets = [NSMutableArray new];
        for (NSDictionary *rawTarget in rawTargets) {
            if (![rawTarget isKindOfClass:[NSDictionary class]]) continue;
            NSString *className = VCTraceSafeString(rawTarget[@"className"] ?: rawTarget[@"class"] ?: rawTarget[@"targetClass"]);
            NSString *selector = VCTraceSafeString(rawTarget[@"selector"] ?: rawTarget[@"sel"] ?: rawTarget[@"method"]);
            if (className.length == 0 || selector.length == 0) continue;
            if ([VCPromptLeakGuard blockedToolReasonForClassName:className moduleName:nil].length > 0) {
                continue;
            }
            [targets addObject:@{
                @"className": className,
                @"selector": selector,
                @"isClassMethod": @(VCTraceSafeBool(rawTarget[@"isClassMethod"], NO))
            }];
            if (targets.count >= 8) break;
        }

        BOOL captureNetwork = VCTraceSafeBool(options[@"captureNetwork"], YES);
        BOOL captureUI = VCTraceSafeBool(options[@"captureUI"], YES);
        NSUInteger maxEvents = VCTraceSafeUnsigned(options[@"maxEvents"], 120, 500);
        NSString *sessionName = VCTraceSafeString(options[@"sessionName"] ?: options[@"name"] ?: options[@"title"]);
        if (sessionName.length == 0) sessionName = @"Runtime Trace";
        NSArray<NSDictionary *> *memoryWatches = [self _memoryWatchSpecsFromOptions:options];
        NSArray<NSDictionary *> *checkpointTriggers = [self _checkpointTriggerSpecsFromOptions:options];

        if (targets.count > 0) {
            NSString *reason = nil;
            if (![[VCCapabilityManager shared] canUseHookingWithReason:&reason]) {
                if (errorMessage) *errorMessage = reason ?: @"Hooking is unavailable for trace capture.";
                return nil;
            }
        }

        BOOL startedNetworkMonitoring = NO;
        if (captureNetwork && ![VCNetMonitor shared].isMonitoring) {
            [[VCNetMonitor shared] startMonitoring];
            startedNetworkMonitoring = YES;
        }

        NSMutableArray<VCHookItem *> *installedHooks = [NSMutableArray new];
        for (NSDictionary *target in targets) {
            VCHookItem *hookItem = [[VCHookItem alloc] init];
            hookItem.className = target[@"className"];
            hookItem.selector = target[@"selector"];
            hookItem.isClassMethod = [target[@"isClassMethod"] boolValue];
            hookItem.hookType = @"log";
            hookItem.remark = @"Temporary trace hook";
            hookItem.enabled = YES;
            hookItem.source = VCItemSourceAI;

            if (![[VCHookManager shared] installHook:hookItem]) {
                for (VCHookItem *installed in installedHooks) {
                    [[VCHookManager shared] removeHook:installed];
                }
                if (startedNetworkMonitoring) {
                    [[VCNetMonitor shared] stopMonitoring];
                }
                if (errorMessage) {
                    *errorMessage = [NSString stringWithFormat:@"Failed to install trace hook for %c[%@ %@]",
                                     hookItem.isClassMethod ? '+' : '-',
                                     hookItem.className ?: @"?",
                                     hookItem.selector ?: @"?"];
                }
                return nil;
            }
            [installedHooks addObject:hookItem];
        }

        NSString *sessionID = [[NSUUID UUID] UUIDString];
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        NSMutableDictionary *session = [@{
            @"sessionID": sessionID,
            @"name": sessionName,
            @"active": @YES,
            @"status": @"active",
            @"startedAt": @(now),
            @"stoppedAt": @0,
            @"captureNetwork": @(captureNetwork),
            @"captureUI": @(captureUI),
            @"maxEvents": @(maxEvents),
            @"methodTargets": [targets copy],
            @"memoryWatches": memoryWatches ?: @[],
            @"memoryWatchCount": @(memoryWatches.count),
            @"checkpointTriggers": checkpointTriggers ?: @[],
            @"checkpointTriggerCount": @(checkpointTriggers.count),
            @"checkpointCount": @0,
            @"autoCheckpointCount": @0,
            @"lastCheckpointLabel": @"",
            @"lastCheckpointAt": @0,
            @"hookIDs": [[installedHooks valueForKey:@"hookID"] copy] ?: @[],
            @"installedMethodCount": @(installedHooks.count),
            @"startedNetworkMonitoring": @(startedNetworkMonitoring),
            @"eventCount": @0,
            @"nextEventOrdinal": @0
        } mutableCopy];

        self.activeSessionID = sessionID;
        self.hooksBySession[sessionID] = [installedHooks copy];
        self.eventsBySession[sessionID] = [NSMutableArray new];
        [self.sessions insertObject:session atIndex:0];
        [self _saveState];
        [self _saveEventsForSessionID:sessionID];
        return [session copy];
    }
}

- (NSDictionary *)stopTraceSession:(NSString *)sessionID errorMessage:(NSString **)errorMessage {
    @synchronized (self) {
        NSString *resolvedSessionID = VCTraceSafeString(sessionID);
        if (resolvedSessionID.length == 0) resolvedSessionID = self.activeSessionID;
        if (resolvedSessionID.length == 0) {
            if (errorMessage) *errorMessage = @"No active trace session.";
            return nil;
        }

        NSMutableDictionary *session = [self _mutableSessionForID:resolvedSessionID];
        if (!session) {
            if (errorMessage) *errorMessage = @"Trace session not found.";
            return nil;
        }

        NSArray<VCHookItem *> *hooks = self.hooksBySession[resolvedSessionID] ?: @[];
        for (VCHookItem *hookItem in hooks) {
            [[VCHookManager shared] removeHook:hookItem];
        }
        [self.hooksBySession removeObjectForKey:resolvedSessionID];

        if ([session[@"startedNetworkMonitoring"] boolValue] && [VCNetMonitor shared].isMonitoring) {
            [[VCNetMonitor shared] stopMonitoring];
        }

        [self _finalizeMemoryWatchesForSession:session];
        session[@"active"] = @NO;
        session[@"status"] = @"stopped";
        session[@"stoppedAt"] = @([[NSDate date] timeIntervalSince1970]);
        session[@"installedMethodCount"] = @0;
        session[@"hookIDs"] = @[];
        if ([self.activeSessionID isEqualToString:resolvedSessionID]) {
            self.activeSessionID = nil;
        }

        [self _saveState];
        return [session copy];
    }
}

- (NSDictionary *)eventsSnapshotForSession:(NSString *)sessionID
                                     limit:(NSUInteger)limit
                                 kindNames:(NSArray<NSString *> *)kindNames {
    @synchronized (self) {
        NSString *resolvedSessionID = VCTraceSafeString(sessionID);
        if (resolvedSessionID.length == 0) resolvedSessionID = self.activeSessionID;
        NSMutableDictionary *session = [self _mutableSessionForID:resolvedSessionID];
        if (!session) return nil;

        NSArray<NSDictionary *> *events = self.eventsBySession[resolvedSessionID] ?: @[];
        NSMutableArray<NSDictionary *> *filtered = [NSMutableArray new];
        NSSet<NSString *> *kindFilter = nil;
        if ([kindNames isKindOfClass:[NSArray class]] && kindNames.count > 0) {
            NSMutableSet<NSString *> *lowerKinds = [NSMutableSet set];
            for (NSString *kind in kindNames) {
                NSString *safeKind = VCTraceSafeString(kind).lowercaseString;
                if (safeKind.length > 0) [lowerKinds addObject:safeKind];
            }
            kindFilter = [lowerKinds copy];
        }

        for (NSDictionary *event in events) {
            NSString *kind = [VCTraceSafeString(event[@"kind"]) lowercaseString];
            if (kindFilter && ![kindFilter containsObject:kind]) continue;
            [filtered addObject:event];
        }

        NSArray<NSDictionary *> *sortedEvents = [self _sortedEvents:filtered];
        NSUInteger includedAncestorCount = 0;
        NSArray<NSDictionary *> *selectedEvents = [self _selectedEventsFromSortedEvents:sortedEvents
                                                                                   limit:limit
                                                                   includedAncestorCount:&includedAncestorCount];
        NSDictionary *callTree = [self _callTreeSummaryForEvents:selectedEvents];

        return @{
            @"session": [session copy],
            @"returnedCount": @(selectedEvents.count),
            @"totalEvents": @(events.count),
            @"includedAncestorCount": @(includedAncestorCount),
            @"events": selectedEvents ?: @[],
            @"callTree": callTree ?: @{}
        };
    }
}

- (NSDictionary *)exportMermaidForSession:(NSString *)sessionID
                                    style:(NSString *)style
                                    title:(NSString *)title
                                    limit:(NSUInteger)limit
                             errorMessage:(NSString **)errorMessage {
    NSDictionary *snapshot = [self eventsSnapshotForSession:sessionID limit:limit kindNames:nil];
    if (!snapshot) {
        if (errorMessage) *errorMessage = @"Trace session not found.";
        return nil;
    }

    NSDictionary *session = snapshot[@"session"] ?: @{};
    NSArray<NSDictionary *> *events = snapshot[@"events"] ?: @[];
    if (events.count == 0) {
        if (errorMessage) *errorMessage = @"Trace session has no events to export.";
        return nil;
    }

    NSString *diagramTitle = VCTraceSafeString(title);
    if (diagramTitle.length == 0) {
        diagramTitle = VCTraceSafeString(session[@"name"]);
        if (diagramTitle.length == 0) diagramTitle = @"Trace Timeline";
    }

    NSString *diagramStyle = VCTraceSafeString(style).lowercaseString;
    if ([diagramStyle isEqualToString:@"calltree"] || [diagramStyle isEqualToString:@"tree"]) diagramStyle = @"call_tree";
    if (diagramStyle.length == 0) diagramStyle = @"sequence";

    NSMutableString *content = [NSMutableString new];
    NSMutableDictionary<NSString *, NSString *> *aliases = [NSMutableDictionary new];
    NSDictionary *callTree = [snapshot[@"callTree"] isKindOfClass:[NSDictionary class]] ? snapshot[@"callTree"] : @{};

    if ([diagramStyle isEqualToString:@"call_tree"]) {
        NSArray<NSDictionary *> *roots = [callTree[@"roots"] isKindOfClass:[NSArray class]] ? callTree[@"roots"] : @[];
        NSArray<NSDictionary *> *detachedEvents = [callTree[@"detachedEvents"] isKindOfClass:[NSArray class]] ? callTree[@"detachedEvents"] : @[];
        if (roots.count == 0) {
            if (detachedEvents.count == 0) {
                if (errorMessage) *errorMessage = @"Trace session has no method call tree to export.";
                return nil;
            }
        }

        [content appendString:@"flowchart TD\n"];
        [content appendString:@"    AppRoot[\"App\"]\n"];
        NSMutableDictionary<NSString *, NSString *> *nodeIDs = [NSMutableDictionary new];
        for (NSDictionary *root in roots) {
            [self _appendCallTreeNode:root
                           toContent:content
                        parentNodeID:@"AppRoot"
                             nodeIDs:nodeIDs];
        }
        NSUInteger detachedIndex = 1;
        for (NSDictionary *detachedEvent in detachedEvents) {
            NSString *nodeID = [NSString stringWithFormat:@"D%lu", (unsigned long)detachedIndex];
            NSString *label = VCTraceSafeString(detachedEvent[@"displayName"]);
            if (label.length == 0) label = VCTraceSafeString(detachedEvent[@"title"]);
            [content appendFormat:@"    %@[\"%@\"]\n", nodeID, VCTraceMermaidEscaped(label)];
            [content appendFormat:@"    AppRoot -.-> %@\n", nodeID];
            detachedIndex++;
        }
    } else if ([diagramStyle isEqualToString:@"flow"]) {
        [content appendString:@"flowchart TD\n"];
        NSUInteger index = 1;
        NSString *previousNode = nil;
        for (NSDictionary *event in events) {
            NSString *nodeID = [NSString stringWithFormat:@"E%lu", (unsigned long)index];
            NSString *label = [self _mermaidLabelForEvent:event];
            label = [[label stringByReplacingOccurrencesOfString:@"\"" withString:@"'"] stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
            [content appendFormat:@"    %@[\"%lu. %@\"]\n", nodeID, (unsigned long)index, label];
            if (previousNode) {
                [content appendFormat:@"    %@ --> %@\n", previousNode, nodeID];
            }
            previousNode = nodeID;
            index++;
        }
    } else {
        [content appendString:@"sequenceDiagram\n"];
        [content appendString:@"    autonumber\n"];
        [content appendString:@"    actor User\n"];
        [content appendString:@"    participant App\n"];

        for (NSDictionary *event in events) {
            NSString *kind = VCTraceSafeString(event[@"kind"]).lowercaseString;
            if ([kind isEqualToString:@"method"]) {
                NSString *className = VCTraceSafeString(event[@"className"]);
                NSString *alias = VCTraceMermaidAlias(className, aliases);
                [content appendFormat:@"    participant %@ as \"%@\"\n", alias, className];
            } else if ([kind isEqualToString:@"network"]) {
                NSString *host = VCTraceSafeString(event[@"host"]);
                if (host.length == 0) host = @"Network";
                NSString *alias = VCTraceMermaidAlias(host, aliases);
                [content appendFormat:@"    participant %@ as \"%@\"\n", alias, host];
            } else if ([kind isEqualToString:@"ui"]) {
                NSString *className = VCTraceSafeString(event[@"className"]);
                NSString *alias = VCTraceMermaidAlias(className, aliases);
                [content appendFormat:@"    participant %@ as \"%@\"\n", alias, className];
            } else if ([kind isEqualToString:@"memory"]) {
                NSString *label = VCTraceSafeString(event[@"label"]);
                if (label.length == 0) label = @"Memory";
                NSString *alias = VCTraceMermaidAlias(label, aliases);
                [content appendFormat:@"    participant %@ as \"%@\"\n", alias, label];
            } else if ([kind isEqualToString:@"checkpoint"]) {
                [content appendString:@"    participant Trace as \"Trace\"\n"];
            }
        }

        NSMutableSet<NSString *> *seenLines = [NSMutableSet set];
        NSArray<NSString *> *allLines = [content componentsSeparatedByString:@"\n"];
        NSMutableArray<NSString *> *dedupedLines = [NSMutableArray new];
        for (NSString *line in allLines) {
            if ([line containsString:@"participant "]) {
                if ([seenLines containsObject:line]) continue;
                [seenLines addObject:line];
            }
            [dedupedLines addObject:line];
        }
        content = [[dedupedLines componentsJoinedByString:@"\n"] mutableCopy];
        if (![content hasSuffix:@"\n"]) [content appendString:@"\n"];

        NSMutableDictionary<NSString *, NSDictionary *> *methodEventsByInvocationID = [NSMutableDictionary new];
        for (NSDictionary *event in events) {
            if (![VCTraceEventKind(event) isEqualToString:@"method"]) continue;
            NSString *invocationID = VCTraceSafeString(event[@"invocationID"]);
            if (invocationID.length == 0) continue;
            methodEventsByInvocationID[invocationID] = event;
        }

        for (NSDictionary *event in events) {
            NSString *kind = VCTraceSafeString(event[@"kind"]).lowercaseString;
            if ([kind isEqualToString:@"method"]) {
                NSString *className = VCTraceSafeString(event[@"className"]);
                NSString *alias = VCTraceMermaidAlias(className, aliases);
                NSString *selector = VCTraceSafeString(event[@"selector"]);
                NSString *prefix = [event[@"isClassMethod"] boolValue] ? @"+" : @"-";
                NSString *sourceAlias = @"App";
                NSString *parentInvocationID = VCTraceSafeString(event[@"parentInvocationID"]);
                NSDictionary *parentEvent = methodEventsByInvocationID[parentInvocationID];
                if ([parentEvent isKindOfClass:[NSDictionary class]]) {
                    NSString *parentClassName = VCTraceSafeString(parentEvent[@"className"]);
                    if (parentClassName.length > 0) {
                        sourceAlias = VCTraceMermaidAlias(parentClassName, aliases);
                    }
                }
                [content appendFormat:@"    %@->>%@: \"%@[%@ %@]\"\n", sourceAlias, alias, prefix, className, selector];
                NSString *returnValue = VCTraceSafeString(event[@"returnValue"]);
                if (returnValue.length > 0) {
                    NSString *truncated = returnValue.length > 80 ? [[returnValue substringToIndex:77] stringByAppendingString:@"..."] : returnValue;
                    truncated = [truncated stringByReplacingOccurrencesOfString:@"\"" withString:@"'"];
                    [content appendFormat:@"    %@-->>%@: \"%@\"\n", alias, sourceAlias, truncated];
                }
            } else if ([kind isEqualToString:@"network"]) {
                NSString *host = VCTraceSafeString(event[@"host"]);
                if (host.length == 0) host = @"Network";
                NSString *alias = VCTraceMermaidAlias(host, aliases);
                NSString *method = VCTraceSafeString(event[@"method"]);
                NSString *path = VCTraceSafeString(event[@"path"]);
                NSNumber *statusCode = event[@"statusCode"];
                NSString *sourceAlias = @"App";
                NSString *relatedInvocationID = VCTraceRelatedInvocationID(event);
                NSDictionary *relatedMethodEvent = methodEventsByInvocationID[relatedInvocationID];
                if ([relatedMethodEvent isKindOfClass:[NSDictionary class]]) {
                    NSString *relatedClassName = VCTraceSafeString(relatedMethodEvent[@"className"]);
                    if (relatedClassName.length > 0) {
                        sourceAlias = VCTraceMermaidAlias(relatedClassName, aliases);
                    }
                }
                [content appendFormat:@"    %@->>%@: \"%@ %@\"\n", sourceAlias, alias, method.length > 0 ? method : @"REQ", path.length > 0 ? path : @"/"];
                if ([statusCode respondsToSelector:@selector(integerValue)] && [statusCode integerValue] > 0) {
                    [content appendFormat:@"    %@-->>%@: \"%@\"\n", alias, sourceAlias, statusCode];
                }
            } else if ([kind isEqualToString:@"ui"]) {
                NSString *className = VCTraceSafeString(event[@"className"]);
                NSString *alias = VCTraceMermaidAlias(className, aliases);
                NSString *frame = VCTraceSafeString(event[@"frame"]);
                NSString *sourceAlias = @"User";
                NSString *relatedInvocationID = VCTraceRelatedInvocationID(event);
                NSDictionary *relatedMethodEvent = methodEventsByInvocationID[relatedInvocationID];
                if ([relatedMethodEvent isKindOfClass:[NSDictionary class]]) {
                    NSString *relatedClassName = VCTraceSafeString(relatedMethodEvent[@"className"]);
                    if (relatedClassName.length > 0) {
                        sourceAlias = VCTraceMermaidAlias(relatedClassName, aliases);
                    }
                }
                [content appendFormat:@"    %@->>%@: \"select %@\"\n", sourceAlias, alias, frame.length > 0 ? frame : className];
            } else if ([kind isEqualToString:@"memory"]) {
                NSString *label = VCTraceSafeString(event[@"label"]);
                if (label.length == 0) label = @"Memory";
                NSString *alias = VCTraceMermaidAlias(label, aliases);
                NSString *sourceAlias = @"App";
                NSString *typedBefore = VCTraceSafeString(event[@"typedBefore"]);
                NSString *typedAfter = VCTraceSafeString(event[@"typedAfter"]);
                NSString *message = nil;
                if (typedBefore.length > 0 || typedAfter.length > 0) {
                    message = [NSString stringWithFormat:@"%@ -> %@", typedBefore.length > 0 ? typedBefore : @"?", typedAfter.length > 0 ? typedAfter : @"?"];
                } else {
                    message = [NSString stringWithFormat:@"%@ bytes changed", event[@"changedByteCount"] ?: @0];
                }
                [content appendFormat:@"    %@->>%@: \"%@\"\n", sourceAlias, alias, VCTraceMermaidEscaped(message)];
            } else if ([kind isEqualToString:@"checkpoint"]) {
                NSString *sourceAlias = @"App";
                NSString *relatedInvocationID = VCTraceRelatedInvocationID(event);
                NSDictionary *relatedMethodEvent = methodEventsByInvocationID[relatedInvocationID];
                if ([relatedMethodEvent isKindOfClass:[NSDictionary class]]) {
                    NSString *relatedClassName = VCTraceSafeString(relatedMethodEvent[@"className"]);
                    if (relatedClassName.length > 0) {
                        sourceAlias = VCTraceMermaidAlias(relatedClassName, aliases);
                    }
                }
                NSString *message = [NSString stringWithFormat:@"%@ (%@ watches, %@ changed)",
                                     VCTraceSafeString(event[@"label"]),
                                     event[@"watchCount"] ?: @0,
                                     event[@"changedWatchCount"] ?: @0];
                [content appendFormat:@"    %@->>%@: \"%@\"\n", sourceAlias, @"Trace", VCTraceMermaidEscaped(message)];
            }
        }
    }

    NSString *summary = [NSString stringWithFormat:@"Generated %@ Mermaid for %lu trace events",
                         diagramStyle,
                         (unsigned long)events.count];
    return @{
        @"sessionID": session[@"sessionID"] ?: @"",
        @"diagramType": @"trace",
        @"title": diagramTitle,
        @"style": diagramStyle,
        @"content": [content copy],
        @"summary": summary,
        @"eventCount": @(events.count)
    };
}

- (NSDictionary *)activeSessionSnapshot {
    @synchronized (self) {
        NSMutableDictionary *session = [self _mutableSessionForID:self.activeSessionID];
        return session ? [session copy] : nil;
    }
}

- (NSArray<NSDictionary *> *)sessionSummariesWithLimit:(NSUInteger)limit {
    @synchronized (self) {
        NSUInteger effectiveLimit = limit > 0 ? MIN(limit, 100) : 20;
        NSMutableArray<NSDictionary *> *items = [NSMutableArray new];
        for (NSMutableDictionary *session in self.sessions ?: @[]) {
            NSString *sessionID = VCTraceSafeString(session[@"sessionID"]);
            NSArray<NSDictionary *> *events = sessionID.length > 0 ? (self.eventsBySession[sessionID] ?: @[]) : @[];
            [items addObject:@{
                @"sessionID": sessionID,
                @"name": VCTraceSafeString(session[@"name"]),
                @"status": VCTraceSafeString(session[@"status"]),
                @"active": session[@"active"] ?: @NO,
                @"startedAt": session[@"startedAt"] ?: @0,
                @"stoppedAt": session[@"stoppedAt"] ?: @0,
                @"eventCount": @(events.count),
                @"installedMethodCount": session[@"installedMethodCount"] ?: @0,
                @"memoryWatchCount": session[@"memoryWatchCount"] ?: @0,
                @"checkpointCount": session[@"checkpointCount"] ?: @0,
                @"autoCheckpointCount": session[@"autoCheckpointCount"] ?: @0,
                @"checkpointTriggerCount": session[@"checkpointTriggerCount"] ?: @0,
                @"lastCheckpointLabel": session[@"lastCheckpointLabel"] ?: @"",
                @"lastCheckpointAt": session[@"lastCheckpointAt"] ?: @0,
                @"captureNetwork": session[@"captureNetwork"] ?: @NO,
                @"captureUI": session[@"captureUI"] ?: @NO,
                @"eventsPath": sessionID.length > 0 ? [self _eventsPathForSessionID:sessionID] : @""
            }];
            if (items.count >= effectiveLimit) break;
        }
        return [items copy];
    }
}

- (NSDictionary *)sessionDetailForSession:(NSString *)sessionID
                               eventLimit:(NSUInteger)eventLimit {
    @synchronized (self) {
        NSString *resolvedSessionID = VCTraceSafeString(sessionID);
        if (resolvedSessionID.length == 0) resolvedSessionID = self.activeSessionID;
        NSMutableDictionary *session = [self _mutableSessionForID:resolvedSessionID];
        if (!session) return nil;

        NSArray<NSDictionary *> *events = self.eventsBySession[resolvedSessionID] ?: @[];
        NSArray<NSDictionary *> *sortedEvents = [self _sortedEvents:events];
        NSUInteger includedAncestorCount = 0;
        NSArray<NSDictionary *> *selectedEvents = [self _selectedEventsFromSortedEvents:sortedEvents
                                                                                   limit:eventLimit
                                                                   includedAncestorCount:&includedAncestorCount];
        NSDictionary *callTree = [self _callTreeSummaryForEvents:selectedEvents] ?: @{};

        NSMutableArray<NSDictionary *> *checkpoints = [NSMutableArray new];
        for (NSDictionary *event in [sortedEvents reverseObjectEnumerator]) {
            if (![VCTraceEventKind(event) isEqualToString:@"checkpoint"]) continue;
            [checkpoints addObject:@{
                @"eventID": VCTraceSafeString(event[@"eventID"]),
                @"label": VCTraceSafeString(event[@"label"]),
                @"timestamp": event[@"timestamp"] ?: @0,
                @"checkpointIndex": event[@"checkpointIndex"] ?: @0,
                @"changedWatchCount": event[@"changedWatchCount"] ?: @0,
                @"watchCount": event[@"watchCount"] ?: @0,
                @"automatic": event[@"automatic"] ?: @NO,
                @"triggerKind": event[@"triggerKind"] ?: @"",
                @"triggeringEventKind": event[@"triggeringEventKind"] ?: @"",
                @"triggeringEventTitle": event[@"triggeringEventTitle"] ?: @"",
                @"relatedInvocationID": VCTraceRelatedInvocationID(event),
                @"summary": VCTraceSafeString(event[@"summary"])
            }];
            if (checkpoints.count >= 40) break;
        }

        return @{
            @"session": [session copy],
            @"eventsPath": [self _eventsPathForSessionID:resolvedSessionID],
            @"returnedCount": @(selectedEvents.count),
            @"totalEvents": @(events.count),
            @"includedAncestorCount": @(includedAncestorCount),
            @"checkpoints": [checkpoints copy],
            @"checkpointCount": @(checkpoints.count),
            @"latestCheckpoint": checkpoints.firstObject ?: @{},
            @"events": selectedEvents ?: @[],
            @"callTree": callTree
        };
    }
}

#pragma mark - Notifications

- (void)_handleHookInvocation:(NSNotification *)notification {
    NSDictionary *userInfo = [notification.userInfo isKindOfClass:[NSDictionary class]] ? notification.userInfo : nil;
    if (!userInfo) return;

    @synchronized (self) {
        NSMutableDictionary *session = [self _mutableSessionForID:self.activeSessionID];
        if (!session || ![session[@"active"] boolValue]) return;
        NSArray<NSString *> *hookIDs = [session[@"hookIDs"] isKindOfClass:[NSArray class]] ? session[@"hookIDs"] : @[];
        NSString *hookID = VCTraceSafeString(userInfo[@"hookID"]);
        if (hookID.length == 0 || ![hookIDs containsObject:hookID]) return;
        NSString *className = VCTraceSafeString(userInfo[@"className"]);
        if ([VCPromptLeakGuard blockedToolReasonForClassName:className moduleName:nil].length > 0) return;
        BOOL didSanitize = NO;
        NSString *returnValue = [VCPromptLeakGuard sanitizedAssistantText:VCTraceSafeString(userInfo[@"returnValue"])
                                                             didSanitize:&didSanitize];

        NSDictionary *event = @{
            @"eventID": [[NSUUID UUID] UUIDString],
            @"kind": @"method",
            @"timestamp": userInfo[@"timestamp"] ?: @([[NSDate date] timeIntervalSince1970]),
            @"invocationID": VCTraceSafeString(userInfo[@"invocationID"]),
            @"parentInvocationID": VCTraceSafeString(userInfo[@"parentInvocationID"]),
            @"className": className,
            @"selector": VCTraceSafeString(userInfo[@"selector"]),
            @"isClassMethod": @([userInfo[@"isClassMethod"] boolValue]),
            @"callDepth": userInfo[@"callDepth"] ?: @0,
            @"threadID": userInfo[@"threadID"] ?: @0,
            @"startedAt": userInfo[@"startedAt"] ?: userInfo[@"timestamp"] ?: @0,
            @"endedAt": userInfo[@"endedAt"] ?: userInfo[@"timestamp"] ?: @0,
            @"returnValue": didSanitize ? @"[redacted]" : returnValue,
            @"durationMs": userInfo[@"durationMs"] ?: @0,
            @"title": [NSString stringWithFormat:@"%c[%@ %@]",
                       [userInfo[@"isClassMethod"] boolValue] ? '+' : '-',
                       className,
                       VCTraceSafeString(userInfo[@"selector"])],
            @"summary": [NSString stringWithFormat:@"%@ @ %@",
                         VCTraceSafeString(userInfo[@"selector"]),
                         VCTraceTimestampString([userInfo[@"timestamp"] doubleValue])]
        };
        [self _appendEvent:event toSession:session];
        [self _evaluateCheckpointTriggersForSession:session event:event];
    }
}

- (void)_handleNetworkRecord:(NSNotification *)notification {
    VCNetRecord *record = [notification.object isKindOfClass:[VCNetRecord class]] ? notification.object : nil;
    if (!record) return;

    @synchronized (self) {
        NSMutableDictionary *session = [self _mutableSessionForID:self.activeSessionID];
        if (!session || ![session[@"active"] boolValue] || ![session[@"captureNetwork"] boolValue]) return;

        NSURL *url = [NSURL URLWithString:record.url ?: @""];
        NSDictionary *traceContext = [record.traceContext isKindOfClass:[NSDictionary class]] ? record.traceContext : nil;
        NSString *relatedInvocationID = VCTraceSafeString(traceContext[@"currentInvocationID"]);
        NSString *relatedParentInvocationID = VCTraceSafeString(traceContext[@"parentInvocationID"]);
        NSString *relatedDisplayName = VCTraceSafeString(traceContext[@"currentDisplayName"]);
        NSDictionary *event = @{
            @"eventID": [[NSUUID UUID] UUIDString],
            @"kind": @"network",
            @"timestamp": @([[NSDate date] timeIntervalSince1970]),
            @"method": record.method ?: @"GET",
            @"url": record.url ?: @"",
            @"host": url.host ?: @"",
            @"path": url.path.length > 0 ? url.path : @"/",
            @"statusCode": @(record.statusCode),
            @"durationMs": @((NSUInteger)llround(record.duration * 1000.0)),
            @"relatedInvocationID": relatedInvocationID ?: @"",
            @"relatedParentInvocationID": relatedParentInvocationID ?: @"",
            @"relatedDisplayName": relatedDisplayName ?: @"",
            @"relatedThreadID": traceContext[@"threadID"] ?: @0,
            @"correlationType": relatedInvocationID.length > 0 ? @"captured_context" : @"none",
            @"title": [NSString stringWithFormat:@"%@ %@", record.method ?: @"REQ", url.host ?: @"request"],
            @"summary": [NSString stringWithFormat:@"%@ %@ (%@)", record.method ?: @"REQ", url.path.length > 0 ? url.path : @"/", @(record.statusCode)]
        };
        [self _appendEvent:event toSession:session];
        [self _evaluateCheckpointTriggersForSession:session event:event];
    }
}

- (void)_handleUISelection:(NSNotification *)notification {
    NSDictionary *userInfo = [notification.userInfo isKindOfClass:[NSDictionary class]] ? notification.userInfo : nil;
    if (!userInfo) return;
    NSString *className = VCTraceSafeString(userInfo[@"className"]);
    if (className.length == 0) return;

    @synchronized (self) {
        NSMutableDictionary *session = [self _mutableSessionForID:self.activeSessionID];
        if (!session || ![session[@"active"] boolValue] || ![session[@"captureUI"] boolValue]) return;

        NSDictionary *traceContext = [userInfo[@"traceContext"] isKindOfClass:[NSDictionary class]] ? userInfo[@"traceContext"] : nil;
        NSString *relatedInvocationID = VCTraceSafeString(traceContext[@"currentInvocationID"]);
        NSString *relatedParentInvocationID = VCTraceSafeString(traceContext[@"parentInvocationID"]);
        NSString *relatedDisplayName = VCTraceSafeString(traceContext[@"currentDisplayName"]);
        NSDictionary *event = @{
            @"eventID": [[NSUUID UUID] UUIDString],
            @"kind": @"ui",
            @"timestamp": @([[NSDate date] timeIntervalSince1970]),
            @"className": className,
            @"address": VCTraceSafeString(userInfo[@"address"]),
            @"frame": VCTraceSafeString(userInfo[@"frame"]),
            @"relatedInvocationID": relatedInvocationID ?: @"",
            @"relatedParentInvocationID": relatedParentInvocationID ?: @"",
            @"relatedDisplayName": relatedDisplayName ?: @"",
            @"relatedThreadID": traceContext[@"threadID"] ?: @0,
            @"correlationType": relatedInvocationID.length > 0 ? @"captured_context" : @"none",
            @"title": [NSString stringWithFormat:@"Select %@", className],
            @"summary": [NSString stringWithFormat:@"%@ %@", className, VCTraceSafeString(userInfo[@"address"])]
        };
        [self _appendEvent:event toSession:session];
        [self _evaluateCheckpointTriggersForSession:session event:event];
    }
}

#pragma mark - Persistence

- (NSString *)_traceDirectory {
    return [[[VCConfig shared] sessionsPath] stringByAppendingPathComponent:@"traces"];
}

- (NSString *)_traceIndexPath {
    return [[self _traceDirectory] stringByAppendingPathComponent:@"index.json"];
}

- (NSString *)_eventsPathForSessionID:(NSString *)sessionID {
    return [[self _traceDirectory] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.events.json", sessionID ?: @"trace"]];
}

- (void)_ensureTraceDirectory {
    [[NSFileManager defaultManager] createDirectoryAtPath:[self _traceDirectory]
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
}

- (void)_loadState {
    NSData *data = [NSData dataWithContentsOfFile:[self _traceIndexPath]];
    NSArray *rawSessions = data ? [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil] : nil;
    if (![rawSessions isKindOfClass:[NSArray class]]) return;

    for (NSDictionary *sessionDict in rawSessions) {
        if (![sessionDict isKindOfClass:[NSDictionary class]]) continue;
        NSMutableDictionary *session = [sessionDict mutableCopy];
        if ([session[@"active"] boolValue]) {
            session[@"active"] = @NO;
            session[@"status"] = @"interrupted";
            if (![session[@"stoppedAt"] respondsToSelector:@selector(doubleValue)] || [session[@"stoppedAt"] doubleValue] == 0) {
                session[@"stoppedAt"] = @([[NSDate date] timeIntervalSince1970]);
            }
        }
        [self.sessions addObject:session];

        NSString *sessionID = VCTraceSafeString(session[@"sessionID"]);
        if (sessionID.length == 0) continue;
        NSData *eventsData = [NSData dataWithContentsOfFile:[self _eventsPathForSessionID:sessionID]];
        NSArray *rawEvents = eventsData ? [NSJSONSerialization JSONObjectWithData:eventsData options:NSJSONReadingMutableContainers error:nil] : nil;
        self.eventsBySession[sessionID] = [rawEvents isKindOfClass:[NSArray class]] ? [rawEvents mutableCopy] : [NSMutableArray new];
    }
    [self _saveState];
}

- (void)_saveState {
    NSData *data = [NSJSONSerialization dataWithJSONObject:self.sessions options:NSJSONWritingPrettyPrinted error:nil];
    [data writeToFile:[self _traceIndexPath] atomically:YES];
}

- (void)_saveEventsForSessionID:(NSString *)sessionID {
    if (sessionID.length == 0) return;
    NSArray *events = self.eventsBySession[sessionID] ?: @[];
    NSData *data = [NSJSONSerialization dataWithJSONObject:events options:NSJSONWritingPrettyPrinted error:nil];
    [data writeToFile:[self _eventsPathForSessionID:sessionID] atomically:YES];
}

#pragma mark - Helpers

- (NSMutableDictionary *)_mutableSessionForID:(NSString *)sessionID {
    if (sessionID.length == 0) return nil;
    for (NSMutableDictionary *session in self.sessions) {
        if ([session[@"sessionID"] isEqualToString:sessionID]) return session;
    }
    return nil;
}

- (void)_appendEvent:(NSDictionary *)event toSession:(NSMutableDictionary *)session {
    NSString *sessionID = VCTraceSafeString(session[@"sessionID"]);
    if (sessionID.length == 0 || ![event isKindOfClass:[NSDictionary class]]) return;

    NSMutableDictionary *eventCopy = [event mutableCopy] ?: [NSMutableDictionary new];
    NSUInteger nextOrdinal = VCTraceSafeUnsigned(session[@"nextEventOrdinal"], 0, NSUIntegerMax - 1) + 1;
    if (![eventCopy[@"ordinal"] respondsToSelector:@selector(unsignedIntegerValue)]) {
        eventCopy[@"ordinal"] = @(nextOrdinal);
    } else {
        nextOrdinal = MAX(nextOrdinal, [eventCopy[@"ordinal"] unsignedIntegerValue]);
    }

    NSMutableArray<NSDictionary *> *events = self.eventsBySession[sessionID];
    if (!events) {
        events = [NSMutableArray new];
        self.eventsBySession[sessionID] = events;
    }
    [events addObject:[eventCopy copy]];

    NSUInteger maxEvents = VCTraceSafeUnsigned(session[@"maxEvents"], 120, 500);
    if (events.count > maxEvents) {
        NSUInteger overflow = events.count - maxEvents;
        [events removeObjectsInRange:NSMakeRange(0, overflow)];
    }

    session[@"eventCount"] = @(events.count);
    session[@"nextEventOrdinal"] = @(nextOrdinal);
    [self _saveEventsForSessionID:sessionID];
    [self _saveState];
}

- (NSString *)_mermaidLabelForEvent:(NSDictionary *)event {
    NSString *kind = VCTraceSafeString(event[@"kind"]).lowercaseString;
    if ([kind isEqualToString:@"method"]) {
        return [NSString stringWithFormat:@"%@ • %@ • %@ms",
                VCTraceMethodDisplayName(event),
                VCTraceTimestampString(VCTraceEventSortTimestamp(event)),
                event[@"durationMs"] ?: @0];
    }
    if ([kind isEqualToString:@"network"]) {
        return [NSString stringWithFormat:@"%@ • %@ • %@",
                VCTraceSafeString(event[@"title"]),
                VCTraceSafeString(event[@"path"]),
                event[@"statusCode"] ?: @0];
    }
    if ([kind isEqualToString:@"ui"]) {
        return [NSString stringWithFormat:@"%@ • %@",
                VCTraceSafeString(event[@"title"]),
                VCTraceSafeString(event[@"frame"])];
    }
    if ([kind isEqualToString:@"memory"]) {
        NSString *typedBefore = VCTraceSafeString(event[@"typedBefore"]);
        NSString *typedAfter = VCTraceSafeString(event[@"typedAfter"]);
        if (typedBefore.length > 0 || typedAfter.length > 0) {
            return [NSString stringWithFormat:@"%@ • %@ -> %@",
                    VCTraceSafeString(event[@"title"]),
                    typedBefore.length > 0 ? typedBefore : @"?",
                    typedAfter.length > 0 ? typedAfter : @"?"];
        }
        return [NSString stringWithFormat:@"%@ • %@ bytes changed",
                VCTraceSafeString(event[@"title"]),
                event[@"changedByteCount"] ?: @0];
    }
    if ([kind isEqualToString:@"checkpoint"]) {
        return [NSString stringWithFormat:@"%@ • %@ watches • %@ changed",
                VCTraceSafeString(event[@"title"]),
                event[@"watchCount"] ?: @0,
                event[@"changedWatchCount"] ?: @0];
    }
    return VCTraceSafeString(event[@"title"]);
}

static NSUInteger VCTraceByteSizeForEncoding(NSString *encoding) {
    NSString *trimmed = VCTraceSafeString(encoding);
    if (trimmed.length == 0) return 0;
    unichar type = [trimmed characterAtIndex:0];
    switch (type) {
        case 'c':
        case 'C':
        case 'B':
            return sizeof(char);
        case 's':
        case 'S':
            return sizeof(short);
        case 'i':
        case 'I':
            return sizeof(int);
        case 'l':
        case 'L':
            return sizeof(long);
        case 'q':
        case 'Q':
            return sizeof(long long);
        case 'f':
            return sizeof(float);
        case 'd':
            return sizeof(double);
        case '^':
        case '?':
            return sizeof(void *);
        case '{': {
            if ([trimmed hasPrefix:@"{CGPoint"]) return sizeof(CGPoint);
            if ([trimmed hasPrefix:@"{CGSize"]) return sizeof(CGSize);
            if ([trimmed hasPrefix:@"{CGRect"]) return sizeof(CGRect);
            if ([trimmed hasPrefix:@"{CGAffineTransform"]) return sizeof(CGAffineTransform);
            if ([trimmed hasPrefix:@"{UIEdgeInsets"]) return sizeof(UIEdgeInsets);
            if ([trimmed hasPrefix:@"{NSRange"] || [trimmed hasPrefix:@"{_NSRange"]) return sizeof(NSRange);
            return 0;
        }
        default:
            return 0;
    }
}

static BOOL VCTraceEncodingIsSafeForRawRead(NSString *encoding) {
    NSString *trimmed = VCTraceSafeString(encoding);
    if (trimmed.length == 0) return NO;
    unichar type = [trimmed characterAtIndex:0];
    switch (type) {
        case 'c':
        case 'C':
        case 's':
        case 'S':
        case 'i':
        case 'I':
        case 'l':
        case 'L':
        case 'q':
        case 'Q':
        case 'f':
        case 'd':
        case 'B':
        case '^':
        case '?':
        case '{':
            return YES;
        default:
            return NO;
    }
}

static NSString *VCTraceHexStringFromData(NSData *data) {
    if (![data isKindOfClass:[NSData class]] || data.length == 0) return @"";
    const unsigned char *bytes = (const unsigned char *)data.bytes;
    NSMutableString *hex = [NSMutableString stringWithCapacity:data.length * 2];
    for (NSUInteger idx = 0; idx < data.length; idx++) {
        [hex appendFormat:@"%02x", bytes[idx]];
    }
    return hex;
}

static NSData *VCTraceDataFromHexString(NSString *hexString) {
    NSString *hex = [[VCTraceSafeString(hexString) lowercaseString] copy];
    if (hex.length == 0 || (hex.length % 2) != 0) return nil;

    NSMutableData *data = [NSMutableData dataWithCapacity:(hex.length / 2)];
    for (NSUInteger idx = 0; idx < hex.length; idx += 2) {
        NSString *chunk = [hex substringWithRange:NSMakeRange(idx, 2)];
        unsigned int value = 0;
        if (![[NSScanner scannerWithString:chunk] scanHexInt:&value]) return nil;
        unsigned char byte = (unsigned char)value;
        [data appendBytes:&byte length:1];
    }
    return [data copy];
}

- (NSArray<NSDictionary *> *)_sortedEvents:(NSArray<NSDictionary *> *)events {
    return [events ?: @[] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *lhs, NSDictionary *rhs) {
        NSTimeInterval leftTime = VCTraceEventSortTimestamp(lhs);
        NSTimeInterval rightTime = VCTraceEventSortTimestamp(rhs);
        if (leftTime < rightTime) return NSOrderedAscending;
        if (leftTime > rightTime) return NSOrderedDescending;

        NSString *leftID = VCTraceSafeString(lhs[@"eventID"]);
        NSString *rightID = VCTraceSafeString(rhs[@"eventID"]);
        NSUInteger leftOrdinal = [lhs[@"ordinal"] respondsToSelector:@selector(unsignedIntegerValue)] ? [lhs[@"ordinal"] unsignedIntegerValue] : 0;
        NSUInteger rightOrdinal = [rhs[@"ordinal"] respondsToSelector:@selector(unsignedIntegerValue)] ? [rhs[@"ordinal"] unsignedIntegerValue] : 0;
        if (leftOrdinal > 0 || rightOrdinal > 0) {
            if (leftOrdinal < rightOrdinal) return NSOrderedAscending;
            if (leftOrdinal > rightOrdinal) return NSOrderedDescending;
        }
        return [leftID compare:rightID];
    }];
}

- (NSArray<NSDictionary *> *)_selectedEventsFromSortedEvents:(NSArray<NSDictionary *> *)sortedEvents
                                                       limit:(NSUInteger)limit
                                       includedAncestorCount:(NSUInteger *)includedAncestorCount {
    NSUInteger effectiveLimit = limit > 0 ? MIN(limit, 300) : 60;
    NSMutableArray<NSDictionary *> *selected = [NSMutableArray new];
    if (sortedEvents.count > effectiveLimit) {
        [selected addObjectsFromArray:[sortedEvents subarrayWithRange:NSMakeRange(sortedEvents.count - effectiveLimit, effectiveLimit)]];
    } else {
        [selected addObjectsFromArray:sortedEvents ?: @[]];
    }

    NSMutableSet<NSString *> *selectedEventIDs = [NSMutableSet set];
    for (NSDictionary *event in selected) {
        NSString *eventID = VCTraceSafeString(event[@"eventID"]);
        if (eventID.length > 0) [selectedEventIDs addObject:eventID];
    }

    NSMutableDictionary<NSString *, NSDictionary *> *eventsByInvocationID = [NSMutableDictionary new];
    for (NSDictionary *event in sortedEvents ?: @[]) {
        NSString *invocationID = VCTraceSafeString(event[@"invocationID"]);
        if (invocationID.length > 0) {
            eventsByInvocationID[invocationID] = event;
        }
    }

    NSUInteger ancestorCount = 0;
    for (NSDictionary *event in [selected copy]) {
        NSString *anchorInvocationID = VCTraceRelatedInvocationID(event);
        NSDictionary *anchorEvent = eventsByInvocationID[anchorInvocationID];
        NSString *parentInvocationID = nil;
        if ([VCTraceEventKind(event) isEqualToString:@"method"]) {
            parentInvocationID = VCTraceSafeString(event[@"parentInvocationID"]);
        } else {
            if ([anchorEvent isKindOfClass:[NSDictionary class]]) {
                NSString *anchorEventID = VCTraceSafeString(anchorEvent[@"eventID"]);
                if (anchorEventID.length > 0 && ![selectedEventIDs containsObject:anchorEventID]) {
                    [selected addObject:anchorEvent];
                    [selectedEventIDs addObject:anchorEventID];
                    ancestorCount++;
                }
                parentInvocationID = VCTraceSafeString(anchorEvent[@"parentInvocationID"]);
            }
        }

        while (parentInvocationID.length > 0) {
            NSDictionary *ancestor = eventsByInvocationID[parentInvocationID];
            if (![ancestor isKindOfClass:[NSDictionary class]]) break;

            NSString *ancestorEventID = VCTraceSafeString(ancestor[@"eventID"]);
            if (ancestorEventID.length == 0) break;
            if (![selectedEventIDs containsObject:ancestorEventID]) {
                [selected addObject:ancestor];
                [selectedEventIDs addObject:ancestorEventID];
                ancestorCount++;
            }
            parentInvocationID = VCTraceSafeString(ancestor[@"parentInvocationID"]);
        }
    }

    if (includedAncestorCount) *includedAncestorCount = ancestorCount;
    return [self _sortedEvents:selected];
}

- (NSDictionary *)_callTreeSummaryForEvents:(NSArray<NSDictionary *> *)events {
    NSMutableDictionary<NSString *, NSMutableDictionary *> *nodesByInvocationID = [NSMutableDictionary new];
    NSMutableArray<NSMutableDictionary *> *orderedNodes = [NSMutableArray new];
    NSUInteger maxDepth = 0;

    for (NSDictionary *event in events ?: @[]) {
        if (![VCTraceEventKind(event) isEqualToString:@"method"]) continue;
        NSString *invocationID = VCTraceSafeString(event[@"invocationID"]);
        if (invocationID.length == 0) continue;

        NSUInteger depth = [event[@"callDepth"] respondsToSelector:@selector(unsignedIntegerValue)] ? [event[@"callDepth"] unsignedIntegerValue] : 0;
        maxDepth = MAX(maxDepth, depth);
        NSMutableDictionary *node = [@{
            @"eventID": VCTraceSafeString(event[@"eventID"]),
            @"invocationID": invocationID,
            @"parentInvocationID": VCTraceSafeString(event[@"parentInvocationID"]),
            @"className": VCTraceSafeString(event[@"className"]),
            @"selector": VCTraceSafeString(event[@"selector"]),
            @"displayName": VCTraceMethodDisplayName(event),
            @"summary": VCTraceSafeString(event[@"summary"]),
            @"threadID": event[@"threadID"] ?: @0,
            @"depth": @(depth),
            @"durationMs": event[@"durationMs"] ?: @0,
            @"startedAt": event[@"startedAt"] ?: event[@"timestamp"] ?: @0,
            @"endedAt": event[@"endedAt"] ?: event[@"timestamp"] ?: @0,
            @"relatedEvents": [NSMutableArray new],
            @"children": [NSMutableArray new]
        } mutableCopy];
        nodesByInvocationID[invocationID] = node;
        [orderedNodes addObject:node];
    }

    NSMutableArray<NSMutableDictionary *> *roots = [NSMutableArray new];
    NSMutableArray<NSDictionary *> *edges = [NSMutableArray new];
    NSMutableArray<NSDictionary *> *relatedEventEdges = [NSMutableArray new];
    NSMutableArray<NSDictionary *> *detachedEvents = [NSMutableArray new];
    NSUInteger linkedMethodCount = 0;
    NSUInteger orphanedMethodCount = 0;
    NSUInteger relatedEventCount = 0;
    NSUInteger unlinkedRelatedEventCount = 0;
    for (NSMutableDictionary *node in orderedNodes) {
        NSString *parentInvocationID = VCTraceSafeString(node[@"parentInvocationID"]);
        NSMutableDictionary *parentNode = nodesByInvocationID[parentInvocationID];
        if (parentNode) {
            [(NSMutableArray *)parentNode[@"children"] addObject:node];
            [edges addObject:@{
                @"parentInvocationID": parentInvocationID,
                @"childInvocationID": node[@"invocationID"] ?: @"",
                @"parentDisplayName": parentNode[@"displayName"] ?: @"",
                @"childDisplayName": node[@"displayName"] ?: @""
            }];
            linkedMethodCount++;
        } else {
            [roots addObject:node];
            if (parentInvocationID.length > 0) orphanedMethodCount++;
        }
    }

    for (NSDictionary *event in events ?: @[]) {
        NSString *kind = VCTraceEventKind(event);
        if ([kind isEqualToString:@"method"]) continue;

        NSString *relatedInvocationID = VCTraceRelatedInvocationID(event);
        NSMutableDictionary *parentNode = nodesByInvocationID[relatedInvocationID];
        if (!parentNode) {
            NSMutableDictionary *detachedEvent = [@{
                @"eventID": VCTraceSafeString(event[@"eventID"]),
                @"kind": kind,
                @"title": VCTraceSafeString(event[@"title"]),
                @"summary": VCTraceSafeString(event[@"summary"]),
                @"displayName": VCTraceMermaidEscaped([self _mermaidLabelForEvent:event]),
                @"timestamp": event[@"timestamp"] ?: @0
            } mutableCopy];
            if ([kind isEqualToString:@"memory"]) {
                detachedEvent[@"address"] = VCTraceSafeString(event[@"address"]);
            } else if ([kind isEqualToString:@"checkpoint"]) {
                detachedEvent[@"label"] = VCTraceSafeString(event[@"label"]);
                detachedEvent[@"watchCount"] = event[@"watchCount"] ?: @0;
                detachedEvent[@"changedWatchCount"] = event[@"changedWatchCount"] ?: @0;
            }
            [detachedEvents addObject:[detachedEvent copy]];
            if (relatedInvocationID.length > 0) unlinkedRelatedEventCount++;
            continue;
        }

        NSMutableDictionary *relatedEvent = [@{
            @"eventID": VCTraceSafeString(event[@"eventID"]),
            @"kind": kind,
            @"title": VCTraceSafeString(event[@"title"]),
            @"summary": VCTraceSafeString(event[@"summary"]),
            @"displayName": kind.length > 0 ? VCTraceMermaidEscaped([self _mermaidLabelForEvent:event]) : VCTraceSafeString(event[@"title"]),
            @"timestamp": event[@"timestamp"] ?: @0,
            @"durationMs": event[@"durationMs"] ?: @0,
            @"relatedInvocationID": relatedInvocationID ?: @"",
            @"relatedDisplayName": VCTraceRelatedDisplayName(event),
        } mutableCopy];
        if ([kind isEqualToString:@"network"]) {
            relatedEvent[@"host"] = VCTraceSafeString(event[@"host"]);
            relatedEvent[@"path"] = VCTraceSafeString(event[@"path"]);
            relatedEvent[@"statusCode"] = event[@"statusCode"] ?: @0;
        } else if ([kind isEqualToString:@"ui"]) {
            relatedEvent[@"className"] = VCTraceSafeString(event[@"className"]);
            relatedEvent[@"frame"] = VCTraceSafeString(event[@"frame"]);
        } else if ([kind isEqualToString:@"checkpoint"]) {
            relatedEvent[@"label"] = VCTraceSafeString(event[@"label"]);
            relatedEvent[@"watchCount"] = event[@"watchCount"] ?: @0;
            relatedEvent[@"changedWatchCount"] = event[@"changedWatchCount"] ?: @0;
        }

        [(NSMutableArray *)parentNode[@"relatedEvents"] addObject:relatedEvent];
        [relatedEventEdges addObject:@{
            @"parentInvocationID": relatedInvocationID,
            @"eventID": VCTraceSafeString(event[@"eventID"]),
            @"kind": kind,
            @"parentDisplayName": parentNode[@"displayName"] ?: @"",
            @"eventDisplayName": relatedEvent[@"displayName"] ?: @""
        }];
        relatedEventCount++;
    }

    return @{
        @"methodEventCount": @(orderedNodes.count),
        @"linkedMethodCount": @(linkedMethodCount),
        @"orphanedMethodCount": @(orphanedMethodCount),
        @"relatedEventCount": @(relatedEventCount),
        @"unlinkedRelatedEventCount": @(unlinkedRelatedEventCount),
        @"detachedEventCount": @(detachedEvents.count),
        @"rootCount": @(roots.count),
        @"maxDepth": @(maxDepth),
        @"roots": VCTraceFrozenCallNodes(roots),
        @"edges": [edges copy],
        @"relatedEventEdges": [relatedEventEdges copy],
        @"detachedEvents": VCTraceFrozenRelatedEvents(detachedEvents)
    };
}

- (void)_appendCallTreeNode:(NSDictionary *)node
                  toContent:(NSMutableString *)content
               parentNodeID:(NSString *)parentNodeID
                    nodeIDs:(NSMutableDictionary<NSString *, NSString *> *)nodeIDs {
    NSString *invocationID = VCTraceSafeString(node[@"invocationID"]);
    NSString *nodeID = nodeIDs[invocationID];
    if (nodeID.length == 0) {
        nodeID = [NSString stringWithFormat:@"M%lu", (unsigned long)nodeIDs.count + 1];
        if (invocationID.length > 0) nodeIDs[invocationID] = nodeID;
    }

    NSString *label = [NSString stringWithFormat:@"%@ • %@ms",
                       VCTraceSafeString(node[@"displayName"]),
                       node[@"durationMs"] ?: @0];
    [content appendFormat:@"    %@[\"%@\"]\n", nodeID, VCTraceMermaidEscaped(label)];
    if (parentNodeID.length > 0) {
        [content appendFormat:@"    %@ --> %@\n", parentNodeID, nodeID];
    }

    NSUInteger relatedIndex = 1;
    for (NSDictionary *relatedEvent in node[@"relatedEvents"] ?: @[]) {
        NSString *relatedNodeID = [NSString stringWithFormat:@"%@R%lu", nodeID, (unsigned long)relatedIndex];
        NSString *relatedLabel = VCTraceSafeString(relatedEvent[@"displayName"]);
        if (relatedLabel.length == 0) relatedLabel = VCTraceSafeString(relatedEvent[@"title"]);
        [content appendFormat:@"    %@[\"%@\"]\n", relatedNodeID, VCTraceMermaidEscaped(relatedLabel)];
        [content appendFormat:@"    %@ -.-> %@\n", nodeID, relatedNodeID];
        relatedIndex++;
    }

    for (NSDictionary *child in node[@"children"] ?: @[]) {
        [self _appendCallTreeNode:child
                        toContent:content
                     parentNodeID:nodeID
                          nodeIDs:nodeIDs];
    }
}

@end
