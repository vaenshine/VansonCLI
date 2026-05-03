/**
 * VCVerificationGate.mm -- Local verification for executed tool calls
 */

#import "VCVerificationGate.h"
#import "../ToolCall/VCToolCallParser.h"
#import "../../Patches/VCPatchManager.h"
#import "../../Patches/VCPatchItem.h"
#import "../../Patches/VCValueItem.h"
#import "../../Patches/VCHookItem.h"
#import "../../Patches/VCNetRule.h"
#import "../../Runtime/VCValueReader.h"
#import "../../UIInspector/VCUIInspector.h"
#import "../../Hook/VCHookManager.h"
#import "../../Vendor/MemoryBackend/Engine/VCMemEngine.h"
#import "../../../VansonCLI.h"
#import <math.h>

static NSString *VCColorHexString(UIColor *color) {
    if (!color) return nil;
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) return nil;
    return [NSString stringWithFormat:@"%02X%02X%02X",
            (int)lround(r * 255.0), (int)lround(g * 255.0), (int)lround(b * 255.0)];
}

static NSString *VCNormalizedColorHex6(id value) {
    NSMutableString *hex = [NSMutableString new];
    NSString *source = [[value description] stringByReplacingOccurrencesOfString:@"#" withString:@""];
    NSCharacterSet *hexSet = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"];
    for (NSUInteger idx = 0; idx < source.length; idx++) {
        unichar ch = [source characterAtIndex:idx];
        if ([hexSet characterIsMember:ch]) {
            [hex appendFormat:@"%c", (char)tolower((int)ch)];
        }
    }
    if (hex.length == 8) return [hex substringToIndex:6];
    if (hex.length >= 6) return [hex substringToIndex:6];
    return [hex copy];
}

static BOOL VCCGRectFromVerificationValue(id value, CGRect *rectOut) {
    if ([value isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)value;
        id xValue = dict[@"x"] ?: dict[@"left"];
        id yValue = dict[@"y"] ?: dict[@"top"];
        id widthValue = dict[@"width"] ?: dict[@"w"];
        id heightValue = dict[@"height"] ?: dict[@"h"];
        if ([xValue respondsToSelector:@selector(doubleValue)] &&
            [yValue respondsToSelector:@selector(doubleValue)] &&
            [widthValue respondsToSelector:@selector(doubleValue)] &&
            [heightValue respondsToSelector:@selector(doubleValue)]) {
            if (rectOut) {
                *rectOut = CGRectMake([xValue doubleValue], [yValue doubleValue], [widthValue doubleValue], [heightValue doubleValue]);
            }
            return YES;
        }
    }
    if ([value isKindOfClass:[NSString class]]) {
        CGRect rect = CGRectFromString((NSString *)value);
        if (!CGRectIsNull(rect) && !CGRectIsEmpty(rect)) {
            if (rectOut) *rectOut = rect;
            return YES;
        }
    }
    return NO;
}

static BOOL VCCGRectApproximatelyEqual(CGRect a, CGRect b) {
    return fabs(a.origin.x - b.origin.x) < 0.5 &&
           fabs(a.origin.y - b.origin.y) < 0.5 &&
           fabs(a.size.width - b.size.width) < 0.5 &&
           fabs(a.size.height - b.size.height) < 0.5;
}

static BOOL VCStringMatchesExpectedValue(NSString *actual, NSString *expected, NSString *type) {
    if (!expected.length) return NO;
    NSString *normalizedType = type.lowercaseString ?: @"";
    NSString *actualTrimmed = [[actual ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    NSString *expectedTrimmed = [[expected stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];

    if ([normalizedType isEqualToString:@"bool"]) {
        BOOL actualBool = [@[@"1", @"yes", @"true"] containsObject:actualTrimmed];
        BOOL expectedBool = [@[@"1", @"yes", @"true", @"on"] containsObject:expectedTrimmed];
        return actualBool == expectedBool;
    }

    if ([@[@"int", @"float", @"double", @"long"] containsObject:normalizedType]) {
        double actualNumber = [actualTrimmed doubleValue];
        double expectedNumber = [expectedTrimmed doubleValue];
        return fabs(actualNumber - expectedNumber) < 0.0001;
    }

    return [actualTrimmed isEqualToString:expectedTrimmed];
}

static NSString *VCNormalizedHexVerificationString(NSString *value) {
    NSMutableString *normalized = [NSMutableString new];
    NSString *source = [value isKindOfClass:[NSString class]] ? value : @"";
    NSCharacterSet *hexSet = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"];
    for (NSUInteger idx = 0; idx < source.length; idx++) {
        unichar ch = [source characterAtIndex:idx];
        if ([hexSet characterIsMember:ch]) {
            [normalized appendFormat:@"%c", (char)tolower((int)ch)];
        }
    }
    return [normalized copy];
}

static NSString *VCHexStringFromData(NSData *data) {
    if (![data isKindOfClass:[NSData class]] || data.length == 0) return @"";
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    NSMutableString *hex = [NSMutableString stringWithCapacity:(data.length * 2)];
    for (NSUInteger idx = 0; idx < data.length; idx++) {
        [hex appendFormat:@"%02x", bytes[idx]];
    }
    return [hex copy];
}

@implementation VCVerificationGate

+ (void)applyVerificationToToolCall:(VCToolCall *)toolCall {
    if (!toolCall) return;

    toolCall.verificationStatus = VCToolCallVerificationClaimed;
    toolCall.verificationMessage = @"Applied, but not independently verified.";

    VCPatchManager *manager = [VCPatchManager shared];

    switch (toolCall.type) {
        case VCToolCallModifyValue: {
            NSString *mode = [toolCall.params[@"mode"] isKindOfClass:[NSString class]] ? [toolCall.params[@"mode"] lowercaseString] : @"";
            NSString *source = [toolCall.params[@"source"] isKindOfClass:[NSString class]] ? [toolCall.params[@"source"] lowercaseString] : @"";
            if ([mode isEqualToString:@"write_once"] || [mode isEqualToString:@"writeonce"] || [mode isEqualToString:@"write"] ||
                [source rangeOfString:@"scan"].location != NSNotFound) {
                toolCall.verificationStatus = VCToolCallVerificationClaimed;
                toolCall.verificationMessage = @"Memory write completed.";
                return;
            }
            VCValueItem *matched = nil;
            for (VCValueItem *item in [manager allValues]) {
                if ([item.sourceToolID isEqualToString:toolCall.toolID]) {
                    matched = item;
                    break;
                }
            }
            if (!matched || !matched.locked) {
                toolCall.verificationStatus = VCToolCallVerificationFailed;
                toolCall.verificationMessage = @"Value lock was not found in the patch manager.";
                return;
            }
            NSString *encoding = @"i";
            NSString *type = matched.dataType.lowercaseString ?: @"int";
            if ([type isEqualToString:@"float"]) encoding = @"f";
            else if ([type isEqualToString:@"double"]) encoding = @"d";
            else if ([type isEqualToString:@"bool"]) encoding = @"B";
            else if ([type isEqualToString:@"long"]) encoding = @"l";
            NSString *actual = [VCValueReader readValueAtAddress:matched.address typeEncoding:encoding];
            if (VCStringMatchesExpectedValue(actual, matched.modifiedValue, matched.dataType)) {
                toolCall.verificationStatus = VCToolCallVerificationVerified;
                toolCall.verificationMessage = [NSString stringWithFormat:@"Verified locked %@ value at 0x%llx.",
                                                matched.dataType ?: @"value", (unsigned long long)matched.address];
            } else {
                toolCall.verificationStatus = VCToolCallVerificationFailed;
                toolCall.verificationMessage = [NSString stringWithFormat:@"Expected %@ but read %@.",
                                                matched.modifiedValue ?: @"(nil)", actual ?: @"(nil)"];
            }
            return;
        }

        case VCToolCallWriteMemoryBytes: {
            uintptr_t address = 0;
            id rawAddress = toolCall.params[@"address"] ?: toolCall.params[@"addr"];
            if ([rawAddress isKindOfClass:[NSNumber class]]) address = (uintptr_t)[(NSNumber *)rawAddress unsignedLongLongValue];
            else if ([rawAddress isKindOfClass:[NSString class]]) address = (uintptr_t)strtoull([(NSString *)rawAddress UTF8String], NULL, 0);

            NSString *expectedHex = VCNormalizedHexVerificationString(toolCall.params[@"hexData"] ?: toolCall.params[@"hex_data"] ?: toolCall.params[@"bytes"] ?: toolCall.params[@"data"]);
            if (address == 0 || expectedHex.length == 0 || (expectedHex.length % 2) != 0) {
                toolCall.verificationStatus = VCToolCallVerificationClaimed;
                toolCall.verificationMessage = @"Raw byte write ran, but no concrete verification payload was available.";
                return;
            }

            NSData *actualData = [[VCMemEngine shared] readMemory:(uint64_t)address length:(expectedHex.length / 2)];
            NSString *actualHex = VCHexStringFromData(actualData);
            if (actualHex.length > 0 && [actualHex isEqualToString:expectedHex]) {
                toolCall.verificationStatus = VCToolCallVerificationVerified;
                toolCall.verificationMessage = [NSString stringWithFormat:@"Verified %lu raw bytes at 0x%llx.",
                                                (unsigned long)actualData.length,
                                                (unsigned long long)address];
            } else {
                toolCall.verificationStatus = VCToolCallVerificationFailed;
                toolCall.verificationMessage = actualHex.length > 0
                    ? [NSString stringWithFormat:@"Expected %@ but read %@.", expectedHex, actualHex]
                    : @"Raw byte write could not be re-read for verification.";
            }
            return;
        }

        case VCToolCallPatchMethod:
        case VCToolCallSwizzleMethod: {
            for (VCPatchItem *item in [manager allPatches]) {
                if ([item.sourceToolID isEqualToString:toolCall.toolID] && item.enabled) {
                    toolCall.verificationStatus = VCToolCallVerificationVerified;
                    toolCall.verificationMessage = @"Verified patch registration in the patch manager.";
                    return;
                }
            }
            toolCall.verificationStatus = VCToolCallVerificationFailed;
            toolCall.verificationMessage = @"Patch was not registered as enabled.";
            return;
        }

        case VCToolCallHookMethod: {
            for (VCHookItem *item in [manager allHooks]) {
                if ([item.sourceToolID isEqualToString:toolCall.toolID] && item.enabled) {
                    toolCall.verificationStatus = VCToolCallVerificationVerified;
                    toolCall.verificationMessage = @"Verified hook registration in the patch manager.";
                    return;
                }
            }
            toolCall.verificationStatus = VCToolCallVerificationFailed;
            toolCall.verificationMessage = @"Hook was not registered as enabled.";
            return;
        }

        case VCToolCallModifyHeader: {
            for (VCNetRule *item in [manager allRules]) {
                if ([item.sourceToolID isEqualToString:toolCall.toolID] && item.enabled) {
                    toolCall.verificationStatus = VCToolCallVerificationVerified;
                    toolCall.verificationMessage = @"Verified network rule registration.";
                    return;
                }
            }
            toolCall.verificationStatus = VCToolCallVerificationFailed;
            toolCall.verificationMessage = @"Network rule was not registered as enabled.";
            return;
        }

        case VCToolCallModifyView: {
            VCUIInspector *inspector = [VCUIInspector shared];
            uintptr_t address = 0;
            id rawAddress = toolCall.params[@"address"] ?: toolCall.params[@"viewAddress"] ?: toolCall.params[@"view_address"];
            if ([rawAddress isKindOfClass:[NSNumber class]]) address = (uintptr_t)[(NSNumber *)rawAddress unsignedLongLongValue];
            else if ([rawAddress isKindOfClass:[NSString class]]) address = (uintptr_t)strtoull([(NSString *)rawAddress UTF8String], NULL, 0);
            UIView *targetView = address ? [inspector viewForAddress:address] : inspector.currentSelectedView;
            if (!targetView) {
                toolCall.verificationStatus = VCToolCallVerificationFailed;
                toolCall.verificationMessage = @"Target view is no longer available.";
                return;
            }

            NSString *property = [toolCall.params[@"property"] ?: toolCall.params[@"key"] ?: toolCall.params[@"attribute"] ?: @"" lowercaseString];
            id expected = toolCall.params[@"value"] ?: toolCall.params[@"newValue"] ?: toolCall.params[@"new_value"];
            NSDictionary *props = [inspector propertiesForView:targetView];

            if ([property isEqualToString:@"hidden"]) {
                BOOL actual = targetView.hidden;
                BOOL expectedBool = [expected respondsToSelector:@selector(boolValue)] ? [expected boolValue] : NO;
                toolCall.verificationStatus = (actual == expectedBool) ? VCToolCallVerificationVerified : VCToolCallVerificationFailed;
                toolCall.verificationMessage = (actual == expectedBool) ? @"Verified view hidden state." : @"View hidden state did not match.";
                return;
            }
            if ([property isEqualToString:@"alpha"]) {
                double actual = targetView.alpha;
                double expectedDouble = [expected respondsToSelector:@selector(doubleValue)] ? [expected doubleValue] : 0.0;
                toolCall.verificationStatus = (fabs(actual - expectedDouble) < 0.0001) ? VCToolCallVerificationVerified : VCToolCallVerificationFailed;
                toolCall.verificationMessage = (fabs(actual - expectedDouble) < 0.0001) ? @"Verified view alpha." : @"View alpha did not match.";
                return;
            }
            if ([property isEqualToString:@"frame"]) {
                CGRect expectedFrame = CGRectNull;
                BOOL hasExpectedFrame = VCCGRectFromVerificationValue(expected, &expectedFrame);
                BOOL matched = hasExpectedFrame && VCCGRectApproximatelyEqual(targetView.frame, expectedFrame);
                toolCall.verificationStatus = matched ? VCToolCallVerificationVerified : VCToolCallVerificationFailed;
                toolCall.verificationMessage = matched
                    ? @"Verified view frame."
                    : [NSString stringWithFormat:@"View frame mismatch. Expected %@, actual %@.",
                       hasExpectedFrame ? NSStringFromCGRect(expectedFrame) : [expected description],
                       NSStringFromCGRect(targetView.frame)];
                return;
            }
            if ([property isEqualToString:@"backgroundcolor"] || [property isEqualToString:@"textcolor"]) {
                UIColor *color = [property isEqualToString:@"backgroundcolor"] ? targetView.backgroundColor : [targetView valueForKey:@"textColor"];
                NSString *actual = [[VCColorHexString(color) lowercaseString] ?: @"" copy];
                NSString *expectedColor = VCNormalizedColorHex6(expected);
                toolCall.verificationStatus = [actual isEqualToString:expectedColor] ? VCToolCallVerificationVerified : VCToolCallVerificationFailed;
                toolCall.verificationMessage = [actual isEqualToString:expectedColor]
                    ? @"Verified view color."
                    : [NSString stringWithFormat:@"View color mismatch. Expected #%@, actual #%@.", expectedColor ?: @"", actual ?: @""];
                return;
            }
            if ([property isEqualToString:@"text"]) {
                NSString *actual = props[@"text"];
                NSString *expectedText = [expected description];
                toolCall.verificationStatus = [actual isEqualToString:expectedText] ? VCToolCallVerificationVerified : VCToolCallVerificationFailed;
                toolCall.verificationMessage = [actual isEqualToString:expectedText] ? @"Verified view text." : @"View text did not match.";
                return;
            }

            toolCall.verificationStatus = VCToolCallVerificationClaimed;
            toolCall.verificationMessage = @"Applied view mutation, but only registration-level verification is available.";
            return;
        }

        case VCToolCallInsertSubview: {
            VCUIInspector *inspector = [VCUIInspector shared];
            uintptr_t address = 0;
            id insertedAddress = toolCall.params[@"insertedAddress"];
            if ([insertedAddress isKindOfClass:[NSString class]]) {
                address = (uintptr_t)strtoull([(NSString *)insertedAddress UTF8String], NULL, 0);
            } else if ([insertedAddress isKindOfClass:[NSNumber class]]) {
                address = (uintptr_t)[(NSNumber *)insertedAddress unsignedLongLongValue];
            }
            UIView *insertedView = address ? [inspector viewForAddress:address] : inspector.currentSelectedView;
            if (insertedView) {
                toolCall.verificationStatus = VCToolCallVerificationVerified;
                toolCall.verificationMessage = [NSString stringWithFormat:@"Verified inserted <%@: %p>.",
                                                NSStringFromClass([insertedView class]), insertedView];
            } else {
                toolCall.verificationStatus = VCToolCallVerificationClaimed;
                toolCall.verificationMessage = @"Subview insertion completed.";
            }
            return;
        }

        case VCToolCallInvokeSelector: {
            toolCall.verificationStatus = VCToolCallVerificationClaimed;
            toolCall.verificationMessage = toolCall.resultMessage.length > 0 ? toolCall.resultMessage : @"Selector invocation ran, but there is no generic postcondition to verify.";
            return;
        }

        default: {
            toolCall.verificationStatus = VCToolCallVerificationNone;
            toolCall.verificationMessage = nil;
            return;
        }
    }
}

@end
