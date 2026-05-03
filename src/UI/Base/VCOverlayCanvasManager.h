/**
 * VCOverlayCanvasManager -- non-interactive drawing canvas for overlay annotations
 */

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface VCOverlayCanvasManager : NSObject

+ (instancetype)shared;
+ (BOOL)hasAttachedCanvas;

- (void)clearCanvasWithIdentifier:(NSString * _Nullable)canvasID
                   itemIdentifier:(NSString * _Nullable)itemID;
- (void)clearCanvasWithIdentifier:(NSString * _Nullable)canvasID
             itemIdentifierPrefix:(NSString * _Nullable)itemIDPrefix;
- (void)setCanvasHidden:(BOOL)hidden identifier:(NSString * _Nullable)canvasID;

- (BOOL)drawLineFrom:(CGPoint)start
                  to:(CGPoint)end
               color:(UIColor *)color
           lineWidth:(CGFloat)lineWidth
    canvasIdentifier:(NSString * _Nullable)canvasID
      itemIdentifier:(NSString * _Nullable)itemID;

- (BOOL)drawBox:(CGRect)rect
    strokeColor:(UIColor *)strokeColor
      lineWidth:(CGFloat)lineWidth
      fillColor:(UIColor * _Nullable)fillColor
canvasIdentifier:(NSString * _Nullable)canvasID
 itemIdentifier:(NSString * _Nullable)itemID
   cornerRadius:(CGFloat)cornerRadius;

- (BOOL)drawCircleAtPoint:(CGPoint)center
                   radius:(CGFloat)radius
              strokeColor:(UIColor *)strokeColor
                lineWidth:(CGFloat)lineWidth
                fillColor:(UIColor * _Nullable)fillColor
         canvasIdentifier:(NSString * _Nullable)canvasID
           itemIdentifier:(NSString * _Nullable)itemID;

- (BOOL)drawText:(NSString *)text
         atPoint:(CGPoint)point
           color:(UIColor *)color
        fontSize:(CGFloat)fontSize
 backgroundColor:(UIColor * _Nullable)backgroundColor
canvasIdentifier:(NSString * _Nullable)canvasID
  itemIdentifier:(NSString * _Nullable)itemID;

- (BOOL)drawPolylineWithPoints:(NSArray<NSValue *> *)points
                   strokeColor:(UIColor *)strokeColor
                     lineWidth:(CGFloat)lineWidth
                     fillColor:(UIColor * _Nullable)fillColor
                        closed:(BOOL)closed
              canvasIdentifier:(NSString * _Nullable)canvasID
                itemIdentifier:(NSString * _Nullable)itemID;

@end

NS_ASSUME_NONNULL_END
