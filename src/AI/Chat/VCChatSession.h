/**
 * VCChatSession -- 会话管理
 * JSON 文件持久化, 支持多会话切换/搜索/归档
 */

#import <Foundation/Foundation.h>

@class VCMessage;
extern NSNotificationName const VCChatPendingReferencesDidChangeNotification;
extern NSNotificationName const VCChatSessionDidChangeNotification;
extern NSString *const VCChatSessionChangeKindKey;
extern NSString *const VCChatSessionChangedSessionIDKey;
extern NSString *const VCChatSessionCurrentSessionIDKey;
extern NSString *const VCChatSessionMessagesChangedKey;
extern NSString *const VCChatSessionMetadataChangedKey;
extern NSString *const VCChatSessionListChangedKey;
extern NSString *const VCChatSessionCurrentSessionChangedKey;

@interface VCChatSession : NSObject

+ (instancetype)shared;

// Session CRUD
- (NSString *)createSession:(NSString *)name;
- (void)switchToSession:(NSString *)sessionID;
- (NSString *)currentSessionID;
- (NSArray<VCMessage *> *)currentMessages;
- (void)addMessage:(VCMessage *)message;
- (void)replaceCurrentMessages:(NSArray<VCMessage *> *)messages;
- (NSDictionary *)currentContinuationArtifact;
- (void)updateCurrentContinuationArtifact:(NSDictionary *)artifact;

// Session management
- (void)renameSession:(NSString *)sessionID name:(NSString *)name;
- (void)pinSession:(NSString *)sessionID;
- (void)archiveSession:(NSString *)sessionID;
- (void)deleteSession:(NSString *)sessionID;

// List & search
- (NSArray<NSDictionary *> *)allSessions;
- (NSArray<NSDictionary *> *)searchSessions:(NSString *)keyword;

// Message operations
- (void)deleteMessage:(NSString *)messageID;
- (void)truncateFromMessage:(NSString *)messageID;
- (VCMessage *)messageForID:(NSString *)messageID;
- (NSUInteger)indexOfMessage:(NSString *)messageID;
- (void)clearCurrentSessionMessages;

// Composer references
- (NSArray<NSDictionary *> *)pendingReferences;
- (void)enqueuePendingReference:(NSDictionary *)reference;
- (void)removePendingReferenceByID:(NSString *)referenceID;
- (void)clearPendingReferences;

// Persistence
- (void)saveAll;
- (void)loadAll;
- (void)saveCurrentSession;
- (void)updateStreamingDraft:(NSString *)content;
- (void)clearStreamingDraft;

@end
