#import <UIKit/UIKit.h>
@class WQMAppModel;
NS_ASSUME_NONNULL_BEGIN
@interface WQMBackupQueueViewController : UITableViewController
- (instancetype)initWithApps:(NSArray<WQMAppModel *> *)apps;
- (void)updateApps:(NSArray<WQMAppModel *> *)apps;
@end
NS_ASSUME_NONNULL_END
