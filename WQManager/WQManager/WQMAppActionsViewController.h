#import <UIKit/UIKit.h>

@class WQMAppModel;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, WQMAppAction) {
    WQMAppActionQuickBackup = 0,
    WQMAppActionFullBackup,
    WQMAppActionRestore,
    WQMAppActionInspectSpace,
    WQMAppActionCopyBundleID,
};

@interface WQMAppActionsViewController : UIViewController

@property (nonatomic, copy, nullable) void (^actionHandler)(WQMAppAction action);

- (instancetype)initWithApp:(WQMAppModel *)app NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil
                        bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

