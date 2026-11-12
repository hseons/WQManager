#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Presents alerts from the controller the user is actually looking at.
/// While a long operation runs, the user can switch tabs or open other screens,
/// so presenting from the original controller can silently fail.
@interface WQMAlertPresenter : NSObject

+ (nullable UIViewController *)topViewController;
+ (void)presentViewController:(UIViewController *)viewController
                     animated:(BOOL)animated
                   completion:(nullable void (^)(void))completion;
+ (void)presentAlertWithTitle:(nullable NSString *)title
                      message:(nullable NSString *)message;

@end

NS_ASSUME_NONNULL_END
