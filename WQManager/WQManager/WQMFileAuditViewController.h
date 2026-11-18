#import <UIKit/UIKit.h>

@class WQMAppModel;

NS_ASSUME_NONNULL_BEGIN

@interface WQMFileAuditViewController : UITableViewController

- (instancetype)initWithApps:(NSArray<WQMAppModel *> *)apps NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithStyle:(UITableViewStyle)style NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil
                        bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
