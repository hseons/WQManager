//
//  WQMSpaceLensView.h
//  WQManager
//
//  The bubble canvas of the space lens: one bubble per container item, area
//  proportional to bytes, tap to drill in.
//

#import <UIKit/UIKit.h>
#import "WQMBubbleLayout.h"

NS_ASSUME_NONNULL_BEGIN

/// Shared glyph rules for the lens: the bubble canvas and the list mode both
/// draw the same symbol and colour for a given kind of item.
@interface WQMSpaceLensIcon : NSObject

+ (NSString *)symbolNameForName:(nullable NSString *)name
                      directory:(BOOL)directory
                      aggregate:(BOOL)aggregate;
+ (UIColor *)tintForName:(nullable NSString *)name
               directory:(BOOL)directory
               aggregate:(BOOL)aggregate;
/// The folder artwork is drawn from vector geometry, so it is returned as an
/// image; files and the folded bucket return nil and use a tinted symbol.
+ (nullable UIImage *)folderImageWithSize:(CGFloat)size;

@end

@interface WQMSpaceLensView : UIView

/// Items already folded by WQMBubbleLayout (the view does not fold again).
@property (nonatomic, copy) NSArray<WQMBubbleLayoutItem *> *items;

/// Called when a bubble is tapped, with the placement that was hit.
@property (nonatomic, copy, nullable) void (^selectionHandler)(WQMBubbleLayoutItem *item);

/// Called by the cancel button of the scanning overlay.
@property (nonatomic, copy, nullable) void (^cancelHandler)(void);

/// Long-press menu for a bubble; return nil to keep the default (no menu).
@property (nonatomic, copy, nullable) UIMenu *(^contextMenuProvider)(WQMBubbleLayoutItem *item);

- (void)setItems:(NSArray<WQMBubbleLayoutItem *> *)items animated:(BOOL)animated;
- (void)setScanning:(BOOL)scanning text:(nullable NSString *)text;
- (void)cancelScanning;

@end

NS_ASSUME_NONNULL_END
