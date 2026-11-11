#import "WQMCleanerViewController.h"
#import "WQMCacheService.h"
#import "WQMAppIconService.h"
#import "WQMLanguageManager.h"
#import "WQMPreferences.h"
#import "WQMSafetyPolicy.h"
#import "WQMTheme.h"
#import "WQAccess.h"

#import <math.h>

typedef NS_ENUM(NSInteger, WQMCleanerQuickAction) {
    WQMCleanerQuickActionSelectAll,
    WQMCleanerQuickActionLargeCaches,
    WQMCleanerQuickActionClearSelection,
};

@interface WQMCleanerProgressView : UIView
@property (nonatomic, strong) UILabel *centerLabel;
@property (nonatomic) CGFloat progress;
- (void)setProgress:(CGFloat)progress animated:(BOOL)animated;
@end

@implementation WQMCleanerProgressView {
    CAShapeLayer *_trackLayer;
    CAShapeLayer *_progressLayer;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        _trackLayer = [CAShapeLayer layer];
        _trackLayer.fillColor = UIColor.clearColor.CGColor;
        _trackLayer.strokeColor = WQMTheme.separatorColor.CGColor;
        _trackLayer.lineWidth = 10;
        _trackLayer.lineCap = kCALineCapRound;
        [self.layer addSublayer:_trackLayer];

        _progressLayer = [CAShapeLayer layer];
        _progressLayer.fillColor = UIColor.clearColor.CGColor;
        _progressLayer.strokeColor = WQMTheme.textPrimaryColor.CGColor;
        _progressLayer.lineWidth = 10;
        _progressLayer.lineCap = kCALineCapRound;
        _progressLayer.strokeEnd = 0;
        [self.layer addSublayer:_progressLayer];

        _centerLabel = [UILabel new];
        _centerLabel.textAlignment = NSTextAlignmentCenter;
        _centerLabel.adjustsFontSizeToFitWidth = YES;
        _centerLabel.minimumScaleFactor = 0.62;
        _centerLabel.font = [UIFont monospacedDigitSystemFontOfSize:18 weight:UIFontWeightBold];
        _centerLabel.textColor = WQMTheme.textPrimaryColor;
        _centerLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_centerLabel];
        [NSLayoutConstraint activateConstraints:@[
            [_centerLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_centerLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_centerLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
            [_centerLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        ]];
        [self updateRingColors];
        [self registerForTraitChanges:@[UITraitUserInterfaceStyle.class]
                           withTarget:self
                               action:@selector(updateRingColors)];
    }
    return self;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGFloat radius = (MIN(self.bounds.size.width, self.bounds.size.height) - 10) / 2.0;
    CGPoint center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    UIBezierPath *path = [UIBezierPath bezierPathWithArcCenter:center
                                                        radius:radius
                                                    startAngle:-M_PI_2
                                                      endAngle:M_PI * 1.5
                                                     clockwise:YES];
    _trackLayer.frame = self.bounds;
    _progressLayer.frame = self.bounds;
    _trackLayer.path = path.CGPath;
    _progressLayer.path = path.CGPath;
}

- (void)updateRingColors
{
    UITraitCollection *traits = self.traitCollection;
    _trackLayer.strokeColor =
        [WQMTheme.separatorColor resolvedColorWithTraitCollection:traits].CGColor;
    _progressLayer.strokeColor =
        [WQMTheme.textPrimaryColor resolvedColorWithTraitCollection:traits].CGColor;
    _centerLabel.textColor = WQMTheme.textPrimaryColor;
}

- (void)setProgress:(CGFloat)progress animated:(BOOL)animated
{
    CGFloat clamped = MIN(MAX(progress, 0), 1);
    if (fabs(clamped - _progress) < 0.0005) return;
    CGFloat from = _progressLayer.strokeEnd;
    CAShapeLayer *presentation = (CAShapeLayer *)_progressLayer.presentationLayer;
    if (presentation && [_progressLayer animationForKey:@"progress"]) {
        from = presentation.strokeEnd;
    }
    _progress = clamped;
    [_progressLayer removeAnimationForKey:@"progress"];
    if (animated && !WQMTheme.shouldReduceMotion) {
        CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
        animation.fromValue = @(from);
        animation.toValue = @(clamped);
        animation.duration = 0.3;
        animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        [_progressLayer addAnimation:animation forKey:@"progress"];
    }
    _progressLayer.strokeEnd = clamped;
}

@end

@interface WQMCleanerSummaryView : UIView
@property (nonatomic, strong) UILabel *totalLabel;
@property (nonatomic, strong) UILabel *selectedLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *cleanButton;
@property (nonatomic, copy) void (^quickActionHandler)(WQMCleanerQuickAction action);
@property (nonatomic, copy) void (^cleanHandler)(void);
- (void)updateItems:(NSArray<WQMCleanItem *> *)items
              status:(NSString *)status
         interactive:(BOOL)interactive;
- (void)updateCleanActionWithSelectedBytes:(unsigned long long)selectedBytes
                                     enabled:(BOOL)enabled;
@end

@implementation WQMCleanerSummaryView {
    WQMSoftSurfaceView *_card;
    WQMCleanerProgressView *_progressView;
    UIButton *_selectAllButton;
    UIButton *_largeCachesButton;
    UIButton *_clearSelectionButton;
    BOOL _playedEntrance;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        _card = [[WQMSoftSurfaceView alloc] initWithElevated:YES];
        _card.translatesAutoresizingMaskIntoConstraints = NO;
        UILabel *caption = [UILabel new];
        caption.text = WQML(@"RECLAIMABLE", @"可清理空间");
        caption.font = [WQMTheme sectionTitleFont];
        caption.textColor = WQMTheme.textSecondaryColor;

        _progressView = [[WQMCleanerProgressView alloc] initWithFrame:CGRectMake(0, 0, 116, 116)];
        _progressView.translatesAutoresizingMaskIntoConstraints = NO;
        _totalLabel = _progressView.centerLabel;
        _totalLabel.text = @"0 KB";
        _selectedLabel = [UILabel new];
        _selectedLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
        _selectedLabel.textColor = WQMTheme.textPrimaryColor;
        _statusLabel = [UILabel new];
        _statusLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
        _statusLabel.textColor = WQMTheme.textSecondaryColor;
        _statusLabel.numberOfLines = 2;

        _selectAllButton = [self quickButtonWithTitle:WQML(@"SELECT_ALL", @"全选")
                                               symbol:@"checkmark.circle.fill"
                                               action:WQMCleanerQuickActionSelectAll];
        _largeCachesButton = [self quickButtonWithTitle:WQML(@"LARGE_CACHES_SHORT", @"50 MB+")
                                                 symbol:@"arrow.up.circle"
                                                 action:WQMCleanerQuickActionLargeCaches];
        _clearSelectionButton = [self quickButtonWithTitle:WQML(@"CLEAR_SELECTION", @"取消全选")
                                                    symbol:@"circle"
                                                    action:WQMCleanerQuickActionClearSelection];
        UIStackView *quickActions = [[UIStackView alloc] initWithArrangedSubviews:@[
            _selectAllButton, _largeCachesButton, _clearSelectionButton
        ]];
        quickActions.axis = UILayoutConstraintAxisHorizontal;
        quickActions.distribution = UIStackViewDistributionFillEqually;
        quickActions.alignment = UIStackViewAlignmentCenter;
        quickActions.spacing = 8;

        UIStackView *details = [[UIStackView alloc] initWithArrangedSubviews:
                                @[caption, _selectedLabel, _statusLabel]];
        details.axis = UILayoutConstraintAxisVertical;
        details.spacing = 7;

        UIStackView *top = [[UIStackView alloc] initWithArrangedSubviews:@[_progressView, details]];
        top.axis = UILayoutConstraintAxisHorizontal;
        top.alignment = UIStackViewAlignmentCenter;
        top.spacing = 18;

        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[top, quickActions]];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 14;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [_card addSubview:stack];
        UIButtonConfiguration *cleanConfiguration = [UIButtonConfiguration filledButtonConfiguration];
        cleanConfiguration.title = WQML(@"CLEAN_SELECTED_ACTION_EMPTY", @"清理所选缓存");
        cleanConfiguration.cornerStyle = UIButtonConfigurationCornerStyleLarge;
        cleanConfiguration.baseBackgroundColor = WQMTheme.inverseSurfaceColor;
        cleanConfiguration.baseForegroundColor = WQMTheme.inverseTextColor;
        cleanConfiguration.contentInsets = NSDirectionalEdgeInsetsMake(15, 20, 15, 20);
        cleanConfiguration.titleTextAttributesTransformer =
            ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *attributes) {
            NSMutableDictionary *updated = [attributes mutableCopy];
            updated[NSFontAttributeName] = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
            return updated;
        };
        _cleanButton = [UIButton buttonWithConfiguration:cleanConfiguration primaryAction:nil];
        _cleanButton.translatesAutoresizingMaskIntoConstraints = NO;
        _cleanButton.configurationUpdateHandler = ^(UIButton *button) {
            UIButtonConfiguration *configuration = button.configuration;
            configuration.baseBackgroundColor = !button.enabled
                ? WQMTheme.separatorColor
                : (button.highlighted
                    ? [WQMTheme.inverseSurfaceColor colorWithAlphaComponent:0.82]
                    : WQMTheme.inverseSurfaceColor);
            configuration.baseForegroundColor = button.enabled
                ? WQMTheme.inverseTextColor : WQMTheme.textSecondaryColor;
            button.configuration = configuration;
        };
        [_cleanButton addTarget:self
                         action:@selector(cleanButtonTapped)
               forControlEvents:UIControlEventTouchUpInside];
        [_cleanButton addTarget:self
                         action:@selector(controlTouchDown:)
               forControlEvents:UIControlEventTouchDown];
        [_cleanButton addTarget:self
                         action:@selector(controlTouchEnded:)
               forControlEvents:UIControlEventTouchUpInside |
                                UIControlEventTouchUpOutside |
                                UIControlEventTouchCancel];
        UIStackView *outer = [[UIStackView alloc] initWithArrangedSubviews:@[_card, _cleanButton]];
        outer.axis = UILayoutConstraintAxisVertical;
        outer.spacing = 10;
        outer.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:outer];
        [NSLayoutConstraint activateConstraints:@[
            [stack.topAnchor constraintEqualToAnchor:_card.topAnchor constant:18],
            [stack.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:20],
            [stack.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-20],
            [stack.bottomAnchor constraintEqualToAnchor:_card.bottomAnchor constant:-16],
            [_statusLabel.heightAnchor constraintGreaterThanOrEqualToConstant:34],
            [outer.topAnchor constraintEqualToAnchor:self.topAnchor constant:8],
            [outer.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:12],
            [outer.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-12],
            [outer.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [outer.widthAnchor constraintLessThanOrEqualToConstant:776],
            [outer.widthAnchor constraintEqualToAnchor:self.widthAnchor constant:-24],
            [outer.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-8],
            [_cleanButton.heightAnchor constraintGreaterThanOrEqualToConstant:54],
            [_progressView.widthAnchor constraintEqualToConstant:116],
            [_progressView.heightAnchor constraintEqualToConstant:116],
        ]];
    }
    return self;
}

- (UIButton *)quickButtonWithTitle:(NSString *)title
                            symbol:(NSString *)symbol
                            action:(WQMCleanerQuickAction)action
{
    UIButtonConfiguration *configuration = [UIButtonConfiguration plainButtonConfiguration];
    configuration.title = title;
    configuration.image = [UIImage systemImageNamed:symbol];
    configuration.imagePlacement = NSDirectionalRectEdgeLeading;
    configuration.imagePadding = 5;
    configuration.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    configuration.titleLineBreakMode = NSLineBreakByTruncatingTail;
    configuration.titleAlignment = UIButtonConfigurationTitleAlignmentCenter;
    configuration.contentInsets = NSDirectionalEdgeInsetsMake(9, 8, 9, 8);
    configuration.baseForegroundColor = WQMTheme.textSecondaryColor;
    configuration.background.cornerRadius = 22;
    configuration.background.strokeWidth = 1;
    configuration.titleTextAttributesTransformer =
        ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *attributes) {
        NSMutableDictionary *updated = [attributes mutableCopy];
        updated[NSFontAttributeName] = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
        return updated;
    };
    UIButton *button = [UIButton buttonWithConfiguration:configuration primaryAction:nil];
    button.tag = action;
    button.configurationUpdateHandler = ^(UIButton *updatedButton) {
        UIButtonConfiguration *updated = updatedButton.configuration;
        BOOL selected = updatedButton.selected;
        BOOL highlighted = updatedButton.highlighted;
        if (!updatedButton.enabled) {
            updated.background.backgroundColor = [WQMTheme.canvasColor colorWithAlphaComponent:0.55];
            updated.baseForegroundColor = [WQMTheme.textSecondaryColor colorWithAlphaComponent:0.48];
            updated.background.strokeColor = UIColor.clearColor;
        } else if (selected) {
            updated.background.backgroundColor = highlighted
                ? [WQMTheme.inverseSurfaceColor colorWithAlphaComponent:0.78]
                : WQMTheme.inverseSurfaceColor;
            updated.baseForegroundColor = WQMTheme.inverseTextColor;
            updated.background.strokeColor = WQMTheme.inverseSurfaceColor;
        } else {
            updated.background.backgroundColor = highlighted
                ? WQMTheme.separatorColor : WQMTheme.canvasColor;
            updated.baseForegroundColor = highlighted
                ? WQMTheme.textPrimaryColor : WQMTheme.textSecondaryColor;
            updated.background.strokeColor = highlighted
                ? WQMTheme.textSecondaryColor : WQMTheme.separatorColor;
        }
        updatedButton.configuration = updated;
    };
    [button addTarget:self action:@selector(quickActionTapped:) forControlEvents:UIControlEventTouchUpInside];
    [button addTarget:self action:@selector(controlTouchDown:) forControlEvents:UIControlEventTouchDown];
    [button addTarget:self action:@selector(controlTouchEnded:)
     forControlEvents:UIControlEventTouchUpInside |
                      UIControlEventTouchUpOutside |
                      UIControlEventTouchCancel];
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    return button;
}

- (void)quickActionTapped:(UIButton *)sender
{
    [self controlTouchEnded:sender];
    UISelectionFeedbackGenerator *feedback = [UISelectionFeedbackGenerator new];
    [feedback prepare];
    [feedback selectionChanged];
    if (self.quickActionHandler) self.quickActionHandler((WQMCleanerQuickAction)sender.tag);
}

- (void)cleanButtonTapped
{
    [self controlTouchEnded:_cleanButton];
    UIImpactFeedbackGenerator *feedback =
        [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [feedback impactOccurred];
    if (self.cleanHandler) self.cleanHandler();
}

- (void)controlTouchDown:(UIButton *)sender
{
    [WQMTheme animatePress:sender pressed:YES];
}

- (void)controlTouchEnded:(UIButton *)sender
{
    [WQMTheme animatePress:sender pressed:NO];
}

- (void)updateItems:(NSArray<WQMCleanItem *> *)items
              status:(NSString *)status
         interactive:(BOOL)interactive
{
    unsigned long long total = 0;
    unsigned long long allBytes = 0;
    for (WQMCleanItem *item in items) {
        allBytes += item.bytes;
        if (item.selected) total += item.selectedBytes;
    }
    [WQMTheme animateLabelChange:self.totalLabel update:^{
        self.totalLabel.text = WQMFormatBytes(total);
    }];
    [_progressView setProgress:allBytes ? (CGFloat)total / (CGFloat)allBytes : 0 animated:YES];
    NSUInteger selected = 0;
    for (WQMCleanItem *item in items) if (item.selected) selected++;
    [WQMTheme animateLabelChange:self.selectedLabel update:^{
        self.selectedLabel.text = [NSString stringWithFormat:
                                   WQML(@"CLEAN_SELECTED_COUNT", @"已选择 %lu 个 App"),
                                   (unsigned long)selected];
    }];
    [WQMTheme animateLabelChange:self.statusLabel update:^{
        self.statusLabel.text = status ?: @"";
    }];
    [self updateQuickActionStatesForItems:items interactive:interactive];
    if (!_playedEntrance) {
        _playedEntrance = YES;
        [WQMTheme animateEntrance:_card delay:0.02];
    }
}

- (void)updateQuickActionStatesForItems:(NSArray<WQMCleanItem *> *)items
                            interactive:(BOOL)interactive
{
    NSUInteger eligibleCount = 0;
    NSUInteger selectedCount = 0;
    NSUInteger largeEligibleCount = 0;
    NSUInteger largeSelectedCount = 0;
    NSUInteger selectedSmallCount = 0;
    unsigned long long largeThreshold = 50ULL * 1024ULL * 1024ULL;
    for (WQMCleanItem *item in items) {
        if (!item.eligible) continue;
        eligibleCount++;
        BOOL large = item.bytes >= largeThreshold;
        if (large) largeEligibleCount++;
        if (item.selected) {
            selectedCount++;
            if (large) largeSelectedCount++;
            else selectedSmallCount++;
        }
    }
    _selectAllButton.selected = eligibleCount > 0 && selectedCount == eligibleCount;
    _largeCachesButton.selected = largeEligibleCount > 0 &&
        largeSelectedCount == largeEligibleCount && selectedSmallCount == 0;
    _selectAllButton.enabled = interactive && eligibleCount > 0;
    _largeCachesButton.enabled = interactive && largeEligibleCount > 0;
    _clearSelectionButton.enabled = interactive && selectedCount > 0;
    [_selectAllButton setNeedsUpdateConfiguration];
    [_largeCachesButton setNeedsUpdateConfiguration];
    [_clearSelectionButton setNeedsUpdateConfiguration];
}

- (void)updateCleanActionWithSelectedBytes:(unsigned long long)selectedBytes
                                     enabled:(BOOL)enabled
{
    UIButtonConfiguration *configuration = _cleanButton.configuration;
    configuration.title = selectedBytes
        ? [NSString stringWithFormat:WQML(@"CLEAN_SELECTED_ACTION_BYTES", @"清理已选 %@"),
           WQMFormatBytes(selectedBytes)]
        : WQML(@"CLEAN_SELECTED_ACTION_EMPTY", @"清理所选缓存");
    _cleanButton.configuration = configuration;
    _cleanButton.enabled = enabled;
    [_cleanButton setNeedsUpdateConfiguration];
}

@end

@interface WQMCleanerCompactSummaryView : UIVisualEffectView
@property (nonatomic, strong) UILabel *totalLabel;
@property (nonatomic, strong) UILabel *selectedLabel;
- (void)updateTotalText:(NSString *)totalText selectedText:(NSString *)selectedText;
@end

@implementation WQMCleanerCompactSummaryView {
    UIView *_iconBackground;
    UIImageView *_iconView;
    UIView *_separatorDot;
}

- (instancetype)init
{
    self = [super initWithEffect:
            [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial]];
    if (self) {
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.cornerRadius = 19;
        self.layer.borderWidth = 0.5;
        self.clipsToBounds = YES;

        _iconBackground = [UIView new];
        _iconBackground.translatesAutoresizingMaskIntoConstraints = NO;
        _iconBackground.backgroundColor = WQMTheme.inverseSurfaceColor;
        _iconBackground.layer.cornerRadius = 12;

        _iconView = [[UIImageView alloc] initWithImage:
                     [UIImage systemImageNamed:@"trash"]];
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.tintColor = WQMTheme.inverseTextColor;
        _iconView.preferredSymbolConfiguration =
            [UIImageSymbolConfiguration configurationWithPointSize:12
                                                           weight:UIImageSymbolWeightSemibold];
        [_iconBackground addSubview:_iconView];

        _totalLabel = [UILabel new];
        _totalLabel.font = [UIFont monospacedDigitSystemFontOfSize:13
                                                            weight:UIFontWeightSemibold];
        _totalLabel.textColor = WQMTheme.textPrimaryColor;

        _separatorDot = [UIView new];
        _separatorDot.translatesAutoresizingMaskIntoConstraints = NO;
        _separatorDot.backgroundColor = WQMTheme.textSecondaryColor;
        _separatorDot.layer.cornerRadius = 1.5;

        _selectedLabel = [UILabel new];
        _selectedLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
        _selectedLabel.textColor = WQMTheme.textSecondaryColor;

        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
            _iconBackground, _totalLabel, _separatorDot, _selectedLabel
        ]];
        stack.axis = UILayoutConstraintAxisHorizontal;
        stack.alignment = UIStackViewAlignmentCenter;
        stack.spacing = 6;
        [stack setCustomSpacing:7 afterView:_iconBackground];
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:stack];

        [NSLayoutConstraint activateConstraints:@[
            [stack.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:7],
            [stack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-11],
            [stack.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_iconBackground.widthAnchor constraintEqualToConstant:24],
            [_iconBackground.heightAnchor constraintEqualToConstant:24],
            [_iconView.centerXAnchor constraintEqualToAnchor:_iconBackground.centerXAnchor],
            [_iconView.centerYAnchor constraintEqualToAnchor:_iconBackground.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:14],
            [_iconView.heightAnchor constraintEqualToConstant:14],
            [_separatorDot.widthAnchor constraintEqualToConstant:3],
            [_separatorDot.heightAnchor constraintEqualToConstant:3],
        ]];
        [self updateAppearance];
        [self registerForTraitChanges:@[UITraitUserInterfaceStyle.class,
                                        UITraitAccessibilityContrast.class]
                           withTarget:self
                               action:@selector(updateAppearance)];
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(updateAppearance)
                                                   name:UIAccessibilityReduceTransparencyStatusDidChangeNotification
                                                 object:nil];
    }
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (CGSize)intrinsicContentSize
{
    CGFloat width = 7 + 24 + 7;
    width += ceil(_totalLabel.intrinsicContentSize.width);
    width += 6 + 3 + 6;
    width += ceil(_selectedLabel.intrinsicContentSize.width);
    width += 11;
    return CGSizeMake(width, 36);
}

- (void)updateAppearance
{
    UIVisualEffect *effect = UIAccessibilityIsReduceTransparencyEnabled()
        ? nil
        : [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial];
    self.effect = effect;
    self.backgroundColor = effect
        ? UIColor.clearColor
        : [WQMTheme.raisedSurfaceColor colorWithAlphaComponent:0.97];
    self.layer.borderColor =
        [WQMTheme.separatorColor colorWithAlphaComponent:0.72].CGColor;
}

- (void)updateTotalText:(NSString *)totalText selectedText:(NSString *)selectedText
{
    self.totalLabel.text = totalText ?: @"";
    self.selectedLabel.text = selectedText ?: @"";
    [self invalidateIntrinsicContentSize];
}

@end

@interface WQMCleanTargetOptionView : UIControl
@property (nonatomic, strong) UIImageView *circleView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *pathLabel;
@property (nonatomic, strong) UILabel *sizeLabel;
- (void)configureWithTarget:(WQMCleanTarget *)target;
@end

@implementation WQMCleanTargetOptionView

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;

        _circleView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"circle"]];
        _circleView.translatesAutoresizingMaskIntoConstraints = NO;
        _circleView.preferredSymbolConfiguration =
            [UIImageSymbolConfiguration configurationWithPointSize:17
                                                            weight:UIImageSymbolWeightRegular];

        _nameLabel = [UILabel new];
        _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _nameLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
        _nameLabel.adjustsFontForContentSizeCategory = YES;
        _nameLabel.numberOfLines = 1;

        _pathLabel = [UILabel new];
        _pathLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _pathLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption2];
        _pathLabel.adjustsFontForContentSizeCategory = YES;
        _pathLabel.textColor = WQMTheme.textSecondaryColor;
        _pathLabel.numberOfLines = 1;
        _pathLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;

        _sizeLabel = [UILabel new];
        _sizeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _sizeLabel.textAlignment = NSTextAlignmentRight;
        _sizeLabel.adjustsFontSizeToFitWidth = YES;
        _sizeLabel.minimumScaleFactor = 0.85;
        _sizeLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightRegular];
        _sizeLabel.textColor = WQMTheme.textSecondaryColor;
        [_sizeLabel setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                    forAxis:UILayoutConstraintAxisHorizontal];

        UIStackView *textStack = [[UIStackView alloc] initWithArrangedSubviews:@[_nameLabel, _pathLabel]];
        textStack.axis = UILayoutConstraintAxisVertical;
        textStack.spacing = 1;
        textStack.alignment = UIStackViewAlignmentLeading;
        textStack.translatesAutoresizingMaskIntoConstraints = NO;

        [self addSubview:_circleView];
        [self addSubview:textStack];
        [self addSubview:_sizeLabel];
        [NSLayoutConstraint activateConstraints:@[
            [_circleView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:2],
            [_circleView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_circleView.widthAnchor constraintEqualToConstant:20],
            [_circleView.heightAnchor constraintEqualToConstant:20],
            [textStack.leadingAnchor constraintEqualToAnchor:_circleView.trailingAnchor constant:8],
            [textStack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [textStack.topAnchor constraintGreaterThanOrEqualToAnchor:self.topAnchor constant:6],
            [textStack.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor constant:-6],
            [textStack.trailingAnchor constraintLessThanOrEqualToAnchor:_sizeLabel.leadingAnchor constant:-8],
            [_sizeLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-2],
            [_sizeLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [self.heightAnchor constraintGreaterThanOrEqualToConstant:44],
        ]];
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitButton;
    }
    return self;
}

- (void)configureWithTarget:(WQMCleanTarget *)target
{
    NSString *name = target.relativePath.lastPathComponent;
    if ([target.relativePath isEqualToString:@"Library/Caches"]) {
        name = WQML(@"CLEAN_CHIP_CACHE", @"缓存");
    } else if ([target.relativePath isEqualToString:@"tmp"]) {
        name = WQML(@"CLEAN_CHIP_TMP", @"临时");
    }
    _nameLabel.text = name;
    _pathLabel.text = target.relativePath;
    _sizeLabel.text = target.bytesKnown ? WQMFormatBytes(target.bytes) : WQML(@"UNKNOWN", @"未知");
    self.selected = target.selected;
    self.accessibilityLabel = [NSString stringWithFormat:@"%@ %@，%@",
                               name, _sizeLabel.text,
                               target.selected ? WQML(@"SELECTED", @"已选择")
                                               : WQML(@"NOT_SELECTED", @"未选择")];
}

- (void)setSelected:(BOOL)selected
{
    [super setSelected:selected];
    _circleView.image = [UIImage systemImageNamed:
                         selected ? @"checkmark.circle.fill" : @"circle"];
    _circleView.tintColor = selected ? WQMTheme.textPrimaryColor : WQMTheme.separatorColor;
    _nameLabel.textColor = selected ? WQMTheme.textPrimaryColor : WQMTheme.textSecondaryColor;
}

@end
@interface WQMCleanerCell : UITableViewCell
@property (nonatomic, strong) WQMSoftSurfaceView *cardView;
@property (nonatomic, copy) void (^targetToggleHandler)(WQMCleanItem *item, WQMCleanTarget *target);
@property (nonatomic, copy) void (^selectionToggleHandler)(WQMCleanItem *item);
- (void)configureWithItem:(WQMCleanItem *)item expanded:(BOOL)expanded;
- (void)setExpanded:(BOOL)expanded animated:(BOOL)animated;
- (void)configureEmptyScanning:(BOOL)scanning status:(NSString *)status;
@end

@implementation WQMCleanerCell {
    UIView *_headerContainer;
    UIButton *_selectionButton;
    UIImageView *_iconView;
    UILabel *_titleLabel;
    UILabel *_subtitleLabel;
    UILabel *_sizeLabel;
    UIImageView *_chevronView;
    UIStackView *_textStack;
    UIStackView *_contentStack;
    UIStackView *_optionsStack;
    NSLayoutConstraint *_iconLeadingToSelection;
    NSLayoutConstraint *_iconLeadingToCard;
    NSLayoutConstraint *_sizeTrailingToChevron;
    NSLayoutConstraint *_sizeTrailingToCard;
    WQMCleanTargetOptionView *_optionViews[2];
    NSArray<NSNumber *> *_visibleTargetIndices;
    WQMCleanItem *_currentItem;
    BOOL _expanded;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.accessoryType = UITableViewCellAccessoryNone;
        self.clipsToBounds = NO;
        self.contentView.clipsToBounds = NO;

        _cardView = [[WQMSoftSurfaceView alloc] initWithElevated:NO];
        _cardView.layer.cornerRadius = 20;
        _cardView.translatesAutoresizingMaskIntoConstraints = NO;

        _headerContainer = [UIView new];
        _headerContainer.translatesAutoresizingMaskIntoConstraints = NO;

        _selectionButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _selectionButton.translatesAutoresizingMaskIntoConstraints = NO;
        _selectionButton.tintColor = WQMTheme.textSecondaryColor;
        [_selectionButton addTarget:self
                             action:@selector(selectionTapped)
                   forControlEvents:UIControlEventTouchUpInside];

        _iconView = [UIImageView new];
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconView.contentMode = UIViewContentModeScaleAspectFill;
        _iconView.layer.cornerRadius = 11;
        _iconView.layer.cornerCurve = kCACornerCurveContinuous;
        _iconView.clipsToBounds = YES;
        _iconView.backgroundColor = WQMTheme.canvasColor;

        _titleLabel = [UILabel new];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
        _titleLabel.adjustsFontForContentSizeCategory = YES;
        _titleLabel.numberOfLines = 1;
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [_titleLabel setContentCompressionResistancePriority:749
                                                     forAxis:UILayoutConstraintAxisHorizontal];

        _subtitleLabel = [UILabel new];
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _subtitleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
        _subtitleLabel.adjustsFontForContentSizeCategory = YES;
        _subtitleLabel.textColor = WQMTheme.textSecondaryColor;
        _subtitleLabel.numberOfLines = 1;
        _subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;

        _textStack = [[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel, _subtitleLabel]];
        _textStack.axis = UILayoutConstraintAxisVertical;
        _textStack.spacing = 1;
        _textStack.alignment = UIStackViewAlignmentLeading;
        _textStack.translatesAutoresizingMaskIntoConstraints = NO;

        _sizeLabel = [UILabel new];
        _sizeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _sizeLabel.textAlignment = NSTextAlignmentRight;
        _sizeLabel.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightSemibold];
        _sizeLabel.textColor = WQMTheme.textSecondaryColor;
        _sizeLabel.adjustsFontSizeToFitWidth = YES;
        _sizeLabel.minimumScaleFactor = 0.85;
        [_sizeLabel setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                    forAxis:UILayoutConstraintAxisHorizontal];

        _chevronView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.down"]];
        _chevronView.translatesAutoresizingMaskIntoConstraints = NO;
        _chevronView.contentMode = UIViewContentModeCenter;
        _chevronView.tintColor = WQMTheme.textSecondaryColor;
        _chevronView.preferredSymbolConfiguration =
            [UIImageSymbolConfiguration configurationWithPointSize:13
                                                            weight:UIImageSymbolWeightSemibold];

        [_headerContainer addSubview:_selectionButton];
        [_headerContainer addSubview:_iconView];
        [_headerContainer addSubview:_textStack];
        [_headerContainer addSubview:_sizeLabel];
        [_headerContainer addSubview:_chevronView];

        _optionsStack = [UIStackView new];
        _optionsStack.axis = UILayoutConstraintAxisVertical;
        _optionsStack.spacing = 0;
        _optionsStack.alignment = UIStackViewAlignmentFill;
        _optionsStack.layoutMarginsRelativeArrangement = YES;
        _optionsStack.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(0, 46, 0, 0);
        _optionsStack.hidden = YES;

        for (NSUInteger i = 0; i < 2; i++) {
            WQMCleanTargetOptionView *option = [[WQMCleanTargetOptionView alloc] initWithFrame:CGRectZero];
            option.tag = (NSInteger)i;
            option.hidden = YES;
            [option addTarget:self
                       action:@selector(optionTapped:)
             forControlEvents:UIControlEventTouchUpInside];
            _optionViews[i] = option;
            [_optionsStack addArrangedSubview:option];
        }

        _contentStack = [[UIStackView alloc] initWithArrangedSubviews:
                         @[_headerContainer, _optionsStack]];
        _contentStack.axis = UILayoutConstraintAxisVertical;
        _contentStack.spacing = 2;
        _contentStack.alignment = UIStackViewAlignmentFill;
        _contentStack.translatesAutoresizingMaskIntoConstraints = NO;

        [_cardView addSubview:_contentStack];
        [self.contentView addSubview:_cardView];

        NSLayoutConstraint *fill = [_cardView.widthAnchor constraintEqualToAnchor:self.contentView.widthAnchor
                                                                       constant:-24];
        fill.priority = 999;
        _iconLeadingToSelection = [_iconView.leadingAnchor
            constraintEqualToAnchor:_selectionButton.trailingAnchor constant:10];
        _iconLeadingToCard = [_iconView.leadingAnchor
            constraintEqualToAnchor:_headerContainer.leadingAnchor constant:2];
        _sizeTrailingToChevron = [_sizeLabel.trailingAnchor
            constraintEqualToAnchor:_chevronView.leadingAnchor constant:-8];
        _sizeTrailingToCard = [_sizeLabel.trailingAnchor
            constraintEqualToAnchor:_headerContainer.trailingAnchor constant:-2];

        [NSLayoutConstraint activateConstraints:@[
            [_cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:5],
            [_cardView.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
            [_cardView.widthAnchor constraintLessThanOrEqualToConstant:760],
            fill,
            [_cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-5],
            [_contentStack.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:8],
            [_contentStack.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:14],
            [_contentStack.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-14],
            [_contentStack.bottomAnchor constraintEqualToAnchor:_cardView.bottomAnchor constant:-8],
            [_headerContainer.heightAnchor constraintGreaterThanOrEqualToConstant:52],
            [_selectionButton.leadingAnchor constraintEqualToAnchor:_headerContainer.leadingAnchor],
            [_selectionButton.centerYAnchor constraintEqualToAnchor:_headerContainer.centerYAnchor],
            [_selectionButton.widthAnchor constraintEqualToConstant:30],
            [_selectionButton.heightAnchor constraintEqualToConstant:30],
            [_iconView.centerYAnchor constraintEqualToAnchor:_headerContainer.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:40],
            [_iconView.heightAnchor constraintEqualToConstant:40],
            [_textStack.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:10],
            [_textStack.centerYAnchor constraintEqualToAnchor:_headerContainer.centerYAnchor],
            [_textStack.topAnchor constraintGreaterThanOrEqualToAnchor:_headerContainer.topAnchor constant:6],
            [_textStack.bottomAnchor constraintLessThanOrEqualToAnchor:_headerContainer.bottomAnchor constant:-6],
            [_textStack.trailingAnchor constraintLessThanOrEqualToAnchor:_sizeLabel.leadingAnchor constant:-8],
            [_sizeLabel.centerYAnchor constraintEqualToAnchor:_headerContainer.centerYAnchor],
            [_chevronView.centerYAnchor constraintEqualToAnchor:_headerContainer.centerYAnchor],
            [_chevronView.trailingAnchor constraintEqualToAnchor:_headerContainer.trailingAnchor constant:-2],
            [_chevronView.widthAnchor constraintEqualToConstant:16],
            [_chevronView.heightAnchor constraintEqualToConstant:16],
        ]];
        _iconLeadingToSelection.active = YES;
        _sizeTrailingToChevron.active = YES;
    }
    return self;
}

- (NSArray<NSNumber *> *)visibleTargetIndicesForItem:(WQMCleanItem *)item
{
    NSMutableArray<NSNumber *> *indices = [NSMutableArray new];
    if (!item.eligible) return indices;
    for (NSUInteger i = 0; i < item.targets.count; i++) {
        WQMCleanTarget *target = item.targets[i];
        if (target.existed || target.bytes > 0) [indices addObject:@(i)];
    }
    return indices;
}

- (NSString *)displayNameForTarget:(WQMCleanTarget *)target
{
    if ([target.relativePath isEqualToString:@"Library/Caches"]) {
        return WQML(@"CLEAN_CHIP_CACHE", @"缓存");
    }
    if ([target.relativePath isEqualToString:@"tmp"]) {
        return WQML(@"CLEAN_CHIP_TMP", @"临时");
    }
    return target.relativePath.lastPathComponent ?: @"";
}

- (void)updateOptions
{
    NSUInteger count = _visibleTargetIndices.count;
    for (NSUInteger slot = 0; slot < 2; slot++) {
        WQMCleanTargetOptionView *option = _optionViews[slot];
        if (slot >= count) {
            option.hidden = YES;
            continue;
        }
        NSUInteger targetIndex = _visibleTargetIndices[slot].unsignedIntegerValue;
        WQMCleanTarget *target = _currentItem.targets[targetIndex];
        option.hidden = NO;
        option.tag = (NSInteger)targetIndex;
        [option configureWithTarget:target];
    }
    _optionsStack.hidden = !_expanded || count == 0;
    _chevronView.hidden = count == 0;
}

- (void)updateSelectionButton
{
    BOOL selected = _currentItem.selected;
    UIImage *image = [UIImage systemImageNamed:
                      selected ? @"checkmark.circle.fill" : @"circle"];
    [_selectionButton setImage:image forState:UIControlStateNormal];
    _selectionButton.tintColor = selected ? WQMTheme.textPrimaryColor : WQMTheme.separatorColor;
    NSUInteger selectedTargets = 0;
    for (WQMCleanTarget *target in _currentItem.targets) if (target.selected) selectedTargets++;
    _selectionButton.accessibilityLabel = [NSString stringWithFormat:
        WQML(@"CLEAN_SELECT_ACCESSIBILITY", @"%@，%lu 个位置已选择"),
        selected ? WQML(@"SELECTED", @"已选择") : WQML(@"NOT_SELECTED", @"未选择"),
        (unsigned long)selectedTargets];
}

- (void)setExpanded:(BOOL)expanded animated:(BOOL)animated
{
    _expanded = expanded;
    _optionsStack.hidden = !expanded || _visibleTargetIndices.count == 0;
    CGAffineTransform transform = expanded ? CGAffineTransformMakeRotation((CGFloat)M_PI)
                                           : CGAffineTransformIdentity;
    if (animated && !WQMTheme.shouldReduceMotion) {
        [UIView animateWithDuration:0.22
                              delay:0
                            options:UIViewAnimationOptionCurveEaseInOut
                         animations:^{
            self->_chevronView.transform = transform;
        } completion:nil];
    } else {
        _chevronView.transform = transform;
    }
    self.accessibilityHint = expanded ? WQML(@"CLEAN_COLLAPSE_HINT", @"轻点收起清理选项")
                                      : WQML(@"CLEAN_EXPAND_HINT", @"轻点展开缓存与临时目录");
}

- (void)selectionTapped
{
    if (!_currentItem || !_currentItem.eligible) return;
    _currentItem.selected = !_currentItem.selected;
    [self updateSelectionButton];
    [self updateOptions];
    if (self.selectionToggleHandler) self.selectionToggleHandler(_currentItem);
}

- (void)optionTapped:(WQMCleanTargetOptionView *)sender
{
    if (!_currentItem) return;
    if (sender.tag < 0 || (NSUInteger)sender.tag >= _currentItem.targets.count) return;
    WQMCleanTarget *target = _currentItem.targets[(NSUInteger)sender.tag];
    target.selected = !target.selected;
    [self updateOptions];
    [self updateSelectionButton];
    if (self.targetToggleHandler) self.targetToggleHandler(_currentItem, target);
}

- (void)configureWithItem:(WQMCleanItem *)item expanded:(BOOL)expanded
{
    _currentItem = item;
    _expanded = expanded;
    _visibleTargetIndices = [self visibleTargetIndicesForItem:item];
    _iconView.contentMode = UIViewContentModeScaleAspectFill;
    _iconView.backgroundColor = WQMTheme.canvasColor;

    _titleLabel.text = item.name;
    _titleLabel.textColor = item.eligible ? WQMTheme.textPrimaryColor : WQMTheme.textSecondaryColor;
    UIImage *icon = [WQMAppIconService iconForBundleIdentifier:item.bundleIdentifier
                                                   displayName:item.name];
    if (icon && icon != _iconView.image) _iconView.image = icon;
    _iconView.alpha = item.eligible ? 1 : 0.5;
    _sizeLabel.text = item.eligible ? WQMFormatBytes(item.bytes) : @"";

    NSMutableArray<NSString *> *names = [NSMutableArray new];
    for (NSNumber *number in _visibleTargetIndices) {
        [names addObject:[self displayNameForTarget:item.targets[number.unsignedIntegerValue]]];
    }
    if (!item.eligible) {
        _subtitleLabel.text = item.limitedReason ?: WQML(@"CLEAN_NOT_ELIGIBLE", @"不可清理");
    } else if (names.count) {
        _subtitleLabel.text = [names componentsJoinedByString:@" · "];
    } else {
        _subtitleLabel.text = WQML(@"CLEAN_NO_CACHES_SHORT", @"暂无缓存");
    }
    _subtitleLabel.hidden = _subtitleLabel.text.length == 0;

    _selectionButton.hidden = !item.eligible;
    _chevronView.hidden = _visibleTargetIndices.count == 0;
    _iconLeadingToSelection.active = item.eligible;
    _iconLeadingToCard.active = !item.eligible;
    _sizeTrailingToChevron.active = _visibleTargetIndices.count > 0;
    _sizeTrailingToCard.active = _visibleTargetIndices.count == 0;

    [self updateOptions];
    [self updateSelectionButton];
    [self setExpanded:expanded animated:NO];

    self.accessibilityLabel = [NSString stringWithFormat:@"%@，%@",
                               item.name,
                               item.eligible ? (item.selected ? WQML(@"SELECTED", @"已选择")
                                                               : WQML(@"NOT_SELECTED", @"未选择"))
                                             : (item.limitedReason ?: WQML(@"CLEAN_NOT_ELIGIBLE", @"不可清理"))];
}

- (void)refreshIconWithItem:(WQMCleanItem *)item
{
    UIImage *icon = [WQMAppIconService iconForBundleIdentifier:item.bundleIdentifier
                                                   displayName:item.name];
    if (icon && icon != _iconView.image) _iconView.image = icon;
}

- (void)configureEmptyScanning:(BOOL)scanning status:(NSString *)status
{
    _currentItem = nil;
    _visibleTargetIndices = @[];
    _titleLabel.text = scanning
        ? WQML(@"CLEAN_SCANNING_CACHES", @"正在扫描缓存")
        : WQML(@"CLEAN_NO_ELIGIBLE_CACHES", @"没有可清理的 App 缓存");
    _titleLabel.textColor = WQMTheme.textPrimaryColor;
    _subtitleLabel.text = status;
    _subtitleLabel.hidden = status.length == 0;
    _iconView.contentMode = UIViewContentModeScaleAspectFit;
    _iconView.backgroundColor = UIColor.clearColor;
    _iconView.tintColor = scanning ? WQMTheme.textPrimaryColor : WQMTheme.textSecondaryColor;
    _iconView.image = scanning
        ? [UIImage imageNamed:@"Scan"]
        : [UIImage systemImageNamed:@"checkmark.circle"];
    _iconView.alpha = 1;
    _sizeLabel.text = @"";
    _selectionButton.hidden = YES;
    _chevronView.hidden = YES;
    _optionsStack.hidden = YES;
    _iconLeadingToSelection.active = NO;
    _iconLeadingToCard.active = YES;
    _sizeTrailingToChevron.active = NO;
    _sizeTrailingToCard.active = YES;
}

@end
@implementation WQMCleanerViewController {
    NSArray<WQMCleanItem *> *_items;
    NSString *_status;
    WQScanCancellation *_scanCancellation;
    WQScanCancellation *_cleanCancellation;
    WQMCleanerSummaryView *_summaryView;
    WQMCleanerCompactSummaryView *_compactSummaryView;
    WQMConfirmationGate *_cleanGate;
    BOOL _scanning;
    BOOL _cleaning;
    NSUInteger _scanGeneration;
    NSMutableSet<NSString *> *_expandedKeys;
}

- (instancetype)init
{
    return [super initWithStyle:UITableViewStylePlain];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = WQML(@"TAB_CLEAN", @"清理");
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.tableView.backgroundColor = WQMTheme.canvasColor;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 76;
    self.tableView.cellLayoutMarginsFollowReadableWidth = YES;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    _summaryView = [[WQMCleanerSummaryView alloc] initWithFrame:
                    CGRectMake(0, 0, self.tableView.bounds.size.width, 170)];
    __weak typeof(self) weakSelf = self;
    _summaryView.quickActionHandler = ^(WQMCleanerQuickAction action) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        if (action == WQMCleanerQuickActionSelectAll) {
            [self selectItems:YES largeOnly:NO];
        } else if (action == WQMCleanerQuickActionLargeCaches) {
            [self selectItems:YES largeOnly:YES];
        } else {
            [self selectItems:NO largeOnly:NO];
        }
    };
    _summaryView.cleanHandler = ^{
        __strong typeof(weakSelf) self = weakSelf;
        [self confirmClean];
    };
    _compactSummaryView = [WQMCleanerCompactSummaryView new];
    _compactSummaryView.userInteractionEnabled = NO;
    _compactSummaryView.isAccessibilityElement = YES;
    self.tableView.tableHeaderView = _summaryView;
    self.refreshControl = [UIRefreshControl new];
    [self.refreshControl addTarget:self action:@selector(scan) forControlEvents:UIControlEventValueChanged];
    [self updateNavigation];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(appIconDidResolve:)
                                               name:WQMAppIconDidResolveNotification
                                             object:nil];
    [self scan];
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [WQMAppIconService cancelPendingRequests];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    self.navigationItem.title = WQML(@"TAB_CLEAN", @"清理");
    if (!_scanning && !_items.count) [self scan];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    _compactSummaryView.hidden = YES;
    _compactSummaryView.alpha = 0;
    [_compactSummaryView removeFromSuperview];
    self.navigationItem.title = WQML(@"TAB_CLEAN", @"清理");
    [_scanCancellation cancel];
    [_cleanCancellation cancel];
}

- (void)updateNavigation
{
    unsigned long long selectedBytes = 0;
    NSUInteger selectedCount = 0;
    for (WQMCleanItem *item in _items) {
        if (!item.selected) continue;
        selectedBytes += item.selectedBytes;
        selectedCount++;
    }
    [_summaryView updateCleanActionWithSelectedBytes:selectedBytes
                                            enabled:!_scanning && !_cleaning && selectedCount > 0];
    self.navigationItem.rightBarButtonItem = nil;
}

- (NSArray<WQMCleanItem *> *)selectedItems
{
    return [_items filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"selected == YES"]];
}

- (void)updateSummary
{
    [_summaryView updateItems:_items
                       status:_status ?: @""
                  interactive:!_scanning && !_cleaning];
    unsigned long long selectedBytes = 0;
    NSUInteger selectedCount = 0;
    for (WQMCleanItem *item in _items) {
        if (!item.selected) continue;
        selectedBytes += item.selectedBytes;
        selectedCount++;
    }
    NSString *totalText = WQMFormatBytes(selectedBytes);
    NSString *selectedText = [NSString stringWithFormat:
                              WQML(@"CLEAN_SELECTED_COUNT_SHORT", @"%lu 个 App"),
                              (unsigned long)selectedCount];
    [_compactSummaryView updateTotalText:totalText selectedText:selectedText];
    _compactSummaryView.accessibilityLabel = [NSString stringWithFormat:
        WQML(@"CLEAN_COMPACT_ACCESSIBILITY", @"可清理 %@，已选择 %lu 个 App"),
        totalText, (unsigned long)selectedCount];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    CGSize fitting = [_summaryView systemLayoutSizeFittingSize:
                      CGSizeMake(self.tableView.bounds.size.width, UILayoutFittingCompressedSize.height)
                                        withHorizontalFittingPriority:UILayoutPriorityRequired
                                              verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    if (fabs(self.tableView.tableHeaderView.frame.size.height - fitting.height) > 0.5) {
        UIView *header = self.tableView.tableHeaderView;
        CGRect frame = header.frame;
        frame.size.width = self.tableView.bounds.size.width;
        frame.size.height = fitting.height;
        header.frame = frame;
        self.tableView.tableHeaderView = header;
    }
    [self updateCompactSummaryForScrollView];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    if (scrollView == self.tableView) [self updateCompactSummaryForScrollView];
}

- (void)updateCompactSummaryForScrollView
{
    if (!_summaryView || !_compactSummaryView || self.view.window == nil) return;
    UINavigationController *navigationController = self.navigationController;
    UINavigationBar *navigationBar = navigationController.navigationBar;
    UIView *hostView = navigationController.view;
    if (!navigationBar || !hostView) return;

    CGFloat scrollDistance = self.tableView.contentOffset.y +
        self.tableView.adjustedContentInset.top;
    CGFloat headerHeight = CGRectGetHeight(self.tableView.tableHeaderView.bounds);
    if (headerHeight < 180) headerHeight = 288;
    CGFloat start = MAX(120, headerHeight * 0.55);
    CGFloat end = MAX(start + 90, headerHeight + 20);
    CGFloat progress = (scrollDistance - start) / MAX(end - start, 1);
    progress = MIN(MAX(progress, 0), 1);

    BOOL installed = _compactSummaryView.superview == hostView &&
        !_compactSummaryView.hidden;
    BOOL shouldShow = progress > 0.08 || (installed && progress > 0.02);
    if (shouldShow && !installed) {
        [self attachCompactSummaryViewToNavigationController:navigationController];
        _compactSummaryView.hidden = NO;
        _compactSummaryView.alpha = 0;
        _compactSummaryView.transform = WQMTheme.shouldReduceMotion
            ? CGAffineTransformIdentity
            : CGAffineTransformMakeScale(0.84, 0.84);
        self.navigationItem.title = @"";
        [hostView bringSubviewToFront:_compactSummaryView];
    } else if (!shouldShow && installed) {
        _compactSummaryView.alpha = 0;
        _compactSummaryView.hidden = YES;
        self.navigationItem.title = WQML(@"TAB_CLEAN", @"清理");
        return;
    }
    if (!shouldShow) return;

    CGFloat eased = 1 - pow(1 - progress, 3);
    _compactSummaryView.alpha = MIN(1, progress / 0.45);
    _compactSummaryView.transform = WQMTheme.shouldReduceMotion
        ? CGAffineTransformIdentity
        : CGAffineTransformMakeScale(0.84 + 0.16 * eased,
                                     0.84 + 0.16 * eased);
}

- (void)attachCompactSummaryViewToNavigationController:(UINavigationController *)navigationController
{
    UIView *hostView = navigationController.view;
    UINavigationBar *navigationBar = navigationController.navigationBar;
    if (!hostView || !navigationBar ||
        _compactSummaryView.superview == hostView) {
        return;
    }
    _compactSummaryView.translatesAutoresizingMaskIntoConstraints = NO;
    [hostView addSubview:_compactSummaryView];
    [NSLayoutConstraint activateConstraints:@[
        [_compactSummaryView.centerXAnchor constraintEqualToAnchor:hostView.centerXAnchor],
        [_compactSummaryView.bottomAnchor constraintEqualToAnchor:navigationBar.bottomAnchor
                                                         constant:-4],
        [_compactSummaryView.leadingAnchor constraintGreaterThanOrEqualToAnchor:hostView.leadingAnchor
                                                                       constant:20],
        [_compactSummaryView.trailingAnchor constraintLessThanOrEqualToAnchor:hostView.trailingAnchor
                                                                      constant:-20],
        [_compactSummaryView.heightAnchor constraintEqualToConstant:36],
    ]];
}

- (void)scan
{
    [_scanCancellation cancel];
    WQScanCancellation *cancellation = [WQScanCancellation new];
    _scanCancellation = cancellation;
    NSUInteger generation = ++_scanGeneration;
    _scanning = YES;
    _status = WQML(@"CLEAN_SCANNING_APPS", @"正在扫描 App 缓存…");
    [self updateSummary];
    [self updateNavigation];
    [self.refreshControl beginRefreshing];
    WQMCacheService *service = [WQMCacheService new];
    __weak typeof(self) weakSelf = self;
    [service scanWithCancellation:cancellation progress:^(NSString *status) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || generation != self->_scanGeneration) return;
        self->_status = status;
        [self updateSummary];
    } completion:^(NSArray<WQMCleanItem *> *items, NSString *status) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || generation != self->_scanGeneration) return;
        self->_scanCancellation = nil;
        self->_scanning = NO;
        self->_items = items;
        self->_expandedKeys = [NSMutableSet new];
        for (WQMCleanItem *item in items) {
            if (item.bundleIdentifier.length) [self->_expandedKeys addObject:item.bundleIdentifier];
        }
        self->_status = status;
        [self.refreshControl endRefreshing];
        [self updateSummary];
        [self updateNavigation];
        [self.tableView reloadData];
#if DEBUG
        NSString *fixtureOffset =
            NSProcessInfo.processInfo.environment[@"WQM_UI_CLEANER_SCROLL_OFFSET"];
        if (fixtureOffset.length) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                CGFloat offset = fixtureOffset.doubleValue;
                CGFloat topInset = self.tableView.adjustedContentInset.top;
                [self.tableView setContentOffset:CGPointMake(0, -topInset + offset)
                                        animated:YES];
                [self updateCompactSummaryForScrollView];
            });
        }
#endif
    }];
}

- (void)selectItems:(BOOL)selected largeOnly:(BOOL)largeOnly
{
    for (WQMCleanItem *item in _items) {
        item.selected = item.eligible && (!largeOnly || item.bytes >= 50ULL * 1024 * 1024) ? selected : NO;
    }
    [self updateSummary];
    [self updateNavigation];
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return MAX((NSInteger)_items.count, 1);
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return _items.count ? WQML(@"APP_CACHES", @"App 缓存") : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    WQMCleanerCell *cell = [tableView dequeueReusableCellWithIdentifier:@"clean"];
    if (!cell) {
        cell = [[WQMCleanerCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"clean"];
    }
    if (!_items.count) {
        [cell configureEmptyScanning:_scanning status:_status];
        return cell;
    }
    WQMCleanItem *item = _items[(NSUInteger)indexPath.row];
    __weak typeof(self) weakSelf = self;
    void (^refreshSummary)(void) = ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        [self updateSummary];
        [self updateNavigation];
    };
    cell.targetToggleHandler = ^(WQMCleanItem *targetItem, WQMCleanTarget *target) {
        refreshSummary();
    };
    cell.selectionToggleHandler = ^(WQMCleanItem *targetItem) {
        refreshSummary();
    };
    BOOL expanded = !_expandedKeys || [_expandedKeys containsObject:item.bundleIdentifier];
    [cell configureWithItem:item expanded:expanded];
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.row >= (NSInteger)_items.count) return;
    WQMCleanItem *item = _items[(NSUInteger)indexPath.row];
    [WQMAppIconService requestIconForBundleIdentifier:item.bundleIdentifier
                                          displayName:item.name];
}

- (void)appIconDidResolve:(NSNotification *)notification
{
    NSString *bundleIdentifier = notification.userInfo[WQMAppIconBundleIdentifierKey];
    if (!bundleIdentifier.length) return;
    NSUInteger index = [_items indexOfObjectPassingTest:
        ^BOOL(WQMCleanItem *item, NSUInteger __unused idx, BOOL *__unused stop) {
            return [item.bundleIdentifier isEqualToString:bundleIdentifier];
        }];
    if (index == NSNotFound || index >= (NSUInteger)[self.tableView numberOfRowsInSection:0]) return;
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:(NSInteger)index inSection:0];
    WQMCleanerCell *cell = (WQMCleanerCell *)[self.tableView cellForRowAtIndexPath:indexPath];
    if (cell) [cell refreshIconWithItem:_items[index]];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (_scanning || _cleaning || indexPath.row >= (NSInteger)_items.count) return;
    WQMCleanItem *item = _items[(NSUInteger)indexPath.row];
    if (!item.eligible) {
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:WQML(@"CLEAN_NOT_ELIGIBLE", @"不可清理")
                             message:item.limitedReason
                                 ?: WQML(@"CLEAN_INCOMPLETE_INFO", @"缓存信息不完整")
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:WQML(@"OK", @"确定")
                                                   style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    if (!_expandedKeys) _expandedKeys = [NSMutableSet new];
    NSString *key = item.bundleIdentifier;
    BOOL expanded = ![_expandedKeys containsObject:key];
    if (expanded) [_expandedKeys addObject:key];
    else [_expandedKeys removeObject:key];
    WQMCleanerCell *cell = (WQMCleanerCell *)[tableView cellForRowAtIndexPath:indexPath];
    [tableView beginUpdates];
    [cell setExpanded:expanded animated:YES];
    [tableView endUpdates];
}

- (void)confirmClean
{
    NSArray<WQMCleanItem *> *selected = [self selectedItems];
    if (!selected.count) return;
    unsigned long long total = 0;
    for (WQMCleanItem *item in selected) total += item.selectedBytes;
    _cleanGate = [WQMConfirmationGate new];
    NSString *operation = [@"clean:" stringByAppendingString:NSUUID.UUID.UUIDString];
    if (![_cleanGate beginForOperation:operation]) return;
    UIAlertController *scope = [UIAlertController
        alertControllerWithTitle:WQML(@"CLEAN_SCOPE_TITLE", @"确认清理范围")
                         message:[NSString stringWithFormat:
                                  WQML(@"CLEAN_SCOPE_MESSAGE",
                                       @"将清理 %lu 个 App 的 Library/Caches 和 tmp，约 %@。\n\n"
                                        "缓存不会备份，部分离线内容可能需要重新下载。请先关闭这些 App。"),
                                  (unsigned long)selected.count,
                                  WQMFormatBytes(total)]
                  preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [scope addAction:[UIAlertAction actionWithTitle:WQML(@"CANCEL", @"取消") style:UIAlertActionStyleCancel
                                            handler:^(__unused UIAlertAction *action) {
        __strong typeof(weakSelf) self = weakSelf;
        [self->_cleanGate cancel];
    }]];
    [scope addAction:[UIAlertAction actionWithTitle:WQML(@"UNDERSTOOD_CONTINUE", @"我已了解，继续") style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || ![self->_cleanGate acknowledgeScopeForOperation:operation]) return;
        if (!WQMCleanDoubleConfirmEnabled()) {
            if (![self->_cleanGate authorizeExecutionForOperation:operation]) return;
            [self cleanItems:selected];
            return;
        }
        [self showFinalCleanConfirmation:operation items:selected];
    }]];
    [self presentViewController:scope animated:YES completion:nil];
}

- (void)showFinalCleanConfirmation:(NSString *)operation items:(NSArray<WQMCleanItem *> *)items
{
    NSString *confirmationWord = WQML(@"CLEAN_CONFIRM_WORD", @"清理");
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:WQML(@"FINAL_CONFIRM_TITLE", @"最终确认")
                         message:[NSString stringWithFormat:
                                  WQML(@"CLEAN_FINAL_MESSAGE",
                                       @"这是第二次确认。将清理 %lu 个 App 的缓存和临时文件，且不会保留缓存备份。\n\n请输入“%@”继续。"),
                                  (unsigned long)items.count,
                                  confirmationWord]
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = confirmationWord;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:WQML(@"CANCEL", @"取消") style:UIAlertActionStyleCancel
                                            handler:^(__unused UIAlertAction *action) {
        __strong typeof(weakSelf) self = weakSelf;
        [self->_cleanGate cancel];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:WQML(@"CLEAN_START_ACTION", @"开始清理") style:UIAlertActionStyleDestructive
                                            handler:^(__unused UIAlertAction *action) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        NSString *typed = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:
                           NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (![typed isEqualToString:confirmationWord]) {
            UIAlertController *error = [UIAlertController
                alertControllerWithTitle:WQML(@"CLEAN_CONFIRM_MISMATCH_TITLE", @"确认文字不匹配")
                                 message:WQML(@"CLEAN_CONFIRM_MISMATCH_MESSAGE",
                                              @"没有执行任何清理操作。")
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [error addAction:[UIAlertAction actionWithTitle:WQML(@"OK", @"确定")
                                                       style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:error animated:YES completion:nil];
            return;
        }
        if (![self->_cleanGate authorizeExecutionForOperation:operation]) return;
        [self cleanItems:items];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)cleanItems:(NSArray<WQMCleanItem *> *)items
{
    WQScanCancellation *cancellation = [WQScanCancellation new];
    _cleanCancellation = cancellation;
    _cleaning = YES;
    [self updateNavigation];
    UIAlertController *progress = [UIAlertController alertControllerWithTitle:WQML(@"CLEAN_PROGRESS_TITLE", @"正在清理")
                                                                      message:WQML(@"PREPARING", @"准备中…")
                                                               preferredStyle:UIAlertControllerStyleAlert];
    [progress addAction:[UIAlertAction actionWithTitle:WQML(@"STOP", @"停止") style:UIAlertActionStyleCancel
                                               handler:^(__unused UIAlertAction *action) {
        [cancellation cancel];
    }]];
    [self presentViewController:progress animated:YES completion:nil];
    WQMCacheService *service = [WQMCacheService new];
    __weak typeof(self) weakSelf = self;
    [service cleanItems:items cancellation:cancellation progress:^(NSString *status) {
        progress.message = status;
    } completion:^(unsigned long long freed, NSUInteger cleanedCount, NSUInteger failedCount, BOOL cancelled) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self->_cleaning = NO;
        self->_cleanCancellation = nil;
        [progress dismissViewControllerAnimated:YES completion:^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf scan];
            UIAlertController *result = [UIAlertController
                alertControllerWithTitle:cancelled
                    ? WQML(@"CLEAN_STOPPED_TITLE", @"清理已停止")
                    : WQML(@"CLEAN_COMPLETE_TITLE", @"清理完成")
                                 message:[NSString stringWithFormat:
                                          WQML(@"CLEAN_RESULT_MESSAGE",
                                               @"已释放约 %@。\n成功 %lu 个，失败 %lu 个。"),
                                          WQMFormatBytes(freed),
                                          (unsigned long)cleanedCount, (unsigned long)failedCount]
                          preferredStyle:UIAlertControllerStyleAlert];
            [result addAction:[UIAlertAction actionWithTitle:WQML(@"OK", @"确定")
                                                       style:UIAlertActionStyleDefault handler:nil]];
            [strongSelf presentViewController:result animated:YES completion:nil];
        }];
    }];
}

@end

