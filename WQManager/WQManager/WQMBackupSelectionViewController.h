#import <UIKit/UIKit.h>
@class WQMAppModel, WQMBackupScopeDescriptor;
NS_ASSUME_NONNULL_BEGIN
@interface WQMBackupSelectionViewController : UITableViewController
- (instancetype)initWithApp:(WQMAppModel *)app completion:(void (^)(WQMBackupScopeDescriptor *selection))completion;
@end
NS_ASSUME_NONNULL_END
