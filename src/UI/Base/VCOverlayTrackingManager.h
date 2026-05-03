/**
 * VCOverlayTrackingManager -- lightweight per-frame projection + redraw tracker
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface VCOverlayTrackingManager : NSObject

+ (instancetype)shared;

- (NSDictionary *)startTrackerWithConfiguration:(NSDictionary *)configuration;
- (NSDictionary *)stopTrackerWithItemIdentifier:(NSString * _Nullable)itemID
                               canvasIdentifier:(NSString * _Nullable)canvasID;
- (NSDictionary *)clearTrackersForCanvasIdentifier:(NSString * _Nullable)canvasID;
- (NSDictionary *)statusForItemIdentifier:(NSString * _Nullable)itemID
                         canvasIdentifier:(NSString * _Nullable)canvasID;
- (NSDictionary *)saveTrackerWithItemIdentifier:(NSString * _Nullable)itemID
                               canvasIdentifier:(NSString * _Nullable)canvasID
                                          title:(NSString * _Nullable)title
                                       subtitle:(NSString * _Nullable)subtitle;
- (NSDictionary *)restoreTrackerFromPath:(NSString * _Nullable)path
                               trackerID:(NSString * _Nullable)trackerID;
- (NSArray<NSDictionary *> *)savedTrackerSummariesWithLimit:(NSUInteger)limit;
- (NSDictionary * _Nullable)savedTrackerDetailFromPath:(NSString * _Nullable)path
                                             trackerID:(NSString * _Nullable)trackerID;

@end

NS_ASSUME_NONNULL_END
