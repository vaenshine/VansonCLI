/**
 * VCChatDiagnostics -- lightweight chat perf/event diagnostics
 */

#import <Foundation/Foundation.h>

extern NSNotificationName const VCChatDiagnosticsDidUpdateNotification;

@interface VCChatDiagnostics : NSObject

+ (instancetype)shared;

- (NSString *)beginRequestForSessionID:(NSString *)sessionID
                          messageCount:(NSUInteger)messageCount
                        contextSummary:(NSDictionary *)contextSummary;

- (void)recordEventWithPhase:(NSString *)phase
                    subphase:(NSString *)subphase
                  durationMS:(double)durationMS
                       extra:(NSDictionary *)extra;

- (void)recordEventWithPhase:(NSString *)phase
                    subphase:(NSString *)subphase
                   sessionID:(NSString *)sessionID
                   requestID:(NSString *)requestID
                  durationMS:(double)durationMS
                       extra:(NSDictionary *)extra;

- (void)noteChunkWithSize:(NSUInteger)chunkSize totalLength:(NSUInteger)totalLength;
- (void)finishActiveRequestWithError:(NSError *)error totalLength:(NSUInteger)totalLength;

- (NSString *)activeRequestID;
- (NSString *)activeSessionID;
- (NSArray<NSDictionary *> *)recentEvents;
- (NSString *)recentEventsPath;
- (NSString *)requestHistoryPath;

@end
