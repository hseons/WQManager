#import "WQMTheme.h"
#import "WQMLanguageManager.h"

static UIColor *WQMDynamicColor(UIColor *light, UIColor *dark)
{
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? dark : light;
    }];
}

@implementation WQMTheme

+ (UIColor *)canvasColor
{
    return WQMDynamicColor([UIColor colorWithWhite:0.95 alpha:1.0],
                           [UIColor colorWithWhite:0.035 alpha:1.0]);
}

+ (UIColor *)surfaceColor
{
    return WQMDynamicColor(UIColor.whiteColor,
                           [UIColor colorWithWhite:0.095 alpha:1.0]);
}

+ (UIColor *)raisedSurfaceColor
{
    return WQMDynamicColor([UIColor colorWithWhite:0.995 alpha:1.0],
                           [UIColor colorWithWhite:0.125 alpha:1.0]);
}

+ (UIColor *)textPrimaryColor
{
    return WQMDynamicColor([UIColor colorWithWhite:0.055 alpha:1.0],
                           [UIColor colorWithWhite:0.97 alpha:1.0]);
}

+ (UIColor *)textSecondaryColor
{
    return WQMDynamicColor([UIColor colorWithWhite:0.46 alpha:1.0],
                           [UIColor colorWithWhite:0.64 alpha:1.0]);
}

+ (UIColor *)separatorColor
{
    return WQMDynamicColor([UIColor colorWithWhite:0.88 alpha:1.0],
                           [UIColor colorWithWhite:0.22 alpha:1.0]);
}

+ (UIColor *)inverseSurfaceColor
{
    return WQMDynamicColor([UIColor colorWithWhite:0.08 alpha:1.0],
                           [UIColor colorWithWhite:0.94 alpha:1.0]);
}

+ (UIColor *)inverseTextColor
{
    return WQMDynamicColor([UIColor colorWithWhite:0.98 alpha:1.0],
                           [UIColor colorWithWhite:0.06 alpha:1.0]);
}

+ (UIColor *)dangerColor
{
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithRed:1.0 green:0.36 blue:0.34 alpha:1.0]
            : [UIColor colorWithRed:0.77 green:0.12 blue:0.12 alpha:1.0];
    }];
}

+ (UIColor *)accentColor { return self.textPrimaryColor; }

+ (UIColor *)highlightColor
{
    return WQMDynamicColor([UIColor colorWithRed:0.10 green:0.34 blue:0.24 alpha:1.0],
                           [UIColor colorWithRed:0.36 green:0.78 blue:0.58 alpha:1.0]);
}
+ (UIColor *)warningColor { return self.textSecondaryColor; }
+ (CGFloat)smallRadius { return 14.0; }
+ (CGFloat)mediumRadius { return 20.0; }
+ (CGFloat)largeRadius { return 28.0; }

+ (UIFont *)displayNumberFont
{
    UIFont *base = [UIFont monospacedDigitSystemFontOfSize:42 weight:UIFontWeightBold];
    return [[UIFontMetrics metricsForTextStyle:UIFontTextStyleLargeTitle] scaledFontForFont:base];
}

+ (UIFont *)titleFont
{
    UIFontDescriptor *descriptor = [UIFontDescriptor preferredFontDescriptorWithTextStyle:UIFontTextStyleTitle2];
    descriptor = [descriptor fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitBold];
    return [UIFont fontWithDescriptor:descriptor size:0];
}

+ (UIFont *)sectionTitleFont
{
    UIFont *base = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    return [[UIFontMetrics metricsForTextStyle:UIFontTextStyleSubheadline] scaledFontForFont:base];
}

+ (BOOL)shouldReduceMotion { return UIAccessibilityIsReduceMotionEnabled(); }

+ (void)configureNavigationBar:(UINavigationBar *)navigationBar
{
    if (!navigationBar) return;
    UINavigationBarAppearance *appearance = [UINavigationBarAppearance new];
    [appearance configureWithDefaultBackground];
    appearance.backgroundColor = [self.canvasColor colorWithAlphaComponent:0.18];
    appearance.shadowColor = UIColor.clearColor;
    appearance.titleTextAttributes = @{NSForegroundColorAttributeName: self.textPrimaryColor};
    appearance.largeTitleTextAttributes = @{
        NSForegroundColorAttributeName: self.textPrimaryColor,
        NSFontAttributeName: [[UIFontMetrics metricsForTextStyle:UIFontTextStyleLargeTitle]
                              scaledFontForFont:[UIFont systemFontOfSize:34 weight:UIFontWeightBold]],
    };
    navigationBar.standardAppearance = appearance;
    navigationBar.compactAppearance = appearance;
    navigationBar.scrollEdgeAppearance = appearance;
    navigationBar.tintColor = self.textPrimaryColor;
    navigationBar.translucent = YES;
}

+ (void)animateLabelChange:(UILabel *)label update:(void (^)(void))update
{
    if (!label || !update) return;
    if (self.shouldReduceMotion) {
        update();
        return;
    }
    [UIView transitionWithView:label
                      duration:0.22
                       options:UIViewAnimationOptionTransitionCrossDissolve |
                               UIViewAnimationOptionAllowUserInteraction
                    animations:update
                    completion:nil];
}

+ (void)animateEntrance:(UIView *)view delay:(NSTimeInterval)delay
{
    if (!view || self.shouldReduceMotion) return;
    view.alpha = 0;
    view.transform = CGAffineTransformMakeTranslation(0, 10);
    [UIView animateWithDuration:0.38
                          delay:delay
         usingSpringWithDamping:0.9
          initialSpringVelocity:0.25
                        options:UIViewAnimationOptionCurveEaseOut |
                                UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        view.alpha = 1;
        view.transform = CGAffineTransformIdentity;
    } completion:nil];
}

+ (void)animatePress:(UIView *)view pressed:(BOOL)pressed
{
    if (!view) return;
    if (self.shouldReduceMotion) {
        view.transform = CGAffineTransformIdentity;
        view.alpha = pressed ? 0.92 : 1.0;
        return;
    }
    [UIView animateWithDuration:pressed ? 0.11 : 0.18
                          delay:0
                        options:UIViewAnimationOptionAllowUserInteraction |
                                UIViewAnimationOptionBeginFromCurrentState |
                                UIViewAnimationOptionCurveEaseOut
                     animations:^{
        view.transform = pressed
            ? CGAffineTransformConcat(CGAffineTransformMakeScale(0.985, 0.985),
                                      CGAffineTransformMakeTranslation(0, 1))
            : CGAffineTransformIdentity;
        view.alpha = pressed ? 0.94 : 1.0;
    } completion:nil];
}

+ (UIViewController *)placeholderViewControllerWithTitle:(NSString *)title
                                                   symbol:(NSString *)symbol
                                                 message:(NSString *)message
{
    UIViewController *controller = [UIViewController new];
    controller.title = title;
    controller.view.backgroundColor = self.canvasColor;

    WQMSoftSurfaceView *card = [[WQMSoftSurfaceView alloc] initWithElevated:YES];
    card.translatesAutoresizingMaskIntoConstraints = NO;

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol]];
    icon.tintColor = self.textPrimaryColor;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:32
                                                                                        weight:UIImageSymbolWeightMedium];

    UILabel *heading = [UILabel new];
    heading.text = title;
    heading.font = self.titleFont;
    heading.textColor = self.textPrimaryColor;
    heading.textAlignment = NSTextAlignmentCenter;

    UILabel *body = [UILabel new];
    body.text = message;
    body.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    body.textColor = self.textSecondaryColor;
    body.textAlignment = NSTextAlignmentCenter;
    body.numberOfLines = 0;

    UILabel *status = [UILabel new];
    status.text = WQML(@"COMING_SOON", @"等待接入");
    status.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    status.textColor = self.textSecondaryColor;
    status.layer.cornerRadius = WQMTheme.smallRadius;
    status.layer.borderWidth = 1;
    status.layer.borderColor = self.separatorColor.CGColor;
    status.clipsToBounds = YES;
    status.textAlignment = NSTextAlignmentCenter;
    [status.widthAnchor constraintEqualToConstant:76].active = YES;
    [status.heightAnchor constraintEqualToConstant:26].active = YES;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[icon, status, heading, body]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [stack setCustomSpacing:18 afterView:status];
    [card addSubview:stack];
    [controller.view addSubview:card];

    UILayoutGuide *margins = controller.view.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [icon.widthAnchor constraintEqualToConstant:52],
        [icon.heightAnchor constraintEqualToConstant:52],
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:28],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:24],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-24],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-28],
        [card.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor constant:20],
        [card.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor constant:-20],
        [card.centerYAnchor constraintEqualToAnchor:controller.view.centerYAnchor],
    ]];
    [self animateEntrance:card delay:0.04];
    return controller;
}

@end

@implementation WQMSoftSurfaceView

- (instancetype)initWithElevated:(BOOL)elevated
{
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _elevated = elevated;
        self.backgroundColor = elevated ? WQMTheme.raisedSurfaceColor : WQMTheme.surfaceColor;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.cornerRadius = WQMTheme.mediumRadius;
        self.layer.borderWidth = 1;
        [self updateAppearance];
        [self registerForTraitChanges:@[UITraitUserInterfaceStyle.class]
                           withTarget:self
                               action:@selector(updateAppearance)];
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(updateAppearance)
                                                   name:UIAccessibilityDarkerSystemColorsStatusDidChangeNotification
                                                 object:nil];
    }
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    if (self.elevated) {
        self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds
                                                          cornerRadius:self.layer.cornerRadius].CGPath;
    }
}

- (void)setElevated:(BOOL)elevated
{
    _elevated = elevated;
    self.backgroundColor = elevated ? WQMTheme.raisedSurfaceColor : WQMTheme.surfaceColor;
    [self updateAppearance];
    [self setNeedsLayout];
}

- (void)updateAppearance
{
    BOOL increaseContrast = UIAccessibilityDarkerSystemColorsEnabled();
    self.layer.borderColor = (increaseContrast ? WQMTheme.textPrimaryColor : WQMTheme.separatorColor).CGColor;
    self.layer.borderWidth = increaseContrast ? 1.5 : 1.0;
    self.layer.shadowColor = UIColor.blackColor.CGColor;
    self.layer.shadowOffset = CGSizeMake(0, self.elevated ? 8 : 2);
    self.layer.shadowRadius = self.elevated ? 18 : 5;
    self.layer.shadowOpacity = self.elevated
        ? (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? 0.42 : 0.10)
        : 0.04;
    self.layer.masksToBounds = NO;
}

@end

