/**
 * VCAutoSave -- 30s 定时自动保存
 */

#import <Foundation/Foundation.h>

@interface VCAutoSave : NSObject

+ (instancetype)shared;

- (void)start;
- (void)stop;
- (void)saveNow;

@end
