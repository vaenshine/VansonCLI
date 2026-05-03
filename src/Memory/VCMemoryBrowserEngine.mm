/**
 * VCMemoryBrowserEngine -- paged memory browsing bridge over memory IO
 */

#import "VCMemoryBrowserEngine.h"
#import "../Process/VCProcessInfo.h"
#import "../AI/Security/VCPromptLeakGuard.h"
#import "../Vendor/MemoryBackend/Engine/VCMemEngine.h"

static NSString *VCMemoryBrowserHexAddress(uint64_t address) {
    return [NSString stringWithFormat:@"0x%llx", (unsigned long long)address];
}

static NSString *VCMemoryBrowserTrimmedString(id value) {
    if ([value isKindOfClass:[NSString class]]) {
        return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        return [[(NSNumber *)value stringValue] copy];
    }
    return @"";
}

static NSUInteger VCMemoryBrowserClampedSize(NSUInteger value, NSUInteger fallbackValue, NSUInteger minValue, NSUInteger maxValue) {
    NSUInteger resolved = value > 0 ? value : fallbackValue;
    resolved = MAX(resolved, minValue);
    resolved = MIN(resolved, maxValue);
    return resolved;
}

@interface VCMemoryBrowserEngine ()
@property (nonatomic, copy) NSString *sessionID;
@property (nonatomic, assign) uint64_t currentAddress;
@property (nonatomic, assign) NSUInteger currentPageSize;
@property (nonatomic, assign) NSTimeInterval updatedAt;
@end

@implementation VCMemoryBrowserEngine

+ (instancetype)shared {
    static VCMemoryBrowserEngine *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VCMemoryBrowserEngine alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        [[VCMemEngine shared] initialize];
        _currentPageSize = 256;
    }
    return self;
}

- (BOOL)hasActiveSession {
    return self.sessionID.length > 0;
}

- (NSDictionary *)activeSessionSummary {
    NSMutableDictionary *payload = [@{
        @"active": @([self hasActiveSession]),
        @"sessionID": self.sessionID ?: @"",
        @"currentAddress": [self hasActiveSession] ? VCMemoryBrowserHexAddress(self.currentAddress) : @"",
        @"pageSize": @(self.currentPageSize),
        @"updatedAt": @(self.updatedAt)
    } mutableCopy];
    if (![self hasActiveSession]) {
        payload[@"message"] = @"No active memory browser session.";
    }
    return [payload copy];
}

- (NSDictionary *)browseAtAddress:(uint64_t)address
                         pageSize:(NSUInteger)pageSize
                           length:(NSUInteger)length
                    updateSession:(BOOL)updateSession
                     errorMessage:(NSString * _Nullable * _Nullable)errorMessage {
    if (address == 0) {
        if (errorMessage) *errorMessage = @"Memory browser requires a non-zero address.";
        return nil;
    }

    VCMemRegion *region = [self _regionForAddress:address];
    if (!region) {
        if (errorMessage) *errorMessage = [NSString stringWithFormat:@"No readable memory region contains %@", VCMemoryBrowserHexAddress(address)];
        return nil;
    }
    if ([region.protection rangeOfString:@"r"].location == NSNotFound) {
        if (errorMessage) *errorMessage = [NSString stringWithFormat:@"Memory region %@ is not readable.", region.protection ?: @"---"];
        return nil;
    }

    NSString *moduleName = nil;
    uint64_t rva = [[VCProcessInfo shared] runtimeToRva:address module:&moduleName];
    NSString *blockedReason = [VCPromptLeakGuard blockedToolReasonForMemoryModuleName:moduleName address:address];
    if (blockedReason.length > 0) {
        if (errorMessage) *errorMessage = blockedReason;
        return nil;
    }

    NSUInteger normalizedPageSize = VCMemoryBrowserClampedSize(pageSize, self.currentPageSize ?: 256, 32, 1024);
    uint64_t availableBytes = region.end > address ? (region.end - address) : 0;
    if (availableBytes == 0) {
        if (errorMessage) *errorMessage = [NSString stringWithFormat:@"Address %@ is at the end of its memory region.", VCMemoryBrowserHexAddress(address)];
        return nil;
    }

    NSUInteger requestedLength = VCMemoryBrowserClampedSize(length, normalizedPageSize, 16, normalizedPageSize);
    NSUInteger readLength = (NSUInteger)MIN((uint64_t)requestedLength, availableBytes);
    NSData *data = [[VCMemEngine shared] readMemory:address length:readLength];
    if (!data || data.length == 0) {
        if (errorMessage) *errorMessage = [NSString stringWithFormat:@"Failed to read %lu bytes at %@.",
                                           (unsigned long)readLength,
                                           VCMemoryBrowserHexAddress(address)];
        return nil;
    }

    if (updateSession) {
        if (self.sessionID.length == 0) self.sessionID = [[NSUUID UUID] UUIDString];
        self.currentAddress = address;
        self.currentPageSize = normalizedPageSize;
        self.updatedAt = [[NSDate date] timeIntervalSince1970];
    }

    NSMutableDictionary *payload = [NSMutableDictionary new];
    payload[@"address"] = VCMemoryBrowserHexAddress(address);
    payload[@"pageSize"] = @(normalizedPageSize);
    payload[@"requestedLength"] = @(requestedLength);
    payload[@"readLength"] = @(data.length);
    payload[@"region"] = @{
        @"start": VCMemoryBrowserHexAddress(region.start),
        @"end": VCMemoryBrowserHexAddress(region.end),
        @"size": @(region.size),
        @"protection": region.protection ?: @"---"
    };
    payload[@"moduleName"] = moduleName ?: @"";
    payload[@"rva"] = rva > 0 ? VCMemoryBrowserHexAddress(rva) : @"";
    payload[@"prevAddress"] = address >= normalizedPageSize ? VCMemoryBrowserHexAddress(address - normalizedPageSize) : @"0x0";
    payload[@"nextAddress"] = (UINT64_MAX - address) >= normalizedPageSize ? VCMemoryBrowserHexAddress(address + normalizedPageSize) : @"";
    payload[@"hexDump"] = [self _formattedHexDumpForAddress:address data:data];
    payload[@"lines"] = [self _lineDictionariesForAddress:address data:data];
    payload[@"typedPreview"] = [self _typedPreviewForAddress:address data:data];
    payload[@"asciiPreview"] = [self _asciiPreviewForData:data];
    payload[@"session"] = [self activeSessionSummary];
    return [payload copy];
}

- (NSDictionary *)stepPageBy:(NSInteger)delta
                    pageSize:(NSUInteger)pageSize
                errorMessage:(NSString * _Nullable * _Nullable)errorMessage {
    if (![self hasActiveSession]) {
        if (errorMessage) *errorMessage = @"No active memory browser session. Open a page first.";
        return nil;
    }

    NSUInteger normalizedPageSize = VCMemoryBrowserClampedSize(pageSize, self.currentPageSize ?: 256, 32, 1024);
    uint64_t targetAddress = self.currentAddress;
    if (delta < 0) {
        targetAddress = self.currentAddress >= normalizedPageSize ? (self.currentAddress - normalizedPageSize) : 0;
    } else if (delta > 0) {
        if ((UINT64_MAX - self.currentAddress) < normalizedPageSize) {
            if (errorMessage) *errorMessage = @"Next page would overflow the address space.";
            return nil;
        }
        targetAddress = self.currentAddress + normalizedPageSize;
    }

    return [self browseAtAddress:targetAddress
                        pageSize:normalizedPageSize
                          length:normalizedPageSize
                   updateSession:YES
                    errorMessage:errorMessage];
}

#pragma mark - Helpers

- (VCMemRegion *)_regionForAddress:(uint64_t)address {
    for (VCMemRegion *region in [[VCProcessInfo shared] memoryRegions] ?: @[]) {
        if (address >= region.start && address < region.end) return region;
    }
    return nil;
}

- (NSString *)_formattedHexDumpForAddress:(uint64_t)address data:(NSData *)data {
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    NSMutableString *dump = [NSMutableString new];

    for (NSUInteger offset = 0; offset < data.length; offset += 16) {
        [dump appendFormat:@"%016llX  ", (unsigned long long)(address + offset)];
        for (NSUInteger idx = 0; idx < 16; idx++) {
            if (offset + idx < data.length) {
                [dump appendFormat:@"%02X ", bytes[offset + idx]];
            } else {
                [dump appendString:@"   "];
            }
            if (idx == 7) [dump appendString:@" "];
        }

        [dump appendString:@" |"];
        for (NSUInteger idx = 0; idx < 16 && (offset + idx) < data.length; idx++) {
            uint8_t byte = bytes[offset + idx];
            [dump appendFormat:@"%c", (byte >= 32 && byte < 127) ? byte : '.'];
        }
        [dump appendString:@"|\n"];
    }

    return [dump copy];
}

- (NSArray<NSDictionary *> *)_lineDictionariesForAddress:(uint64_t)address data:(NSData *)data {
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    NSMutableArray<NSDictionary *> *lines = [NSMutableArray new];

    for (NSUInteger offset = 0; offset < data.length; offset += 16) {
        NSMutableString *hex = [NSMutableString new];
        NSMutableString *ascii = [NSMutableString new];
        NSUInteger byteCount = MIN((NSUInteger)16, data.length - offset);
        for (NSUInteger idx = 0; idx < byteCount; idx++) {
            uint8_t byte = bytes[offset + idx];
            [hex appendFormat:@"%02X", byte];
            if (idx + 1 < byteCount) [hex appendString:@" "];
            [ascii appendFormat:@"%c", (byte >= 32 && byte < 127) ? byte : '.'];
        }
        [lines addObject:@{
            @"address": VCMemoryBrowserHexAddress(address + offset),
            @"hex": hex,
            @"ascii": ascii,
            @"byteCount": @(byteCount)
        }];
    }

    return [lines copy];
}

- (NSString *)_asciiPreviewForData:(NSData *)data {
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    NSMutableString *preview = [NSMutableString new];
    NSUInteger limit = MIN((NSUInteger)96, data.length);
    for (NSUInteger idx = 0; idx < limit; idx++) {
        uint8_t byte = bytes[idx];
        [preview appendFormat:@"%c", (byte >= 32 && byte < 127) ? byte : '.'];
    }
    return [preview copy];
}

- (NSDictionary *)_typedPreviewForAddress:(uint64_t)address data:(NSData *)data {
    NSArray<NSDictionary *> *specs = @[
        @{@"key": @"int8", @"type": @(VCMemDataTypeI8), @"bytes": @1},
        @{@"key": @"uint8", @"type": @(VCMemDataTypeU8), @"bytes": @1},
        @{@"key": @"int16", @"type": @(VCMemDataTypeI16), @"bytes": @2},
        @{@"key": @"uint16", @"type": @(VCMemDataTypeU16), @"bytes": @2},
        @{@"key": @"int32", @"type": @(VCMemDataTypeI32), @"bytes": @4},
        @{@"key": @"uint32", @"type": @(VCMemDataTypeU32), @"bytes": @4},
        @{@"key": @"int64", @"type": @(VCMemDataTypeI64), @"bytes": @8},
        @{@"key": @"uint64", @"type": @(VCMemDataTypeU64), @"bytes": @8},
        @{@"key": @"float", @"type": @(VCMemDataTypeF32), @"bytes": @4},
        @{@"key": @"double", @"type": @(VCMemDataTypeF64), @"bytes": @8},
    ];

    NSMutableDictionary *preview = [NSMutableDictionary new];
    for (NSDictionary *spec in specs) {
        NSUInteger bytesRequired = [spec[@"bytes"] unsignedIntegerValue];
        if (data.length < bytesRequired) continue;
        NSString *value = [[VCMemEngine shared] readAddress:address type:(VCMemDataType)[spec[@"type"] unsignedIntegerValue]];
        if (VCMemoryBrowserTrimmedString(value).length > 0) {
            preview[spec[@"key"]] = value;
        }
    }

    if (data.length >= sizeof(uint64_t)) {
        uint64_t pointerValue = 0;
        [data getBytes:&pointerValue length:sizeof(uint64_t)];
        NSMutableDictionary *pointerPreview = [@{
            @"value": VCMemoryBrowserHexAddress(pointerValue)
        } mutableCopy];
        VCMemRegion *pointerRegion = [self _regionForAddress:pointerValue];
        if (pointerRegion) {
            pointerPreview[@"readable"] = @([pointerRegion.protection rangeOfString:@"r"].location != NSNotFound);
            pointerPreview[@"protection"] = pointerRegion.protection ?: @"---";
        }
        preview[@"pointer"] = [pointerPreview copy];
    }

    return [preview copy];
}

@end
