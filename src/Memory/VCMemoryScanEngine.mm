/**
 * VCMemoryScanEngine -- thin bridge over the memory scan backend
 */

#import "VCMemoryScanEngine.h"
#import "../Core/VCConfig.h"
#import "../Vendor/MemoryBackend/Engine/VCMemEngine.h"

static NSString *VCMemoryScanHexAddress(uint64_t address) {
    return [NSString stringWithFormat:@"0x%llx", (unsigned long long)address];
}

static NSString *VCMemoryScanTrimmedString(id value) {
    if ([value isKindOfClass:[NSString class]]) {
        return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        return [[(NSNumber *)value stringValue] copy];
    }
    return @"";
}

static NSString *VCMemoryScanStateDirectoryPath(void) {
    NSString *path = [[[VCConfig shared] sessionsPath] stringByAppendingPathComponent:@"scan"];
    [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    return path;
}

static NSString *VCMemoryScanStateFilePath(void) {
    return [VCMemoryScanStateDirectoryPath() stringByAppendingPathComponent:@"active_scan.json"];
}

@interface VCMemoryScanEngine ()
@property (nonatomic, copy) NSString *sessionID;
@property (nonatomic, copy) NSString *activeScanMode;
@property (nonatomic, copy) NSString *activeDataTypeString;
@property (nonatomic, assign) VCMemDataType activeDataType;
@property (nonatomic, assign) BOOL fuzzySession;
@property (nonatomic, assign) NSUInteger fuzzySnapshotAddressCount;
@property (nonatomic, assign) NSTimeInterval createdAt;
@property (nonatomic, assign) NSTimeInterval updatedAt;
@property (nonatomic, assign) NSUInteger lastResultCount;
@property (nonatomic, copy) NSDictionary *startParameters;
@property (nonatomic, copy) NSArray<NSDictionary *> *refineHistory;
@property (nonatomic, copy) NSDictionary *lastResultsPage;
@property (nonatomic, copy) NSDictionary *persistedSnapshot;
@end

@implementation VCMemoryScanEngine

+ (instancetype)shared {
    static VCMemoryScanEngine *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VCMemoryScanEngine alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        [[VCMemEngine shared] initialize];
        [self _resetSessionMetadata];
        [self _loadPersistedSnapshot];
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
        @"scanMode": self.activeScanMode ?: @"",
        @"dataType": self.activeDataTypeString ?: @"",
        @"fuzzySession": @(self.fuzzySession),
        @"fuzzySnapshotAddressCount": @(self.fuzzySnapshotAddressCount),
        @"resultCount": @([VCMemEngine shared].resultCount),
        @"createdAt": @(self.createdAt),
        @"updatedAt": @(self.updatedAt)
    } mutableCopy];
    if (![self hasActiveSession]) {
        payload[@"message"] = @"No active memory scan session.";
    }
    return [payload copy];
}

- (BOOL)hasPersistedSession {
    return [self.persistedSnapshot isKindOfClass:[NSDictionary class]] && self.persistedSnapshot.count > 0;
}

- (NSDictionary *)persistedSessionSummary {
    NSMutableDictionary *payload = [[self.persistedSnapshot isKindOfClass:[NSDictionary class]] ? self.persistedSnapshot : @{} mutableCopy] ?: [NSMutableDictionary new];
    payload[@"hasPersistedSession"] = @([self hasPersistedSession]);
    payload[@"hasActiveSession"] = @([self hasActiveSession]);
    if (![self hasPersistedSession]) {
        payload[@"message"] = @"No saved memory scan session.";
    }
    return [payload copy];
}

- (NSDictionary *)startScanWithMode:(NSString *)scanMode
                              value:(NSString *)value
                           minValue:(NSString *)minValue
                           maxValue:(NSString *)maxValue
                     dataTypeString:(NSString *)dataTypeString
                     floatTolerance:(NSNumber *)floatTolerance
                         groupRange:(NSNumber *)groupRange
                    groupAnchorMode:(NSNumber *)groupAnchorMode
                        resultLimit:(NSNumber *)resultLimit
                       errorMessage:(NSString * _Nullable * _Nullable)errorMessage {
    NSString *normalizedMode = [VCMemoryScanTrimmedString(scanMode).lowercaseString copy];
    if (normalizedMode.length == 0) normalizedMode = @"exact";

    VCMemDataType dataType = VCMemDataTypeIntAuto;
    NSString *canonicalType = nil;
    if (![self _resolveDataTypeString:dataTypeString outType:&dataType canonical:&canonicalType]) {
        if (errorMessage) *errorMessage = [NSString stringWithFormat:@"Unsupported memory scan type: %@", VCMemoryScanTrimmedString(dataTypeString)];
        return nil;
    }

    [VCMemEngine shared].floatTolerance = (floatTolerance ?: @0.001).doubleValue > 0 ? (floatTolerance ?: @0.001).doubleValue : 0.001;
    [VCMemEngine shared].groupSearchRange = (groupRange ?: @200).unsignedLongLongValue;
    [VCMemEngine shared].groupAnchorMode = groupAnchorMode ? groupAnchorMode.boolValue : NO;
    [VCMemEngine shared].resultLimit = resultLimit ? resultLimit.unsignedIntegerValue : 0;

    [[VCMemEngine shared] clearResults];
    [[VCMemEngine shared] clearFastFuzzySnapshot];

    __block NSUInteger count = 0;
    __block NSUInteger fuzzyAddressCount = 0;
    __block NSString *message = @"";
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);

    if ([normalizedMode isEqualToString:@"fuzzy"]) {
        [[VCMemEngine shared] fastFuzzyInitWithCompletion:^(BOOL success, NSString *msg, NSUInteger addressCount) {
            message = msg ?: @"";
            fuzzyAddressCount = success ? addressCount : 0;
            dispatch_semaphore_signal(sema);
        }];
        dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
        if (fuzzyAddressCount == 0) {
            if (errorMessage) *errorMessage = message.length > 0 ? message : @"Could not initialize a fuzzy scan snapshot.";
            return nil;
        }
        count = 0;
        self.fuzzySession = YES;
        self.fuzzySnapshotAddressCount = fuzzyAddressCount;
    } else if ([normalizedMode isEqualToString:@"between"]) {
        NSString *rangeValue = [NSString stringWithFormat:@"%@,%@",
                                VCMemoryScanTrimmedString(minValue),
                                VCMemoryScanTrimmedString(maxValue)];
        if ([VCMemoryScanTrimmedString(minValue) length] == 0 || [VCMemoryScanTrimmedString(maxValue) length] == 0) {
            if (errorMessage) *errorMessage = @"Between scan requires minValue and maxValue.";
            return nil;
        }
        [[VCMemEngine shared] scanWithMode:VCMemSearchModeBetween value:rangeValue type:dataType completion:^(NSUInteger resultCount, NSString *msg) {
            count = resultCount;
            message = msg ?: @"";
            dispatch_semaphore_signal(sema);
        }];
        dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
        self.fuzzySession = NO;
        self.fuzzySnapshotAddressCount = 0;
    } else if ([normalizedMode isEqualToString:@"group"] || [normalizedMode isEqualToString:@"union"]) {
        NSString *groupValue = VCMemoryScanTrimmedString(value);
        if (groupValue.length == 0) {
            if (errorMessage) *errorMessage = @"Group scan requires a value string.";
            return nil;
        }
        [[VCMemEngine shared] scanWithMode:VCMemSearchModeGroup value:groupValue type:dataType completion:^(NSUInteger resultCount, NSString *msg) {
            count = resultCount;
            message = msg ?: @"";
            dispatch_semaphore_signal(sema);
        }];
        dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
        self.fuzzySession = NO;
        self.fuzzySnapshotAddressCount = 0;
    } else {
        NSString *exactValue = VCMemoryScanTrimmedString(value);
        if (exactValue.length == 0) {
            if (errorMessage) *errorMessage = @"Exact scan requires a value.";
            return nil;
        }
        [[VCMemEngine shared] scanWithMode:VCMemSearchModeExact value:exactValue type:dataType completion:^(NSUInteger resultCount, NSString *msg) {
            count = resultCount;
            message = msg ?: @"";
            dispatch_semaphore_signal(sema);
        }];
        dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
        normalizedMode = @"exact";
        self.fuzzySession = NO;
        self.fuzzySnapshotAddressCount = 0;
    }

    self.sessionID = [[NSUUID UUID] UUIDString];
    self.activeScanMode = normalizedMode;
    self.activeDataType = dataType;
    self.activeDataTypeString = canonicalType;
    self.createdAt = [[NSDate date] timeIntervalSince1970];
    self.updatedAt = self.createdAt;
    self.lastResultCount = count;
    self.startParameters = @{
        @"scanMode": normalizedMode ?: @"exact",
        @"value": VCMemoryScanTrimmedString(value),
        @"minValue": VCMemoryScanTrimmedString(minValue),
        @"maxValue": VCMemoryScanTrimmedString(maxValue),
        @"dataType": canonicalType ?: @"int_auto",
        @"floatTolerance": floatTolerance ?: @0.001,
        @"groupRange": groupRange ?: @200,
        @"groupAnchorMode": groupAnchorMode ?: @NO,
        @"resultLimit": resultLimit ?: @0
    };
    self.refineHistory = @[];
    self.lastResultsPage = nil;
    [self _persistSessionSnapshot];

    return @{
        @"session": [self activeSessionSummary],
        @"message": message ?: @"",
        @"resultCount": @(count),
        @"fuzzySnapshotAddressCount": @(self.fuzzySnapshotAddressCount)
    };
}

- (NSDictionary *)refineScanWithMode:(NSString *)filterMode
                               value:(NSString *)value
                            minValue:(NSString *)minValue
                            maxValue:(NSString *)maxValue
                      dataTypeString:(NSString *)dataTypeString
                        errorMessage:(NSString * _Nullable * _Nullable)errorMessage {
    if (![self hasActiveSession]) {
        if (errorMessage) *errorMessage = @"No active memory scan session. Start one first.";
        return nil;
    }

    VCMemDataType dataType = self.activeDataType;
    NSString *canonicalType = self.activeDataTypeString;
    if (VCMemoryScanTrimmedString(dataTypeString).length > 0 &&
        ![self _resolveDataTypeString:dataTypeString outType:&dataType canonical:&canonicalType]) {
        if (errorMessage) *errorMessage = [NSString stringWithFormat:@"Unsupported memory scan type: %@", VCMemoryScanTrimmedString(dataTypeString)];
        return nil;
    }

    NSString *mode = [VCMemoryScanTrimmedString(filterMode).lowercaseString copy];
    if (mode.length == 0) mode = @"exact";

    __block NSUInteger count = 0;
    __block NSString *message = @"";
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);

    if ((self.fuzzySession || [[VCMemEngine shared] hasFastFuzzySnapshot]) &&
        ([mode isEqualToString:@"increased"] ||
         [mode isEqualToString:@"decreased"] ||
         [mode isEqualToString:@"changed"] ||
         [mode isEqualToString:@"unchanged"])) {
        VCMemFilterMode fuzzyMode = [self _filterModeForString:mode defaultMode:VCMemFilterModeChanged];
        [[VCMemEngine shared] fastFuzzyFilterWithMode:fuzzyMode type:dataType completion:^(NSUInteger resultCount, NSString *msg) {
            count = resultCount;
            message = msg ?: @"";
            dispatch_semaphore_signal(sema);
        }];
        dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
        self.fuzzySession = YES;
    } else if ([mode isEqualToString:@"greater"] || [mode isEqualToString:@"less"] || [mode isEqualToString:@"between"]) {
        VCMemFilterMode rangeMode = [self _filterModeForString:mode defaultMode:VCMemFilterModeGreater];
        NSString *v1 = [mode isEqualToString:@"between"] ? VCMemoryScanTrimmedString(minValue) : VCMemoryScanTrimmedString(value);
        NSString *v2 = [mode isEqualToString:@"between"] ? VCMemoryScanTrimmedString(maxValue) : @"";
        if (v1.length == 0 || ([mode isEqualToString:@"between"] && v2.length == 0)) {
            if (errorMessage) *errorMessage = [mode isEqualToString:@"between"] ? @"Between refine requires minValue and maxValue." : @"This refine mode requires a value.";
            return nil;
        }
        [[VCMemEngine shared] filterResultsWithMode:rangeMode val1:v1 val2:v2 type:dataType completion:^(NSUInteger resultCount, NSString *msg) {
            count = resultCount;
            message = msg ?: @"";
            dispatch_semaphore_signal(sema);
        }];
        dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
        self.fuzzySession = NO;
        self.fuzzySnapshotAddressCount = 0;
    } else {
        NSString *targetValue = VCMemoryScanTrimmedString(value);
        if (targetValue.length == 0) {
            if (errorMessage) *errorMessage = @"Exact refine requires a value.";
            return nil;
        }
        VCMemFilterMode exactMode = [mode isEqualToString:@"exact"] ? (VCMemFilterMode)100 : [self _filterModeForString:mode defaultMode:(VCMemFilterMode)100];
        [[VCMemEngine shared] nextScanWithValue:targetValue type:dataType filterMode:exactMode completion:^(NSUInteger resultCount, NSString *msg) {
            count = resultCount;
            message = msg ?: @"";
            dispatch_semaphore_signal(sema);
        }];
        dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
        self.fuzzySession = NO;
        self.fuzzySnapshotAddressCount = 0;
    }

    self.activeDataType = dataType;
    self.activeDataTypeString = canonicalType;
    self.updatedAt = [[NSDate date] timeIntervalSince1970];
    self.lastResultCount = count;
    NSMutableArray<NSDictionary *> *history = [NSMutableArray arrayWithArray:self.refineHistory ?: @[]];
    [history addObject:@{
        @"filterMode": mode ?: @"exact",
        @"value": VCMemoryScanTrimmedString(value),
        @"minValue": VCMemoryScanTrimmedString(minValue),
        @"maxValue": VCMemoryScanTrimmedString(maxValue),
        @"dataType": canonicalType ?: @"int_auto"
    }];
    self.refineHistory = [history copy];
    self.lastResultsPage = nil;
    [self _persistSessionSnapshot];

    return @{
        @"session": [self activeSessionSummary],
        @"message": message ?: @"",
        @"resultCount": @(count)
    };
}

- (NSDictionary *)resultsWithOffset:(NSUInteger)offset
                              limit:(NSUInteger)limit
                      refreshValues:(BOOL)refreshValues
                       errorMessage:(NSString * _Nullable * _Nullable)errorMessage {
    if (![self hasActiveSession]) {
        if (errorMessage) *errorMessage = @"No active memory scan session. Start one first.";
        return nil;
    }

    NSUInteger totalCount = [VCMemEngine shared].resultCount;
    NSUInteger pageLimit = MIN(MAX(limit, 1), 200);
    NSUInteger startIndex = MIN(offset, totalCount);
    NSUInteger endIndex = MIN(startIndex + pageLimit, totalCount);
    NSMutableArray<NSDictionary *> *candidates = [NSMutableArray new];

    for (NSUInteger index = startIndex; index < endIndex; index++) {
        VCMemResultItem *item = [[VCMemEngine shared] getResultAtIndex:index type:self.activeDataType];
        if (!item) continue;

        NSString *storedValue = item.valueStr ?: @"";
        NSString *currentValue = @"";
        if (refreshValues) {
            currentValue = [[VCMemEngine shared] readAddress:item.address type:item.type] ?: @"";
        }

        [candidates addObject:@{
            @"index": @(index),
            @"address": VCMemoryScanHexAddress(item.address),
            @"dataType": [self _stringForDataType:item.type],
            @"storedValue": storedValue,
            @"currentValue": currentValue ?: @""
        }];
    }

    self.updatedAt = [[NSDate date] timeIntervalSince1970];
    self.lastResultCount = totalCount;
    self.lastResultsPage = @{
        @"offset": @(startIndex),
        @"limit": @(pageLimit),
        @"refreshValues": @(refreshValues),
        @"returnedCount": @(candidates.count),
        @"totalCount": @(totalCount),
        @"candidates": [candidates copy]
    };
    [self _persistSessionSnapshot];

    return @{
        @"session": [self activeSessionSummary],
        @"offset": @(startIndex),
        @"limit": @(pageLimit),
        @"returnedCount": @(candidates.count),
        @"totalCount": @(totalCount),
        @"candidates": [candidates copy]
    };
}

- (NSDictionary *)clearScan {
    [[VCMemEngine shared] clearResults];
    [[VCMemEngine shared] clearFastFuzzySnapshot];
    [self _resetSessionMetadata];
    [self _clearPersistedSnapshot];
    return @{
        @"active": @NO,
        @"cleared": @YES
    };
}

- (NSDictionary *)resumePersistedSessionWithErrorMessage:(NSString * _Nullable * _Nullable)errorMessage {
    NSDictionary *snapshot = [self persistedSessionSummary];
    NSDictionary *start = [snapshot[@"startParameters"] isKindOfClass:[NSDictionary class]] ? snapshot[@"startParameters"] : nil;
    if (![start isKindOfClass:[NSDictionary class]] || start.count == 0) {
        if (errorMessage) *errorMessage = @"No saved scan start parameters were found.";
        return nil;
    }

    if (![self _persistedSessionIsReplayable:snapshot]) {
        return @{
            @"resumed": @NO,
            @"replayable": @NO,
            @"message": @"Saved scan inputs were restored, but this session contains fuzzy or relative refine steps that must be repeated manually.",
            @"snapshot": snapshot
        };
    }

    NSDictionary *startResult = [self startScanWithMode:VCMemoryScanTrimmedString(start[@"scanMode"])
                                                  value:VCMemoryScanTrimmedString(start[@"value"])
                                               minValue:VCMemoryScanTrimmedString(start[@"minValue"])
                                               maxValue:VCMemoryScanTrimmedString(start[@"maxValue"])
                                         dataTypeString:VCMemoryScanTrimmedString(start[@"dataType"])
                                         floatTolerance:start[@"floatTolerance"]
                                             groupRange:start[@"groupRange"]
                                        groupAnchorMode:start[@"groupAnchorMode"]
                                            resultLimit:start[@"resultLimit"]
                                           errorMessage:errorMessage];
    if (!startResult) return nil;

    NSArray<NSDictionary *> *history = [snapshot[@"refineHistory"] isKindOfClass:[NSArray class]] ? snapshot[@"refineHistory"] : @[];
    NSDictionary *lastRefineResult = nil;
    for (NSDictionary *step in history) {
        lastRefineResult = [self refineScanWithMode:VCMemoryScanTrimmedString(step[@"filterMode"])
                                              value:VCMemoryScanTrimmedString(step[@"value"])
                                           minValue:VCMemoryScanTrimmedString(step[@"minValue"])
                                           maxValue:VCMemoryScanTrimmedString(step[@"maxValue"])
                                     dataTypeString:VCMemoryScanTrimmedString(step[@"dataType"])
                                       errorMessage:errorMessage];
        if (!lastRefineResult) return nil;
    }

    NSDictionary *savedResults = [snapshot[@"lastResultsPage"] isKindOfClass:[NSDictionary class]] ? snapshot[@"lastResultsPage"] : nil;
    NSDictionary *results = nil;
    if ([savedResults isKindOfClass:[NSDictionary class]]) {
        results = [self resultsWithOffset:[savedResults[@"offset"] respondsToSelector:@selector(unsignedIntegerValue)] ? [savedResults[@"offset"] unsignedIntegerValue] : 0
                                    limit:[savedResults[@"limit"] respondsToSelector:@selector(unsignedIntegerValue)] ? [savedResults[@"limit"] unsignedIntegerValue] : 24
                            refreshValues:[savedResults[@"refreshValues"] respondsToSelector:@selector(boolValue)] ? [savedResults[@"refreshValues"] boolValue] : YES
                             errorMessage:errorMessage];
        if (!results) return nil;
    }

    return @{
        @"resumed": @YES,
        @"replayable": @YES,
        @"session": [self activeSessionSummary],
        @"startResult": startResult ?: @{},
        @"lastRefineResult": lastRefineResult ?: @{},
        @"results": results ?: @{},
        @"snapshot": [self persistedSessionSummary]
    };
}

#pragma mark - Private

- (void)_resetSessionMetadata {
    self.sessionID = @"";
    self.activeScanMode = @"";
    self.activeDataTypeString = @"";
    self.activeDataType = VCMemDataTypeIntAuto;
    self.fuzzySession = NO;
    self.fuzzySnapshotAddressCount = 0;
    self.createdAt = 0;
    self.updatedAt = 0;
    self.lastResultCount = 0;
    self.startParameters = nil;
    self.refineHistory = @[];
    self.lastResultsPage = nil;
}

- (BOOL)_persistedSessionIsReplayable:(NSDictionary *)snapshot {
    NSDictionary *start = [snapshot[@"startParameters"] isKindOfClass:[NSDictionary class]] ? snapshot[@"startParameters"] : nil;
    NSString *scanMode = [VCMemoryScanTrimmedString(start[@"scanMode"]).lowercaseString copy];
    if ([scanMode isEqualToString:@"fuzzy"]) return NO;

    NSArray<NSDictionary *> *history = [snapshot[@"refineHistory"] isKindOfClass:[NSArray class]] ? snapshot[@"refineHistory"] : @[];
    for (NSDictionary *step in history) {
        NSString *mode = [VCMemoryScanTrimmedString(step[@"filterMode"]).lowercaseString copy];
        if ([mode isEqualToString:@"changed"] ||
            [mode isEqualToString:@"unchanged"] ||
            [mode isEqualToString:@"increased"] ||
            [mode isEqualToString:@"decreased"]) {
            return NO;
        }
    }
    return YES;
}

- (NSDictionary *)_sessionSnapshotDictionary {
    if (![self hasActiveSession]) return @{};
    NSMutableDictionary *payload = [NSMutableDictionary new];
    payload[@"session"] = [self activeSessionSummary];
    if ([self.startParameters isKindOfClass:[NSDictionary class]]) payload[@"startParameters"] = self.startParameters;
    if ([self.refineHistory isKindOfClass:[NSArray class]]) payload[@"refineHistory"] = self.refineHistory;
    if ([self.lastResultsPage isKindOfClass:[NSDictionary class]]) payload[@"lastResultsPage"] = self.lastResultsPage;
    payload[@"replayable"] = @([self _persistedSessionIsReplayable:@{
        @"startParameters": self.startParameters ?: @{},
        @"refineHistory": self.refineHistory ?: @[]
    }]);
    return [payload copy];
}

- (void)_persistSessionSnapshot {
    NSDictionary *snapshot = [self _sessionSnapshotDictionary];
    if (![snapshot isKindOfClass:[NSDictionary class]] || snapshot.count == 0) {
        [self _clearPersistedSnapshot];
        return;
    }

    NSData *data = [NSJSONSerialization dataWithJSONObject:snapshot options:NSJSONWritingPrettyPrinted error:nil];
    if (![data isKindOfClass:[NSData class]]) return;
    NSString *path = VCMemoryScanStateFilePath();
    if ([data writeToFile:path atomically:YES]) {
        self.persistedSnapshot = snapshot;
    }
}

- (void)_loadPersistedSnapshot {
    NSString *path = VCMemoryScanStateFilePath();
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (![data isKindOfClass:[NSData class]]) {
        self.persistedSnapshot = nil;
        return;
    }

    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if ([object isKindOfClass:[NSDictionary class]]) {
        self.persistedSnapshot = object;
    } else {
        self.persistedSnapshot = nil;
    }
}

- (void)_clearPersistedSnapshot {
    self.persistedSnapshot = nil;
    [[NSFileManager defaultManager] removeItemAtPath:VCMemoryScanStateFilePath() error:nil];
}

- (BOOL)_resolveDataTypeString:(NSString *)dataTypeString
                       outType:(VCMemDataType *)outType
                     canonical:(NSString **)canonical {
    NSString *lower = [VCMemoryScanTrimmedString(dataTypeString).lowercaseString copy];
    if (lower.length == 0) lower = @"int_auto";

    NSDictionary<NSString *, NSDictionary *> *table = @{
        @"char": @{@"type": @(VCMemDataTypeI8), @"name": @"int8"},
        @"i8": @{@"type": @(VCMemDataTypeI8), @"name": @"int8"},
        @"int8": @{@"type": @(VCMemDataTypeI8), @"name": @"int8"},
        @"short": @{@"type": @(VCMemDataTypeI16), @"name": @"int16"},
        @"i16": @{@"type": @(VCMemDataTypeI16), @"name": @"int16"},
        @"int16": @{@"type": @(VCMemDataTypeI16), @"name": @"int16"},
        @"int": @{@"type": @(VCMemDataTypeI32), @"name": @"int32"},
        @"i32": @{@"type": @(VCMemDataTypeI32), @"name": @"int32"},
        @"int32": @{@"type": @(VCMemDataTypeI32), @"name": @"int32"},
        @"longlong": @{@"type": @(VCMemDataTypeI64), @"name": @"int64"},
        @"i64": @{@"type": @(VCMemDataTypeI64), @"name": @"int64"},
        @"int64": @{@"type": @(VCMemDataTypeI64), @"name": @"int64"},
        @"uchar": @{@"type": @(VCMemDataTypeU8), @"name": @"uint8"},
        @"u8": @{@"type": @(VCMemDataTypeU8), @"name": @"uint8"},
        @"uint8": @{@"type": @(VCMemDataTypeU8), @"name": @"uint8"},
        @"ushort": @{@"type": @(VCMemDataTypeU16), @"name": @"uint16"},
        @"u16": @{@"type": @(VCMemDataTypeU16), @"name": @"uint16"},
        @"uint16": @{@"type": @(VCMemDataTypeU16), @"name": @"uint16"},
        @"uint": @{@"type": @(VCMemDataTypeU32), @"name": @"uint32"},
        @"u32": @{@"type": @(VCMemDataTypeU32), @"name": @"uint32"},
        @"uint32": @{@"type": @(VCMemDataTypeU32), @"name": @"uint32"},
        @"ulonglong": @{@"type": @(VCMemDataTypeU64), @"name": @"uint64"},
        @"u64": @{@"type": @(VCMemDataTypeU64), @"name": @"uint64"},
        @"uint64": @{@"type": @(VCMemDataTypeU64), @"name": @"uint64"},
        @"float": @{@"type": @(VCMemDataTypeF32), @"name": @"float"},
        @"f32": @{@"type": @(VCMemDataTypeF32), @"name": @"float"},
        @"double": @{@"type": @(VCMemDataTypeF64), @"name": @"double"},
        @"f64": @{@"type": @(VCMemDataTypeF64), @"name": @"double"},
        @"string": @{@"type": @(VCMemDataTypeString), @"name": @"string"},
        @"int_auto": @{@"type": @(VCMemDataTypeIntAuto), @"name": @"int_auto"},
        @"uint_auto": @{@"type": @(VCMemDataTypeUIntAuto), @"name": @"uint_auto"},
        @"float_auto": @{@"type": @(VCMemDataTypeFloatAuto), @"name": @"float_auto"}
    };

    NSDictionary *entry = table[lower];
    if (!entry) return NO;
    if (outType) *outType = (VCMemDataType)[entry[@"type"] unsignedIntegerValue];
    if (canonical) *canonical = entry[@"name"];
    return YES;
}

- (NSString *)_stringForDataType:(VCMemDataType)type {
    switch (type) {
        case VCMemDataTypeI8: return @"int8";
        case VCMemDataTypeI16: return @"int16";
        case VCMemDataTypeI32: return @"int32";
        case VCMemDataTypeI64: return @"int64";
        case VCMemDataTypeU8: return @"uint8";
        case VCMemDataTypeU16: return @"uint16";
        case VCMemDataTypeU32: return @"uint32";
        case VCMemDataTypeU64: return @"uint64";
        case VCMemDataTypeF32: return @"float";
        case VCMemDataTypeF64: return @"double";
        case VCMemDataTypeString: return @"string";
        case VCMemDataTypeIntAuto: return @"int_auto";
        case VCMemDataTypeUIntAuto: return @"uint_auto";
        case VCMemDataTypeFloatAuto: return @"float_auto";
    }
    return @"int_auto";
}

- (VCMemFilterMode)_filterModeForString:(NSString *)mode defaultMode:(VCMemFilterMode)defaultMode {
    NSString *lower = [VCMemoryScanTrimmedString(mode).lowercaseString copy];
    if ([lower isEqualToString:@"less"] || [lower isEqualToString:@"lt"]) return VCMemFilterModeLess;
    if ([lower isEqualToString:@"greater"] || [lower isEqualToString:@"gt"]) return VCMemFilterModeGreater;
    if ([lower isEqualToString:@"between"]) return VCMemFilterModeBetween;
    if ([lower isEqualToString:@"increased"] || [lower isEqualToString:@"inc"]) return VCMemFilterModeIncreased;
    if ([lower isEqualToString:@"decreased"] || [lower isEqualToString:@"dec"]) return VCMemFilterModeDecreased;
    if ([lower isEqualToString:@"changed"] || [lower isEqualToString:@"chg"]) return VCMemFilterModeChanged;
    if ([lower isEqualToString:@"unchanged"]) return VCMemFilterModeUnchanged;
    return defaultMode;
}

@end
