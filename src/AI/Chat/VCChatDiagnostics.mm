/**
 * VCChatDiagnostics.mm -- lightweight chat perf/event diagnostics
 */

#import "VCChatDiagnostics.h"
#import "../../../VansonCLI.h"
#import "../../Core/VCConfig.h"
#import <math.h>

NSNotificationName const VCChatDiagnosticsDidUpdateNotification = @"VCChatDiagnosticsDidUpdateNotification";

static const NSUInteger kVCChatDiagnosticsMaxEvents = 160;
static const double kVCChatChunkStallThresholdMS = 350.0;
static const NSTimeInterval kVCChatDiagnosticsFlushDelay = 1.0;

static NSDictionary *VCChatDiagnosticsSanitizeExtra(NSDictionary *extra) {
    if (![extra isKindOfClass:[NSDictionary class]] || extra.count == 0) return @{};
    NSMutableDictionary *sanitized = [NSMutableDictionary dictionaryWithCapacity:extra.count];
    [extra enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        if (![key isKindOfClass:[NSString class]]) return;
        if ([obj isKindOfClass:[NSString class]] ||
            [obj isKindOfClass:[NSNumber class]] ||
            [obj isKindOfClass:[NSDictionary class]] ||
            [obj isKindOfClass:[NSArray class]] ||
            [obj isKindOfClass:[NSNull class]]) {
            sanitized[key] = obj;
        } else {
            sanitized[key] = [obj description] ?: @"";
        }
    }];
    return [sanitized copy];
}

static NSNumber *VCChatDiagnosticsRounded(double value) {
    return @(((double)llround(value * 10.0)) / 10.0);
}

@implementation VCChatDiagnostics {
    dispatch_queue_t _queue;
    NSMutableArray<NSDictionary *> *_recentEvents;
    NSString *_activeRequestID;
    NSString *_activeSessionID;
    CFAbsoluteTime _requestStartTime;
    CFAbsoluteTime _lastChunkTime;
    BOOL _hasReceivedFirstChunk;
    NSUInteger _chunkCount;
    NSUInteger _stallCount;
    NSMutableArray<NSNumber *> *_chunkIntervalsMS;
    BOOL _flushScheduled;
}

+ (instancetype)shared {
    static VCChatDiagnostics *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VCChatDiagnostics alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _queue = dispatch_queue_create("com.vanson.chat.diagnostics", DISPATCH_QUEUE_SERIAL);
        _recentEvents = [NSMutableArray new];
        _chunkIntervalsMS = [NSMutableArray new];
    }
    return self;
}

- (NSString *)beginRequestForSessionID:(NSString *)sessionID
                          messageCount:(NSUInteger)messageCount
                        contextSummary:(NSDictionary *)contextSummary {
    NSString *requestID = [[NSUUID UUID] UUIDString];
    NSDictionary *summary = VCChatDiagnosticsSanitizeExtra(contextSummary);
    dispatch_async(_queue, ^{
        self->_activeRequestID = requestID;
        self->_activeSessionID = [sessionID copy] ?: @"";
        self->_requestStartTime = CFAbsoluteTimeGetCurrent();
        self->_lastChunkTime = 0;
        self->_hasReceivedFirstChunk = NO;
        self->_chunkCount = 0;
        self->_stallCount = 0;
        [self->_chunkIntervalsMS removeAllObjects];

        NSMutableDictionary *extra = [summary mutableCopy];
        extra[@"messageCount"] = @(messageCount);
        [self _appendEventLockedWithPhase:@"request"
                                 subphase:@"begin"
                                sessionID:self->_activeSessionID
                                requestID:self->_activeRequestID
                               durationMS:0.0
                                    extra:extra];
    });
    return requestID;
}

- (void)recordEventWithPhase:(NSString *)phase
                    subphase:(NSString *)subphase
                  durationMS:(double)durationMS
                       extra:(NSDictionary *)extra {
    [self recordEventWithPhase:phase
                      subphase:subphase
                     sessionID:nil
                     requestID:nil
                    durationMS:durationMS
                         extra:extra];
}

- (void)recordEventWithPhase:(NSString *)phase
                    subphase:(NSString *)subphase
                   sessionID:(NSString *)sessionID
                   requestID:(NSString *)requestID
                  durationMS:(double)durationMS
                       extra:(NSDictionary *)extra {
    NSString *phaseCopy = [phase copy] ?: @"";
    NSString *subphaseCopy = [subphase copy] ?: @"";
    NSDictionary *sanitizedExtra = VCChatDiagnosticsSanitizeExtra(extra);
    dispatch_async(_queue, ^{
        NSString *effectiveSessionID = sessionID ?: self->_activeSessionID ?: @"";
        NSString *effectiveRequestID = requestID ?: self->_activeRequestID ?: @"";
        [self _appendEventLockedWithPhase:phaseCopy
                                 subphase:subphaseCopy
                                sessionID:effectiveSessionID
                                requestID:effectiveRequestID
                               durationMS:durationMS
                                    extra:sanitizedExtra];
    });
}

- (void)noteChunkWithSize:(NSUInteger)chunkSize totalLength:(NSUInteger)totalLength {
    dispatch_async(_queue, ^{
        if (self->_activeRequestID.length == 0) return;
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        self->_chunkCount += 1;

        if (!self->_hasReceivedFirstChunk) {
            self->_hasReceivedFirstChunk = YES;
            self->_lastChunkTime = now;
            double firstTokenMS = MAX(0.0, (now - self->_requestStartTime) * 1000.0);
            [self _appendEventLockedWithPhase:@"stream"
                                     subphase:@"first_token"
                                    sessionID:self->_activeSessionID
                                    requestID:self->_activeRequestID
                                   durationMS:firstTokenMS
                                        extra:@{
                                            @"chunkSize": @(chunkSize),
                                            @"visibleLength": @(totalLength)
                                        }];
            [self _schedulePersistenceFlushLocked];
            return;
        }

        double intervalMS = MAX(0.0, (now - self->_lastChunkTime) * 1000.0);
        self->_lastChunkTime = now;
        [self->_chunkIntervalsMS addObject:@(intervalMS)];
        if (intervalMS >= kVCChatChunkStallThresholdMS) {
            self->_stallCount += 1;
            [self _appendEventLockedWithPhase:@"stream"
                                     subphase:@"chunk_gap"
                                    sessionID:self->_activeSessionID
                                    requestID:self->_activeRequestID
                                   durationMS:intervalMS
                                        extra:@{
                                            @"chunkIndex": @(self->_chunkCount),
                                            @"visibleLength": @(totalLength)
                                        }];
        }
        [self _schedulePersistenceFlushLocked];
    });
}

- (void)finishActiveRequestWithError:(NSError *)error totalLength:(NSUInteger)totalLength {
    NSString *errorDescription = error.localizedDescription ?: @"";
    dispatch_async(_queue, ^{
        if (self->_activeRequestID.length == 0) return;

        double totalMS = MAX(0.0, (CFAbsoluteTimeGetCurrent() - self->_requestStartTime) * 1000.0);
        double avgIntervalMS = 0.0;
        double p95IntervalMS = 0.0;
        if (self->_chunkIntervalsMS.count > 0) {
            double sum = 0.0;
            for (NSNumber *value in self->_chunkIntervalsMS) {
                sum += value.doubleValue;
            }
            avgIntervalMS = sum / (double)self->_chunkIntervalsMS.count;

            NSArray<NSNumber *> *sorted = [self->_chunkIntervalsMS sortedArrayUsingSelector:@selector(compare:)];
            NSUInteger p95Index = (NSUInteger)floor(MAX(0.0, ((double)sorted.count - 1.0) * 0.95));
            p95IntervalMS = [sorted[p95Index] doubleValue];
        }

        NSMutableDictionary *extra = [@{
            @"chunkCount": @(self->_chunkCount),
            @"stallCount": @(self->_stallCount),
            @"visibleLength": @(totalLength),
            @"avgChunkIntervalMS": VCChatDiagnosticsRounded(avgIntervalMS),
            @"p95ChunkIntervalMS": VCChatDiagnosticsRounded(p95IntervalMS)
        } mutableCopy];
        if (errorDescription.length > 0) {
            extra[@"error"] = errorDescription;
        }

        [self _appendEventLockedWithPhase:@"request"
                                 subphase:(errorDescription.length > 0 ? @"error" : @"finish")
                                sessionID:self->_activeSessionID
                                requestID:self->_activeRequestID
                               durationMS:totalMS
                                    extra:extra];
        [self _appendRequestSummaryLockedWithSubphase:(errorDescription.length > 0 ? @"error" : @"finish")
                                            sessionID:self->_activeSessionID
                                            requestID:self->_activeRequestID
                                           durationMS:totalMS
                                                extra:extra];
        [self _persistRecentEventsLocked];

        self->_activeRequestID = nil;
        self->_activeSessionID = nil;
        self->_requestStartTime = 0;
        self->_lastChunkTime = 0;
        self->_hasReceivedFirstChunk = NO;
        self->_chunkCount = 0;
        self->_stallCount = 0;
        [self->_chunkIntervalsMS removeAllObjects];
    });
}

- (NSString *)activeRequestID {
    __block NSString *value = nil;
    dispatch_sync(_queue, ^{
        value = [self->_activeRequestID copy];
    });
    return value;
}

- (NSString *)activeSessionID {
    __block NSString *value = nil;
    dispatch_sync(_queue, ^{
        value = [self->_activeSessionID copy];
    });
    return value;
}

- (NSArray<NSDictionary *> *)recentEvents {
    __block NSArray<NSDictionary *> *events = nil;
    dispatch_sync(_queue, ^{
        events = [self->_recentEvents copy];
    });
    return events ?: @[];
}

- (NSString *)recentEventsPath {
    NSString *directory = [self _diagnosticsDirectoryPath];
    return [directory stringByAppendingPathComponent:@"chat_diagnostics_recent.json"];
}

- (NSString *)requestHistoryPath {
    NSString *directory = [self _diagnosticsDirectoryPath];
    return [directory stringByAppendingPathComponent:@"chat_request_history.jsonl"];
}

- (void)_appendEventLockedWithPhase:(NSString *)phase
                           subphase:(NSString *)subphase
                          sessionID:(NSString *)sessionID
                          requestID:(NSString *)requestID
                         durationMS:(double)durationMS
                              extra:(NSDictionary *)extra {
    NSMutableDictionary *event = [NSMutableDictionary new];
    event[@"timestamp"] = @([[NSDate date] timeIntervalSince1970]);
    event[@"phase"] = phase ?: @"";
    event[@"subphase"] = subphase ?: @"";
    if (sessionID.length > 0) event[@"sessionID"] = sessionID;
    if (requestID.length > 0) event[@"requestID"] = requestID;
    if (durationMS > 0.0) event[@"durationMS"] = VCChatDiagnosticsRounded(durationMS);
    if (extra.count > 0) event[@"extra"] = extra;

    [self->_recentEvents addObject:event];
    while (self->_recentEvents.count > kVCChatDiagnosticsMaxEvents) {
        [self->_recentEvents removeObjectAtIndex:0];
    }

    VCLog(@"[ChatDiag] %@/%@ session=%@ request=%@ duration=%.1fms extra=%@",
          phase ?: @"",
          subphase ?: @"",
          sessionID ?: @"",
          requestID ?: @"",
          durationMS,
          extra ?: @{});
    [self _schedulePersistenceFlushLocked];

    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:VCChatDiagnosticsDidUpdateNotification object:self];
    });
}

- (NSString *)_diagnosticsDirectoryPath {
    NSString *directory = [[[VCConfig shared] sessionsPath] stringByAppendingPathComponent:@"diagnostics"];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    return directory;
}

- (void)_schedulePersistenceFlushLocked {
    if (_flushScheduled) return;
    _flushScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kVCChatDiagnosticsFlushDelay * NSEC_PER_SEC)), _queue, ^{
        self->_flushScheduled = NO;
        [self _persistRecentEventsLocked];
    });
}

- (void)_persistRecentEventsLocked {
    NSString *path = [self recentEventsPath];
    NSDictionary *payload = @{
        @"updatedAt": @([[NSDate date] timeIntervalSince1970]),
        @"activeSessionID": self->_activeSessionID ?: @"",
        @"activeRequestID": self->_activeRequestID ?: @"",
        @"events": [self->_recentEvents copy] ?: @[]
    };
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:NSJSONWritingPrettyPrinted error:nil];
    if (![json isKindOfClass:[NSData class]]) return;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        [json writeToFile:path atomically:YES];
    });
}

- (void)_appendRequestSummaryLockedWithSubphase:(NSString *)subphase
                                      sessionID:(NSString *)sessionID
                                      requestID:(NSString *)requestID
                                     durationMS:(double)durationMS
                                          extra:(NSDictionary *)extra {
    NSMutableDictionary *summary = [NSMutableDictionary new];
    summary[@"timestamp"] = @([[NSDate date] timeIntervalSince1970]);
    summary[@"phase"] = @"request";
    summary[@"subphase"] = subphase ?: @"finish";
    if (sessionID.length > 0) summary[@"sessionID"] = sessionID;
    if (requestID.length > 0) summary[@"requestID"] = requestID;
    summary[@"durationMS"] = VCChatDiagnosticsRounded(durationMS);
    if (extra.count > 0) summary[@"extra"] = extra;

    NSData *json = [NSJSONSerialization dataWithJSONObject:summary options:0 error:nil];
    if (![json isKindOfClass:[NSData class]]) return;
    NSMutableData *line = [json mutableCopy];
    [line appendData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
    NSData *lineData = [line copy];
    NSString *path = [self requestHistoryPath];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if (![fileManager fileExistsAtPath:path]) {
            [lineData writeToFile:path atomically:YES];
            return;
        }
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!handle) {
            [lineData writeToFile:path atomically:YES];
            return;
        }
        @try {
            [handle seekToEndOfFile];
            [handle writeData:lineData];
        } @catch (__unused NSException *exception) {
        } @finally {
            [handle closeFile];
        }
    });
}

@end
