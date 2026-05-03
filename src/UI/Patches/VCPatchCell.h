/**
 * VCPatchCell -- Patches 列表 Cell
 * Slide-12: Patches Engine UI
 */

#import <UIKit/UIKit.h>

@class VCPatchItem;
@class VCValueItem;
@class VCHookItem;
@class VCNetRule;
@class VCPatchCell;

@protocol VCPatchCellDelegate <NSObject>
- (void)patchCell:(VCPatchCell *)cell didToggleEnabled:(BOOL)enabled;
@end

@interface VCPatchCell : UITableViewCell

@property (nonatomic, weak) id<VCPatchCellDelegate> delegate;

- (void)configureWithPatch:(VCPatchItem *)item;
- (void)configureWithValue:(VCValueItem *)item;
- (void)configureWithHook:(VCHookItem *)item;
- (void)configureWithRule:(VCNetRule *)item;

@end
