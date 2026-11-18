#import <UIKit/UIKit.h>

@class WQMAppModel;

NS_ASSUME_NONNULL_BEGIN

/// Searches user files across every accessible app container. The scan starts
/// when the screen opens and reports matches while it is still running; typing
/// only filters the files collected so far.
@interface WQMGlobalFileSearchViewController : UITableViewController

- (instancetype)initWithApps:(NSArray<WQMAppModel *> *)apps NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithStyle:(UITableViewStyle)style NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil
                        bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
