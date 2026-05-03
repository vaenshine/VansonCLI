/**
 * VCTouchOverlay.h -- Touch-to-select overlay
 * Slide-4: UI Inspector Engine
 */

#import <UIKit/UIKit.h>

@class VCTouchOverlay;

// ═══════════════════════════════════════════════════════════════
// VCTouchOverlayDelegate
// ═══════════════════════════════════════════════════════════════
@protocol VCTouchOverlayDelegate <NSObject>
- (void)touchOverlay:(VCTouchOverlay *)overlay didSelectView:(UIView *)view;
@optional
- (void)touchOverlayDidCancel:(VCTouchOverlay *)overlay;
@end

// ═══════════════════════════════════════════════════════════════
// VCTouchOverlay
// ═══════════════════════════════════════════════════════════════
@interface VCTouchOverlay : NSObject

+ (instancetype)shared;

@property (nonatomic, weak) id<VCTouchOverlayDelegate> delegate;
@property (nonatomic, readonly) BOOL isPicking;

- (void)startPicking;
- (void)stopPicking;

@end
