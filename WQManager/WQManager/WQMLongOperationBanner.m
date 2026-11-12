#import "WQMLongOperationBanner.h"
#import "WQMAlertPresenter.h"
#import "WQMLanguageManager.h"

@interface WQMBannerWindow : UIWindow
@end

@implementation WQMBannerWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    UIView *view = [super hitTest:point withEvent:event];
    if (view == self || view == self.rootViewController.view) return nil;
    return view;
}

@end

@interface WQMLongOperationBanner ()

@property (nonatomic, strong, nullable) WQMBannerWindow *window;
@property (nonatomic, strong, nullable) UIView *capsule;
@property (nonatomic, strong, nullable) UIActivityIndicatorView *spinner;
@property (nonatomic, strong, nullable) UILabel *label;
@property (nonatomic, copy, nullable) NSString *titleText;
@property (nonatomic, copy, nullable) NSString *statusText;
@property (nonatomic, copy, nullable) void (^cancelHandler)(void);
@property (nonatomic, weak, nullable) UIAlertController *detailAlert;
@property (nonatomic, readwrite, getter=isBusy) BOOL busy;

@end

@implementation WQMLongOperationBanner

+ (BOOL)startOperationWithTitle:(NSString *)title
                         status:(NSString *)status
                  cancelHandler:(void (^)(void))cancelHandler
{
    if (WQMLongOperationBanner.shared.isBusy) {
        [WQMAlertPresenter presentAlertWithTitle:WQML(@"OPERATION_BUSY_TITLE", @"有操作正在进行")
                                         message:WQML(@"OPERATION_BUSY_MESSAGE", @"请等待当前操作完成后再试。")];
        return NO;
    }
    [WQMLongOperationBanner.shared showWithTitle:title status:status cancelHandler:cancelHandler];
    return YES;
}

+ (instancetype)shared
{
    static WQMLongOperationBanner *banner;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ banner = [WQMLongOperationBanner new]; });
    return banner;
}

- (void)showWithTitle:(NSString *)title status:(NSString *)status
{
    [self showWithTitle:title status:status cancelHandler:nil];
}

- (void)showWithTitle:(NSString *)title
               status:(NSString *)status
        cancelHandler:(void (^)(void))cancelHandler
{
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showWithTitle:title status:status cancelHandler:cancelHandler];
        });
        return;
    }
    self.titleText = title ?: @"";
    self.statusText = status ?: @"";
    self.cancelHandler = cancelHandler;
    if (![self ensureWindow]) return;

    BOOL wasHidden = self.capsule.alpha < 0.5;
    self.busy = YES;
    self.window.hidden = NO;
    [self.window.rootViewController.view bringSubviewToFront:self.capsule];
    [self refreshLabel];
    [self.spinner startAnimating];
    [self.window layoutIfNeeded];

    if (wasHidden) {
        self.capsule.transform = CGAffineTransformMakeTranslation(0, -70);
        self.capsule.alpha = 0;
        if (UIAccessibilityIsReduceMotionEnabled()) {
            [UIView animateWithDuration:0.2 animations:^{ self.capsule.alpha = 1; }];
        } else {
            [UIView animateWithDuration:0.34 delay:0
                 usingSpringWithDamping:0.86 initialSpringVelocity:0.4
                                options:UIViewAnimationOptionBeginFromCurrentState
                             animations:^{
                self.capsule.transform = CGAffineTransformIdentity;
                self.capsule.alpha = 1;
            } completion:nil];
        }
    }
}

- (void)updateStatus:(NSString *)status
{
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self updateStatus:status]; });
        return;
    }
    self.statusText = status ?: @"";
    if (self.busy) [self refreshLabel];
}

- (void)hide
{
    [self hideWithCompletion:nil];
}

- (void)hideWithCompletion:(void (^)(void))completion
{
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self hideWithCompletion:completion]; });
        return;
    }
    if (!self.busy) {
        if (completion) completion();
        return;
    }
    self.busy = NO;
    void (^finish)(void) = ^{
        [self animateOutWithCompletion:^{
            self.window.hidden = YES;
            [self.spinner stopAnimating];
            self.cancelHandler = nil;
            self.detailAlert = nil;
            if (completion) completion();
        }];
    };
    UIAlertController *detail = self.detailAlert;
    if (detail && detail.presentingViewController) {
        [detail dismissViewControllerAnimated:NO completion:finish];
    } else {
        finish();
    }
}

- (BOOL)ensureWindow
{
    if (self.window && self.window.windowScene) return YES;
    UIWindowScene *scene = nil;
    for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
        if (![candidate isKindOfClass:UIWindowScene.class]) continue;
        if (candidate.activationState == UISceneActivationStateForegroundActive ||
            candidate.activationState == UISceneActivationStateForegroundInactive) {
            scene = (UIWindowScene *)candidate;
            break;
        }
    }
    if (!scene) return NO;

    WQMBannerWindow *window = [[WQMBannerWindow alloc] initWithWindowScene:scene];
    window.windowLevel = UIWindowLevelStatusBar + 1;
    window.backgroundColor = UIColor.clearColor;
    UIViewController *root = [UIViewController new];
    root.view.backgroundColor = UIColor.clearColor;
    window.rootViewController = root;

    UIView *capsule = [UIView new];
    capsule.translatesAutoresizingMaskIntoConstraints = NO;
    capsule.layer.cornerRadius = 22;
    capsule.layer.cornerCurve = kCACornerCurveContinuous;
    capsule.clipsToBounds = YES;
    capsule.isAccessibilityElement = YES;
    capsule.accessibilityTraits = UIAccessibilityTraitButton;

    UIVisualEffectView *blur = [[UIVisualEffectView alloc]
        initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial]];
    blur.translatesAutoresizingMaskIntoConstraints = NO;
    blur.userInteractionEnabled = NO;
    [capsule addSubview:blur];

    UIActivityIndicatorView *spinner =
        [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    spinner.translatesAutoresizingMaskIntoConstraints = NO;
    spinner.color = UIColor.secondaryLabelColor;
    spinner.hidesWhenStopped = NO;
    spinner.userInteractionEnabled = NO;
    [capsule addSubview:spinner];

    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = UIColor.labelColor;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.numberOfLines = 1;
    label.userInteractionEnabled = NO;
    [label setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
    [label setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh
                                           forAxis:UILayoutConstraintAxisHorizontal];
    [capsule addSubview:label];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                         action:@selector(handleTap)];
    [capsule addGestureRecognizer:tap];

    [root.view addSubview:capsule];

    [NSLayoutConstraint activateConstraints:@[
        [capsule.topAnchor constraintEqualToAnchor:root.view.safeAreaLayoutGuide.topAnchor constant:6],
        [capsule.centerXAnchor constraintEqualToAnchor:root.view.centerXAnchor],
        [capsule.leadingAnchor constraintGreaterThanOrEqualToAnchor:root.view.leadingAnchor constant:16],
        [capsule.trailingAnchor constraintLessThanOrEqualToAnchor:root.view.trailingAnchor constant:-16],
        [capsule.widthAnchor constraintLessThanOrEqualToAnchor:root.view.widthAnchor constant:-32],
        [capsule.heightAnchor constraintEqualToConstant:44],

        [blur.leadingAnchor constraintEqualToAnchor:capsule.leadingAnchor],
        [blur.trailingAnchor constraintEqualToAnchor:capsule.trailingAnchor],
        [blur.topAnchor constraintEqualToAnchor:capsule.topAnchor],
        [blur.bottomAnchor constraintEqualToAnchor:capsule.bottomAnchor],

        [spinner.leadingAnchor constraintEqualToAnchor:capsule.leadingAnchor constant:14],
        [spinner.centerYAnchor constraintEqualToAnchor:capsule.centerYAnchor],
        [label.leadingAnchor constraintEqualToAnchor:spinner.trailingAnchor constant:10],
        [label.trailingAnchor constraintEqualToAnchor:capsule.trailingAnchor constant:-16],
        [label.centerYAnchor constraintEqualToAnchor:capsule.centerYAnchor],
    ]];

    window.hidden = YES;
    self.window = window;
    self.capsule = capsule;
    self.spinner = spinner;
    self.label = label;
    self.capsule.alpha = 0;
    return YES;
}

- (void)refreshLabel
{
    NSString *title = self.titleText ?: @"";
    NSString *status = self.statusText ?: @"";
    self.label.text = status.length ? [NSString stringWithFormat:@"%@ · %@", title, status] : title;
    self.capsule.accessibilityLabel = title;
    self.capsule.accessibilityValue = status;
    self.capsule.accessibilityHint = WQML(@"LONG_OPERATION_TAP_HINT", @"轻点查看详情");
}

- (void)handleTap
{
    if (!self.busy || self.titleText.length == 0) return;
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:self.titleText
                         message:self.statusText
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:WQML(@"CLOSE", @"关闭")
                                              style:UIAlertActionStyleCancel handler:nil]];
    if (self.cancelHandler) {
        __weak typeof(self) weakSelf = self;
        [alert addAction:[UIAlertAction actionWithTitle:WQML(@"STOP", @"停止")
                                                  style:UIAlertActionStyleDestructive
                                                handler:^(__unused UIAlertAction *action) {
            void (^cancel)(void) = weakSelf.cancelHandler;
            if (cancel) cancel();
        }]];
    }
    self.detailAlert = alert;
    [WQMAlertPresenter presentViewController:alert animated:YES completion:nil];
}

- (void)animateOutWithCompletion:(void (^)(void))completion
{
    if (UIAccessibilityIsReduceMotionEnabled()) {
        self.capsule.alpha = 0;
        self.capsule.transform = CGAffineTransformIdentity;
        if (completion) completion();
        return;
    }
    [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        self.capsule.alpha = 0;
        self.capsule.transform = CGAffineTransformMakeTranslation(0, -60);
    } completion:^(__unused BOOL finished) {
        self.capsule.transform = CGAffineTransformIdentity;
        if (completion) completion();
    }];
}

@end
