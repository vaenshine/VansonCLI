/**
 * VCMemoryScanEngine -- thin bridge over the memory scan backend
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface VCMemoryScanEngine : NSObject

+ (instancetype)shared;

- (BOOL)hasActiveSession;
- (NSDictionary *)activeSessionSummary;
- (BOOL)hasPersistedSession;
- (NSDictionary *)persistedSessionSummary;

- (NSDictionary * _Nullable)startScanWithMode:(NSString *)scanMode
                                        value:(NSString * _Nullable)value
                                     minValue:(NSString * _Nullable)minValue
                                     maxValue:(NSString * _Nullable)maxValue
                               dataTypeString:(NSString * _Nullable)dataTypeString
                               floatTolerance:(NSNumber * _Nullable)floatTolerance
                                   groupRange:(NSNumber * _Nullable)groupRange
                              groupAnchorMode:(NSNumber * _Nullable)groupAnchorMode
                                  resultLimit:(NSNumber * _Nullable)resultLimit
                                 errorMessage:(NSString * _Nullable * _Nullable)errorMessage;

- (NSDictionary * _Nullable)refineScanWithMode:(NSString *)filterMode
                                         value:(NSString * _Nullable)value
                                      minValue:(NSString * _Nullable)minValue
                                      maxValue:(NSString * _Nullable)maxValue
                                dataTypeString:(NSString * _Nullable)dataTypeString
                                  errorMessage:(NSString * _Nullable * _Nullable)errorMessage;

- (NSDictionary * _Nullable)resultsWithOffset:(NSUInteger)offset
                                        limit:(NSUInteger)limit
                                refreshValues:(BOOL)refreshValues
                                 errorMessage:(NSString * _Nullable * _Nullable)errorMessage;

- (NSDictionary * _Nullable)resumePersistedSessionWithErrorMessage:(NSString * _Nullable * _Nullable)errorMessage;
- (NSDictionary *)clearScan;

@end

NS_ASSUME_NONNULL_END
