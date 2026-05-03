/**
 * VCChatSession.mm -- 会话管理实现
 * 持久化: sessions.json (元数据) + {sessionID}.json (消息)
 */

#import "VCChatSession.h"
#import "VCChatDiagnostics.h"
#import "VCMessage.h"
#import "../../../VansonCLI.h"
#import "../../Core/VCConfig.h"

NSNotificationName const VCChatPendingReferencesDidChangeNotification = @"VCChatPendingReferencesDidChangeNotification";
NSNotificationName const VCChatSessionDidChangeNotification = @"VCChatSessionDidChangeNotification";
NSString *const VCChatSessionChangeKindKey = @"changeKind";
NSString *const VCChatSessionChangedSessionIDKey = @"changedSessionID";
NSString *const VCChatSessionCurrentSessionIDKey = @"currentSessionID";
NSString *const VCChatSessionMessagesChangedKey = @"messagesChanged";
NSString *const VCChatSessionMetadataChangedKey = @"metadataChanged";
NSString *const VCChatSessionListChangedKey = @"sessionListChanged";
NSString *const VCChatSessionCurrentSessionChangedKey = @"currentSessionChanged";

static const NSTimeInterval kVCStreamingDraftWriteMinInterval = 0.65;
static const NSUInteger kVCStreamingDraftWriteMinDelta = 240;

@implementation VCChatSession {
    NSMutableArray<NSMutableDictionary *> *_sessionList;  // 会话元数据列表
    NSString *_currentSessionID;
    NSMutableArray<VCMessage *> *_currentMessages;
    NSMutableArray<NSDictionary *> *_pendingReferences;
    NSString *_pendingStreamingDraftContent;
    NSString *_pendingStreamingDraftSessionID;
    NSUInteger _pendingStreamingDraftRevision;
    NSUInteger _lastWrittenStreamingDraftRevision;
    NSTimeInterval _lastStreamingDraftWriteTime;
    NSUInteger _lastStreamingDraftWriteLength;
    NSUInteger _suppressedStreamingDraftUpdates;
}

+ (instancetype)shared {
    static VCChatSession *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VCChatSession alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _sessionList = [NSMutableArray new];
        _currentMessages = [NSMutableArray new];
        _pendingReferences = [NSMutableArray new];
        [self loadAll];
        if (_sessionList.count == 0) {
            [self createSession:@"New Chat"];
        }
    }
    return self;
}

#pragma mark - Session CRUD

- (NSString *)createSession:(NSString *)name {
    NSString *sid = [[NSUUID UUID] UUIDString];
    NSMutableDictionary *meta = [NSMutableDictionary new];
    meta[@"id"] = sid;
    meta[@"name"] = name ?: @"New Chat";
    meta[@"pinned"] = @(NO);
    meta[@"archived"] = @(NO);
    meta[@"lastMessage"] = @"";
    meta[@"updatedAt"] = @([[NSDate date] timeIntervalSince1970]);
    meta[@"createdAt"] = @([[NSDate date] timeIntervalSince1970]);
    meta[@"continuationArtifact"] = @{};
    meta[@"nextStep"] = @"";
    meta[@"sessionSummary"] = @"";
    [_sessionList insertObject:meta atIndex:0];
    BOOL didChangeCurrentSession = ![_currentSessionID isEqualToString:sid];
    [self _switchToSession:sid notify:NO changeKind:@"create"];
    [self _saveSessionList];
    [self _notifySessionChangeKind:@"create"
                         sessionID:sid
                   messagesChanged:didChangeCurrentSession
                   metadataChanged:NO
                 sessionListChanged:YES
              currentSessionChanged:didChangeCurrentSession];
    return sid;
}

- (void)switchToSession:(NSString *)sessionID {
    [self _switchToSession:sessionID notify:YES changeKind:@"switch"];
}

- (void)_switchToSession:(NSString *)sessionID notify:(BOOL)notify changeKind:(NSString *)changeKind {
    if ([_currentSessionID isEqualToString:sessionID]) return;
    // Save current session first
    if (_currentSessionID) [self saveCurrentSession];
    _currentSessionID = sessionID;
    _currentMessages = [NSMutableArray new];
    [self _loadMessagesForSession:sessionID];
    if (notify) {
        [self _notifySessionChangeKind:(changeKind ?: @"switch")
                             sessionID:sessionID
                       messagesChanged:YES
                       metadataChanged:NO
                     sessionListChanged:NO
                  currentSessionChanged:YES];
    }
}

- (NSString *)currentSessionID {
    return _currentSessionID;
}

- (NSArray<VCMessage *> *)currentMessages {
    return [_currentMessages copy];
}

- (void)addMessage:(VCMessage *)message {
    if (!message) return;
    [_currentMessages addObject:message];
    [self _refreshCurrentMetaPreview];
}

- (void)replaceCurrentMessages:(NSArray<VCMessage *> *)messages {
    _currentMessages = messages ? [messages mutableCopy] : [NSMutableArray new];
    [self _refreshCurrentMetaPreview];
}

- (NSDictionary *)currentContinuationArtifact {
    NSDictionary *artifact = [self _metaForSession:_currentSessionID][@"continuationArtifact"];
    return [artifact isKindOfClass:[NSDictionary class]] ? artifact : @{};
}

- (void)updateCurrentContinuationArtifact:(NSDictionary *)artifact {
    NSMutableDictionary *meta = [self _metaForSession:_currentSessionID];
    if (!meta) return;
    NSDictionary *safeArtifact = [artifact isKindOfClass:[NSDictionary class]] ? artifact : @{};
    meta[@"continuationArtifact"] = safeArtifact;
    meta[@"nextStep"] = safeArtifact[@"nextAlignedStep"] ?: @"";
    meta[@"sessionSummary"] = safeArtifact[@"currentWork"] ?: safeArtifact[@"primaryRequestAndIntent"] ?: @"";
    meta[@"updatedAt"] = @([[NSDate date] timeIntervalSince1970]);
    [self _saveSessionList];
    [self _notifySessionChangeKind:@"continuation"
                         sessionID:_currentSessionID
                   messagesChanged:NO
                   metadataChanged:YES
                 sessionListChanged:YES
              currentSessionChanged:NO];
}

#pragma mark - Session Management

- (void)renameSession:(NSString *)sessionID name:(NSString *)name {
    NSMutableDictionary *meta = [self _metaForSession:sessionID];
    if (meta) meta[@"name"] = name ?: @"";
    [self _saveSessionList];
    [self _notifySessionChangeKind:@"rename"
                         sessionID:sessionID
                   messagesChanged:NO
                   metadataChanged:YES
                 sessionListChanged:YES
              currentSessionChanged:NO];
}

- (void)pinSession:(NSString *)sessionID {
    NSMutableDictionary *meta = [self _metaForSession:sessionID];
    if (meta) meta[@"pinned"] = @(![meta[@"pinned"] boolValue]);
    [self _saveSessionList];
    [self _notifySessionChangeKind:@"pin"
                         sessionID:sessionID
                   messagesChanged:NO
                   metadataChanged:YES
                 sessionListChanged:YES
              currentSessionChanged:NO];
}

- (void)archiveSession:(NSString *)sessionID {
    NSMutableDictionary *meta = [self _metaForSession:sessionID];
    if (meta) meta[@"archived"] = @(YES);
    [self _saveSessionList];
    [self _notifySessionChangeKind:@"archive"
                         sessionID:sessionID
                   messagesChanged:NO
                   metadataChanged:YES
                 sessionListChanged:YES
              currentSessionChanged:NO];
}

- (void)deleteSession:(NSString *)sessionID {
    NSMutableDictionary *meta = [self _metaForSession:sessionID];
    if (meta) [_sessionList removeObject:meta];
    // Delete messages file
    NSString *path = [self _messagesPathForSession:sessionID];
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:[self _streamingDraftPathForSession:sessionID] error:nil];
    // If deleted current session, switch
    BOOL currentSessionChanged = NO;
    if ([_currentSessionID isEqualToString:sessionID]) {
        currentSessionChanged = YES;
        if (_sessionList.count > 0) {
            [self _switchToSession:_sessionList.firstObject[@"id"] notify:NO changeKind:@"delete"];
        } else {
            [self createSession:@"New Chat"];
            return;
        }
    }
    [self _saveSessionList];
    [self _notifySessionChangeKind:@"delete"
                         sessionID:sessionID
                   messagesChanged:currentSessionChanged
                   metadataChanged:NO
                 sessionListChanged:YES
              currentSessionChanged:currentSessionChanged];
}

#pragma mark - List & Search

- (NSArray<NSDictionary *> *)allSessions {
    // Sort: pinned first, then by updatedAt desc
    return [_sessionList sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        BOOL pa = [a[@"pinned"] boolValue], pb = [b[@"pinned"] boolValue];
        if (pa != pb) return pa ? NSOrderedAscending : NSOrderedDescending;
        double ta = [a[@"updatedAt"] doubleValue], tb = [b[@"updatedAt"] doubleValue];
        return ta > tb ? NSOrderedAscending : NSOrderedDescending;
    }];
}

- (NSArray<NSDictionary *> *)searchSessions:(NSString *)keyword {
    if (!keyword.length) return [self allSessions];
    NSString *lower = keyword.lowercaseString;
    NSMutableArray *results = [NSMutableArray new];
    for (NSDictionary *meta in _sessionList) {
        NSString *name = [meta[@"name"] lowercaseString];
        NSString *last = [meta[@"lastMessage"] lowercaseString];
        if ([name containsString:lower] || [last containsString:lower]) {
            [results addObject:meta];
        }
    }
    return results;
}

#pragma mark - Message Operations

- (void)deleteMessage:(NSString *)messageID {
    NSUInteger idx = [self indexOfMessage:messageID];
    if (idx == NSNotFound) return;
    [_currentMessages removeObjectAtIndex:idx];
    // Also remove following assistant reply if exists
    if (idx < _currentMessages.count) {
        VCMessage *next = _currentMessages[idx];
        if ([next.role isEqualToString:@"assistant"]) {
            [_currentMessages removeObjectAtIndex:idx];
        }
    }
}

- (void)truncateFromMessage:(NSString *)messageID {
    NSUInteger idx = [self indexOfMessage:messageID];
    if (idx == NSNotFound) return;
    NSRange range = NSMakeRange(idx, _currentMessages.count - idx);
    [_currentMessages removeObjectsInRange:range];
    [self _refreshCurrentMetaPreview];
}

- (VCMessage *)messageForID:(NSString *)messageID {
    for (VCMessage *msg in _currentMessages) {
        if ([msg.messageID isEqualToString:messageID]) return msg;
    }
    return nil;
}

- (NSUInteger)indexOfMessage:(NSString *)messageID {
    for (NSUInteger i = 0; i < _currentMessages.count; i++) {
        if ([_currentMessages[i].messageID isEqualToString:messageID]) return i;
    }
    return NSNotFound;
}

- (void)clearCurrentSessionMessages {
    if (_currentSessionID.length == 0) return;
    [_currentMessages removeAllObjects];
    [self clearPendingReferences];
    [self clearStreamingDraft];

    NSMutableDictionary *meta = [self _metaForSession:_currentSessionID];
    if (meta) {
        meta[@"lastMessage"] = @"";
        meta[@"updatedAt"] = @([[NSDate date] timeIntervalSince1970]);
        meta[@"continuationArtifact"] = @{};
        meta[@"nextStep"] = @"";
        meta[@"sessionSummary"] = @"";
    }

    [self saveCurrentSession];
    [self _saveSessionList];
    [self _notifySessionChangeKind:@"clear"
                         sessionID:_currentSessionID
                   messagesChanged:YES
                   metadataChanged:YES
                 sessionListChanged:YES
              currentSessionChanged:NO];
}

#pragma mark - Pending References

- (NSArray<NSDictionary *> *)pendingReferences {
    return [_pendingReferences copy];
}

- (void)enqueuePendingReference:(NSDictionary *)reference {
    if (![reference isKindOfClass:[NSDictionary class]]) return;
    NSString *referenceID = [reference[@"referenceID"] isKindOfClass:[NSString class]] ? reference[@"referenceID"] : [[NSUUID UUID] UUIDString];
    NSMutableDictionary *safeReference = [reference mutableCopy];
    safeReference[@"referenceID"] = referenceID;

    NSIndexSet *duplicates = [_pendingReferences indexesOfObjectsPassingTest:^BOOL(NSDictionary *obj, NSUInteger idx, BOOL *stop) {
        return [obj[@"referenceID"] isEqualToString:referenceID];
    }];
    if (duplicates.count > 0) {
        [_pendingReferences removeObjectsAtIndexes:duplicates];
    }
    [_pendingReferences addObject:safeReference];
    [[NSNotificationCenter defaultCenter] postNotificationName:VCChatPendingReferencesDidChangeNotification object:self];
}

- (void)removePendingReferenceByID:(NSString *)referenceID {
    if (referenceID.length == 0) return;
    NSIndexSet *matches = [_pendingReferences indexesOfObjectsPassingTest:^BOOL(NSDictionary *obj, NSUInteger idx, BOOL *stop) {
        return [obj[@"referenceID"] isEqualToString:referenceID];
    }];
    if (matches.count == 0) return;
    [_pendingReferences removeObjectsAtIndexes:matches];
    [[NSNotificationCenter defaultCenter] postNotificationName:VCChatPendingReferencesDidChangeNotification object:self];
}

- (void)clearPendingReferences {
    if (_pendingReferences.count == 0) return;
    [_pendingReferences removeAllObjects];
    [[NSNotificationCenter defaultCenter] postNotificationName:VCChatPendingReferencesDidChangeNotification object:self];
}

#pragma mark - Persistence

- (void)saveAll {
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    [self _flushPendingStreamingDraftIfNeeded];
    [self saveCurrentSession];
    [self _saveSessionList];
    double durationMS = MAX(0.0, (CFAbsoluteTimeGetCurrent() - start) * 1000.0);
    [[VCChatDiagnostics shared] recordEventWithPhase:@"persistence"
                                            subphase:@"save_all"
                                           sessionID:_currentSessionID
                                           requestID:nil
                                          durationMS:durationMS
                                               extra:@{
                                                   @"messageCount": @(_currentMessages.count),
                                                   @"sessionCount": @(_sessionList.count)
                                               }];
}

- (void)loadAll {
    [self _loadSessionList];
    if (_sessionList.count > 0) {
        NSString *sid = _sessionList.firstObject[@"id"];
        _currentSessionID = sid;
        [self _loadMessagesForSession:sid];
    }
}

- (void)saveCurrentSession {
    if (!_currentSessionID) return;
    [self _flushPendingStreamingDraftIfNeeded];
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    NSString *path = [self _messagesPathForSession:_currentSessionID];
    NSMutableArray *arr = [NSMutableArray new];
    for (VCMessage *msg in _currentMessages) {
        [arr addObject:[msg toDictionary]];
    }
    NSData *json = [NSJSONSerialization dataWithJSONObject:arr options:NSJSONWritingPrettyPrinted error:nil];
    [json writeToFile:path atomically:YES];
    double durationMS = MAX(0.0, (CFAbsoluteTimeGetCurrent() - start) * 1000.0);
    [[VCChatDiagnostics shared] recordEventWithPhase:@"persistence"
                                            subphase:@"save_current_session"
                                           sessionID:_currentSessionID
                                           requestID:nil
                                          durationMS:durationMS
                                               extra:@{
                                                   @"messageCount": @(_currentMessages.count),
                                                   @"bytes": @(json.length)
                                               }];
}

- (void)updateStreamingDraft:(NSString *)content {
    if (_currentSessionID.length == 0) return;
    NSString *trimmed = content ?: @"";
    if (trimmed.length == 0) {
        [self clearStreamingDraft];
        return;
    }
    BOOL shouldWrite = NO;
    NSUInteger coalescedUpdates = 0;
    NSUInteger revisionToWrite = 0;
    NSString *sessionID = [_currentSessionID copy];
    NSUInteger lengthDelta = 0;
    @synchronized (self) {
        _pendingStreamingDraftContent = [trimmed copy];
        _pendingStreamingDraftSessionID = [sessionID copy];
        _pendingStreamingDraftRevision += 1;
        revisionToWrite = _pendingStreamingDraftRevision;

        NSUInteger currentLength = trimmed.length;
        lengthDelta = currentLength > _lastStreamingDraftWriteLength
            ? (currentLength - _lastStreamingDraftWriteLength)
            : (_lastStreamingDraftWriteLength - currentLength);
        NSTimeInterval now = CFAbsoluteTimeGetCurrent();
        BOOL hasNeverWritten = (_lastStreamingDraftWriteTime <= 0);
        shouldWrite = hasNeverWritten ||
                      ((now - _lastStreamingDraftWriteTime) >= kVCStreamingDraftWriteMinInterval) ||
                      (lengthDelta >= kVCStreamingDraftWriteMinDelta);
        if (shouldWrite) {
            coalescedUpdates = _suppressedStreamingDraftUpdates;
            _suppressedStreamingDraftUpdates = 0;
            _lastStreamingDraftWriteTime = now;
            _lastStreamingDraftWriteLength = currentLength;
            _lastWrittenStreamingDraftRevision = revisionToWrite;
        } else {
            _suppressedStreamingDraftUpdates += 1;
        }
    }

    if (shouldWrite) {
        [self _writeStreamingDraftContent:trimmed
                                sessionID:sessionID
                           coalescedCount:coalescedUpdates
                             lengthDelta:lengthDelta];
    }
}

- (void)clearStreamingDraft {
    if (_currentSessionID.length == 0) return;
    @synchronized (self) {
        _pendingStreamingDraftContent = nil;
        _pendingStreamingDraftSessionID = nil;
        _pendingStreamingDraftRevision = 0;
        _lastWrittenStreamingDraftRevision = 0;
        _lastStreamingDraftWriteTime = 0;
        _lastStreamingDraftWriteLength = 0;
        _suppressedStreamingDraftUpdates = 0;
    }
    [[NSFileManager defaultManager] removeItemAtPath:[self _streamingDraftPathForSession:_currentSessionID] error:nil];
}

#pragma mark - Private

- (NSMutableDictionary *)_metaForSession:(NSString *)sessionID {
    for (NSMutableDictionary *meta in _sessionList) {
        if ([meta[@"id"] isEqualToString:sessionID]) return meta;
    }
    return nil;
}

- (NSString *)_sessionsDir {
    return [VCConfig shared].sessionsPath;
}

- (NSString *)_sessionsListPath {
    return [[self _sessionsDir] stringByAppendingPathComponent:@"sessions.json"];
}

- (NSString *)_messagesPathForSession:(NSString *)sessionID {
    return [[self _sessionsDir] stringByAppendingPathComponent:
        [NSString stringWithFormat:@"%@.json", sessionID]];
}

- (NSString *)_streamingDraftPathForSession:(NSString *)sessionID {
    return [[self _sessionsDir] stringByAppendingPathComponent:
        [NSString stringWithFormat:@"%@.draft.json", sessionID]];
}

- (void)_saveSessionList {
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    NSData *json = [NSJSONSerialization dataWithJSONObject:_sessionList
        options:NSJSONWritingPrettyPrinted error:nil];
    [json writeToFile:[self _sessionsListPath] atomically:YES];
    double durationMS = MAX(0.0, (CFAbsoluteTimeGetCurrent() - start) * 1000.0);
    [[VCChatDiagnostics shared] recordEventWithPhase:@"persistence"
                                            subphase:@"save_session_list"
                                           sessionID:_currentSessionID
                                           requestID:nil
                                          durationMS:durationMS
                                               extra:@{
                                                   @"sessionCount": @(_sessionList.count),
                                                   @"bytes": @(json.length)
                                               }];
}

- (void)_flushPendingStreamingDraftIfNeeded {
    NSString *contentToWrite = nil;
    NSString *sessionID = nil;
    NSUInteger coalescedUpdates = 0;
    NSUInteger lengthDelta = 0;
    @synchronized (self) {
        if (_pendingStreamingDraftRevision == 0 ||
            _pendingStreamingDraftRevision == _lastWrittenStreamingDraftRevision ||
            _pendingStreamingDraftContent.length == 0 ||
            _pendingStreamingDraftSessionID.length == 0) {
            return;
        }

        contentToWrite = [_pendingStreamingDraftContent copy];
        sessionID = [_pendingStreamingDraftSessionID copy];
        coalescedUpdates = _suppressedStreamingDraftUpdates;
        _suppressedStreamingDraftUpdates = 0;
        lengthDelta = contentToWrite.length > _lastStreamingDraftWriteLength
            ? (contentToWrite.length - _lastStreamingDraftWriteLength)
            : (_lastStreamingDraftWriteLength - contentToWrite.length);
        _lastStreamingDraftWriteTime = CFAbsoluteTimeGetCurrent();
        _lastStreamingDraftWriteLength = contentToWrite.length;
        _lastWrittenStreamingDraftRevision = _pendingStreamingDraftRevision;
    }
    [self _writeStreamingDraftContent:contentToWrite
                            sessionID:sessionID
                       coalescedCount:coalescedUpdates
                         lengthDelta:lengthDelta];
}

- (void)_writeStreamingDraftContent:(NSString *)content
                          sessionID:(NSString *)sessionID
                     coalescedCount:(NSUInteger)coalescedCount
                       lengthDelta:(NSUInteger)lengthDelta {
    if (content.length == 0 || sessionID.length == 0) return;
    NSDictionary *payload = @{
        @"role": @"assistant",
        @"content": content,
        @"timestamp": @([[NSDate date] timeIntervalSince1970]),
    };
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:NSJSONWritingPrettyPrinted error:nil];
    [json writeToFile:[self _streamingDraftPathForSession:sessionID] atomically:YES];
    double durationMS = MAX(0.0, (CFAbsoluteTimeGetCurrent() - start) * 1000.0);
    [[VCChatDiagnostics shared] recordEventWithPhase:@"persistence"
                                            subphase:@"write_streaming_draft"
                                           sessionID:sessionID
                                           requestID:nil
                                          durationMS:durationMS
                                               extra:@{
                                                   @"bytes": @(json.length),
                                                   @"contentLength": @(content.length),
                                                   @"lengthDelta": @(lengthDelta),
                                                   @"coalescedUpdates": @(coalescedCount)
                                               }];
}

- (void)_loadSessionList {
    NSData *json = [NSData dataWithContentsOfFile:[self _sessionsListPath]];
    if (!json) return;
    NSArray *arr = [NSJSONSerialization JSONObjectWithData:json options:NSJSONReadingMutableContainers error:nil];
    if ([arr isKindOfClass:[NSArray class]]) {
        _sessionList = [arr mutableCopy];
        for (NSMutableDictionary *meta in _sessionList) {
            if (![meta[@"continuationArtifact"] isKindOfClass:[NSDictionary class]]) meta[@"continuationArtifact"] = @{};
            if (![meta[@"nextStep"] isKindOfClass:[NSString class]]) meta[@"nextStep"] = @"";
            if (![meta[@"sessionSummary"] isKindOfClass:[NSString class]]) meta[@"sessionSummary"] = @"";
        }
    }
}

- (void)_loadMessagesForSession:(NSString *)sessionID {
    _currentMessages = [NSMutableArray new];
    NSString *path = [self _messagesPathForSession:sessionID];
    NSData *json = [NSData dataWithContentsOfFile:path];
    if (!json) return;
    NSArray *arr = [NSJSONSerialization JSONObjectWithData:json options:0 error:nil];
    if (![arr isKindOfClass:[NSArray class]]) return;
    for (NSDictionary *dict in arr) {
        VCMessage *msg = [VCMessage fromDictionary:dict];
        if (msg) [_currentMessages addObject:msg];
    }

    NSData *draftData = [NSData dataWithContentsOfFile:[self _streamingDraftPathForSession:sessionID]];
    if (draftData.length > 0) {
        NSDictionary *draft = [NSJSONSerialization JSONObjectWithData:draftData options:0 error:nil];
        NSString *draftContent = [draft[@"content"] isKindOfClass:[NSString class]] ? draft[@"content"] : @"";
        if (draftContent.length > 0) {
            VCMessage *draftMessage = [VCMessage messageWithRole:@"assistant"
                                                         content:[NSString stringWithFormat:@"[Recovered Draft]\n%@", draftContent]];
            draftMessage.isEdited = YES;
            [_currentMessages addObject:draftMessage];
        }
    }
}

- (void)_refreshCurrentMetaPreview {
    NSMutableDictionary *meta = [self _metaForSession:_currentSessionID];
    if (!meta) return;

    VCMessage *message = _currentMessages.lastObject;
    NSString *preview = message.content ?: @"";
    if (preview.length > 50) preview = [[preview substringToIndex:50] stringByAppendingString:@"..."];
    meta[@"lastMessage"] = preview ?: @"";
    meta[@"updatedAt"] = @([[NSDate date] timeIntervalSince1970]);

    NSDictionary *artifact = meta[@"continuationArtifact"];
    if (![artifact isKindOfClass:[NSDictionary class]]) artifact = @{};
    meta[@"nextStep"] = artifact[@"nextAlignedStep"] ?: meta[@"nextStep"] ?: @"";
    meta[@"sessionSummary"] = artifact[@"currentWork"] ?: artifact[@"primaryRequestAndIntent"] ?: meta[@"sessionSummary"] ?: @"";
}

- (void)_notifySessionChangeKind:(NSString *)changeKind
                       sessionID:(NSString *)sessionID
                 messagesChanged:(BOOL)messagesChanged
                 metadataChanged:(BOOL)metadataChanged
               sessionListChanged:(BOOL)sessionListChanged
            currentSessionChanged:(BOOL)currentSessionChanged {
    NSString *effectiveSessionID = [sessionID copy] ?: @"";
    NSString *currentSessionID = [_currentSessionID copy] ?: @"";
    NSMutableDictionary *userInfo = [NSMutableDictionary new];
    userInfo[VCChatSessionChangeKindKey] = changeKind ?: @"update";
    userInfo[VCChatSessionChangedSessionIDKey] = effectiveSessionID;
    userInfo[VCChatSessionCurrentSessionIDKey] = currentSessionID;
    userInfo[VCChatSessionMessagesChangedKey] = @(messagesChanged);
    userInfo[VCChatSessionMetadataChangedKey] = @(metadataChanged);
    userInfo[VCChatSessionListChangedKey] = @(sessionListChanged);
    userInfo[VCChatSessionCurrentSessionChangedKey] = @(currentSessionChanged);

    [[VCChatDiagnostics shared] recordEventWithPhase:@"session"
                                            subphase:(changeKind ?: @"update")
                                           sessionID:effectiveSessionID.length > 0 ? effectiveSessionID : currentSessionID
                                           requestID:nil
                                          durationMS:0.0
                                               extra:@{
                                                   @"messagesChanged": @(messagesChanged),
                                                   @"metadataChanged": @(metadataChanged),
                                                   @"sessionListChanged": @(sessionListChanged),
                                                   @"currentSessionChanged": @(currentSessionChanged)
                                               }];

    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:VCChatSessionDidChangeNotification
                                                            object:self
                                                          userInfo:[userInfo copy]];
    });
}

@end
