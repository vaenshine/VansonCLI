/**
 * VCPromptLeakGuard -- local protection against VansonCLI prompt exfiltration
 */

#import <Foundation/Foundation.h>

@interface VCPromptLeakGuard : NSObject

+ (NSString *)blockedLocalResponseForUserText:(NSString *)text;
+ (NSString *)sanitizedAssistantText:(NSString *)text didSanitize:(BOOL *)didSanitize;
+ (NSString *)blockedToolReasonForClassName:(NSString *)className moduleName:(NSString *)moduleName;
+ (NSString *)blockedToolReasonForModuleName:(NSString *)moduleName;
+ (NSString *)blockedToolReasonForStringPattern:(NSString *)pattern moduleName:(NSString *)moduleName;
+ (NSString *)blockedToolReasonForMemoryModuleName:(NSString *)moduleName address:(unsigned long long)address;
+ (NSString *)sanitizedEnvironmentValueForKey:(NSString *)key value:(id)value wasRedacted:(BOOL *)wasRedacted;

@end
