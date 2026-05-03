/**
 * VCMemoryBrowserEngine -- paged memory browsing bridge over memory IO
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface VCMemoryBrowserEngine : NSObject

+ (instancetype)shared;

- (BOOL)hasActiveSession;
- (NSDictionary *)activeSessionSummary;

- (NSDictionary * _Nullable)browseAtAddress:(uint64_t)address
                                   pageSize:(NSUInteger)pageSize
                                     length:(NSUInteger)length
                              updateSession:(BOOL)updateSession
                               errorMessage:(NSString * _Nullable * _Nullable)errorMessage;

- (NSDictionary * _Nullable)stepPageBy:(NSInteger)delta
                              pageSize:(NSUInteger)pageSize
                          errorMessage:(NSString * _Nullable * _Nullable)errorMessage;

@end

NS_ASSUME_NONNULL_END
