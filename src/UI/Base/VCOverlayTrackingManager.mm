/**
 * VCOverlayTrackingManager -- persistent overlay projection tracker for moving targets
 */

#import "VCOverlayTrackingManager.h"
#import "VCOverlayCanvasManager.h"
#import "VCOverlayRootViewController.h"
#import "../../Core/VCConfig.h"
#import "../../AI/ToolCall/VCAIReadOnlyToolExecutor.h"
#import "../../AI/ToolCall/VCToolCallParser.h"
#import "../../../VansonCLI.h"

#import <mach/mach_time.h>

static NSString *VCOverlayTrackTrimmedString(id value) {
    if ([value isKindOfClass:[NSString class]]) {
        return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        return [[(NSNumber *)value stringValue] copy];
    }
    return @"";
}

static NSString *VCOverlayTrackStringParam(NSDictionary *params, NSArray<NSString *> *keys) {
    for (NSString *key in keys) {
        NSString *value = VCOverlayTrackTrimmedString(params[key]);
        if (value.length > 0) return value;
    }
    return @"";
}

static double VCOverlayTrackDoubleParam(NSDictionary *params, NSArray<NSString *> *keys, double fallbackValue) {
    for (NSString *key in keys) {
        id rawValue = params[key];
        if ([rawValue respondsToSelector:@selector(doubleValue)]) {
            return [rawValue doubleValue];
        }
    }
    return fallbackValue;
}

static BOOL VCOverlayTrackBoolParam(NSDictionary *params, NSArray<NSString *> *keys, BOOL fallbackValue) {
    for (NSString *key in keys) {
        id rawValue = params[key];
        if ([rawValue respondsToSelector:@selector(boolValue)]) {
            return [rawValue boolValue];
        }
    }
    return fallbackValue;
}

static uintptr_t VCOverlayTrackAddressParam(NSDictionary *params, NSArray<NSString *> *keys) {
    for (NSString *key in keys) {
        id rawValue = params[key];
        if ([rawValue isKindOfClass:[NSNumber class]]) {
            return (uintptr_t)[(NSNumber *)rawValue unsignedLongLongValue];
        }
        if ([rawValue isKindOfClass:[NSString class]]) {
            NSString *text = VCOverlayTrackTrimmedString(rawValue);
            if (text.length == 0) continue;
            return (uintptr_t)strtoull(text.UTF8String, NULL, 0);
        }
    }
    return 0;
}

static NSString *VCOverlayTrackHexAddress(uintptr_t address) {
    return [NSString stringWithFormat:@"0x%llx", (unsigned long long)address];
}

static NSData *VCOverlayTrackJSONObjectData(id object) {
    if (![NSJSONSerialization isValidJSONObject:object]) return nil;
    return [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted error:nil];
}

static NSString *VCOverlayTrackingDirectoryPath(void) {
    NSString *path = [[[VCConfig shared] sessionsPath] stringByAppendingPathComponent:@"tracks"];
    [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    return path;
}

static NSDictionary *VCOverlayTrackLoadJSONAtPath(NSString *path) {
    NSString *trimmed = VCOverlayTrackTrimmedString(path);
    if (trimmed.length == 0) return nil;
    NSData *data = [NSData dataWithContentsOfFile:trimmed];
    if (![data isKindOfClass:[NSData class]]) return nil;
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![object isKindOfClass:[NSDictionary class]]) return nil;
    NSMutableDictionary *payload = [(NSDictionary *)object mutableCopy];
    payload[@"path"] = trimmed;
    return [payload copy];
}

static NSString *VCOverlayTrackCanvasID(NSString *value) {
    NSString *trimmed = VCOverlayTrackTrimmedString(value);
    return trimmed.length > 0 ? trimmed : @"tracking";
}

static NSString *VCOverlayTrackItemID(NSString *value) {
    NSString *trimmed = VCOverlayTrackTrimmedString(value);
    return trimmed.length > 0 ? trimmed : [[NSUUID UUID] UUIDString];
}

static NSString *VCOverlayTrackModeNormalized(NSString *value) {
    NSString *normalized = [VCOverlayTrackTrimmedString(value).lowercaseString copy];
    if (normalized.length == 0) return @"";
    if ([normalized isEqualToString:@"point"] ||
        [normalized isEqualToString:@"project_point"] ||
        [normalized isEqualToString:@"projection_point"] ||
        [normalized isEqualToString:@"project"]) {
        return @"project_point";
    }
    if ([normalized isEqualToString:@"screen_point"] ||
        [normalized isEqualToString:@"point2d"] ||
        [normalized isEqualToString:@"screenpoint"]) {
        return @"screen_point";
    }
    if ([normalized isEqualToString:@"screen_rect"] ||
        [normalized isEqualToString:@"rect2d"] ||
        [normalized isEqualToString:@"screenrect"]) {
        return @"screen_rect";
    }
    if ([normalized isEqualToString:@"bounds"] ||
        [normalized isEqualToString:@"project_bounds"] ||
        [normalized isEqualToString:@"projection_bounds"]) {
        return @"project_bounds";
    }
    if ([normalized isEqualToString:@"unity_transform"] ||
        [normalized isEqualToString:@"unity_point"] ||
        [normalized isEqualToString:@"transform"] ||
        [normalized isEqualToString:@"component"] ||
        [normalized isEqualToString:@"gameobject"] ||
        [normalized isEqualToString:@"game_object"]) {
        return @"unity_transform";
    }
    if ([normalized isEqualToString:@"unity_renderer"] ||
        [normalized isEqualToString:@"renderer"] ||
        [normalized isEqualToString:@"renderer_bounds"] ||
        [normalized isEqualToString:@"unity_bounds"]) {
        return @"unity_renderer";
    }
    return normalized;
}

static UIColor *VCOverlayTrackColorFromString(NSString *value, UIColor *fallback) {
    NSString *trimmed = VCOverlayTrackTrimmedString(value).lowercaseString;
    if (trimmed.length == 0) return fallback;

    NSDictionary<NSString *, UIColor *> *named = @{
        @"red": kVCRed,
        @"green": kVCGreen,
        @"blue": kVCAccent,
        @"cyan": kVCAccent,
        @"yellow": kVCYellow,
        @"orange": kVCOrange,
        @"white": kVCTextPrimary,
        @"black": kVCBgPrimary,
        @"clear": [UIColor clearColor]
    };
    UIColor *namedColor = named[trimmed];
    if (namedColor) return namedColor;

    NSString *hex = [trimmed stringByReplacingOccurrencesOfString:@"#" withString:@""];
    if (hex.length == 6 || hex.length == 8) {
        unsigned long long raw = strtoull(hex.UTF8String, NULL, 16);
        CGFloat red = ((raw >> (hex.length == 8 ? 24 : 16)) & 0xFF) / 255.0;
        CGFloat green = ((raw >> (hex.length == 8 ? 16 : 8)) & 0xFF) / 255.0;
        CGFloat blue = ((raw >> (hex.length == 8 ? 8 : 0)) & 0xFF) / 255.0;
        CGFloat alpha = hex.length == 8 ? (raw & 0xFF) / 255.0 : 1.0;
        return [UIColor colorWithRed:red green:green blue:blue alpha:alpha];
    }
    return fallback;
}

static NSDictionary *VCOverlayTrackScreenPoint(NSDictionary *payload) {
    NSDictionary *point = [payload[@"screenPoint"] isKindOfClass:[NSDictionary class]] ? payload[@"screenPoint"] : nil;
    if (!point) {
        point = [payload[@"overlayPoint"] isKindOfClass:[NSDictionary class]] ? payload[@"overlayPoint"] : nil;
    }
    if (!point) return nil;
    if (![point[@"x"] respondsToSelector:@selector(doubleValue)] ||
        ![point[@"y"] respondsToSelector:@selector(doubleValue)]) {
        return nil;
    }
    return point;
}

static NSDictionary *VCOverlayTrackScreenBox(NSDictionary *payload) {
    NSDictionary *box = [payload[@"screenBox"] isKindOfClass:[NSDictionary class]] ? payload[@"screenBox"] : nil;
    if (!box) return nil;
    if (![box[@"x"] respondsToSelector:@selector(doubleValue)] ||
        ![box[@"y"] respondsToSelector:@selector(doubleValue)] ||
        ![box[@"width"] respondsToSelector:@selector(doubleValue)] ||
        ![box[@"height"] respondsToSelector:@selector(doubleValue)]) {
        return nil;
    }
    return box;
}

@interface VCOverlayTracker : NSObject
@property (nonatomic, copy) NSString *canvasID;
@property (nonatomic, copy) NSString *itemID;
@property (nonatomic, copy) NSString *mode;
@property (nonatomic, copy) NSDictionary *config;
@property (nonatomic, copy) NSString *drawStyle;
@property (nonatomic, copy) NSString *label;
@property (nonatomic, strong) UIColor *color;
@property (nonatomic, strong, nullable) UIColor *fillColor;
@property (nonatomic, strong, nullable) UIColor *backgroundColor;
@property (nonatomic, assign) CGFloat lineWidth;
@property (nonatomic, assign) CGFloat fontSize;
@property (nonatomic, assign) CGFloat radius;
@property (nonatomic, assign) CGFloat cornerRadius;
@property (nonatomic, assign) CGFloat labelOffsetX;
@property (nonatomic, assign) CGFloat labelOffsetY;
@property (nonatomic, assign) BOOL lastVisible;
@property (nonatomic, assign) NSTimeInterval lastUpdatedAt;
@property (nonatomic, copy) NSString *lastStatus;
@property (nonatomic, assign) NSTimeInterval updateInterval;
@property (nonatomic, assign) NSUInteger consecutiveFailures;
@property (nonatomic, assign) NSUInteger maxConsecutiveFailures;
@end

@implementation VCOverlayTracker
@end

@interface VCOverlayTrackingManager ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, VCOverlayTracker *> *trackers;
@property (nonatomic, strong, nullable) CADisplayLink *displayLink;
@end

@implementation VCOverlayTrackingManager

+ (instancetype)shared {
    static VCOverlayTrackingManager *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VCOverlayTrackingManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        _trackers = [NSMutableDictionary new];
    }
    return self;
}

- (NSDictionary *)startTrackerWithConfiguration:(NSDictionary *)configuration {
    __block NSDictionary *result = nil;
    [self _performOnMainThread:^{
        NSString *errorMessage = nil;
        VCOverlayTracker *tracker = [self _trackerFromConfiguration:configuration errorMessage:&errorMessage];
        if (!tracker) {
            result = @{
                @"success": @NO,
                @"summary": errorMessage.length > 0 ? errorMessage : @"overlay_track could not be started."
            };
            return;
        }

        NSString *key = [self _trackerKeyForCanvasIdentifier:tracker.canvasID itemIdentifier:tracker.itemID];
        self.trackers[key] = tracker;
        [[VCOverlayCanvasManager shared] setCanvasHidden:NO identifier:tracker.canvasID];
        [self _ensureDisplayLink];
        [self _refreshTracker:tracker];

        NSString *summary = [NSString stringWithFormat:@"Started %@ tracker %@ on %@",
                             tracker.mode ?: @"overlay",
                             tracker.itemID ?: @"item",
                             tracker.canvasID ?: @"tracking"];
        result = [self _payloadForTrackers:@[tracker] summary:summary];
    }];
    return result ?: @{@"success": @NO, @"summary": @"overlay_track could not be started."};
}

- (NSDictionary *)stopTrackerWithItemIdentifier:(NSString *)itemID
                               canvasIdentifier:(NSString *)canvasID {
    __block NSDictionary *result = nil;
    [self _performOnMainThread:^{
        NSArray<VCOverlayTracker *> *targets = [self _matchingTrackersForItemIdentifier:itemID canvasIdentifier:canvasID];
        if (targets.count == 0) {
            result = @{
                @"success": @NO,
                @"summary": @"No matching overlay trackers were active."
            };
            return;
        }

        for (VCOverlayTracker *tracker in targets) {
            [self _clearOverlayForTracker:tracker];
            [self.trackers removeObjectForKey:[self _trackerKeyForCanvasIdentifier:tracker.canvasID itemIdentifier:tracker.itemID]];
        }
        [self _updateDisplayLinkState];
        NSString *summary = targets.count == 1
            ? [NSString stringWithFormat:@"Stopped tracker %@ on %@", targets.firstObject.itemID, targets.firstObject.canvasID]
            : [NSString stringWithFormat:@"Stopped %lu overlay trackers", (unsigned long)targets.count];
        result = [self _payloadForTrackers:targets summary:summary];
    }];
    return result ?: @{@"success": @NO, @"summary": @"No matching overlay trackers were active."};
}

- (NSDictionary *)clearTrackersForCanvasIdentifier:(NSString *)canvasID {
    __block NSDictionary *result = nil;
    [self _performOnMainThread:^{
        NSArray<VCOverlayTracker *> *targets = [self _matchingTrackersForItemIdentifier:nil canvasIdentifier:canvasID];
        if (targets.count == 0) {
            if (canvasID.length > 0) {
                [[VCOverlayCanvasManager shared] clearCanvasWithIdentifier:canvasID itemIdentifier:nil];
            } else {
                [[VCOverlayCanvasManager shared] clearCanvasWithIdentifier:nil itemIdentifier:nil];
            }
            result = @{
                @"success": @YES,
                @"summary": canvasID.length > 0
                    ? [NSString stringWithFormat:@"Cleared canvas %@ with no active trackers.", canvasID]
                    : @"Cleared overlay tracking canvas."
            };
            return;
        }

        for (VCOverlayTracker *tracker in targets) {
            [self _clearOverlayForTracker:tracker];
            [self.trackers removeObjectForKey:[self _trackerKeyForCanvasIdentifier:tracker.canvasID itemIdentifier:tracker.itemID]];
        }
        [self _updateDisplayLinkState];

        if (canvasID.length > 0) {
            [[VCOverlayCanvasManager shared] clearCanvasWithIdentifier:canvasID itemIdentifier:nil];
        } else {
            NSMutableSet<NSString *> *canvasIDs = [NSMutableSet set];
            for (VCOverlayTracker *tracker in targets) {
                if (tracker.canvasID.length > 0) [canvasIDs addObject:tracker.canvasID];
            }
            for (NSString *identifier in canvasIDs) {
                [[VCOverlayCanvasManager shared] clearCanvasWithIdentifier:identifier itemIdentifier:nil];
            }
        }
        NSString *summary = canvasID.length > 0
            ? [NSString stringWithFormat:@"Cleared %lu tracker(s) on %@", (unsigned long)targets.count, canvasID]
            : [NSString stringWithFormat:@"Cleared %lu overlay tracker(s)", (unsigned long)targets.count];
        result = [self _payloadForTrackers:targets summary:summary];
    }];
    return result ?: @{@"success": @YES, @"summary": @"Cleared overlay tracking canvas."};
}

- (NSDictionary *)statusForItemIdentifier:(NSString *)itemID
                         canvasIdentifier:(NSString *)canvasID {
    __block NSDictionary *result = nil;
    [self _performOnMainThread:^{
        NSArray<VCOverlayTracker *> *targets = [self _matchingTrackersForItemIdentifier:itemID canvasIdentifier:canvasID];
        NSString *summary = nil;
        if (targets.count == 0) {
            summary = itemID.length > 0 ? @"No matching overlay tracker is active." : @"No overlay trackers are active.";
        } else if (targets.count == 1) {
            VCOverlayTracker *tracker = targets.firstObject;
            summary = [NSString stringWithFormat:@"Tracker %@ on %@ is %@",
                       tracker.itemID ?: @"item",
                       tracker.canvasID ?: @"tracking",
                       tracker.lastVisible ? @"visible" : @"hidden/off-screen"];
        } else {
            summary = [NSString stringWithFormat:@"%lu overlay trackers are active", (unsigned long)targets.count];
        }
        result = [self _payloadForTrackers:targets summary:summary];
    }];
    return result ?: @{@"success": @YES, @"summary": @"No overlay trackers are active."};
}

- (NSDictionary *)saveTrackerWithItemIdentifier:(NSString *)itemID
                               canvasIdentifier:(NSString *)canvasID
                                          title:(NSString *)title
                                       subtitle:(NSString *)subtitle {
    __block NSDictionary *result = nil;
    [self _performOnMainThread:^{
        NSArray<VCOverlayTracker *> *targets = [self _matchingTrackersForItemIdentifier:itemID canvasIdentifier:canvasID];
        VCOverlayTracker *tracker = targets.firstObject;
        if (!tracker) {
            result = @{@"success": @NO, @"summary": @"No matching overlay tracker is active."};
            return;
        }

        NSString *trackerID = [NSString stringWithFormat:@"%@-%@", [[NSUUID UUID] UUIDString], tracker.itemID ?: @"track"];
        NSDictionary *payload = [self _artifactPayloadForTracker:tracker
                                                       trackerID:trackerID
                                                           title:title
                                                        subtitle:subtitle];
        NSData *jsonData = VCOverlayTrackJSONObjectData(payload);
        if (!jsonData) {
            result = @{@"success": @NO, @"summary": @"Could not serialize the tracker preset."};
            return;
        }
        NSString *path = [[VCOverlayTrackingDirectoryPath() stringByAppendingPathComponent:trackerID] stringByAppendingPathExtension:@"json"];
        if (![jsonData writeToFile:path atomically:YES]) {
            result = @{@"success": @NO, @"summary": @"Could not save the tracker preset to disk."};
            return;
        }
        result = @{
            @"success": @YES,
            @"summary": [NSString stringWithFormat:@"Saved tracker %@ for later restore.", tracker.itemID ?: @"track"],
            @"tracker": [self _artifactSummaryFromPayload:payload path:path]
        };
    }];
    return result ?: @{@"success": @NO, @"summary": @"No matching overlay tracker is active."};
}

- (NSDictionary *)restoreTrackerFromPath:(NSString *)path
                               trackerID:(NSString *)trackerID {
    __block NSDictionary *result = nil;
    [self _performOnMainThread:^{
        NSDictionary *payload = nil;
        if (VCOverlayTrackTrimmedString(path).length > 0) {
            payload = VCOverlayTrackLoadJSONAtPath(path);
        } else if (VCOverlayTrackTrimmedString(trackerID).length > 0) {
            payload = [self savedTrackerDetailFromPath:nil trackerID:trackerID];
        }
        NSDictionary *config = [payload[@"config"] isKindOfClass:[NSDictionary class]] ? payload[@"config"] : nil;
        if (!config) {
            result = @{@"success": @NO, @"summary": @"Saved tracker preset could not be loaded."};
            return;
        }

        NSMutableDictionary *startConfig = [config mutableCopy];
        if ([payload[@"drawStyle"] isKindOfClass:[NSString class]]) startConfig[@"drawStyle"] = payload[@"drawStyle"];
        if ([payload[@"label"] isKindOfClass:[NSString class]]) startConfig[@"label"] = payload[@"label"];
        if ([payload[@"color"] isKindOfClass:[NSString class]]) startConfig[@"color"] = payload[@"color"];
        if ([payload[@"fillColor"] isKindOfClass:[NSString class]]) startConfig[@"fillColor"] = payload[@"fillColor"];
        if ([payload[@"backgroundColor"] isKindOfClass:[NSString class]]) startConfig[@"backgroundColor"] = payload[@"backgroundColor"];
        if ([payload[@"lineWidth"] respondsToSelector:@selector(doubleValue)]) startConfig[@"lineWidth"] = payload[@"lineWidth"];
        if ([payload[@"fontSize"] respondsToSelector:@selector(doubleValue)]) startConfig[@"fontSize"] = payload[@"fontSize"];
        if ([payload[@"radius"] respondsToSelector:@selector(doubleValue)]) startConfig[@"radius"] = payload[@"radius"];
        if ([payload[@"cornerRadius"] respondsToSelector:@selector(doubleValue)]) startConfig[@"cornerRadius"] = payload[@"cornerRadius"];
        if ([payload[@"labelOffsetX"] respondsToSelector:@selector(doubleValue)]) startConfig[@"labelOffsetX"] = payload[@"labelOffsetX"];
        if ([payload[@"labelOffsetY"] respondsToSelector:@selector(doubleValue)]) startConfig[@"labelOffsetY"] = payload[@"labelOffsetY"];
        if ([payload[@"updateInterval"] respondsToSelector:@selector(doubleValue)]) startConfig[@"updateInterval"] = payload[@"updateInterval"];
        if ([payload[@"maxConsecutiveFailures"] respondsToSelector:@selector(unsignedIntegerValue)]) startConfig[@"maxConsecutiveFailures"] = payload[@"maxConsecutiveFailures"];

        result = [self startTrackerWithConfiguration:[startConfig copy]];
    }];
    return result ?: @{@"success": @NO, @"summary": @"Saved tracker preset could not be loaded."};
}

- (NSArray<NSDictionary *> *)savedTrackerSummariesWithLimit:(NSUInteger)limit {
    NSString *directory = VCOverlayTrackingDirectoryPath();
    NSArray<NSString *> *fileNames = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:nil] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray<NSDictionary *> *items = [NSMutableArray new];
    NSUInteger clampedLimit = MAX((NSUInteger)1, MIN(limit > 0 ? limit : 20, (NSUInteger)100));
    for (NSString *fileName in [fileNames reverseObjectEnumerator]) {
        if (![fileName.pathExtension.lowercaseString isEqualToString:@"json"]) continue;
        NSDictionary *payload = VCOverlayTrackLoadJSONAtPath([directory stringByAppendingPathComponent:fileName]);
        if (!payload) continue;
        [items addObject:[self _artifactSummaryFromPayload:payload path:payload[@"path"]]];
        if (items.count >= clampedLimit) break;
    }
    return [items copy];
}

- (NSDictionary *)savedTrackerDetailFromPath:(NSString *)path
                                   trackerID:(NSString *)trackerID {
    NSString *resolvedPath = VCOverlayTrackTrimmedString(path);
    if (resolvedPath.length == 0) {
        NSString *trimmedID = VCOverlayTrackTrimmedString(trackerID);
        if (trimmedID.length == 0) return nil;
        resolvedPath = [[VCOverlayTrackingDirectoryPath() stringByAppendingPathComponent:trimmedID] stringByAppendingPathExtension:@"json"];
    }
    return VCOverlayTrackLoadJSONAtPath(resolvedPath);
}

#pragma mark - Private

- (void)_performOnMainThread:(dispatch_block_t)block {
    if (!block) return;
    if ([NSThread isMainThread]) {
        block();
    } else {
        dispatch_sync(dispatch_get_main_queue(), block);
    }
}

- (NSString *)_trackerKeyForCanvasIdentifier:(NSString *)canvasID itemIdentifier:(NSString *)itemID {
    return [NSString stringWithFormat:@"%@::%@", VCOverlayTrackCanvasID(canvasID), VCOverlayTrackItemID(itemID)];
}

- (NSArray<VCOverlayTracker *> *)_matchingTrackersForItemIdentifier:(NSString *)itemID
                                                   canvasIdentifier:(NSString *)canvasID {
    NSString *normalizedItemID = VCOverlayTrackTrimmedString(itemID);
    NSString *normalizedCanvasID = VCOverlayTrackTrimmedString(canvasID);
    NSMutableArray<VCOverlayTracker *> *matches = [NSMutableArray new];
    for (VCOverlayTracker *tracker in self.trackers.allValues) {
        if (normalizedCanvasID.length > 0 && ![tracker.canvasID isEqualToString:normalizedCanvasID]) continue;
        if (normalizedItemID.length > 0 && ![tracker.itemID isEqualToString:normalizedItemID]) continue;
        [matches addObject:tracker];
    }
    return [matches copy];
}

- (NSDictionary *)_payloadForTrackers:(NSArray<VCOverlayTracker *> *)trackers summary:(NSString *)summary {
    NSMutableArray *items = [NSMutableArray new];
    for (VCOverlayTracker *tracker in trackers ?: @[]) {
        [items addObject:@{
            @"canvasID": tracker.canvasID ?: @"tracking",
            @"itemID": tracker.itemID ?: @"",
            @"mode": tracker.mode ?: @"",
            @"drawStyle": tracker.drawStyle ?: @"",
            @"label": tracker.label ?: @"",
            @"lastVisible": @(tracker.lastVisible),
            @"lastUpdatedAt": @(tracker.lastUpdatedAt),
            @"lastStatus": tracker.lastStatus ?: @"",
            @"updateInterval": @(tracker.updateInterval),
            @"maxConsecutiveFailures": @(tracker.maxConsecutiveFailures)
        }];
    }
    return @{
        @"success": @YES,
        @"summary": summary ?: @"Overlay tracking updated.",
        @"activeCount": @(self.trackers.count),
        @"trackers": [items copy]
    };
}

- (NSDictionary *)_artifactPayloadForTracker:(VCOverlayTracker *)tracker
                                   trackerID:(NSString *)trackerID
                                       title:(NSString *)title
                                    subtitle:(NSString *)subtitle {
    NSString *resolvedTitle = VCOverlayTrackTrimmedString(title);
    if (resolvedTitle.length == 0) {
        resolvedTitle = tracker.label.length > 0 ? tracker.label : [NSString stringWithFormat:@"%@ %@", tracker.mode ?: @"track", tracker.itemID ?: @"item"];
    }
    return @{
        @"queryType": @"track",
        @"trackerID": trackerID ?: @"",
        @"title": resolvedTitle ?: @"Track",
        @"subtitle": VCOverlayTrackTrimmedString(subtitle),
        @"createdAt": @([[NSDate date] timeIntervalSince1970]),
        @"canvasID": tracker.canvasID ?: @"tracking",
        @"itemID": tracker.itemID ?: @"",
        @"mode": tracker.mode ?: @"",
        @"config": tracker.config ?: @{},
        @"drawStyle": tracker.drawStyle ?: @"",
        @"label": tracker.label ?: @"",
        @"color": [self _stringColorFromColor:tracker.color fallback:@"#00d4ff"],
        @"fillColor": tracker.fillColor ? [self _stringColorFromColor:tracker.fillColor fallback:@""] : @"",
        @"backgroundColor": tracker.backgroundColor ? [self _stringColorFromColor:tracker.backgroundColor fallback:@""] : @"",
        @"lineWidth": @(tracker.lineWidth),
        @"fontSize": @(tracker.fontSize),
        @"radius": @(tracker.radius),
        @"cornerRadius": @(tracker.cornerRadius),
        @"labelOffsetX": @(tracker.labelOffsetX),
        @"labelOffsetY": @(tracker.labelOffsetY),
        @"updateInterval": @(tracker.updateInterval),
        @"maxConsecutiveFailures": @(tracker.maxConsecutiveFailures)
    };
}

- (NSDictionary *)_artifactSummaryFromPayload:(NSDictionary *)payload path:(NSString *)path {
    NSString *resolvedPath = VCOverlayTrackTrimmedString(path.length > 0 ? path : payload[@"path"]);
    return @{
        @"queryType": @"track",
        @"trackerID": payload[@"trackerID"] ?: @"",
        @"title": payload[@"title"] ?: @"Track",
        @"subtitle": payload[@"subtitle"] ?: @"",
        @"createdAt": payload[@"createdAt"] ?: @0,
        @"mode": payload[@"mode"] ?: @"",
        @"canvasID": payload[@"canvasID"] ?: @"tracking",
        @"itemID": payload[@"itemID"] ?: @"",
        @"path": resolvedPath ?: @""
    };
}

- (NSString *)_stringColorFromColor:(UIColor *)color fallback:(NSString *)fallback {
    if (![color isKindOfClass:[UIColor class]]) return fallback ?: @"";
    CGFloat r = 0;
    CGFloat g = 0;
    CGFloat b = 0;
    CGFloat a = 0;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) return fallback ?: @"";
    return [NSString stringWithFormat:@"#%02X%02X%02X%02X",
            (int)llround(r * 255.0),
            (int)llround(g * 255.0),
            (int)llround(b * 255.0),
            (int)llround(a * 255.0)];
}

- (VCOverlayTracker *)_trackerFromConfiguration:(NSDictionary *)configuration
                                   errorMessage:(NSString **)errorMessage {
    NSDictionary *params = [configuration isKindOfClass:[NSDictionary class]] ? configuration : @{};
    NSString *mode = VCOverlayTrackModeNormalized(VCOverlayTrackStringParam(params, @[@"trackMode", @"track_mode", @"mode", @"type"]));
    if (mode.length == 0) {
        if (errorMessage) *errorMessage = @"overlay_track start requires trackMode such as screen_point, screen_rect, project_point, project_bounds, unity_transform, or unity_renderer.";
        return nil;
    }

    NSMutableDictionary *normalized = [NSMutableDictionary new];
    NSString *canvasID = VCOverlayTrackCanvasID(VCOverlayTrackStringParam(params, @[@"canvasID", @"canvas", @"canvas_id"]));
    NSString *itemID = VCOverlayTrackItemID(VCOverlayTrackStringParam(params, @[@"itemID", @"item", @"item_id", @"id"]));
    normalized[@"canvasID"] = canvasID;
    normalized[@"itemID"] = itemID;
    normalized[@"mode"] = mode;

    if ([mode isEqualToString:@"screen_point"]) {
        uintptr_t pointAddress = VCOverlayTrackAddressParam(params, @[@"pointAddress", @"point_address", @"address"]);
        NSString *pointType = VCOverlayTrackStringParam(params, @[@"pointType", @"point_type", @"structType", @"struct_type", @"type"]);
        if (pointAddress == 0 || pointType.length == 0) {
            if (errorMessage) *errorMessage = @"overlay_track screen_point requires pointAddress plus pointType.";
            return nil;
        }
        normalized[@"pointAddress"] = VCOverlayTrackHexAddress(pointAddress);
        normalized[@"pointType"] = pointType;
    } else if ([mode isEqualToString:@"screen_rect"]) {
        uintptr_t rectAddress = VCOverlayTrackAddressParam(params, @[@"rectAddress", @"rect_address", @"address"]);
        NSString *rectType = VCOverlayTrackStringParam(params, @[@"rectType", @"rect_type", @"structType", @"struct_type", @"type"]);
        if (rectAddress == 0 || rectType.length == 0) {
            if (errorMessage) *errorMessage = @"overlay_track screen_rect requires rectAddress plus rectType.";
            return nil;
        }
        normalized[@"rectAddress"] = VCOverlayTrackHexAddress(rectAddress);
        normalized[@"rectType"] = rectType;
    } else if ([mode isEqualToString:@"project_point"] || [mode isEqualToString:@"project_bounds"]) {
        uintptr_t worldAddress = VCOverlayTrackAddressParam(params, @[@"worldAddress", @"world_address", @"address"]);
        NSString *worldType = VCOverlayTrackStringParam(params, @[@"worldType", @"world_type", @"vectorType", @"vector_type"]);
        double worldX = VCOverlayTrackDoubleParam(params, @[@"worldX", @"x"], NAN);
        double worldY = VCOverlayTrackDoubleParam(params, @[@"worldY", @"y"], NAN);
        double worldZ = VCOverlayTrackDoubleParam(params, @[@"worldZ", @"z"], NAN);
        double worldW = VCOverlayTrackDoubleParam(params, @[@"worldW", @"w"], 1.0);
        if ((isnan(worldX) || isnan(worldY) || isnan(worldZ)) && (worldAddress == 0 || worldType.length == 0)) {
            if (errorMessage) *errorMessage = @"overlay_track project modes require worldX/worldY/worldZ or worldAddress plus worldType.";
            return nil;
        }
        if (worldAddress > 0) normalized[@"worldAddress"] = VCOverlayTrackHexAddress(worldAddress);
        if (worldType.length > 0) normalized[@"worldType"] = worldType;
        if (!isnan(worldX)) normalized[@"worldX"] = @(worldX);
        if (!isnan(worldY)) normalized[@"worldY"] = @(worldY);
        if (!isnan(worldZ)) normalized[@"worldZ"] = @(worldZ);
        normalized[@"worldW"] = @(worldW);

        id matrixElements = params[@"matrixElements"] ?: params[@"matrix"];
        uintptr_t matrixAddress = VCOverlayTrackAddressParam(params, @[@"matrixAddress", @"matrix_address"]);
        NSString *matrixType = VCOverlayTrackStringParam(params, @[@"matrixType", @"matrix_type", @"type"]);
        NSString *matrixLayout = VCOverlayTrackStringParam(params, @[@"matrixLayout", @"matrix_layout", @"layout"]);
        if (![matrixElements isKindOfClass:[NSArray class]] && matrixAddress == 0) {
            if (errorMessage) *errorMessage = @"overlay_track project modes require matrixElements or matrixAddress.";
            return nil;
        }
        if ([matrixElements isKindOfClass:[NSArray class]]) normalized[@"matrixElements"] = matrixElements;
        if (matrixAddress > 0) normalized[@"matrixAddress"] = VCOverlayTrackHexAddress(matrixAddress);
        if (matrixType.length > 0) normalized[@"matrixType"] = matrixType;
        if (matrixLayout.length > 0) normalized[@"matrixLayout"] = matrixLayout;

        double viewportWidth = VCOverlayTrackDoubleParam(params, @[@"viewportWidth", @"viewport_width"], 0.0);
        double viewportHeight = VCOverlayTrackDoubleParam(params, @[@"viewportHeight", @"viewport_height"], 0.0);
        double viewportX = VCOverlayTrackDoubleParam(params, @[@"viewportX", @"viewport_x"], 0.0);
        double viewportY = VCOverlayTrackDoubleParam(params, @[@"viewportY", @"viewport_y"], 0.0);
        if (viewportWidth > 0.0) normalized[@"viewportWidth"] = @(viewportWidth);
        if (viewportHeight > 0.0) normalized[@"viewportHeight"] = @(viewportHeight);
        if (viewportX != 0.0) normalized[@"viewportX"] = @(viewportX);
        if (viewportY != 0.0) normalized[@"viewportY"] = @(viewportY);
        normalized[@"flipY"] = @(VCOverlayTrackBoolParam(params, @[@"flipY", @"flip_y"], YES));

        if ([mode isEqualToString:@"project_bounds"]) {
            uintptr_t extentAddress = VCOverlayTrackAddressParam(params, @[@"extentAddress", @"extent_address"]);
            NSString *extentType = VCOverlayTrackStringParam(params, @[@"extentType", @"extent_type"]);
            double extentX = VCOverlayTrackDoubleParam(params, @[@"extentX", @"ex"], NAN);
            double extentY = VCOverlayTrackDoubleParam(params, @[@"extentY", @"ey"], NAN);
            double extentZ = VCOverlayTrackDoubleParam(params, @[@"extentZ", @"ez"], NAN);
            if ((isnan(extentX) || isnan(extentY) || isnan(extentZ)) && (extentAddress == 0 || extentType.length == 0)) {
                if (errorMessage) *errorMessage = @"overlay_track project_bounds requires extents or extentAddress plus extentType.";
                return nil;
            }
            if (!isnan(extentX)) normalized[@"extentX"] = @(extentX);
            if (!isnan(extentY)) normalized[@"extentY"] = @(extentY);
            if (!isnan(extentZ)) normalized[@"extentZ"] = @(extentZ);
            if (extentAddress > 0) normalized[@"extentAddress"] = VCOverlayTrackHexAddress(extentAddress);
            if (extentType.length > 0) normalized[@"extentType"] = extentType;
        }
    } else if ([mode isEqualToString:@"unity_transform"]) {
        uintptr_t transformAddress = VCOverlayTrackAddressParam(params, @[@"transformAddress", @"transform_address"]);
        uintptr_t componentAddress = VCOverlayTrackAddressParam(params, @[@"componentAddress", @"component_address"]);
        uintptr_t gameObjectAddress = VCOverlayTrackAddressParam(params, @[@"gameObjectAddress", @"game_object_address"]);
        uintptr_t genericAddress = VCOverlayTrackAddressParam(params, @[@"address"]);
        uintptr_t cameraAddress = VCOverlayTrackAddressParam(params, @[@"cameraAddress", @"camera_address"]);
        NSString *objectKind = VCOverlayTrackStringParam(params, @[@"objectKind", @"object_kind", @"kind"]);

        if (transformAddress == 0 && componentAddress == 0 && gameObjectAddress == 0 && genericAddress == 0) {
            if (errorMessage) *errorMessage = @"overlay_track unity_transform requires transformAddress, componentAddress, gameObjectAddress, or address.";
            return nil;
        }
        if (transformAddress > 0) normalized[@"transformAddress"] = VCOverlayTrackHexAddress(transformAddress);
        if (componentAddress > 0) normalized[@"componentAddress"] = VCOverlayTrackHexAddress(componentAddress);
        if (gameObjectAddress > 0) normalized[@"gameObjectAddress"] = VCOverlayTrackHexAddress(gameObjectAddress);
        if (genericAddress > 0) normalized[@"address"] = VCOverlayTrackHexAddress(genericAddress);
        if (cameraAddress > 0) normalized[@"cameraAddress"] = VCOverlayTrackHexAddress(cameraAddress);
        if (objectKind.length > 0) normalized[@"objectKind"] = objectKind;
    } else if ([mode isEqualToString:@"unity_renderer"]) {
        uintptr_t rendererAddress = VCOverlayTrackAddressParam(params, @[@"rendererAddress", @"renderer_address", @"address"]);
        uintptr_t cameraAddress = VCOverlayTrackAddressParam(params, @[@"cameraAddress", @"camera_address"]);
        if (rendererAddress == 0) {
            if (errorMessage) *errorMessage = @"overlay_track unity_renderer requires rendererAddress or address.";
            return nil;
        }
        normalized[@"rendererAddress"] = VCOverlayTrackHexAddress(rendererAddress);
        if (cameraAddress > 0) normalized[@"cameraAddress"] = VCOverlayTrackHexAddress(cameraAddress);
    } else {
        if (errorMessage) *errorMessage = [NSString stringWithFormat:@"Unsupported overlay_track mode %@", mode];
        return nil;
    }

    VCOverlayTracker *tracker = [VCOverlayTracker new];
    tracker.canvasID = canvasID;
    tracker.itemID = itemID;
    tracker.mode = mode;
    tracker.config = [normalized copy];
    tracker.label = VCOverlayTrackStringParam(params, @[@"label", @"text"]);
    tracker.color = VCOverlayTrackColorFromString(VCOverlayTrackStringParam(params, @[@"color"]), kVCAccent);
    tracker.fillColor = VCOverlayTrackColorFromString(VCOverlayTrackStringParam(params, @[@"fillColor", @"fill_color"]), nil);
    tracker.backgroundColor = VCOverlayTrackColorFromString(VCOverlayTrackStringParam(params, @[@"backgroundColor", @"background_color"]), [kVCBgSurface colorWithAlphaComponent:0.84]);
    tracker.lineWidth = MAX(VCOverlayTrackDoubleParam(params, @[@"lineWidth", @"line_width"], 2.0), 1.0);
    tracker.fontSize = MAX(VCOverlayTrackDoubleParam(params, @[@"fontSize", @"font_size"], 12.0), 10.0);
    tracker.radius = MAX(VCOverlayTrackDoubleParam(params, @[@"radius"], 5.0), 2.0);
    tracker.cornerRadius = MAX(VCOverlayTrackDoubleParam(params, @[@"cornerRadius", @"corner_radius"], 8.0), 0.0);
    tracker.labelOffsetX = VCOverlayTrackDoubleParam(params, @[@"labelOffsetX", @"label_offset_x"], 8.0);
    tracker.labelOffsetY = VCOverlayTrackDoubleParam(params, @[@"labelOffsetY", @"label_offset_y"], -18.0);
    tracker.updateInterval = MAX(VCOverlayTrackDoubleParam(params, @[@"updateInterval", @"update_interval"], 1.0 / 15.0), 1.0 / 60.0);
    tracker.maxConsecutiveFailures = MAX((NSUInteger)VCOverlayTrackDoubleParam(params, @[@"maxConsecutiveFailures", @"max_consecutive_failures"], 45), (NSUInteger)1);
    tracker.drawStyle = [VCOverlayTrackStringParam(params, @[@"drawStyle", @"draw_style", @"style"]) lowercaseString];
    if (tracker.drawStyle.length == 0) {
        if ([mode isEqualToString:@"screen_rect"] || [mode isEqualToString:@"project_bounds"] || [mode isEqualToString:@"unity_renderer"]) {
            tracker.drawStyle = tracker.label.length > 0 ? @"box_label" : @"box";
        } else {
            tracker.drawStyle = tracker.label.length > 0 ? @"circle_label" : @"circle";
        }
    }
    tracker.lastStatus = @"Pending first projection.";
    return tracker;
}

- (void)_ensureDisplayLink {
    if (self.displayLink) {
        self.displayLink.paused = self.trackers.count == 0;
        return;
    }
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(_displayLinkTick:)];
    self.displayLink.preferredFramesPerSecond = 15;
    [self.displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    self.displayLink.paused = self.trackers.count == 0;
}

- (void)_updateDisplayLinkState {
    if (!self.displayLink) return;
    self.displayLink.paused = self.trackers.count == 0;
}

- (void)_displayLinkTick:(CADisplayLink *)link {
    (void)link;
    if (self.trackers.count == 0) return;
    NSArray<VCOverlayTracker *> *trackers = [self.trackers.allValues copy];
    for (VCOverlayTracker *tracker in trackers) {
        [self _refreshTracker:tracker];
    }
}

- (void)_refreshTracker:(VCOverlayTracker *)tracker {
    if (!tracker) return;
    NSDictionary *toolResult = [self _toolResultForTracker:tracker];
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    if (tracker.lastUpdatedAt > 0 && (now - tracker.lastUpdatedAt) < tracker.updateInterval) {
        return;
    }
    tracker.lastUpdatedAt = now;
    tracker.lastVisible = NO;

    if (![toolResult[@"success"] boolValue]) {
        tracker.lastStatus = VCOverlayTrackTrimmedString(toolResult[@"summary"]);
        tracker.consecutiveFailures += 1;
        [self _clearOverlayForTracker:tracker];
        if (tracker.consecutiveFailures >= tracker.maxConsecutiveFailures) {
            [self.trackers removeObjectForKey:[self _trackerKeyForCanvasIdentifier:tracker.canvasID itemIdentifier:tracker.itemID]];
            [self _updateDisplayLinkState];
        }
        return;
    }
    tracker.consecutiveFailures = 0;

    NSDictionary *payload = [toolResult[@"payload"] isKindOfClass:[NSDictionary class]] ? toolResult[@"payload"] : @{};
    if ([tracker.mode isEqualToString:@"screen_rect"] || [tracker.mode isEqualToString:@"project_bounds"] || [tracker.mode isEqualToString:@"unity_renderer"]) {
        NSDictionary *box = VCOverlayTrackScreenBox(payload);
        if (!box || ![payload[@"onScreen"] boolValue]) {
            tracker.lastStatus = VCOverlayTrackTrimmedString(toolResult[@"summary"]).length > 0 ? toolResult[@"summary"] : @"Tracked bounds are off-screen.";
            [self _clearOverlayForTracker:tracker];
            return;
        }

        CGRect rect = CGRectMake([box[@"x"] doubleValue],
                                 [box[@"y"] doubleValue],
                                 [box[@"width"] doubleValue],
                                 [box[@"height"] doubleValue]);
        [[VCOverlayCanvasManager shared] drawBox:rect
                                     strokeColor:tracker.color
                                       lineWidth:tracker.lineWidth
                                       fillColor:[tracker.drawStyle containsString:@"fill"] ? tracker.fillColor : nil
                                 canvasIdentifier:tracker.canvasID
                                   itemIdentifier:[self _boxItemIdentifierForTracker:tracker]
                                     cornerRadius:tracker.cornerRadius];

        if ([tracker.drawStyle containsString:@"label"] && tracker.label.length > 0) {
            CGPoint labelPoint = CGPointMake(CGRectGetMinX(rect) + tracker.labelOffsetX,
                                             MAX(2.0, CGRectGetMinY(rect) + tracker.labelOffsetY));
            [[VCOverlayCanvasManager shared] drawText:tracker.label
                                              atPoint:labelPoint
                                                color:tracker.color
                                             fontSize:tracker.fontSize
                                      backgroundColor:tracker.backgroundColor
                                     canvasIdentifier:tracker.canvasID
                                       itemIdentifier:[self _labelItemIdentifierForTracker:tracker]];
        } else {
            [[VCOverlayCanvasManager shared] clearCanvasWithIdentifier:tracker.canvasID
                                                        itemIdentifier:[self _labelItemIdentifierForTracker:tracker]];
        }
        [[VCOverlayCanvasManager shared] clearCanvasWithIdentifier:tracker.canvasID
                                                    itemIdentifier:[self _pointItemIdentifierForTracker:tracker]];
        tracker.lastVisible = YES;
        tracker.lastStatus = @"Tracking screen box";
        return;
    }

    NSDictionary *point = VCOverlayTrackScreenPoint(payload);
    if (!point || ![payload[@"onScreen"] boolValue]) {
        tracker.lastStatus = VCOverlayTrackTrimmedString(toolResult[@"summary"]).length > 0 ? toolResult[@"summary"] : @"Tracked point is off-screen.";
        [self _clearOverlayForTracker:tracker];
        return;
    }

    CGPoint center = CGPointMake([point[@"x"] doubleValue], [point[@"y"] doubleValue]);
    if ([tracker.drawStyle containsString:@"circle"] || [tracker.drawStyle containsString:@"point"]) {
        [[VCOverlayCanvasManager shared] drawCircleAtPoint:center
                                                    radius:tracker.radius
                                               strokeColor:tracker.color
                                                 lineWidth:tracker.lineWidth
                                                 fillColor:[tracker.drawStyle containsString:@"fill"] ? tracker.fillColor : nil
                                          canvasIdentifier:tracker.canvasID
                                            itemIdentifier:[self _pointItemIdentifierForTracker:tracker]];
    } else {
        [[VCOverlayCanvasManager shared] clearCanvasWithIdentifier:tracker.canvasID
                                                    itemIdentifier:[self _pointItemIdentifierForTracker:tracker]];
    }

    if ([tracker.drawStyle containsString:@"label"] && tracker.label.length > 0) {
        CGPoint labelPoint = CGPointMake(center.x + tracker.labelOffsetX, center.y + tracker.labelOffsetY);
        [[VCOverlayCanvasManager shared] drawText:tracker.label
                                          atPoint:labelPoint
                                            color:tracker.color
                                         fontSize:tracker.fontSize
                                  backgroundColor:tracker.backgroundColor
                                 canvasIdentifier:tracker.canvasID
                                   itemIdentifier:[self _labelItemIdentifierForTracker:tracker]];
    } else {
        [[VCOverlayCanvasManager shared] clearCanvasWithIdentifier:tracker.canvasID
                                                    itemIdentifier:[self _labelItemIdentifierForTracker:tracker]];
    }
    [[VCOverlayCanvasManager shared] clearCanvasWithIdentifier:tracker.canvasID
                                                itemIdentifier:[self _boxItemIdentifierForTracker:tracker]];
    tracker.lastVisible = YES;
    tracker.lastStatus = @"Tracking screen point";
}

- (NSDictionary *)_toolResultForTracker:(VCOverlayTracker *)tracker {
    if (!tracker) return @{@"success": @NO, @"summary": @"Missing tracker."};

    VCToolCall *toolCall = [[VCToolCall alloc] init];
    toolCall.toolID = [[NSUUID UUID] UUIDString];

    NSMutableDictionary *params = [tracker.config mutableCopy] ?: [NSMutableDictionary new];
    if ([tracker.mode isEqualToString:@"screen_point"]) {
        toolCall.type = VCToolCallQueryMemory;
        toolCall.title = @"query_memory";
        params[@"queryType"] = @"read_struct";
        params[@"address"] = params[@"pointAddress"] ?: params[@"address"] ?: @"";
        params[@"structType"] = params[@"pointType"] ?: params[@"structType"] ?: @"";
    } else if ([tracker.mode isEqualToString:@"screen_rect"]) {
        toolCall.type = VCToolCallQueryMemory;
        toolCall.title = @"query_memory";
        params[@"queryType"] = @"read_struct";
        params[@"address"] = params[@"rectAddress"] ?: params[@"address"] ?: @"";
        params[@"structType"] = params[@"rectType"] ?: params[@"structType"] ?: @"";
    } else if ([tracker.mode isEqualToString:@"project_point"]) {
        toolCall.type = VCToolCallProject3D;
        toolCall.title = @"project_3d";
        params[@"mode"] = @"point";
    } else if ([tracker.mode isEqualToString:@"project_bounds"]) {
        toolCall.type = VCToolCallProject3D;
        toolCall.title = @"project_3d";
        params[@"mode"] = @"bounds";
    } else if ([tracker.mode isEqualToString:@"unity_transform"]) {
        toolCall.type = VCToolCallUnityRuntime;
        toolCall.title = @"unity_runtime";
        params[@"queryType"] = @"world_to_screen";
    } else if ([tracker.mode isEqualToString:@"unity_renderer"]) {
        toolCall.type = VCToolCallUnityRuntime;
        toolCall.title = @"unity_runtime";
        params[@"queryType"] = @"project_renderer_bounds";
    } else {
        return @{@"success": @NO, @"summary": [NSString stringWithFormat:@"Unsupported tracker mode %@", tracker.mode ?: @""]};
    }
    toolCall.params = [params copy];

    NSDictionary *result = [VCAIReadOnlyToolExecutor executeToolCalls:@[toolCall]].firstObject;
    if (![result isKindOfClass:[NSDictionary class]]) {
        return @{@"success": @NO, @"summary": @"Tracking projection did not return a result."};
    }

    if ([tracker.mode isEqualToString:@"screen_point"] || [tracker.mode isEqualToString:@"screen_rect"]) {
        NSMutableDictionary *resultPayload = [result mutableCopy];
        NSMutableDictionary *payload = [resultPayload[@"payload"] isKindOfClass:[NSDictionary class]] ? [resultPayload[@"payload"] mutableCopy] : [NSMutableDictionary new];
        NSDictionary *value = [payload[@"value"] isKindOfClass:[NSDictionary class]] ? payload[@"value"] : nil;
        if ([tracker.mode isEqualToString:@"screen_point"]) {
            if ([value[@"x"] respondsToSelector:@selector(doubleValue)] &&
                [value[@"y"] respondsToSelector:@selector(doubleValue)]) {
                payload[@"screenPoint"] = @{@"x": value[@"x"], @"y": value[@"y"]};
                payload[@"onScreen"] = @YES;
            }
        } else {
            if ([value[@"x"] respondsToSelector:@selector(doubleValue)] &&
                [value[@"y"] respondsToSelector:@selector(doubleValue)] &&
                [value[@"width"] respondsToSelector:@selector(doubleValue)] &&
                [value[@"height"] respondsToSelector:@selector(doubleValue)]) {
                payload[@"screenBox"] = @{
                    @"x": value[@"x"],
                    @"y": value[@"y"],
                    @"width": value[@"width"],
                    @"height": value[@"height"]
                };
                payload[@"onScreen"] = @YES;
            }
        }
        resultPayload[@"payload"] = [payload copy];
        return [resultPayload copy];
    }
    return result;
}

- (NSString *)_boxItemIdentifierForTracker:(VCOverlayTracker *)tracker {
    return [NSString stringWithFormat:@"%@.box", tracker.itemID ?: @"item"];
}

- (NSString *)_pointItemIdentifierForTracker:(VCOverlayTracker *)tracker {
    return [NSString stringWithFormat:@"%@.point", tracker.itemID ?: @"item"];
}

- (NSString *)_labelItemIdentifierForTracker:(VCOverlayTracker *)tracker {
    return [NSString stringWithFormat:@"%@.label", tracker.itemID ?: @"item"];
}

- (void)_clearOverlayForTracker:(VCOverlayTracker *)tracker {
    if (!tracker) return;
    VCOverlayCanvasManager *canvas = [VCOverlayCanvasManager shared];
    [canvas clearCanvasWithIdentifier:tracker.canvasID itemIdentifier:[self _boxItemIdentifierForTracker:tracker]];
    [canvas clearCanvasWithIdentifier:tracker.canvasID itemIdentifier:[self _pointItemIdentifierForTracker:tracker]];
    [canvas clearCanvasWithIdentifier:tracker.canvasID itemIdentifier:[self _labelItemIdentifierForTracker:tracker]];
}

@end
