#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// A small capsule below the status bar that reports a long-running operation
/// (backup, restore, import, export, recovery, delete, clean). The overlay
/// window only receives touches on the capsule; everything else goes to the app.
@interface WQMLongOperationBanner : NSObject

+ (instancetype)shared;

/// Shows the banner unless another operation is already running. In that case
/// it presents a short alert and returns NO.
+ (BOOL)startOperationWithTitle:(NSString *)title
                         status:(nullable NSString *)status
                  cancelHandler:(nullable void (^)(void))cancelHandler;

@property (nonatomic, readonly, getter=isBusy) BOOL busy;

- (void)showWithTitle:(NSString *)title status:(nullable NSString *)status;
- (void)showWithTitle:(NSString *)title
               status:(nullable NSString *)status
        cancelHandler:(nullable void (^)(void))cancelHandler;
- (void)updateStatus:(nullable NSString *)status;
- (void)hide;
- (void)hideWithCompletion:(nullable void (^)(void))completion;

@end

NS_ASSUME_NONNULL_END
