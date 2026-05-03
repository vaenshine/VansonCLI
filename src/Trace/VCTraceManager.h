/**
 * VCTraceManager -- lightweight runtime trace sessions for AI analysis
 */

#import <Foundation/Foundation.h>

@interface VCTraceManager : NSObject

+ (instancetype)shared;

- (NSDictionary *)startTraceWithOptions:(NSDictionary *)options errorMessage:(NSString **)errorMessage;
- (NSDictionary *)captureCheckpointForSession:(NSString *)sessionID
                                      options:(NSDictionary *)options
                                 errorMessage:(NSString **)errorMessage;
- (NSDictionary *)stopTraceSession:(NSString *)sessionID errorMessage:(NSString **)errorMessage;
- (NSDictionary *)eventsSnapshotForSession:(NSString *)sessionID
                                     limit:(NSUInteger)limit
                                 kindNames:(NSArray<NSString *> *)kindNames;
- (NSArray<NSDictionary *> *)sessionSummariesWithLimit:(NSUInteger)limit;
- (NSDictionary *)sessionDetailForSession:(NSString *)sessionID
                               eventLimit:(NSUInteger)eventLimit;
- (NSDictionary *)exportMermaidForSession:(NSString *)sessionID
                                    style:(NSString *)style
                                    title:(NSString *)title
                                   limit:(NSUInteger)limit
                             errorMessage:(NSString **)errorMessage;
- (NSDictionary *)activeSessionSnapshot;

@end
