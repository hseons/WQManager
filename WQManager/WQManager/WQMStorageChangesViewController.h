#import <UIKit/UIKit.h>
@class WQMAppModel;
NS_ASSUME_NONNULL_BEGIN
@interface WQMStorageChangesViewController : UITableViewController
- (instancetype)initWithApps:(NSArray<WQMAppModel *> *)apps;
- (instancetype)initWithApp:(WQMAppModel *)app;
@end
NS_ASSUME_NONNULL_END
