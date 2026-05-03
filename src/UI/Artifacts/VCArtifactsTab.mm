/**
 * VCArtifactsTab -- artifact browser for persisted AI/runtime analysis output
 */

#import "VCArtifactsTab.h"
#import "../Panel/VCPanel.h"
#import "../../../VansonCLI.h"
#import "../../Core/VCConfig.h"
#import "../../Patches/VCValueItem.h"
#import "../../Trace/VCTraceManager.h"
#import "../Base/VCOverlayTrackingManager.h"
#import "../Memory/VCMemoryBrowserTab.h"
#import "../Patches/VCPatchesTab.h"
#import "../Chat/VCMermaidPreviewView.h"
#import "../../AI/Chat/VCChatDiagnostics.h"
#import <math.h>

static NSString *const kVCArtifactsCellID = @"VCArtifactsCell";
NSNotificationName const VCArtifactsRequestOpenModeNotification = @"VCArtifactsRequestOpenModeNotification";
NSString *const VCArtifactsOpenModeKey = @"mode";
NSString *const VCArtifactsOpenModeDiagnosticsValue = @"diagnostics";

typedef NS_ENUM(NSInteger, VCArtifactsMode) {
    VCArtifactsModeTraces = 0,
    VCArtifactsModeDiagrams,
    VCArtifactsModeSnapshots,
    VCArtifactsModeDiagnostics
};

static NSString *VCArtifactsTrim(id value) {
    if (![value isKindOfClass:[NSString class]]) return @"";
    return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *VCArtifactsSafeString(id value) {
    if (![value isKindOfClass:[NSString class]]) return @"";
    return (NSString *)value;
}

static NSTimeInterval VCArtifactsFileTimestampAtPath(NSString *path) {
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    NSDate *date = [attrs objectForKey:NSFileModificationDate];
    return [date isKindOfClass:[NSDate class]] ? [date timeIntervalSince1970] : 0;
}

static NSNumber *VCArtifactsFileSizeAtPath(NSString *path) {
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    NSNumber *fileSize = [attrs objectForKey:NSFileSize];
    return [fileSize isKindOfClass:[NSNumber class]] ? fileSize : @0;
}

static NSString *VCArtifactsDateString(NSTimeInterval timestamp) {
    if (timestamp <= 0) return @"Unknown time";
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"MM-dd HH:mm";
    });
    return [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:timestamp]] ?: @"Unknown time";
}

static NSString *VCArtifactsPreciseDateString(NSTimeInterval timestamp) {
    if (timestamp <= 0) return @"Unknown time";
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"MM-dd HH:mm:ss";
    });
    return [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:timestamp]] ?: @"Unknown time";
}

static NSString *VCArtifactsShortIdentifier(NSString *value) {
    NSString *trimmed = VCArtifactsTrim(value);
    if (trimmed.length <= 8) return trimmed;
    return [trimmed substringToIndex:8];
}

static NSString *VCArtifactsPrettyJSONString(id object) {
    if (!object || ![NSJSONSerialization isValidJSONObject:object]) return @"";
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted error:nil];
    if (![data isKindOfClass:[NSData class]]) return @"";
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

static NSString *VCArtifactsDiagramsDirectoryPath(void) {
    NSString *path = [[[VCConfig shared] sessionsPath] stringByAppendingPathComponent:@"diagrams"];
    [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    return path;
}

static NSString *VCArtifactsMemoryDirectoryPath(void) {
    NSString *path = [[[VCConfig shared] sessionsPath] stringByAppendingPathComponent:@"memory"];
    [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    return path;
}

static NSDictionary *VCArtifactsLoadJSONDictionaryAtPath(NSString *path) {
    NSString *trimmedPath = VCArtifactsTrim(path);
    if (trimmedPath.length == 0) return nil;
    NSData *data = [NSData dataWithContentsOfFile:trimmedPath];
    if (![data isKindOfClass:[NSData class]]) return nil;
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![object isKindOfClass:[NSDictionary class]]) return nil;
    NSMutableDictionary *dictionary = [(NSDictionary *)object mutableCopy];
    dictionary[@"path"] = trimmedPath;
    return [dictionary copy];
}

static NSString *VCArtifactsDiagramTypeForContent(NSString *content) {
    NSString *normalized = [VCArtifactsTrim(content) lowercaseString];
    if (normalized.length == 0) return @"diagram";
    if ([normalized hasPrefix:@"sequencediagram"]) return @"sequence";
    if ([normalized hasPrefix:@"flowchart"] || [normalized hasPrefix:@"graph "]) return @"flowchart";
    if ([normalized hasPrefix:@"classdiagram"]) return @"class";
    if ([normalized hasPrefix:@"statediagram"]) return @"state";
    if ([normalized hasPrefix:@"erdiagram"]) return @"er";
    return @"diagram";
}

static NSDictionary *VCArtifactsLoadMermaidArtifactAtPath(NSString *path) {
    NSString *trimmedPath = VCArtifactsTrim(path);
    if (trimmedPath.length == 0) return nil;
    NSString *content = [NSString stringWithContentsOfFile:trimmedPath encoding:NSUTF8StringEncoding error:nil];
    if (![content isKindOfClass:[NSString class]]) return nil;

    NSString *fileName = trimmedPath.lastPathComponent ?: @"diagram.mmd";
    NSString *artifactID = fileName.stringByDeletingPathExtension ?: fileName;
    NSString *title = artifactID;
    if (title.length > 16 && [title characterAtIndex:8] == '-' && [title characterAtIndex:15] == '-') {
        NSString *suffix = [title substringFromIndex:16];
        if (suffix.length > 0) title = suffix;
    }

    NSString *summary = @"";
    for (NSString *line in [content componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSString *trimmedLine = VCArtifactsTrim(line);
        if (trimmedLine.length == 0) continue;
        summary = trimmedLine;
        break;
    }

    return @{
        @"artifactID": artifactID ?: @"",
        @"title": title ?: @"Diagram",
        @"path": trimmedPath,
        @"createdAt": @(VCArtifactsFileTimestampAtPath(trimmedPath)),
        @"byteCount": VCArtifactsFileSizeAtPath(trimmedPath),
        @"diagramType": VCArtifactsDiagramTypeForContent(content),
        @"summary": summary ?: @"",
        @"content": content ?: @""
    };
}

static NSDictionary *VCArtifactsMermaidSummary(NSDictionary *artifact) {
    NSString *content = VCArtifactsSafeString(artifact[@"content"]);
    NSUInteger lineCount = content.length > 0 ? [[content componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] count] : 0;
    return @{
        @"artifactID": artifact[@"artifactID"] ?: @"",
        @"title": artifact[@"title"] ?: @"Diagram",
        @"path": artifact[@"path"] ?: @"",
        @"createdAt": artifact[@"createdAt"] ?: @0,
        @"byteCount": artifact[@"byteCount"] ?: @0,
        @"diagramType": artifact[@"diagramType"] ?: @"diagram",
        @"summary": artifact[@"summary"] ?: @"",
        @"lineCount": @(lineCount)
    };
}

static NSArray<NSDictionary *> *VCArtifactsMermaidSummaries(NSUInteger limit) {
    NSString *directory = VCArtifactsDiagramsDirectoryPath();
    NSArray<NSString *> *fileNames = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:nil] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray<NSDictionary *> *items = [NSMutableArray new];
    for (NSString *fileName in [fileNames reverseObjectEnumerator]) {
        if (![fileName.pathExtension.lowercaseString isEqualToString:@"mmd"]) continue;
        NSDictionary *artifact = VCArtifactsLoadMermaidArtifactAtPath([directory stringByAppendingPathComponent:fileName]);
        if (!artifact) continue;
        [items addObject:VCArtifactsMermaidSummary(artifact)];
        if (items.count >= limit) break;
    }
    return [items copy];
}

static NSDictionary *VCArtifactsLoadMemorySnapshotAtPath(NSString *path) {
    NSMutableDictionary *snapshot = [[VCArtifactsLoadJSONDictionaryAtPath(path) ?: @{} mutableCopy] mutableCopy];
    if (snapshot.count == 0) return nil;
    if (![snapshot[@"queryType"] isKindOfClass:[NSString class]] || [snapshot[@"queryType"] length] == 0) {
        snapshot[@"queryType"] = snapshot[@"changedByteCount"] ? @"diff_snapshot" : @"snapshot";
    }
    return [snapshot copy];
}

static NSDictionary *VCArtifactsMemorySnapshotSummary(NSDictionary *snapshot) {
    NSString *queryType = [snapshot[@"queryType"] isKindOfClass:[NSString class]] ? snapshot[@"queryType"] : @"snapshot";
    NSDictionary *lengths = [snapshot[@"lengths"] isKindOfClass:[NSDictionary class]] ? snapshot[@"lengths"] : nil;
    BOOL isDiff = [queryType isEqualToString:@"diff_snapshot"];
    return @{
        @"queryType": queryType,
        @"snapshotID": snapshot[@"snapshotID"] ?: @"",
        @"title": snapshot[@"title"] ?: @"",
        @"subtitle": snapshot[@"subtitle"] ?: @"",
        @"path": snapshot[@"path"] ?: @"",
        @"createdAt": snapshot[@"createdAt"] ?: @0,
        @"address": (isDiff ? snapshot[@"snapshotAddress"] : snapshot[@"address"]) ?: @"",
        @"length": snapshot[@"length"] ?: lengths[@"before"] ?: @0,
        @"moduleName": snapshot[@"moduleName"] ?: @"",
        @"changedByteCount": snapshot[@"changedByteCount"] ?: @0,
        @"comparisonName": snapshot[@"comparisonName"] ?: @"",
        @"typeEncoding": snapshot[@"typeEncoding"] ?: @""
    };
}

static NSArray<NSDictionary *> *VCArtifactsMemorySnapshotSummaries(NSUInteger limit) {
    NSString *directory = VCArtifactsMemoryDirectoryPath();
    NSArray<NSString *> *fileNames = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:nil] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray<NSDictionary *> *items = [NSMutableArray new];
    for (NSString *fileName in [fileNames reverseObjectEnumerator]) {
        if (![fileName.pathExtension.lowercaseString isEqualToString:@"json"]) continue;
        NSDictionary *snapshot = VCArtifactsLoadMemorySnapshotAtPath([directory stringByAppendingPathComponent:fileName]);
        if (!snapshot) continue;
        [items addObject:VCArtifactsMemorySnapshotSummary(snapshot)];
        if (items.count >= limit) break;
    }
    return [items copy];
}

static NSArray<NSDictionary *> *VCArtifactsCombinedSavedSummaries(NSUInteger limit) {
    NSMutableArray<NSDictionary *> *items = [NSMutableArray new];
    [items addObjectsFromArray:VCArtifactsMemorySnapshotSummaries(limit)];
    [items addObjectsFromArray:[[VCOverlayTrackingManager shared] savedTrackerSummariesWithLimit:limit] ?: @[]];
    [items sortUsingComparator:^NSComparisonResult(NSDictionary *lhs, NSDictionary *rhs) {
        NSTimeInterval leftTime = [lhs[@"createdAt"] doubleValue];
        NSTimeInterval rightTime = [rhs[@"createdAt"] doubleValue];
        if (leftTime > rightTime) return NSOrderedAscending;
        if (leftTime < rightTime) return NSOrderedDescending;
        return [VCArtifactsSafeString(lhs[@"title"]) compare:VCArtifactsSafeString(rhs[@"title"])];
    }];
    if (items.count > limit) {
        return [items subarrayWithRange:NSMakeRange(0, limit)];
    }
    return [items copy];
}

static NSDictionary *VCArtifactsLoadDiagnosticsRecentSummary(void) {
    NSString *path = [[VCChatDiagnostics shared] recentEventsPath];
    NSMutableDictionary *payload = [[VCArtifactsLoadJSONDictionaryAtPath(path) ?: @{} mutableCopy] mutableCopy];
    if (payload.count == 0) return nil;

    NSArray *events = [payload[@"events"] isKindOfClass:[NSArray class]] ? payload[@"events"] : @[];
    NSTimeInterval updatedAt = [payload[@"updatedAt"] doubleValue];
    if (updatedAt <= 0) {
        updatedAt = VCArtifactsFileTimestampAtPath(path);
        payload[@"updatedAt"] = @(updatedAt);
    }

    payload[@"diagnosticsKind"] = @"recent_events";
    payload[@"artifactID"] = @"chat-diagnostics-recent";
    payload[@"title"] = @"Recent Event Buffer";
    payload[@"path"] = path ?: @"";
    payload[@"eventCount"] = @(events.count);
    payload[@"activeRequestID"] = VCArtifactsSafeString(payload[@"activeRequestID"]);
    payload[@"activeSessionID"] = VCArtifactsSafeString(payload[@"activeSessionID"]);
    return [payload copy];
}

static NSArray<NSDictionary *> *VCArtifactsLoadDiagnosticsHistorySummaries(NSUInteger limit) {
    NSString *path = [[VCChatDiagnostics shared] requestHistoryPath];
    NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (content.length == 0) return @[];

    NSMutableArray<NSDictionary *> *entries = [NSMutableArray new];
    __block NSUInteger lineNumber = 0;
    [content enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
        lineNumber += 1;
        NSString *trimmed = VCArtifactsTrim(line);
        if (trimmed.length == 0) return;
        NSData *data = [trimmed dataUsingEncoding:NSUTF8StringEncoding];
        if (![data isKindOfClass:[NSData class]]) return;
        id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![object isKindOfClass:[NSDictionary class]]) return;

        NSDictionary *summary = (NSDictionary *)object;
        NSString *requestID = VCArtifactsSafeString(summary[@"requestID"]);
        NSString *subphase = VCArtifactsSafeString(summary[@"subphase"]);
        NSDictionary *extra = [summary[@"extra"] isKindOfClass:[NSDictionary class]] ? summary[@"extra"] : @{};
        NSString *shortRequestID = requestID.length > 0 ? VCArtifactsShortIdentifier(requestID) : [NSString stringWithFormat:@"L%lu", (unsigned long)lineNumber];
        NSString *titlePrefix = [subphase isEqualToString:@"error"] ? @"Failed Request" : @"Request";
        NSTimeInterval timestamp = [summary[@"timestamp"] doubleValue];
        if (timestamp <= 0) timestamp = VCArtifactsFileTimestampAtPath(path);

        NSMutableDictionary *item = [summary mutableCopy];
        item[@"diagnosticsKind"] = @"request_history";
        item[@"artifactID"] = [NSString stringWithFormat:@"request-%@", shortRequestID];
        item[@"title"] = [NSString stringWithFormat:@"%@ %@", titlePrefix, shortRequestID];
        item[@"path"] = path ?: @"";
        item[@"lineNumber"] = @(lineNumber);
        item[@"createdAt"] = @(timestamp);
        item[@"chunkCount"] = extra[@"chunkCount"] ?: @0;
        item[@"stallCount"] = extra[@"stallCount"] ?: @0;
        [entries addObject:[item copy]];
    }];

    [entries sortUsingComparator:^NSComparisonResult(NSDictionary *lhs, NSDictionary *rhs) {
        NSTimeInterval leftTime = [lhs[@"createdAt"] doubleValue];
        NSTimeInterval rightTime = [rhs[@"createdAt"] doubleValue];
        if (leftTime > rightTime) return NSOrderedAscending;
        if (leftTime < rightTime) return NSOrderedDescending;
        return [VCArtifactsSafeString(lhs[@"artifactID"]) compare:VCArtifactsSafeString(rhs[@"artifactID"])];
    }];

    if (entries.count > limit) {
        return [entries subarrayWithRange:NSMakeRange(0, limit)];
    }
    return [entries copy];
}

static NSNumber *VCArtifactsRoundedNumber(double value) {
    return @(((double)llround(value * 10.0)) / 10.0);
}

static double VCArtifactsPercentileValue(NSArray<NSNumber *> *values, double percentile) {
    if (values.count == 0) return 0.0;
    NSArray<NSNumber *> *sorted = [values sortedArrayUsingSelector:@selector(compare:)];
    double clamped = MAX(0.0, MIN(1.0, percentile));
    NSUInteger index = (NSUInteger)floor(((double)sorted.count - 1.0) * clamped);
    return [sorted[index] doubleValue];
}

static NSDictionary *VCArtifactsDiagnosticsRollupSummary(NSArray<NSDictionary *> *entries) {
    if (entries.count == 0) return nil;

    NSMutableArray<NSNumber *> *durations = [NSMutableArray new];
    NSMutableArray<NSNumber *> *avgChunkIntervals = [NSMutableArray new];
    NSMutableArray<NSNumber *> *p95ChunkIntervals = [NSMutableArray new];
    NSUInteger errorCount = 0;
    NSUInteger successCount = 0;
    NSUInteger totalStalls = 0;
    NSTimeInterval latestTimestamp = 0;

    for (NSDictionary *entry in entries) {
        if ([entry[@"durationMS"] isKindOfClass:[NSNumber class]]) {
            [durations addObject:entry[@"durationMS"]];
        }
        NSDictionary *extra = [entry[@"extra"] isKindOfClass:[NSDictionary class]] ? entry[@"extra"] : nil;
        if ([extra[@"avgChunkIntervalMS"] isKindOfClass:[NSNumber class]]) {
            [avgChunkIntervals addObject:extra[@"avgChunkIntervalMS"]];
        }
        if ([extra[@"p95ChunkIntervalMS"] isKindOfClass:[NSNumber class]]) {
            [p95ChunkIntervals addObject:extra[@"p95ChunkIntervalMS"]];
        }
        totalStalls += [extra[@"stallCount"] unsignedIntegerValue];
        if ([VCArtifactsSafeString(entry[@"subphase"]) isEqualToString:@"error"]) {
            errorCount += 1;
        } else {
            successCount += 1;
        }
        latestTimestamp = MAX(latestTimestamp, [entry[@"createdAt"] doubleValue]);
    }

    return @{
        @"diagnosticsKind": @"request_rollup",
        @"artifactID": @"chat-request-rollup",
        @"title": @"Latency Rollup",
        @"path": [[VCChatDiagnostics shared] requestHistoryPath] ?: @"",
        @"requestCount": @(entries.count),
        @"successCount": @(successCount),
        @"errorCount": @(errorCount),
        @"totalStalls": @(totalStalls),
        @"updatedAt": @(latestTimestamp),
        @"p50DurationMS": VCArtifactsRoundedNumber(VCArtifactsPercentileValue(durations, 0.50)),
        @"p95DurationMS": VCArtifactsRoundedNumber(VCArtifactsPercentileValue(durations, 0.95)),
        @"p50AvgChunkIntervalMS": VCArtifactsRoundedNumber(VCArtifactsPercentileValue(avgChunkIntervals, 0.50)),
        @"p95AvgChunkIntervalMS": VCArtifactsRoundedNumber(VCArtifactsPercentileValue(avgChunkIntervals, 0.95)),
        @"p50P95ChunkGapMS": VCArtifactsRoundedNumber(VCArtifactsPercentileValue(p95ChunkIntervals, 0.50)),
        @"p95P95ChunkGapMS": VCArtifactsRoundedNumber(VCArtifactsPercentileValue(p95ChunkIntervals, 0.95))
    };
}

static NSArray<NSDictionary *> *VCArtifactsDiagnosticsSummaries(NSUInteger limit) {
    NSArray<NSDictionary *> *historyItems = VCArtifactsLoadDiagnosticsHistorySummaries(limit);
    NSMutableArray<NSDictionary *> *items = [NSMutableArray new];
    NSDictionary *rollup = VCArtifactsDiagnosticsRollupSummary(historyItems);
    if (rollup) {
        [items addObject:rollup];
    }
    NSDictionary *recent = VCArtifactsLoadDiagnosticsRecentSummary();
    if (recent) {
        [items addObject:recent];
    }
    [items addObjectsFromArray:historyItems];
    return [items copy];
}

static NSString *VCArtifactsFormattedDiagnosticEvents(NSArray<NSDictionary *> *events, NSString *requestID, NSUInteger limit) {
    if (![events isKindOfClass:[NSArray class]] || events.count == 0) {
        return @"No diagnostic events are available.";
    }

    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"HH:mm:ss.SSS";
    });

    NSMutableArray<NSDictionary *> *filteredEvents = [NSMutableArray new];
    for (NSDictionary *event in events) {
        if (![event isKindOfClass:[NSDictionary class]]) continue;
        NSString *eventRequestID = VCArtifactsSafeString(event[@"requestID"]);
        if (requestID.length > 0 && ![eventRequestID isEqualToString:requestID]) continue;
        [filteredEvents addObject:event];
    }
    NSArray<NSDictionary *> *source = filteredEvents.count > 0 ? [filteredEvents copy] : events;
    NSUInteger maxLines = MIN(limit, source.count);
    NSUInteger startIndex = source.count > maxLines ? (source.count - maxLines) : 0;
    NSMutableArray<NSString *> *lines = [NSMutableArray new];
    for (NSUInteger idx = startIndex; idx < source.count; idx++) {
        NSDictionary *event = source[idx];
        NSTimeInterval timestamp = [event[@"timestamp"] doubleValue];
        NSString *phase = VCArtifactsSafeString(event[@"phase"]);
        NSString *subphase = VCArtifactsSafeString(event[@"subphase"]);
        NSString *durationText = [event[@"durationMS"] isKindOfClass:[NSNumber class]]
            ? [NSString stringWithFormat:@"%@ms", event[@"durationMS"]]
            : @"-";
        NSString *timestampText = [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:timestamp]] ?: @"--:--:--.---";
        NSDictionary *extra = [event[@"extra"] isKindOfClass:[NSDictionary class]] ? event[@"extra"] : nil;
        NSString *extraText = @"";
        if (extra.count > 0) {
            NSData *json = [NSJSONSerialization dataWithJSONObject:extra options:0 error:nil];
            extraText = json ? ([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] ?: @"") : extra.description;
        }
        NSString *line = extraText.length > 0
            ? [NSString stringWithFormat:@"%@  %@/%@  %@  %@", timestampText, phase ?: @"", subphase ?: @"", durationText, extraText]
            : [NSString stringWithFormat:@"%@  %@/%@  %@", timestampText, phase ?: @"", subphase ?: @"", durationText];
        [lines addObject:line];
    }
    return [lines componentsJoinedByString:@"\n"];
}

static UIButton *VCArtifactsActionButton(NSString *title) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    VCApplyCompactSecondaryButtonStyle(button);
    VCPrepareButtonTitle(button, NSLineBreakByTruncatingTail, 0.78);
    button.titleLabel.textAlignment = NSTextAlignmentCenter;
    button.contentEdgeInsets = UIEdgeInsetsMake(4, 7, 4, 7);
    return button;
}

static NSString *VCArtifactsModeCollectionLabel(VCArtifactsMode mode) {
    switch (mode) {
        case VCArtifactsModeTraces: return @"trace sessions";
        case VCArtifactsModeDiagrams: return @"Mermaid exports";
        case VCArtifactsModeSnapshots: return @"saved snapshots + tracks";
        case VCArtifactsModeDiagnostics: return @"diagnostic captures";
    }
    return @"artifacts";
}

static NSString *VCArtifactsEmptyTitle(VCArtifactsMode mode) {
    switch (mode) {
        case VCArtifactsModeTraces: return @"No Traces Yet";
        case VCArtifactsModeDiagrams: return @"No Diagrams Yet";
        case VCArtifactsModeSnapshots: return @"No Snapshots Yet";
        case VCArtifactsModeDiagnostics: return @"No Diagnostics Yet";
    }
    return @"No Artifacts Yet";
}

static NSString *VCArtifactsEmptySubtitle(VCArtifactsMode mode) {
    switch (mode) {
        case VCArtifactsModeTraces:
            return @"Run chat, inspect, or network flows to persist a trace session here.";
        case VCArtifactsModeDiagrams:
            return @"Export a Mermaid view from a trace or workflow to capture a diagram here.";
        case VCArtifactsModeSnapshots:
            return @"Save a memory snapshot or tracking preset to keep it in this shelf.";
        case VCArtifactsModeDiagnostics:
            return @"Recent chat diagnostics and request summaries will appear after the next run.";
    }
    return @"Persist an artifact from chat, memory, or tracking to populate this shelf.";
}

@interface VCArtifactsTab () <UITableViewDataSource, UITableViewDelegate, VCPanelLayoutUpdatable>
@property (nonatomic, strong) UIView *headerCard;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UISegmentedControl *modeControl;
@property (nonatomic, strong) UIButton *refreshButton;
@property (nonatomic, strong) UIStackView *headerControlStack;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *contentDividerView;
@property (nonatomic, strong) UIView *detailCard;
@property (nonatomic, strong) UILabel *detailTitleLabel;
@property (nonatomic, strong) UILabel *detailSubtitleLabel;
@property (nonatomic, strong) UIStackView *detailActionRow;
@property (nonatomic, strong) UIButton *openMemoryButton;
@property (nonatomic, strong) UIButton *draftValueButton;
@property (nonatomic, strong) UIButton *restoreTrackButton;
@property (nonatomic, strong) VCMermaidPreviewView *mermaidPreview;
@property (nonatomic, strong) UITextView *detailTextView;
@property (nonatomic, strong) NSLayoutConstraint *listWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *detailActionHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *previewHeightConstraint;
@property (nonatomic, strong) NSArray<NSDictionary *> *items;
@property (nonatomic, assign) VCArtifactsMode mode;
@property (nonatomic, copy) NSString *selectedIdentifier;
@property (nonatomic, assign) VCPanelLayoutMode currentLayoutMode;
@property (nonatomic, assign) CGRect availableLayoutBounds;
@property (nonatomic, strong) NSDictionary *currentSnapshotDetail;
@property (nonatomic, strong) NSDictionary *currentTrackDetail;
@end

@implementation VCArtifactsTab

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = kVCBgTertiary;
    self.items = @[];
    self.mode = VCArtifactsModeTraces;
    self.availableLayoutBounds = CGRectZero;

    [self _setupHeaderCard];
    [self _setupBrowser];
    [self _clearDetailWithTitle:VCTextLiteral(@"No Artifact Selected") subtitle:VCTextLiteral(@"Pick a trace, diagram, snapshot, or diagnostic record to inspect.")];
    [self _reloadArtifactsPreservingSelection:NO];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_handleAppBecameActive)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    BOOL landscape = self.currentLayoutMode == VCPanelLayoutModeLandscape;
    CGFloat ratio = landscape ? 0.30 : 0.36;
    CGFloat minWidth = landscape ? 188.0 : 168.0;
    CGFloat maxWidth = landscape ? 280.0 : 238.0;
    CGFloat boundsWidth = CGRectIsEmpty(self.availableLayoutBounds) ? CGRectGetWidth(self.view.bounds) : CGRectGetWidth(self.availableLayoutBounds);
    CGFloat targetWidth = MAX(minWidth, MIN(maxWidth, floor(boundsWidth * ratio)));
    self.listWidthConstraint.constant = targetWidth;
    self.contentDividerView.hidden = !landscape;
    self.contentDividerView.alpha = landscape ? 1.0 : 0.0;
    self.statusLabel.font = [UIFont systemFontOfSize:(landscape ? 10.0 : 11.0) weight:UIFontWeightSemibold];
    self.statusLabel.numberOfLines = 1;
    self.subtitleLabel.numberOfLines = landscape ? 1 : 2;
    [self _updateHeaderControlLayoutForWidth:boundsWidth];
    self.detailSubtitleLabel.numberOfLines = landscape ? 1 : 3;
    [self _updateDetailActionLayout];
}

- (void)_updateHeaderControlLayoutForWidth:(CGFloat)width {
    BOOL shouldStackVertically = width < 540.0;
    self.headerControlStack.axis = shouldStackVertically ? UILayoutConstraintAxisVertical : UILayoutConstraintAxisHorizontal;
    self.headerControlStack.alignment = UIStackViewAlignmentFill;
    self.headerControlStack.spacing = shouldStackVertically ? 8.0 : 10.0;
}

- (void)_setupHeaderCard {
    self.headerCard = [[UIView alloc] init];
    VCApplyPanelSurface(self.headerCard, 12.0);
    self.headerCard.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.headerCard];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = VCTextLiteral(@"ARTIFACTS");
    titleLabel.textColor = kVCTextSecondary;
    titleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
    titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [titleLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.headerCard addSubview:titleLabel];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.textColor = kVCTextMuted;
    self.statusLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    self.statusLabel.textAlignment = NSTextAlignmentRight;
    self.statusLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    self.statusLabel.numberOfLines = 1;
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.headerCard addSubview:self.statusLabel];

    self.subtitleLabel = [[UILabel alloc] init];
    self.subtitleLabel.text = VCTextLiteral(@"Saved traces, Mermaid exports, memory snapshots, tracking presets, and chat diagnostics live here.");
    self.subtitleLabel.textColor = kVCTextMuted;
    self.subtitleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    self.subtitleLabel.numberOfLines = 2;
    self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.headerCard addSubview:self.subtitleLabel];

    self.modeControl = [[UISegmentedControl alloc] initWithItems:@[VCTextLiteral(@"Traces"), VCTextLiteral(@"Diagrams"), VCTextLiteral(@"Snapshots"), VCTextLiteral(@"Diagnostics")]];
    self.modeControl.selectedSegmentIndex = 0;
    self.modeControl.apportionsSegmentWidthsByContent = YES;
    self.modeControl.selectedSegmentTintColor = kVCAccent;
    [self.modeControl setTitleTextAttributes:@{NSForegroundColorAttributeName: kVCTextPrimary} forState:UIControlStateNormal];
    [self.modeControl setTitleTextAttributes:@{NSForegroundColorAttributeName: kVCBgPrimary} forState:UIControlStateSelected];
    self.modeControl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.modeControl addTarget:self action:@selector(_modeChanged:) forControlEvents:UIControlEventValueChanged];
    [self.modeControl setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

    self.refreshButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.refreshButton setTitle:VCTextLiteral(@"Refresh") forState:UIControlStateNormal];
    VCApplySecondaryButtonStyle(self.refreshButton);
    self.refreshButton.contentEdgeInsets = UIEdgeInsetsMake(6, 10, 6, 10);
    VCApplyCompactIconTitleButtonLayout(self.refreshButton, @"arrow.clockwise", 11.0);
    VCPrepareButtonTitle(self.refreshButton, NSLineBreakByTruncatingTail, 0.82);
    self.refreshButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.refreshButton addTarget:self action:@selector(_refreshTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.refreshButton setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self.refreshButton setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    self.headerControlStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.modeControl, self.refreshButton]];
    self.headerControlStack.axis = UILayoutConstraintAxisHorizontal;
    self.headerControlStack.alignment = UIStackViewAlignmentFill;
    self.headerControlStack.spacing = 10.0;
    self.headerControlStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.headerCard addSubview:self.headerControlStack];

    [NSLayoutConstraint activateConstraints:@[
        [self.headerCard.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:10],
        [self.headerCard.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10],
        [self.headerCard.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],

        [titleLabel.topAnchor constraintEqualToAnchor:self.headerCard.topAnchor constant:10],
        [titleLabel.leadingAnchor constraintEqualToAnchor:self.headerCard.leadingAnchor constant:12],
        [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.statusLabel.leadingAnchor constant:-8],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.headerCard.trailingAnchor constant:-12],
        [self.statusLabel.centerYAnchor constraintEqualToAnchor:titleLabel.centerYAnchor],
        [self.statusLabel.widthAnchor constraintLessThanOrEqualToAnchor:self.headerCard.widthAnchor multiplier:0.58],

        [self.subtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:6],
        [self.subtitleLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [self.subtitleLabel.trailingAnchor constraintEqualToAnchor:self.headerCard.trailingAnchor constant:-12],

        [self.headerControlStack.topAnchor constraintEqualToAnchor:self.subtitleLabel.bottomAnchor constant:10],
        [self.headerControlStack.leadingAnchor constraintEqualToAnchor:self.headerCard.leadingAnchor constant:12],
        [self.headerControlStack.trailingAnchor constraintEqualToAnchor:self.headerCard.trailingAnchor constant:-12],
        [self.headerControlStack.bottomAnchor constraintEqualToAnchor:self.headerCard.bottomAnchor constant:-12],
        [self.refreshButton.heightAnchor constraintEqualToConstant:30]
    ]];
}

- (void)_setupBrowser {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    VCApplyPanelSurface(self.tableView, 12.0);
    self.tableView.separatorColor = [kVCBorder colorWithAlphaComponent:0.65];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tableView];

    self.contentDividerView = [[UIView alloc] init];
    self.contentDividerView.backgroundColor = [kVCBorderStrong colorWithAlphaComponent:0.34];
    self.contentDividerView.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentDividerView.hidden = YES;
    self.contentDividerView.alpha = 0.0;
    [self.view addSubview:self.contentDividerView];

    self.detailCard = [[UIView alloc] init];
    VCApplyPanelSurface(self.detailCard, 12.0);
    self.detailCard.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.detailCard];

    self.detailTitleLabel = [[UILabel alloc] init];
    self.detailTitleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    self.detailTitleLabel.textColor = kVCTextPrimary;
    self.detailTitleLabel.numberOfLines = 2;
    self.detailTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.detailCard addSubview:self.detailTitleLabel];

    self.detailSubtitleLabel = [[UILabel alloc] init];
    self.detailSubtitleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    self.detailSubtitleLabel.textColor = kVCTextMuted;
    self.detailSubtitleLabel.numberOfLines = 3;
    self.detailSubtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.detailCard addSubview:self.detailSubtitleLabel];

    self.openMemoryButton = VCArtifactsActionButton(@"Open in Memory");
    VCSetButtonSymbol(self.openMemoryButton, @"memorychip");
    [self.openMemoryButton addTarget:self action:@selector(_openCurrentSnapshotInMemory) forControlEvents:UIControlEventTouchUpInside];
    self.draftValueButton = VCArtifactsActionButton(@"Draft Value Lock");
    VCSetButtonSymbol(self.draftValueButton, @"slider.horizontal.3");
    [self.draftValueButton addTarget:self action:@selector(_draftValueLockFromCurrentSnapshot) forControlEvents:UIControlEventTouchUpInside];
    self.restoreTrackButton = VCArtifactsActionButton(@"Restore Track");
    VCSetButtonSymbol(self.restoreTrackButton, @"scope");
    [self.restoreTrackButton addTarget:self action:@selector(_restoreCurrentTrack) forControlEvents:UIControlEventTouchUpInside];

    self.detailActionRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.openMemoryButton, self.draftValueButton, self.restoreTrackButton]];
    self.detailActionRow.axis = UILayoutConstraintAxisHorizontal;
    self.detailActionRow.spacing = 8.0;
    self.detailActionRow.distribution = UIStackViewDistributionFillEqually;
    self.detailActionRow.translatesAutoresizingMaskIntoConstraints = NO;
    [self.detailCard addSubview:self.detailActionRow];

    self.mermaidPreview = [[VCMermaidPreviewView alloc] initWithFrame:CGRectZero];
    self.mermaidPreview.translatesAutoresizingMaskIntoConstraints = NO;
    [self.detailCard addSubview:self.mermaidPreview];

    self.detailTextView = [[UITextView alloc] init];
    VCApplyInputSurface(self.detailTextView, 10.0);
    self.detailTextView.textColor = kVCTextPrimary;
    self.detailTextView.font = [UIFont monospacedSystemFontOfSize:11.5 weight:UIFontWeightRegular];
    self.detailTextView.editable = NO;
    self.detailTextView.alwaysBounceVertical = YES;
    self.detailTextView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.detailCard addSubview:self.detailTextView];

    self.listWidthConstraint = [self.tableView.widthAnchor constraintEqualToConstant:208.0];
    self.detailActionHeightConstraint = [self.detailActionRow.heightAnchor constraintEqualToConstant:0.0];
    self.previewHeightConstraint = [self.mermaidPreview.heightAnchor constraintEqualToConstant:0.0];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.headerCard.bottomAnchor constant:10],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-10],
        self.listWidthConstraint,
        [self.contentDividerView.leadingAnchor constraintEqualToAnchor:self.tableView.trailingAnchor constant:5.5],
        [self.contentDividerView.trailingAnchor constraintEqualToAnchor:self.detailCard.leadingAnchor constant:-5.5],
        [self.contentDividerView.widthAnchor constraintEqualToConstant:1.0],
        [self.contentDividerView.topAnchor constraintEqualToAnchor:self.tableView.topAnchor constant:4.0],
        [self.contentDividerView.bottomAnchor constraintEqualToAnchor:self.tableView.bottomAnchor constant:-4.0],

        [self.detailCard.topAnchor constraintEqualToAnchor:self.tableView.topAnchor],
        [self.detailCard.leadingAnchor constraintEqualToAnchor:self.tableView.trailingAnchor constant:10],
        [self.detailCard.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],
        [self.detailCard.bottomAnchor constraintEqualToAnchor:self.tableView.bottomAnchor],

        [self.detailTitleLabel.topAnchor constraintEqualToAnchor:self.detailCard.topAnchor constant:12],
        [self.detailTitleLabel.leadingAnchor constraintEqualToAnchor:self.detailCard.leadingAnchor constant:12],
        [self.detailTitleLabel.trailingAnchor constraintEqualToAnchor:self.detailCard.trailingAnchor constant:-12],

        [self.detailSubtitleLabel.topAnchor constraintEqualToAnchor:self.detailTitleLabel.bottomAnchor constant:4],
        [self.detailSubtitleLabel.leadingAnchor constraintEqualToAnchor:self.detailTitleLabel.leadingAnchor],
        [self.detailSubtitleLabel.trailingAnchor constraintEqualToAnchor:self.detailTitleLabel.trailingAnchor],

        [self.detailActionRow.topAnchor constraintEqualToAnchor:self.detailSubtitleLabel.bottomAnchor constant:8],
        [self.detailActionRow.leadingAnchor constraintEqualToAnchor:self.detailCard.leadingAnchor constant:12],
        [self.detailActionRow.trailingAnchor constraintEqualToAnchor:self.detailCard.trailingAnchor constant:-12],
        self.detailActionHeightConstraint,

        [self.mermaidPreview.topAnchor constraintEqualToAnchor:self.detailActionRow.bottomAnchor constant:8],
        [self.mermaidPreview.leadingAnchor constraintEqualToAnchor:self.detailCard.leadingAnchor constant:12],
        [self.mermaidPreview.trailingAnchor constraintEqualToAnchor:self.detailCard.trailingAnchor constant:-12],
        self.previewHeightConstraint,

        [self.detailTextView.topAnchor constraintEqualToAnchor:self.mermaidPreview.bottomAnchor constant:8],
        [self.detailTextView.leadingAnchor constraintEqualToAnchor:self.detailCard.leadingAnchor constant:12],
        [self.detailTextView.trailingAnchor constraintEqualToAnchor:self.detailCard.trailingAnchor constant:-12],
        [self.detailTextView.bottomAnchor constraintEqualToAnchor:self.detailCard.bottomAnchor constant:-12]
    ]];

    [self _setDetailActionsVisible:NO];
}

- (void)_handleAppBecameActive {
    [self _reloadArtifactsPreservingSelection:YES];
}

- (void)_modeChanged:(UISegmentedControl *)control {
    self.mode = (VCArtifactsMode)control.selectedSegmentIndex;
    self.selectedIdentifier = nil;
    [self _reloadArtifactsPreservingSelection:NO];
}

- (void)openArtifactsModeNamed:(NSString *)modeName {
    NSString *normalized = [VCArtifactsSafeString(modeName) lowercaseString];
    VCArtifactsMode targetMode = self.mode;
    if ([normalized isEqualToString:VCArtifactsOpenModeDiagnosticsValue]) {
        targetMode = VCArtifactsModeDiagnostics;
    } else if ([normalized isEqualToString:@"traces"]) {
        targetMode = VCArtifactsModeTraces;
    } else if ([normalized isEqualToString:@"diagrams"]) {
        targetMode = VCArtifactsModeDiagrams;
    } else if ([normalized isEqualToString:@"snapshots"] || [normalized isEqualToString:@"saved"]) {
        targetMode = VCArtifactsModeSnapshots;
    }

    self.mode = targetMode;
    self.modeControl.selectedSegmentIndex = targetMode;
    self.selectedIdentifier = nil;
    [self _reloadArtifactsPreservingSelection:NO];
}

- (void)_refreshTapped {
    [self _reloadArtifactsPreservingSelection:YES];
}

- (NSArray<NSDictionary *> *)_itemsForCurrentMode {
    switch (self.mode) {
        case VCArtifactsModeTraces:
            return [[VCTraceManager shared] sessionSummariesWithLimit:60] ?: @[];
        case VCArtifactsModeDiagrams:
            return VCArtifactsMermaidSummaries(80);
        case VCArtifactsModeSnapshots:
            return VCArtifactsCombinedSavedSummaries(80);
        case VCArtifactsModeDiagnostics:
            return VCArtifactsDiagnosticsSummaries(120);
    }
}

- (NSString *)_identifierForItem:(NSDictionary *)item {
    switch (self.mode) {
        case VCArtifactsModeTraces:
            return VCArtifactsSafeString(item[@"sessionID"]);
        case VCArtifactsModeDiagrams:
            return VCArtifactsSafeString(item[@"artifactID"]);
        case VCArtifactsModeSnapshots:
            return VCArtifactsSafeString(item[@"snapshotID"]).length > 0
                ? VCArtifactsSafeString(item[@"snapshotID"])
                : (VCArtifactsSafeString(item[@"trackerID"]).length > 0
                   ? VCArtifactsSafeString(item[@"trackerID"])
                   : VCArtifactsSafeString(item[@"path"]));
        case VCArtifactsModeDiagnostics:
            return VCArtifactsSafeString(item[@"artifactID"]).length > 0
                ? VCArtifactsSafeString(item[@"artifactID"])
                : VCArtifactsSafeString(item[@"path"]);
    }
}

- (void)_reloadArtifactsPreservingSelection:(BOOL)preserveSelection {
    NSString *previousIdentifier = preserveSelection ? self.selectedIdentifier : nil;
    self.items = [self _itemsForCurrentMode] ?: @[];
    [self.tableView reloadData];

    self.statusLabel.text = [NSString stringWithFormat:@"%@ %@",
                             @(self.items.count),
                             VCArtifactsModeCollectionLabel(self.mode) ?: @"artifacts"];

    NSInteger targetIndex = NSNotFound;
    if (previousIdentifier.length > 0) {
        for (NSUInteger idx = 0; idx < self.items.count; idx++) {
            if ([[self _identifierForItem:self.items[idx]] isEqualToString:previousIdentifier]) {
                targetIndex = (NSInteger)idx;
                break;
            }
        }
    }
    if (targetIndex == NSNotFound && self.items.count > 0) targetIndex = 0;

    if (targetIndex != NSNotFound) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:targetIndex inSection:0];
        [self.tableView selectRowAtIndexPath:indexPath animated:NO scrollPosition:UITableViewScrollPositionNone];
        [self tableView:self.tableView didSelectRowAtIndexPath:indexPath];
    } else {
        [self _clearDetailWithTitle:VCArtifactsEmptyTitle(self.mode)
                           subtitle:VCArtifactsEmptySubtitle(self.mode)];
    }
}

- (void)_clearDetailWithTitle:(NSString *)title subtitle:(NSString *)subtitle {
    self.currentSnapshotDetail = nil;
    self.currentTrackDetail = nil;
    self.detailTitleLabel.text = title;
    self.detailSubtitleLabel.text = subtitle;
    self.detailTextView.text = @"";
    self.previewHeightConstraint.constant = 0.0;
    self.mermaidPreview.hidden = YES;
    [self _setDetailActionsVisible:NO];
}

- (void)_showMermaidIfPossibleWithTitle:(NSString *)title summary:(NSString *)summary content:(NSString *)content diagramType:(NSString *)diagramType {
    NSString *trimmed = VCArtifactsTrim(content);
    if (trimmed.length == 0) {
        self.previewHeightConstraint.constant = 0.0;
        self.mermaidPreview.hidden = YES;
        return;
    }

    [self.mermaidPreview configureWithTitle:title ?: @"Diagram"
                                    summary:summary ?: @""
                                    content:trimmed
                                diagramType:diagramType ?: @"diagram"];
    self.previewHeightConstraint.constant = self.currentLayoutMode == VCPanelLayoutModeLandscape ? 220.0 : 248.0;
    self.mermaidPreview.hidden = NO;
}

- (void)_updateDetailActionLayout {
    NSArray<UIButton *> *actionButtons = @[
        self.openMemoryButton,
        self.draftValueButton,
        self.restoreTrackButton
    ];
    NSInteger visibleActionCount = 0;
    for (UIButton *button in actionButtons) {
        if (button && !button.hidden) {
            visibleActionCount += 1;
        }
    }

    BOOL landscape = self.currentLayoutMode == VCPanelLayoutModeLandscape;
    CGFloat availableWidth = CGRectGetWidth(self.detailCard.bounds);
    BOOL prefersVerticalActions = (visibleActionCount > 1) && (!landscape || availableWidth < 360.0);

    self.detailActionRow.axis = prefersVerticalActions ? UILayoutConstraintAxisVertical : UILayoutConstraintAxisHorizontal;
    self.detailActionRow.alignment = UIStackViewAlignmentFill;
    self.detailActionRow.distribution = prefersVerticalActions ? UIStackViewDistributionFill : UIStackViewDistributionFillEqually;

    if (visibleActionCount == 0 || self.detailActionRow.hidden) {
        self.detailActionHeightConstraint.constant = 0.0;
        return;
    }

    CGFloat rowHeight = 34.0;
    CGFloat spacing = self.detailActionRow.spacing;
    self.detailActionHeightConstraint.constant = prefersVerticalActions
        ? ((rowHeight * visibleActionCount) + (spacing * MAX(0, visibleActionCount - 1)))
        : rowHeight;
}

- (void)_setDetailActionsVisible:(BOOL)visible {
    self.detailActionRow.hidden = !visible;
    NSDictionary *snapshot = self.currentSnapshotDetail;
    NSDictionary *track = self.currentTrackDetail;
    self.openMemoryButton.hidden = !(visible && snapshot != nil);
    self.draftValueButton.hidden = !(visible && snapshot != nil);
    self.restoreTrackButton.hidden = !(visible && track != nil);
    self.openMemoryButton.enabled = visible && [self _snapshotCanOpenInMemory:snapshot];
    self.draftValueButton.enabled = visible && [self _snapshotCanDraftValueLock:snapshot];
    self.restoreTrackButton.enabled = visible && [track isKindOfClass:[NSDictionary class]];
    self.openMemoryButton.alpha = self.openMemoryButton.enabled ? 1.0 : 0.45;
    self.draftValueButton.alpha = self.draftValueButton.enabled ? 1.0 : 0.45;
    self.restoreTrackButton.alpha = self.restoreTrackButton.enabled ? 1.0 : 0.45;
    [self _updateDetailActionLayout];
}

- (NSString *)_addressStringForSnapshot:(NSDictionary *)snapshot {
    NSString *address = VCArtifactsSafeString(snapshot[@"address"]);
    if (address.length == 0) {
        address = VCArtifactsSafeString(snapshot[@"snapshotAddress"]);
    }
    if (address.length == 0) {
        address = VCArtifactsSafeString(snapshot[@"resolvedAddress"]);
    }
    return address;
}

- (BOOL)_snapshotCanOpenInMemory:(NSDictionary *)snapshot {
    return [self _addressStringForSnapshot:snapshot].length > 0;
}

- (BOOL)_snapshotCanDraftValueLock:(NSDictionary *)snapshot {
    return [self _addressStringForSnapshot:snapshot].length > 0;
}

- (NSDictionary *)_snapshotDetailForItem:(NSDictionary *)item {
    if (![item isKindOfClass:[NSDictionary class]]) return nil;
    return VCArtifactsLoadMemorySnapshotAtPath(item[@"path"]);
}

- (NSDictionary *)_trackDetailForItem:(NSDictionary *)item {
    if (![item isKindOfClass:[NSDictionary class]]) return nil;
    NSString *path = VCArtifactsSafeString(item[@"path"]);
    NSString *trackerID = VCArtifactsSafeString(item[@"trackerID"]);
    return [[VCOverlayTrackingManager shared] savedTrackerDetailFromPath:(path.length > 0 ? path : nil)
                                                              trackerID:(trackerID.length > 0 ? trackerID : nil)];
}

- (void)_openSnapshotInMemory:(NSDictionary *)snapshot {
    NSString *address = [self _addressStringForSnapshot:snapshot];
    if (address.length == 0) return;
    [[NSNotificationCenter defaultCenter] postNotificationName:VCMemoryBrowserRequestOpenAddressNotification
                                                        object:self
                                                      userInfo:@{ VCMemoryBrowserOpenAddressKey: address }];
}

- (void)_draftValueLockFromSnapshot:(NSDictionary *)snapshot {
    NSString *addressString = [self _addressStringForSnapshot:snapshot];
    uintptr_t address = (uintptr_t)strtoull(addressString.UTF8String, NULL, 0);
    if (address == 0) return;

    VCValueItem *draft = [[VCValueItem alloc] init];
    NSString *moduleName = VCArtifactsSafeString(snapshot[@"moduleName"]);
    NSString *rva = VCArtifactsSafeString(snapshot[@"rva"]);
    NSString *title = VCArtifactsSafeString(snapshot[@"title"]);
    NSString *targetDesc = title.length > 0 ? title : [NSString stringWithFormat:@"Memory %@", addressString];
    if (moduleName.length > 0 && rva.length > 0) {
        targetDesc = [NSString stringWithFormat:@"%@ (%@ %@)", targetDesc, moduleName, rva];
    }

    draft.targetDesc = targetDesc;
    draft.address = address;
    draft.dataType = VCArtifactsSafeString(snapshot[@"typeEncoding"]).length > 0 ? VCArtifactsSafeString(snapshot[@"typeEncoding"]) : @"int";
    draft.modifiedValue = @"";
    draft.remark = VCArtifactsPrettyJSONString(snapshot);

    [[NSNotificationCenter defaultCenter] postNotificationName:VCPatchesRequestOpenEditorNotification
                                                        object:self
                                                      userInfo:@{
        VCPatchesOpenEditorSegmentKey: @1,
        VCPatchesOpenEditorItemKey: draft,
        VCPatchesOpenEditorCreatesKey: @YES
    }];
}

- (void)_openCurrentSnapshotInMemory {
    NSDictionary *snapshot = self.currentSnapshotDetail;
    [self _openSnapshotInMemory:snapshot];
}

- (void)_draftValueLockFromCurrentSnapshot {
    NSDictionary *snapshot = self.currentSnapshotDetail;
    [self _draftValueLockFromSnapshot:snapshot];
}

- (void)_restoreTrackDetail:(NSDictionary *)track {
    NSString *path = VCArtifactsSafeString(track[@"path"]);
    NSString *trackerID = VCArtifactsSafeString(track[@"trackerID"]);
    if (path.length == 0 && trackerID.length == 0) return;
    [[VCOverlayTrackingManager shared] restoreTrackerFromPath:(path.length > 0 ? path : nil)
                                                    trackerID:(trackerID.length > 0 ? trackerID : nil)];
}

- (void)_restoreCurrentTrack {
    [self _restoreTrackDetail:self.currentTrackDetail];
}

- (void)vc_applyPanelLayoutMode:(VCPanelLayoutMode)mode
                availableBounds:(CGRect)bounds
                 safeAreaInsets:(UIEdgeInsets)safeAreaInsets {
    self.currentLayoutMode = mode;
    self.availableLayoutBounds = bounds;
    [self.view setNeedsLayout];
}

- (void)_showDetailForTrace:(NSDictionary *)item {
    self.currentSnapshotDetail = nil;
    self.currentTrackDetail = nil;
    [self _setDetailActionsVisible:NO];
    NSString *sessionID = VCArtifactsSafeString(item[@"sessionID"]);
    NSDictionary *detail = [[VCTraceManager shared] sessionDetailForSession:sessionID eventLimit:120];
    NSDictionary *session = [detail[@"session"] isKindOfClass:[NSDictionary class]] ? detail[@"session"] : @{};
    NSString *name = VCArtifactsSafeString(session[@"name"]);
    if (name.length == 0) name = sessionID.length > 0 ? sessionID : @"Trace Session";

    NSString *subtitle = [NSString stringWithFormat:@"%@ events · %@ checkpoints · %@",
                          item[@"eventCount"] ?: @0,
                          item[@"checkpointCount"] ?: @0,
                          [session[@"active"] boolValue] ? @"active" : @"saved"];
    self.detailTitleLabel.text = name;
    self.detailSubtitleLabel.text = [NSString stringWithFormat:@"%@\n%@",
                                     subtitle,
                                     detail[@"eventsPath"] ?: @"No events path"];

    NSString *exportError = nil;
    NSDictionary *diagram = [[VCTraceManager shared] exportMermaidForSession:sessionID
                                                                       style:@"call_tree"
                                                                       title:[NSString stringWithFormat:@"%@ Call Tree", name]
                                                                       limit:120
                                                                errorMessage:&exportError];
    if ([diagram isKindOfClass:[NSDictionary class]] && [VCArtifactsSafeString(diagram[@"content"]) length] > 0) {
        [self _showMermaidIfPossibleWithTitle:diagram[@"title"]
                                      summary:diagram[@"summary"]
                                      content:diagram[@"content"]
                                  diagramType:@"trace"];
    } else {
        self.previewHeightConstraint.constant = 0.0;
        self.mermaidPreview.hidden = YES;
    }

    NSMutableDictionary *payload = [NSMutableDictionary new];
    if (session.count > 0) payload[@"session"] = session;
    if ([detail[@"checkpoints"] isKindOfClass:[NSArray class]]) payload[@"checkpoints"] = detail[@"checkpoints"];
    if ([detail[@"callTree"] isKindOfClass:[NSDictionary class]]) payload[@"callTree"] = detail[@"callTree"];
    if ([detail[@"events"] isKindOfClass:[NSArray class]]) payload[@"events"] = detail[@"events"];
    payload[@"eventsPath"] = detail[@"eventsPath"] ?: @"";
    self.detailTextView.text = VCArtifactsPrettyJSONString(payload);
}

- (void)_showDetailForDiagram:(NSDictionary *)item {
    self.currentSnapshotDetail = nil;
    self.currentTrackDetail = nil;
    [self _setDetailActionsVisible:NO];
    NSDictionary *artifact = VCArtifactsLoadMermaidArtifactAtPath(item[@"path"]);
    if (!artifact) {
        [self _clearDetailWithTitle:VCTextLiteral(@"Diagram Missing") subtitle:VCTextLiteral(@"The saved Mermaid file could not be loaded.")];
        self.detailTextView.text = @"";
        return;
    }

    NSString *title = VCArtifactsSafeString(artifact[@"title"]);
    NSString *summary = VCArtifactsSafeString(artifact[@"summary"]);
    NSString *path = VCArtifactsSafeString(artifact[@"path"]);
    self.detailTitleLabel.text = title.length > 0 ? title : VCTextLiteral(@"Diagram");
    self.detailSubtitleLabel.text = [NSString stringWithFormat:@"%@ · %@ bytes · %@\n%@",
                                     artifact[@"diagramType"] ?: @"diagram",
                                     artifact[@"byteCount"] ?: @0,
                                     VCArtifactsDateString([artifact[@"createdAt"] doubleValue]),
                                     path];
    [self _showMermaidIfPossibleWithTitle:title
                                  summary:summary
                                  content:artifact[@"content"]
                              diagramType:artifact[@"diagramType"]];

    NSMutableString *source = [NSMutableString new];
    [source appendFormat:@"%@: %@\n", VCTextLiteral(@"Title"), title.length > 0 ? title : VCTextLiteral(@"Diagram")];
    [source appendFormat:@"%@: %@\n", VCTextLiteral(@"Type"), artifact[@"diagramType"] ?: @"diagram"];
    [source appendFormat:@"%@: %@\n", VCTextLiteral(@"Saved"), VCArtifactsDateString([artifact[@"createdAt"] doubleValue])];
    [source appendFormat:@"%@: %@\n", VCTextLiteral(@"Path"), path];
    if (summary.length > 0) [source appendFormat:@"%@: %@\n", VCTextLiteral(@"Summary"), summary];
    [source appendString:@"\n"];
    [source appendString:VCArtifactsSafeString(artifact[@"content"])];
    self.detailTextView.text = [source copy];
}

- (void)_showDetailForSnapshot:(NSDictionary *)item {
    self.currentTrackDetail = nil;
    NSDictionary *snapshot = VCArtifactsLoadMemorySnapshotAtPath(item[@"path"]);
    if (!snapshot) {
        [self _clearDetailWithTitle:VCTextLiteral(@"Snapshot Missing") subtitle:VCTextLiteral(@"The saved memory snapshot could not be loaded.")];
        self.detailTextView.text = @"";
        return;
    }

    self.currentSnapshotDetail = snapshot;
    NSString *queryType = VCArtifactsSafeString(snapshot[@"queryType"]);
    NSString *locatorTitle = VCArtifactsSafeString(snapshot[@"title"]);
    NSString *displayTitle = locatorTitle.length > 0
        ? locatorTitle
        : (VCArtifactsSafeString(snapshot[@"snapshotID"]).length > 0 ? snapshot[@"snapshotID"] : VCTextLiteral(@"Memory Snapshot"));
    self.detailTitleLabel.text = displayTitle;
    NSString *subtitle = [NSString stringWithFormat:@"%@ · %@ bytes · %@\n%@",
                          queryType.length > 0 ? queryType : @"snapshot",
                          item[@"length"] ?: @0,
                          VCArtifactsDateString([snapshot[@"createdAt"] doubleValue]),
                          snapshot[@"path"] ?: @""];
    NSString *locatorSubtitle = VCArtifactsSafeString(snapshot[@"subtitle"]);
    if (locatorSubtitle.length > 0) {
        subtitle = [subtitle stringByAppendingFormat:@"\n%@", locatorSubtitle];
    }
    self.detailSubtitleLabel.text = subtitle;
    self.previewHeightConstraint.constant = 0.0;
    self.mermaidPreview.hidden = YES;
    self.detailTextView.text = VCArtifactsPrettyJSONString(snapshot);
    [self _setDetailActionsVisible:[self _snapshotCanOpenInMemory:snapshot] || [self _snapshotCanDraftValueLock:snapshot]];
}

- (void)_showDetailForTrack:(NSDictionary *)item {
    self.currentSnapshotDetail = nil;
    NSDictionary *track = [self _trackDetailForItem:item];
    if (!track) {
        [self _clearDetailWithTitle:VCTextLiteral(@"Track Missing") subtitle:VCTextLiteral(@"The saved tracking preset could not be loaded.")];
        self.detailTextView.text = @"";
        return;
    }

    self.currentTrackDetail = track;
    NSString *title = VCArtifactsSafeString(track[@"title"]);
    self.detailTitleLabel.text = title.length > 0 ? title : VCTextLiteral(@"Saved Track");
    NSString *subtitle = [NSString stringWithFormat:@"%@ · %@ · %@\n%@",
                          VCArtifactsSafeString(track[@"mode"]).length > 0 ? VCArtifactsSafeString(track[@"mode"]) : @"track",
                          VCArtifactsSafeString(track[@"canvasID"]).length > 0 ? VCArtifactsSafeString(track[@"canvasID"]) : @"tracking",
                          VCArtifactsDateString([track[@"createdAt"] doubleValue]),
                          VCArtifactsSafeString(track[@"path"])];
    NSString *savedSubtitle = VCArtifactsSafeString(track[@"subtitle"]);
    if (savedSubtitle.length > 0) {
        subtitle = [subtitle stringByAppendingFormat:@"\n%@", savedSubtitle];
    }
    self.detailSubtitleLabel.text = subtitle;
    self.previewHeightConstraint.constant = 0.0;
    self.mermaidPreview.hidden = YES;
    self.detailTextView.text = VCArtifactsPrettyJSONString(track);
    [self _setDetailActionsVisible:YES];
}

- (void)_showDetailForDiagnosticsItem:(NSDictionary *)item {
    self.currentSnapshotDetail = nil;
    self.currentTrackDetail = nil;
    [self _setDetailActionsVisible:NO];
    self.previewHeightConstraint.constant = 0.0;
    self.mermaidPreview.hidden = YES;

    NSString *kind = VCArtifactsSafeString(item[@"diagnosticsKind"]);
    if ([kind isEqualToString:@"request_rollup"]) {
        self.detailTitleLabel.text = VCArtifactsSafeString(item[@"title"]).length > 0 ? VCArtifactsSafeString(item[@"title"]) : VCTextLiteral(@"Latency Rollup");
        self.detailSubtitleLabel.text = [NSString stringWithFormat:@"%@ requests · %@ errors · %@\n%@",
                                         item[@"requestCount"] ?: @0,
                                         item[@"errorCount"] ?: @0,
                                         VCArtifactsDateString([item[@"updatedAt"] doubleValue]),
                                         VCArtifactsSafeString(item[@"path"])];

        NSMutableString *detail = [NSMutableString new];
        [detail appendFormat:@"%@: %@\n", VCTextLiteral(@"Updated"), VCArtifactsPreciseDateString([item[@"updatedAt"] doubleValue])];
        [detail appendFormat:@"%@: %@\n", VCTextLiteral(@"Path"), VCArtifactsSafeString(item[@"path"])];
        [detail appendFormat:@"%@: %@\n", VCTextLiteral(@"Request Count"), item[@"requestCount"] ?: @0];
        [detail appendFormat:@"%@: %@\n", VCTextLiteral(@"Success Count"), item[@"successCount"] ?: @0];
        [detail appendFormat:@"%@: %@\n", VCTextLiteral(@"Error Count"), item[@"errorCount"] ?: @0];
        [detail appendFormat:@"%@: %@\n\n", VCTextLiteral(@"Total Stalls"), item[@"totalStalls"] ?: @0];
        [detail appendFormat:@"%@:\n", VCTextLiteral(@"Duration Percentiles")];
        [detail appendFormat:@"P50: %@ ms\n", item[@"p50DurationMS"] ?: @0];
        [detail appendFormat:@"P95: %@ ms\n\n", item[@"p95DurationMS"] ?: @0];
        [detail appendFormat:@"%@:\n", VCTextLiteral(@"Average Chunk Interval Percentiles")];
        [detail appendFormat:@"P50: %@ ms\n", item[@"p50AvgChunkIntervalMS"] ?: @0];
        [detail appendFormat:@"P95: %@ ms\n\n", item[@"p95AvgChunkIntervalMS"] ?: @0];
        [detail appendFormat:@"%@:\n", VCTextLiteral(@"Per-request P95 Chunk Gap Percentiles")];
        [detail appendFormat:@"P50: %@ ms\n", item[@"p50P95ChunkGapMS"] ?: @0];
        [detail appendFormat:@"P95: %@ ms\n\n", item[@"p95P95ChunkGapMS"] ?: @0];
        [detail appendFormat:@"%@:\n", VCTextLiteral(@"Rollup JSON")];
        [detail appendString:VCArtifactsPrettyJSONString(item)];
        self.detailTextView.text = [detail copy];
        return;
    }

    if ([kind isEqualToString:@"recent_events"]) {
        NSDictionary *payload = VCArtifactsLoadDiagnosticsRecentSummary();
        if (!payload) {
            [self _clearDetailWithTitle:VCTextLiteral(@"Diagnostics Missing") subtitle:VCTextLiteral(@"The recent diagnostics snapshot could not be loaded.")];
            return;
        }

        NSArray *events = [payload[@"events"] isKindOfClass:[NSArray class]] ? payload[@"events"] : @[];
        NSString *activeRequestID = VCArtifactsSafeString(payload[@"activeRequestID"]);
        NSString *activeSessionID = VCArtifactsSafeString(payload[@"activeSessionID"]);
        self.detailTitleLabel.text = VCArtifactsSafeString(payload[@"title"]).length > 0 ? VCArtifactsSafeString(payload[@"title"]) : VCTextLiteral(@"Recent Event Buffer");
        self.detailSubtitleLabel.text = [NSString stringWithFormat:@"%@ events · %@ · %@\n%@",
                                         payload[@"eventCount"] ?: @(events.count),
                                         activeRequestID.length > 0 ? [NSString stringWithFormat:@"active %@", VCArtifactsShortIdentifier(activeRequestID)] : @"idle",
                                         VCArtifactsDateString([payload[@"updatedAt"] doubleValue]),
                                         VCArtifactsSafeString(payload[@"path"])];

        NSMutableString *detail = [NSMutableString new];
        [detail appendFormat:@"Updated: %@\n", VCArtifactsPreciseDateString([payload[@"updatedAt"] doubleValue])];
        [detail appendFormat:@"Path: %@\n", VCArtifactsSafeString(payload[@"path"])];
        [detail appendFormat:@"Active Session: %@\n", activeSessionID.length > 0 ? activeSessionID : @"-"];
        [detail appendFormat:@"Active Request: %@\n", activeRequestID.length > 0 ? activeRequestID : @"-"];
        [detail appendFormat:@"Event Count: %@\n\n", payload[@"eventCount"] ?: @(events.count)];
        [detail appendString:@"Recent Timeline:\n"];
        [detail appendString:VCArtifactsFormattedDiagnosticEvents(events, nil, 80)];
        [detail appendString:@"\n\nRaw Snapshot:\n"];
        [detail appendString:VCArtifactsPrettyJSONString(payload)];
        self.detailTextView.text = [detail copy];
        return;
    }

    NSString *requestID = VCArtifactsSafeString(item[@"requestID"]);
    NSString *path = VCArtifactsSafeString(item[@"path"]);
    NSString *subphase = VCArtifactsSafeString(item[@"subphase"]);
    NSDictionary *extra = [item[@"extra"] isKindOfClass:[NSDictionary class]] ? item[@"extra"] : @{};
    NSDictionary *recent = VCArtifactsLoadDiagnosticsRecentSummary();
    NSArray *recentEvents = [recent[@"events"] isKindOfClass:[NSArray class]] ? recent[@"events"] : @[];

    self.detailTitleLabel.text = VCArtifactsSafeString(item[@"title"]).length > 0 ? VCArtifactsSafeString(item[@"title"]) : @"Request Summary";
    self.detailSubtitleLabel.text = [NSString stringWithFormat:@"%@ · %@ · %@\n%@",
                                     subphase.length > 0 ? subphase : @"finish",
                                     [item[@"durationMS"] isKindOfClass:[NSNumber class]] ? [NSString stringWithFormat:@"%@ ms", item[@"durationMS"]] : @"-",
                                     VCArtifactsDateString([item[@"createdAt"] doubleValue]),
                                     path];

    NSMutableString *detail = [NSMutableString new];
    [detail appendFormat:@"Recorded: %@\n", VCArtifactsPreciseDateString([item[@"createdAt"] doubleValue])];
    [detail appendFormat:@"Path: %@\n", path];
    [detail appendFormat:@"Request ID: %@\n", requestID.length > 0 ? requestID : @"-"];
    [detail appendFormat:@"Session ID: %@\n", VCArtifactsSafeString(item[@"sessionID"]).length > 0 ? VCArtifactsSafeString(item[@"sessionID"]) : @"-"];
    [detail appendFormat:@"Result: %@\n", subphase.length > 0 ? subphase : @"finish"];
    [detail appendFormat:@"Duration: %@ ms\n", [item[@"durationMS"] isKindOfClass:[NSNumber class]] ? item[@"durationMS"] : @0];
    if (extra.count > 0) {
        [detail appendFormat:@"Chunk Count: %@\n", extra[@"chunkCount"] ?: @0];
        [detail appendFormat:@"Stall Count: %@\n", extra[@"stallCount"] ?: @0];
        [detail appendFormat:@"Visible Length: %@\n", extra[@"visibleLength"] ?: @0];
    }
    [detail appendString:@"\nRequest Summary JSON:\n"];
    [detail appendString:VCArtifactsPrettyJSONString(item)];

    NSString *timeline = VCArtifactsFormattedDiagnosticEvents(recentEvents, requestID, 36);
    if (timeline.length > 0) {
        [detail appendString:@"\n\nMatching Recent Events:\n"];
        [detail appendString:timeline];
    }
    self.detailTextView.text = [detail copy];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kVCArtifactsCellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kVCArtifactsCellID];
    }

    NSDictionary *item = self.items[indexPath.row];
    cell.backgroundColor = [UIColor clearColor];
    cell.textLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    cell.textLabel.textColor = kVCTextPrimary;
    cell.detailTextLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    cell.detailTextLabel.textColor = kVCTextMuted;
    cell.detailTextLabel.numberOfLines = 2;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    switch (self.mode) {
        case VCArtifactsModeTraces: {
            cell.imageView.image = [UIImage systemImageNamed:@"point.3.connected.trianglepath.dotted"];
            NSString *name = VCArtifactsSafeString(item[@"name"]);
            cell.textLabel.text = name.length > 0 ? name : (item[@"sessionID"] ?: @"Trace");
            cell.detailTextLabel.text = [NSString stringWithFormat:@"Trace session · %@ events · %@ checkpoints · %@",
                                         item[@"eventCount"] ?: @0,
                                         item[@"checkpointCount"] ?: @0,
                                         [item[@"active"] boolValue] ? @"active" : VCArtifactsDateString([item[@"startedAt"] doubleValue])];
            break;
        }
        case VCArtifactsModeDiagrams: {
            cell.imageView.image = [UIImage systemImageNamed:@"square.stack.3d.up"];
            cell.textLabel.text = item[@"title"] ?: @"Diagram";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"Mermaid export · %@ · %@ lines · %@",
                                         item[@"diagramType"] ?: @"diagram",
                                         item[@"lineCount"] ?: @0,
                                         VCArtifactsDateString([item[@"createdAt"] doubleValue])];
            break;
        }
        case VCArtifactsModeSnapshots: {
            NSString *queryType = VCArtifactsSafeString(item[@"queryType"]);
            BOOL isLocator = [queryType isEqualToString:@"locator"];
            BOOL isTrack = [queryType isEqualToString:@"track"];
            cell.imageView.image = [UIImage systemImageNamed:(isTrack ? @"location.circle" : (isLocator ? @"scope" : @"memorychip"))];
            NSString *snapshotID = VCArtifactsSafeString(item[@"snapshotID"]);
            NSString *moduleName = VCArtifactsSafeString(item[@"moduleName"]);
            NSString *title = VCArtifactsSafeString(item[@"title"]);
            cell.textLabel.text = title.length > 0 ? title : (snapshotID.length > 0 ? snapshotID : (VCArtifactsSafeString(item[@"trackerID"]).length > 0 ? VCArtifactsSafeString(item[@"trackerID"]) : @"Saved Item"));
            if (isTrack) {
                cell.detailTextLabel.text = [NSString stringWithFormat:@"Saved track · %@ · %@ · %@",
                                             queryType.length > 0 ? queryType : @"track",
                                             VCArtifactsSafeString(item[@"mode"]).length > 0 ? VCArtifactsSafeString(item[@"mode"]) : @"tracker",
                                             VCArtifactsDateString([item[@"createdAt"] doubleValue])];
            } else {
                cell.detailTextLabel.text = [NSString stringWithFormat:@"Memory snapshot · %@ · %@ bytes%@",
                                             queryType.length > 0 ? queryType : @"snapshot",
                                             item[@"length"] ?: @0,
                                             moduleName.length > 0 ? [NSString stringWithFormat:@" · %@", moduleName] : @""];
            }
            break;
        }
        case VCArtifactsModeDiagnostics: {
            NSString *kind = VCArtifactsSafeString(item[@"diagnosticsKind"]);
            BOOL isRollup = [kind isEqualToString:@"request_rollup"];
            BOOL isRecent = [kind isEqualToString:@"recent_events"];
            cell.imageView.image = [UIImage systemImageNamed:(isRollup ? @"speedometer" : (isRecent ? @"waveform.path.ecg" : @"clock.arrow.circlepath"))];
            cell.textLabel.text = VCArtifactsSafeString(item[@"title"]).length > 0 ? VCArtifactsSafeString(item[@"title"]) : (isRollup ? @"Latency Rollup" : (isRecent ? @"Recent Event Buffer" : @"Request Summary"));
            if (isRollup) {
                cell.detailTextLabel.text = [NSString stringWithFormat:@"Chat diagnostics · %@ req · P50 %@ ms · P95 %@ ms",
                                             item[@"requestCount"] ?: @0,
                                             item[@"p50DurationMS"] ?: @0,
                                             item[@"p95DurationMS"] ?: @0];
            } else if (isRecent) {
                NSString *activeRequestID = VCArtifactsSafeString(item[@"activeRequestID"]);
                cell.detailTextLabel.text = [NSString stringWithFormat:@"Chat diagnostics · %@ events · %@ · %@",
                                             item[@"eventCount"] ?: @0,
                                             activeRequestID.length > 0 ? [NSString stringWithFormat:@"active %@", VCArtifactsShortIdentifier(activeRequestID)] : @"idle",
                                             VCArtifactsDateString([item[@"updatedAt"] doubleValue])];
            } else {
                NSDictionary *extra = [item[@"extra"] isKindOfClass:[NSDictionary class]] ? item[@"extra"] : @{};
                cell.detailTextLabel.text = [NSString stringWithFormat:@"Chat diagnostics · %@ · %@ ms · %@ chunks",
                                             VCArtifactsSafeString(item[@"subphase"]).length > 0 ? VCArtifactsSafeString(item[@"subphase"]) : @"finish",
                                             [item[@"durationMS"] isKindOfClass:[NSNumber class]] ? item[@"durationMS"] : @0,
                                             extra[@"chunkCount"] ?: @0];
            }
            break;
        }
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row >= self.items.count) return;
    NSDictionary *item = self.items[indexPath.row];
    self.selectedIdentifier = [self _identifierForItem:item];

    switch (self.mode) {
        case VCArtifactsModeTraces:
            [self _showDetailForTrace:item];
            break;
        case VCArtifactsModeDiagrams:
            [self _showDetailForDiagram:item];
            break;
        case VCArtifactsModeSnapshots:
            if ([VCArtifactsSafeString(item[@"queryType"]) isEqualToString:@"track"]) {
                [self _showDetailForTrack:item];
            } else {
                [self _showDetailForSnapshot:item];
            }
            break;
        case VCArtifactsModeDiagnostics:
            [self _showDetailForDiagnosticsItem:item];
            break;
    }
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.mode != VCArtifactsModeSnapshots || indexPath.row >= self.items.count) return nil;

    NSDictionary *item = self.items[indexPath.row];
    if ([VCArtifactsSafeString(item[@"queryType"]) isEqualToString:@"track"]) {
        NSDictionary *track = [self _trackDetailForItem:item];
        if (![track isKindOfClass:[NSDictionary class]] || track.count == 0) return nil;
        __weak __typeof__(self) weakSelf = self;
        UIContextualAction *restoreAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                                    title:VCTextLiteral(@"Restore")
                                                                                  handler:^(__unused UIContextualAction * _Nonnull action, __unused UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
            weakSelf.selectedIdentifier = [weakSelf _identifierForItem:item];
            [weakSelf _showDetailForTrack:item];
            [weakSelf _restoreTrackDetail:track];
            completionHandler(YES);
        }];
        restoreAction.backgroundColor = kVCAccent;
        UISwipeActionsConfiguration *config = [UISwipeActionsConfiguration configurationWithActions:@[restoreAction]];
        config.performsFirstActionWithFullSwipe = NO;
        return config;
    }

    NSDictionary *snapshot = [self _snapshotDetailForItem:item];
    if (![snapshot isKindOfClass:[NSDictionary class]] || snapshot.count == 0) return nil;

    BOOL canOpen = [self _snapshotCanOpenInMemory:snapshot];
    BOOL canDraft = [self _snapshotCanDraftValueLock:snapshot];
    if (!canOpen && !canDraft) return nil;

    __weak __typeof__(self) weakSelf = self;
    NSMutableArray<UIContextualAction *> *actions = [NSMutableArray new];

    if (canOpen) {
        UIContextualAction *openAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                                 title:VCTextLiteral(@"Open")
                                                                               handler:^(__unused UIContextualAction * _Nonnull action, __unused UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
            weakSelf.selectedIdentifier = [weakSelf _identifierForItem:item];
            [weakSelf _showDetailForSnapshot:item];
            [weakSelf _openSnapshotInMemory:snapshot];
            completionHandler(YES);
        }];
        openAction.backgroundColor = kVCAccent;
        [actions addObject:openAction];
    }

    if (canDraft) {
        UIContextualAction *draftAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                                  title:VCTextLiteral(@"Draft")
                                                                                handler:^(__unused UIContextualAction * _Nonnull action, __unused UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
            weakSelf.selectedIdentifier = [weakSelf _identifierForItem:item];
            [weakSelf _showDetailForSnapshot:item];
            [weakSelf _draftValueLockFromSnapshot:snapshot];
            completionHandler(YES);
        }];
        draftAction.backgroundColor = [kVCAccentDim colorWithAlphaComponent:0.96];
        [actions addObject:draftAction];
    }

    UISwipeActionsConfiguration *config = [UISwipeActionsConfiguration configurationWithActions:[actions copy]];
    config.performsFirstActionWithFullSwipe = NO;
    return config;
}

@end
