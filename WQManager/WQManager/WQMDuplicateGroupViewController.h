#import <UIKit/UIKit.h>

@class WQMAuditFile;
@class WQMAppModel;

NS_ASSUME_NONNULL_BEGIN

@interface WQMDuplicateGroupViewController : UITableViewController

- (instancetype)initWithFiles:(NSArray<WQMAuditFile *> *)files
                         apps:(NSArray<WQMAppModel *> *)apps
                   completion:(nullable void (^)(void))completion NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithStyle:(UITableViewStyle)style NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil
                        bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
