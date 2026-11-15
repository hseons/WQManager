#import <UIKit/UIKit.h>
@class WQMAppModel, WQMBackupRecord;
NS_ASSUME_NONNULL_BEGIN
@interface WQMFilesViewController : UITableViewController
- (instancetype)initWithApp:(WQMAppModel *)app;
- (instancetype)initWithBackup:(WQMBackupRecord *)backup;
- (instancetype)initComparingOlder:(WQMBackupRecord *)older newer:(WQMBackupRecord *)newer;
@end
NS_ASSUME_NONNULL_END
