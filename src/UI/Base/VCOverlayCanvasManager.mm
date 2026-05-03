/**
 * VCOverlayCanvasManager -- lightweight screen-space drawing layers for AI/runtime annotations
 */

#import "VCOverlayCanvasManager.h"
#import "VCOverlayWindow.h"
#import "../../../VansonCLI.h"

#import <QuartzCore/QuartzCore.h>

static BOOL gVCOverlayCanvasAttached = NO;

static NSString *VCCanvasNormalizedIdentifier(NSString *value, NSString *fallback) {
    NSString *trimmed = [value isKindOfClass:[NSString class]]
        ? [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
        : @"";
    return trimmed.length > 0 ? trimmed : fallback;
}

static UIColor *VCCanvasResolvedColor(UIColor *color, UIColor *fallback) {
    return [color isKindOfClass:[UIColor class]] ? color : fallback;
}

@interface VCOverlayCanvasManager ()
@property (nonatomic, strong) UIView *canvasView;
@property (nonatomic, strong) NSMutableDictionary<NSString *, CALayer *> *canvasLayers;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, CALayer *> *> *itemLayers;
@property (nonatomic, assign) BOOL observersInstalled;
@end

@implementation VCOverlayCanvasManager

+ (instancetype)shared {
    static VCOverlayCanvasManager *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VCOverlayCanvasManager alloc] init];
    });
    return instance;
}

+ (BOOL)hasAttachedCanvas {
    return gVCOverlayCanvasAttached;
}

- (instancetype)init {
    if ((self = [super init])) {
        _canvasLayers = [NSMutableDictionary new];
        _itemLayers = [NSMutableDictionary new];
        [self _installObserversIfNeeded];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)clearCanvasWithIdentifier:(NSString *)canvasID
                   itemIdentifier:(NSString *)itemID {
    [self _performOnMainThread:^{
        [self _ensureCanvasAttached];
        NSString *normalizedCanvasID = VCCanvasNormalizedIdentifier(canvasID, @"default");
        NSString *normalizedItemID = VCCanvasNormalizedIdentifier(itemID, @"");

        CALayer *canvasLayer = self.canvasLayers[normalizedCanvasID];
        if (!canvasLayer) return;

        if (normalizedItemID.length > 0) {
            CALayer *itemLayer = self.itemLayers[normalizedCanvasID][normalizedItemID];
            [itemLayer removeFromSuperlayer];
            [self.itemLayers[normalizedCanvasID] removeObjectForKey:normalizedItemID];
            if (self.itemLayers[normalizedCanvasID].count == 0) {
                [self.itemLayers removeObjectForKey:normalizedCanvasID];
                [self.canvasLayers removeObjectForKey:normalizedCanvasID];
                [canvasLayer removeFromSuperlayer];
            }
            return;
        }

        [canvasLayer removeFromSuperlayer];
        [self.canvasLayers removeObjectForKey:normalizedCanvasID];
        [self.itemLayers removeObjectForKey:normalizedCanvasID];
    }];
}

- (void)clearCanvasWithIdentifier:(NSString *)canvasID
             itemIdentifierPrefix:(NSString *)itemIDPrefix {
    [self _performOnMainThread:^{
        [self _ensureCanvasAttached];
        NSString *normalizedCanvasID = VCCanvasNormalizedIdentifier(canvasID, @"default");
        NSString *normalizedPrefix = VCCanvasNormalizedIdentifier(itemIDPrefix, @"");
        if (normalizedPrefix.length == 0) return;

        CALayer *canvasLayer = self.canvasLayers[normalizedCanvasID];
        NSMutableDictionary<NSString *, CALayer *> *items = self.itemLayers[normalizedCanvasID];
        if (!canvasLayer || items.count == 0) return;

        NSMutableArray<NSString *> *keysToRemove = [NSMutableArray new];
        for (NSString *key in items.allKeys ?: @[]) {
            if (![key hasPrefix:normalizedPrefix]) continue;
            [items[key] removeFromSuperlayer];
            [keysToRemove addObject:key];
        }
        [items removeObjectsForKeys:keysToRemove];
        if (items.count == 0) {
            [self.itemLayers removeObjectForKey:normalizedCanvasID];
            [self.canvasLayers removeObjectForKey:normalizedCanvasID];
            [canvasLayer removeFromSuperlayer];
        }
    }];
}

- (void)setCanvasHidden:(BOOL)hidden identifier:(NSString *)canvasID {
    [self _performOnMainThread:^{
        [self _ensureCanvasAttached];
        NSString *normalizedCanvasID = VCCanvasNormalizedIdentifier(canvasID, @"default");
        CALayer *canvasLayer = [self _canvasLayerForIdentifier:normalizedCanvasID createIfNeeded:NO];
        canvasLayer.hidden = hidden;
    }];
}

- (BOOL)drawLineFrom:(CGPoint)start
                  to:(CGPoint)end
               color:(UIColor *)color
           lineWidth:(CGFloat)lineWidth
    canvasIdentifier:(NSString *)canvasID
      itemIdentifier:(NSString *)itemID {
    __block BOOL success = NO;
    [self _performOnMainThread:^{
        [self _ensureCanvasAttached];
        NSString *normalizedCanvasID = VCCanvasNormalizedIdentifier(canvasID, @"default");
        NSString *normalizedItemID = VCCanvasNormalizedIdentifier(itemID, [[NSUUID UUID] UUIDString]);

        UIBezierPath *path = [UIBezierPath bezierPath];
        [path moveToPoint:start];
        [path addLineToPoint:end];

        CAShapeLayer *shape = [CAShapeLayer layer];
        shape.frame = self.canvasView.bounds;
        shape.path = path.CGPath;
        shape.strokeColor = VCCanvasResolvedColor(color, kVCAccent).CGColor;
        shape.fillColor = [UIColor clearColor].CGColor;
        shape.lineWidth = MAX(lineWidth, 1.0);
        shape.contentsScale = UIScreen.mainScreen.scale;

        [self _setItemLayer:shape canvasIdentifier:normalizedCanvasID itemIdentifier:normalizedItemID];
        success = YES;
    }];
    return success;
}

- (BOOL)drawBox:(CGRect)rect
    strokeColor:(UIColor *)strokeColor
      lineWidth:(CGFloat)lineWidth
      fillColor:(UIColor *)fillColor
canvasIdentifier:(NSString *)canvasID
 itemIdentifier:(NSString *)itemID
   cornerRadius:(CGFloat)cornerRadius {
    __block BOOL success = NO;
    [self _performOnMainThread:^{
        [self _ensureCanvasAttached];
        NSString *normalizedCanvasID = VCCanvasNormalizedIdentifier(canvasID, @"default");
        NSString *normalizedItemID = VCCanvasNormalizedIdentifier(itemID, [[NSUUID UUID] UUIDString]);

        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:MAX(cornerRadius, 0.0)];
        CAShapeLayer *shape = [CAShapeLayer layer];
        shape.frame = self.canvasView.bounds;
        shape.path = path.CGPath;
        shape.strokeColor = VCCanvasResolvedColor(strokeColor, kVCAccent).CGColor;
        shape.fillColor = (fillColor ?: [UIColor clearColor]).CGColor;
        shape.lineWidth = MAX(lineWidth, 1.0);
        shape.contentsScale = UIScreen.mainScreen.scale;

        [self _setItemLayer:shape canvasIdentifier:normalizedCanvasID itemIdentifier:normalizedItemID];
        success = YES;
    }];
    return success;
}

- (BOOL)drawCircleAtPoint:(CGPoint)center
                   radius:(CGFloat)radius
              strokeColor:(UIColor *)strokeColor
                lineWidth:(CGFloat)lineWidth
                fillColor:(UIColor *)fillColor
         canvasIdentifier:(NSString *)canvasID
           itemIdentifier:(NSString *)itemID {
    __block BOOL success = NO;
    [self _performOnMainThread:^{
        [self _ensureCanvasAttached];
        NSString *normalizedCanvasID = VCCanvasNormalizedIdentifier(canvasID, @"default");
        NSString *normalizedItemID = VCCanvasNormalizedIdentifier(itemID, [[NSUUID UUID] UUIDString]);
        CGFloat clampedRadius = MAX(radius, 2.0);
        CGRect circleRect = CGRectMake(center.x - clampedRadius,
                                       center.y - clampedRadius,
                                       clampedRadius * 2.0,
                                       clampedRadius * 2.0);

        UIBezierPath *path = [UIBezierPath bezierPathWithOvalInRect:circleRect];
        CAShapeLayer *shape = [CAShapeLayer layer];
        shape.frame = self.canvasView.bounds;
        shape.path = path.CGPath;
        shape.strokeColor = VCCanvasResolvedColor(strokeColor, kVCAccent).CGColor;
        shape.fillColor = (fillColor ?: [UIColor clearColor]).CGColor;
        shape.lineWidth = MAX(lineWidth, 1.0);
        shape.contentsScale = UIScreen.mainScreen.scale;

        [self _setItemLayer:shape canvasIdentifier:normalizedCanvasID itemIdentifier:normalizedItemID];
        success = YES;
    }];
    return success;
}

- (BOOL)drawText:(NSString *)text
         atPoint:(CGPoint)point
           color:(UIColor *)color
        fontSize:(CGFloat)fontSize
 backgroundColor:(UIColor *)backgroundColor
canvasIdentifier:(NSString *)canvasID
  itemIdentifier:(NSString *)itemID {
    NSString *trimmed = [text isKindOfClass:[NSString class]]
        ? [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
        : @"";
    if (trimmed.length == 0) return NO;

    __block BOOL success = NO;
    [self _performOnMainThread:^{
        [self _ensureCanvasAttached];
        NSString *normalizedCanvasID = VCCanvasNormalizedIdentifier(canvasID, @"default");
        NSString *normalizedItemID = VCCanvasNormalizedIdentifier(itemID, [[NSUUID UUID] UUIDString]);

        UIFont *font = [UIFont systemFontOfSize:MAX(fontSize, 11.0) weight:UIFontWeightSemibold];
        CGSize textSize = [trimmed sizeWithAttributes:@{ NSFontAttributeName: font }];
        CGFloat paddingX = 7.0;
        CGFloat paddingY = 4.0;
        CGRect frame = CGRectMake(point.x,
                                  point.y,
                                  ceil(textSize.width + paddingX * 2.0),
                                  ceil(textSize.height + paddingY * 2.0));

        CALayer *container = [CALayer layer];
        container.frame = frame;
        container.cornerRadius = 7.0;
        container.backgroundColor = (backgroundColor ?: [kVCBgSurface colorWithAlphaComponent:0.84]).CGColor;
        container.borderWidth = 1.0;
        container.borderColor = [kVCBorderStrong colorWithAlphaComponent:0.85].CGColor;
        container.contentsScale = UIScreen.mainScreen.scale;

        CATextLayer *textLayer = [CATextLayer layer];
        textLayer.frame = CGRectMake(paddingX, paddingY - 1.0, ceil(textSize.width), ceil(textSize.height + 2.0));
        textLayer.foregroundColor = VCCanvasResolvedColor(color, kVCTextPrimary).CGColor;
        textLayer.contentsScale = UIScreen.mainScreen.scale;
        textLayer.alignmentMode = kCAAlignmentLeft;
        textLayer.wrapped = NO;
        textLayer.font = (__bridge CFTypeRef)font.fontName;
        textLayer.fontSize = font.pointSize;
        textLayer.string = trimmed;
        [container addSublayer:textLayer];

        [self _setItemLayer:container canvasIdentifier:normalizedCanvasID itemIdentifier:normalizedItemID];
        success = YES;
    }];
    return success;
}

- (BOOL)drawPolylineWithPoints:(NSArray<NSValue *> *)points
                   strokeColor:(UIColor *)strokeColor
                     lineWidth:(CGFloat)lineWidth
                     fillColor:(UIColor *)fillColor
                        closed:(BOOL)closed
              canvasIdentifier:(NSString *)canvasID
                itemIdentifier:(NSString *)itemID {
    if (![points isKindOfClass:[NSArray class]] || points.count < 2) return NO;

    __block BOOL success = NO;
    [self _performOnMainThread:^{
        [self _ensureCanvasAttached];
        NSString *normalizedCanvasID = VCCanvasNormalizedIdentifier(canvasID, @"default");
        NSString *normalizedItemID = VCCanvasNormalizedIdentifier(itemID, [[NSUUID UUID] UUIDString]);

        UIBezierPath *path = [UIBezierPath bezierPath];
        CGPoint firstPoint = CGPointZero;
        BOOL didMove = NO;
        for (id value in points) {
            if (![value isKindOfClass:[NSValue class]]) continue;
            CGPoint point = [value CGPointValue];
            if (!didMove) {
                firstPoint = point;
                [path moveToPoint:point];
                didMove = YES;
            } else {
                [path addLineToPoint:point];
            }
        }
        if (!didMove) return;
        if (closed) [path addLineToPoint:firstPoint];

        CAShapeLayer *shape = [CAShapeLayer layer];
        shape.frame = self.canvasView.bounds;
        shape.path = path.CGPath;
        shape.strokeColor = VCCanvasResolvedColor(strokeColor, kVCAccent).CGColor;
        shape.fillColor = (closed ? (fillColor ?: [UIColor clearColor]) : [UIColor clearColor]).CGColor;
        shape.lineWidth = MAX(lineWidth, 1.0);
        shape.lineJoin = kCALineJoinRound;
        shape.lineCap = kCALineCapRound;
        shape.contentsScale = UIScreen.mainScreen.scale;

        [self _setItemLayer:shape canvasIdentifier:normalizedCanvasID itemIdentifier:normalizedItemID];
        success = YES;
    }];
    return success;
}

#pragma mark - Private

- (void)_installObserversIfNeeded {
    if (self.observersInstalled) return;
    self.observersInstalled = YES;
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(_overlayGeometryDidChange:) name:VCOverlayWindowGeometryDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(_overlayGeometryDidChange:) name:UIApplicationDidBecomeActiveNotification object:nil];
}

- (void)_overlayGeometryDidChange:(NSNotification *)notification {
    (void)notification;
    [self _performOnMainThread:^{
        [self _updateCanvasFrame];
    }];
}

- (void)_performOnMainThread:(dispatch_block_t)block {
    if (!block) return;
    if ([NSThread isMainThread]) {
        block();
    } else {
        dispatch_sync(dispatch_get_main_queue(), block);
    }
}

- (void)_ensureCanvasAttached {
    VCOverlayWindow *overlayWindow = [VCOverlayWindow shared];
    [overlayWindow showOverlay];
    [overlayWindow refreshGeometryIfNeeded];

    UIView *rootView = overlayWindow.rootViewController.view;
    if (!rootView) return;

    if (!self.canvasView) {
        UIView *canvasView = [[UIView alloc] initWithFrame:CGRectZero];
        canvasView.translatesAutoresizingMaskIntoConstraints = NO;
        canvasView.backgroundColor = [UIColor clearColor];
        canvasView.opaque = NO;
        canvasView.userInteractionEnabled = NO;
        canvasView.accessibilityIdentifier = @"vc.overlay.canvas";
        self.canvasView = canvasView;
    }

    if (self.canvasView.superview != rootView) {
        [self.canvasView removeFromSuperview];
        [rootView insertSubview:self.canvasView atIndex:0];
        [NSLayoutConstraint activateConstraints:@[
            [self.canvasView.topAnchor constraintEqualToAnchor:rootView.topAnchor],
            [self.canvasView.leadingAnchor constraintEqualToAnchor:rootView.leadingAnchor],
            [self.canvasView.trailingAnchor constraintEqualToAnchor:rootView.trailingAnchor],
            [self.canvasView.bottomAnchor constraintEqualToAnchor:rootView.bottomAnchor],
        ]];
    }

    [self _updateCanvasFrame];
    gVCOverlayCanvasAttached = YES;
}

- (void)_updateCanvasFrame {
    if (!self.canvasView) return;
    UIView *rootView = [VCOverlayWindow shared].rootViewController.view;
    if (!rootView) return;
    self.canvasView.frame = rootView.bounds;
    for (CALayer *layer in self.canvasLayers.allValues) {
        layer.frame = self.canvasView.bounds;
    }
}

- (CALayer *)_canvasLayerForIdentifier:(NSString *)canvasID createIfNeeded:(BOOL)createIfNeeded {
    NSString *normalizedCanvasID = VCCanvasNormalizedIdentifier(canvasID, @"default");
    CALayer *layer = self.canvasLayers[normalizedCanvasID];
    if (!layer && createIfNeeded) {
        layer = [CALayer layer];
        layer.frame = self.canvasView.bounds;
        layer.masksToBounds = NO;
        layer.contentsScale = UIScreen.mainScreen.scale;
        [self.canvasView.layer addSublayer:layer];
        self.canvasLayers[normalizedCanvasID] = layer;
        self.itemLayers[normalizedCanvasID] = [NSMutableDictionary new];
    }
    return layer;
}

- (void)_setItemLayer:(CALayer *)layer
    canvasIdentifier:(NSString *)canvasID
      itemIdentifier:(NSString *)itemID {
    CALayer *canvasLayer = [self _canvasLayerForIdentifier:canvasID createIfNeeded:YES];
    if (!canvasLayer || !layer) return;

    NSMutableDictionary<NSString *, CALayer *> *canvasItems = self.itemLayers[canvasID];
    CALayer *existing = canvasItems[itemID];
    if (existing) {
        [existing removeFromSuperlayer];
    }

    layer.frame = layer.frame;
    [canvasLayer addSublayer:layer];
    canvasItems[itemID] = layer;
}

@end
