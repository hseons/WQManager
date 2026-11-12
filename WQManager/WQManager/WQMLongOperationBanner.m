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
@property (nonatomic, strong, nullable) UIView *headerView;
@property (nonatomic, strong, nullable) UIView *detailView;
@property (nonatomic, strong, nullable) UIActivityIndicatorView *spinner;
@property (nonatomic, strong, nullable) UILabel *titleLabel;
@property (nonatomic, strong, nullable) UILabel *statusLabel;
@property (nonatomic, strong, nullable) UIImageView *chevron;
@property (nonatomic, strong, nullable) UIButton *stopButton;
@property (nonatomic, strong, nullable) UIButton *collapseButton;
@property (nonatomic, strong, nullable) NSLayoutConstraint *heightConstraint;
@property (nonatomic, strong, nullable) NSLayoutConstraint *expandedWidthConstraint;
@property (nonatomic, copy, nullable) NSString *titleText;
@property (nonatomic, copy, nullable) NSString *statusText;
@property (nonatomic, copy, nullable) void (^cancelHandler)(void);
@property (nonatomic, readwrite, getter=isBusy) BOOL busy;
@property (nonatomic) BOOL expanded;
@property (nonatomic) BOOL stopping;

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

    BOOL wasHidden = !self.busy;
    self.busy = YES;
    self.stopping = NO;
    self.stopButton.enabled = YES;
    self.stopButton.hidden = (cancelHandler == nil);
    self.collapseButton.hidden = NO;
    self.window.hidden = NO;
    [self.window.rootViewController.view bringSubviewToFront:self.capsule];
    [self refreshLabels];
    [self.spinner startAnimating];
    [self.window layoutIfNeeded];

    if (wasHidden) {
        [self resetExpandedState];
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
#if DEBUG
    if (getenv("WQM_BANNER_EXPAND_DEMO")) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self setExpanded:YES animated:YES];
        });
    }
#endif
}

- (void)updateStatus:(NSString *)status
{
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self updateStatus:status]; });
        return;
    }
    self.statusText = status ?: @"";
    if (self.busy) [self refreshLabels];
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
    [self animateOutWithCompletion:^{
        self.window.hidden = YES;
        [self.spinner stopAnimating];
        self.cancelHandler = nil;
        [self resetExpandedState];
        if (completion) completion();
    }];
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

    UIView *header = [UIView new];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [capsule addSubview:header];

    UIActivityIndicatorView *spinner =
        [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    spinner.translatesAutoresizingMaskIntoConstraints = NO;
    spinner.color = UIColor.secondaryLabelColor;
    spinner.hidesWhenStopped = NO;
    spinner.userInteractionEnabled = NO;
    [header addSubview:spinner];

    UILabel *titleLabel = [UILabel new];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    titleLabel.adjustsFontForContentSizeCategory = YES;
    titleLabel.textColor = UIColor.labelColor;
    titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    titleLabel.numberOfLines = 1;
    titleLabel.userInteractionEnabled = NO;
    [titleLabel setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
    [titleLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh
                                                forAxis:UILayoutConstraintAxisHorizontal];
    [header addSubview:titleLabel];

    UIImageView *chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.down"]];
    chevron.translatesAutoresizingMaskIntoConstraints = NO;
    chevron.tintColor = UIColor.tertiaryLabelColor;
    chevron.contentMode = UIViewContentModeCenter;
    chevron.userInteractionEnabled = NO;
    [header addSubview:chevron];

    UIView *detail = [UIView new];
    detail.translatesAutoresizingMaskIntoConstraints = NO;
    detail.alpha = 0;
    [capsule addSubview:detail];

    UILabel *statusLabel = [UILabel new];
    statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    statusLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    statusLabel.adjustsFontForContentSizeCategory = YES;
    statusLabel.textColor = UIColor.secondaryLabelColor;
    statusLabel.numberOfLines = 2;
    statusLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [detail addSubview:statusLabel];

    UIButtonConfiguration *stopConfig = [UIButtonConfiguration borderedButtonConfiguration];
    stopConfig.title = WQML(@"STOP", @"停止");
    stopConfig.baseForegroundColor = UIColor.systemRedColor;
    stopConfig.contentInsets = NSDirectionalEdgeInsetsMake(6, 14, 6, 14);
    UIButton *stopButton = [UIButton buttonWithConfiguration:stopConfig primaryAction:nil];
    stopButton.translatesAutoresizingMaskIntoConstraints = NO;
    [stopButton addTarget:self action:@selector(handleStop) forControlEvents:UIControlEventTouchUpInside];
    [detail addSubview:stopButton];

    UIButtonConfiguration *collapseConfig = [UIButtonConfiguration plainButtonConfiguration];
    collapseConfig.title = WQML(@"COLLAPSE", @"收起");
    collapseConfig.baseForegroundColor = UIColor.secondaryLabelColor;
    collapseConfig.contentInsets = NSDirectionalEdgeInsetsMake(6, 10, 6, 4);
    UIButton *collapseButton = [UIButton buttonWithConfiguration:collapseConfig primaryAction:nil];
    collapseButton.translatesAutoresizingMaskIntoConstraints = NO;
    [collapseButton addTarget:self action:@selector(collapseTapped)
             forControlEvents:UIControlEventTouchUpInside];
    [detail addSubview:collapseButton];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                         action:@selector(headerTapped)];
    [header addGestureRecognizer:tap];

    [root.view addSubview:capsule];

    NSLayoutConstraint *height = [capsule.heightAnchor constraintEqualToConstant:44];
    [NSLayoutConstraint activateConstraints:@[
        [capsule.topAnchor constraintEqualToAnchor:root.view.safeAreaLayoutGuide.topAnchor constant:6],
        [capsule.centerXAnchor constraintEqualToAnchor:root.view.centerXAnchor],
        [capsule.leadingAnchor constraintGreaterThanOrEqualToAnchor:root.view.leadingAnchor constant:16],
        [capsule.trailingAnchor constraintLessThanOrEqualToAnchor:root.view.trailingAnchor constant:-16],
        height,

        [blur.leadingAnchor constraintEqualToAnchor:capsule.leadingAnchor],
        [blur.trailingAnchor constraintEqualToAnchor:capsule.trailingAnchor],
        [blur.topAnchor constraintEqualToAnchor:capsule.topAnchor],
        [blur.bottomAnchor constraintEqualToAnchor:capsule.bottomAnchor],

        [header.leadingAnchor constraintEqualToAnchor:capsule.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:capsule.trailingAnchor],
        [header.topAnchor constraintEqualToAnchor:capsule.topAnchor],
        [header.heightAnchor constraintEqualToConstant:44],

        [spinner.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:14],
        [spinner.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],

        [chevron.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-10],
        [chevron.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [chevron.widthAnchor constraintEqualToConstant:28],
        [chevron.heightAnchor constraintEqualToConstant:28],

        [titleLabel.leadingAnchor constraintEqualToAnchor:spinner.trailingAnchor constant:10],
        [titleLabel.trailingAnchor constraintEqualToAnchor:chevron.leadingAnchor constant:-6],
        [titleLabel.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],

        [detail.leadingAnchor constraintEqualToAnchor:capsule.leadingAnchor constant:16],
        [detail.trailingAnchor constraintEqualToAnchor:capsule.trailingAnchor constant:-16],
        [detail.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:6],

        [statusLabel.leadingAnchor constraintEqualToAnchor:detail.leadingAnchor],
        [statusLabel.trailingAnchor constraintEqualToAnchor:detail.trailingAnchor],
        [statusLabel.topAnchor constraintEqualToAnchor:detail.topAnchor],

        [stopButton.leadingAnchor constraintEqualToAnchor:detail.leadingAnchor],
        [stopButton.topAnchor constraintEqualToAnchor:statusLabel.bottomAnchor constant:10],
        [stopButton.heightAnchor constraintEqualToConstant:32],

        [collapseButton.trailingAnchor constraintEqualToAnchor:detail.trailingAnchor],
        [collapseButton.centerYAnchor constraintEqualToAnchor:stopButton.centerYAnchor],
        [collapseButton.heightAnchor constraintEqualToConstant:32],

        [detail.bottomAnchor constraintEqualToAnchor:stopButton.bottomAnchor],
    ]];

    window.hidden = YES;
    self.window = window;
    self.capsule = capsule;
    self.headerView = header;
    self.detailView = detail;
    self.spinner = spinner;
    self.titleLabel = titleLabel;
    self.statusLabel = statusLabel;
    self.chevron = chevron;
    self.stopButton = stopButton;
    self.collapseButton = collapseButton;
    self.heightConstraint = height;
    self.capsule.alpha = 0;
    return YES;
}

- (void)refreshLabels
{
    NSString *title = self.titleText ?: @"";
    NSString *status = self.statusText ?: @"";
    self.titleLabel.text = title;
    self.statusLabel.text = status.length ? status : WQML(@"PREPARING", @"准备中…");
    [self refreshAccessibility];
}

- (void)refreshAccessibility
{
    self.capsule.accessibilityLabel = self.titleText ?: @"";
    self.capsule.accessibilityValue = self.statusText ?: @"";
    self.headerView.accessibilityHint = self.expanded
        ? WQML(@"COLLAPSE", @"收起")
        : WQML(@"LONG_OPERATION_TAP_HINT", @"轻点查看详情");
}

- (void)headerTapped
{
    if (!self.busy) return;
    [self setExpanded:!self.expanded animated:YES];
}

- (void)collapseTapped
{
    [self setExpanded:NO animated:YES];
}

- (void)handleStop
{
    if (self.stopping) return;
    void (^cancel)(void) = self.cancelHandler;
    if (!cancel) return;
    self.stopping = YES;
    self.stopButton.enabled = NO;
    [self updateStatus:WQML(@"STOPPING", @"正在停止…")];
    cancel();
}

- (void)setExpanded:(BOOL)expanded animated:(BOOL)animated
{
    if (self.expanded == expanded) return;
    self.expanded = expanded;

    if (expanded) {
        CGFloat available = self.capsule.superview.bounds.size.width - 32.0;
        CGFloat wanted = MIN(360.0, available);
        NSLayoutConstraint *width = [self.capsule.widthAnchor constraintEqualToConstant:wanted];
        width.priority = UILayoutPriorityRequired - 1;
        width.active = YES;
        self.expandedWidthConstraint = width;
        [self.window layoutIfNeeded];
        CGFloat detailHeight = [self.detailView
            systemLayoutSizeFittingSize:CGSizeMake(wanted - 32.0, UILayoutFittingCompressedSize.height)
            withHorizontalFittingPriority:UILayoutPriorityRequired
                  verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
        self.heightConstraint.constant = MAX(100.0, 44.0 + 6.0 + ceil(detailHeight) + 14.0);
    } else {
        self.heightConstraint.constant = 44;
        self.expandedWidthConstraint.active = NO;
        self.expandedWidthConstraint = nil;
    }

    void (^updates)(void) = ^{
        self.detailView.alpha = expanded ? 1 : 0;
        self.chevron.transform = expanded ? CGAffineTransformMakeRotation(M_PI) : CGAffineTransformIdentity;
        [self.window layoutIfNeeded];
    };

    [self refreshAccessibility];
    if (!animated || UIAccessibilityIsReduceMotionEnabled()) {
        updates();
        return;
    }
    [UIView animateWithDuration:0.38 delay:0
         usingSpringWithDamping:0.82 initialSpringVelocity:0.5
                        options:UIViewAnimationOptionBeginFromCurrentState |
                                UIViewAnimationOptionAllowUserInteraction
                     animations:updates completion:nil];
}

- (void)resetExpandedState
{
    self.expanded = NO;
    self.stopping = NO;
    self.heightConstraint.constant = 44;
    self.expandedWidthConstraint.active = NO;
    self.expandedWidthConstraint = nil;
    self.detailView.alpha = 0;
    self.chevron.transform = CGAffineTransformIdentity;
    self.stopButton.enabled = YES;
    [self.window layoutIfNeeded];
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
