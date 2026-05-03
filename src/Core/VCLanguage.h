/**
 * VCLanguage -- Lightweight UI localization manager
 */

#import <Foundation/Foundation.h>

extern NSNotificationName const VCLanguageDidChangeNotification;

@interface VCLanguage : NSObject

+ (NSString *)preferredLanguageOption;
+ (void)setPreferredLanguageOption:(NSString *)option;
+ (NSString *)resolvedLanguageCode;
+ (BOOL)isChinese;
+ (NSString *)textForKey:(NSString *)key fallback:(NSString *)fallback;
+ (NSArray<NSString *> *)availableLanguageOptions;
+ (NSString *)displayNameForOption:(NSString *)option;
+ (NSString *)languageSummaryText;

@end
