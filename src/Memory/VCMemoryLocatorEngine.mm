/**
 * VCMemoryLocatorEngine -- pointer chains, signatures, and address resolution
 */

#import "VCMemoryLocatorEngine.h"
#import "../Process/VCProcessInfo.h"
#import "../AI/Security/VCPromptLeakGuard.h"
#import "../Vendor/MemoryBackend/Engine/VCMemEngine.h"
#import "../Vendor/MemoryBackend/Core/VCMemoryCore.hpp"

static NSString *VCMemoryLocatorHexAddress(uint64_t address) {
    return [NSString stringWithFormat:@"0x%llx", (unsigned long long)address];
}

static NSString *VCMemoryLocatorTrimmedString(id value) {
    if ([value isKindOfClass:[NSString class]]) {
        return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        return [[(NSNumber *)value stringValue] copy];
    }
    return @"";
}

static NSArray<NSNumber *> *VCMemoryLocatorNormalizedOffsets(NSArray<NSNumber *> *offsets) {
    NSMutableArray<NSNumber *> *results = [NSMutableArray new];
    for (id value in offsets ?: @[]) {
        if ([value isKindOfClass:[NSNumber class]]) {
            [results addObject:@([(NSNumber *)value longLongValue])];
        } else if ([value isKindOfClass:[NSString class]]) {
            NSString *text = VCMemoryLocatorTrimmedString(value);
            if (text.length == 0) continue;
            long long parsed = strtoll(text.UTF8String, NULL, 0);
            [results addObject:@(parsed)];
        }
    }
    return [results copy];
}

static BOOL VCMemoryLocatorRegionCanContainPointers(VCMemRegion *region) {
    if (![region isKindOfClass:[VCMemRegion class]]) return NO;
    NSString *protection = [region.protection lowercaseString];
    if (![protection containsString:@"r"]) return NO;
    if ([protection containsString:@"x"]) return NO;
    return region.size >= sizeof(uint64_t);
}

@implementation VCMemoryLocatorEngine

+ (instancetype)shared {
    static VCMemoryLocatorEngine *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VCMemoryLocatorEngine alloc] init];
    });
    return instance;
}

- (NSDictionary *)resolvePointerChainWithModuleName:(NSString *)moduleName
                                        baseAddress:(uint64_t)baseAddress
                                         baseOffset:(uint64_t)baseOffset
                                            offsets:(NSArray<NSNumber *> *)offsets
                                       errorMessage:(NSString * _Nullable * _Nullable)errorMessage {
    NSString *trimmedModule = VCMemoryLocatorTrimmedString(moduleName);
    NSString *blockedReason = [VCPromptLeakGuard blockedToolReasonForModuleName:trimmedModule];
    if (blockedReason.length > 0) {
        if (errorMessage) *errorMessage = blockedReason;
        return nil;
    }

    NSArray<NSNumber *> *normalizedOffsets = VCMemoryLocatorNormalizedOffsets(offsets);
    uint64_t rootBase = baseAddress;
    NSString *resolvedModuleName = trimmedModule;

    if (rootBase == 0) {
        if (trimmedModule.length == 0) {
            if (errorMessage) *errorMessage = @"Pointer chain resolution requires moduleName or baseAddress.";
            return nil;
        }
        rootBase = vcore::MemEngine::inst().modBase(trimmedModule.UTF8String);
        if (rootBase == 0) {
            if (errorMessage) *errorMessage = [NSString stringWithFormat:@"Could not resolve module base for %@", trimmedModule];
            return nil;
        }
    } else if (resolvedModuleName.length == 0) {
        NSString *owner = nil;
        [[VCProcessInfo shared] runtimeToRva:rootBase module:&owner];
        resolvedModuleName = owner ?: @"";
    }

    uint64_t currentSlot = rootBase + baseOffset;
    NSMutableArray<NSDictionary *> *hops = [NSMutableArray new];
    NSMutableSet<NSString *> *seenTargets = [NSMutableSet new];

    if (normalizedOffsets.count == 0) {
        NSString *moduleForAddress = nil;
        uint64_t rva = [[VCProcessInfo shared] runtimeToRva:currentSlot module:&moduleForAddress];
        NSString *memoryBlocked = [VCPromptLeakGuard blockedToolReasonForMemoryModuleName:moduleForAddress address:currentSlot];
        if (memoryBlocked.length > 0) {
            if (errorMessage) *errorMessage = memoryBlocked;
            return nil;
        }
        return @{
            @"moduleName": resolvedModuleName ?: @"",
            @"rootBase": VCMemoryLocatorHexAddress(rootBase),
            @"baseOffset": VCMemoryLocatorHexAddress(baseOffset),
            @"offsets": normalizedOffsets ?: @[],
            @"resolvedAddress": VCMemoryLocatorHexAddress(currentSlot),
            @"rva": rva > 0 ? VCMemoryLocatorHexAddress(rva) : @"",
            @"hopCount": @0,
            @"hops": @[]
        };
    }

    for (NSUInteger idx = 0; idx < normalizedOffsets.count; idx++) {
        uint64_t pointerValue = 0;
        if (!vcore::MemEngine::inst().readMem(currentSlot, &pointerValue, sizeof(pointerValue))) {
            if (errorMessage) *errorMessage = [NSString stringWithFormat:@"Failed to read pointer-sized value at %@", VCMemoryLocatorHexAddress(currentSlot)];
            return nil;
        }

        int64_t offsetValue = [normalizedOffsets[idx] longLongValue];
        uint64_t nextAddress = (uint64_t)((int64_t)pointerValue + offsetValue);
        NSString *moduleForAddress = nil;
        uint64_t rva = [[VCProcessInfo shared] runtimeToRva:nextAddress module:&moduleForAddress];
        NSString *memoryBlocked = [VCPromptLeakGuard blockedToolReasonForMemoryModuleName:moduleForAddress address:nextAddress];
        if (memoryBlocked.length > 0) {
            if (errorMessage) *errorMessage = memoryBlocked;
            return nil;
        }

        NSString *loopKey = VCMemoryLocatorHexAddress(nextAddress);
        [hops addObject:@{
            @"index": @(idx),
            @"slotAddress": VCMemoryLocatorHexAddress(currentSlot),
            @"pointerValue": VCMemoryLocatorHexAddress(pointerValue),
            @"offset": [NSString stringWithFormat:@"%lld", offsetValue],
            @"resolvedAddress": VCMemoryLocatorHexAddress(nextAddress),
            @"moduleName": moduleForAddress ?: @"",
            @"rva": rva > 0 ? VCMemoryLocatorHexAddress(rva) : @""
        }];

        if ([seenTargets containsObject:loopKey]) {
            if (errorMessage) *errorMessage = @"Pointer chain encountered a loop.";
            return nil;
        }
        [seenTargets addObject:loopKey];
        currentSlot = nextAddress;
    }

    NSString *finalModule = nil;
    uint64_t finalRva = [[VCProcessInfo shared] runtimeToRva:currentSlot module:&finalModule];
    NSString *finalBlocked = [VCPromptLeakGuard blockedToolReasonForMemoryModuleName:finalModule address:currentSlot];
    if (finalBlocked.length > 0) {
        if (errorMessage) *errorMessage = finalBlocked;
        return nil;
    }

    return @{
        @"moduleName": resolvedModuleName ?: @"",
        @"rootBase": VCMemoryLocatorHexAddress(rootBase),
        @"baseOffset": VCMemoryLocatorHexAddress(baseOffset),
        @"offsets": normalizedOffsets ?: @[],
        @"resolvedAddress": VCMemoryLocatorHexAddress(currentSlot),
        @"moduleForResolvedAddress": finalModule ?: @"",
        @"rva": finalRva > 0 ? VCMemoryLocatorHexAddress(finalRva) : @"",
        @"hopCount": @(hops.count),
        @"hops": [hops copy]
    };
}

- (NSDictionary *)readPointerChainWithModuleName:(NSString *)moduleName
                                     baseAddress:(uint64_t)baseAddress
                                      baseOffset:(uint64_t)baseOffset
                                         offsets:(NSArray<NSNumber *> *)offsets
                                  dataTypeString:(NSString *)dataTypeString
                                    errorMessage:(NSString * _Nullable * _Nullable)errorMessage {
    NSDictionary *resolved = [self resolvePointerChainWithModuleName:moduleName
                                                         baseAddress:baseAddress
                                                          baseOffset:baseOffset
                                                             offsets:offsets
                                                        errorMessage:errorMessage];
    if (!resolved) return nil;

    NSString *resolvedAddressString = VCMemoryLocatorTrimmedString(resolved[@"resolvedAddress"]);
    uint64_t resolvedAddress = strtoull(resolvedAddressString.UTF8String, NULL, 0);
    vcore::DataType dataType = vcore::DT_I32;
    NSString *canonicalType = nil;
    if (![self _resolveDataTypeString:dataTypeString outType:&dataType canonical:&canonicalType]) {
        if (errorMessage) *errorMessage = [NSString stringWithFormat:@"Unsupported pointer_chain read type: %@", VCMemoryLocatorTrimmedString(dataTypeString)];
        return nil;
    }

    char buffer[96] = {0};
    if (!vcore::MemEngine::inst().readVal(resolvedAddress, dataType, buffer, sizeof(buffer))) {
        if (errorMessage) *errorMessage = [NSString stringWithFormat:@"Failed to read %@ at %@", canonicalType, resolvedAddressString];
        return nil;
    }

    NSMutableDictionary *payload = [resolved mutableCopy];
    payload[@"dataType"] = canonicalType ?: @"int32";
    payload[@"value"] = [NSString stringWithUTF8String:buffer] ?: @"";
    return [payload copy];
}

- (NSDictionary *)scanSignature:(NSString *)signature
                     moduleName:(NSString *)moduleName
                          limit:(NSUInteger)limit
                   errorMessage:(NSString * _Nullable * _Nullable)errorMessage {
    NSString *trimmedSignature = VCMemoryLocatorTrimmedString(signature);
    if (trimmedSignature.length == 0) {
        if (errorMessage) *errorMessage = @"Signature scan requires a non-empty signature string.";
        return nil;
    }

    NSString *trimmedModule = VCMemoryLocatorTrimmedString(moduleName);
    NSString *blockedReason = [VCPromptLeakGuard blockedToolReasonForModuleName:trimmedModule];
    if (blockedReason.length > 0) {
        if (errorMessage) *errorMessage = blockedReason;
        return nil;
    }

    size_t resultLimit = MAX((NSUInteger)1, MIN(limit, (NSUInteger)200));
    std::vector<uint64_t> results = vcore::MemEngine::inst().sigScan(trimmedSignature.UTF8String,
                                                                     trimmedModule.length > 0 ? trimmedModule.UTF8String : nullptr,
                                                                     resultLimit);

    NSMutableArray<NSDictionary *> *matches = [NSMutableArray new];
    for (uint64_t address : results) {
        NSString *ownerModule = nil;
        uint64_t rva = [[VCProcessInfo shared] runtimeToRva:address module:&ownerModule];
        NSString *memoryBlocked = [VCPromptLeakGuard blockedToolReasonForMemoryModuleName:ownerModule address:address];
        if (memoryBlocked.length > 0) continue;
        [matches addObject:@{
            @"address": VCMemoryLocatorHexAddress(address),
            @"moduleName": ownerModule ?: @"",
            @"rva": rva > 0 ? VCMemoryLocatorHexAddress(rva) : @""
        }];
    }

    return @{
        @"signature": trimmedSignature,
        @"moduleName": trimmedModule ?: @"",
        @"returnedCount": @(matches.count),
        @"matches": [matches copy]
    };
}

- (NSDictionary *)resolveSignature:(NSString *)signature
                        moduleName:(NSString *)moduleName
                            offset:(int64_t)offset
                    dataTypeString:(NSString *)dataTypeString
                        resultLimit:(NSUInteger)resultLimit
                      errorMessage:(NSString * _Nullable * _Nullable)errorMessage {
    NSDictionary *scan = [self scanSignature:signature moduleName:moduleName limit:MAX(resultLimit, (NSUInteger)8) errorMessage:errorMessage];
    if (!scan) return nil;

    NSArray<NSDictionary *> *matches = [scan[@"matches"] isKindOfClass:[NSArray class]] ? scan[@"matches"] : @[];
    if (matches.count == 0) {
        if (errorMessage) *errorMessage = @"Signature scan returned no matches.";
        return nil;
    }

    NSDictionary *first = matches.firstObject;
    uint64_t firstAddress = strtoull([VCMemoryLocatorTrimmedString(first[@"address"]) UTF8String], NULL, 0);
    uint64_t resolvedAddress = (uint64_t)((int64_t)firstAddress + offset);
    NSString *ownerModule = nil;
    uint64_t rva = [[VCProcessInfo shared] runtimeToRva:resolvedAddress module:&ownerModule];
    NSString *memoryBlocked = [VCPromptLeakGuard blockedToolReasonForMemoryModuleName:ownerModule address:resolvedAddress];
    if (memoryBlocked.length > 0) {
        if (errorMessage) *errorMessage = memoryBlocked;
        return nil;
    }

    NSMutableDictionary *payload = [scan mutableCopy];
    payload[@"firstMatchAddress"] = VCMemoryLocatorHexAddress(firstAddress);
    payload[@"offset"] = [NSString stringWithFormat:@"%lld", offset];
    payload[@"resolvedAddress"] = VCMemoryLocatorHexAddress(resolvedAddress);
    payload[@"moduleForResolvedAddress"] = ownerModule ?: @"";
    payload[@"resolvedRva"] = rva > 0 ? VCMemoryLocatorHexAddress(rva) : @"";

    NSString *typeString = VCMemoryLocatorTrimmedString(dataTypeString);
    if (typeString.length > 0) {
        vcore::DataType dataType = vcore::DT_I32;
        NSString *canonicalType = nil;
        if (![self _resolveDataTypeString:typeString outType:&dataType canonical:&canonicalType]) {
            if (errorMessage) *errorMessage = [NSString stringWithFormat:@"Unsupported signature_scan read type: %@", typeString];
            return nil;
        }
        char buffer[96] = {0};
        if (!vcore::MemEngine::inst().readVal(resolvedAddress, dataType, buffer, sizeof(buffer))) {
            if (errorMessage) *errorMessage = [NSString stringWithFormat:@"Failed to read %@ at %@", canonicalType, VCMemoryLocatorHexAddress(resolvedAddress)];
            return nil;
        }
        payload[@"dataType"] = canonicalType ?: @"int32";
        payload[@"value"] = [NSString stringWithUTF8String:buffer] ?: @"";
    }

    return [payload copy];
}

- (NSDictionary *)resolveAddressAction:(NSString *)action
                            moduleName:(NSString *)moduleName
                                   rva:(uint64_t)rva
                               address:(uint64_t)address
                          errorMessage:(NSString * _Nullable * _Nullable)errorMessage {
    NSString *normalizedAction = [VCMemoryLocatorTrimmedString(action).lowercaseString copy];
    NSString *trimmedModule = VCMemoryLocatorTrimmedString(moduleName);
    NSString *blockedReason = [VCPromptLeakGuard blockedToolReasonForModuleName:trimmedModule];
    if (trimmedModule.length > 0 && blockedReason.length > 0) {
        if (errorMessage) *errorMessage = blockedReason;
        return nil;
    }

    if ([normalizedAction isEqualToString:@"module_base"]) {
        if (trimmedModule.length == 0) {
            if (errorMessage) *errorMessage = @"module_base requires moduleName.";
            return nil;
        }
        uint64_t base = vcore::MemEngine::inst().modBase(trimmedModule.UTF8String);
        if (base == 0) {
            if (errorMessage) *errorMessage = [NSString stringWithFormat:@"Could not resolve module base for %@", trimmedModule];
            return nil;
        }
        return @{
            @"action": normalizedAction,
            @"moduleName": trimmedModule,
            @"moduleBase": VCMemoryLocatorHexAddress(base)
        };
    }

    if ([normalizedAction isEqualToString:@"module_size"]) {
        if (trimmedModule.length == 0) {
            if (errorMessage) *errorMessage = @"module_size requires moduleName.";
            return nil;
        }
        uint64_t size = vcore::MemEngine::inst().modSize(trimmedModule.UTF8String);
        if (size == 0) {
            if (errorMessage) *errorMessage = [NSString stringWithFormat:@"Could not resolve module size for %@", trimmedModule];
            return nil;
        }
        return @{
            @"action": normalizedAction,
            @"moduleName": trimmedModule,
            @"moduleSize": @(size),
            @"moduleSizeHex": VCMemoryLocatorHexAddress(size)
        };
    }

    if ([normalizedAction isEqualToString:@"rva_to_runtime"]) {
        if (trimmedModule.length == 0 || rva == 0) {
            if (errorMessage) *errorMessage = @"rva_to_runtime requires moduleName and rva.";
            return nil;
        }
        uint64_t runtimeAddress = [[VCProcessInfo shared] rvaToRuntime:rva module:trimmedModule];
        if (runtimeAddress == 0) {
            if (errorMessage) *errorMessage = [NSString stringWithFormat:@"Could not resolve RVA %@ in %@", VCMemoryLocatorHexAddress(rva), trimmedModule];
            return nil;
        }
        NSString *memoryBlocked = [VCPromptLeakGuard blockedToolReasonForMemoryModuleName:trimmedModule address:runtimeAddress];
        if (memoryBlocked.length > 0) {
            if (errorMessage) *errorMessage = memoryBlocked;
            return nil;
        }
        return @{
            @"action": normalizedAction,
            @"moduleName": trimmedModule,
            @"rva": VCMemoryLocatorHexAddress(rva),
            @"runtimeAddress": VCMemoryLocatorHexAddress(runtimeAddress)
        };
    }

    if ([normalizedAction isEqualToString:@"runtime_to_rva"]) {
        if (address == 0) {
            if (errorMessage) *errorMessage = @"runtime_to_rva requires address.";
            return nil;
        }
        NSString *ownerModule = nil;
        uint64_t resolvedRva = [[VCProcessInfo shared] runtimeToRva:address module:&ownerModule];
        NSString *memoryBlocked = [VCPromptLeakGuard blockedToolReasonForMemoryModuleName:ownerModule address:address];
        if (memoryBlocked.length > 0) {
            if (errorMessage) *errorMessage = memoryBlocked;
            return nil;
        }
        if (resolvedRva == 0 && ownerModule.length == 0) {
            if (errorMessage) *errorMessage = [NSString stringWithFormat:@"Address %@ is not inside a known module.", VCMemoryLocatorHexAddress(address)];
            return nil;
        }
        return @{
            @"action": normalizedAction,
            @"address": VCMemoryLocatorHexAddress(address),
            @"moduleName": ownerModule ?: @"",
            @"rva": resolvedRva > 0 ? VCMemoryLocatorHexAddress(resolvedRva) : @""
        };
    }

    if (errorMessage) *errorMessage = [NSString stringWithFormat:@"Unsupported address_resolve action: %@", normalizedAction ?: @""];
    return nil;
}

- (NSDictionary *)findPointerReferencesToAddress:(uint64_t)address
                                           limit:(NSUInteger)limit
                                includeSecondHop:(BOOL)includeSecondHop
                                    errorMessage:(NSString * _Nullable * _Nullable)errorMessage {
    if (address == 0) {
        if (errorMessage) *errorMessage = @"findPointerReferences requires a non-zero address.";
        return nil;
    }

    [[VCMemEngine shared] initialize];

    uint64_t scannedBytes = 0;
    NSUInteger scannedRegionCount = 0;
    NSArray<NSDictionary *> *directReferences = [self _pointerSlotsReferencingAddress:address
                                                                                 limit:MAX((NSUInteger)1, MIN(limit, (NSUInteger)48))
                                                                          scannedBytes:&scannedBytes
                                                                         scannedRegionCount:&scannedRegionCount];

    NSMutableArray<NSDictionary *> *suggestedChains = [NSMutableArray new];
    NSMutableSet<NSString *> *chainKeys = [NSMutableSet new];

    for (NSDictionary *reference in directReferences) {
        NSString *moduleName = VCMemoryLocatorTrimmedString(reference[@"slotModuleName"]);
        NSString *rva = VCMemoryLocatorTrimmedString(reference[@"slotRva"]);
        if (moduleName.length == 0 || rva.length == 0) continue;
        NSString *chainKey = [NSString stringWithFormat:@"%@|%@|0", moduleName, rva];
        if ([chainKeys containsObject:chainKey]) continue;
        [chainKeys addObject:chainKey];
        [suggestedChains addObject:@{
            @"kind": @"one_hop",
            @"moduleName": moduleName,
            @"baseOffset": rva,
            @"offsets": @[@0],
            @"resolvedAddress": VCMemoryLocatorHexAddress(address),
            @"slotAddress": reference[@"slotAddress"] ?: @"",
            @"note": @"Module slot dereference reaches the target address."
        }];
    }

    NSMutableArray<NSDictionary *> *secondHopReferences = [NSMutableArray new];
    if (includeSecondHop && directReferences.count > 0) {
        NSUInteger remaining = MAX((NSUInteger)1, MIN(limit, (NSUInteger)24));
        NSUInteger parentBudget = MIN((NSUInteger)8, directReferences.count);
        for (NSUInteger idx = 0; idx < parentBudget && remaining > 0; idx++) {
            NSDictionary *childReference = directReferences[idx];
            uint64_t childSlot = strtoull([VCMemoryLocatorTrimmedString(childReference[@"slotAddress"]) UTF8String], NULL, 0);
            if (childSlot == 0) continue;

            uint64_t nestedScannedBytes = 0;
            NSUInteger nestedRegionCount = 0;
            NSArray<NSDictionary *> *parents = [self _pointerSlotsReferencingAddress:childSlot
                                                                                limit:remaining
                                                                         scannedBytes:&nestedScannedBytes
                                                                    scannedRegionCount:&nestedRegionCount];
            scannedBytes += nestedScannedBytes;
            scannedRegionCount += nestedRegionCount;

            for (NSDictionary *parentReference in parents) {
                NSMutableDictionary *enriched = [parentReference mutableCopy];
                enriched[@"intermediateSlotAddress"] = childReference[@"slotAddress"] ?: @"";
                enriched[@"intermediateModuleName"] = childReference[@"slotModuleName"] ?: @"";
                enriched[@"intermediateSlotRva"] = childReference[@"slotRva"] ?: @"";
                [secondHopReferences addObject:[enriched copy]];

                NSString *moduleName = VCMemoryLocatorTrimmedString(parentReference[@"slotModuleName"]);
                NSString *rva = VCMemoryLocatorTrimmedString(parentReference[@"slotRva"]);
                if (moduleName.length > 0 && rva.length > 0) {
                    NSString *chainKey = [NSString stringWithFormat:@"%@|%@|0|0", moduleName, rva];
                    if (![chainKeys containsObject:chainKey]) {
                        [chainKeys addObject:chainKey];
                        [suggestedChains addObject:@{
                            @"kind": @"two_hop",
                            @"moduleName": moduleName,
                            @"baseOffset": rva,
                            @"offsets": @[@0, @0],
                            @"resolvedAddress": VCMemoryLocatorHexAddress(address),
                            @"intermediateSlotAddress": childReference[@"slotAddress"] ?: @"",
                            @"slotAddress": parentReference[@"slotAddress"] ?: @"",
                            @"note": @"Module slot dereferences to another pointer slot that reaches the target."
                        }];
                    }
                }

                if (remaining > 0) remaining--;
                if (remaining == 0) break;
            }
        }
    }

    return @{
        @"targetAddress": VCMemoryLocatorHexAddress(address),
        @"limit": @(limit),
        @"searchDepth": @(includeSecondHop ? 2 : 1),
        @"directReferenceCount": @(directReferences.count),
        @"directReferences": directReferences ?: @[],
        @"secondHopReferenceCount": @(secondHopReferences.count),
        @"secondHopReferences": [secondHopReferences copy] ?: @[],
        @"suggestedPointerChains": [suggestedChains copy] ?: @[],
        @"scannedBytes": @(scannedBytes),
        @"scannedRegionCount": @(scannedRegionCount)
    };
}

#pragma mark - Private

- (NSArray<NSDictionary *> *)_pointerSlotsReferencingAddress:(uint64_t)targetAddress
                                                       limit:(NSUInteger)limit
                                                scannedBytes:(uint64_t *)outScannedBytes
                                           scannedRegionCount:(NSUInteger *)outScannedRegionCount {
    NSMutableArray<NSDictionary *> *results = [NSMutableArray new];
    uint64_t scannedBytes = 0;
    NSUInteger scannedRegionCount = 0;

    NSArray<VCMemRegion *> *regions = [[VCProcessInfo shared] memoryRegions];
    const NSUInteger chunkSize = 0x8000;

    for (VCMemRegion *region in regions) {
        if (![self _regionShouldBeScannedForPointerReferences:region]) continue;
        scannedRegionCount++;

        uint64_t cursor = region.start;
        while (cursor + sizeof(uint64_t) <= region.end) {
            NSUInteger length = (NSUInteger)MIN((uint64_t)chunkSize, region.end - cursor);
            NSMutableData *buffer = [NSMutableData dataWithLength:length];
            if (![buffer isKindOfClass:[NSMutableData class]] || buffer.length == 0) break;

            BOOL readOK = vcore::MemEngine::inst().readMem(cursor, buffer.mutableBytes, length);
            scannedBytes += length;
            if (!readOK) {
                cursor += length;
                continue;
            }

            const uint8_t *bytes = (const uint8_t *)buffer.bytes;
            for (NSUInteger offset = 0; offset + sizeof(uint64_t) <= length; offset += sizeof(uint64_t)) {
                uint64_t pointerValue = 0;
                memcpy(&pointerValue, bytes + offset, sizeof(uint64_t));
                if (pointerValue != targetAddress) continue;

                uint64_t slotAddress = cursor + offset;
                NSString *ownerModule = nil;
                uint64_t rva = [[VCProcessInfo shared] runtimeToRva:slotAddress module:&ownerModule];
                NSString *memoryBlocked = [VCPromptLeakGuard blockedToolReasonForMemoryModuleName:ownerModule address:slotAddress];
                if (memoryBlocked.length > 0) continue;

                [results addObject:@{
                    @"slotAddress": VCMemoryLocatorHexAddress(slotAddress),
                    @"slotModuleName": ownerModule ?: @"",
                    @"slotRva": rva > 0 ? VCMemoryLocatorHexAddress(rva) : @"",
                    @"regionStart": VCMemoryLocatorHexAddress(region.start),
                    @"regionEnd": VCMemoryLocatorHexAddress(region.end),
                    @"protection": region.protection ?: @""
                }];
                if (results.count >= limit) {
                    if (outScannedBytes) *outScannedBytes = scannedBytes;
                    if (outScannedRegionCount) *outScannedRegionCount = scannedRegionCount;
                    return [results copy];
                }
            }

            cursor += length;
        }
    }

    if (outScannedBytes) *outScannedBytes = scannedBytes;
    if (outScannedRegionCount) *outScannedRegionCount = scannedRegionCount;
    return [results copy];
}

- (BOOL)_regionShouldBeScannedForPointerReferences:(VCMemRegion *)region {
    if (!VCMemoryLocatorRegionCanContainPointers(region)) return NO;
    NSString *protection = [region.protection lowercaseString];
    if (![protection containsString:@"r"]) return NO;
    if ([protection containsString:@"x"]) return NO;
    return YES;
}

- (BOOL)_resolveDataTypeString:(NSString *)dataTypeString
                       outType:(vcore::DataType *)outType
                     canonical:(NSString **)canonical {
    NSString *lower = [VCMemoryLocatorTrimmedString(dataTypeString).lowercaseString copy];
    if (lower.length == 0) lower = @"int32";

    NSDictionary<NSString *, NSDictionary *> *table = @{
        @"char": @{@"type": @(vcore::DT_I8), @"name": @"int8"},
        @"i8": @{@"type": @(vcore::DT_I8), @"name": @"int8"},
        @"int8": @{@"type": @(vcore::DT_I8), @"name": @"int8"},
        @"short": @{@"type": @(vcore::DT_I16), @"name": @"int16"},
        @"i16": @{@"type": @(vcore::DT_I16), @"name": @"int16"},
        @"int16": @{@"type": @(vcore::DT_I16), @"name": @"int16"},
        @"int": @{@"type": @(vcore::DT_I32), @"name": @"int32"},
        @"i32": @{@"type": @(vcore::DT_I32), @"name": @"int32"},
        @"int32": @{@"type": @(vcore::DT_I32), @"name": @"int32"},
        @"longlong": @{@"type": @(vcore::DT_I64), @"name": @"int64"},
        @"i64": @{@"type": @(vcore::DT_I64), @"name": @"int64"},
        @"int64": @{@"type": @(vcore::DT_I64), @"name": @"int64"},
        @"uchar": @{@"type": @(vcore::DT_U8), @"name": @"uint8"},
        @"u8": @{@"type": @(vcore::DT_U8), @"name": @"uint8"},
        @"uint8": @{@"type": @(vcore::DT_U8), @"name": @"uint8"},
        @"ushort": @{@"type": @(vcore::DT_U16), @"name": @"uint16"},
        @"u16": @{@"type": @(vcore::DT_U16), @"name": @"uint16"},
        @"uint16": @{@"type": @(vcore::DT_U16), @"name": @"uint16"},
        @"uint": @{@"type": @(vcore::DT_U32), @"name": @"uint32"},
        @"u32": @{@"type": @(vcore::DT_U32), @"name": @"uint32"},
        @"uint32": @{@"type": @(vcore::DT_U32), @"name": @"uint32"},
        @"ulonglong": @{@"type": @(vcore::DT_U64), @"name": @"uint64"},
        @"u64": @{@"type": @(vcore::DT_U64), @"name": @"uint64"},
        @"uint64": @{@"type": @(vcore::DT_U64), @"name": @"uint64"},
        @"float": @{@"type": @(vcore::DT_F32), @"name": @"float"},
        @"f32": @{@"type": @(vcore::DT_F32), @"name": @"float"},
        @"double": @{@"type": @(vcore::DT_F64), @"name": @"double"},
        @"f64": @{@"type": @(vcore::DT_F64), @"name": @"double"}
    };

    NSDictionary *entry = table[lower];
    if (!entry) return NO;
    if (outType) *outType = (vcore::DataType)[entry[@"type"] intValue];
    if (canonical) *canonical = entry[@"name"];
    return YES;
}

@end
