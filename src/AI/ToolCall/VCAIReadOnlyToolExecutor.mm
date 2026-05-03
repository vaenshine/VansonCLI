/**
 * VCAIReadOnlyToolExecutor -- safe auto-executed analysis tools for AI
 */

#import "VCAIReadOnlyToolExecutor.h"
#import "VCToolCallParser.h"
#import "../../Runtime/VCRuntimeEngine.h"
#import "../../Runtime/VCRuntimeModels.h"
#import "../../Runtime/VCStringScanner.h"
#import "../../Runtime/VCInstanceScanner.h"
#import "../../Runtime/VCValueReader.h"
#import "../../Memory/VCMemoryBrowserEngine.h"
#import "../../Memory/VCMemoryScanEngine.h"
#import "../../Memory/VCMemoryLocatorEngine.h"
#import "../../Process/VCProcessInfo.h"
#import "../../Unity/VCUnityRuntimeEngine.h"
#import "../../Trace/VCTraceManager.h"
#import "../../UI/Base/VCOverlayTrackingManager.h"
#import "../../UI/Base/VCOverlayRootViewController.h"
#import "../../Network/VCNetMonitor.h"
#import "../../Network/VCNetRecord.h"
#import "../../UIInspector/VCUIInspector.h"
#import "../../Core/VCConfig.h"
#import "../Security/VCPromptLeakGuard.h"
#import "../../../VansonCLI.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach/mach.h>
#include <math.h>
#include <float.h>

static NSString *VCAIHexAddress(uint64_t address) {
    return [NSString stringWithFormat:@"0x%llx", (unsigned long long)address];
}

static NSString *VCAITrimmedString(id value) {
    if ([value isKindOfClass:[NSString class]]) {
        return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        return [[(NSNumber *)value stringValue] copy];
    }
    return @"";
}

static NSString *VCAIStringParam(NSDictionary *params, NSArray<NSString *> *keys) {
    for (NSString *key in keys) {
        NSString *value = VCAITrimmedString(params[key]);
        if (value.length > 0) return value;
    }
    return @"";
}

static NSArray<NSString *> *VCAIStringArrayParam(NSDictionary *params, NSArray<NSString *> *keys) {
    for (NSString *key in keys) {
        id rawValue = params[key];
        if ([rawValue isKindOfClass:[NSArray class]]) {
            NSMutableArray<NSString *> *items = [NSMutableArray new];
            for (id item in (NSArray *)rawValue) {
                NSString *trimmed = VCAITrimmedString(item);
                if (trimmed.length > 0) [items addObject:trimmed];
            }
            if (items.count > 0) return [items copy];
        } else if ([rawValue isKindOfClass:[NSString class]]) {
            NSString *joined = VCAITrimmedString(rawValue);
            if (joined.length == 0) continue;
            NSArray<NSString *> *parts = [joined componentsSeparatedByString:@","];
            NSMutableArray<NSString *> *items = [NSMutableArray new];
            for (NSString *part in parts) {
                NSString *trimmed = VCAITrimmedString(part);
                if (trimmed.length > 0) [items addObject:trimmed];
            }
            if (items.count > 0) return [items copy];
        }
    }
    return @[];
}

static NSUInteger VCAIUnsignedParam(NSDictionary *params, NSArray<NSString *> *keys, NSUInteger fallbackValue, NSUInteger maxValue) {
    for (NSString *key in keys) {
        id rawValue = params[key];
        if ([rawValue respondsToSelector:@selector(unsignedIntegerValue)]) {
            NSUInteger value = [rawValue unsignedIntegerValue];
            if (value == 0) continue;
            return MIN(value, maxValue);
        }
    }
    return MIN(fallbackValue, maxValue);
}

static BOOL VCAIBoolParam(NSDictionary *params, NSArray<NSString *> *keys, BOOL fallbackValue) {
    for (NSString *key in keys) {
        id rawValue = params[key];
        if ([rawValue respondsToSelector:@selector(boolValue)]) {
            return [rawValue boolValue];
        }
    }
    return fallbackValue;
}

static double VCAIDoubleParam(NSDictionary *params, NSArray<NSString *> *keys, double fallbackValue) {
    for (NSString *key in keys) {
        id rawValue = params[key];
        if ([rawValue respondsToSelector:@selector(doubleValue)]) {
            return [rawValue doubleValue];
        }
    }
    return fallbackValue;
}

static uintptr_t VCAIAddressParam(NSDictionary *params, NSArray<NSString *> *keys) {
    for (NSString *key in keys) {
        id rawValue = params[key];
        if ([rawValue isKindOfClass:[NSNumber class]]) {
            return (uintptr_t)[(NSNumber *)rawValue unsignedLongLongValue];
        }
        if ([rawValue isKindOfClass:[NSString class]]) {
            NSString *text = VCAITrimmedString(rawValue);
            if (text.length == 0) continue;
            return (uintptr_t)strtoull(text.UTF8String, NULL, 0);
        }
    }
    return 0;
}

static NSString *VCAITruncatedString(NSString *value, NSUInteger maxLength) {
    NSString *safeValue = [value isKindOfClass:[NSString class]] ? value : @"";
    if (safeValue.length <= maxLength) return safeValue;
    return [[safeValue substringToIndex:maxLength] stringByAppendingString:@"..."];
}

static NSArray *VCAITail(NSArray *items, NSUInteger count) {
    if (![items isKindOfClass:[NSArray class]]) return @[];
    if (items.count <= count) return items;
    return [items subarrayWithRange:NSMakeRange(items.count - count, count)];
}

static NSArray *VCAIReversedArray(NSArray *items) {
    if (![items isKindOfClass:[NSArray class]]) return @[];
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:items.count];
    for (id item in [items reverseObjectEnumerator]) {
        [result addObject:item];
    }
    return result;
}

static NSData *VCAIJSONObjectData(id object) {
    if (![NSJSONSerialization isValidJSONObject:object]) return nil;
    return [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted error:nil];
}

static NSString *VCAIJSONString(id object) {
    NSData *data = VCAIJSONObjectData(object);
    if (!data) return @"{}";
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"{}";
}

static NSString *VCAISlugString(NSString *value) {
    NSString *lower = VCAITrimmedString(value).lowercaseString;
    if (lower.length == 0) return @"diagram";

    NSMutableString *slug = [NSMutableString new];
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789-_"];
    for (NSUInteger idx = 0; idx < lower.length; idx++) {
        unichar ch = [lower characterAtIndex:idx];
        NSString *charString = [NSString stringWithCharacters:&ch length:1];
        if ([allowed characterIsMember:ch]) {
            [slug appendString:charString];
        } else if ([charString rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].location != NSNotFound || ch == '/' || ch == '.') {
            if (![slug hasSuffix:@"-"]) [slug appendString:@"-"];
        }
    }
    while ([slug hasSuffix:@"-"]) {
        [slug deleteCharactersInRange:NSMakeRange(slug.length - 1, 1)];
    }
    return slug.length > 0 ? slug : @"diagram";
}

static NSDictionary *VCAISuccessResult(VCToolCall *toolCall,
                                       NSString *summary,
                                       NSDictionary *payload,
                                       NSDictionary *reference) {
    NSMutableDictionary *result = [NSMutableDictionary new];
    result[@"toolID"] = toolCall.toolID ?: @"";
    result[@"tool"] = toolCall.title ?: @"tool";
    result[@"success"] = @YES;
    result[@"summary"] = summary ?: @"Completed";
    result[@"payload"] = payload ?: @{};
    if (reference) result[@"reference"] = reference;
    return [result copy];
}

static NSDictionary *VCAIErrorResult(VCToolCall *toolCall, NSString *summary) {
    return @{
        @"toolID": toolCall.toolID ?: @"",
        @"tool": toolCall.title ?: @"tool",
        @"success": @NO,
        @"summary": summary ?: @"Tool execution failed",
        @"payload": @{}
    };
}

static NSUInteger VCAIByteSizeForEncoding(NSString *encoding) {
    NSString *trimmed = VCAITrimmedString(encoding);
    if (trimmed.length == 0) return 0;
    unichar type = [trimmed characterAtIndex:0];
    switch (type) {
        case 'c':
        case 'C':
        case 'B':
            return sizeof(char);
        case 's':
        case 'S':
            return sizeof(short);
        case 'i':
        case 'I':
            return sizeof(int);
        case 'l':
        case 'L':
            return sizeof(long);
        case 'q':
        case 'Q':
            return sizeof(long long);
        case 'f':
            return sizeof(float);
        case 'd':
            return sizeof(double);
        case '^':
        case '?':
            return sizeof(void *);
        case '{': {
            if ([trimmed hasPrefix:@"{CGPoint"]) return sizeof(CGPoint);
            if ([trimmed hasPrefix:@"{CGSize"]) return sizeof(CGSize);
            if ([trimmed hasPrefix:@"{CGRect"]) return sizeof(CGRect);
            if ([trimmed hasPrefix:@"{CGAffineTransform"]) return sizeof(CGAffineTransform);
            if ([trimmed hasPrefix:@"{UIEdgeInsets"]) return sizeof(UIEdgeInsets);
            if ([trimmed hasPrefix:@"{NSRange"] || [trimmed hasPrefix:@"{_NSRange"]) return sizeof(NSRange);
            return 0;
        }
        default:
            return 0;
    }
}

static BOOL VCAIEncodingIsSafeForRawRead(NSString *encoding) {
    NSString *trimmed = VCAITrimmedString(encoding);
    if (trimmed.length == 0) return NO;
    unichar type = [trimmed characterAtIndex:0];
    switch (type) {
        case 'c':
        case 'C':
        case 's':
        case 'S':
        case 'i':
        case 'I':
        case 'l':
        case 'L':
        case 'q':
        case 'Q':
        case 'f':
        case 'd':
        case 'B':
        case '^':
        case '?':
        case '{':
            return YES;
        default:
            return NO;
    }
}

static NSDictionary *VCAIMemoryRegionDictionary(VCMemRegion *region) {
    if (!region) return @{};
    return @{
        @"start": VCAIHexAddress(region.start),
        @"end": VCAIHexAddress(region.end),
        @"size": @(region.size),
        @"protection": region.protection ?: @"---"
    };
}

static NSString *VCAISafeObjectDescription(id object, NSUInteger maxLength) {
    if (!object) return @"nil";
    NSString *description = nil;
    @try {
        description = [object debugDescription];
        if (description.length == 0) description = [object description];
    } @catch (NSException *exception) {
        description = [NSString stringWithFormat:@"<%@: %p (description threw %@)>",
                       NSStringFromClass([object class]) ?: @"NSObject",
                       (__bridge void *)object,
                       exception.name ?: @"exception"];
    }
    if (description.length == 0) {
        description = [NSString stringWithFormat:@"<%@: %p>",
                       NSStringFromClass([object class]) ?: @"NSObject",
                       (__bridge void *)object];
    }
    BOOL didSanitize = NO;
    NSString *sanitized = [VCPromptLeakGuard sanitizedAssistantText:description didSanitize:&didSanitize];
    return VCAITruncatedString(didSanitize ? @"[redacted]" : sanitized, maxLength);
}

static NSString *VCAIMermaidEscapedLabel(NSString *value) {
    NSString *text = [VCAITrimmedString(value) copy];
    if (text.length == 0) return @"";
    text = [text stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    text = [text stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    text = [text stringByReplacingOccurrencesOfString:@"\n" withString:@"<br/>"];
    text = [text stringByReplacingOccurrencesOfString:@"\r" withString:@""];
    return text;
}

static NSString *VCAIHexStringFromData(NSData *data) {
    if (![data isKindOfClass:[NSData class]] || data.length == 0) return @"";
    const unsigned char *bytes = (const unsigned char *)data.bytes;
    NSMutableString *hex = [NSMutableString stringWithCapacity:data.length * 2];
    for (NSUInteger idx = 0; idx < data.length; idx++) {
        [hex appendFormat:@"%02x", bytes[idx]];
    }
    return hex;
}

static NSData *VCAIDataFromHexString(NSString *hexString) {
    NSString *hex = [[VCAITrimmedString(hexString) lowercaseString] copy];
    if (hex.length == 0 || (hex.length % 2) != 0) return nil;

    NSMutableData *data = [NSMutableData dataWithCapacity:(hex.length / 2)];
    for (NSUInteger idx = 0; idx < hex.length; idx += 2) {
        NSString *chunk = [hex substringWithRange:NSMakeRange(idx, 2)];
        unsigned int value = 0;
        if ([[NSScanner scannerWithString:chunk] scanHexInt:&value]) {
            unsigned char byte = (unsigned char)value;
            [data appendBytes:&byte length:1];
        } else {
            return nil;
        }
    }
    return [data copy];
}

static NSString *VCAIFrameString(CGRect frame) {
    return NSStringFromCGRect(frame);
}

typedef struct {
    double x;
    double y;
} VCAIVector2d;

typedef struct {
    double x;
    double y;
    double z;
} VCAIVector3d;

typedef struct {
    double x;
    double y;
    double z;
    double w;
} VCAIVector4d;

static NSString *VCAIStructTypeNormalized(NSString *value) {
    NSString *normalized = [[VCAITrimmedString(value) lowercaseString] copy];
    if (normalized.length == 0) return @"";
    if ([normalized isEqualToString:@"point"] || [normalized isEqualToString:@"cgpoint"]) return @"cgpoint";
    if ([normalized isEqualToString:@"size"] || [normalized isEqualToString:@"cgsize"]) return @"cgsize";
    if ([normalized isEqualToString:@"rect"] || [normalized isEqualToString:@"cgrect"]) return @"cgrect";
    if ([normalized isEqualToString:@"affine"] || [normalized isEqualToString:@"cgaffinetransform"]) return @"affine";
    if ([normalized isEqualToString:@"uiedgeinsets"] || [normalized isEqualToString:@"insets"]) return @"insets";
    if ([normalized isEqualToString:@"nsrange"] || [normalized isEqualToString:@"range"]) return @"range";
    if ([normalized isEqualToString:@"vec2"] || [normalized isEqualToString:@"vector2"] || [normalized isEqualToString:@"vector2f"] || [normalized isEqualToString:@"float2"]) return @"vector2f";
    if ([normalized isEqualToString:@"vector2d"] || [normalized isEqualToString:@"double2"]) return @"vector2d";
    if ([normalized isEqualToString:@"vec3"] || [normalized isEqualToString:@"vector3"] || [normalized isEqualToString:@"vector3f"] || [normalized isEqualToString:@"float3"]) return @"vector3f";
    if ([normalized isEqualToString:@"vector3d"] || [normalized isEqualToString:@"double3"]) return @"vector3d";
    if ([normalized isEqualToString:@"vec4"] || [normalized isEqualToString:@"vector4"] || [normalized isEqualToString:@"vector4f"] || [normalized isEqualToString:@"float4"]) return @"vector4f";
    if ([normalized isEqualToString:@"vector4d"] || [normalized isEqualToString:@"double4"]) return @"vector4d";
    if ([normalized isEqualToString:@"matrix"] || [normalized isEqualToString:@"matrix4x4"] || [normalized isEqualToString:@"matrix4x4f"] || [normalized isEqualToString:@"float4x4"]) return @"matrix4x4f";
    if ([normalized isEqualToString:@"matrix4x4d"] || [normalized isEqualToString:@"double4x4"]) return @"matrix4x4d";
    return normalized;
}

static NSUInteger VCAIStructByteSize(NSString *structType) {
    NSString *normalized = VCAIStructTypeNormalized(structType);
    if ([normalized isEqualToString:@"cgpoint"]) return sizeof(CGPoint);
    if ([normalized isEqualToString:@"cgsize"]) return sizeof(CGSize);
    if ([normalized isEqualToString:@"cgrect"]) return sizeof(CGRect);
    if ([normalized isEqualToString:@"affine"]) return sizeof(CGAffineTransform);
    if ([normalized isEqualToString:@"insets"]) return sizeof(UIEdgeInsets);
    if ([normalized isEqualToString:@"range"]) return sizeof(NSRange);
    if ([normalized isEqualToString:@"vector2f"]) return sizeof(float) * 2;
    if ([normalized isEqualToString:@"vector2d"]) return sizeof(double) * 2;
    if ([normalized isEqualToString:@"vector3f"]) return sizeof(float) * 3;
    if ([normalized isEqualToString:@"vector3d"]) return sizeof(double) * 3;
    if ([normalized isEqualToString:@"vector4f"]) return sizeof(float) * 4;
    if ([normalized isEqualToString:@"vector4d"]) return sizeof(double) * 4;
    if ([normalized isEqualToString:@"matrix4x4f"]) return sizeof(float) * 16;
    if ([normalized isEqualToString:@"matrix4x4d"]) return sizeof(double) * 16;
    return 0;
}

static NSDictionary *VCAIOverlayViewportPayload(CGFloat width, CGFloat height, CGFloat originX, CGFloat originY) {
    return @{
        @"x": @(originX),
        @"y": @(originY),
        @"width": @(width),
        @"height": @(height)
    };
}

static NSDictionary *VCAIProjectClipCandidate(VCAIVector4d clip,
                                              CGFloat viewportX,
                                              CGFloat viewportY,
                                              CGFloat viewportWidth,
                                              CGFloat viewportHeight,
                                              BOOL flipY,
                                              NSString *layout) {
    double absW = fabs(clip.w);
    if (absW < 1e-6) {
        return @{
            @"layout": layout ?: @"",
            @"valid": @NO,
            @"reason": @"clip.w was near zero"
        };
    }

    double ndcX = clip.x / clip.w;
    double ndcY = clip.y / clip.w;
    double ndcZ = clip.z / clip.w;

    double screenX = viewportX + ((ndcX + 1.0) * 0.5 * viewportWidth);
    double screenYBottomLeft = viewportY + ((ndcY + 1.0) * 0.5 * viewportHeight);
    double screenY = flipY ? (viewportY + viewportHeight - screenYBottomLeft) : screenYBottomLeft;

    BOOL ndcVisible = clip.w > 0.0 &&
        ndcX >= -1.0 && ndcX <= 1.0 &&
        ndcY >= -1.0 && ndcY <= 1.0;

    double ndcDistance = fabs(ndcX) + fabs(ndcY) + fabs(ndcZ);
    double plausibility = (clip.w > 0.0 ? 10.0 : 0.0) - ndcDistance;

    return @{
        @"layout": layout ?: @"",
        @"valid": @YES,
        @"clip": @{
            @"x": @(clip.x),
            @"y": @(clip.y),
            @"z": @(clip.z),
            @"w": @(clip.w)
        },
        @"ndc": @{
            @"x": @(ndcX),
            @"y": @(ndcY),
            @"z": @(ndcZ)
        },
        @"screenPoint": @{
            @"x": @(screenX),
            @"y": @(screenY)
        },
        @"onScreen": @(ndcVisible &&
                       screenX >= viewportX && screenX <= viewportX + viewportWidth &&
                       screenY >= viewportY && screenY <= viewportY + viewportHeight),
        @"plausibilityScore": @(plausibility)
    };
}

static VCAIVector4d VCAIClipVectorWithMatrix(const double *m, VCAIVector4d world, BOOL columnMajor) {
    if (columnMajor) {
        return (VCAIVector4d){
            m[0] * world.x + m[4] * world.y + m[8] * world.z + m[12] * world.w,
            m[1] * world.x + m[5] * world.y + m[9] * world.z + m[13] * world.w,
            m[2] * world.x + m[6] * world.y + m[10] * world.z + m[14] * world.w,
            m[3] * world.x + m[7] * world.y + m[11] * world.z + m[15] * world.w
        };
    }
    return (VCAIVector4d){
        m[0] * world.x + m[1] * world.y + m[2] * world.z + m[3] * world.w,
        m[4] * world.x + m[5] * world.y + m[6] * world.z + m[7] * world.w,
        m[8] * world.x + m[9] * world.y + m[10] * world.z + m[11] * world.w,
        m[12] * world.x + m[13] * world.y + m[14] * world.z + m[15] * world.w
    };
}

static BOOL VCAIMatrixElementsFromRawData(NSData *data, NSString *matrixType, double outElements[16]) {
    NSString *normalized = VCAIStructTypeNormalized(matrixType);
    if ([normalized isEqualToString:@"matrix4x4f"] && data.length >= sizeof(float) * 16) {
        float values[16] = {0};
        [data getBytes:&values length:sizeof(values)];
        for (NSUInteger idx = 0; idx < 16; idx++) outElements[idx] = values[idx];
        return YES;
    }
    if ([normalized isEqualToString:@"matrix4x4d"] && data.length >= sizeof(double) * 16) {
        double values[16] = {0};
        [data getBytes:&values length:sizeof(values)];
        for (NSUInteger idx = 0; idx < 16; idx++) outElements[idx] = values[idx];
        return YES;
    }
    return NO;
}

static double VCAIMatrixProjectionScore(const double m[16],
                                        BOOL columnMajor,
                                        CGFloat viewportWidth,
                                        CGFloat viewportHeight) {
    static const VCAIVector4d kSampleVectors[] = {
        {0.0, 0.0, 1.0, 1.0},
        {0.0, 0.0, 5.0, 1.0},
        {1.0, 1.0, 5.0, 1.0},
        {-1.0, 1.0, 5.0, 1.0},
        {0.0, -1.0, 3.0, 1.0}
    };
    NSArray<NSValue *> *sampleValues = @[
        [NSValue valueWithBytes:&kSampleVectors[0] objCType:@encode(VCAIVector4d)],
        [NSValue valueWithBytes:&kSampleVectors[1] objCType:@encode(VCAIVector4d)],
        [NSValue valueWithBytes:&kSampleVectors[2] objCType:@encode(VCAIVector4d)],
        [NSValue valueWithBytes:&kSampleVectors[3] objCType:@encode(VCAIVector4d)],
        [NSValue valueWithBytes:&kSampleVectors[4] objCType:@encode(VCAIVector4d)]
    ];

    double magnitudePenalty = 0.0;
    double nonZeroCount = 0.0;
    for (NSUInteger idx = 0; idx < 16; idx++) {
        double value = m[idx];
        if (!isfinite(value)) return -DBL_MAX;
        if (fabs(value) > 1e6) magnitudePenalty += 8.0;
        if (fabs(value) > 1e-6) nonZeroCount += 1.0;
    }
    if (nonZeroCount < 6.0) return -DBL_MAX;

    double score = 0.0;
    for (NSValue *boxed in sampleValues) {
        VCAIVector4d world = {0};
        [boxed getValue:&world];
        VCAIVector4d clip = VCAIClipVectorWithMatrix(m, world, columnMajor);
        NSDictionary *candidate = VCAIProjectClipCandidate(clip, 0.0, 0.0, viewportWidth, viewportHeight, YES, columnMajor ? @"column_major" : @"row_major");
        if (![candidate[@"valid"] boolValue]) continue;
        score += [candidate[@"plausibilityScore"] doubleValue];
        if ([candidate[@"onScreen"] boolValue]) score += 4.0;
        NSDictionary *ndc = [candidate[@"ndc"] isKindOfClass:[NSDictionary class]] ? candidate[@"ndc"] : nil;
        double ndcZ = [ndc[@"z"] respondsToSelector:@selector(doubleValue)] ? [ndc[@"z"] doubleValue] : 0.0;
        if (ndcZ > -4.0 && ndcZ < 4.0) score += 1.2;
    }

    double diagonalIdentityPenalty = fabs(m[0] - 1.0) + fabs(m[5] - 1.0) + fabs(m[10] - 1.0) + fabs(m[15] - 1.0);
    if (diagonalIdentityPenalty < 0.3) score -= 12.0;
    return score - magnitudePenalty;
}

static NSDictionary *VCAIViewNodeDictionary(VCViewNode *node, NSInteger depth) {
    if (!node) return @{};
    return @{
        @"className": node.className ?: @"UIView",
        @"address": VCAIHexAddress(node.address),
        @"frame": VCAIFrameString(node.frame),
        @"depth": @(depth),
        @"childrenCount": @(node.children.count),
        @"briefDescription": VCAITruncatedString(node.briefDescription ?: @"", 160)
    };
}

static void VCAIAppendViewNodes(VCViewNode *node,
                                NSInteger depth,
                                NSInteger maxDepth,
                                NSString *filter,
                                NSUInteger limit,
                                NSMutableArray<NSDictionary *> *collector) {
    if (!node || collector.count >= limit || depth > maxDepth) return;

    NSString *candidate = [NSString stringWithFormat:@"%@ %@ %@",
                           node.className ?: @"",
                           VCAIHexAddress(node.address),
                           node.briefDescription ?: @""].lowercaseString;
    BOOL matches = (filter.length == 0 || [candidate containsString:filter]);
    if (matches) {
        [collector addObject:VCAIViewNodeDictionary(node, depth)];
        if (collector.count >= limit) return;
    }

    for (VCViewNode *child in node.children ?: @[]) {
        VCAIAppendViewNodes(child, depth + 1, maxDepth, filter, limit, collector);
        if (collector.count >= limit) return;
    }
}

static void VCAIAppendVisibleTextFromView(UIView *view,
                                          NSMutableArray<NSString *> *collector,
                                          NSUInteger limit) {
    if (!view || collector.count >= limit || view.hidden || view.alpha < 0.05) return;

    NSString *text = nil;
    if ([view isKindOfClass:[UILabel class]]) {
        text = ((UILabel *)view).text;
    } else if ([view isKindOfClass:[UIButton class]]) {
        text = ((UIButton *)view).titleLabel.text;
    } else if ([view isKindOfClass:[UITextField class]]) {
        UITextField *field = (UITextField *)view;
        text = field.text.length > 0 ? field.text : field.placeholder;
    } else if ([view isKindOfClass:[UITextView class]]) {
        text = ((UITextView *)view).text;
    }

    NSString *trimmed = VCAITrimmedString(text);
    if (trimmed.length > 0) {
        [collector addObject:VCAITruncatedString(trimmed, 220)];
        if (collector.count >= limit) return;
    }

    for (UIView *subview in view.subviews ?: @[]) {
        VCAIAppendVisibleTextFromView(subview, collector, limit);
        if (collector.count >= limit) return;
    }
}

static UIViewController *VCAITopViewControllerFromController(UIViewController *controller) {
    UIViewController *current = controller;
    while (current.presentedViewController) {
        current = current.presentedViewController;
    }
    if ([current isKindOfClass:[UINavigationController class]]) {
        UIViewController *visible = ((UINavigationController *)current).visibleViewController;
        if (visible) return VCAITopViewControllerFromController(visible);
    }
    if ([current isKindOfClass:[UITabBarController class]]) {
        UIViewController *selected = ((UITabBarController *)current).selectedViewController;
        if (selected) return VCAITopViewControllerFromController(selected);
    }
    return current;
}

static NSDictionary *VCAIAlertPayloadForController(UIViewController *controller, UIWindow *window) {
    if (!controller) return @{};
    NSMutableArray<NSString *> *texts = [NSMutableArray new];
    VCAIAppendVisibleTextFromView(controller.view, texts, 40);

    NSMutableDictionary *payload = [@{
        @"controllerClass": NSStringFromClass([controller class]) ?: @"UIViewController",
        @"windowClass": NSStringFromClass([window class]) ?: @"UIWindow",
        @"windowLevel": @(window.windowLevel),
        @"viewFrame": NSStringFromCGRect(controller.view.frame),
        @"visibleText": [texts copy],
    } mutableCopy];

    if ([controller isKindOfClass:[UIAlertController class]]) {
        UIAlertController *alert = (UIAlertController *)controller;
        NSMutableArray<NSDictionary *> *actions = [NSMutableArray new];
        for (UIAlertAction *action in alert.actions ?: @[]) {
            [actions addObject:@{
                @"title": action.title ?: @"",
                @"style": @(action.style),
                @"enabled": @(action.enabled)
            }];
        }
        NSMutableArray<NSDictionary *> *fields = [NSMutableArray new];
        for (UITextField *field in alert.textFields ?: @[]) {
            [fields addObject:@{
                @"placeholder": field.placeholder ?: @"",
                @"hasText": @(field.text.length > 0),
                @"secure": @(field.secureTextEntry)
            }];
        }
        payload[@"title"] = alert.title ?: @"";
        payload[@"message"] = alert.message ?: @"";
        payload[@"preferredStyle"] = @(alert.preferredStyle);
        payload[@"actions"] = actions;
        payload[@"textFields"] = fields;
    } else {
        payload[@"title"] = controller.title ?: @"";
    }

    return [payload copy];
}

static NSArray<NSDictionary *> *VCAICurrentAlertPayloads(void) {
    __block NSArray<NSDictionary *> *result = @[];
    dispatch_block_t collect = ^{
        NSMutableArray<NSDictionary *> *alerts = [NSMutableArray new];
        for (UIWindow *window in [UIApplication sharedApplication].windows ?: @[]) {
            if (window.hidden || window.alpha < 0.05) continue;
            UIViewController *top = VCAITopViewControllerFromController(window.rootViewController);
            NSString *controllerClass = NSStringFromClass([top class]) ?: @"";
            NSString *windowClass = NSStringFromClass([window class]) ?: @"";
            BOOL isAlertController = [top isKindOfClass:[UIAlertController class]];
            BOOL looksLikeAlert = [controllerClass rangeOfString:@"Alert" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                                  [windowClass rangeOfString:@"Alert" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                                  window.windowLevel > UIWindowLevelNormal;
            if (isAlertController || looksLikeAlert) {
                NSDictionary *payload = VCAIAlertPayloadForController(top, window);
                if (payload.count > 0) [alerts addObject:payload];
            }
        }
        result = [alerts copy];
    };
    if ([NSThread isMainThread]) {
        collect();
    } else {
        dispatch_sync(dispatch_get_main_queue(), collect);
    }
    return result;
}

static NSDictionary *VCAIReferenceForMermaid(NSString *title,
                                             NSString *diagramType,
                                             NSString *path,
                                             NSString *content,
                                             NSString *summary) {
    return @{
        @"referenceID": [[NSUUID UUID] UUIDString],
        @"kind": @"Diagram",
        @"title": title ?: @"Diagram",
        @"payload": @{
            @"type": @"mermaid",
            @"diagramType": diagramType ?: @"diagram",
            @"path": path ?: @"",
            @"summary": summary ?: @"",
            @"contentPreview": VCAITruncatedString(content ?: @"", 2400)
        }
    };
}

static NSDictionary *VCAIReferenceForFile(NSString *kind,
                                          NSString *title,
                                          NSString *type,
                                          NSString *path,
                                          NSString *summary,
                                          NSDictionary *extraPayload) {
    NSMutableDictionary *payload = [@{
        @"type": type ?: @"file",
        @"path": path ?: @"",
        @"summary": summary ?: @""
    } mutableCopy];
    if ([extraPayload isKindOfClass:[NSDictionary class]]) {
        [payload addEntriesFromDictionary:extraPayload];
    }
    return @{
        @"referenceID": [[NSUUID UUID] UUIDString],
        @"kind": kind ?: @"File",
        @"title": title ?: @"Attachment",
        @"payload": [payload copy]
    };
}

static NSDictionary *VCAISaveBinaryArtifact(NSString *subdirectory,
                                            NSString *title,
                                            NSString *fileExtension,
                                            NSData *data,
                                            NSString **errorMessage) {
    if (data.length == 0) {
        if (errorMessage) *errorMessage = @"Artifact data was empty.";
        return nil;
    }

    NSString *basePath = [VCConfig shared].sessionsPath;
    NSString *artifactPath = subdirectory.length > 0 ? [basePath stringByAppendingPathComponent:subdirectory] : basePath;
    [[NSFileManager defaultManager] createDirectoryAtPath:artifactPath withIntermediateDirectories:YES attributes:nil error:nil];

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyyMMdd-HHmmss";
    NSString *safeExtension = VCAITrimmedString(fileExtension);
    if (safeExtension.length == 0) safeExtension = @"bin";
    NSString *fileName = [NSString stringWithFormat:@"%@-%@.%@",
                          [formatter stringFromDate:[NSDate date]],
                          VCAISlugString(title),
                          safeExtension];
    NSString *path = [artifactPath stringByAppendingPathComponent:fileName];
    NSError *writeError = nil;
    [data writeToFile:path options:NSDataWritingAtomic error:&writeError];
    if (writeError) {
        if (errorMessage) {
            *errorMessage = [NSString stringWithFormat:@"Failed to save artifact: %@", writeError.localizedDescription ?: @"write error"];
        }
        return nil;
    }

    return @{
        @"title": title ?: @"Artifact",
        @"path": path ?: @"",
        @"byteCount": @(data.length),
        @"fileExtension": safeExtension
    };
}

static NSDictionary *VCAISaveMermaidArtifact(NSString *title,
                                             NSString *diagramType,
                                             NSString *content,
                                             NSString *summary,
                                             NSString **errorMessage) {
    NSString *normalizedContent = [content stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([normalizedContent hasPrefix:@"```"]) {
        NSRange firstNewline = [normalizedContent rangeOfString:@"\n"];
        NSRange closingFence = [normalizedContent rangeOfString:@"```" options:NSBackwardsSearch];
        if (firstNewline.location != NSNotFound && closingFence.location != NSNotFound && closingFence.location > firstNewline.location) {
            normalizedContent = [normalizedContent substringWithRange:NSMakeRange(firstNewline.location + 1, closingFence.location - firstNewline.location - 1)];
            normalizedContent = [normalizedContent stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
    }
    if (normalizedContent.length == 0) {
        if (errorMessage) *errorMessage = @"Mermaid content was empty after normalization.";
        return nil;
    }

    NSString *diagramsPath = [[[VCConfig shared] sessionsPath] stringByAppendingPathComponent:@"diagrams"];
    [[NSFileManager defaultManager] createDirectoryAtPath:diagramsPath withIntermediateDirectories:YES attributes:nil error:nil];

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyyMMdd-HHmmss";
    NSString *fileName = [NSString stringWithFormat:@"%@-%@.mmd",
                          [formatter stringFromDate:[NSDate date]],
                          VCAISlugString(title)];
    NSString *path = [diagramsPath stringByAppendingPathComponent:fileName];
    NSError *writeError = nil;
    [normalizedContent writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&writeError];
    if (writeError) {
        if (errorMessage) {
            *errorMessage = [NSString stringWithFormat:@"Failed to save Mermaid diagram: %@", writeError.localizedDescription ?: @"write error"];
        }
        return nil;
    }

    return @{
        @"title": title ?: @"Diagram",
        @"diagramType": diagramType ?: @"diagram",
        @"path": path,
        @"content": normalizedContent,
        @"summary": summary ?: @""
    };
}

static NSTimeInterval VCAIFileTimestampAtPath(NSString *path) {
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    NSDate *date = attributes[NSFileModificationDate] ?: attributes[NSFileCreationDate];
    return [date isKindOfClass:[NSDate class]] ? [date timeIntervalSince1970] : 0;
}

static NSNumber *VCAIFileSizeAtPath(NSString *path) {
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    return [attributes[NSFileSize] respondsToSelector:@selector(unsignedLongLongValue)] ? @([attributes[NSFileSize] unsignedLongLongValue]) : @0;
}

static NSString *VCAIMatrixValidationActionNormalized(NSString *value) {
    NSString *normalized = [VCAITrimmedString(value).lowercaseString copy];
    if (normalized.length == 0) return @"status";
    if ([normalized isEqualToString:@"begin"] || [normalized isEqualToString:@"init"]) return @"start";
    if ([normalized isEqualToString:@"sample"] || [normalized isEqualToString:@"step"] || [normalized isEqualToString:@"record"]) return @"capture";
    if ([normalized isEqualToString:@"summary"] || [normalized isEqualToString:@"inspect"]) return @"status";
    if ([normalized isEqualToString:@"score"] || [normalized isEqualToString:@"analyze"] || [normalized isEqualToString:@"finish"]) return @"rank";
    if ([normalized isEqualToString:@"reset"] || [normalized isEqualToString:@"stop"]) return @"clear";
    return normalized;
}

static NSString *VCAIMatrixValidationMotionNormalized(NSString *value) {
    NSString *normalized = [VCAITrimmedString(value).lowercaseString copy];
    if (normalized.length == 0) return @"rotate_only";
    if ([normalized isEqualToString:@"rotate"] || [normalized isEqualToString:@"rotation"] || [normalized isEqualToString:@"yaw_pitch"]) {
        return @"rotate_only";
    }
    if ([normalized isEqualToString:@"zoom"] || [normalized isEqualToString:@"fov"]) {
        return @"zoom_only";
    }
    if ([normalized isEqualToString:@"move"] || [normalized isEqualToString:@"translate"] || [normalized isEqualToString:@"position"]) {
        return @"move_only";
    }
    if ([normalized isEqualToString:@"mixed"] || [normalized isEqualToString:@"combined"]) {
        return @"mixed";
    }
    return normalized;
}

static NSString *VCAIMatrixValidationCaptureLabel(NSString *value, NSUInteger captureIndex) {
    NSString *trimmed = VCAITrimmedString(value);
    if (trimmed.length > 0) return trimmed;
    return captureIndex == 0 ? @"baseline" : [NSString stringWithFormat:@"capture_%lu", (unsigned long)captureIndex];
}

static double VCAIMatrixValidationAbsoluteThreshold(NSString *matrixType) {
    return [[VCAIStructTypeNormalized(matrixType) copy] isEqualToString:@"matrix4x4d"] ? 1e-8 : 5e-4;
}

static double VCAIMatrixValidationRelativeThreshold(double lhs, double rhs, NSString *matrixType) {
    double magnitude = MAX(fabs(lhs), fabs(rhs));
    return MAX(VCAIMatrixValidationAbsoluteThreshold(matrixType), magnitude * 0.015);
}

static NSArray<NSNumber *> *VCAIMatrixValidationElementsArray(const double elements[16]) {
    NSMutableArray<NSNumber *> *items = [NSMutableArray arrayWithCapacity:16];
    for (NSUInteger idx = 0; idx < 16; idx++) {
        [items addObject:@(elements[idx])];
    }
    return [items copy];
}

@interface VCAIReadOnlyToolExecutor ()

+ (NSDictionary *)_executeMatrixValidationActionForToolCall:(VCToolCall *)toolCall;
+ (NSMutableDictionary *)_matrixValidationSessionStorage;
+ (NSMutableDictionary *)_matrixValidationMutableSessionMatchingParams:(NSDictionary *)params
                                                         errorMessage:(NSString **)errorMessage;
+ (NSArray<NSDictionary *> *)_matrixValidationCandidatesFromParams:(NSDictionary *)params
                                                 defaultMatrixType:(NSString *)matrixType
                                                            limit:(NSUInteger)limit;
+ (NSDictionary *)_matrixValidationCapturedSampleForCandidate:(NSDictionary *)candidate
                                                        label:(NSString *)label
                                                   matrixType:(NSString *)matrixType;
+ (NSArray<NSDictionary *> *)_matrixValidationRankedCandidatesForSession:(NSDictionary *)session
                                                     includeSamplePreview:(BOOL)includeSamplePreview;
+ (NSDictionary *)_matrixValidationSessionSummary:(NSDictionary *)session
                                rankedCandidates:(NSArray<NSDictionary *> *)rankedCandidates;

@end

@implementation VCAIReadOnlyToolExecutor

+ (BOOL)isReadOnlyToolCall:(VCToolCall *)toolCall {
    if (!toolCall) return NO;
    switch (toolCall.type) {
        case VCToolCallQueryRuntime:
        case VCToolCallQueryProcess:
        case VCToolCallQueryNetwork:
        case VCToolCallQueryUI:
        case VCToolCallQueryMemory:
        case VCToolCallMemoryBrowser:
        case VCToolCallMemoryScan:
        case VCToolCallPointerChain:
        case VCToolCallSignatureScan:
        case VCToolCallAddressResolve:
        case VCToolCallExportMermaid:
        case VCToolCallTraceStart:
        case VCToolCallTraceCheckpoint:
        case VCToolCallTraceStop:
        case VCToolCallTraceEvents:
        case VCToolCallTraceExportMermaid:
        case VCToolCallQueryArtifacts:
        case VCToolCallUnityRuntime:
        case VCToolCallProject3D:
            return YES;
        default:
            return NO;
    }
}

+ (NSArray<VCToolCall *> *)readOnlyToolCallsFromArray:(NSArray<VCToolCall *> *)toolCalls {
    NSMutableArray<VCToolCall *> *results = [NSMutableArray new];
    for (VCToolCall *toolCall in toolCalls ?: @[]) {
        [VCToolCallParser normalizeToolCall:toolCall];
        if (toolCall.type == VCToolCallUnknown) continue;
        if ([self isReadOnlyToolCall:toolCall]) {
            [results addObject:toolCall];
        }
    }
    return [results copy];
}

+ (NSArray<VCToolCall *> *)manualToolCallsFromArray:(NSArray<VCToolCall *> *)toolCalls {
    NSMutableArray<VCToolCall *> *results = [NSMutableArray new];
    for (VCToolCall *toolCall in toolCalls ?: @[]) {
        [VCToolCallParser normalizeToolCall:toolCall];
        if (toolCall.type == VCToolCallUnknown) continue;
        if (![self isReadOnlyToolCall:toolCall]) {
            [results addObject:toolCall];
        }
    }
    return [results copy];
}

+ (NSArray<NSDictionary *> *)executeToolCalls:(NSArray<VCToolCall *> *)toolCalls {
    NSMutableArray<NSDictionary *> *results = [NSMutableArray new];
    for (VCToolCall *toolCall in toolCalls ?: @[]) {
        NSDictionary *result = [self _executeToolCall:toolCall];
        if (result) [results addObject:result];
    }
    return [results copy];
}

+ (NSString *)systemMessageForToolResults:(NSArray<NSDictionary *> *)results {
    NSMutableArray<NSDictionary *> *compactResults = [NSMutableArray new];
    for (NSDictionary *result in results ?: @[]) {
        NSMutableDictionary *entry = [NSMutableDictionary new];
        entry[@"tool"] = result[@"tool"] ?: @"tool";
        entry[@"success"] = result[@"success"] ?: @NO;
        entry[@"summary"] = result[@"summary"] ?: @"";
        entry[@"payload"] = result[@"payload"] ?: @{};
        if (result[@"reference"]) entry[@"reference"] = result[@"reference"];
        [compactResults addObject:entry];
    }

    return [NSString stringWithFormat:
            @"[Auto Tool Results]\n%@\nUse these results as the current runtime ground truth. Continue the analysis directly. If the user asked for a diagram, answer with Mermaid and optionally call export_mermaid to persist it.",
            VCAIJSONString(compactResults)];
}

+ (NSArray<NSDictionary *> *)artifactReferencesFromToolResults:(NSArray<NSDictionary *> *)results {
    NSMutableArray<NSDictionary *> *references = [NSMutableArray new];
    for (NSDictionary *result in results ?: @[]) {
        NSDictionary *reference = [result[@"reference"] isKindOfClass:[NSDictionary class]] ? result[@"reference"] : nil;
        if (reference) [references addObject:reference];
    }
    return [references copy];
}

+ (NSDictionary *)_executeToolCall:(VCToolCall *)toolCall {
    if (!toolCall) return nil;

    switch (toolCall.type) {
        case VCToolCallQueryRuntime:
            return [self _executeRuntimeQuery:toolCall];
        case VCToolCallQueryProcess:
            return [self _executeProcessQuery:toolCall];
        case VCToolCallQueryNetwork:
            return [self _executeNetworkQuery:toolCall];
        case VCToolCallQueryUI:
            return [self _executeUIQuery:toolCall];
        case VCToolCallQueryMemory:
            return [self _executeMemoryQuery:toolCall];
        case VCToolCallMemoryBrowser:
            return [self _executeMemoryBrowser:toolCall];
        case VCToolCallMemoryScan:
            return [self _executeMemoryScan:toolCall];
        case VCToolCallPointerChain:
            return [self _executePointerChain:toolCall];
        case VCToolCallSignatureScan:
            return [self _executeSignatureScan:toolCall];
        case VCToolCallAddressResolve:
            return [self _executeAddressResolve:toolCall];
        case VCToolCallExportMermaid:
            return [self _executeMermaidExport:toolCall];
        case VCToolCallTraceStart:
            return [self _executeTraceStart:toolCall];
        case VCToolCallTraceCheckpoint:
            return [self _executeTraceCheckpoint:toolCall];
        case VCToolCallTraceStop:
            return [self _executeTraceStop:toolCall];
        case VCToolCallTraceEvents:
            return [self _executeTraceEvents:toolCall];
        case VCToolCallTraceExportMermaid:
            return [self _executeTraceExportMermaid:toolCall];
        case VCToolCallQueryArtifacts:
            return [self _executeArtifactQuery:toolCall];
        case VCToolCallUnityRuntime:
            return [self _executeUnityRuntimeQuery:toolCall];
        case VCToolCallProject3D:
            return [self _executeProject3D:toolCall];
        default:
            return VCAIErrorResult(toolCall, @"Unsupported auto-executed tool");
    }
}

+ (VCMethodInfo *)_methodInfoForClassInfo:(VCClassInfo *)classInfo
                                 selector:(NSString *)selector
                            isClassMethod:(BOOL)isClassMethod {
    NSArray<VCMethodInfo *> *methods = isClassMethod ? (classInfo.classMethods ?: @[]) : (classInfo.instanceMethods ?: @[]);
    for (VCMethodInfo *methodInfo in methods) {
        if ([methodInfo.selector isEqualToString:selector]) {
            return methodInfo;
        }
    }
    return nil;
}

+ (id)_instanceForRecord:(VCInstanceRecord *)record {
    if (!record) return nil;
    if (record.instance) return record.instance;
    return nil;
}

+ (VCInstanceRecord *)_resolveInstanceRecordForClassName:(NSString *)className
                                                 address:(uintptr_t)address
                                            errorMessage:(NSString **)errorMessage {
    if (address > 0) {
        UIView *selectedView = [[VCUIInspector shared] viewForAddress:address];
        if (selectedView && (className.length == 0 || [NSStringFromClass([selectedView class]) isEqualToString:className])) {
            VCInstanceRecord *viewRecord = [VCInstanceRecord new];
            viewRecord.className = NSStringFromClass([selectedView class]) ?: className ?: @"UIView";
            viewRecord.address = address;
            viewRecord.instance = selectedView;
            viewRecord.discoveredAt = [NSDate date];
            viewRecord.briefDescription = VCAISafeObjectDescription(selectedView, 220);
            return viewRecord;
        }
    }

    if (className.length == 0) {
        if (errorMessage) *errorMessage = @"Object inspection requires className unless the address belongs to a live selected UIView.";
        return nil;
    }

    NSArray<VCInstanceRecord *> *matches = [VCInstanceScanner scanInstancesOfClass:className] ?: @[];
    if (address > 0) {
        for (VCInstanceRecord *record in matches) {
            if (record.address == address) return record;
        }
        if (errorMessage) *errorMessage = [NSString stringWithFormat:@"No live %@ instance matched %@", className, VCAIHexAddress(address)];
        return nil;
    }

    if (matches.count == 1) {
        return matches.firstObject;
    }

    if (errorMessage) {
        *errorMessage = matches.count > 1
            ? [NSString stringWithFormat:@"Found %lu live %@ instances. Provide instanceAddress to inspect one.", (unsigned long)matches.count, className]
            : [NSString stringWithFormat:@"No live %@ instances were found", className];
    }
    return nil;
}

+ (NSDictionary *)_objectReferencePayloadForObject:(id)object {
    if (!object) return @{
        @"isNil": @YES,
        @"address": @"",
        @"className": @"",
        @"moduleName": @"",
        @"briefDescription": @"nil"
    };

    NSString *className = NSStringFromClass([object class]) ?: @"NSObject";
    VCClassInfo *classInfo = [[VCRuntimeEngine shared] classInfoForName:className];
    NSString *blockedReason = [VCPromptLeakGuard blockedToolReasonForClassName:classInfo.className ?: className
                                                                     moduleName:classInfo.moduleName];
    if (blockedReason.length > 0) {
        return @{
            @"redacted": @YES,
            @"address": @"",
            @"className": @"",
            @"moduleName": @"",
            @"briefDescription": @"[redacted]"
        };
    }

    return @{
        @"isNil": @NO,
        @"address": VCAIHexAddress((uintptr_t)(__bridge void *)object),
        @"className": className,
        @"moduleName": classInfo.moduleName ?: @"",
        @"briefDescription": VCAISafeObjectDescription(object, 200)
    };
}

+ (BOOL)_shouldExpandCollectionsForObject:(id)object {
    if (!object) return NO;
    return [object isKindOfClass:[NSArray class]]
        || [object isKindOfClass:[NSOrderedSet class]]
        || [object isKindOfClass:[NSSet class]]
        || [object isKindOfClass:[NSDictionary class]];
}

+ (NSArray<NSDictionary *> *)_collectionReferenceEntriesForObject:(id)object
                                                         maxItems:(NSUInteger)maxItems {
    if (![self _shouldExpandCollectionsForObject:object] || maxItems == 0) return @[];

    NSMutableArray<NSDictionary *> *items = [NSMutableArray new];
    if ([object isKindOfClass:[NSArray class]]) {
        NSArray *array = (NSArray *)object;
        for (NSUInteger idx = 0; idx < MIN(array.count, maxItems); idx++) {
            id child = array[idx];
            if (!child) continue;
            [items addObject:@{
                @"label": [NSString stringWithFormat:@"[%lu]", (unsigned long)idx],
                @"child": child
            }];
        }
        return [items copy];
    }

    if ([object isKindOfClass:[NSOrderedSet class]]) {
        NSOrderedSet *orderedSet = (NSOrderedSet *)object;
        for (NSUInteger idx = 0; idx < MIN(orderedSet.count, maxItems); idx++) {
            id child = [orderedSet objectAtIndex:idx];
            if (!child) continue;
            [items addObject:@{
                @"label": [NSString stringWithFormat:@"[%lu]", (unsigned long)idx],
                @"child": child
            }];
        }
        return [items copy];
    }

    if ([object isKindOfClass:[NSSet class]]) {
        NSUInteger idx = 0;
        for (id child in (NSSet *)object) {
            if (!child) continue;
            [items addObject:@{
                @"label": [NSString stringWithFormat:@"member%lu", (unsigned long)idx],
                @"child": child
            }];
            idx++;
            if (idx >= maxItems) break;
        }
        return [items copy];
    }

    if ([object isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dictionary = (NSDictionary *)object;
        NSArray *keys = [[dictionary allKeys] sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
            return [VCAISafeObjectDescription(a, 80) compare:VCAISafeObjectDescription(b, 80)];
        }];
        for (NSUInteger idx = 0; idx < MIN(keys.count, maxItems); idx++) {
            id key = keys[idx];
            id child = dictionary[key];
            if (!child) continue;
            NSString *label = [NSString stringWithFormat:@"[%@]", VCAITruncatedString(VCAISafeObjectDescription(key, 36), 36)];
            [items addObject:@{
                @"label": label,
                @"child": child
            }];
        }
        return [items copy];
    }

    return @[];
}

+ (NSDictionary *)_ivarPayloadForIvar:(VCIvarInfo *)ivar
                             instance:(id)instance
                 includeObjectReference:(BOOL)includeObjectReference {
    if (!ivar || !instance) return @{};

    id rawValue = [VCValueReader readIvar:ivar fromInstance:instance];
    NSString *valueDescription = @"";
    if ([rawValue isKindOfClass:[NSString class]]) {
        BOOL didSanitize = NO;
        NSString *sanitized = [VCPromptLeakGuard sanitizedAssistantText:rawValue didSanitize:&didSanitize];
        valueDescription = VCAITruncatedString(didSanitize ? @"[redacted]" : sanitized, 220);
    } else if ([rawValue respondsToSelector:@selector(description)]) {
        valueDescription = VCAITruncatedString([[rawValue description] copy] ?: @"", 220);
    }

    NSMutableDictionary *payload = [@{
        @"name": ivar.name ?: @"",
        @"typeEncoding": ivar.typeEncoding ?: @"",
        @"decodedType": ivar.decodedType ?: @"",
        @"offset": @(ivar.offset),
        @"valueDescription": valueDescription ?: @""
    } mutableCopy];

    if (includeObjectReference && [ivar.typeEncoding hasPrefix:@"@"]) {
        @try {
            Ivar runtimeIvar = class_getInstanceVariable(object_getClass(instance), [ivar.name UTF8String]);
            id objectValue = runtimeIvar ? object_getIvar(instance, runtimeIvar) : nil;
            payload[@"objectValue"] = [self _objectReferencePayloadForObject:objectValue];
        } @catch (NSException *exception) {
            payload[@"objectValue"] = @{
                @"error": VCAITruncatedString(exception.reason ?: exception.name ?: @"object_getIvar failed", 180)
            };
        }
    }

    return [payload copy];
}

+ (NSDictionary *)_instanceSummaryPayloadForRecord:(VCInstanceRecord *)record
                                         classInfo:(VCClassInfo *)classInfo {
    id instance = [self _instanceForRecord:record];
    return @{
        @"className": record.className ?: classInfo.className ?: @"",
        @"moduleName": classInfo.moduleName ?: @"",
        @"address": VCAIHexAddress(record.address),
        @"superClassName": classInfo.superClassName ?: @"",
        @"briefDescription": instance ? VCAISafeObjectDescription(instance, 240) : VCAITruncatedString(record.briefDescription ?: @"", 240),
        @"discoveredAt": record.discoveredAt ? @([record.discoveredAt timeIntervalSince1970]) : @0
    };
}

+ (NSDictionary *)_instanceDetailPayloadForRecord:(VCInstanceRecord *)record
                                        classInfo:(VCClassInfo *)classInfo
                                        ivarLimit:(NSUInteger)ivarLimit {
    id instance = [self _instanceForRecord:record];
    NSMutableArray<NSDictionary *> *ivarPayload = [NSMutableArray new];
    NSArray<VCIvarInfo *> *ivars = classInfo.ivars ?: @[];
    for (VCIvarInfo *ivarInfo in [ivars subarrayWithRange:NSMakeRange(0, MIN(ivars.count, ivarLimit))]) {
        [ivarPayload addObject:[self _ivarPayloadForIvar:ivarInfo instance:instance includeObjectReference:YES]];
    }

    NSMutableArray<NSDictionary *> *propertyPayload = [NSMutableArray new];
    for (VCPropertyInfo *propertyInfo in [classInfo.properties subarrayWithRange:NSMakeRange(0, MIN(classInfo.properties.count, ivarLimit))]) {
        [propertyPayload addObject:@{
            @"name": propertyInfo.name ?: @"",
            @"type": propertyInfo.type ?: @"",
            @"getter": propertyInfo.getter ?: @"",
            @"setter": propertyInfo.setter ?: @"",
            @"ivarName": propertyInfo.ivarName ?: @"",
            @"readonly": @(propertyInfo.isReadonly)
        }];
    }

    return @{
        @"instance": [self _instanceSummaryPayloadForRecord:record classInfo:classInfo],
        @"counts": @{
            @"ivars": @(ivars.count),
            @"properties": @(classInfo.properties.count)
        },
        @"ivars": ivarPayload,
        @"properties": propertyPayload,
        @"ivarLimit": @(ivarLimit),
        @"hasMoreIvars": @(ivars.count > ivarLimit)
    };
}

+ (NSString *)_objectGraphMermaidForNodes:(NSArray<NSDictionary *> *)nodes
                                    edges:(NSArray<NSDictionary *> *)edges {
    NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithObject:@"flowchart TD"];
    for (NSDictionary *node in nodes ?: @[]) {
        NSString *nodeID = node[@"nodeID"] ?: @"N0";
        NSString *label = [NSString stringWithFormat:@"%@\n%@",
                           node[@"className"] ?: @"Object",
                           node[@"address"] ?: @""];
        [lines addObject:[NSString stringWithFormat:@"    %@[\"%@\"]", nodeID, VCAIMermaidEscapedLabel(label)]];
    }
    for (NSDictionary *edge in edges ?: @[]) {
        NSString *fromNodeID = edge[@"fromNodeID"] ?: @"";
        NSString *toNodeID = edge[@"toNodeID"] ?: @"";
        if (fromNodeID.length == 0 || toNodeID.length == 0) continue;
        NSString *label = edge[@"label"] ?: @"ref";
        [lines addObject:[NSString stringWithFormat:@"    %@ -- \"%@\" --> %@",
                          fromNodeID,
                          VCAIMermaidEscapedLabel(label),
                          toNodeID]];
    }
    return [lines componentsJoinedByString:@"\n"];
}

+ (NSDictionary *)_objectGraphNodePayloadForObject:(id)object
                                          nodeID:(NSString *)nodeID
                                           depth:(NSUInteger)depth
                                       classInfo:(VCClassInfo *)classInfo {
    NSString *className = NSStringFromClass([object class]) ?: @"NSObject";
    NSMutableDictionary *payload = [@{
        @"nodeID": nodeID ?: @"N0",
        @"address": VCAIHexAddress((uintptr_t)(__bridge void *)object),
        @"className": className,
        @"moduleName": classInfo.moduleName ?: @"",
        @"briefDescription": VCAISafeObjectDescription(object, 160),
        @"depth": @(depth)
    } mutableCopy];

    if ([self _shouldExpandCollectionsForObject:object]) {
        NSUInteger count = 0;
        if ([object respondsToSelector:@selector(count)]) {
            count = (NSUInteger)[object count];
        }
        payload[@"collectionCount"] = @(count);
    }
    return [payload copy];
}

+ (NSDictionary *)_objectGraphPayloadForRecord:(VCInstanceRecord *)record
                                     classInfo:(VCClassInfo *)classInfo
                                      maxDepth:(NSUInteger)maxDepth
                                     nodeLimit:(NSUInteger)nodeLimit
                               collectionLimit:(NSUInteger)collectionLimit {
    id rootInstance = [self _instanceForRecord:record];
    if (!rootInstance) {
        return @{
            @"error": @"The live instance is no longer available."
        };
    }

    NSMutableArray<NSDictionary *> *nodes = [NSMutableArray new];
    NSMutableArray<NSDictionary *> *edges = [NSMutableArray new];
    NSMutableArray<NSDictionary *> *queue = [NSMutableArray new];
    NSMutableDictionary<NSString *, NSString *> *nodeIDs = [NSMutableDictionary new];

    uintptr_t rootAddress = (uintptr_t)(__bridge void *)rootInstance;
    NSString *rootKey = VCAIHexAddress(rootAddress);
    nodeIDs[rootKey] = @"N0";
    [nodes addObject:[self _objectGraphNodePayloadForObject:rootInstance nodeID:@"N0" depth:0 classInfo:classInfo]];
    [queue addObject:@{
        @"instance": rootInstance,
        @"classInfo": classInfo ?: [NSNull null],
        @"depth": @0,
        @"nodeID": @"N0",
        @"address": rootKey
    }];

    NSUInteger cursor = 0;
    while (cursor < queue.count && nodes.count < nodeLimit) {
        NSDictionary *entry = queue[cursor++];
        id instance = entry[@"instance"];
        VCClassInfo *currentClassInfo = [entry[@"classInfo"] isKindOfClass:[VCClassInfo class]] ? entry[@"classInfo"] : nil;
        if (!currentClassInfo) {
            currentClassInfo = [[VCRuntimeEngine shared] classInfoForName:NSStringFromClass([instance class])];
        }
        NSUInteger depth = [entry[@"depth"] unsignedIntegerValue];
        NSString *fromNodeID = entry[@"nodeID"] ?: @"";
        NSString *fromAddress = entry[@"address"] ?: @"";
        if (depth >= maxDepth || !instance || fromNodeID.length == 0) continue;

        NSMutableArray<NSDictionary *> *references = [NSMutableArray new];
        if ([self _shouldExpandCollectionsForObject:instance]) {
            [references addObjectsFromArray:[self _collectionReferenceEntriesForObject:instance maxItems:collectionLimit]];
        } else {
            for (VCIvarInfo *ivarInfo in currentClassInfo.ivars ?: @[]) {
                if (![ivarInfo.typeEncoding hasPrefix:@"@"]) continue;
                id child = nil;
                @try {
                    Ivar runtimeIvar = class_getInstanceVariable(object_getClass(instance), [ivarInfo.name UTF8String]);
                    if (!runtimeIvar) continue;
                    child = object_getIvar(instance, runtimeIvar);
                } @catch (NSException *exception) {
                    continue;
                }
                if (!child) continue;
                [references addObject:@{
                    @"label": ivarInfo.name ?: @"ivar",
                    @"child": child
                }];
            }
        }

        for (NSDictionary *reference in references) {
            id child = reference[@"child"];
            if (!child) continue;

            NSString *childClassName = NSStringFromClass([child class]) ?: @"NSObject";
            VCClassInfo *childClassInfo = [[VCRuntimeEngine shared] classInfoForName:childClassName];
            NSString *blockedReason = [VCPromptLeakGuard blockedToolReasonForClassName:childClassInfo.className ?: childClassName
                                                                             moduleName:childClassInfo.moduleName];
            if (blockedReason.length > 0) continue;

            uintptr_t childAddress = (uintptr_t)(__bridge void *)child;
            NSString *childKey = VCAIHexAddress(childAddress);
            NSString *childNodeID = nodeIDs[childKey];
            BOOL isNewNode = NO;
            if (childNodeID.length == 0) {
                if (nodes.count >= nodeLimit) break;
                childNodeID = [NSString stringWithFormat:@"N%lu", (unsigned long)nodes.count];
                nodeIDs[childKey] = childNodeID;
                [nodes addObject:[self _objectGraphNodePayloadForObject:child nodeID:childNodeID depth:(depth + 1) classInfo:childClassInfo]];
                isNewNode = YES;
            }

            [edges addObject:@{
                @"fromNodeID": fromNodeID,
                @"toNodeID": childNodeID,
                @"fromAddress": fromAddress,
                @"toAddress": childKey,
                @"label": reference[@"label"] ?: @"ref"
            }];

            if (isNewNode && depth + 1 < maxDepth) {
                [queue addObject:@{
                    @"instance": child,
                    @"classInfo": childClassInfo ?: [NSNull null],
                    @"depth": @(depth + 1),
                    @"nodeID": childNodeID,
                    @"address": childKey
                }];
            }
        }
    }

    NSString *mermaid = [self _objectGraphMermaidForNodes:nodes edges:edges];
    return @{
        @"root": [self _instanceSummaryPayloadForRecord:record classInfo:classInfo],
        @"nodes": nodes,
        @"edges": edges,
        @"nodeLimit": @(nodeLimit),
        @"maxDepth": @(maxDepth),
        @"collectionLimit": @(collectionLimit),
        @"truncated": @(nodes.count >= nodeLimit),
        @"mermaid": mermaid ?: @""
    };
}

+ (NSDictionary *)_executeRuntimeQuery:(VCToolCall *)toolCall {
    NSDictionary *params = toolCall.params ?: @{};
    NSString *queryType = [VCAIStringParam(params, @[@"queryType", @"query_type", @"mode"]) lowercaseString];
    if (queryType.length == 0) queryType = @"class_search";

    if ([queryType isEqualToString:@"class_search"]) {
        NSString *filter = VCAIStringParam(params, @[@"filter", @"pattern", @"query"]);
        NSString *module = VCAIStringParam(params, @[@"module", @"moduleName", @"module_name"]);
        NSUInteger offset = VCAIUnsignedParam(params, @[@"offset"], 0, 5000);
        NSUInteger limit = VCAIUnsignedParam(params, @[@"limit", @"pageSize", @"page_size"], 25, 100);
        NSArray<VCClassInfo *> *classes = [[VCRuntimeEngine shared] allClassesFilteredBy:(filter.length > 0 ? filter : nil)
                                                                                   module:(module.length > 0 ? module : nil)
                                                                                   offset:offset
                                                                                    limit:limit];
        NSMutableArray<NSDictionary *> *items = [NSMutableArray new];
        for (VCClassInfo *classInfo in classes) {
            if ([VCPromptLeakGuard blockedToolReasonForClassName:classInfo.className moduleName:classInfo.moduleName].length > 0) {
                continue;
            }
            [items addObject:@{
                @"className": classInfo.className ?: @"",
                @"moduleName": classInfo.moduleName ?: @"",
                @"superClassName": classInfo.superClassName ?: @""
            }];
        }
        NSDictionary *payload = @{
            @"queryType": queryType,
            @"filter": filter ?: @"",
            @"module": module ?: @"",
            @"offset": @(offset),
            @"limit": @(limit),
            @"returnedCount": @(items.count),
            @"hasMore": @(items.count >= limit),
            @"totalClasses": @([[VCRuntimeEngine shared] totalClassCount]),
            @"classes": items
        };
        NSString *summary = items.count > 0
            ? [NSString stringWithFormat:@"Found %lu runtime classes%@", (unsigned long)items.count, filter.length > 0 ? [NSString stringWithFormat:@" matching \"%@\"", filter] : @""]
            : @"No runtime classes matched the query";
        return VCAISuccessResult(toolCall, summary, payload, nil);
    }

    if ([queryType isEqualToString:@"class_detail"]) {
        NSString *className = VCAIStringParam(params, @[@"className", @"class", @"target"]);
        if (className.length == 0) return VCAIErrorResult(toolCall, @"query_runtime class_detail requires className");

        VCClassInfo *classInfo = [[VCRuntimeEngine shared] classInfoForName:className];
        if (!classInfo) return VCAIErrorResult(toolCall, [NSString stringWithFormat:@"Class %@ was not found", className]);
        NSString *blockedReason = [VCPromptLeakGuard blockedToolReasonForClassName:classInfo.className moduleName:classInfo.moduleName];
        if (blockedReason.length > 0) return VCAIErrorResult(toolCall, blockedReason);

        NSString *memberFilter = [VCAIStringParam(params, @[@"memberFilter", @"member_filter", @"filter", @"query"]) lowercaseString];
        NSUInteger memberLimit = VCAIUnsignedParam(params, @[@"limit", @"memberLimit", @"member_limit"], 40, 120);

        NSArray<VCMethodInfo *> *instanceMethods = classInfo.instanceMethods ?: @[];
        NSArray<VCMethodInfo *> *classMethods = classInfo.classMethods ?: @[];
        NSArray<VCIvarInfo *> *ivars = classInfo.ivars ?: @[];
        NSArray<VCPropertyInfo *> *properties = classInfo.properties ?: @[];

        if (memberFilter.length > 0) {
            NSPredicate *methodPredicate = [NSPredicate predicateWithBlock:^BOOL(VCMethodInfo *evaluated, NSDictionary<NSString *,id> *bindings) {
                NSString *candidate = [NSString stringWithFormat:@"%@ %@ %@", evaluated.selector ?: @"", evaluated.decodedSignature ?: @"", evaluated.typeEncoding ?: @""].lowercaseString;
                return [candidate containsString:memberFilter];
            }];
            NSPredicate *ivarPredicate = [NSPredicate predicateWithBlock:^BOOL(VCIvarInfo *evaluated, NSDictionary<NSString *,id> *bindings) {
                NSString *candidate = [NSString stringWithFormat:@"%@ %@ %@", evaluated.name ?: @"", evaluated.decodedType ?: @"", evaluated.typeEncoding ?: @""].lowercaseString;
                return [candidate containsString:memberFilter];
            }];
            NSPredicate *propertyPredicate = [NSPredicate predicateWithBlock:^BOOL(VCPropertyInfo *evaluated, NSDictionary<NSString *,id> *bindings) {
                NSString *candidate = [NSString stringWithFormat:@"%@ %@ %@ %@", evaluated.name ?: @"", evaluated.type ?: @"", evaluated.getter ?: @"", evaluated.setter ?: @""].lowercaseString;
                return [candidate containsString:memberFilter];
            }];
            instanceMethods = [instanceMethods filteredArrayUsingPredicate:methodPredicate];
            classMethods = [classMethods filteredArrayUsingPredicate:methodPredicate];
            ivars = [ivars filteredArrayUsingPredicate:ivarPredicate];
            properties = [properties filteredArrayUsingPredicate:propertyPredicate];
        }

        NSMutableArray<NSDictionary *> *instanceMethodPayload = [NSMutableArray new];
        for (VCMethodInfo *methodInfo in [instanceMethods subarrayWithRange:NSMakeRange(0, MIN(instanceMethods.count, memberLimit))]) {
            [instanceMethodPayload addObject:@{
                @"selector": methodInfo.selector ?: @"",
                @"signature": methodInfo.decodedSignature ?: methodInfo.typeEncoding ?: @"",
                @"typeEncoding": methodInfo.typeEncoding ?: @"",
                @"impAddress": VCAIHexAddress(methodInfo.impAddress),
                @"rva": VCAIHexAddress(methodInfo.rva)
            }];
        }

        NSMutableArray<NSDictionary *> *classMethodPayload = [NSMutableArray new];
        for (VCMethodInfo *methodInfo in [classMethods subarrayWithRange:NSMakeRange(0, MIN(classMethods.count, memberLimit))]) {
            [classMethodPayload addObject:@{
                @"selector": methodInfo.selector ?: @"",
                @"signature": methodInfo.decodedSignature ?: methodInfo.typeEncoding ?: @"",
                @"typeEncoding": methodInfo.typeEncoding ?: @"",
                @"impAddress": VCAIHexAddress(methodInfo.impAddress),
                @"rva": VCAIHexAddress(methodInfo.rva)
            }];
        }

        NSMutableArray<NSDictionary *> *ivarPayload = [NSMutableArray new];
        for (VCIvarInfo *ivarInfo in [ivars subarrayWithRange:NSMakeRange(0, MIN(ivars.count, memberLimit))]) {
            [ivarPayload addObject:@{
                @"name": ivarInfo.name ?: @"",
                @"typeEncoding": ivarInfo.typeEncoding ?: @"",
                @"decodedType": ivarInfo.decodedType ?: @"",
                @"offset": @(ivarInfo.offset)
            }];
        }

        NSMutableArray<NSDictionary *> *propertyPayload = [NSMutableArray new];
        for (VCPropertyInfo *propertyInfo in [properties subarrayWithRange:NSMakeRange(0, MIN(properties.count, memberLimit))]) {
            [propertyPayload addObject:@{
                @"name": propertyInfo.name ?: @"",
                @"type": propertyInfo.type ?: @"",
                @"attributes": propertyInfo.attributes ?: @"",
                @"getter": propertyInfo.getter ?: @"",
                @"setter": propertyInfo.setter ?: @"",
                @"ivarName": propertyInfo.ivarName ?: @"",
                @"readonly": @(propertyInfo.isReadonly),
                @"weak": @(propertyInfo.isWeak),
                @"nonatomic": @(propertyInfo.isNonatomic)
            }];
        }

        NSDictionary *payload = @{
            @"queryType": queryType,
            @"className": classInfo.className ?: @"",
            @"moduleName": classInfo.moduleName ?: @"",
            @"superClassName": classInfo.superClassName ?: @"",
            @"inheritanceChain": classInfo.inheritanceChain ?: @[],
            @"protocols": classInfo.protocols ?: @[],
            @"counts": @{
                @"instanceMethods": @(instanceMethods.count),
                @"classMethods": @(classMethods.count),
                @"ivars": @(ivars.count),
                @"properties": @(properties.count)
            },
            @"instanceMethods": instanceMethodPayload,
            @"classMethods": classMethodPayload,
            @"ivars": ivarPayload,
            @"properties": propertyPayload,
            @"memberFilter": memberFilter ?: @"",
            @"memberLimit": @(memberLimit)
        };
        NSString *summary = [NSString stringWithFormat:@"Loaded runtime detail for %@ (%lu instance methods, %lu ivars)",
                             classInfo.className ?: className,
                             (unsigned long)instanceMethods.count,
                             (unsigned long)ivars.count];
        return VCAISuccessResult(toolCall, summary, payload, nil);
    }

    if ([queryType isEqualToString:@"method_detail"]) {
        NSString *className = VCAIStringParam(params, @[@"className", @"class", @"target"]);
        NSString *selector = VCAIStringParam(params, @[@"selector", @"method", @"sel"]);
        if (className.length == 0 || selector.length == 0) {
            return VCAIErrorResult(toolCall, @"query_runtime method_detail requires className and selector");
        }

        VCClassInfo *classInfo = [[VCRuntimeEngine shared] classInfoForName:className];
        if (!classInfo) return VCAIErrorResult(toolCall, [NSString stringWithFormat:@"Class %@ was not found", className]);
        NSString *blockedReason = [VCPromptLeakGuard blockedToolReasonForClassName:classInfo.className moduleName:classInfo.moduleName];
        if (blockedReason.length > 0) return VCAIErrorResult(toolCall, blockedReason);

        id classMethodFlag = params[@"isClassMethod"] ?: params[@"classMethod"] ?: params[@"is_class_method"];
        BOOL resolvedClassMethod = classMethodFlag ? [classMethodFlag boolValue] : NO;
        VCMethodInfo *methodInfo = nil;
        if (classMethodFlag) {
            methodInfo = [self _methodInfoForClassInfo:classInfo selector:selector isClassMethod:resolvedClassMethod];
        } else {
            methodInfo = [self _methodInfoForClassInfo:classInfo selector:selector isClassMethod:NO];
            if (!methodInfo) {
                methodInfo = [self _methodInfoForClassInfo:classInfo selector:selector isClassMethod:YES];
                resolvedClassMethod = (methodInfo != nil);
            }
        }
        if (!methodInfo) {
            return VCAIErrorResult(toolCall, [NSString stringWithFormat:@"%@ does not implement %@", className, selector]);
        }

        NSDictionary *payload = @{
            @"queryType": queryType,
            @"className": classInfo.className ?: className,
            @"moduleName": classInfo.moduleName ?: @"",
            @"superClassName": classInfo.superClassName ?: @"",
            @"selector": methodInfo.selector ?: selector,
            @"isClassMethod": @(resolvedClassMethod),
            @"signature": methodInfo.decodedSignature ?: methodInfo.typeEncoding ?: @"",
            @"typeEncoding": methodInfo.typeEncoding ?: @"",
            @"impAddress": VCAIHexAddress(methodInfo.impAddress),
            @"rva": VCAIHexAddress(methodInfo.rva)
        };
        NSString *summary = [NSString stringWithFormat:@"Loaded runtime detail for %@ %@%@",
                             classInfo.className ?: className,
                             resolvedClassMethod ? @"+" : @"-",
                             selector];
        return VCAISuccessResult(toolCall, summary, payload, nil);
    }

    if ([queryType isEqualToString:@"strings_search"]) {
        NSString *pattern = VCAIStringParam(params, @[@"pattern", @"filter", @"query"]);
        if (pattern.length == 0) return VCAIErrorResult(toolCall, @"query_runtime strings_search requires pattern");

        NSString *module = VCAIStringParam(params, @[@"module", @"moduleName", @"module_name"]);
        NSString *blockedReason = [VCPromptLeakGuard blockedToolReasonForStringPattern:pattern moduleName:module];
        if (blockedReason.length > 0) return VCAIErrorResult(toolCall, blockedReason);
        NSUInteger limit = VCAIUnsignedParam(params, @[@"limit"], 20, 100);
        NSArray<VCStringResult *> *matches = [VCStringScanner scanStringsMatching:pattern inModule:(module.length > 0 ? module : nil)] ?: @[];

        NSMutableArray<NSDictionary *> *items = [NSMutableArray new];
        for (VCStringResult *result in matches) {
            if ([VCPromptLeakGuard blockedToolReasonForModuleName:result.moduleName].length > 0) {
                continue;
            }
            BOOL didSanitize = NO;
            NSString *safeValue = [VCPromptLeakGuard sanitizedAssistantText:(result.value ?: @"") didSanitize:&didSanitize];
            [items addObject:@{
                @"value": VCAITruncatedString(didSanitize ? @"[redacted]" : safeValue, 200),
                @"section": result.section ?: @"",
                @"moduleName": result.moduleName ?: @"",
                @"address": VCAIHexAddress(result.address),
                @"rva": VCAIHexAddress(result.rva)
            }];
            if (items.count >= limit) break;
        }
        NSDictionary *payload = @{
            @"queryType": queryType,
            @"pattern": pattern,
            @"module": module ?: @"",
            @"returnedCount": @(items.count),
            @"totalMatches": @(matches.count),
            @"matches": items
        };
        NSString *summary = items.count > 0
            ? [NSString stringWithFormat:@"Found %lu strings matching \"%@\"", (unsigned long)matches.count, pattern]
            : [NSString stringWithFormat:@"No strings matched \"%@\"", pattern];
        return VCAISuccessResult(toolCall, summary, payload, nil);
    }

    if ([queryType isEqualToString:@"instances_search"]) {
        NSString *className = VCAIStringParam(params, @[@"className", @"class", @"target"]);
        if (className.length == 0) return VCAIErrorResult(toolCall, @"query_runtime instances_search requires className");
        VCClassInfo *classInfo = [[VCRuntimeEngine shared] classInfoForName:className];
        NSString *blockedReason = [VCPromptLeakGuard blockedToolReasonForClassName:classInfo.className ?: className
                                                                         moduleName:classInfo.moduleName];
        if (blockedReason.length > 0) return VCAIErrorResult(toolCall, blockedReason);

        NSUInteger limit = VCAIUnsignedParam(params, @[@"limit"], 20, 100);
        NSArray<VCInstanceRecord *> *matches = [VCInstanceScanner scanInstancesOfClass:className] ?: @[];

        NSMutableArray<NSDictionary *> *items = [NSMutableArray new];
        for (VCInstanceRecord *record in [matches subarrayWithRange:NSMakeRange(0, MIN(matches.count, limit))]) {
            [items addObject:@{
                @"className": record.className ?: className,
                @"address": VCAIHexAddress(record.address),
                @"briefDescription": VCAITruncatedString(record.briefDescription ?: @"", 240),
                @"discoveredAt": @([record.discoveredAt timeIntervalSince1970])
            }];
        }
        NSDictionary *payload = @{
            @"queryType": queryType,
            @"className": className,
            @"returnedCount": @(items.count),
            @"totalMatches": @(matches.count),
            @"instances": items
        };
        NSString *summary = items.count > 0
            ? [NSString stringWithFormat:@"Found %lu live %@ instances", (unsigned long)matches.count, className]
            : [NSString stringWithFormat:@"No live %@ instances were found", className];
        return VCAISuccessResult(toolCall, summary, payload, nil);
    }

    if ([queryType isEqualToString:@"instance_detail"] || [queryType isEqualToString:@"dump_object"]) {
        NSString *className = VCAIStringParam(params, @[@"className", @"class", @"target"]);
        uintptr_t instanceAddress = VCAIAddressParam(params, @[@"instanceAddress", @"instance_address", @"address", @"objectAddress"]);
        NSString *resolveError = nil;
        VCInstanceRecord *record = [self _resolveInstanceRecordForClassName:className address:instanceAddress errorMessage:&resolveError];
        if (!record) return VCAIErrorResult(toolCall, resolveError ?: @"Object instance could not be resolved");

        VCClassInfo *classInfo = [[VCRuntimeEngine shared] classInfoForName:record.className ?: className];
        NSString *blockedReason = [VCPromptLeakGuard blockedToolReasonForClassName:classInfo.className ?: record.className
                                                                         moduleName:classInfo.moduleName];
        if (blockedReason.length > 0) return VCAIErrorResult(toolCall, blockedReason);
        if (![self _instanceForRecord:record]) return VCAIErrorResult(toolCall, @"The live instance is no longer available");

        NSUInteger ivarLimit = VCAIUnsignedParam(params, @[@"limit", @"ivarLimit", @"ivar_limit"], 24, 80);
        NSMutableDictionary *payload = [[self _instanceDetailPayloadForRecord:record classInfo:classInfo ivarLimit:ivarLimit] mutableCopy];
        payload[@"queryType"] = queryType;
        NSString *summary = [NSString stringWithFormat:@"Loaded %@ detail for %@ at %@",
                             queryType,
                             record.className ?: className,
                             VCAIHexAddress(record.address)];
        return VCAISuccessResult(toolCall, summary, [payload copy], nil);
    }

    if ([queryType isEqualToString:@"read_ivar"]) {
        NSString *className = VCAIStringParam(params, @[@"className", @"class", @"target"]);
        uintptr_t instanceAddress = VCAIAddressParam(params, @[@"instanceAddress", @"instance_address", @"address", @"objectAddress"]);
        NSString *ivarName = VCAIStringParam(params, @[@"ivarName", @"ivar", @"name"]);
        if (ivarName.length == 0) return VCAIErrorResult(toolCall, @"query_runtime read_ivar requires ivarName");

        NSString *resolveError = nil;
        VCInstanceRecord *record = [self _resolveInstanceRecordForClassName:className address:instanceAddress errorMessage:&resolveError];
        if (!record) return VCAIErrorResult(toolCall, resolveError ?: @"Object instance could not be resolved");

        VCClassInfo *classInfo = [[VCRuntimeEngine shared] classInfoForName:record.className ?: className];
        NSString *blockedReason = [VCPromptLeakGuard blockedToolReasonForClassName:classInfo.className ?: record.className
                                                                         moduleName:classInfo.moduleName];
        if (blockedReason.length > 0) return VCAIErrorResult(toolCall, blockedReason);
        id instance = [self _instanceForRecord:record];
        if (!instance) return VCAIErrorResult(toolCall, @"The live instance is no longer available");

        VCIvarInfo *matchedIvar = nil;
        for (VCIvarInfo *ivarInfo in classInfo.ivars ?: @[]) {
            if ([ivarInfo.name isEqualToString:ivarName]) {
                matchedIvar = ivarInfo;
                break;
            }
        }
        if (!matchedIvar) {
            return VCAIErrorResult(toolCall, [NSString stringWithFormat:@"%@ does not define ivar %@", record.className ?: className, ivarName]);
        }

        NSDictionary *payload = @{
            @"queryType": queryType,
            @"instance": [self _instanceSummaryPayloadForRecord:record classInfo:classInfo],
            @"ivar": [self _ivarPayloadForIvar:matchedIvar instance:instance includeObjectReference:YES]
        };
        NSString *summary = [NSString stringWithFormat:@"Read ivar %@ on %@",
                             ivarName,
                             record.className ?: className];
        return VCAISuccessResult(toolCall, summary, payload, nil);
    }

    if ([queryType isEqualToString:@"object_graph"]) {
        NSString *className = VCAIStringParam(params, @[@"className", @"class", @"target"]);
        uintptr_t instanceAddress = VCAIAddressParam(params, @[@"instanceAddress", @"instance_address", @"address", @"objectAddress"]);
        NSString *resolveError = nil;
        VCInstanceRecord *record = [self _resolveInstanceRecordForClassName:className address:instanceAddress errorMessage:&resolveError];
        if (!record) return VCAIErrorResult(toolCall, resolveError ?: @"Object instance could not be resolved");

        VCClassInfo *classInfo = [[VCRuntimeEngine shared] classInfoForName:record.className ?: className];
        NSString *blockedReason = [VCPromptLeakGuard blockedToolReasonForClassName:classInfo.className ?: record.className
                                                                         moduleName:classInfo.moduleName];
        if (blockedReason.length > 0) return VCAIErrorResult(toolCall, blockedReason);

        NSUInteger maxDepth = VCAIUnsignedParam(params, @[@"maxDepth", @"max_depth", @"depth"], 2, 4);
        NSUInteger nodeLimit = VCAIUnsignedParam(params, @[@"limit", @"nodeLimit", @"node_limit"], 16, 40);
        NSUInteger collectionLimit = VCAIUnsignedParam(params, @[@"collectionLimit", @"collection_limit"], 6, 16);
        NSDictionary *graph = [self _objectGraphPayloadForRecord:record
                                                       classInfo:classInfo
                                                        maxDepth:maxDepth
                                                       nodeLimit:nodeLimit
                                                 collectionLimit:collectionLimit];
        if ([graph[@"error"] isKindOfClass:[NSString class]] && [graph[@"error"] length] > 0) {
            return VCAIErrorResult(toolCall, graph[@"error"]);
        }

        NSMutableDictionary *payload = [graph mutableCopy];
        payload[@"queryType"] = queryType;
        NSString *summary = [NSString stringWithFormat:@"Built a conservative object graph for %@ (%lu nodes)",
                             record.className ?: className,
                             (unsigned long)[graph[@"nodes"] count]];
        return VCAISuccessResult(toolCall, summary, [payload copy], nil);
    }

    return VCAIErrorResult(toolCall, [NSString stringWithFormat:@"Unsupported query_runtime queryType: %@", queryType ?: @""]);
}

+ (NSDictionary *)_executeProcessQuery:(VCToolCall *)toolCall {
    NSDictionary *params = toolCall.params ?: @{};
    NSString *queryType = [VCAIStringParam(params, @[@"queryType", @"query_type", @"mode"]) lowercaseString];
    if (queryType.length == 0) queryType = @"basic_info";

    VCProcessInfo *processInfo = [VCProcessInfo shared];

    if ([queryType isEqualToString:@"basic_info"]) {
        NSDictionary *basicInfo = [processInfo basicInfo] ?: @{};
        NSDictionary *payload = @{
            @"queryType": queryType,
            @"basicInfo": basicInfo,
            @"moduleCount": @([[processInfo loadedModules] count])
        };
        NSString *summary = [NSString stringWithFormat:@"Loaded process info for %@",
                             basicInfo[@"bundleID"] ?: [VCConfig shared].targetBundleID ?: @"target process"];
        return VCAISuccessResult(toolCall, summary, payload, nil);
    }

    if ([queryType isEqualToString:@"modules"]) {
        NSString *filter = [VCAIStringParam(params, @[@"filter", @"query", @"pattern"]) lowercaseString];
        NSString *category = [VCAIStringParam(params, @[@"category"]) lowercaseString];
        NSUInteger offset = VCAIUnsignedParam(params, @[@"offset"], 0, 5000);
        NSUInteger limit = VCAIUnsignedParam(params, @[@"limit"], 25, 100);
        NSArray<VCModuleInfo *> *modules = [processInfo loadedModules] ?: @[];

        if (filter.length > 0 || category.length > 0) {
            NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(VCModuleInfo *moduleInfo, NSDictionary<NSString *,id> *bindings) {
                BOOL matchesFilter = YES;
                if (filter.length > 0) {
                    NSString *candidate = [NSString stringWithFormat:@"%@ %@ %@", moduleInfo.name ?: @"", moduleInfo.path ?: @"", moduleInfo.category ?: @""].lowercaseString;
                    matchesFilter = [candidate containsString:filter];
                }
                BOOL matchesCategory = (category.length == 0 || [moduleInfo.category.lowercaseString isEqualToString:category]);
                return matchesFilter && matchesCategory;
            }];
            modules = [modules filteredArrayUsingPredicate:predicate];
        }

        if (offset < modules.count) {
            modules = [modules subarrayWithRange:NSMakeRange(offset, MIN(limit, modules.count - offset))];
        } else {
            modules = @[];
        }

        NSMutableArray<NSDictionary *> *items = [NSMutableArray new];
        for (VCModuleInfo *moduleInfo in modules) {
            if ([VCPromptLeakGuard blockedToolReasonForModuleName:moduleInfo.name].length > 0 ||
                [VCPromptLeakGuard blockedToolReasonForModuleName:moduleInfo.path].length > 0) {
                continue;
            }
            [items addObject:@{
                @"name": moduleInfo.name ?: @"",
                @"path": moduleInfo.path ?: @"",
                @"category": moduleInfo.category ?: @"",
                @"loadAddress": VCAIHexAddress(moduleInfo.loadAddress),
                @"slide": VCAIHexAddress(moduleInfo.slide),
                @"size": @(moduleInfo.size)
            }];
        }
        NSDictionary *payload = @{
            @"queryType": queryType,
            @"filter": filter ?: @"",
            @"category": category ?: @"",
            @"offset": @(offset),
            @"limit": @(limit),
            @"modules": items,
            @"returnedCount": @(items.count)
        };
        NSString *summary = [NSString stringWithFormat:@"Loaded %lu modules", (unsigned long)items.count];
        return VCAISuccessResult(toolCall, summary, payload, nil);
    }

    if ([queryType isEqualToString:@"memory_regions"]) {
        NSArray<VCMemRegion *> *regions = [processInfo memoryRegions] ?: @[];
        uintptr_t address = VCAIAddressParam(params, @[@"address", @"targetAddress", @"target_address"]);
        NSString *protectionFilter = [VCAIStringParam(params, @[@"protection", @"protectionFilter", @"protection_filter"]) lowercaseString];
        NSUInteger limit = VCAIUnsignedParam(params, @[@"limit"], 20, 80);

        NSMutableArray<NSDictionary *> *items = [NSMutableArray new];
        if (address > 0) {
            NSInteger matchIndex = NSNotFound;
            for (NSUInteger idx = 0; idx < regions.count; idx++) {
                VCMemRegion *region = regions[idx];
                if (address >= region.start && address < region.end) {
                    matchIndex = (NSInteger)idx;
                    break;
                }
            }
            if (matchIndex != NSNotFound) {
                NSInteger startIndex = MAX(0, matchIndex - 2);
                NSInteger endIndex = MIN((NSInteger)regions.count - 1, matchIndex + 2);
                for (NSInteger idx = startIndex; idx <= endIndex; idx++) {
                    VCMemRegion *region = regions[idx];
                    NSMutableDictionary *entry = [VCAIMemoryRegionDictionary(region) mutableCopy];
                    entry[@"containsTargetAddress"] = @(address >= region.start && address < region.end);
                    [items addObject:[entry copy]];
                }
            }
        } else {
            for (VCMemRegion *region in regions) {
                if (protectionFilter.length > 0 && ![region.protection.lowercaseString containsString:protectionFilter]) continue;
                [items addObject:VCAIMemoryRegionDictionary(region)];
                if (items.count >= limit) break;
            }
        }

        NSDictionary *payload = @{
            @"queryType": queryType,
            @"address": address > 0 ? VCAIHexAddress(address) : @"",
            @"protectionFilter": protectionFilter ?: @"",
            @"regions": items,
            @"returnedCount": @(items.count),
            @"totalRegions": @(regions.count)
        };
        NSString *summary = address > 0
            ? (items.count > 0 ? [NSString stringWithFormat:@"Located memory region around %@", VCAIHexAddress(address)] : [NSString stringWithFormat:@"No memory region contained %@", VCAIHexAddress(address)])
            : [NSString stringWithFormat:@"Loaded %lu memory regions", (unsigned long)items.count];
        return VCAISuccessResult(toolCall, summary, payload, nil);
    }

    if ([queryType isEqualToString:@"entitlements"]) {
        NSDictionary *payload = @{
            @"queryType": queryType,
            @"entitlements": [processInfo entitlements] ?: @{}
        };
        return VCAISuccessResult(toolCall, @"Loaded process entitlements", payload, nil);
    }

    if ([queryType isEqualToString:@"environment"]) {
        NSDictionary *environment = [processInfo environmentVariables] ?: @{};
        NSUInteger limit = VCAIUnsignedParam(params, @[@"limit"], 40, 120);
        NSArray<NSString *> *keys = [[environment allKeys] sortedArrayUsingSelector:@selector(compare:)];
        NSMutableDictionary *limited = [NSMutableDictionary new];
        for (NSString *key in [keys subarrayWithRange:NSMakeRange(0, MIN(keys.count, limit))]) {
            BOOL wasRedacted = NO;
            NSString *safeValue = [VCPromptLeakGuard sanitizedEnvironmentValueForKey:key
                                                                               value:environment[key]
                                                                         wasRedacted:&wasRedacted];
            limited[key] = VCAITruncatedString(safeValue, 240);
        }
        NSDictionary *payload = @{
            @"queryType": queryType,
            @"returnedCount": @(limited.count),
            @"totalVariables": @(environment.count),
            @"environment": [limited copy]
        };
        return VCAISuccessResult(toolCall, @"Loaded process environment variables", payload, nil);
    }

    return VCAIErrorResult(toolCall, [NSString stringWithFormat:@"Unsupported query_process queryType: %@", queryType ?: @""]);
}

+ (NSDictionary *)_executeUnityRuntimeQuery:(VCToolCall *)toolCall {
    NSDictionary *params = toolCall.params ?: @{};
    NSString *queryType = [VCAIStringParam(params, @[@"queryType", @"query_type", @"mode"]) lowercaseString];
    if (queryType.length == 0) queryType = @"detect";

    VCUnityRuntimeEngine *engine = [VCUnityRuntimeEngine shared];

    if ([queryType isEqualToString:@"detect"]) {
        NSDictionary *payload = [engine detectUnityRuntime] ?: @{};
        BOOL likelyUnity = [payload[@"likelyUnity"] boolValue];
        NSString *runtimeFlavor = VCAITrimmedString(payload[@"runtimeFlavor"]);
        NSString *summary = likelyUnity
            ? [NSString stringWithFormat:@"Detected a likely Unity runtime (%@)", runtimeFlavor.length > 0 ? runtimeFlavor : @"unknown"]
            : @"No strong Unity runtime markers were detected";
        return VCAISuccessResult(toolCall, summary, payload, nil);
    }

    if ([queryType isEqualToString:@"modules"]) {
        NSUInteger limit = VCAIUnsignedParam(params, @[@"limit"], 20, 80);
        NSArray<NSDictionary *> *modules = [engine unityModuleSummariesWithLimit:limit] ?: @[];
        NSDictionary *payload = @{
            @"queryType": queryType,
            @"returnedCount": @(modules.count),
            @"modules": modules
        };
        NSString *summary = modules.count > 0
            ? [NSString stringWithFormat:@"Loaded %lu Unity-related modules", (unsigned long)modules.count]
            : @"No Unity-related modules were found";
        return VCAISuccessResult(toolCall, summary, payload, nil);
    }

    if ([queryType isEqualToString:@"symbols"]) {
        NSArray<NSString *> *symbols = VCAIStringArrayParam(params, @[@"symbols", @"symbolNames", @"symbol_names"]);
        NSString *preferredModule = VCAIStringParam(params, @[@"preferredModule", @"module", @"moduleName"]);
        BOOL includeDefaultSymbols = VCAIBoolParam(params, @[@"includeDefaultSymbols", @"include_defaults"], symbols.count == 0);
        NSDictionary *payload = [engine resolveSymbols:symbols preferredModule:preferredModule includeDefaultSymbols:includeDefaultSymbols] ?: @{};
        NSUInteger resolvedCount = [payload[@"resolvedCount"] respondsToSelector:@selector(unsignedIntegerValue)] ? [payload[@"resolvedCount"] unsignedIntegerValue] : 0;
        NSString *summary = [NSString stringWithFormat:@"Resolved %lu Unity runtime symbols", (unsigned long)resolvedCount];
        return VCAISuccessResult(toolCall, summary, payload, nil);
    }

    if ([queryType isEqualToString:@"icalls"]) {
        NSArray<NSString *> *icallNames = VCAIStringArrayParam(params, @[@"icallNames", @"icalls", @"names"]);
        BOOL includeDefaultICalls = VCAIBoolParam(params, @[@"includeDefaultICalls", @"include_default_icalls"], icallNames.count == 0);
        NSDictionary *payload = [engine resolveICalls:icallNames includeDefaultICalls:includeDefaultICalls] ?: @{};
        NSUInteger resolvedCount = [payload[@"resolvedCount"] respondsToSelector:@selector(unsignedIntegerValue)] ? [payload[@"resolvedCount"] unsignedIntegerValue] : 0;
        NSString *summary = [NSString stringWithFormat:@"Resolved %lu Unity icalls", (unsigned long)resolvedCount];
        return VCAISuccessResult(toolCall, summary, payload, nil);
    }

    if ([queryType isEqualToString:@"drawing_support"]) {
        NSDictionary *payload = [engine drawingSupportSummary] ?: @{};
        BOOL readyForWorldToScreen = [payload[@"canPrepareWorldToScreenBridge"] boolValue];
        BOOL readyForObjectDrawing = [payload[@"canPrepareObjectDrawingBridge"] boolValue];
        NSString *summary = readyForObjectDrawing
            ? @"Unity runtime markers suggest object-drawing prerequisites are mostly present"
            : (readyForWorldToScreen ? @"Unity runtime markers suggest WorldToScreen prerequisites are present" : @"Unity drawing prerequisites are still incomplete");
        return VCAISuccessResult(toolCall, summary, payload, nil);
    }

    if ([queryType isEqualToString:@"camera_main"]) {
        NSDictionary *payload = [engine mainCameraSummary] ?: @{};
        BOOL success = [payload[@"success"] boolValue];
        NSString *summary = success
            ? [NSString stringWithFormat:@"Resolved Unity main camera at %@",
               VCAITrimmedString(payload[@"cameraAddress"]).length > 0 ? payload[@"cameraAddress"] : @"runtime address"]
            : (VCAITrimmedString(payload[@"error"]).length > 0 ? payload[@"error"] : @"Unity main camera could not be resolved");
        return success ? VCAISuccessResult(toolCall, summary, payload, nil) : VCAIErrorResult(toolCall, summary);
    }

    if ([queryType isEqualToString:@"find_by_name"]) {
        NSString *name = VCAIStringParam(params, @[@"name", @"objectName", @"object_name"]);
        NSDictionary *payload = [engine findGameObjectByName:name] ?: @{};
        BOOL success = [payload[@"success"] boolValue];
        NSString *summary = success
            ? [NSString stringWithFormat:@"Resolved Unity GameObject \"%@\"", name]
            : (VCAITrimmedString(payload[@"error"]).length > 0 ? payload[@"error"] : @"Unity object name lookup failed");
        return success ? VCAISuccessResult(toolCall, summary, payload, nil) : VCAIErrorResult(toolCall, summary);
    }

    if ([queryType isEqualToString:@"find_by_tag"]) {
        NSString *tag = VCAIStringParam(params, @[@"tag"]);
        NSUInteger limit = VCAIUnsignedParam(params, @[@"limit"], 12, 64);
        NSDictionary *payload = [engine findGameObjectsByTag:tag limit:limit] ?: @{};
        BOOL success = [payload[@"success"] boolValue];
        NSString *summary = success
            ? [NSString stringWithFormat:@"Resolved %lu Unity objects for tag \"%@\"",
               (unsigned long)[payload[@"returnedCount"] unsignedIntegerValue], tag]
            : (VCAITrimmedString(payload[@"error"]).length > 0 ? payload[@"error"] : @"Unity tag lookup failed");
        return success ? VCAISuccessResult(toolCall, summary, payload, nil) : VCAIErrorResult(toolCall, summary);
    }

    if ([queryType isEqualToString:@"get_component"]) {
        uintptr_t gameObjectAddress = VCAIAddressParam(params, @[@"gameObjectAddress", @"game_object_address"]);
        uintptr_t componentAddress = VCAIAddressParam(params, @[@"componentAddress", @"component_address"]);
        uintptr_t genericAddress = VCAIAddressParam(params, @[@"address"]);
        uintptr_t sourceAddress = gameObjectAddress > 0 ? gameObjectAddress : (componentAddress > 0 ? componentAddress : genericAddress);
        NSString *objectKind = gameObjectAddress > 0 ? @"gameobject" : (componentAddress > 0 ? @"component" : VCAIStringParam(params, @[@"objectKind", @"object_kind", @"kind"]));
        NSString *componentName = VCAIStringParam(params, @[@"componentName", @"component_name", @"name"]);
        NSDictionary *payload = [engine componentForObjectAddress:sourceAddress objectKind:objectKind componentName:componentName] ?: @{};
        BOOL success = [payload[@"success"] boolValue];
        NSString *summary = success
            ? [NSString stringWithFormat:@"Resolved Unity component %@ for %@", componentName, payload[@"objectAddress"] ?: @""]
            : (VCAITrimmedString(payload[@"error"]).length > 0 ? payload[@"error"] : @"Unity component lookup failed");
        return success ? VCAISuccessResult(toolCall, summary, payload, nil) : VCAIErrorResult(toolCall, summary);
    }

    if ([queryType isEqualToString:@"list_renderers"]) {
        NSString *name = VCAIStringParam(params, @[@"name", @"objectName", @"object_name"]);
        NSString *tag = VCAIStringParam(params, @[@"tag"]);
        NSUInteger limit = VCAIUnsignedParam(params, @[@"limit"], 12, 32);
        NSDictionary *payload = [engine rendererCandidatesForName:name tag:tag limit:limit] ?: @{};
        BOOL success = [payload[@"success"] boolValue];
        NSString *summary = success
            ? [NSString stringWithFormat:@"Resolved %lu Unity renderer candidates",
               (unsigned long)[payload[@"returnedCount"] unsignedIntegerValue]]
            : (VCAITrimmedString(payload[@"error"]).length > 0 ? payload[@"error"] : @"Unity renderer discovery failed");
        return success ? VCAISuccessResult(toolCall, summary, payload, nil) : VCAIErrorResult(toolCall, summary);
    }

    if ([queryType isEqualToString:@"transform_position"]) {
        uintptr_t transformAddress = VCAIAddressParam(params, @[@"transformAddress", @"transform_address"]);
        uintptr_t componentAddress = VCAIAddressParam(params, @[@"componentAddress", @"component_address"]);
        uintptr_t gameObjectAddress = VCAIAddressParam(params, @[@"gameObjectAddress", @"game_object_address"]);
        uintptr_t genericAddress = VCAIAddressParam(params, @[@"address"]);

        uintptr_t sourceAddress = 0;
        NSString *objectKind = @"";
        if (transformAddress > 0) {
            sourceAddress = transformAddress;
            objectKind = @"transform";
        } else if (componentAddress > 0) {
            sourceAddress = componentAddress;
            objectKind = @"component";
        } else if (gameObjectAddress > 0) {
            sourceAddress = gameObjectAddress;
            objectKind = @"gameobject";
        } else if (genericAddress > 0) {
            sourceAddress = genericAddress;
            objectKind = [VCAIStringParam(params, @[@"objectKind", @"object_kind", @"kind"]) lowercaseString];
        }

        if (sourceAddress == 0) {
            return VCAIErrorResult(toolCall, @"transform_position requires transformAddress, componentAddress, gameObjectAddress, or address.");
        }

        NSDictionary *payload = [engine transformPositionForAddress:sourceAddress objectKind:objectKind] ?: @{};
        BOOL success = [payload[@"success"] boolValue];
        NSString *summary = success
            ? [NSString stringWithFormat:@"Resolved Unity %@ position for %@",
               VCAITrimmedString(payload[@"objectKind"]).length > 0 ? payload[@"objectKind"] : @"transform",
               VCAITrimmedString(payload[@"sourceAddress"]).length > 0 ? payload[@"sourceAddress"] : VCAIHexAddress(sourceAddress)]
            : (VCAITrimmedString(payload[@"error"]).length > 0 ? payload[@"error"] : @"Unity transform position could not be resolved");
        return success ? VCAISuccessResult(toolCall, summary, payload, nil) : VCAIErrorResult(toolCall, summary);
    }

    if ([queryType isEqualToString:@"renderer_bounds"]) {
        uintptr_t rendererAddress = VCAIAddressParam(params, @[@"rendererAddress", @"renderer_address", @"address"]);
        if (rendererAddress == 0) {
            return VCAIErrorResult(toolCall, @"renderer_bounds requires rendererAddress or address.");
        }

        NSDictionary *payload = [engine rendererBoundsForAddress:rendererAddress] ?: @{};
        BOOL success = [payload[@"success"] boolValue];
        NSString *summary = success
            ? [NSString stringWithFormat:@"Resolved Unity renderer bounds for %@",
               VCAITrimmedString(payload[@"rendererAddress"]).length > 0 ? payload[@"rendererAddress"] : VCAIHexAddress(rendererAddress)]
            : (VCAITrimmedString(payload[@"error"]).length > 0 ? payload[@"error"] : @"Unity renderer bounds could not be resolved");
        return success ? VCAISuccessResult(toolCall, summary, payload, nil) : VCAIErrorResult(toolCall, summary);
    }

    if ([queryType isEqualToString:@"project_renderer_bounds"]) {
        uintptr_t rendererAddress = VCAIAddressParam(params, @[@"rendererAddress", @"renderer_address", @"address"]);
        uintptr_t cameraAddress = VCAIAddressParam(params, @[@"cameraAddress", @"camera_address"]);
        if (rendererAddress == 0) {
            return VCAIErrorResult(toolCall, @"project_renderer_bounds requires rendererAddress or address.");
        }

        NSDictionary *payload = [engine projectRendererBoundsForAddress:rendererAddress cameraAddress:cameraAddress] ?: @{};
        BOOL success = [payload[@"success"] boolValue];
        NSString *summary = success
            ? @"Projected Unity renderer bounds into an overlay screen box"
            : (VCAITrimmedString(payload[@"error"]).length > 0 ? payload[@"error"] : @"Unity renderer bounds could not be projected");
        return success ? VCAISuccessResult(toolCall, summary, payload, nil) : VCAIErrorResult(toolCall, summary);
    }

    if ([queryType isEqualToString:@"world_to_screen"]) {
        uintptr_t cameraAddress = VCAIAddressParam(params, @[@"cameraAddress", @"camera_address"]);
        double worldX = VCAIDoubleParam(params, @[@"worldX", @"x"], NAN);
        double worldY = VCAIDoubleParam(params, @[@"worldY", @"y"], NAN);
        double worldZ = VCAIDoubleParam(params, @[@"worldZ", @"z"], NAN);

        NSDictionary *sourcePosition = nil;
        if (isnan(worldX) || isnan(worldY) || isnan(worldZ)) {
            uintptr_t transformAddress = VCAIAddressParam(params, @[@"transformAddress", @"transform_address"]);
            uintptr_t componentAddress = VCAIAddressParam(params, @[@"componentAddress", @"component_address"]);
            uintptr_t gameObjectAddress = VCAIAddressParam(params, @[@"gameObjectAddress", @"game_object_address"]);
            uintptr_t genericAddress = VCAIAddressParam(params, @[@"address"]);
            uintptr_t sourceAddress = 0;
            NSString *objectKind = @"";
            if (transformAddress > 0) {
                sourceAddress = transformAddress;
                objectKind = @"transform";
            } else if (componentAddress > 0) {
                sourceAddress = componentAddress;
                objectKind = @"component";
            } else if (gameObjectAddress > 0) {
                sourceAddress = gameObjectAddress;
                objectKind = @"gameobject";
            } else if (genericAddress > 0) {
                sourceAddress = genericAddress;
                objectKind = [VCAIStringParam(params, @[@"objectKind", @"object_kind", @"kind"]) lowercaseString];
            }
            if (sourceAddress == 0) {
                return VCAIErrorResult(toolCall, @"world_to_screen requires worldX/worldY/worldZ or a transform/component/gameObject address.");
            }

            sourcePosition = [engine transformPositionForAddress:sourceAddress objectKind:objectKind] ?: @{};
            if (![sourcePosition[@"success"] boolValue]) {
                NSString *error = VCAITrimmedString(sourcePosition[@"error"]);
                return VCAIErrorResult(toolCall, error.length > 0 ? error : @"Failed to resolve Unity object position before WorldToScreen.");
            }

            NSDictionary *world = [sourcePosition[@"world"] isKindOfClass:[NSDictionary class]] ? sourcePosition[@"world"] : @{};
            worldX = [world[@"x"] respondsToSelector:@selector(doubleValue)] ? [world[@"x"] doubleValue] : NAN;
            worldY = [world[@"y"] respondsToSelector:@selector(doubleValue)] ? [world[@"y"] doubleValue] : NAN;
            worldZ = [world[@"z"] respondsToSelector:@selector(doubleValue)] ? [world[@"z"] doubleValue] : NAN;
        }

        if (isnan(worldX) || isnan(worldY) || isnan(worldZ)) {
            return VCAIErrorResult(toolCall, @"world_to_screen requires concrete world coordinates.");
        }

        NSMutableDictionary *payload = [[engine worldToScreenForWorldX:worldX y:worldY z:worldZ cameraAddress:cameraAddress] mutableCopy] ?: [NSMutableDictionary new];
        BOOL success = [payload[@"success"] boolValue];
        if (sourcePosition) payload[@"sourcePosition"] = sourcePosition;
        NSString *summary = success
            ? ([payload[@"onScreen"] boolValue]
                ? @"Projected Unity world position onto the overlay canvas"
                : @"Projected Unity world position, but it is currently off-screen")
            : (VCAITrimmedString(payload[@"error"]).length > 0 ? payload[@"error"] : @"Unity WorldToScreen projection failed");
        return success ? VCAISuccessResult(toolCall, summary, [payload copy], nil) : VCAIErrorResult(toolCall, summary);
    }

    if ([queryType isEqualToString:@"notes"]) {
        NSDictionary *payload = [engine runtimeNotes] ?: @{};
        NSString *summary = [NSString stringWithFormat:@"Loaded Unity runtime guidance for %@",
                             VCAITrimmedString(payload[@"runtimeFlavor"]).length > 0 ? payload[@"runtimeFlavor"] : @"unknown runtime"];
        return VCAISuccessResult(toolCall, summary, payload, nil);
    }

    return VCAIErrorResult(toolCall, [NSString stringWithFormat:@"Unsupported unity_runtime queryType: %@", queryType ?: @""]);
}

+ (NSDictionary *)_executeProject3D:(VCToolCall *)toolCall {
    NSDictionary *params = toolCall.params ?: @{};
    NSString *mode = [VCAIStringParam(params, @[@"mode"]) lowercaseString];
    if (mode.length == 0) mode = @"point";

    double worldX = VCAIDoubleParam(params, @[@"worldX", @"x"], NAN);
    double worldY = VCAIDoubleParam(params, @[@"worldY", @"y"], NAN);
    double worldZ = VCAIDoubleParam(params, @[@"worldZ", @"z"], NAN);
    double worldW = VCAIDoubleParam(params, @[@"worldW", @"w"], 1.0);

    if (isnan(worldX) || isnan(worldY) || isnan(worldZ)) {
        uintptr_t worldAddress = VCAIAddressParam(params, @[@"worldAddress", @"world_address", @"address"]);
        NSString *worldType = VCAIStructTypeNormalized(VCAIStringParam(params, @[@"worldType", @"world_type", @"vectorType", @"vector_type"]));
        if (worldAddress == 0 || worldType.length == 0) {
            return VCAIErrorResult(toolCall, @"project_3d requires worldX/worldY/worldZ or worldAddress plus worldType.");
        }

        NSUInteger worldByteSize = VCAIStructByteSize(worldType);
        if (worldByteSize == 0) {
            return VCAIErrorResult(toolCall, [NSString stringWithFormat:@"Unsupported worldType %@", worldType]);
        }

        NSString *readError = nil;
        NSData *worldData = [self _safeReadDataAtAddress:worldAddress length:worldByteSize error:&readError];
        if (!worldData) return VCAIErrorResult(toolCall, readError ?: @"Failed to read world vector");
        NSDictionary *worldPayload = [self _structuredValuePayloadForData:worldData structType:worldType];
        if (!worldPayload) {
            return VCAIErrorResult(toolCall, [NSString stringWithFormat:@"Could not decode world vector type %@", worldType]);
        }

        worldX = [worldPayload[@"x"] respondsToSelector:@selector(doubleValue)] ? [worldPayload[@"x"] doubleValue] : NAN;
        worldY = [worldPayload[@"y"] respondsToSelector:@selector(doubleValue)] ? [worldPayload[@"y"] doubleValue] : NAN;
        worldZ = [worldPayload[@"z"] respondsToSelector:@selector(doubleValue)] ? [worldPayload[@"z"] doubleValue] : 0.0;
        if ([worldPayload[@"w"] respondsToSelector:@selector(doubleValue)]) {
            worldW = [worldPayload[@"w"] doubleValue];
        }
    }

    if (isnan(worldX) || isnan(worldY) || isnan(worldZ)) {
        return VCAIErrorResult(toolCall, @"project_3d needs concrete world coordinates.");
    }

    NSMutableArray<NSNumber *> *matrixElements = [NSMutableArray new];
    id rawElements = params[@"matrixElements"] ?: params[@"matrix"];
    if ([rawElements isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)rawElements) {
            if ([item respondsToSelector:@selector(doubleValue)]) {
                [matrixElements addObject:@([item doubleValue])];
            }
        }
    }

    NSString *matrixType = VCAIStructTypeNormalized(VCAIStringParam(params, @[@"matrixType", @"matrix_type", @"type"]));
    if (matrixType.length == 0) matrixType = @"matrix4x4f";

    if (matrixElements.count == 0) {
        uintptr_t matrixAddress = VCAIAddressParam(params, @[@"matrixAddress", @"matrix_address"]);
        if (matrixAddress == 0) {
            return VCAIErrorResult(toolCall, @"project_3d requires matrixElements or matrixAddress.");
        }

        NSUInteger matrixByteSize = VCAIStructByteSize(matrixType);
        if (matrixByteSize == 0) {
            return VCAIErrorResult(toolCall, [NSString stringWithFormat:@"Unsupported matrixType %@", matrixType]);
        }

        NSString *readError = nil;
        NSData *matrixData = [self _safeReadDataAtAddress:matrixAddress length:matrixByteSize error:&readError];
        if (!matrixData) return VCAIErrorResult(toolCall, readError ?: @"Failed to read projection matrix");
        NSDictionary *matrixPayload = [self _structuredValuePayloadForData:matrixData structType:matrixType];
        NSArray *elements = [matrixPayload[@"elements"] isKindOfClass:[NSArray class]] ? matrixPayload[@"elements"] : nil;
        if (elements.count != 16) {
            return VCAIErrorResult(toolCall, [NSString stringWithFormat:@"Could not decode %@ at %@", matrixType, VCAIHexAddress(matrixAddress)]);
        }
        for (id item in elements) {
            [matrixElements addObject:@([item doubleValue])];
        }
    }

    if (matrixElements.count != 16) {
        return VCAIErrorResult(toolCall, @"project_3d requires exactly 16 matrix elements.");
    }

    CGRect hostBounds = [VCOverlayRootViewController currentHostBounds];
    CGFloat viewportWidth = VCAIDoubleParam(params, @[@"viewportWidth", @"viewport_width"], CGRectGetWidth(hostBounds));
    CGFloat viewportHeight = VCAIDoubleParam(params, @[@"viewportHeight", @"viewport_height"], CGRectGetHeight(hostBounds));
    CGFloat viewportX = VCAIDoubleParam(params, @[@"viewportX", @"viewport_x"], 0.0);
    CGFloat viewportY = VCAIDoubleParam(params, @[@"viewportY", @"viewport_y"], 0.0);
    BOOL flipY = VCAIBoolParam(params, @[@"flipY", @"flip_y"], YES);

    if (viewportWidth <= 0.0 || viewportHeight <= 0.0) {
        return VCAIErrorResult(toolCall, @"project_3d needs a positive viewport width and height.");
    }

    NSString *layout = [VCAIStringParam(params, @[@"matrixLayout", @"matrix_layout", @"layout"]) lowercaseString];
    if (layout.length == 0) layout = @"auto";

    VCAIVector4d world = { worldX, worldY, worldZ, worldW };
    double m[16] = {0};
    for (NSUInteger idx = 0; idx < 16; idx++) {
        m[idx] = [matrixElements[idx] doubleValue];
    }

    VCAIVector4d rowMajorClip = VCAIClipVectorWithMatrix(m, world, NO);
    VCAIVector4d columnMajorClip = VCAIClipVectorWithMatrix(m, world, YES);

    NSDictionary *rowCandidate = VCAIProjectClipCandidate(rowMajorClip, viewportX, viewportY, viewportWidth, viewportHeight, flipY, @"row_major");
    NSDictionary *columnCandidate = VCAIProjectClipCandidate(columnMajorClip, viewportX, viewportY, viewportWidth, viewportHeight, flipY, @"column_major");

    NSDictionary *selected = rowCandidate;
    if ([layout isEqualToString:@"column_major"]) {
        selected = columnCandidate;
    } else if ([layout isEqualToString:@"auto"]) {
        double rowScore = [rowCandidate[@"plausibilityScore"] respondsToSelector:@selector(doubleValue)] ? [rowCandidate[@"plausibilityScore"] doubleValue] : -DBL_MAX;
        double columnScore = [columnCandidate[@"plausibilityScore"] respondsToSelector:@selector(doubleValue)] ? [columnCandidate[@"plausibilityScore"] doubleValue] : -DBL_MAX;
        selected = columnScore > rowScore ? columnCandidate : rowCandidate;
    }

    if ([mode isEqualToString:@"bounds"]) {
        double extentX = VCAIDoubleParam(params, @[@"extentX", @"ex"], NAN);
        double extentY = VCAIDoubleParam(params, @[@"extentY", @"ey"], NAN);
        double extentZ = VCAIDoubleParam(params, @[@"extentZ", @"ez"], NAN);
        if (isnan(extentX) || isnan(extentY) || isnan(extentZ)) {
            uintptr_t extentAddress = VCAIAddressParam(params, @[@"extentAddress", @"extent_address"]);
            NSString *extentType = VCAIStructTypeNormalized(VCAIStringParam(params, @[@"extentType", @"extent_type"]));
            if (extentAddress > 0 && extentType.length > 0) {
                NSUInteger extentByteSize = VCAIStructByteSize(extentType);
                if (extentByteSize == 0) {
                    return VCAIErrorResult(toolCall, [NSString stringWithFormat:@"Unsupported extentType %@", extentType]);
                }
                NSString *readError = nil;
                NSData *extentData = [self _safeReadDataAtAddress:extentAddress length:extentByteSize error:&readError];
                if (!extentData) return VCAIErrorResult(toolCall, readError ?: @"Failed to read bounds extents");
                NSDictionary *extentPayload = [self _structuredValuePayloadForData:extentData structType:extentType];
                if (!extentPayload) {
                    return VCAIErrorResult(toolCall, [NSString stringWithFormat:@"Could not decode extents type %@", extentType]);
                }
                extentX = [extentPayload[@"x"] respondsToSelector:@selector(doubleValue)] ? [extentPayload[@"x"] doubleValue] : NAN;
                extentY = [extentPayload[@"y"] respondsToSelector:@selector(doubleValue)] ? [extentPayload[@"y"] doubleValue] : NAN;
                extentZ = [extentPayload[@"z"] respondsToSelector:@selector(doubleValue)] ? [extentPayload[@"z"] doubleValue] : NAN;
            }
        }

        if (isnan(extentX) || isnan(extentY) || isnan(extentZ)) {
            return VCAIErrorResult(toolCall, @"project_3d mode=bounds requires extentX/extentY/extentZ or extentAddress plus extentType.");
        }

        NSArray<NSDictionary *> *corners = @[
            @{@"x": @(world.x - extentX), @"y": @(world.y - extentY), @"z": @(world.z - extentZ)},
            @{@"x": @(world.x - extentX), @"y": @(world.y - extentY), @"z": @(world.z + extentZ)},
            @{@"x": @(world.x - extentX), @"y": @(world.y + extentY), @"z": @(world.z - extentZ)},
            @{@"x": @(world.x - extentX), @"y": @(world.y + extentY), @"z": @(world.z + extentZ)},
            @{@"x": @(world.x + extentX), @"y": @(world.y - extentY), @"z": @(world.z - extentZ)},
            @{@"x": @(world.x + extentX), @"y": @(world.y - extentY), @"z": @(world.z + extentZ)},
            @{@"x": @(world.x + extentX), @"y": @(world.y + extentY), @"z": @(world.z - extentZ)},
            @{@"x": @(world.x + extentX), @"y": @(world.y + extentY), @"z": @(world.z + extentZ)}
        ];

        NSString *selectedLayout = selected[@"layout"] ?: ([layout isEqualToString:@"column_major"] ? @"column_major" : @"row_major");
        BOOL useColumnMajor = [selectedLayout isEqualToString:@"column_major"];
        NSMutableArray *projectedCorners = [NSMutableArray new];
        CGFloat minX = CGFLOAT_MAX;
        CGFloat minY = CGFLOAT_MAX;
        CGFloat maxX = -CGFLOAT_MAX;
        CGFloat maxY = -CGFLOAT_MAX;
        NSUInteger visibleCount = 0;

        for (NSDictionary *corner in corners) {
            VCAIVector4d cornerWorld = {
                [corner[@"x"] doubleValue],
                [corner[@"y"] doubleValue],
                [corner[@"z"] doubleValue],
                1.0
            };
            VCAIVector4d clip = VCAIClipVectorWithMatrix(m, cornerWorld, useColumnMajor);
            NSDictionary *projection = VCAIProjectClipCandidate(clip, viewportX, viewportY, viewportWidth, viewportHeight, flipY, selectedLayout);
            NSMutableDictionary *entry = [corner mutableCopy];
            entry[@"projection"] = projection ?: @{};
            [projectedCorners addObject:[entry copy]];
            if (![projection[@"valid"] boolValue] || ![projection[@"onScreen"] boolValue]) continue;
            NSDictionary *screenPoint = [projection[@"screenPoint"] isKindOfClass:[NSDictionary class]] ? projection[@"screenPoint"] : @{};
            CGFloat sx = [screenPoint[@"x"] respondsToSelector:@selector(doubleValue)] ? [screenPoint[@"x"] doubleValue] : 0.0;
            CGFloat sy = [screenPoint[@"y"] respondsToSelector:@selector(doubleValue)] ? [screenPoint[@"y"] doubleValue] : 0.0;
            minX = MIN(minX, sx);
            minY = MIN(minY, sy);
            maxX = MAX(maxX, sx);
            maxY = MAX(maxY, sy);
            visibleCount++;
        }

        BOOL hasBox = visibleCount > 0 && minX != CGFLOAT_MAX && minY != CGFLOAT_MAX && maxX >= minX && maxY >= minY;
        NSMutableDictionary *boundsPayload = [@{
            @"mode": @"bounds",
            @"worldCenter": @{
                @"x": @(world.x),
                @"y": @(world.y),
                @"z": @(world.z)
            },
            @"extents": @{
                @"x": @(extentX),
                @"y": @(extentY),
                @"z": @(extentZ)
            },
            @"matrixType": matrixType,
            @"matrixLayout": layout,
            @"selectedLayout": selectedLayout,
            @"viewport": VCAIOverlayViewportPayload(viewportWidth, viewportHeight, viewportX, viewportY),
            @"projectedCorners": [projectedCorners copy],
            @"visibleCornerCount": @(visibleCount),
            @"onScreen": @(hasBox)
        } mutableCopy];
        if (hasBox) {
            boundsPayload[@"screenBox"] = @{
                @"x": @(minX),
                @"y": @(minY),
                @"width": @(maxX - minX),
                @"height": @(maxY - minY)
            };
        }

        NSString *boundsSummary = hasBox
            ? @"Projected a 3D bounds volume into an overlay screen box"
            : @"Projected a 3D bounds volume, but it is currently off-screen";
        return hasBox ? VCAISuccessResult(toolCall, boundsSummary, [boundsPayload copy], nil) : VCAIErrorResult(toolCall, boundsSummary);
    }

    BOOL success = [selected[@"valid"] boolValue];
    NSMutableDictionary *payload = [@{
        @"mode": @"point",
        @"world": @{
            @"x": @(world.x),
            @"y": @(world.y),
            @"z": @(world.z),
            @"w": @(world.w)
        },
        @"matrixType": matrixType,
        @"matrixLayout": layout,
        @"selectedLayout": selected[@"layout"] ?: @"",
        @"viewport": VCAIOverlayViewportPayload(viewportWidth, viewportHeight, viewportX, viewportY),
        @"rowMajor": rowCandidate ?: @{},
        @"columnMajor": columnCandidate ?: @{}
    } mutableCopy];
    if (success) {
        payload[@"screenPoint"] = selected[@"screenPoint"] ?: @{};
        payload[@"onScreen"] = selected[@"onScreen"] ?: @NO;
        payload[@"ndc"] = selected[@"ndc"] ?: @{};
        payload[@"clip"] = selected[@"clip"] ?: @{};
    }

    NSString *summary = success
        ? ([selected[@"onScreen"] boolValue] ? @"Projected a 3D point into overlay screen coordinates" : @"Projected a 3D point, but it is currently off-screen")
        : (VCAITrimmedString(selected[@"reason"]).length > 0 ? selected[@"reason"] : @"3D projection failed");
    return success ? VCAISuccessResult(toolCall, summary, [payload copy], nil) : VCAIErrorResult(toolCall, summary);
}

+ (VCNetRecord *)_recordForRequestID:(NSString *)requestID {
    if (requestID.length == 0) return nil;
    for (VCNetRecord *record in [[VCNetMonitor shared] allRecords] ?: @[]) {
        if ([record.requestID isEqualToString:requestID]) return record;
    }
    return nil;
}

+ (NSDictionary *)_networkRecordSummary:(VCNetRecord *)record {
    if (!record) return @{};
    NSString *host = [NSURL URLWithString:record.url ?: @""].host ?: @"";
    return @{
        @"requestID": record.requestID ?: @"",
        @"method": record.method ?: @"GET",
        @"host": host,
        @"url": record.url ?: @"",
        @"statusCode": @(record.statusCode),
        @"durationMs": @((NSUInteger)llround(record.duration * 1000.0)),
        @"mimeType": record.mimeType ?: @"",
        @"wasModifiedByRule": @(record.wasModifiedByRule),
        @"matchedRules": record.matchedRules ?: @[]
    };
}

+ (NSDictionary *)_executeNetworkQuery:(VCToolCall *)toolCall {
    NSDictionary *params = toolCall.params ?: @{};
    NSString *queryType = [VCAIStringParam(params, @[@"queryType", @"query_type", @"mode"]) lowercaseString];
    if (queryType.length == 0) queryType = @"list";

    VCNetMonitor *monitor = [VCNetMonitor shared];

    if ([queryType isEqualToString:@"list"]) {
        NSString *filter = VCAIStringParam(params, @[@"filter", @"query", @"pattern"]);
        NSUInteger limit = VCAIUnsignedParam(params, @[@"limit"], 15, 60);
        NSArray<VCNetRecord *> *records = filter.length > 0 ? [monitor recordsMatchingFilter:filter] : [monitor allRecords];
        NSArray<VCNetRecord *> *recentRecords = VCAIReversedArray(VCAITail(records ?: @[], limit));

        NSMutableArray<NSDictionary *> *items = [NSMutableArray new];
        for (VCNetRecord *record in recentRecords) {
            [items addObject:[self _networkRecordSummary:record]];
        }

        NSDictionary *payload = @{
            @"queryType": queryType,
            @"monitoring": @(monitor.isMonitoring),
            @"filter": filter ?: @"",
            @"returnedCount": @(items.count),
            @"totalRecords": @(records.count),
            @"records": items
        };
        NSString *summary = items.count > 0
            ? [NSString stringWithFormat:@"Loaded %lu recent network records", (unsigned long)items.count]
            : @"No network records matched the query";
        return VCAISuccessResult(toolCall, summary, payload, nil);
    }

    if ([queryType isEqualToString:@"har"]) {
        NSString *filter = VCAIStringParam(params, @[@"filter", @"query", @"pattern"]);
        NSString *requestID = VCAIStringParam(params, @[@"requestID", @"requestId", @"id"]);
        NSUInteger limit = VCAIUnsignedParam(params, @[@"limit"], 40, 120);

        NSArray<VCNetRecord *> *records = nil;
        if (requestID.length > 0) {
            VCNetRecord *record = [self _recordForRequestID:requestID];
            if (!record) return VCAIErrorResult(toolCall, [NSString stringWithFormat:@"Network record %@ was not found", requestID]);
            records = @[record];
        } else {
            records = filter.length > 0 ? [monitor recordsMatchingFilter:filter] : [monitor allRecords];
            records = VCAITail(records ?: @[], limit);
        }

        NSMutableArray<NSDictionary *> *entries = [NSMutableArray new];
        NSUInteger skippedWebSockets = 0;
        for (VCNetRecord *record in records ?: @[]) {
            if (record.isWebSocket) {
                skippedWebSockets++;
                continue;
            }
            [entries addObject:[self _harEntryForRecord:record]];
        }

        NSDictionary *har = @{
            @"log": @{
                @"version": @"1.2",
                @"creator": @{@"name": @"VansonCLI", @"version": @"1.0"},
                @"entries": entries
            }
        };
        NSData *data = [NSJSONSerialization dataWithJSONObject:har options:NSJSONWritingPrettyPrinted error:nil];
        NSString *saveError = nil;
        NSDictionary *artifact = VCAISaveBinaryArtifact(@"network", @"Network Export", @"har", data, &saveError);
        if (!artifact) return VCAIErrorResult(toolCall, saveError ?: @"Failed to save HAR export");

        NSString *path = artifact[@"path"];
        NSDictionary *reference = VCAIReferenceForFile(@"HAR",
                                                       @"HAR Export",
                                                       @"har",
                                                       path,
                                                       @"Captured HTTP export for later analysis.",
                                                       nil);
        NSDictionary *payload = @{
            @"queryType": queryType,
            @"path": path ?: @"",
            @"entryCount": @(entries.count),
            @"skippedWebSocketRecords": @(skippedWebSockets),
            @"filter": filter ?: @"",
            @"requestID": requestID ?: @""
        };
        NSString *summary = [NSString stringWithFormat:@"Saved HAR export with %lu HTTP entries", (unsigned long)entries.count];
        return VCAISuccessResult(toolCall, summary, payload, reference);
    }

    NSString *requestID = VCAIStringParam(params, @[@"requestID", @"requestId", @"id"]);
    if ([queryType isEqualToString:@"ws_list"]) {
        NSString *filter = [VCAIStringParam(params, @[@"filter", @"query", @"pattern"]) lowercaseString];
        NSString *connectionID = VCAIStringParam(params, @[@"connectionID", @"connectionId", @"connection_id"]);
        NSUInteger limit = VCAIUnsignedParam(params, @[@"limit"], 20, 120);
        NSArray<VCWebSocketFrame *> *frames = [[VCNetMonitor shared] allWebSocketFrames] ?: @[];
        NSMutableArray<NSDictionary *> *items = [NSMutableArray new];
        for (VCWebSocketFrame *frame in VCAIReversedArray(frames)) {
            NSDictionary *summary = [self _webSocketFrameSummary:frame];
            NSString *candidate = [NSString stringWithFormat:@"%@ %@ %@ %@",
                                   summary[@"connectionID"] ?: @"",
                                   summary[@"direction"] ?: @"",
                                   summary[@"type"] ?: @"",
                                   summary[@"payloadPreview"] ?: @""].lowercaseString;
            if (connectionID.length > 0 && ![summary[@"connectionID"] isEqualToString:connectionID]) continue;
            if (filter.length > 0 && ![candidate containsString:filter]) continue;
            [items addObject:summary];
            if (items.count >= limit) break;
        }
        NSDictionary *payload = @{
            @"queryType": queryType,
            @"connectionID": connectionID ?: @"",
            @"filter": filter ?: @"",
            @"returnedCount": @(items.count),
            @"totalFrames": @(frames.count),
            @"frames": items
        };
        NSString *summary = items.count > 0
            ? [NSString stringWithFormat:@"Loaded %lu recent WebSocket frames", (unsigned long)items.count]
            : @"No WebSocket frames matched the query";
        return VCAISuccessResult(toolCall, summary, payload, nil);
    }

    if ([queryType isEqualToString:@"ws_detail"]) {
        NSString *frameID = VCAIStringParam(params, @[@"frameID", @"frameId", @"id"]);
        if (frameID.length == 0) return VCAIErrorResult(toolCall, @"query_network ws_detail requires frameID");

        VCWebSocketFrame *matchedFrame = nil;
        for (VCWebSocketFrame *frame in [[VCNetMonitor shared] allWebSocketFrames] ?: @[]) {
            if ([frame.frameID isEqualToString:frameID]) {
                matchedFrame = frame;
                break;
            }
        }
        if (!matchedFrame) return VCAIErrorResult(toolCall, [NSString stringWithFormat:@"WebSocket frame %@ was not found", frameID]);

        NSString *payloadText = @"";
        if ([matchedFrame.type isEqualToString:@"text"]) {
            payloadText = [[NSString alloc] initWithData:matchedFrame.payload encoding:NSUTF8StringEncoding] ?: @"";
        } else {
            payloadText = [NSString stringWithFormat:@"(binary %lu bytes)", (unsigned long)matchedFrame.payload.length];
        }
        NSDictionary *payload = @{
            @"queryType": queryType,
            @"frame": @{
                @"summary": [self _webSocketFrameSummary:matchedFrame],
                @"payloadText": VCAITruncatedString(payloadText, 4000)
            }
        };
        return VCAISuccessResult(toolCall, @"Loaded WebSocket frame detail", payload, nil);
    }

    VCNetRecord *record = [self _recordForRequestID:requestID];
    if (!record) return VCAIErrorResult(toolCall, [NSString stringWithFormat:@"Network record %@ was not found", requestID ?: @""]);

    if ([queryType isEqualToString:@"detail"]) {
        BOOL includeBodies = VCAIBoolParam(params, @[@"includeBodies", @"includeBody", @"include_bodies"], YES);
        NSDictionary *payload = @{
            @"queryType": queryType,
            @"record": @{
                @"summary": [self _networkRecordSummary:record],
                @"requestHeaders": record.requestHeaders ?: @{},
                @"responseHeaders": record.responseHeaders ?: @{},
                @"requestBody": includeBodies ? VCAITruncatedString([record requestBodyAsString] ?: @"", 3200) : @"",
                @"responseBody": includeBodies ? VCAITruncatedString([record responseBodyAsString] ?: @"", 4200) : @""
            }
        };
        NSString *summary = [NSString stringWithFormat:@"Loaded network detail for %@ %@", record.method ?: @"REQ", record.url ?: @"request"];
        return VCAISuccessResult(toolCall, summary, payload, nil);
    }

    if ([queryType isEqualToString:@"curl"]) {
        NSDictionary *payload = @{
            @"queryType": queryType,
            @"requestID": record.requestID ?: @"",
            @"curl": [record curlCommand] ?: @""
        };
        return VCAISuccessResult(toolCall, @"Exported cURL for the selected request", payload, nil);
    }

    return VCAIErrorResult(toolCall, [NSString stringWithFormat:@"Unsupported query_network queryType: %@", queryType ?: @""]);
}

+ (NSDictionary *)_viewDetailPayloadForView:(UIView *)view {
    if (!view) return @{};
    VCUIInspector *inspector = [VCUIInspector shared];
    NSDictionary *properties = [inspector propertiesForView:view] ?: @{};
    NSArray<NSString *> *keys = [[properties allKeys] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableDictionary *sampleProperties = [NSMutableDictionary new];
    for (NSString *key in [keys subarrayWithRange:NSMakeRange(0, MIN(keys.count, 50))]) {
        sampleProperties[key] = properties[key] ?: @"";
    }
    return @{
        @"className": NSStringFromClass([view class]) ?: @"UIView",
        @"address": VCAIHexAddress((uintptr_t)(__bridge void *)view),
        @"frame": NSStringFromCGRect(view.frame),
        @"hidden": @(view.hidden),
        @"alpha": @(view.alpha),
        @"userInteractionEnabled": @(view.userInteractionEnabled),
        @"subviewCount": @(view.subviews.count),
        @"properties": [sampleProperties copy],
        @"responderChain": [inspector responderChainForView:view] ?: @[]
    };
}

+ (NSString *)_controlEventName:(UIControlEvents)event {
    switch (event) {
        case UIControlEventTouchDown: return @"touch_down";
        case UIControlEventTouchDownRepeat: return @"touch_down_repeat";
        case UIControlEventTouchDragInside: return @"touch_drag_inside";
        case UIControlEventTouchDragOutside: return @"touch_drag_outside";
        case UIControlEventTouchUpInside: return @"touch_up_inside";
        case UIControlEventTouchUpOutside: return @"touch_up_outside";
        case UIControlEventValueChanged: return @"value_changed";
        case UIControlEventPrimaryActionTriggered: return @"primary_action_triggered";
        case UIControlEventEditingDidBegin: return @"editing_did_begin";
        case UIControlEventEditingChanged: return @"editing_changed";
        case UIControlEventEditingDidEnd: return @"editing_did_end";
        case UIControlEventEditingDidEndOnExit: return @"editing_did_end_on_exit";
        default: return [NSString stringWithFormat:@"0x%llx", (unsigned long long)event];
    }
}

+ (NSString *)_gestureStateName:(UIGestureRecognizerState)state {
    switch (state) {
        case UIGestureRecognizerStatePossible: return @"possible";
        case UIGestureRecognizerStateBegan: return @"began";
        case UIGestureRecognizerStateChanged: return @"changed";
        case UIGestureRecognizerStateEnded: return @"recognized";
        case UIGestureRecognizerStateCancelled: return @"cancelled";
        case UIGestureRecognizerStateFailed: return @"failed";
        default: return @"unknown";
    }
}

+ (NSString *)_layoutAttributeName:(NSLayoutAttribute)attribute {
    switch (attribute) {
        case NSLayoutAttributeLeft: return @"left";
        case NSLayoutAttributeRight: return @"right";
        case NSLayoutAttributeTop: return @"top";
        case NSLayoutAttributeBottom: return @"bottom";
        case NSLayoutAttributeLeading: return @"leading";
        case NSLayoutAttributeTrailing: return @"trailing";
        case NSLayoutAttributeWidth: return @"width";
        case NSLayoutAttributeHeight: return @"height";
        case NSLayoutAttributeCenterX: return @"centerX";
        case NSLayoutAttributeCenterY: return @"centerY";
        case NSLayoutAttributeLastBaseline: return @"lastBaseline";
        case NSLayoutAttributeFirstBaseline: return @"firstBaseline";
        case NSLayoutAttributeLeftMargin: return @"leftMargin";
        case NSLayoutAttributeRightMargin: return @"rightMargin";
        case NSLayoutAttributeTopMargin: return @"topMargin";
        case NSLayoutAttributeBottomMargin: return @"bottomMargin";
        case NSLayoutAttributeLeadingMargin: return @"leadingMargin";
        case NSLayoutAttributeTrailingMargin: return @"trailingMargin";
        case NSLayoutAttributeCenterXWithinMargins: return @"centerXWithinMargins";
        case NSLayoutAttributeCenterYWithinMargins: return @"centerYWithinMargins";
        case NSLayoutAttributeNotAnAttribute: return @"none";
        default: return [NSString stringWithFormat:@"%ld", (long)attribute];
    }
}

+ (NSString *)_layoutRelationName:(NSLayoutRelation)relation {
    switch (relation) {
        case NSLayoutRelationLessThanOrEqual: return @"<=";
        case NSLayoutRelationEqual: return @"==";
        case NSLayoutRelationGreaterThanOrEqual: return @">=";
        default: return @"?";
    }
}

+ (NSDictionary *)_constraintPayloadForConstraint:(NSLayoutConstraint *)constraint ownerView:(UIView *)ownerView {
    if (!constraint) return @{};
    id firstItem = constraint.firstItem;
    id secondItem = constraint.secondItem;
    NSString *ownerAddress = ownerView ? VCAIHexAddress((uintptr_t)(__bridge void *)ownerView) : @"";
    return @{
        @"description": constraint.description ?: @"",
        @"identifier": constraint.identifier ?: @"",
        @"relation": [self _layoutRelationName:constraint.relation],
        @"constant": @(constraint.constant),
        @"multiplier": @(constraint.multiplier),
        @"priority": @(constraint.priority),
        @"active": @(constraint.isActive),
        @"ownerAddress": ownerAddress,
        @"firstItemClass": firstItem ? NSStringFromClass([firstItem class]) : @"",
        @"firstItemAddress": firstItem ? VCAIHexAddress((uintptr_t)(__bridge void *)firstItem) : @"",
        @"firstAttribute": [self _layoutAttributeName:constraint.firstAttribute],
        @"secondItemClass": secondItem ? NSStringFromClass([secondItem class]) : @"",
        @"secondItemAddress": secondItem ? VCAIHexAddress((uintptr_t)(__bridge void *)secondItem) : @"",
        @"secondAttribute": [self _layoutAttributeName:constraint.secondAttribute]
    };
}

+ (NSArray<NSDictionary *> *)_constraintPayloadsForView:(UIView *)view {
    if (!view) return @[];
    NSMutableArray<NSDictionary *> *items = [NSMutableArray new];
    for (NSLayoutConstraint *constraint in view.constraints ?: @[]) {
        [items addObject:[self _constraintPayloadForConstraint:constraint ownerView:view]];
    }
    UIView *superview = view.superview;
    for (NSLayoutConstraint *constraint in superview.constraints ?: @[]) {
        if (constraint.firstItem == view || constraint.secondItem == view) {
            [items addObject:[self _constraintPayloadForConstraint:constraint ownerView:superview]];
        }
    }
    return [items copy];
}

+ (NSDictionary *)_accessibilityPayloadForView:(UIView *)view {
    if (!view) return @{};
    return @{
        @"className": NSStringFromClass([view class]) ?: @"UIView",
        @"address": VCAIHexAddress((uintptr_t)(__bridge void *)view),
        @"isAccessibilityElement": @(view.isAccessibilityElement),
        @"accessibilityLabel": view.accessibilityLabel ?: @"",
        @"accessibilityIdentifier": view.accessibilityIdentifier ?: @"",
        @"accessibilityHint": view.accessibilityHint ?: @"",
        @"accessibilityValue": [view.accessibilityValue respondsToSelector:@selector(description)] ? [view.accessibilityValue description] : @"",
        @"accessibilityTraits": @((unsigned long long)view.accessibilityTraits),
        @"accessibilityElementsHidden": @(view.accessibilityElementsHidden)
    };
}

+ (NSArray<NSDictionary *> *)_gesturePayloadsForView:(UIView *)view {
    NSMutableArray<NSDictionary *> *items = [NSMutableArray new];
    for (UIGestureRecognizer *gesture in view.gestureRecognizers ?: @[]) {
        NSMutableDictionary *entry = [@{
            @"className": NSStringFromClass([gesture class]) ?: @"UIGestureRecognizer",
            @"state": [self _gestureStateName:gesture.state],
            @"enabled": @(gesture.enabled),
            @"cancelsTouchesInView": @(gesture.cancelsTouchesInView),
            @"delaysTouchesBegan": @(gesture.delaysTouchesBegan),
            @"delaysTouchesEnded": @(gesture.delaysTouchesEnded)
        } mutableCopy];
        if ([gesture isKindOfClass:[UITapGestureRecognizer class]]) {
            UITapGestureRecognizer *tap = (UITapGestureRecognizer *)gesture;
            entry[@"numberOfTapsRequired"] = @(tap.numberOfTapsRequired);
            entry[@"numberOfTouchesRequired"] = @(tap.numberOfTouchesRequired);
        } else if ([gesture isKindOfClass:[UILongPressGestureRecognizer class]]) {
            UILongPressGestureRecognizer *press = (UILongPressGestureRecognizer *)gesture;
            entry[@"minimumPressDuration"] = @(press.minimumPressDuration);
            entry[@"allowableMovement"] = @(press.allowableMovement);
            entry[@"numberOfTouchesRequired"] = @(press.numberOfTouchesRequired);
        } else if ([gesture isKindOfClass:[UIPanGestureRecognizer class]]) {
            UIPanGestureRecognizer *pan = (UIPanGestureRecognizer *)gesture;
            entry[@"minimumNumberOfTouches"] = @(pan.minimumNumberOfTouches);
            entry[@"maximumNumberOfTouches"] = @(pan.maximumNumberOfTouches);
        } else if ([gesture isKindOfClass:[UISwipeGestureRecognizer class]]) {
            UISwipeGestureRecognizer *swipe = (UISwipeGestureRecognizer *)gesture;
            entry[@"numberOfTouchesRequired"] = @(swipe.numberOfTouchesRequired);
            entry[@"direction"] = @(swipe.direction);
        }
        [items addObject:[entry copy]];
    }
    return [items copy];
}

+ (NSArray<NSDictionary *> *)_controlActionPayloadsForView:(UIView *)view {
    if (![view isKindOfClass:[UIControl class]]) return @[];
    UIControl *control = (UIControl *)view;
    NSArray<NSNumber *> *events = @[
        @(UIControlEventTouchDown),
        @(UIControlEventTouchDownRepeat),
        @(UIControlEventTouchUpInside),
        @(UIControlEventTouchUpOutside),
        @(UIControlEventValueChanged),
        @(UIControlEventPrimaryActionTriggered),
        @(UIControlEventEditingDidBegin),
        @(UIControlEventEditingChanged),
        @(UIControlEventEditingDidEnd),
        @(UIControlEventEditingDidEndOnExit)
    ];

    NSMutableArray<NSDictionary *> *items = [NSMutableArray new];
    for (id target in control.allTargets ?: @[]) {
        NSString *targetClass = target ? NSStringFromClass([target class]) : @"";
        for (NSNumber *eventNumber in events) {
            UIControlEvents event = (UIControlEvents)[eventNumber unsignedLongLongValue];
            NSArray<NSString *> *actions = [control actionsForTarget:target forControlEvent:event] ?: @[];
            if (actions.count == 0) continue;
            [items addObject:@{
                @"targetClass": targetClass ?: @"",
                @"event": [self _controlEventName:event],
                @"actions": actions
            }];
        }
    }
    return [items copy];
}

+ (NSDictionary *)_interactionsPayloadForView:(UIView *)view {
    return @{
        @"className": NSStringFromClass([view class]) ?: @"UIView",
        @"address": VCAIHexAddress((uintptr_t)(__bridge void *)view),
        @"userInteractionEnabled": @(view.userInteractionEnabled),
        @"multipleTouchEnabled": @(view.multipleTouchEnabled),
        @"exclusiveTouch": @(view.exclusiveTouch),
        @"gestureRecognizers": [self _gesturePayloadsForView:view],
        @"controlActions": [self _controlActionPayloadsForView:view]
    };
}

+ (NSDictionary *)_webSocketFrameSummary:(VCWebSocketFrame *)frame {
    if (!frame) return @{};
    NSString *payloadPreview = @"";
    if ([frame.type isEqualToString:@"text"]) {
        NSString *text = [[NSString alloc] initWithData:frame.payload encoding:NSUTF8StringEncoding] ?: @"";
        payloadPreview = VCAITruncatedString(text, 240);
    } else {
        payloadPreview = [NSString stringWithFormat:@"(%lu bytes binary)", (unsigned long)frame.payload.length];
    }
    return @{
        @"frameID": frame.frameID ?: @"",
        @"connectionID": frame.connectionID ?: @"",
        @"direction": frame.direction ?: @"",
        @"type": frame.type ?: @"",
        @"payloadSize": @(frame.payload.length),
        @"payloadPreview": payloadPreview ?: @"",
        @"timestamp": @(frame.timestamp)
    };
}

+ (NSDictionary *)_harEntryForRecord:(VCNetRecord *)record {
    NSString *requestBodyText = [record requestBodyAsString];
    NSString *responseBodyText = [record responseBodyAsString];
    return @{
        @"startedDateTime": @((record.startTime > 0 ? record.startTime : [NSProcessInfo processInfo].systemUptime)),
        @"time": @(MAX(record.duration * 1000.0, 0)),
        @"request": @{
            @"method": record.method ?: @"GET",
            @"url": record.url ?: @"",
            @"headers": @[],
            @"queryString": @[],
            @"postData": @{
                @"mimeType": record.requestHeaders[@"Content-Type"] ?: @"text/plain",
                @"text": [requestBodyText isEqualToString:@"(empty)"] ? @"" : (requestBodyText ?: @"")
            }
        },
        @"response": @{
            @"status": @(record.statusCode),
            @"statusText": @"",
            @"headers": @[],
            @"content": @{
                @"mimeType": record.mimeType ?: @"text/plain",
                @"text": [responseBodyText isEqualToString:@"(empty)"] ? @"" : (responseBodyText ?: @"")
            }
        },
        @"comment": record.wasModifiedByRule ? [NSString stringWithFormat:@"matched: %@", [record.matchedRules componentsJoinedByString:@", "]] : @""
    };
}

+ (NSDictionary *)_executeUIQuery:(VCToolCall *)toolCall {
    NSDictionary *params = toolCall.params ?: @{};
    NSString *queryType = [VCAIStringParam(params, @[@"queryType", @"query_type", @"mode"]) lowercaseString];
    if (queryType.length == 0) queryType = @"hierarchy";

    VCUIInspector *inspector = [VCUIInspector shared];

    if ([queryType isEqualToString:@"hierarchy"]) {
        VCViewNode *root = [inspector viewHierarchyTree];
        if (!root) return VCAIErrorResult(toolCall, @"UI hierarchy is unavailable");

        NSString *filter = [VCAIStringParam(params, @[@"filter", @"query", @"pattern"]) lowercaseString];
        NSUInteger limit = VCAIUnsignedParam(params, @[@"limit"], 80, 160);
        NSUInteger maxDepth = VCAIUnsignedParam(params, @[@"maxDepth", @"max_depth", @"depth"], 4, 10);
        NSMutableArray<NSDictionary *> *nodes = [NSMutableArray new];
        for (VCViewNode *windowNode in root.children ?: @[]) {
            VCAIAppendViewNodes(windowNode, 0, (NSInteger)maxDepth, filter, limit, nodes);
            if (nodes.count >= limit) break;
        }
        NSDictionary *payload = @{
            @"queryType": queryType,
            @"filter": filter ?: @"",
            @"windowCount": @(root.children.count),
            @"returnedCount": @(nodes.count),
            @"maxDepth": @(maxDepth),
            @"nodes": nodes
        };
        NSString *summary = nodes.count > 0
            ? [NSString stringWithFormat:@"Loaded %lu UI nodes across %lu windows", (unsigned long)nodes.count, (unsigned long)root.children.count]
            : @"No UI nodes matched the current query";
        return VCAISuccessResult(toolCall, summary, payload, nil);
    }

    if ([queryType isEqualToString:@"alerts"] || [queryType isEqualToString:@"alert"]) {
        NSArray<NSDictionary *> *alerts = VCAICurrentAlertPayloads();
        NSDictionary *payload = @{
            @"queryType": queryType,
            @"returnedCount": @(alerts.count),
            @"alerts": alerts ?: @[]
        };
        NSString *summary = alerts.count > 0
            ? [NSString stringWithFormat:@"Loaded %lu visible alert candidate(s)", (unsigned long)alerts.count]
            : @"No visible alert candidates found";
        return VCAISuccessResult(toolCall, summary, payload, nil);
    }

    UIView *targetView = nil;
    uintptr_t address = VCAIAddressParam(params, @[@"address", @"viewAddress", @"view_address"]);
    if (address > 0) {
        targetView = [inspector viewForAddress:address];
    } else {
        targetView = inspector.currentSelectedView;
    }
    if (!targetView) return VCAIErrorResult(toolCall, @"No target view is available for this UI query");

    if ([queryType isEqualToString:@"selected_view"] || [queryType isEqualToString:@"view_detail"]) {
        NSDictionary *payload = @{
            @"queryType": queryType,
            @"view": [self _viewDetailPayloadForView:targetView]
        };
        NSString *summary = [NSString stringWithFormat:@"Loaded UI detail for %@", NSStringFromClass([targetView class]) ?: @"UIView"];
        return VCAISuccessResult(toolCall, summary, payload, nil);
    }

    if ([queryType isEqualToString:@"responder_chain"]) {
        NSDictionary *payload = @{
            @"queryType": queryType,
            @"address": VCAIHexAddress((uintptr_t)(__bridge void *)targetView),
            @"className": NSStringFromClass([targetView class]) ?: @"UIView",
            @"responderChain": [inspector responderChainForView:targetView] ?: @[]
        };
        return VCAISuccessResult(toolCall, @"Loaded UI responder chain", payload, nil);
    }

    if ([queryType isEqualToString:@"constraints"]) {
        NSArray<NSDictionary *> *constraints = [self _constraintPayloadsForView:targetView];
        NSDictionary *payload = @{
            @"queryType": queryType,
            @"address": VCAIHexAddress((uintptr_t)(__bridge void *)targetView),
            @"className": NSStringFromClass([targetView class]) ?: @"UIView",
            @"returnedCount": @(constraints.count),
            @"constraints": constraints
        };
        NSString *summary = [NSString stringWithFormat:@"Loaded %lu constraints involving %@",
                             (unsigned long)constraints.count,
                             NSStringFromClass([targetView class]) ?: @"UIView"];
        return VCAISuccessResult(toolCall, summary, payload, nil);
    }

    if ([queryType isEqualToString:@"accessibility"]) {
        NSDictionary *payload = @{
            @"queryType": queryType,
            @"view": [self _accessibilityPayloadForView:targetView]
        };
        return VCAISuccessResult(toolCall, @"Loaded UI accessibility detail", payload, nil);
    }

    if ([queryType isEqualToString:@"interactions"]) {
        NSDictionary *payload = @{
            @"queryType": queryType,
            @"view": [self _interactionsPayloadForView:targetView]
        };
        return VCAISuccessResult(toolCall, @"Loaded UI interactions for the target view", payload, nil);
    }

    if ([queryType isEqualToString:@"screenshot"]) {
        UIImage *image = [inspector screenshotView:targetView];
        NSData *imageData = UIImagePNGRepresentation(image);
        NSString *saveError = nil;
        NSString *title = [NSString stringWithFormat:@"%@ Screenshot", NSStringFromClass([targetView class]) ?: @"View"];
        NSDictionary *artifact = VCAISaveBinaryArtifact(@"screenshots", title, @"png", imageData, &saveError);
        if (!artifact) return VCAIErrorResult(toolCall, saveError ?: @"Failed to save UI screenshot");

        NSString *path = artifact[@"path"];
        NSDictionary *reference = VCAIReferenceForFile(@"Screenshot",
                                                       title,
                                                       @"image",
                                                       path,
                                                       @"Saved UI snapshot for later analysis.",
                                                       @{
                                                           @"width": @(CGImageGetWidth(image.CGImage)),
                                                           @"height": @(CGImageGetHeight(image.CGImage))
                                                       });
        NSDictionary *payload = @{
            @"queryType": queryType,
            @"address": VCAIHexAddress((uintptr_t)(__bridge void *)targetView),
            @"className": NSStringFromClass([targetView class]) ?: @"UIView",
            @"path": path ?: @"",
            @"width": @(CGImageGetWidth(image.CGImage)),
            @"height": @(CGImageGetHeight(image.CGImage))
        };
        NSString *summary = [NSString stringWithFormat:@"Saved screenshot for %@", NSStringFromClass([targetView class]) ?: @"UIView"];
        return VCAISuccessResult(toolCall, summary, payload, reference);
    }

    return VCAIErrorResult(toolCall, [NSString stringWithFormat:@"Unsupported query_ui queryType: %@", queryType ?: @""]);
}

+ (VCMemRegion *)_regionContainingAddress:(uintptr_t)address {
    if (address == 0) return nil;
    for (VCMemRegion *region in [[VCProcessInfo shared] memoryRegions] ?: @[]) {
        if (address >= region.start && address < region.end) {
            return region;
        }
    }
    return nil;
}

+ (NSData *)_safeReadDataAtAddress:(uintptr_t)address
                            length:(NSUInteger)length
                             error:(NSString **)errorMessage {
    if (address == 0 || length == 0) {
        if (errorMessage) *errorMessage = @"A non-zero address and length are required.";
        return nil;
    }

    VCMemRegion *region = [self _regionContainingAddress:address];
    if (!region || [region.protection rangeOfString:@"r"].location == NSNotFound) {
        if (errorMessage) *errorMessage = [NSString stringWithFormat:@"Address %@ is not inside a readable region", VCAIHexAddress(address)];
        return nil;
    }
    if ((uint64_t)address + length > region.end) {
        if (errorMessage) *errorMessage = [NSString stringWithFormat:@"Address %@ plus %@ bytes crosses the current region boundary", VCAIHexAddress(address), @(length)];
        return nil;
    }

    NSMutableData *buffer = [NSMutableData dataWithLength:length];
    vm_size_t outSize = 0;
    kern_return_t kr = vm_read_overwrite(mach_task_self(),
                                              (vm_address_t)address,
                                              (vm_size_t)length,
                                              (vm_address_t)buffer.mutableBytes,
                                              &outSize);
    if (kr != KERN_SUCCESS || outSize == 0) {
        if (errorMessage) *errorMessage = [NSString stringWithFormat:@"vm_read_overwrite failed for %@ (kr=%d)", VCAIHexAddress(address), kr];
        return nil;
    }

    if (outSize < length) {
        return [buffer subdataWithRange:NSMakeRange(0, (NSUInteger)outSize)];
    }
    return [buffer copy];
}

+ (NSString *)_hexDumpStringForData:(NSData *)data startAddress:(uintptr_t)address {
    if (![data isKindOfClass:[NSData class]] || data.length == 0) return @"";

    NSMutableArray<NSString *> *lines = [NSMutableArray new];
    const unsigned char *bytes = (const unsigned char *)data.bytes;
    NSUInteger offset = 0;
    while (offset < data.length) {
        NSUInteger lineLength = MIN(16, data.length - offset);
        NSMutableString *hexPart = [NSMutableString new];
        NSMutableString *asciiPart = [NSMutableString new];
        for (NSUInteger idx = 0; idx < 16; idx++) {
            if (idx < lineLength) {
                unsigned char byte = bytes[offset + idx];
                [hexPart appendFormat:@"%02x ", byte];
                [asciiPart appendFormat:@"%c", (byte >= 32 && byte <= 126) ? byte : '.'];
            } else {
                [hexPart appendString:@"   "];
            }
        }
        [lines addObject:[NSString stringWithFormat:@"%@  %@ %@",
                          VCAIHexAddress(address + offset),
                          hexPart,
                          asciiPart]];
        offset += lineLength;
    }
    return [lines componentsJoinedByString:@"\n"];
}

+ (NSDictionary *)_structuredValuePayloadForData:(NSData *)data structType:(NSString *)structType {
    NSString *normalized = VCAIStructTypeNormalized(structType);
    if (normalized.length == 0 || ![data isKindOfClass:[NSData class]]) return nil;

    if ([normalized isEqualToString:@"cgpoint"] && data.length >= sizeof(CGPoint)) {
        CGPoint point = CGPointZero;
        [data getBytes:&point length:sizeof(CGPoint)];
        return @{
            @"structType": normalized,
            @"x": @(point.x),
            @"y": @(point.y),
            @"description": NSStringFromCGPoint(point)
        };
    }
    if ([normalized isEqualToString:@"cgsize"] && data.length >= sizeof(CGSize)) {
        CGSize size = CGSizeZero;
        [data getBytes:&size length:sizeof(CGSize)];
        return @{
            @"structType": normalized,
            @"width": @(size.width),
            @"height": @(size.height),
            @"description": NSStringFromCGSize(size)
        };
    }
    if ([normalized isEqualToString:@"cgrect"] && data.length >= sizeof(CGRect)) {
        CGRect rect = CGRectZero;
        [data getBytes:&rect length:sizeof(CGRect)];
        return @{
            @"structType": normalized,
            @"x": @(rect.origin.x),
            @"y": @(rect.origin.y),
            @"width": @(rect.size.width),
            @"height": @(rect.size.height),
            @"description": NSStringFromCGRect(rect)
        };
    }
    if ([normalized isEqualToString:@"affine"] && data.length >= sizeof(CGAffineTransform)) {
        CGAffineTransform transform = CGAffineTransformIdentity;
        [data getBytes:&transform length:sizeof(CGAffineTransform)];
        return @{
            @"structType": normalized,
            @"a": @(transform.a),
            @"b": @(transform.b),
            @"c": @(transform.c),
            @"d": @(transform.d),
            @"tx": @(transform.tx),
            @"ty": @(transform.ty)
        };
    }
    if ([normalized isEqualToString:@"insets"] && data.length >= sizeof(UIEdgeInsets)) {
        UIEdgeInsets insets = UIEdgeInsetsZero;
        [data getBytes:&insets length:sizeof(UIEdgeInsets)];
        return @{
            @"structType": normalized,
            @"top": @(insets.top),
            @"left": @(insets.left),
            @"bottom": @(insets.bottom),
            @"right": @(insets.right)
        };
    }
    if ([normalized isEqualToString:@"range"] && data.length >= sizeof(NSRange)) {
        NSRange range = NSMakeRange(0, 0);
        [data getBytes:&range length:sizeof(NSRange)];
        return @{
            @"structType": normalized,
            @"location": @(range.location),
            @"length": @(range.length)
        };
    }
    if ([normalized isEqualToString:@"vector2f"] && data.length >= sizeof(float) * 2) {
        float values[2] = {0};
        [data getBytes:&values length:sizeof(values)];
        return @{
            @"structType": normalized,
            @"x": @(values[0]),
            @"y": @(values[1])
        };
    }
    if ([normalized isEqualToString:@"vector2d"] && data.length >= sizeof(double) * 2) {
        double values[2] = {0};
        [data getBytes:&values length:sizeof(values)];
        return @{
            @"structType": normalized,
            @"x": @(values[0]),
            @"y": @(values[1])
        };
    }
    if ([normalized isEqualToString:@"vector3f"] && data.length >= sizeof(float) * 3) {
        float values[3] = {0};
        [data getBytes:&values length:sizeof(values)];
        return @{
            @"structType": normalized,
            @"x": @(values[0]),
            @"y": @(values[1]),
            @"z": @(values[2])
        };
    }
    if ([normalized isEqualToString:@"vector3d"] && data.length >= sizeof(double) * 3) {
        double values[3] = {0};
        [data getBytes:&values length:sizeof(values)];
        return @{
            @"structType": normalized,
            @"x": @(values[0]),
            @"y": @(values[1]),
            @"z": @(values[2])
        };
    }
    if ([normalized isEqualToString:@"vector4f"] && data.length >= sizeof(float) * 4) {
        float values[4] = {0};
        [data getBytes:&values length:sizeof(values)];
        return @{
            @"structType": normalized,
            @"x": @(values[0]),
            @"y": @(values[1]),
            @"z": @(values[2]),
            @"w": @(values[3])
        };
    }
    if ([normalized isEqualToString:@"vector4d"] && data.length >= sizeof(double) * 4) {
        double values[4] = {0};
        [data getBytes:&values length:sizeof(values)];
        return @{
            @"structType": normalized,
            @"x": @(values[0]),
            @"y": @(values[1]),
            @"z": @(values[2]),
            @"w": @(values[3])
        };
    }
    if ([normalized isEqualToString:@"matrix4x4f"] && data.length >= sizeof(float) * 16) {
        float values[16] = {0};
        [data getBytes:&values length:sizeof(values)];
        NSMutableArray *rows = [NSMutableArray new];
        NSMutableArray *flat = [NSMutableArray new];
        for (NSUInteger row = 0; row < 4; row++) {
            NSMutableArray *rowValues = [NSMutableArray new];
            for (NSUInteger col = 0; col < 4; col++) {
                NSNumber *entry = @(values[row * 4 + col]);
                [rowValues addObject:entry];
                [flat addObject:entry];
            }
            [rows addObject:[rowValues copy]];
        }
        return @{
            @"structType": normalized,
            @"rows": [rows copy],
            @"elements": [flat copy]
        };
    }
    if ([normalized isEqualToString:@"matrix4x4d"] && data.length >= sizeof(double) * 16) {
        double values[16] = {0};
        [data getBytes:&values length:sizeof(values)];
        NSMutableArray *rows = [NSMutableArray new];
        NSMutableArray *flat = [NSMutableArray new];
        for (NSUInteger row = 0; row < 4; row++) {
            NSMutableArray *rowValues = [NSMutableArray new];
            for (NSUInteger col = 0; col < 4; col++) {
                NSNumber *entry = @(values[row * 4 + col]);
                [rowValues addObject:entry];
                [flat addObject:entry];
            }
            [rows addObject:[rowValues copy]];
        }
        return @{
            @"structType": normalized,
            @"rows": [rows copy],
            @"elements": [flat copy]
        };
    }

    return nil;
}

+ (NSString *)_valueDescriptionForData:(NSData *)data typeEncoding:(NSString *)typeEncoding {
    NSString *encoding = VCAITrimmedString(typeEncoding);
    if (!VCAIEncodingIsSafeForRawRead(encoding)) return @"";

    NSUInteger byteSize = VCAIByteSizeForEncoding(encoding);
    if (byteSize == 0 || data.length < byteSize) return @"";

    void *buffer = calloc(1, byteSize);
    if (!buffer) return @"";
    [data getBytes:buffer length:byteSize];
    NSString *value = [VCValueReader readValueAtAddress:(uintptr_t)buffer typeEncoding:encoding] ?: @"";
    free(buffer);
    return value ?: @"";
}

+ (NSString *)_memorySnapshotsDirectoryPath {
    NSString *path = [[[VCConfig shared] sessionsPath] stringByAppendingPathComponent:@"memory"];
    [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    return path;
}

+ (NSDictionary *)_saveMemorySnapshotPayload:(NSDictionary *)snapshotPayload
                                       title:(NSString *)title
                                errorMessage:(NSString **)errorMessage {
    NSData *jsonData = VCAIJSONObjectData(snapshotPayload);
    if (!jsonData) {
        if (errorMessage) *errorMessage = @"Memory snapshot payload could not be serialized.";
        return nil;
    }
    return VCAISaveBinaryArtifact(@"memory", title, @"json", jsonData, errorMessage);
}

+ (NSDictionary *)_memorySnapshotPayloadForAddress:(uintptr_t)address
                                            data:(NSData *)data
                                          region:(VCMemRegion *)region
                                      moduleName:(NSString *)moduleName
                                             rva:(uint64_t)rva
                                    typeEncoding:(NSString *)typeEncoding {
    NSString *snapshotID = [[NSUUID UUID] UUIDString];
    NSMutableDictionary *payload = [@{
        @"queryType": @"snapshot",
        @"snapshotID": snapshotID,
        @"createdAt": @([[NSDate date] timeIntervalSince1970]),
        @"address": VCAIHexAddress(address),
        @"length": @(data.length),
        @"moduleName": moduleName ?: @"",
        @"rva": rva > 0 ? VCAIHexAddress(rva) : @"",
        @"region": VCAIMemoryRegionDictionary(region),
        @"bytesHex": VCAIHexStringFromData(data) ?: @"",
        @"hexDump": [self _hexDumpStringForData:data startAddress:address] ?: @""
    } mutableCopy];

    NSString *encoding = VCAITrimmedString(typeEncoding);
    NSString *typedValue = [self _valueDescriptionForData:data typeEncoding:encoding];
    if (encoding.length > 0 && typedValue.length > 0) {
        payload[@"typeEncoding"] = encoding;
        payload[@"typedValue"] = typedValue;
    }
    return [payload copy];
}

+ (NSDictionary *)_loadMemorySnapshotAtPath:(NSString *)path errorMessage:(NSString **)errorMessage {
    NSString *trimmedPath = VCAITrimmedString(path);
    if (trimmedPath.length == 0) {
        if (errorMessage) *errorMessage = @"Snapshot path was empty.";
        return nil;
    }

    NSData *data = [NSData dataWithContentsOfFile:trimmedPath];
    if (!data) {
        if (errorMessage) *errorMessage = [NSString stringWithFormat:@"Could not read snapshot at %@", trimmedPath];
        return nil;
    }

    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![object isKindOfClass:[NSDictionary class]]) {
        if (errorMessage) *errorMessage = @"Snapshot JSON was invalid.";
        return nil;
    }

    NSMutableDictionary *snapshot = [(NSDictionary *)object mutableCopy];
    if (![snapshot[@"queryType"] isKindOfClass:[NSString class]] || [snapshot[@"queryType"] length] == 0) {
        snapshot[@"queryType"] = snapshot[@"changedByteCount"] ? @"diff_snapshot" : @"snapshot";
    }
    snapshot[@"path"] = trimmedPath;
    return [snapshot copy];
}

+ (NSDictionary *)_memorySnapshotSummaryPayloadForSnapshot:(NSDictionary *)snapshot {
    NSString *queryType = [snapshot[@"queryType"] isKindOfClass:[NSString class]] ? snapshot[@"queryType"] : @"snapshot";
    NSDictionary *lengths = [snapshot[@"lengths"] isKindOfClass:[NSDictionary class]] ? snapshot[@"lengths"] : nil;
    BOOL isDiff = [queryType isEqualToString:@"diff_snapshot"];
    return @{
        @"queryType": queryType,
        @"snapshotID": snapshot[@"snapshotID"] ?: @"",
        @"path": snapshot[@"path"] ?: @"",
        @"createdAt": snapshot[@"createdAt"] ?: @0,
        @"address": (isDiff ? snapshot[@"snapshotAddress"] : snapshot[@"address"]) ?: @"",
        @"length": snapshot[@"length"] ?: lengths[@"before"] ?: @0,
        @"moduleName": snapshot[@"moduleName"] ?: @"",
        @"changedByteCount": snapshot[@"changedByteCount"] ?: @0,
        @"comparisonName": snapshot[@"comparisonName"] ?: @"",
        @"typeEncoding": snapshot[@"typeEncoding"] ?: @""
    };
}

+ (NSArray<NSDictionary *> *)_memorySnapshotSummariesWithLimit:(NSUInteger)limit {
    NSString *directory = [self _memorySnapshotsDirectoryPath];
    NSArray<NSString *> *fileNames = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:nil] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray<NSDictionary *> *items = [NSMutableArray new];
    for (NSString *fileName in VCAIReversedArray(fileNames ?: @[])) {
        if (![fileName.pathExtension.lowercaseString isEqualToString:@"json"]) continue;
        NSString *fullPath = [directory stringByAppendingPathComponent:fileName];
        NSDictionary *snapshot = [self _loadMemorySnapshotAtPath:fullPath errorMessage:nil];
        if (!snapshot) continue;
        [items addObject:[self _memorySnapshotSummaryPayloadForSnapshot:snapshot]];
        if (items.count >= limit) break;
    }
    return [items copy];
}

+ (NSDictionary *)_loadMemorySnapshotByID:(NSString *)snapshotID errorMessage:(NSString **)errorMessage {
    NSString *trimmedID = VCAITrimmedString(snapshotID);
    if (trimmedID.length == 0) {
        if (errorMessage) *errorMessage = @"Snapshot ID was empty.";
        return nil;
    }

    NSString *directory = [self _memorySnapshotsDirectoryPath];
    NSArray<NSString *> *fileNames = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:nil] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *fileName in fileNames ?: @[]) {
        if (![fileName.pathExtension.lowercaseString isEqualToString:@"json"]) continue;
        NSString *fullPath = [directory stringByAppendingPathComponent:fileName];
        NSDictionary *snapshot = [self _loadMemorySnapshotAtPath:fullPath errorMessage:nil];
        if ([snapshot[@"snapshotID"] isEqualToString:trimmedID]) {
            return snapshot;
        }
    }

    if (errorMessage) *errorMessage = [NSString stringWithFormat:@"Snapshot %@ was not found", trimmedID];
    return nil;
}

+ (NSDictionary *)_loadMemorySnapshotFromParams:(NSDictionary *)params
                                            idKeys:(NSArray<NSString *> *)idKeys
                                          pathKeys:(NSArray<NSString *> *)pathKeys
                                     errorMessage:(NSString **)errorMessage {
    NSString *snapshotPath = VCAIStringParam(params, pathKeys);
    if (snapshotPath.length > 0) {
        return [self _loadMemorySnapshotAtPath:snapshotPath errorMessage:errorMessage];
    }
    NSString *snapshotID = VCAIStringParam(params, idKeys);
    if (snapshotID.length > 0) {
        return [self _loadMemorySnapshotByID:snapshotID errorMessage:errorMessage];
    }
    if (errorMessage) *errorMessage = @"A snapshotID or snapshotPath is required.";
    return nil;
}

+ (NSArray<NSDictionary *> *)_savedTrackSummariesWithLimit:(NSUInteger)limit {
    return [[VCOverlayTrackingManager shared] savedTrackerSummariesWithLimit:MAX((NSUInteger)1, MIN(limit, (NSUInteger)100))] ?: @[];
}

+ (NSDictionary *)_loadTrackDetailFromParams:(NSDictionary *)params
                                      idKeys:(NSArray<NSString *> *)idKeys
                                    pathKeys:(NSArray<NSString *> *)pathKeys
                               errorMessage:(NSString **)errorMessage {
    NSString *trackPath = VCAIStringParam(params, pathKeys);
    NSString *trackID = VCAIStringParam(params, idKeys);
    NSDictionary *detail = [[VCOverlayTrackingManager shared] savedTrackerDetailFromPath:(trackPath.length > 0 ? trackPath : nil)
                                                                               trackerID:(trackID.length > 0 ? trackID : nil)];
    if (detail) return detail;
    if (errorMessage) {
        *errorMessage = trackPath.length > 0
            ? [NSString stringWithFormat:@"Saved tracker at %@ could not be loaded", trackPath]
            : @"A trackerID or trackerPath is required.";
    }
    return nil;
}

+ (NSString *)_mermaidArtifactsDirectoryPath {
    NSString *path = [[[VCConfig shared] sessionsPath] stringByAppendingPathComponent:@"diagrams"];
    [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    return path;
}

+ (NSString *)_diagramTypeForMermaidContent:(NSString *)content {
    NSString *normalized = [VCAITrimmedString(content) copy];
    if (normalized.length == 0) return @"diagram";
    NSArray<NSString *> *lines = [normalized componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    for (NSString *line in lines) {
        NSString *trimmedLine = VCAITrimmedString(line).lowercaseString;
        if (trimmedLine.length == 0) continue;
        if ([trimmedLine hasPrefix:@"sequenceDiagram".lowercaseString]) return @"sequence";
        if ([trimmedLine hasPrefix:@"flowchart"] || [trimmedLine hasPrefix:@"graph "]) return @"flowchart";
        if ([trimmedLine hasPrefix:@"classDiagram".lowercaseString]) return @"class";
        if ([trimmedLine hasPrefix:@"stateDiagram".lowercaseString]) return @"state";
        if ([trimmedLine hasPrefix:@"erDiagram".lowercaseString]) return @"er";
        return @"diagram";
    }
    return @"diagram";
}

+ (NSDictionary *)_loadMermaidArtifactAtPath:(NSString *)path errorMessage:(NSString **)errorMessage {
    NSString *trimmedPath = VCAITrimmedString(path);
    if (trimmedPath.length == 0) {
        if (errorMessage) *errorMessage = @"Artifact path was empty.";
        return nil;
    }

    NSString *content = [NSString stringWithContentsOfFile:trimmedPath encoding:NSUTF8StringEncoding error:nil];
    if (![content isKindOfClass:[NSString class]]) {
        if (errorMessage) *errorMessage = [NSString stringWithFormat:@"Could not read Mermaid artifact at %@", trimmedPath];
        return nil;
    }

    NSString *fileName = trimmedPath.lastPathComponent ?: @"diagram.mmd";
    NSString *artifactID = fileName.stringByDeletingPathExtension ?: fileName;
    NSString *title = artifactID;
    if ([title length] > 16 && [title characterAtIndex:8] == '-' && [title characterAtIndex:15] == '-') {
        NSString *suffix = [title substringFromIndex:16];
        if (suffix.length > 0) title = suffix;
    }

    NSString *summary = @"";
    NSArray<NSString *> *lines = [content componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    for (NSString *line in lines) {
        NSString *trimmedLine = VCAITrimmedString(line);
        if (trimmedLine.length == 0) continue;
        summary = trimmedLine;
        break;
    }

    return @{
        @"artifactID": artifactID ?: @"",
        @"title": title ?: @"Diagram",
        @"path": trimmedPath,
        @"createdAt": @(VCAIFileTimestampAtPath(trimmedPath)),
        @"byteCount": VCAIFileSizeAtPath(trimmedPath),
        @"diagramType": [self _diagramTypeForMermaidContent:content],
        @"summary": summary ?: @"",
        @"content": content ?: @""
    };
}

+ (NSDictionary *)_mermaidArtifactSummaryForArtifact:(NSDictionary *)artifact {
    NSString *content = [artifact[@"content"] isKindOfClass:[NSString class]] ? artifact[@"content"] : @"";
    NSUInteger lineCount = content.length > 0 ? [[content componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] count] : 0;
    return @{
        @"artifactID": artifact[@"artifactID"] ?: @"",
        @"title": artifact[@"title"] ?: @"Diagram",
        @"path": artifact[@"path"] ?: @"",
        @"createdAt": artifact[@"createdAt"] ?: @0,
        @"byteCount": artifact[@"byteCount"] ?: @0,
        @"diagramType": artifact[@"diagramType"] ?: @"diagram",
        @"summary": artifact[@"summary"] ?: @"",
        @"lineCount": @(lineCount)
    };
}

+ (NSArray<NSDictionary *> *)_mermaidArtifactSummariesWithLimit:(NSUInteger)limit {
    NSString *directory = [self _mermaidArtifactsDirectoryPath];
    NSArray<NSString *> *fileNames = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:nil] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray<NSDictionary *> *items = [NSMutableArray new];
    for (NSString *fileName in VCAIReversedArray(fileNames ?: @[])) {
        if (![fileName.pathExtension.lowercaseString isEqualToString:@"mmd"]) continue;
        NSString *fullPath = [directory stringByAppendingPathComponent:fileName];
        NSDictionary *artifact = [self _loadMermaidArtifactAtPath:fullPath errorMessage:nil];
        if (!artifact) continue;
        [items addObject:[self _mermaidArtifactSummaryForArtifact:artifact]];
        if (items.count >= limit) break;
    }
    return [items copy];
}

+ (NSDictionary *)_loadMermaidArtifactByID:(NSString *)artifactID errorMessage:(NSString **)errorMessage {
    NSString *trimmedID = VCAITrimmedString(artifactID);
    if (trimmedID.length == 0) {
        if (errorMessage) *errorMessage = @"Artifact ID was empty.";
        return nil;
    }

    NSString *directory = [self _mermaidArtifactsDirectoryPath];
    NSArray<NSString *> *fileNames = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:nil] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *fileName in fileNames ?: @[]) {
        if (![fileName.pathExtension.lowercaseString isEqualToString:@"mmd"]) continue;
        NSString *stem = fileName.stringByDeletingPathExtension ?: fileName;
        if (![stem isEqualToString:trimmedID] && ![fileName isEqualToString:trimmedID]) continue;
        return [self _loadMermaidArtifactAtPath:[directory stringByAppendingPathComponent:fileName] errorMessage:errorMessage];
    }

    if (errorMessage) *errorMessage = [NSString stringWithFormat:@"Artifact %@ was not found", trimmedID];
    return nil;
}

+ (NSDictionary *)_memoryDiffPayloadFromSourceSnapshot:(NSDictionary *)sourceSnapshot
                                        comparisonName:(NSString *)comparisonName
                                       comparisonBytes:(NSData *)comparisonBytes
                                     comparisonAddress:(uintptr_t)comparisonAddress
                                          typeEncoding:(NSString *)typeEncoding {
    NSData *sourceBytes = VCAIDataFromHexString(sourceSnapshot[@"bytesHex"]);
    if (sourceBytes.length == 0 || comparisonBytes.length == 0) return nil;

    const unsigned char *beforeBytes = (const unsigned char *)sourceBytes.bytes;
    const unsigned char *afterBytes = (const unsigned char *)comparisonBytes.bytes;
    NSUInteger maxLength = MAX(sourceBytes.length, comparisonBytes.length);
    NSUInteger changedCount = 0;
    NSMutableArray<NSDictionary *> *changes = [NSMutableArray new];

    uintptr_t sourceAddress = (uintptr_t)strtoull([VCAITrimmedString(sourceSnapshot[@"address"]) UTF8String], NULL, 0);
    for (NSUInteger idx = 0; idx < maxLength; idx++) {
        BOOL hasBefore = idx < sourceBytes.length;
        BOOL hasAfter = idx < comparisonBytes.length;
        unsigned char beforeByte = hasBefore ? beforeBytes[idx] : 0;
        unsigned char afterByte = hasAfter ? afterBytes[idx] : 0;
        if (!hasBefore || !hasAfter || beforeByte != afterByte) {
            changedCount++;
            if (changes.count < 96) {
                [changes addObject:@{
                    @"offset": @(idx),
                    @"address": sourceAddress > 0 ? VCAIHexAddress(sourceAddress + idx) : @"",
                    @"before": hasBefore ? [NSString stringWithFormat:@"%02x", beforeByte] : @"--",
                    @"after": hasAfter ? [NSString stringWithFormat:@"%02x", afterByte] : @"--"
                }];
            }
        }
    }

    NSMutableDictionary *payload = [@{
        @"queryType": @"diff_snapshot",
        @"snapshotID": sourceSnapshot[@"snapshotID"] ?: @"",
        @"snapshotAddress": sourceSnapshot[@"address"] ?: @"",
        @"createdAt": @([[NSDate date] timeIntervalSince1970]),
        @"comparisonName": comparisonName ?: @"comparison",
        @"comparisonAddress": comparisonAddress > 0 ? VCAIHexAddress(comparisonAddress) : @"",
        @"lengths": @{
            @"before": @(sourceBytes.length),
            @"after": @(comparisonBytes.length)
        },
        @"changedByteCount": @(changedCount),
        @"changes": changes,
        @"beforeHexDump": [self _hexDumpStringForData:sourceBytes startAddress:sourceAddress] ?: @"",
        @"afterHexDump": [self _hexDumpStringForData:comparisonBytes startAddress:(comparisonAddress > 0 ? comparisonAddress : sourceAddress)] ?: @""
    } mutableCopy];

    NSString *resolvedEncoding = VCAITrimmedString(typeEncoding);
    if (resolvedEncoding.length == 0) {
        resolvedEncoding = [VCAITrimmedString(sourceSnapshot[@"typeEncoding"]) copy];
    }
    NSString *beforeValue = [self _valueDescriptionForData:sourceBytes typeEncoding:resolvedEncoding];
    NSString *afterValue = [self _valueDescriptionForData:comparisonBytes typeEncoding:resolvedEncoding];
    if (resolvedEncoding.length > 0 && beforeValue.length > 0 && afterValue.length > 0) {
        payload[@"typeEncoding"] = resolvedEncoding;
        payload[@"typedBefore"] = beforeValue;
        payload[@"typedAfter"] = afterValue;
        payload[@"typedChanged"] = @(![beforeValue isEqualToString:afterValue]);
    }

    return [payload copy];
}

+ (NSMutableDictionary *)_matrixValidationSessionStorage {
    static NSMutableDictionary *session = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        session = [NSMutableDictionary new];
    });
    return session;
}

+ (NSMutableDictionary *)_matrixValidationMutableSessionMatchingParams:(NSDictionary *)params
                                                         errorMessage:(NSString **)errorMessage {
    NSMutableDictionary *session = [self _matrixValidationSessionStorage];
    NSString *activeSessionID = VCAITrimmedString(session[@"sessionID"]);
    if (activeSessionID.length == 0) {
        if (errorMessage) *errorMessage = @"No active matrix validation session. Start one with query_memory matrix_validate action=start.";
        return nil;
    }

    NSString *requestedSessionID = VCAIStringParam(params, @[@"sessionID", @"sessionId", @"id"]);
    if (requestedSessionID.length > 0 && ![requestedSessionID isEqualToString:activeSessionID]) {
        if (errorMessage) {
            *errorMessage = [NSString stringWithFormat:@"Active matrix validation session is %@, not %@.",
                             activeSessionID,
                             requestedSessionID];
        }
        return nil;
    }
    return session;
}

+ (NSArray<NSDictionary *> *)_matrixValidationCandidatesFromParams:(NSDictionary *)params
                                                 defaultMatrixType:(NSString *)matrixType
                                                            limit:(NSUInteger)limit {
    NSMutableArray *rawItems = [NSMutableArray new];
    NSArray *candidateObjects = [params[@"candidates"] isKindOfClass:[NSArray class]] ? params[@"candidates"] : nil;
    if (candidateObjects.count > 0) {
        [rawItems addObjectsFromArray:candidateObjects];
    }

    NSArray *candidateAddresses = [params[@"candidateAddresses"] isKindOfClass:[NSArray class]] ? params[@"candidateAddresses"] : nil;
    if (candidateAddresses.count > 0) {
        [rawItems addObjectsFromArray:candidateAddresses];
    } else {
        NSArray<NSString *> *candidateAddressStrings = VCAIStringArrayParam(params, @[@"candidateAddresses", @"candidate_addresses"]);
        if (candidateAddressStrings.count > 0) {
            [rawItems addObjectsFromArray:candidateAddressStrings];
        }
    }

    uintptr_t singleAddress = VCAIAddressParam(params, @[@"address", @"matrixAddress", @"candidateAddress"]);
    if (rawItems.count == 0 && singleAddress > 0) {
        [rawItems addObject:VCAIHexAddress(singleAddress)];
    }

    NSString *fallbackMatrixType = VCAIStructTypeNormalized(matrixType);
    if (fallbackMatrixType.length == 0) fallbackMatrixType = @"matrix4x4f";

    NSMutableArray<NSDictionary *> *normalized = [NSMutableArray new];
    NSMutableSet<NSString *> *seenAddresses = [NSMutableSet set];
    NSUInteger maxCount = MAX((NSUInteger)1, MIN(limit, (NSUInteger)12));

    for (id item in rawItems) {
        if (normalized.count >= maxCount) break;

        uintptr_t address = 0;
        NSString *moduleName = @"";
        NSString *rvaString = @"";
        NSString *preferredLayout = @"";
        NSString *candidateMatrixType = fallbackMatrixType;
        double staticScore = 0.0;

        if ([item isKindOfClass:[NSDictionary class]]) {
            NSDictionary *dictionary = (NSDictionary *)item;
            address = VCAIAddressParam(dictionary, @[@"address", @"matrixAddress", @"candidateAddress"]);
            moduleName = VCAITrimmedString(dictionary[@"moduleName"]);
            rvaString = VCAITrimmedString(dictionary[@"rva"]);
            preferredLayout = VCAITrimmedString(dictionary[@"preferredLayout"]);
            NSString *dictionaryMatrixType = VCAIStructTypeNormalized(VCAIStringParam(dictionary, @[@"matrixType", @"matrix_type", @"type"]));
            if (dictionaryMatrixType.length > 0) candidateMatrixType = dictionaryMatrixType;
            if ([dictionary[@"score"] respondsToSelector:@selector(doubleValue)]) {
                staticScore = [dictionary[@"score"] doubleValue];
            } else {
                double rowScore = [dictionary[@"rowMajorScore"] respondsToSelector:@selector(doubleValue)] ? [dictionary[@"rowMajorScore"] doubleValue] : 0.0;
                double columnScore = [dictionary[@"columnMajorScore"] respondsToSelector:@selector(doubleValue)] ? [dictionary[@"columnMajorScore"] doubleValue] : 0.0;
                staticScore = MAX(rowScore, columnScore);
            }
        } else if ([item isKindOfClass:[NSString class]] || [item isKindOfClass:[NSNumber class]]) {
            address = (uintptr_t)strtoull([VCAITrimmedString(item) UTF8String], NULL, 0);
        }

        if (address == 0) continue;
        NSString *addressString = VCAIHexAddress(address);
        if ([seenAddresses containsObject:addressString]) continue;

        VCMemRegion *candidateRegion = [self _regionContainingAddress:address];
        if (!candidateRegion || [candidateRegion.protection rangeOfString:@"r"].location == NSNotFound) continue;

        NSString *resolvedModuleName = nil;
        uint64_t rva = [[VCProcessInfo shared] runtimeToRva:(uint64_t)address module:&resolvedModuleName];
        NSString *blockedReason = [VCPromptLeakGuard blockedToolReasonForMemoryModuleName:(moduleName.length > 0 ? moduleName : resolvedModuleName)
                                                                                  address:(unsigned long long)address];
        if (blockedReason.length > 0) continue;

        [seenAddresses addObject:addressString];
        [normalized addObject:@{
            @"address": addressString,
            @"moduleName": moduleName.length > 0 ? moduleName : (resolvedModuleName ?: @""),
            @"rva": rvaString.length > 0 ? rvaString : (rva > 0 ? VCAIHexAddress(rva) : @""),
            @"matrixType": candidateMatrixType ?: fallbackMatrixType,
            @"preferredLayout": preferredLayout.length > 0 ? preferredLayout : @"auto",
            @"initialStaticScore": @(staticScore),
            @"region": VCAIMemoryRegionDictionary(candidateRegion)
        }];
    }

    return [normalized copy];
}

+ (NSDictionary *)_matrixValidationCapturedSampleForCandidate:(NSDictionary *)candidate
                                                        label:(NSString *)label
                                                   matrixType:(NSString *)matrixType {
    uintptr_t address = (uintptr_t)strtoull([VCAITrimmedString(candidate[@"address"]) UTF8String], NULL, 0);
    NSString *resolvedMatrixType = VCAIStructTypeNormalized(matrixType);
    if (resolvedMatrixType.length == 0) {
        resolvedMatrixType = VCAIStructTypeNormalized(VCAITrimmedString(candidate[@"matrixType"]));
    }
    if (resolvedMatrixType.length == 0) resolvedMatrixType = @"matrix4x4f";

    NSMutableDictionary *sample = [@{
        @"label": label ?: @"capture",
        @"capturedAt": @([[NSDate date] timeIntervalSince1970]),
        @"success": @NO
    } mutableCopy];

    if (address == 0) {
        sample[@"error"] = @"Candidate address was empty.";
        return [sample copy];
    }

    NSUInteger byteSize = VCAIStructByteSize(resolvedMatrixType);
    if (byteSize == 0) {
        sample[@"error"] = [NSString stringWithFormat:@"Unsupported matrix type %@", resolvedMatrixType];
        return [sample copy];
    }

    NSString *readError = nil;
    NSData *data = [self _safeReadDataAtAddress:address length:byteSize error:&readError];
    if (data.length < byteSize) {
        sample[@"error"] = readError.length > 0 ? readError : @"Could not read a full matrix payload.";
        return [sample copy];
    }

    double elements[16] = {0};
    if (!VCAIMatrixElementsFromRawData(data, resolvedMatrixType, elements)) {
        sample[@"error"] = [NSString stringWithFormat:@"Could not decode %@", resolvedMatrixType];
        return [sample copy];
    }

    CGRect hostBounds = [VCOverlayRootViewController currentHostBounds];
    CGFloat viewportWidth = MAX(CGRectGetWidth(hostBounds), 1.0);
    CGFloat viewportHeight = MAX(CGRectGetHeight(hostBounds), 1.0);
    double rowScore = VCAIMatrixProjectionScore(elements, NO, viewportWidth, viewportHeight);
    double columnScore = VCAIMatrixProjectionScore(elements, YES, viewportWidth, viewportHeight);
    if (!isfinite(rowScore)) rowScore = -1000000.0;
    if (!isfinite(columnScore)) columnScore = -1000000.0;

    sample[@"success"] = @YES;
    sample[@"address"] = VCAIHexAddress(address);
    sample[@"matrixType"] = resolvedMatrixType;
    sample[@"rowMajorScore"] = @(rowScore);
    sample[@"columnMajorScore"] = @(columnScore);
    sample[@"staticScore"] = @(MAX(rowScore, columnScore));
    sample[@"preferredLayout"] = columnScore > rowScore ? @"column_major" : @"row_major";
    sample[@"elements"] = VCAIMatrixValidationElementsArray(elements);
    return [sample copy];
}

+ (NSArray<NSDictionary *> *)_matrixValidationRankedCandidatesForSession:(NSDictionary *)session
                                                     includeSamplePreview:(BOOL)includeSamplePreview {
    NSArray<NSDictionary *> *candidates = [session[@"candidates"] isKindOfClass:[NSArray class]] ? session[@"candidates"] : @[];
    NSString *expectedMotion = VCAIMatrixValidationMotionNormalized(VCAITrimmedString(session[@"expectedMotion"]));
    NSMutableArray<NSDictionary *> *ranked = [NSMutableArray new];

    for (NSDictionary *candidate in candidates) {
        NSArray<NSDictionary *> *samples = [candidate[@"samples"] isKindOfClass:[NSArray class]] ? candidate[@"samples"] : @[];
        NSMutableArray<NSDictionary *> *successfulSamples = [NSMutableArray new];
        NSMutableArray<NSString *> *layouts = [NSMutableArray new];
        NSMutableArray<NSString *> *notes = [NSMutableArray new];

        double minValues[16] = {0};
        double maxValues[16] = {0};
        double meanAbsValues[16] = {0};
        for (NSUInteger idx = 0; idx < 16; idx++) {
            minValues[idx] = DBL_MAX;
            maxValues[idx] = -DBL_MAX;
            meanAbsValues[idx] = 0.0;
        }

        double staticScoreSum = 0.0;
        double staticScoreMin = DBL_MAX;
        NSUInteger failedSamples = 0;

        for (NSDictionary *sample in samples) {
            if (![sample[@"success"] boolValue]) {
                failedSamples++;
                continue;
            }

            NSArray *elements = [sample[@"elements"] isKindOfClass:[NSArray class]] ? sample[@"elements"] : nil;
            if (elements.count < 16) {
                failedSamples++;
                continue;
            }

            [successfulSamples addObject:sample];
            double staticScore = [sample[@"staticScore"] respondsToSelector:@selector(doubleValue)] ? [sample[@"staticScore"] doubleValue] : 0.0;
            staticScoreSum += staticScore;
            staticScoreMin = MIN(staticScoreMin, staticScore);

            NSString *layout = VCAITrimmedString(sample[@"preferredLayout"]);
            if (layout.length > 0) [layouts addObject:layout];

            for (NSUInteger idx = 0; idx < 16; idx++) {
                double value = [elements[idx] respondsToSelector:@selector(doubleValue)] ? [elements[idx] doubleValue] : 0.0;
                minValues[idx] = MIN(minValues[idx], value);
                maxValues[idx] = MAX(maxValues[idx], value);
                meanAbsValues[idx] += fabs(value);
            }
        }

        NSUInteger totalSamples = samples.count;
        NSUInteger successfulCount = successfulSamples.count;
        double successRatio = totalSamples > 0 ? ((double)successfulCount / (double)totalSamples) : 0.0;
        NSString *matrixType = VCAIStructTypeNormalized(VCAITrimmedString(candidate[@"matrixType"]));
        if (matrixType.length == 0) matrixType = @"matrix4x4f";
        double absThreshold = VCAIMatrixValidationAbsoluteThreshold(matrixType);

        NSUInteger stableElementCount = 0;
        NSUInteger dynamicElementCount = 0;
        if (successfulCount > 0) {
            for (NSUInteger idx = 0; idx < 16; idx++) {
                double range = maxValues[idx] - minValues[idx];
                double averageMagnitude = meanAbsValues[idx] / (double)successfulCount;
                double stableThreshold = MAX(absThreshold, averageMagnitude * 0.02);
                double dynamicThreshold = MAX(absThreshold * 6.0, averageMagnitude * 0.08);
                if (range <= stableThreshold) stableElementCount++;
                if (range >= dynamicThreshold) dynamicElementCount++;
            }
        }

        NSUInteger pairCount = 0;
        NSUInteger deadPairCount = 0;
        NSUInteger chaoticPairCount = 0;
        double changedElementSum = 0.0;
        double totalDeltaSum = 0.0;
        double maxDeltaSum = 0.0;

        for (NSUInteger sampleIndex = 1; sampleIndex < successfulSamples.count; sampleIndex++) {
            NSArray *previous = [successfulSamples[sampleIndex - 1][@"elements"] isKindOfClass:[NSArray class]] ? successfulSamples[sampleIndex - 1][@"elements"] : nil;
            NSArray *current = [successfulSamples[sampleIndex][@"elements"] isKindOfClass:[NSArray class]] ? successfulSamples[sampleIndex][@"elements"] : nil;
            if (previous.count < 16 || current.count < 16) continue;

            NSUInteger changedCount = 0;
            double totalDelta = 0.0;
            double maxDelta = 0.0;
            for (NSUInteger idx = 0; idx < 16; idx++) {
                double lhs = [previous[idx] respondsToSelector:@selector(doubleValue)] ? [previous[idx] doubleValue] : 0.0;
                double rhs = [current[idx] respondsToSelector:@selector(doubleValue)] ? [current[idx] doubleValue] : 0.0;
                double delta = fabs(rhs - lhs);
                totalDelta += delta;
                maxDelta = MAX(maxDelta, delta);
                if (delta > VCAIMatrixValidationRelativeThreshold(lhs, rhs, matrixType)) changedCount++;
            }

            changedElementSum += changedCount;
            totalDeltaSum += totalDelta;
            maxDeltaSum += maxDelta;
            if (changedCount == 0 || totalDelta < absThreshold * 8.0) deadPairCount++;
            if (changedCount >= 15) chaoticPairCount++;
            pairCount++;
        }

        double staticScoreAverage = successfulCount > 0 ? (staticScoreSum / (double)successfulCount) : -1000.0;
        if (staticScoreMin == DBL_MAX) staticScoreMin = staticScoreAverage;
        double averageChangedElements = pairCount > 0 ? (changedElementSum / (double)pairCount) : 0.0;
        double averagePairDelta = pairCount > 0 ? (totalDeltaSum / (double)pairCount) : 0.0;
        double averagePairMaxDelta = pairCount > 0 ? (maxDeltaSum / (double)pairCount) : 0.0;

        NSString *dominantLayout = VCAITrimmedString(candidate[@"preferredLayout"]);
        double layoutAgreement = 0.0;
        if (layouts.count > 0) {
            NSUInteger rowCount = 0;
            NSUInteger columnCount = 0;
            for (NSString *layout in layouts) {
                if ([layout isEqualToString:@"column_major"]) columnCount++;
                else rowCount++;
            }
            if (columnCount > rowCount) {
                dominantLayout = @"column_major";
                layoutAgreement = (double)columnCount / (double)layouts.count;
            } else {
                dominantLayout = @"row_major";
                layoutAgreement = (double)rowCount / (double)layouts.count;
            }
        }
        if (dominantLayout.length == 0) dominantLayout = @"auto";

        double validationScore = 0.0;
        validationScore += MAX(-40.0, MIN(staticScoreAverage * 1.6, 80.0));
        validationScore += layoutAgreement * 12.0;
        validationScore += successRatio * 10.0;
        if (pairCount == 0) {
            validationScore -= 30.0;
        } else {
            validationScore += MIN(averageChangedElements * 1.4, 18.0);
            validationScore += MIN(averagePairDelta * 10.0, 12.0);
            validationScore += MIN(averagePairMaxDelta * 6.0, 8.0);
        }

        if ([expectedMotion isEqualToString:@"rotate_only"]) {
            if (dynamicElementCount >= 4 && dynamicElementCount <= 12) validationScore += 16.0;
            else if (dynamicElementCount >= 2 && dynamicElementCount <= 14) validationScore += 8.0;
            else validationScore -= 10.0;

            if (stableElementCount >= 2 && stableElementCount <= 10) validationScore += 10.0;
            else if (stableElementCount == 0) validationScore -= 12.0;
        } else if ([expectedMotion isEqualToString:@"zoom_only"]) {
            if (dynamicElementCount >= 1 && dynamicElementCount <= 6) validationScore += 16.0;
            else if (dynamicElementCount > 10) validationScore -= 10.0;
            if (stableElementCount >= 6) validationScore += 8.0;
        } else if ([expectedMotion isEqualToString:@"move_only"]) {
            if (dynamicElementCount >= 3 && dynamicElementCount <= 12) validationScore += 12.0;
            if (stableElementCount >= 2) validationScore += 6.0;
        } else {
            if (dynamicElementCount >= 3 && dynamicElementCount <= 14) validationScore += 12.0;
            if (stableElementCount >= 1 && stableElementCount <= 10) validationScore += 6.0;
        }

        validationScore -= deadPairCount * 8.0;
        validationScore -= chaoticPairCount * 6.0;
        if (staticScoreMin < 6.0) validationScore -= 8.0;
        if (successfulCount == 0) validationScore = -1000.0;

        if (successfulCount == 0) {
            [notes addObject:@"All captures failed to read a full 4x4 matrix from this address."];
        } else {
            if (pairCount == 0) {
                [notes addObject:@"Only the baseline capture is available. Capture at least one changed camera pose."];
            }
            if (dynamicElementCount >= 4 && dynamicElementCount <= 12) {
                [notes addObject:@"A focused subset of matrix elements changed across captures, which is a good camera-matrix sign."];
            } else if (dynamicElementCount <= 1) {
                [notes addObject:@"The matrix barely moved across captures, so this address may be static or unrelated."];
            } else if (dynamicElementCount >= 14) {
                [notes addObject:@"Nearly every element changed, which can indicate noisy or unrelated data."];
            }
            if (stableElementCount >= 2) {
                [notes addObject:@"Some elements stayed comparatively stable while others moved."];
            }
            if (layoutAgreement >= 0.75) {
                [notes addObject:[NSString stringWithFormat:@"Layout stayed mostly %@ across captures.", dominantLayout]];
            }
            if (deadPairCount > 0) {
                [notes addObject:@"One or more capture pairs showed almost no effective motion."];
            }
            if (chaoticPairCount > 0) {
                [notes addObject:@"One or more capture pairs changed almost every element at once."];
            }
        }
        if (failedSamples > 0) {
            [notes addObject:[NSString stringWithFormat:@"%lu capture(s) could not be read cleanly.", (unsigned long)failedSamples]];
        }

        NSMutableDictionary *entry = [@{
            @"address": candidate[@"address"] ?: @"",
            @"moduleName": candidate[@"moduleName"] ?: @"",
            @"rva": candidate[@"rva"] ?: @"",
            @"matrixType": matrixType,
            @"sampleCount": @(totalSamples),
            @"successfulSampleCount": @(successfulCount),
            @"dominantLayout": dominantLayout,
            @"layoutAgreement": @(layoutAgreement),
            @"initialStaticScore": candidate[@"initialStaticScore"] ?: @0,
            @"staticScoreAverage": @(staticScoreAverage),
            @"staticScoreMinimum": @(staticScoreMin),
            @"averageChangedElements": @(averageChangedElements),
            @"averagePairDelta": @(averagePairDelta),
            @"averagePairMaxDelta": @(averagePairMaxDelta),
            @"dynamicElementCount": @(dynamicElementCount),
            @"stableElementCount": @(stableElementCount),
            @"deadPairCount": @(deadPairCount),
            @"chaoticPairCount": @(chaoticPairCount),
            @"validationScore": @(validationScore),
            @"notes": [notes copy]
        } mutableCopy];

        NSDictionary *lastSuccessfulSample = successfulSamples.lastObject;
        if ([lastSuccessfulSample isKindOfClass:[NSDictionary class]]) {
            entry[@"latestStaticScore"] = lastSuccessfulSample[@"staticScore"] ?: @0;
            entry[@"latestPreferredLayout"] = lastSuccessfulSample[@"preferredLayout"] ?: @"";
        }

        if (includeSamplePreview) {
            NSMutableArray<NSDictionary *> *preview = [NSMutableArray new];
            for (NSDictionary *sample in VCAITail(samples, MIN((NSUInteger)5, samples.count))) {
                NSMutableDictionary *previewItem = [@{
                    @"label": sample[@"label"] ?: @"",
                    @"success": sample[@"success"] ?: @NO
                } mutableCopy];
                if ([sample[@"success"] boolValue]) {
                    previewItem[@"staticScore"] = sample[@"staticScore"] ?: @0;
                    previewItem[@"preferredLayout"] = sample[@"preferredLayout"] ?: @"";
                } else if (VCAITrimmedString(sample[@"error"]).length > 0) {
                    previewItem[@"error"] = sample[@"error"];
                }
                [preview addObject:[previewItem copy]];
            }
            entry[@"samplePreview"] = [preview copy];
        }

        [ranked addObject:[entry copy]];
    }

    NSArray<NSDictionary *> *sorted = [ranked sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *lhs, NSDictionary *rhs) {
        double left = [lhs[@"validationScore"] respondsToSelector:@selector(doubleValue)] ? [lhs[@"validationScore"] doubleValue] : -DBL_MAX;
        double right = [rhs[@"validationScore"] respondsToSelector:@selector(doubleValue)] ? [rhs[@"validationScore"] doubleValue] : -DBL_MAX;
        if (left > right) return NSOrderedAscending;
        if (left < right) return NSOrderedDescending;
        return NSOrderedSame;
    }];

    NSMutableArray<NSDictionary *> *finalItems = [NSMutableArray new];
    NSUInteger rank = 1;
    for (NSDictionary *entry in sorted ?: @[]) {
        NSMutableDictionary *rankedEntry = [entry mutableCopy];
        rankedEntry[@"rank"] = @(rank);
        [finalItems addObject:[rankedEntry copy]];
        rank++;
    }
    return [finalItems copy];
}

+ (NSDictionary *)_matrixValidationSessionSummary:(NSDictionary *)session
                                rankedCandidates:(NSArray<NSDictionary *> *)rankedCandidates {
    NSArray<NSString *> *captureLabels = [session[@"captureLabels"] isKindOfClass:[NSArray class]] ? session[@"captureLabels"] : @[];
    NSArray<NSDictionary *> *candidates = [session[@"candidates"] isKindOfClass:[NSArray class]] ? session[@"candidates"] : @[];

    NSMutableDictionary *payload = [@{
        @"sessionID": session[@"sessionID"] ?: @"",
        @"matrixType": session[@"matrixType"] ?: @"matrix4x4f",
        @"expectedMotion": session[@"expectedMotion"] ?: @"rotate_only",
        @"captureCount": @(captureLabels.count),
        @"captureLabels": captureLabels,
        @"candidateCount": @(candidates.count),
        @"createdAt": session[@"createdAt"] ?: @0,
        @"updatedAt": session[@"updatedAt"] ?: @0
    } mutableCopy];

    NSDictionary *topCandidate = [rankedCandidates.firstObject isKindOfClass:[NSDictionary class]] ? rankedCandidates.firstObject : nil;
    if (topCandidate) {
        payload[@"topCandidate"] = @{
            @"rank": topCandidate[@"rank"] ?: @1,
            @"address": topCandidate[@"address"] ?: @"",
            @"validationScore": topCandidate[@"validationScore"] ?: @0,
            @"dominantLayout": topCandidate[@"dominantLayout"] ?: @""
        };
    }

    if (captureLabels.count <= 1) {
        payload[@"nextSuggestedStep"] = @"Rotate or tilt the camera to a clearly different angle, then call matrix_validate capture again.";
    } else if (captureLabels.count < 4) {
        payload[@"nextSuggestedStep"] = @"Capture 1-2 more labeled motions such as yaw_right or pitch_up to improve confidence.";
    } else {
        payload[@"nextSuggestedStep"] = @"Call matrix_validate rank to pick the strongest candidate and move on to project_3d.";
    }

    return [payload copy];
}

+ (NSDictionary *)_executeMatrixValidationActionForToolCall:(VCToolCall *)toolCall {
    NSDictionary *params = toolCall.params ?: @{};
    NSString *action = VCAIMatrixValidationActionNormalized(VCAIStringParam(params, @[@"action", @"mode", @"operation"]));

    if ([action isEqualToString:@"clear"]) {
        NSMutableDictionary *session = [self _matrixValidationSessionStorage];
        NSString *clearedSessionID = VCAITrimmedString(session[@"sessionID"]);
        [session removeAllObjects];
        NSDictionary *payload = @{
            @"queryType": @"matrix_validate",
            @"action": @"clear",
            @"cleared": @YES,
            @"sessionID": clearedSessionID ?: @""
        };
        NSString *summary = clearedSessionID.length > 0
            ? [NSString stringWithFormat:@"Cleared matrix validation session %@", clearedSessionID]
            : @"No active matrix validation session was present.";
        return VCAISuccessResult(toolCall, summary, payload, nil);
    }

    if ([action isEqualToString:@"start"]) {
        NSString *matrixType = VCAIStructTypeNormalized(VCAIStringParam(params, @[@"matrixType", @"matrix_type", @"structType", @"struct_type", @"type"]));
        if (matrixType.length == 0) matrixType = @"matrix4x4f";
        NSUInteger limit = VCAIUnsignedParam(params, @[@"limit", @"candidateLimit", @"candidate_limit"], 6, 12);
        NSArray<NSDictionary *> *candidates = [self _matrixValidationCandidatesFromParams:params defaultMatrixType:matrixType limit:limit];
        if (candidates.count == 0) {
            return VCAIErrorResult(toolCall, @"matrix_validate start needs at least one readable candidate address or candidate object.");
        }

        NSString *expectedMotion = VCAIMatrixValidationMotionNormalized(VCAIStringParam(params, @[@"expectedMotion", @"motion", @"motionType", @"motion_type"]));
        NSString *baselineLabel = VCAIMatrixValidationCaptureLabel(VCAIStringParam(params, @[@"label", @"baselineLabel", @"baseline_label"]), 0);

        NSMutableArray<NSMutableDictionary *> *sessionCandidates = [NSMutableArray new];
        NSUInteger readableCount = 0;
        for (NSDictionary *candidate in candidates) {
            NSMutableDictionary *mutableCandidate = [candidate mutableCopy];
            NSDictionary *baselineSample = [self _matrixValidationCapturedSampleForCandidate:mutableCandidate
                                                                                       label:baselineLabel
                                                                                  matrixType:mutableCandidate[@"matrixType"]];
            mutableCandidate[@"samples"] = [NSMutableArray arrayWithObject:baselineSample ?: @{}];
            if ([baselineSample[@"success"] boolValue]) readableCount++;
            [sessionCandidates addObject:mutableCandidate];
        }

        if (readableCount == 0) {
            return VCAIErrorResult(toolCall, @"matrix_validate start could not read a full matrix from any candidate address.");
        }

        NSMutableDictionary *session = [self _matrixValidationSessionStorage];
        [session removeAllObjects];
        session[@"sessionID"] = [[NSUUID UUID] UUIDString];
        session[@"queryType"] = @"matrix_validate";
        session[@"matrixType"] = matrixType;
        session[@"expectedMotion"] = expectedMotion;
        session[@"createdAt"] = @([[NSDate date] timeIntervalSince1970]);
        session[@"updatedAt"] = session[@"createdAt"];
        session[@"captureLabels"] = [NSMutableArray arrayWithObject:baselineLabel];
        session[@"candidates"] = sessionCandidates;

        NSArray<NSDictionary *> *rankedCandidates = [self _matrixValidationRankedCandidatesForSession:session includeSamplePreview:YES];
        NSDictionary *payload = @{
            @"queryType": @"matrix_validate",
            @"action": @"start",
            @"session": [self _matrixValidationSessionSummary:session rankedCandidates:rankedCandidates],
            @"readableCandidateCount": @(readableCount),
            @"returnedCount": @(rankedCandidates.count),
            @"suggestedNextLabels": @[@"yaw_left", @"yaw_right", @"pitch_up", @"pitch_down"],
            @"candidates": rankedCandidates
        };
        NSString *summary = [NSString stringWithFormat:@"Started matrix validation with a %@ baseline across %lu/%lu candidate(s)",
                             baselineLabel,
                             (unsigned long)readableCount,
                             (unsigned long)candidates.count];
        return VCAISuccessResult(toolCall, summary, payload, nil);
    }

    NSMutableDictionary *session = [self _matrixValidationMutableSessionMatchingParams:params errorMessage:nil];
    if (!session) {
        NSString *errorMessage = nil;
        [self _matrixValidationMutableSessionMatchingParams:params errorMessage:&errorMessage];
        return VCAIErrorResult(toolCall, errorMessage ?: @"No active matrix validation session.");
    }

    if ([action isEqualToString:@"capture"]) {
        NSMutableArray *captureLabels = [session[@"captureLabels"] isKindOfClass:[NSMutableArray class]]
            ? session[@"captureLabels"]
            : [NSMutableArray arrayWithArray:([session[@"captureLabels"] isKindOfClass:[NSArray class]] ? session[@"captureLabels"] : @[])];
        NSString *label = VCAIMatrixValidationCaptureLabel(VCAIStringParam(params, @[@"label"]), captureLabels.count);
        NSMutableArray *sessionCandidates = [session[@"candidates"] isKindOfClass:[NSMutableArray class]]
            ? session[@"candidates"]
            : [NSMutableArray arrayWithArray:([session[@"candidates"] isKindOfClass:[NSArray class]] ? session[@"candidates"] : @[])];

        NSUInteger readableCount = 0;
        for (NSUInteger idx = 0; idx < sessionCandidates.count; idx++) {
            NSMutableDictionary *candidate = [sessionCandidates[idx] isKindOfClass:[NSMutableDictionary class]]
                ? sessionCandidates[idx]
                : [sessionCandidates[idx] mutableCopy];
            NSMutableArray *samples = [candidate[@"samples"] isKindOfClass:[NSMutableArray class]]
                ? candidate[@"samples"]
                : [NSMutableArray arrayWithArray:([candidate[@"samples"] isKindOfClass:[NSArray class]] ? candidate[@"samples"] : @[])];
            NSDictionary *sample = [self _matrixValidationCapturedSampleForCandidate:candidate
                                                                               label:label
                                                                          matrixType:candidate[@"matrixType"]];
            [samples addObject:sample ?: @{}];
            candidate[@"samples"] = samples;
            sessionCandidates[idx] = candidate;
            if ([sample[@"success"] boolValue]) readableCount++;
        }

        [captureLabels addObject:label];
        session[@"captureLabels"] = captureLabels;
        session[@"candidates"] = sessionCandidates;
        session[@"updatedAt"] = @([[NSDate date] timeIntervalSince1970]);

        NSArray<NSDictionary *> *rankedCandidates = [self _matrixValidationRankedCandidatesForSession:session includeSamplePreview:YES];
        NSDictionary *payload = @{
            @"queryType": @"matrix_validate",
            @"action": @"capture",
            @"label": label ?: @"",
            @"readableCandidateCount": @(readableCount),
            @"session": [self _matrixValidationSessionSummary:session rankedCandidates:rankedCandidates],
            @"returnedCount": @(rankedCandidates.count),
            @"candidates": rankedCandidates
        };
        NSString *summary = [NSString stringWithFormat:@"Captured %@ for %lu/%lu matrix candidate(s)",
                             label,
                             (unsigned long)readableCount,
                             (unsigned long)sessionCandidates.count];
        return VCAISuccessResult(toolCall, summary, payload, nil);
    }

    NSArray<NSDictionary *> *rankedCandidates = [self _matrixValidationRankedCandidatesForSession:session includeSamplePreview:YES];
    if ([action isEqualToString:@"status"]) {
        NSDictionary *payload = @{
            @"queryType": @"matrix_validate",
            @"action": @"status",
            @"session": [self _matrixValidationSessionSummary:session rankedCandidates:rankedCandidates],
            @"returnedCount": @(rankedCandidates.count),
            @"candidates": rankedCandidates
        };
        NSString *summary = [NSString stringWithFormat:@"Matrix validation session %@ has %@ capture(s) across %@ candidate(s)",
                             session[@"sessionID"] ?: @"",
                             @([session[@"captureLabels"] isKindOfClass:[NSArray class]] ? [(NSArray *)session[@"captureLabels"] count] : 0),
                             @(rankedCandidates.count)];
        return VCAISuccessResult(toolCall, summary, payload, nil);
    }

    if ([action isEqualToString:@"rank"]) {
        NSUInteger captureCount = [session[@"captureLabels"] isKindOfClass:[NSArray class]] ? [(NSArray *)session[@"captureLabels"] count] : 0;
        double topScore = [rankedCandidates.firstObject[@"validationScore"] respondsToSelector:@selector(doubleValue)]
            ? [rankedCandidates.firstObject[@"validationScore"] doubleValue] : -DBL_MAX;
        double secondScore = rankedCandidates.count > 1 && [rankedCandidates[1][@"validationScore"] respondsToSelector:@selector(doubleValue)]
            ? [rankedCandidates[1][@"validationScore"] doubleValue] : -DBL_MAX;
        double scoreGap = (isfinite(topScore) && isfinite(secondScore)) ? (topScore - secondScore) : 0.0;

        NSString *confidence = @"low";
        if (captureCount >= 4 && scoreGap >= 12.0) confidence = @"high";
        else if (captureCount >= 3 && scoreGap >= 6.0) confidence = @"medium";

        NSDictionary *payload = @{
            @"queryType": @"matrix_validate",
            @"action": @"rank",
            @"confidence": confidence,
            @"scoreGap": @(scoreGap),
            @"session": [self _matrixValidationSessionSummary:session rankedCandidates:rankedCandidates],
            @"recommendedCandidate": rankedCandidates.firstObject ?: @{},
            @"returnedCount": @(rankedCandidates.count),
            @"candidates": rankedCandidates
        };
        NSString *summary = rankedCandidates.count > 0
            ? [NSString stringWithFormat:@"Ranked %lu matrix candidate(s); top candidate is %@ with %@ confidence",
               (unsigned long)rankedCandidates.count,
               rankedCandidates.firstObject[@"address"] ?: @"unknown",
               confidence]
            : @"No matrix candidates are active in the validation session.";
        return VCAISuccessResult(toolCall, summary, payload, nil);
    }

    return VCAIErrorResult(toolCall, [NSString stringWithFormat:@"Unsupported matrix_validate action: %@", action ?: @""]);
}

+ (NSDictionary *)_executeMemoryQuery:(VCToolCall *)toolCall {
    NSDictionary *params = toolCall.params ?: @{};
    NSString *queryType = [VCAIStringParam(params, @[@"queryType", @"query_type", @"mode"]) lowercaseString];
    if (queryType.length == 0) queryType = @"address_context";

    uintptr_t address = VCAIAddressParam(params, @[@"address", @"targetAddress", @"target_address"]);
    VCMemRegion *region = nil;
    NSString *moduleName = nil;
    uint64_t rva = 0;
    NSString *blockedReason = nil;
    if (address > 0) {
        region = [self _regionContainingAddress:address];
        rva = [[VCProcessInfo shared] runtimeToRva:(uint64_t)address module:&moduleName];
        blockedReason = [VCPromptLeakGuard blockedToolReasonForMemoryModuleName:moduleName address:(unsigned long long)address];
        if (blockedReason.length > 0) return VCAIErrorResult(toolCall, blockedReason);
    }

    if ([queryType isEqualToString:@"address_context"]) {
        if (address == 0) return VCAIErrorResult(toolCall, @"query_memory address_context requires a non-zero address");
        NSDictionary *payload = @{
            @"queryType": queryType,
            @"address": VCAIHexAddress(address),
            @"region": VCAIMemoryRegionDictionary(region),
            @"moduleName": moduleName ?: @"",
            @"rva": rva > 0 ? VCAIHexAddress(rva) : @""
        };
        NSString *summary = region
            ? [NSString stringWithFormat:@"Resolved %@ into %@ memory", VCAIHexAddress(address), region.protection ?: @"mapped"]
            : [NSString stringWithFormat:@"Address %@ is not inside a known region", VCAIHexAddress(address)];
        return VCAISuccessResult(toolCall, summary, payload, nil);
    }

    if ([queryType isEqualToString:@"read_value"]) {
        if (address == 0) return VCAIErrorResult(toolCall, @"query_memory read_value requires a non-zero address");
        NSString *typeEncoding = VCAIStringParam(params, @[@"typeEncoding", @"type_encoding", @"encoding"]);
        if (!VCAIEncodingIsSafeForRawRead(typeEncoding)) {
            return VCAIErrorResult(toolCall, @"query_memory read_value only supports conservative primitive, pointer, and common struct encodings");
        }
        if (!region || [region.protection rangeOfString:@"r"].location == NSNotFound) {
            return VCAIErrorResult(toolCall, [NSString stringWithFormat:@"Address %@ is not inside a readable region", VCAIHexAddress(address)]);
        }

        NSUInteger byteSize = VCAIByteSizeForEncoding(typeEncoding);
        if (byteSize == 0) {
            return VCAIErrorResult(toolCall, [NSString stringWithFormat:@"Could not determine a safe byte size for encoding %@", typeEncoding]);
        }
        if ((uint64_t)address + byteSize > region.end) {
            return VCAIErrorResult(toolCall, [NSString stringWithFormat:@"Address %@ plus %@ bytes crosses the current region boundary", VCAIHexAddress(address), @(byteSize)]);
        }

        NSString *value = [VCValueReader readValueAtAddress:address typeEncoding:typeEncoding] ?: @"";
        NSDictionary *payload = @{
            @"queryType": queryType,
            @"address": VCAIHexAddress(address),
            @"typeEncoding": typeEncoding,
            @"byteSize": @(byteSize),
            @"value": value,
            @"region": VCAIMemoryRegionDictionary(region),
            @"moduleName": moduleName ?: @"",
            @"rva": rva > 0 ? VCAIHexAddress(rva) : @""
        };
        NSString *summary = [NSString stringWithFormat:@"Read %@ at %@", typeEncoding, VCAIHexAddress(address)];
        return VCAISuccessResult(toolCall, summary, payload, nil);
    }

    if ([queryType isEqualToString:@"read_struct"]) {
        if (address == 0) return VCAIErrorResult(toolCall, @"query_memory read_struct requires a non-zero address");
        NSString *structType = VCAIStructTypeNormalized(VCAIStringParam(params, @[@"structType", @"struct_type", @"type"]));
        if (structType.length == 0) {
            return VCAIErrorResult(toolCall, @"query_memory read_struct requires a supported structType such as cgpoint, vector3f, or matrix4x4f.");
        }
        NSUInteger byteSize = VCAIStructByteSize(structType);
        if (byteSize == 0) {
            return VCAIErrorResult(toolCall, [NSString stringWithFormat:@"Unsupported structType %@", structType]);
        }

        NSString *readError = nil;
        NSData *data = [self _safeReadDataAtAddress:address length:byteSize error:&readError];
        if (!data) return VCAIErrorResult(toolCall, readError ?: @"Failed to read structured memory");

        NSDictionary *structPayload = [self _structuredValuePayloadForData:data structType:structType];
        if (!structPayload) {
            return VCAIErrorResult(toolCall, [NSString stringWithFormat:@"Could not decode %@ at %@", structType, VCAIHexAddress(address)]);
        }

        NSDictionary *payload = @{
            @"queryType": queryType,
            @"address": VCAIHexAddress(address),
            @"structType": structType,
            @"byteSize": @(byteSize),
            @"value": structPayload,
            @"region": VCAIMemoryRegionDictionary(region),
            @"moduleName": moduleName ?: @"",
            @"rva": rva > 0 ? VCAIHexAddress(rva) : @""
        };
        NSString *summary = [NSString stringWithFormat:@"Read %@ at %@", structType, VCAIHexAddress(address)];
        return VCAISuccessResult(toolCall, summary, payload, nil);
    }

    if ([queryType isEqualToString:@"matrix_validate"]) {
        return [self _executeMatrixValidationActionForToolCall:toolCall];
    }

    if ([queryType isEqualToString:@"matrix_scan"] || [queryType isEqualToString:@"camera_candidates"]) {
        NSString *matrixType = VCAIStructTypeNormalized(VCAIStringParam(params, @[@"matrixType", @"matrix_type", @"structType", @"struct_type", @"type"]));
        if (matrixType.length == 0) matrixType = @"matrix4x4f";
        NSUInteger matrixByteSize = VCAIStructByteSize(matrixType);
        if (matrixByteSize == 0) {
            return VCAIErrorResult(toolCall, [NSString stringWithFormat:@"Unsupported matrixType %@", matrixType]);
        }

        NSUInteger resultLimit = VCAIUnsignedParam(params, @[@"limit"], 12, 48);
        NSUInteger stepBytes = VCAIUnsignedParam(params, @[@"stepBytes", @"step_bytes"], [matrixType isEqualToString:@"matrix4x4d"] ? 32 : 16, 64);
        NSUInteger regionByteLimit = VCAIUnsignedParam(params, @[@"regionByteLimit", @"region_byte_limit"], 256 * 1024, 1024 * 1024);
        NSUInteger totalByteBudget = VCAIUnsignedParam(params, @[@"totalByteBudget", @"total_byte_budget"], 2 * 1024 * 1024, 8 * 1024 * 1024);
        NSString *protectionFilter = [VCAIStringParam(params, @[@"protection", @"protectionFilter", @"protection_filter"]) lowercaseString];
        NSString *moduleFilter = [VCAIStringParam(params, @[@"module", @"moduleName", @"module_name"]) lowercaseString];

        CGRect hostBounds = [VCOverlayRootViewController currentHostBounds];
        CGFloat viewportWidth = MAX(CGRectGetWidth(hostBounds), 1.0);
        CGFloat viewportHeight = MAX(CGRectGetHeight(hostBounds), 1.0);

        NSMutableArray<NSDictionary *> *candidates = [NSMutableArray new];
        NSUInteger regionsScanned = 0;
        NSUInteger bytesScanned = 0;

        for (VCMemRegion *scanRegion in [[VCProcessInfo shared] memoryRegions] ?: @[]) {
            if (bytesScanned >= totalByteBudget || candidates.count >= resultLimit * 2) break;
            NSString *protection = [VCAITrimmedString(scanRegion.protection) lowercaseString];
            if ([protection rangeOfString:@"r"].location == NSNotFound) continue;
            if (protectionFilter.length > 0) {
                if ([protection rangeOfString:protectionFilter].location == NSNotFound) continue;
            } else if ([protection rangeOfString:@"x"].location != NSNotFound) {
                continue;
            }

            uint64_t remainingBudget = totalByteBudget - bytesScanned;
            uint64_t regionSpan = MIN((uint64_t)scanRegion.size, (uint64_t)regionByteLimit);
            if (regionSpan == 0) continue;
            regionSpan = MIN(regionSpan, remainingBudget);
            if (regionSpan < matrixByteSize) continue;

            NSData *regionData = [self _safeReadDataAtAddress:(uintptr_t)scanRegion.start length:(NSUInteger)regionSpan error:nil];
            if (regionData.length < matrixByteSize) continue;
            regionsScanned += 1;
            bytesScanned += regionData.length;

            NSUInteger scanLimit = regionData.length - matrixByteSize;
            for (NSUInteger offset = 0; offset <= scanLimit; offset += MAX((NSUInteger)1, stepBytes)) {
                uint64_t candidateAddress = scanRegion.start + offset;
                NSString *ownerModule = nil;
                uint64_t candidateRva = [[VCProcessInfo shared] runtimeToRva:candidateAddress module:&ownerModule];
                if (moduleFilter.length > 0) {
                    NSString *moduleNameLower = [ownerModule.lowercaseString copy];
                    if (moduleNameLower.length == 0 || [moduleNameLower rangeOfString:moduleFilter].location == NSNotFound) continue;
                }
                NSString *blockedReason = [VCPromptLeakGuard blockedToolReasonForMemoryModuleName:ownerModule address:candidateAddress];
                if (blockedReason.length > 0) continue;

                NSData *slice = [regionData subdataWithRange:NSMakeRange(offset, matrixByteSize)];
                double elements[16] = {0};
                if (!VCAIMatrixElementsFromRawData(slice, matrixType, elements)) continue;

                double rowScore = VCAIMatrixProjectionScore(elements, NO, viewportWidth, viewportHeight);
                double columnScore = VCAIMatrixProjectionScore(elements, YES, viewportWidth, viewportHeight);
                double bestScore = MAX(rowScore, columnScore);
                if (!isfinite(bestScore) || bestScore < ([queryType isEqualToString:@"camera_candidates"] ? 12.0 : 10.0)) continue;

                NSMutableArray *flat = [NSMutableArray new];
                for (NSUInteger idx = 0; idx < 16; idx++) [flat addObject:@(elements[idx])];
                [candidates addObject:@{
                    @"address": VCAIHexAddress(candidateAddress),
                    @"moduleName": ownerModule ?: @"",
                    @"rva": candidateRva > 0 ? VCAIHexAddress(candidateRva) : @"",
                    @"matrixType": matrixType,
                    @"rowMajorScore": @(rowScore),
                    @"columnMajorScore": @(columnScore),
                    @"preferredLayout": (columnScore > rowScore ? @"column_major" : @"row_major"),
                    @"score": @(bestScore),
                    @"elements": [flat copy],
                    @"region": VCAIMemoryRegionDictionary(scanRegion)
                }];
            }
        }

        NSArray<NSDictionary *> *sorted = [candidates sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *lhs, NSDictionary *rhs) {
            double left = [lhs[@"score"] respondsToSelector:@selector(doubleValue)] ? [lhs[@"score"] doubleValue] : 0.0;
            double right = [rhs[@"score"] respondsToSelector:@selector(doubleValue)] ? [rhs[@"score"] doubleValue] : 0.0;
            if (left > right) return NSOrderedAscending;
            if (left < right) return NSOrderedDescending;
            return NSOrderedSame;
        }];
        if (sorted.count > resultLimit) {
            sorted = [sorted subarrayWithRange:NSMakeRange(0, resultLimit)];
        }

        NSDictionary *payload = @{
            @"queryType": queryType,
            @"matrixType": matrixType,
            @"returnedCount": @(sorted.count),
            @"regionsScanned": @(regionsScanned),
            @"bytesScanned": @(bytesScanned),
            @"protectionFilter": protectionFilter ?: @"",
            @"moduleFilter": moduleFilter ?: @"",
            @"candidates": sorted ?: @[]
        };
        NSString *summary = sorted.count > 0
            ? [NSString stringWithFormat:@"Found %lu plausible %@ candidate(s) after scanning %@ region(s)",
               (unsigned long)sorted.count,
               [queryType isEqualToString:@"camera_candidates"] ? @"camera/view-projection matrix" : @"matrix",
               @(regionsScanned)]
            : [NSString stringWithFormat:@"No plausible %@ were found in the scanned readable regions",
               [queryType isEqualToString:@"camera_candidates"] ? @"camera/view-projection matrices" : @"matrices"];
        return VCAISuccessResult(toolCall, summary, payload, nil);
    }

    if ([queryType isEqualToString:@"pointer_follow"]) {
        if (address == 0) return VCAIErrorResult(toolCall, @"query_memory pointer_follow requires a non-zero address");
        NSUInteger depth = VCAIUnsignedParam(params, @[@"depth", @"maxDepth", @"max_depth"], 3, 6);
        NSMutableArray<NSDictionary *> *hops = [NSMutableArray new];
        NSMutableSet<NSString *> *seenPointers = [NSMutableSet new];
        uintptr_t currentAddress = address;
        BOOL terminatedEarly = NO;
        NSString *terminationReason = @"";

        for (NSUInteger hopIndex = 0; hopIndex < depth; hopIndex++) {
            NSString *readError = nil;
            NSData *data = [self _safeReadDataAtAddress:currentAddress length:sizeof(uintptr_t) error:&readError];
            if (data.length < sizeof(uintptr_t)) {
                terminatedEarly = YES;
                terminationReason = readError ?: @"Could not read a pointer-sized value.";
                break;
            }

            uintptr_t pointedAddress = 0;
            [data getBytes:&pointedAddress length:sizeof(uintptr_t)];
            NSString *targetModuleName = nil;
            uint64_t targetRva = 0;
            VCMemRegion *targetRegion = nil;
            NSString *blockedTargetReason = nil;
            if (pointedAddress != 0) {
                targetRegion = [self _regionContainingAddress:pointedAddress];
                targetRva = [[VCProcessInfo shared] runtimeToRva:(uint64_t)pointedAddress module:&targetModuleName];
                blockedTargetReason = [VCPromptLeakGuard blockedToolReasonForMemoryModuleName:targetModuleName address:(unsigned long long)pointedAddress];
            }

            NSMutableDictionary *hop = [@{
                @"hop": @(hopIndex),
                @"slotAddress": VCAIHexAddress(currentAddress),
                @"pointerValue": pointedAddress > 0 ? VCAIHexAddress(pointedAddress) : @"0x0",
                @"targetRegion": VCAIMemoryRegionDictionary(targetRegion),
                @"moduleName": targetModuleName ?: @"",
                @"rva": targetRva > 0 ? VCAIHexAddress(targetRva) : @"",
                @"readable": @(targetRegion && [targetRegion.protection rangeOfString:@"r"].location != NSNotFound)
            } mutableCopy];
            if (blockedTargetReason.length > 0) {
                hop[@"redacted"] = @YES;
            }
            [hops addObject:[hop copy]];

            if (pointedAddress == 0) {
                terminatedEarly = YES;
                terminationReason = @"Reached a null pointer.";
                break;
            }
            if (blockedTargetReason.length > 0) {
                terminatedEarly = YES;
                terminationReason = blockedTargetReason;
                break;
            }

            NSString *pointerKey = VCAIHexAddress(pointedAddress);
            if ([seenPointers containsObject:pointerKey]) {
                terminatedEarly = YES;
                terminationReason = @"Detected a pointer loop.";
                break;
            }
            [seenPointers addObject:pointerKey];

            if (!targetRegion || [targetRegion.protection rangeOfString:@"r"].location == NSNotFound) {
                terminatedEarly = YES;
                terminationReason = @"The next pointer does not resolve into readable memory.";
                break;
            }
            currentAddress = pointedAddress;
        }

        NSDictionary *payload = @{
            @"queryType": queryType,
            @"address": VCAIHexAddress(address),
            @"depth": @(depth),
            @"returnedCount": @(hops.count),
            @"terminatedEarly": @(terminatedEarly),
            @"terminationReason": terminationReason ?: @"",
            @"hops": hops
        };
        NSString *summary = [NSString stringWithFormat:@"Followed %lu pointer hops from %@",
                             (unsigned long)hops.count,
                             VCAIHexAddress(address)];
        return VCAISuccessResult(toolCall, summary, payload, nil);
    }

    if ([queryType isEqualToString:@"hexdump"]) {
        if (address == 0) return VCAIErrorResult(toolCall, @"query_memory hexdump requires a non-zero address");
        NSUInteger length = VCAIUnsignedParam(params, @[@"length", @"byteCount", @"byte_count"], 64, 256);
        NSString *readError = nil;
        NSData *data = [self _safeReadDataAtAddress:address length:length error:&readError];
        if (!data) return VCAIErrorResult(toolCall, readError ?: @"Failed to read memory bytes");

        NSString *hexDump = [self _hexDumpStringForData:data startAddress:address];
        NSDictionary *payload = @{
            @"queryType": queryType,
            @"address": VCAIHexAddress(address),
            @"length": @(data.length),
            @"hexDump": hexDump ?: @"",
            @"region": VCAIMemoryRegionDictionary(region),
            @"moduleName": moduleName ?: @"",
            @"rva": rva > 0 ? VCAIHexAddress(rva) : @""
        };
        NSString *summary = [NSString stringWithFormat:@"Read %@ bytes from %@", @(data.length), VCAIHexAddress(address)];
        return VCAISuccessResult(toolCall, summary, payload, nil);
    }

    if ([queryType isEqualToString:@"snapshot_list"]) {
        NSUInteger limit = VCAIUnsignedParam(params, @[@"limit"], 20, 100);
        NSArray<NSDictionary *> *snapshots = [self _memorySnapshotSummariesWithLimit:limit];
        NSDictionary *payload = @{
            @"queryType": queryType,
            @"returnedCount": @(snapshots.count),
            @"snapshots": snapshots
        };
        NSString *summary = snapshots.count > 0
            ? [NSString stringWithFormat:@"Loaded %lu saved memory snapshots", (unsigned long)snapshots.count]
            : @"No saved memory snapshots were found";
        return VCAISuccessResult(toolCall, summary, payload, nil);
    }

    if ([queryType isEqualToString:@"snapshot_detail"]) {
        NSString *loadError = nil;
        NSDictionary *snapshot = [self _loadMemorySnapshotFromParams:params
                                                              idKeys:@[@"snapshotID", @"snapshotId"]
                                                            pathKeys:@[@"snapshotPath", @"snapshot_path"]
                                                       errorMessage:&loadError];
        if (!snapshot) return VCAIErrorResult(toolCall, loadError ?: @"Snapshot detail could not be loaded");

        NSMutableDictionary *detail = [snapshot mutableCopy];
        NSString *requestedEncoding = VCAITrimmedString(VCAIStringParam(params, @[@"typeEncoding", @"type_encoding", @"encoding"]));
        NSString *resolvedEncoding = requestedEncoding.length > 0 ? requestedEncoding : VCAITrimmedString(snapshot[@"typeEncoding"]);
        if (resolvedEncoding.length > 0 && !detail[@"typedValue"]) {
            NSData *bytes = VCAIDataFromHexString(snapshot[@"bytesHex"]);
            NSString *typedValue = [self _valueDescriptionForData:bytes typeEncoding:resolvedEncoding];
            if (typedValue.length > 0) {
                detail[@"typeEncoding"] = resolvedEncoding;
                detail[@"typedValue"] = typedValue;
            }
        }

        NSDictionary *reference = VCAIReferenceForFile(@"Memory Snapshot",
                                                       [NSString stringWithFormat:@"Memory Snapshot %@", snapshot[@"snapshotID"] ?: @"detail"],
                                                       @"json",
                                                       snapshot[@"path"] ?: @"",
                                                       @"Loaded saved memory snapshot detail.",
                                                       @{
                                                           @"snapshotID": snapshot[@"snapshotID"] ?: @"",
                                                           @"queryType": snapshot[@"queryType"] ?: @"snapshot"
                                                       });
        NSDictionary *payload = @{
            @"queryType": queryType,
            @"snapshot": [detail copy]
        };
        NSString *summary = [NSString stringWithFormat:@"Loaded %@ detail for %@",
                             snapshot[@"queryType"] ?: @"snapshot",
                             snapshot[@"snapshotID"] ?: @"snapshot"];
        return VCAISuccessResult(toolCall, summary, payload, reference);
    }

    if ([queryType isEqualToString:@"snapshot"]) {
        if (address == 0) return VCAIErrorResult(toolCall, @"query_memory snapshot requires a non-zero address");
        NSUInteger length = VCAIUnsignedParam(params, @[@"length", @"byteCount", @"byte_count"], 64, 256);
        NSString *typeEncoding = VCAIStringParam(params, @[@"typeEncoding", @"type_encoding", @"encoding"]);
        NSString *readError = nil;
        NSData *data = [self _safeReadDataAtAddress:address length:length error:&readError];
        if (!data) return VCAIErrorResult(toolCall, readError ?: @"Failed to read memory bytes");

        NSDictionary *snapshotPayload = [self _memorySnapshotPayloadForAddress:address
                                                                          data:data
                                                                        region:region
                                                                    moduleName:moduleName
                                                                           rva:rva
                                                                  typeEncoding:typeEncoding];
        NSString *title = [NSString stringWithFormat:@"Memory Snapshot %@", VCAIHexAddress(address)];
        NSString *saveError = nil;
        NSDictionary *artifact = [self _saveMemorySnapshotPayload:snapshotPayload title:title errorMessage:&saveError];
        if (!artifact) return VCAIErrorResult(toolCall, saveError ?: @"Failed to save memory snapshot");

        NSString *path = artifact[@"path"];
        NSDictionary *reference = VCAIReferenceForFile(@"Memory Snapshot",
                                                       title,
                                                       @"json",
                                                       path,
                                                       @"Saved bounded memory snapshot for later diffing.",
                                                       @{
                                                           @"snapshotID": snapshotPayload[@"snapshotID"] ?: @"",
                                                           @"address": snapshotPayload[@"address"] ?: @"",
                                                           @"length": snapshotPayload[@"length"] ?: @0
                                                       });
        NSDictionary *payload = @{
            @"queryType": queryType,
            @"snapshotID": snapshotPayload[@"snapshotID"] ?: @"",
            @"address": snapshotPayload[@"address"] ?: @"",
            @"length": snapshotPayload[@"length"] ?: @0,
            @"moduleName": snapshotPayload[@"moduleName"] ?: @"",
            @"rva": snapshotPayload[@"rva"] ?: @"",
            @"path": path ?: @"",
            @"hexDump": snapshotPayload[@"hexDump"] ?: @""
        };
        NSString *summary = [NSString stringWithFormat:@"Saved a %@-byte memory snapshot at %@",
                             snapshotPayload[@"length"] ?: @0,
                             snapshotPayload[@"address"] ?: VCAIHexAddress(address)];
        return VCAISuccessResult(toolCall, summary, payload, reference);
    }

    if ([queryType isEqualToString:@"diff_snapshot"]) {
        NSString *loadError = nil;
        NSDictionary *baselineSnapshot = [self _loadMemorySnapshotFromParams:params
                                                                      idKeys:@[@"snapshotID", @"snapshotId"]
                                                                    pathKeys:@[@"snapshotPath", @"snapshot_path"]
                                                               errorMessage:&loadError];
        if (!baselineSnapshot) return VCAIErrorResult(toolCall, loadError ?: @"Baseline snapshot could not be loaded");

        NSDictionary *comparisonSnapshot = [self _loadMemorySnapshotFromParams:params
                                                                        idKeys:@[@"otherSnapshotID", @"otherSnapshotId"]
                                                                      pathKeys:@[@"otherSnapshotPath", @"other_snapshot_path"]
                                                                 errorMessage:nil];

        NSData *comparisonBytes = nil;
        uintptr_t comparisonAddress = 0;
        NSString *comparisonName = @"live memory";
        if (comparisonSnapshot) {
            comparisonBytes = VCAIDataFromHexString(comparisonSnapshot[@"bytesHex"]);
            comparisonAddress = (uintptr_t)strtoull([VCAITrimmedString(comparisonSnapshot[@"address"]) UTF8String], NULL, 0);
            comparisonName = comparisonSnapshot[@"snapshotID"] ?: @"snapshot";
        } else {
            if (address == 0) {
                address = (uintptr_t)strtoull([VCAITrimmedString(baselineSnapshot[@"address"]) UTF8String], NULL, 0);
            }
            if (address == 0) return VCAIErrorResult(toolCall, @"diff_snapshot needs an address or a saved comparison snapshot");

            NSString *liveModuleName = nil;
            [[VCProcessInfo shared] runtimeToRva:(uint64_t)address module:&liveModuleName];
            NSString *liveBlockedReason = [VCPromptLeakGuard blockedToolReasonForMemoryModuleName:liveModuleName address:(unsigned long long)address];
            if (liveBlockedReason.length > 0) return VCAIErrorResult(toolCall, liveBlockedReason);

            id baselineLengthValue = baselineSnapshot[@"length"];
            NSUInteger length = [baselineLengthValue respondsToSelector:@selector(unsignedIntegerValue)] ? [baselineLengthValue unsignedIntegerValue] : 0;
            if (length == 0) length = VCAIUnsignedParam(params, @[@"length", @"byteCount", @"byte_count"], 64, 256);
            NSString *readError = nil;
            comparisonBytes = [self _safeReadDataAtAddress:address length:length error:&readError];
            if (!comparisonBytes) return VCAIErrorResult(toolCall, readError ?: @"Could not read live memory for diff");
            comparisonAddress = address;
        }

        NSDictionary *diffPayload = [self _memoryDiffPayloadFromSourceSnapshot:baselineSnapshot
                                                                comparisonName:comparisonName
                                                               comparisonBytes:comparisonBytes
                                                             comparisonAddress:comparisonAddress
                                                                  typeEncoding:VCAIStringParam(params, @[@"typeEncoding", @"type_encoding", @"encoding"])];
        if (!diffPayload) return VCAIErrorResult(toolCall, @"Could not compute a memory diff from the provided snapshots");

        NSMutableDictionary *artifactPayload = [diffPayload mutableCopy];
        artifactPayload[@"baselineSnapshotPath"] = baselineSnapshot[@"path"] ?: @"";
        artifactPayload[@"comparisonSnapshotPath"] = comparisonSnapshot[@"path"] ?: @"";
        NSString *title = [NSString stringWithFormat:@"Memory Diff %@", baselineSnapshot[@"snapshotID"] ?: @"snapshot"];
        NSString *saveError = nil;
        NSDictionary *artifact = [self _saveMemorySnapshotPayload:artifactPayload title:title errorMessage:&saveError];
        NSDictionary *reference = nil;
        if (artifact) {
            reference = VCAIReferenceForFile(@"Memory Diff",
                                             title,
                                             @"json",
                                             artifact[@"path"],
                                             @"Saved memory diff for later review.",
                                             @{
                                                 @"snapshotID": baselineSnapshot[@"snapshotID"] ?: @"",
                                                 @"comparisonName": comparisonName ?: @""
                                             });
        }

        NSString *summary = [NSString stringWithFormat:@"Computed a memory diff with %@ changed bytes",
                             diffPayload[@"changedByteCount"] ?: @0];
        return VCAISuccessResult(toolCall, summary, diffPayload, reference);
    }

    return VCAIErrorResult(toolCall, [NSString stringWithFormat:@"Unsupported query_memory queryType: %@", queryType ?: @""]);
}

+ (NSDictionary *)_executeMemoryBrowser:(VCToolCall *)toolCall {
    NSDictionary *params = toolCall.params ?: @{};
    NSString *action = [VCAIStringParam(params, @[@"action", @"queryType", @"query_type", @"mode"]) lowercaseString];
    if (action.length == 0) action = @"status";

    VCMemoryBrowserEngine *engine = [VCMemoryBrowserEngine shared];
    NSString *errorMessage = nil;
    NSDictionary *payload = nil;
    NSString *summary = @"";

    if ([action isEqualToString:@"status"]) {
        payload = [engine activeSessionSummary];
        summary = [engine hasActiveSession]
            ? [NSString stringWithFormat:@"Memory browser is active at %@",
               payload[@"currentAddress"] ?: @""]
            : @"No active memory browser session";
    } else if ([action isEqualToString:@"next"]) {
        NSUInteger pageSize = VCAIUnsignedParam(params, @[@"pageSize", @"page_size", @"limit"], 256, 1024);
        payload = [engine stepPageBy:1 pageSize:pageSize errorMessage:&errorMessage];
        if (!payload) return VCAIErrorResult(toolCall, errorMessage ?: @"Could not load the next memory page");
        summary = [NSString stringWithFormat:@"Loaded the next memory page at %@",
                   payload[@"address"] ?: @""];
    } else if ([action isEqualToString:@"prev"]) {
        NSUInteger pageSize = VCAIUnsignedParam(params, @[@"pageSize", @"page_size", @"limit"], 256, 1024);
        payload = [engine stepPageBy:-1 pageSize:pageSize errorMessage:&errorMessage];
        if (!payload) return VCAIErrorResult(toolCall, errorMessage ?: @"Could not load the previous memory page");
        summary = [NSString stringWithFormat:@"Loaded the previous memory page at %@",
                   payload[@"address"] ?: @""];
    } else {
        uintptr_t address = VCAIAddressParam(params, @[@"address", @"baseAddress", @"base_address"]);
        if (address == 0 && [action isEqualToString:@"page"] && [engine hasActiveSession]) {
            NSDictionary *session = [engine activeSessionSummary];
            address = (uintptr_t)strtoull([VCAITrimmedString(session[@"currentAddress"]) UTF8String], NULL, 0);
        }
        NSUInteger pageSize = VCAIUnsignedParam(params, @[@"pageSize", @"page_size"], 256, 1024);
        NSUInteger length = VCAIUnsignedParam(params, @[@"length", @"readLength", @"read_length"], pageSize, 1024);
        BOOL updateSession = ![action isEqualToString:@"peek"];
        if (action.length == 0 || [action isEqualToString:@"goto"] || [action isEqualToString:@"page"] || [action isEqualToString:@"peek"]) {
            payload = [engine browseAtAddress:(uint64_t)address
                                     pageSize:pageSize
                                       length:length
                                updateSession:updateSession
                                 errorMessage:&errorMessage];
            if (!payload) return VCAIErrorResult(toolCall, errorMessage ?: @"Could not browse memory at the requested address");
            if ([action isEqualToString:@"peek"]) {
                summary = [NSString stringWithFormat:@"Peeked %@ bytes at %@",
                           payload[@"readLength"] ?: @0,
                           payload[@"address"] ?: @""];
            } else {
                summary = [NSString stringWithFormat:@"Loaded %@ bytes at %@",
                           payload[@"readLength"] ?: @0,
                           payload[@"address"] ?: @""];
            }
            if ([action isEqualToString:@"goto"] || [action isEqualToString:@"page"]) {
                action = @"page";
            }
        } else {
            return VCAIErrorResult(toolCall, [NSString stringWithFormat:@"Unsupported memory_browser action: %@", action ?: @""]);
        }
    }

    NSMutableDictionary *enrichedPayload = [payload mutableCopy] ?: [NSMutableDictionary new];
    enrichedPayload[@"action"] = action;
    return VCAISuccessResult(toolCall, summary, [enrichedPayload copy], nil);
}

+ (NSDictionary *)_executeMemoryScan:(VCToolCall *)toolCall {
    NSDictionary *params = toolCall.params ?: @{};
    NSString *action = [VCAIStringParam(params, @[@"action", @"queryType", @"query_type", @"mode"]) lowercaseString];
    if (action.length == 0) action = @"status";

    VCMemoryScanEngine *engine = [VCMemoryScanEngine shared];
    NSString *errorMessage = nil;
    NSDictionary *payload = nil;
    NSString *summary = @"";

    if ([action isEqualToString:@"start"]) {
        NSString *scanMode = [VCAIStringParam(params, @[@"scanMode", @"scan_mode", @"mode"]) lowercaseString];
        payload = [engine startScanWithMode:scanMode
                                      value:VCAIStringParam(params, @[@"value", @"targetValue", @"target_value"])
                                   minValue:VCAIStringParam(params, @[@"minValue", @"min_value"])
                                   maxValue:VCAIStringParam(params, @[@"maxValue", @"max_value"])
                             dataTypeString:VCAIStringParam(params, @[@"dataType", @"data_type", @"type"])
                             floatTolerance:params[@"floatTolerance"] ?: params[@"float_tolerance"]
                                 groupRange:params[@"groupRange"] ?: params[@"group_range"]
                            groupAnchorMode:params[@"groupAnchorMode"] ?: params[@"group_anchor_mode"]
                                resultLimit:params[@"resultLimit"] ?: params[@"result_limit"]
                               errorMessage:&errorMessage];
        if (!payload) return VCAIErrorResult(toolCall, errorMessage ?: @"Could not start the memory scan");

        NSDictionary *session = [payload[@"session"] isKindOfClass:[NSDictionary class]] ? payload[@"session"] : @{};
        NSString *resolvedMode = VCAITrimmedString(session[@"scanMode"]);
        NSUInteger resultCount = [payload[@"resultCount"] respondsToSelector:@selector(unsignedIntegerValue)] ? [payload[@"resultCount"] unsignedIntegerValue] : 0;
        NSUInteger fuzzyCount = [payload[@"fuzzySnapshotAddressCount"] respondsToSelector:@selector(unsignedIntegerValue)] ? [payload[@"fuzzySnapshotAddressCount"] unsignedIntegerValue] : 0;
        if ([resolvedMode isEqualToString:@"fuzzy"]) {
            summary = [NSString stringWithFormat:@"Started a fuzzy memory scan snapshot across %lu writable addresses", (unsigned long)fuzzyCount];
        } else {
            summary = [NSString stringWithFormat:@"Started a %@ memory scan and found %lu candidates", resolvedMode.length > 0 ? resolvedMode : @"memory", (unsigned long)resultCount];
        }
    } else if ([action isEqualToString:@"refine"]) {
        payload = [engine refineScanWithMode:VCAIStringParam(params, @[@"filterMode", @"filter_mode", @"mode"])
                                       value:VCAIStringParam(params, @[@"value", @"targetValue", @"target_value"])
                                    minValue:VCAIStringParam(params, @[@"minValue", @"min_value"])
                                    maxValue:VCAIStringParam(params, @[@"maxValue", @"max_value"])
                              dataTypeString:VCAIStringParam(params, @[@"dataType", @"data_type", @"type"])
                                errorMessage:&errorMessage];
        if (!payload) return VCAIErrorResult(toolCall, errorMessage ?: @"Could not refine the memory scan");

        NSUInteger resultCount = [payload[@"resultCount"] respondsToSelector:@selector(unsignedIntegerValue)] ? [payload[@"resultCount"] unsignedIntegerValue] : 0;
        NSString *filterMode = VCAIStringParam(params, @[@"filterMode", @"filter_mode", @"mode"]);
        summary = [NSString stringWithFormat:@"Refined the memory scan with %@ and kept %lu candidates",
                   filterMode.length > 0 ? filterMode : @"the requested filter",
                   (unsigned long)resultCount];
    } else if ([action isEqualToString:@"results"]) {
        NSUInteger offset = VCAIUnsignedParam(params, @[@"offset"], 0, 1000000);
        NSUInteger limit = VCAIUnsignedParam(params, @[@"limit"], 24, 200);
        BOOL refreshValues = VCAIBoolParam(params, @[@"refreshValues", @"refresh_values"], YES);
        payload = [engine resultsWithOffset:offset limit:limit refreshValues:refreshValues errorMessage:&errorMessage];
        if (!payload) return VCAIErrorResult(toolCall, errorMessage ?: @"Could not load memory scan results");

        NSUInteger returnedCount = [payload[@"returnedCount"] respondsToSelector:@selector(unsignedIntegerValue)] ? [payload[@"returnedCount"] unsignedIntegerValue] : 0;
        NSUInteger totalCount = [payload[@"totalCount"] respondsToSelector:@selector(unsignedIntegerValue)] ? [payload[@"totalCount"] unsignedIntegerValue] : 0;
        summary = [NSString stringWithFormat:@"Loaded %lu memory scan candidates (total %lu)",
                   (unsigned long)returnedCount,
                   (unsigned long)totalCount];
    } else if ([action isEqualToString:@"clear"]) {
        payload = [engine clearScan];
        summary = @"Cleared the active memory scan session";
    } else if ([action isEqualToString:@"status"]) {
        payload = [engine activeSessionSummary];
        summary = [engine hasActiveSession]
            ? [NSString stringWithFormat:@"Memory scan session is active with %lu candidates",
               (unsigned long)[payload[@"resultCount"] unsignedIntegerValue]]
            : @"No active memory scan session";
    } else {
        return VCAIErrorResult(toolCall, [NSString stringWithFormat:@"Unsupported memory_scan action: %@", action ?: @""]);
    }

    NSMutableDictionary *enrichedPayload = [payload mutableCopy] ?: [NSMutableDictionary new];
    enrichedPayload[@"action"] = action;
    return VCAISuccessResult(toolCall, summary, [enrichedPayload copy], nil);
}

+ (NSDictionary *)_executePointerChain:(VCToolCall *)toolCall {
    NSDictionary *params = toolCall.params ?: @{};
    NSString *action = [VCAIStringParam(params, @[@"action", @"mode"]) lowercaseString];
    if (action.length == 0) action = @"resolve";

    NSMutableArray<NSNumber *> *offsets = [NSMutableArray new];
    id rawOffsets = params[@"offsets"] ?: params[@"chain"];
    if ([rawOffsets isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)rawOffsets) {
            if ([item isKindOfClass:[NSNumber class]]) {
                [offsets addObject:@([(NSNumber *)item longLongValue])];
            } else if ([item isKindOfClass:[NSString class]]) {
                NSString *text = VCAITrimmedString(item);
                if (text.length == 0) continue;
                [offsets addObject:@(strtoll(text.UTF8String, NULL, 0))];
            }
        }
    }

    uint64_t baseOffset = strtoull([VCAIStringParam(params, @[@"baseOffset", @"base_offset"]) UTF8String], NULL, 0);
    uint64_t baseAddress = VCAIAddressParam(params, @[@"baseAddress", @"base_address", @"address"]);

    NSString *errorMessage = nil;
    NSDictionary *payload = nil;
    VCMemoryLocatorEngine *engine = [VCMemoryLocatorEngine shared];
    if ([action isEqualToString:@"find_refs"] || [action isEqualToString:@"find_referrers"] || [action isEqualToString:@"reverse"]) {
        uint64_t targetAddress = VCAIAddressParam(params, @[@"address", @"targetAddress", @"target_address"]);
        NSUInteger limit = VCAIUnsignedParam(params, @[@"limit"], 12, 48);
        BOOL includeSecondHop = VCAIBoolParam(params, @[@"includeSecondHop", @"include_second_hop"], YES);
        payload = [engine findPointerReferencesToAddress:targetAddress
                                                   limit:limit
                                        includeSecondHop:includeSecondHop
                                            errorMessage:&errorMessage];
        action = @"find_refs";
    } else if ([action isEqualToString:@"read"]) {
        payload = [engine readPointerChainWithModuleName:VCAIStringParam(params, @[@"moduleName", @"module", @"module_name"])
                                             baseAddress:baseAddress
                                              baseOffset:baseOffset
                                                 offsets:[offsets copy]
                                          dataTypeString:VCAIStringParam(params, @[@"dataType", @"data_type", @"type"])
                                            errorMessage:&errorMessage];
    } else {
        payload = [engine resolvePointerChainWithModuleName:VCAIStringParam(params, @[@"moduleName", @"module", @"module_name"])
                                                baseAddress:baseAddress
                                                 baseOffset:baseOffset
                                                    offsets:[offsets copy]
                                               errorMessage:&errorMessage];
        action = @"resolve";
    }

    if (!payload) return VCAIErrorResult(toolCall, errorMessage ?: @"Pointer chain resolution failed");
    NSMutableDictionary *enriched = [payload mutableCopy];
    enriched[@"action"] = action;
    NSString *summary = [action isEqualToString:@"find_refs"]
        ? [NSString stringWithFormat:@"Found %@ direct references and %@ shallow chain suggestions for %@",
           enriched[@"directReferenceCount"] ?: @0,
           @([enriched[@"suggestedPointerChains"] isKindOfClass:[NSArray class]] ? [(NSArray *)enriched[@"suggestedPointerChains"] count] : 0),
           enriched[@"targetAddress"] ?: @""]
        : [action isEqualToString:@"read"]
        ? [NSString stringWithFormat:@"Resolved the pointer chain and read %@ at %@",
           enriched[@"dataType"] ?: @"value",
           enriched[@"resolvedAddress"] ?: @""]
        : [NSString stringWithFormat:@"Resolved the pointer chain to %@",
           enriched[@"resolvedAddress"] ?: @""];
    return VCAISuccessResult(toolCall, summary, [enriched copy], nil);
}

+ (NSDictionary *)_executeSignatureScan:(VCToolCall *)toolCall {
    NSDictionary *params = toolCall.params ?: @{};
    NSString *action = [VCAIStringParam(params, @[@"action", @"mode"]) lowercaseString];
    if (action.length == 0) action = @"scan";

    NSString *signature = VCAIStringParam(params, @[@"signature", @"pattern"]);
    NSString *moduleName = VCAIStringParam(params, @[@"moduleName", @"module", @"module_name"]);
    NSUInteger limit = VCAIUnsignedParam(params, @[@"limit"], 32, 200);
    int64_t offset = strtoll([VCAIStringParam(params, @[@"offset", @"sigOffset", @"sig_offset"]) UTF8String], NULL, 0);

    NSString *errorMessage = nil;
    NSDictionary *payload = nil;
    VCMemoryLocatorEngine *engine = [VCMemoryLocatorEngine shared];
    if ([action isEqualToString:@"resolve"] || [action isEqualToString:@"read"]) {
        payload = [engine resolveSignature:signature
                                moduleName:moduleName
                                    offset:offset
                            dataTypeString:VCAIStringParam(params, @[@"dataType", @"data_type", @"type"])
                                resultLimit:limit
                              errorMessage:&errorMessage];
        action = @"resolve";
    } else {
        payload = [engine scanSignature:signature moduleName:moduleName limit:limit errorMessage:&errorMessage];
        action = @"scan";
    }

    if (!payload) return VCAIErrorResult(toolCall, errorMessage ?: @"Signature scan failed");
    NSMutableDictionary *enriched = [payload mutableCopy];
    enriched[@"action"] = action;
    NSString *summary = [action isEqualToString:@"resolve"]
        ? [NSString stringWithFormat:@"Resolved the signature to %@",
           enriched[@"resolvedAddress"] ?: @""]
        : [NSString stringWithFormat:@"Found %lu signature matches",
           (unsigned long)[enriched[@"returnedCount"] unsignedIntegerValue]];
    return VCAISuccessResult(toolCall, summary, [enriched copy], nil);
}

+ (NSDictionary *)_executeAddressResolve:(VCToolCall *)toolCall {
    NSDictionary *params = toolCall.params ?: @{};
    NSString *action = [VCAIStringParam(params, @[@"action", @"mode"]) lowercaseString];
    if (action.length == 0) action = @"runtime_to_rva";

    NSString *moduleName = VCAIStringParam(params, @[@"moduleName", @"module", @"module_name"]);
    uint64_t address = VCAIAddressParam(params, @[@"address", @"runtimeAddress", @"runtime_address"]);
    uint64_t rva = strtoull([VCAIStringParam(params, @[@"rva", @"offset"]) UTF8String], NULL, 0);

    NSString *errorMessage = nil;
    NSDictionary *payload = [[VCMemoryLocatorEngine shared] resolveAddressAction:action
                                                                      moduleName:moduleName
                                                                             rva:rva
                                                                         address:address
                                                                    errorMessage:&errorMessage];
    if (!payload) return VCAIErrorResult(toolCall, errorMessage ?: @"Address resolution failed");

    NSString *summary = @"Resolved address metadata";
    if ([action isEqualToString:@"module_base"]) {
        summary = [NSString stringWithFormat:@"Resolved %@ base to %@", moduleName, payload[@"moduleBase"] ?: @""];
    } else if ([action isEqualToString:@"module_size"]) {
        summary = [NSString stringWithFormat:@"Resolved %@ size", moduleName];
    } else if ([action isEqualToString:@"rva_to_runtime"]) {
        summary = [NSString stringWithFormat:@"Resolved %@:%@ to %@",
                   moduleName,
                   payload[@"rva"] ?: @"",
                   payload[@"runtimeAddress"] ?: @""];
    } else if ([action isEqualToString:@"runtime_to_rva"]) {
        summary = [NSString stringWithFormat:@"Resolved %@ into %@ %@",
                   payload[@"address"] ?: @"",
                   payload[@"moduleName"] ?: @"module",
                   payload[@"rva"] ?: @""];
    }
    return VCAISuccessResult(toolCall, summary, payload, nil);
}

+ (NSDictionary *)_executeArtifactQuery:(VCToolCall *)toolCall {
    NSDictionary *params = toolCall.params ?: @{};
    NSString *queryType = [VCAIStringParam(params, @[@"queryType", @"query_type", @"mode"]) lowercaseString];
    if (queryType.length == 0) queryType = @"overview";

    if ([queryType isEqualToString:@"overview"]) {
        NSUInteger limit = VCAIUnsignedParam(params, @[@"limit"], 8, 40);
        NSArray<NSDictionary *> *traceSessions = [[VCTraceManager shared] sessionSummariesWithLimit:limit] ?: @[];
        NSArray<NSDictionary *> *diagrams = [self _mermaidArtifactSummariesWithLimit:limit];
        NSArray<NSDictionary *> *snapshots = [self _memorySnapshotSummariesWithLimit:limit];
        NSArray<NSDictionary *> *tracks = [self _savedTrackSummariesWithLimit:limit];
        NSDictionary *payload = @{
            @"queryType": queryType,
            @"traceSessions": traceSessions,
            @"diagrams": diagrams,
            @"memorySnapshots": snapshots,
            @"tracks": tracks,
            @"counts": @{
                @"traceSessions": @(traceSessions.count),
                @"diagrams": @(diagrams.count),
                @"memorySnapshots": @(snapshots.count),
                @"tracks": @(tracks.count)
            }
        };
        NSString *summary = [NSString stringWithFormat:@"Loaded %@ trace sessions, %@ diagrams, %@ memory snapshots, and %@ saved tracks",
                             @(traceSessions.count),
                             @(diagrams.count),
                             @(snapshots.count),
                             @(tracks.count)];
        return VCAISuccessResult(toolCall, summary, payload, nil);
    }

    if ([queryType isEqualToString:@"trace_sessions"]) {
        NSUInteger limit = VCAIUnsignedParam(params, @[@"limit"], 12, 60);
        NSArray<NSDictionary *> *sessions = [[VCTraceManager shared] sessionSummariesWithLimit:limit] ?: @[];
        NSDictionary *payload = @{
            @"queryType": queryType,
            @"returnedCount": @(sessions.count),
            @"sessions": sessions
        };
        NSString *summary = sessions.count > 0
            ? [NSString stringWithFormat:@"Loaded %lu saved trace sessions", (unsigned long)sessions.count]
            : @"No saved trace sessions were found";
        return VCAISuccessResult(toolCall, summary, payload, nil);
    }

    if ([queryType isEqualToString:@"trace_session_detail"]) {
        NSString *sessionID = VCAIStringParam(params, @[@"sessionID", @"sessionId", @"id"]);
        NSUInteger limit = VCAIUnsignedParam(params, @[@"limit"], 80, 300);
        NSDictionary *detail = [[VCTraceManager shared] sessionDetailForSession:sessionID eventLimit:limit];
        if (!detail) return VCAIErrorResult(toolCall, @"Trace session detail was not found");
        NSDictionary *session = [detail[@"session"] isKindOfClass:[NSDictionary class]] ? detail[@"session"] : @{};
        NSDictionary *reference = VCAIReferenceForFile(@"Trace",
                                                       [NSString stringWithFormat:@"Trace %@", session[@"name"] ?: session[@"sessionID"] ?: @"Session"],
                                                       @"json",
                                                       detail[@"eventsPath"] ?: @"",
                                                       @"Saved trace session events.",
                                                       @{
                                                           @"sessionID": session[@"sessionID"] ?: @"",
                                                           @"checkpointCount": session[@"checkpointCount"] ?: @0
                                                       });
        NSString *summary = [NSString stringWithFormat:@"Loaded trace \"%@\" with %@ checkpoints",
                             session[@"name"] ?: @"Trace",
                             detail[@"checkpointCount"] ?: @0];
        return VCAISuccessResult(toolCall, summary, detail, reference);
    }

    if ([queryType isEqualToString:@"diagram_list"]) {
        NSUInteger limit = VCAIUnsignedParam(params, @[@"limit"], 20, 100);
        NSArray<NSDictionary *> *diagrams = [self _mermaidArtifactSummariesWithLimit:limit];
        NSDictionary *payload = @{
            @"queryType": queryType,
            @"returnedCount": @(diagrams.count),
            @"artifacts": diagrams
        };
        NSString *summary = diagrams.count > 0
            ? [NSString stringWithFormat:@"Loaded %lu saved Mermaid diagrams", (unsigned long)diagrams.count]
            : @"No saved Mermaid diagrams were found";
        return VCAISuccessResult(toolCall, summary, payload, nil);
    }

    if ([queryType isEqualToString:@"diagram_detail"]) {
        NSString *artifactPath = VCAIStringParam(params, @[@"artifactPath", @"path"]);
        NSString *artifactID = VCAIStringParam(params, @[@"artifactID", @"id"]);
        NSString *loadError = nil;
        NSDictionary *artifact = artifactPath.length > 0
            ? [self _loadMermaidArtifactAtPath:artifactPath errorMessage:&loadError]
            : [self _loadMermaidArtifactByID:artifactID errorMessage:&loadError];
        if (!artifact) return VCAIErrorResult(toolCall, loadError ?: @"Mermaid artifact could not be loaded");

        BOOL includeContent = VCAIBoolParam(params, @[@"includeContent", @"include_content"], YES);
        NSMutableDictionary *payload = [[self _mermaidArtifactSummaryForArtifact:artifact] mutableCopy];
        if (includeContent) payload[@"content"] = artifact[@"content"] ?: @"";
        NSDictionary *reference = VCAIReferenceForMermaid(payload[@"title"],
                                                          payload[@"diagramType"],
                                                          payload[@"path"],
                                                          artifact[@"content"],
                                                          artifact[@"summary"]);
        NSString *summary = [NSString stringWithFormat:@"Loaded Mermaid diagram %@", payload[@"title"] ?: @"artifact"];
        return VCAISuccessResult(toolCall, summary, [payload copy], reference);
    }

    if ([queryType isEqualToString:@"memory_snapshot_list"]) {
        NSUInteger limit = VCAIUnsignedParam(params, @[@"limit"], 20, 100);
        NSArray<NSDictionary *> *snapshots = [self _memorySnapshotSummariesWithLimit:limit];
        NSDictionary *payload = @{
            @"queryType": queryType,
            @"returnedCount": @(snapshots.count),
            @"snapshots": snapshots
        };
        NSString *summary = snapshots.count > 0
            ? [NSString stringWithFormat:@"Loaded %lu saved memory snapshots", (unsigned long)snapshots.count]
            : @"No saved memory snapshots were found";
        return VCAISuccessResult(toolCall, summary, payload, nil);
    }

    if ([queryType isEqualToString:@"memory_snapshot_detail"]) {
        NSString *loadError = nil;
        NSDictionary *snapshot = [self _loadMemorySnapshotFromParams:params
                                                              idKeys:@[@"snapshotID", @"snapshotId"]
                                                            pathKeys:@[@"snapshotPath", @"snapshot_path", @"artifactPath"]
                                                       errorMessage:&loadError];
        if (!snapshot) return VCAIErrorResult(toolCall, loadError ?: @"Memory snapshot detail could not be loaded");

        BOOL includeContent = VCAIBoolParam(params, @[@"includeContent", @"include_content"], YES);
        NSMutableDictionary *payload = [[snapshot copy] mutableCopy];
        if (!includeContent) {
            [payload removeObjectForKey:@"bytesHex"];
            [payload removeObjectForKey:@"hexDump"];
            [payload removeObjectForKey:@"beforeHexDump"];
            [payload removeObjectForKey:@"afterHexDump"];
            [payload removeObjectForKey:@"changes"];
        }
        NSDictionary *reference = VCAIReferenceForFile(@"Memory Snapshot",
                                                       [NSString stringWithFormat:@"Memory Snapshot %@", snapshot[@"snapshotID"] ?: @"detail"],
                                                       @"json",
                                                       snapshot[@"path"] ?: @"",
                                                       @"Loaded saved memory snapshot detail.",
                                                       @{
                                                           @"snapshotID": snapshot[@"snapshotID"] ?: @"",
                                                           @"queryType": snapshot[@"queryType"] ?: @"snapshot"
                                                       });
        NSString *summary = [NSString stringWithFormat:@"Loaded memory snapshot %@", snapshot[@"snapshotID"] ?: @"detail"];
        return VCAISuccessResult(toolCall, summary, [payload copy], reference);
    }

    if ([queryType isEqualToString:@"track_list"]) {
        NSUInteger limit = VCAIUnsignedParam(params, @[@"limit"], 20, 100);
        NSArray<NSDictionary *> *tracks = [self _savedTrackSummariesWithLimit:limit];
        NSDictionary *payload = @{
            @"queryType": queryType,
            @"returnedCount": @(tracks.count),
            @"tracks": tracks
        };
        NSString *summary = tracks.count > 0
            ? [NSString stringWithFormat:@"Loaded %lu saved overlay tracks", (unsigned long)tracks.count]
            : @"No saved overlay tracks were found";
        return VCAISuccessResult(toolCall, summary, payload, nil);
    }

    if ([queryType isEqualToString:@"track_detail"]) {
        NSString *loadError = nil;
        NSDictionary *track = [self _loadTrackDetailFromParams:params
                                                        idKeys:@[@"trackerID", @"trackerId", @"id"]
                                                      pathKeys:@[@"trackerPath", @"tracker_path", @"artifactPath", @"path"]
                                                 errorMessage:&loadError];
        if (!track) return VCAIErrorResult(toolCall, loadError ?: @"Track detail could not be loaded");

        BOOL includeContent = VCAIBoolParam(params, @[@"includeContent", @"include_content"], YES);
        NSMutableDictionary *payload = [track mutableCopy];
        if (!includeContent) {
            [payload removeObjectForKey:@"config"];
        }
        NSDictionary *reference = VCAIReferenceForFile(@"Overlay Track",
                                                       [NSString stringWithFormat:@"Track %@", track[@"title"] ?: track[@"trackerID"] ?: @"detail"],
                                                       @"json",
                                                       track[@"path"] ?: @"",
                                                       @"Loaded saved overlay tracking preset.",
                                                       @{
                                                           @"trackerID": track[@"trackerID"] ?: @"",
                                                           @"mode": track[@"mode"] ?: @""
                                                       });
        NSString *summary = [NSString stringWithFormat:@"Loaded saved track %@", track[@"title"] ?: track[@"trackerID"] ?: @"detail"];
        return VCAISuccessResult(toolCall, summary, [payload copy], reference);
    }

    return VCAIErrorResult(toolCall, [NSString stringWithFormat:@"Unsupported query_artifacts mode %@", queryType]);
}

+ (NSDictionary *)_executeMermaidExport:(VCToolCall *)toolCall {
    NSDictionary *params = toolCall.params ?: @{};
    NSString *content = VCAIStringParam(params, @[@"content", @"diagram", @"mermaid"]);
    if (content.length == 0) return VCAIErrorResult(toolCall, @"export_mermaid requires Mermaid content");

    NSString *title = VCAIStringParam(params, @[@"title"]);
    if (title.length == 0) title = @"Program Diagram";
    NSString *diagramType = VCAIStringParam(params, @[@"diagramType", @"diagram_type", @"type"]);
    if (diagramType.length == 0) diagramType = @"diagram";
    NSString *summary = VCAIStringParam(params, @[@"summary", @"remark"]);
    NSString *saveError = nil;
    NSDictionary *artifact = VCAISaveMermaidArtifact(title, diagramType, content, summary, &saveError);
    if (!artifact) {
        return VCAIErrorResult(toolCall, saveError ?: @"Failed to save Mermaid diagram");
    }

    NSString *path = artifact[@"path"];
    NSString *normalizedContent = artifact[@"content"];
    NSDictionary *reference = VCAIReferenceForMermaid(title, diagramType, path, normalizedContent, summary);
    NSDictionary *payload = @{
        @"diagramType": diagramType,
        @"title": title,
        @"path": path,
        @"lineCount": @([[normalizedContent componentsSeparatedByString:@"\n"] count]),
        @"byteCount": @([[normalizedContent dataUsingEncoding:NSUTF8StringEncoding] length])
    };
    NSString *resultSummary = [NSString stringWithFormat:@"Saved Mermaid diagram to %@", path.lastPathComponent ?: @"diagram.mmd"];
    return VCAISuccessResult(toolCall, resultSummary, payload, reference);
}

+ (NSDictionary *)_executeTraceStart:(VCToolCall *)toolCall {
    NSString *errorMessage = nil;
    NSDictionary *session = [[VCTraceManager shared] startTraceWithOptions:(toolCall.params ?: @{}) errorMessage:&errorMessage];
    if (!session) return VCAIErrorResult(toolCall, errorMessage ?: @"Failed to start trace session");
    NSString *summary = [NSString stringWithFormat:@"Started trace \"%@\" with %@ method targets, %@ memory watches, and %@ checkpoint triggers",
                         session[@"name"] ?: @"Runtime Trace",
                         session[@"installedMethodCount"] ?: @0,
                         session[@"memoryWatchCount"] ?: @0,
                         session[@"checkpointTriggerCount"] ?: @0];
    return VCAISuccessResult(toolCall, summary, session, nil);
}

+ (NSDictionary *)_executeTraceCheckpoint:(VCToolCall *)toolCall {
    NSDictionary *params = toolCall.params ?: @{};
    NSString *sessionID = VCAIStringParam(params, @[@"sessionID", @"sessionId", @"id"]);
    NSString *errorMessage = nil;
    NSDictionary *checkpoint = [[VCTraceManager shared] captureCheckpointForSession:sessionID
                                                                            options:params
                                                                       errorMessage:&errorMessage];
    if (!checkpoint) return VCAIErrorResult(toolCall, errorMessage ?: @"Failed to capture trace checkpoint");
    NSString *summary = [NSString stringWithFormat:@"Captured checkpoint \"%@\" with %@ changed watches",
                         checkpoint[@"label"] ?: @"Checkpoint",
                         checkpoint[@"changedWatchCount"] ?: @0];
    return VCAISuccessResult(toolCall, summary, checkpoint, nil);
}

+ (NSDictionary *)_executeTraceStop:(VCToolCall *)toolCall {
    NSString *sessionID = VCAIStringParam(toolCall.params ?: @{}, @[@"sessionID", @"sessionId", @"id"]);
    NSString *errorMessage = nil;
    NSDictionary *session = [[VCTraceManager shared] stopTraceSession:sessionID errorMessage:&errorMessage];
    if (!session) return VCAIErrorResult(toolCall, errorMessage ?: @"Failed to stop trace session");
    NSString *summary = [NSString stringWithFormat:@"Stopped trace \"%@\" after %@ events with %@ memory watches finalized",
                         session[@"name"] ?: @"Runtime Trace",
                         session[@"eventCount"] ?: @0,
                         session[@"memoryWatchCount"] ?: @0];
    return VCAISuccessResult(toolCall, summary, session, nil);
}

+ (NSDictionary *)_executeTraceEvents:(VCToolCall *)toolCall {
    NSDictionary *params = toolCall.params ?: @{};
    NSString *sessionID = VCAIStringParam(params, @[@"sessionID", @"sessionId", @"id"]);
    NSUInteger limit = VCAIUnsignedParam(params, @[@"limit"], 60, 300);
    NSArray *kindNames = [params[@"kindNames"] isKindOfClass:[NSArray class]] ? params[@"kindNames"] : nil;
    NSDictionary *snapshot = [[VCTraceManager shared] eventsSnapshotForSession:sessionID limit:limit kindNames:kindNames];
    if (!snapshot) return VCAIErrorResult(toolCall, @"Trace session not found");
    NSString *summary = [NSString stringWithFormat:@"Loaded %@ trace events from \"%@\" (%@ memory watches, %@ checkpoints)",
                         snapshot[@"returnedCount"] ?: @0,
                         snapshot[@"session"][@"name"] ?: @"Runtime Trace",
                         snapshot[@"session"][@"memoryWatchCount"] ?: @0,
                         snapshot[@"session"][@"checkpointCount"] ?: @0];
    return VCAISuccessResult(toolCall, summary, snapshot, nil);
}

+ (NSDictionary *)_executeTraceExportMermaid:(VCToolCall *)toolCall {
    NSDictionary *params = toolCall.params ?: @{};
    NSString *sessionID = VCAIStringParam(params, @[@"sessionID", @"sessionId", @"id"]);
    NSString *style = VCAIStringParam(params, @[@"style", @"diagramStyle"]);
    NSString *title = VCAIStringParam(params, @[@"title"]);
    NSUInteger limit = VCAIUnsignedParam(params, @[@"limit"], 120, 300);
    NSString *errorMessage = nil;
    NSDictionary *diagram = [[VCTraceManager shared] exportMermaidForSession:sessionID
                                                                       style:style
                                                                       title:title
                                                                       limit:limit
                                                                errorMessage:&errorMessage];
    if (!diagram) return VCAIErrorResult(toolCall, errorMessage ?: @"Failed to export trace Mermaid");

    NSString *saveError = nil;
    NSDictionary *artifact = VCAISaveMermaidArtifact(diagram[@"title"], @"trace", diagram[@"content"], diagram[@"summary"], &saveError);
    if (!artifact) return VCAIErrorResult(toolCall, saveError ?: @"Failed to persist trace Mermaid");

    NSDictionary *reference = VCAIReferenceForMermaid(artifact[@"title"], @"trace", artifact[@"path"], artifact[@"content"], artifact[@"summary"]);
    NSDictionary *payload = @{
        @"sessionID": diagram[@"sessionID"] ?: @"",
        @"diagramType": @"trace",
        @"title": artifact[@"title"] ?: @"Trace Diagram",
        @"style": diagram[@"style"] ?: @"sequence",
        @"path": artifact[@"path"] ?: @"",
        @"eventCount": diagram[@"eventCount"] ?: @0
    };
    NSString *summary = [NSString stringWithFormat:@"Saved trace Mermaid to %@", [artifact[@"path"] lastPathComponent] ?: @"trace.mmd"];
    return VCAISuccessResult(toolCall, summary, payload, reference);
}

@end
