/**
 * VCLanguage -- Lightweight UI localization manager
 */

#import "VCLanguage.h"
#import "Lang/VCLang.h"

NSNotificationName const VCLanguageDidChangeNotification = @"VCLanguageDidChangeNotification";
static NSString *const kVCLanguagePreferenceKey = @"com.vanson.cli.language.preference";

@interface VCLanguage ()
+ (NSDictionary<NSString *, NSString *> *)_dictionaryForLanguageCode:(NSString *)code;
+ (NSDictionary<NSString *, NSString *> *)_languageNativeNames;
+ (BOOL)_preferredLanguage:(NSString *)preferred matchesPrefix:(NSString *)prefix;
@end

@implementation VCLanguage

+ (NSString *)preferredLanguageOption {
    NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:kVCLanguagePreferenceKey];
    if ([saved isKindOfClass:[NSString class]] && saved.length > 0) {
        return [self _normalizedOption:saved];
    }
    return @"auto";
}

+ (void)setPreferredLanguageOption:(NSString *)option {
    NSString *normalized = [self _normalizedOption:option];
    NSString *previous = [self preferredLanguageOption];
    if ([previous isEqualToString:normalized]) return;
    [[NSUserDefaults standardUserDefaults] setObject:normalized forKey:kVCLanguagePreferenceKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:VCLanguageDidChangeNotification object:nil];
}

+ (NSString *)resolvedLanguageCode {
    NSString *option = [self preferredLanguageOption];
    if (![option isEqualToString:@"auto"]) {
        return option;
    }

    for (NSString *preferred in [NSLocale preferredLanguages]) {
        NSString *value = [[preferred lowercaseString] stringByReplacingOccurrencesOfString:@"_" withString:@"-"];
        if ([value hasPrefix:@"zh-hant"] || [value hasPrefix:@"zh-tw"] || [value hasPrefix:@"zh-hk"] || [value hasPrefix:@"zh-mo"]) {
            return @"zh-Hant";
        }
        if ([value hasPrefix:@"zh"]) {
            return @"zh-Hans";
        }
        if ([self _preferredLanguage:value matchesPrefix:@"ja"]) return @"ja";
        if ([self _preferredLanguage:value matchesPrefix:@"ko"]) return @"ko";
        if ([self _preferredLanguage:value matchesPrefix:@"ru"]) return @"ru";
        if ([self _preferredLanguage:value matchesPrefix:@"es"]) return @"es";
        if ([self _preferredLanguage:value matchesPrefix:@"vi"]) return @"vi";
        if ([self _preferredLanguage:value matchesPrefix:@"th"]) return @"th";
        if ([self _preferredLanguage:value matchesPrefix:@"pt"]) return @"pt";
        if ([self _preferredLanguage:value matchesPrefix:@"fr"]) return @"fr";
        if ([self _preferredLanguage:value matchesPrefix:@"de"]) return @"de";
        if ([self _preferredLanguage:value matchesPrefix:@"ar"]) return @"ar";
    }
    return @"en";
}

+ (BOOL)isChinese {
    return [[self resolvedLanguageCode] hasPrefix:@"zh"];
}

+ (NSString *)textForKey:(NSString *)key fallback:(NSString *)fallback {
    NSString *lookup = key.length > 0 ? key : fallback;
    if (lookup.length == 0) return @"";
    NSString *english = VCLangENDictionary()[lookup];
    NSString *defaultText = fallback.length > 0 ? fallback : (english.length > 0 ? english : lookup);
    NSString *languageCode = [self resolvedLanguageCode];
    if ([languageCode isEqualToString:@"en"]) {
        return defaultText;
    }
    NSString *translated = [self _dictionaryForLanguageCode:languageCode][lookup];
    return translated.length > 0 ? translated : defaultText;
}

+ (NSArray<NSString *> *)availableLanguageOptions {
    return @[@"auto", @"en", @"zh-Hans", @"zh-Hant", @"ja", @"ko", @"ru", @"es", @"vi", @"th", @"pt", @"fr", @"de", @"ar"];
}

+ (NSString *)displayNameForOption:(NSString *)option {
    NSString *normalized = [self _normalizedOption:option];
    return [self _languageNativeNames][normalized] ?: @"Auto";
}

+ (NSString *)languageSummaryText {
    NSString *option = [self preferredLanguageOption];
    if ([option isEqualToString:@"auto"]) {
        return [NSString stringWithFormat:@"%@ · %@", [self displayNameForOption:@"auto"], [self displayNameForOption:[self resolvedLanguageCode]]];
    }
    return [self displayNameForOption:option];
}

+ (NSString *)_normalizedOption:(NSString *)option {
    NSString *raw = option.lowercaseString ?: @"auto";
    NSString *value = [raw stringByReplacingOccurrencesOfString:@"_" withString:@"-"];
    if ([value isEqualToString:@"auto"]) return @"auto";
    if ([value hasPrefix:@"zh-hant"] || [value hasPrefix:@"zh-tw"] || [value hasPrefix:@"zh-hk"] || [value hasPrefix:@"zh-mo"]) return @"zh-Hant";
    if ([value hasPrefix:@"zh"]) return @"zh-Hans";
    if ([value hasPrefix:@"en"]) return @"en";
    if ([value hasPrefix:@"ja"]) return @"ja";
    if ([value hasPrefix:@"ko"]) return @"ko";
    if ([value hasPrefix:@"ru"]) return @"ru";
    if ([value hasPrefix:@"es"]) return @"es";
    if ([value hasPrefix:@"vi"]) return @"vi";
    if ([value hasPrefix:@"th"]) return @"th";
    if ([value hasPrefix:@"pt"]) return @"pt";
    if ([value hasPrefix:@"fr"]) return @"fr";
    if ([value hasPrefix:@"de"]) return @"de";
    if ([value hasPrefix:@"ar"]) return @"ar";
    return @"auto";
}

+ (BOOL)_preferredLanguage:(NSString *)preferred matchesPrefix:(NSString *)prefix {
    return [preferred isEqualToString:prefix] || [preferred hasPrefix:[prefix stringByAppendingString:@"-"]];
}

+ (NSDictionary<NSString *, NSString *> *)_languageNativeNames {
    return @{
        @"auto": @"Auto",
        @"en": @"English",
        @"zh-Hans": @"简体中文",
        @"zh-Hant": @"繁體中文",
        @"ja": @"日本語",
        @"ko": @"한국어",
        @"ru": @"Русский",
        @"es": @"Español",
        @"vi": @"Tiếng Việt",
        @"th": @"ไทย",
        @"pt": @"Português",
        @"fr": @"Français",
        @"de": @"Deutsch",
        @"ar": @"العربية",
    };
}

+ (NSDictionary<NSString *, NSString *> *)_dictionaryForLanguageCode:(NSString *)code {
    NSString *normalized = [self _normalizedOption:code];
    if ([normalized isEqualToString:@"en"]) return VCLangENDictionary();
    if ([normalized isEqualToString:@"zh-Hans"]) return VCLangZHDictionary();
    if ([normalized isEqualToString:@"zh-Hant"]) return VCLangZHHantDictionary();
    if ([normalized isEqualToString:@"ja"]) return VCLangJADictionary();
    if ([normalized isEqualToString:@"ko"]) return VCLangKODictionary();
    if ([normalized isEqualToString:@"ru"]) return VCLangRUDictionary();
    if ([normalized isEqualToString:@"es"]) return VCLangESDictionary();
    if ([normalized isEqualToString:@"vi"]) return VCLangVIDictionary();
    if ([normalized isEqualToString:@"th"]) return VCLangTHDictionary();
    if ([normalized isEqualToString:@"pt"]) return VCLangPTDictionary();
    if ([normalized isEqualToString:@"fr"]) return VCLangFRDictionary();
    if ([normalized isEqualToString:@"de"]) return VCLangDEDictionary();
    if ([normalized isEqualToString:@"ar"]) return VCLangARDictionary();
    return @{};
}

@end
