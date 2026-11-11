#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface WQMMainTabBarController : UITabBarController <UITabBarControllerDelegate>
- (void)openSharedBackupAtURL:(NSURL *)url;
- (void)openImportPicker;
@end

NS_ASSUME_NONNULL_END

