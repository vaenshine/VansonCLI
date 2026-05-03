/**
 * VCUIInspector.h -- UI hierarchy inspector + property read/modify
 * Slide-4: UI Inspector Engine
 */

#import <UIKit/UIKit.h>

extern NSString *const kVCUIInspectorDidSelectViewNotification;

@class VCViewNode;

// ═══════════════════════════════════════════════════════════════
// VCViewNode -- View tree node
// ═══════════════════════════════════════════════════════════════
@interface VCViewNode : NSObject
@property (nonatomic, strong) NSString *className;
@property (nonatomic, strong) NSString *briefDescription;
@property (nonatomic, assign) CGRect frame;
@property (nonatomic, assign) uintptr_t address;
@property (nonatomic, strong) NSArray<VCViewNode *> *children;
@property (nonatomic, weak) UIView *view;
@end

// ═══════════════════════════════════════════════════════════════
// VCUIInspector
// ═══════════════════════════════════════════════════════════════
@interface VCUIInspector : NSObject

+ (instancetype)shared;

@property (nonatomic, weak, readonly) UIView *currentSelectedView;
@property (nonatomic, assign) BOOL selectionHighlightEnabled;

/// Build full view hierarchy tree from all windows
- (VCViewNode *)viewHierarchyTree;

/// Read all properties for a given view
- (NSDictionary *)propertiesForView:(UIView *)view;

/// Walk responder chain, return class name array
- (NSArray<NSString *> *)responderChainForView:(UIView *)view;

/// Highlight a view with red border
- (void)highlightView:(UIView *)view;

/// Clear all highlights (restore original border)
- (void)clearHighlights;

/// Modify a view property (hidden/alpha/backgroundColor/frame/tag)
- (void)modifyView:(UIView *)view property:(NSString *)key value:(id)value;

/// Screenshot a view
- (UIImage *)screenshotView:(UIView *)view;

/// Remember the last user-selected view for context collection
- (void)rememberSelectedView:(UIView *)view;

/// Resolve a live view by address, if it is still in the hierarchy
- (UIView *)viewForAddress:(uintptr_t)address;

/// Insert a native subview into an existing view using a simple spec dictionary
- (UIView *)insertSubviewIntoView:(UIView *)parentView spec:(NSDictionary *)spec;

/// Invoke a selector on a target object with zero or one argument
- (BOOL)invokeSelector:(NSString *)selectorName onTarget:(id)target argument:(id)argument result:(NSString **)resultMessage;

@end
