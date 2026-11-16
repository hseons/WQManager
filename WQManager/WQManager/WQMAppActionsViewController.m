#import "WQMAppActionsViewController.h"
#import "WQMAppIconService.h"
#import "WQMAppModel.h"
#import "WQMLanguageManager.h"
#import "WQMTheme.h"

@implementation WQMAppActionsViewController {
    WQMAppModel *_app;
}

- (instancetype)initWithApp:(WQMAppModel *)app
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _app = app;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = WQMTheme.canvasColor;
    self.modalPresentationStyle = UIModalPresentationPageSheet;
    self.sheetPresentationController.detents = @[
        UISheetPresentationControllerDetent.mediumDetent,
        UISheetPresentationControllerDetent.largeDetent,
    ];
    self.sheetPresentationController.prefersGrabberVisible = YES;
    self.sheetPresentationController.preferredCornerRadius = WQMTheme.largeRadius;

    UIImageView *icon = [UIImageView new];
    icon.image = [WQMAppIconService iconForBundleIdentifier:_app.bundleIdentifier
                                                 displayName:_app.displayName];
    icon.tintColor = WQMTheme.textPrimaryColor;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.layer.cornerRadius = 15;
    icon.layer.cornerCurve = kCACornerCurveContinuous;
    icon.clipsToBounds = YES;
    [icon.widthAnchor constraintEqualToConstant:58].active = YES;
    [icon.heightAnchor constraintEqualToConstant:58].active = YES;

    UILabel *name = [UILabel new];
    name.text = _app.displayName;
    name.font = [WQMTheme titleFont];
    name.textColor = WQMTheme.textPrimaryColor;

    UILabel *detail = [UILabel new];
    detail.text = [NSString stringWithFormat:@"%@\n%@", _app.formattedSize, _app.bundleIdentifier];
    detail.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    detail.textColor = WQMTheme.textSecondaryColor;
    detail.numberOfLines = 2;

    UIStackView *nameStack = [[UIStackView alloc] initWithArrangedSubviews:@[name, detail]];
    nameStack.axis = UILayoutConstraintAxisVertical;
    nameStack.spacing = 4;

    UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[icon, nameStack]];
    header.axis = UILayoutConstraintAxisHorizontal;
    header.alignment = UIStackViewAlignmentCenter;
    header.spacing = 14;

    UIButton *quick = [self actionButtonWithTitle:WQML(@"QUICK_BACKUP", @"快速备份")
                                         subtitle:WQML(@"QUICK_BACKUP_SUB", @"Documents 和 Library")
                                           symbol:@"arrow.up.doc.fill"
                                          primary:YES
                                           action:WQMAppActionQuickBackup];
    UIButton *full = [self actionButtonWithTitle:WQML(@"FULL_BACKUP", @"完整备份")
                                        subtitle:WQML(@"FULL_BACKUP_SUB", @"额外包含 tmp")
                                          symbol:@"externaldrive.fill.badge.plus"
                                         primary:NO
                                          action:WQMAppActionFullBackup];
    UIButton *restore = [self actionButtonWithTitle:WQML(@"RESTORE_BACKUP", @"从备份恢复")
                                           subtitle:WQML(@"RESTORE_SUB", @"替换同一 App 的数据")
                                             symbol:@"arrow.triangle.2.circlepath"
                                            primary:NO
                                             action:WQMAppActionRestore];
    UIButton *space = [self actionButtonWithTitle:WQML(@"LENS_TITLE", @"空间透镜")
                                         subtitle:WQML(@"LENS_SUB", @"查看容器里谁占空间")
                                           symbol:@"circle.grid.2x2"
                                          primary:NO
                                           action:WQMAppActionInspectSpace];
    UIButton *find = [self actionButtonWithTitle:WQML(@"FILE_FINDER", @"文件查找")
                                        subtitle:WQML(@"FILE_FINDER_SUBTITLE", @"大文件、搜索与类型筛选")
                                          symbol:@"doc.text.magnifyingglass" primary:NO action:WQMAppActionFindFiles];
    UIButton *custom = [self actionButtonWithTitle:WQML(@"CUSTOM_BACKUP", @"自定义备份")
                                          subtitle:WQML(@"CUSTOM_BACKUP_SUBTITLE", @"选择需要保留的目录")
                                            symbol:@"folder.badge.gearshape" primary:NO action:WQMAppActionCustomBackup];
    UIButton *copy = [self actionButtonWithTitle:WQML(@"COPY_BUNDLE", @"复制 Bundle ID")
                                        subtitle:_app.bundleIdentifier
                                          symbol:@"doc.on.doc"
                                         primary:NO
                                          action:WQMAppActionCopyBundleID];

    UIButton *refresh = [self actionButtonWithTitle:WQML(@"APP_REFRESH_ONE", @"刷新这个 App") subtitle:WQML(@"APP_REFRESH_ONE_SUB", @"重新核对身份与统计大小") symbol:@"arrow.clockwise" primary:NO action:WQMAppActionRefresh];
    UIButton *diagnose = [self actionButtonWithTitle:WQML(@"ACCESS_TITLE", @"访问能力") subtitle:WQML(@"ACCESS_SETTINGS_SUB", @"检查受限原因与导出脱敏报告") symbol:@"stethoscope" primary:NO action:WQMAppActionDiagnose];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        header, quick, full, custom, restore, space, find, refresh, diagnose, copy
    ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 10;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [stack setCustomSpacing:20 afterView:header];
    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scroll];
    [scroll addSubview:stack];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-36],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-18],
    ]];
    UILayoutGuide *guide = scroll.contentLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:guide.topAnchor constant:18],
        [stack.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:18],
        [stack.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-18],
        [quick.heightAnchor constraintGreaterThanOrEqualToConstant:60],
        [full.heightAnchor constraintGreaterThanOrEqualToConstant:60],
        [restore.heightAnchor constraintGreaterThanOrEqualToConstant:60],
        [space.heightAnchor constraintGreaterThanOrEqualToConstant:60],
        [copy.heightAnchor constraintGreaterThanOrEqualToConstant:56],
    ]];
    [WQMTheme animateEntrance:stack delay:0.02];
}

- (UIButton *)actionButtonWithTitle:(NSString *)title
                           subtitle:(NSString *)subtitle
                             symbol:(NSString *)symbol
                            primary:(BOOL)primary
                             action:(WQMAppAction)action
{
    UIButtonConfiguration *configuration = primary
        ? [UIButtonConfiguration filledButtonConfiguration]
        : [UIButtonConfiguration grayButtonConfiguration];
    configuration.title = title;
    configuration.subtitle = subtitle;
    configuration.image = [UIImage systemImageNamed:symbol];
    configuration.imagePlacement = NSDirectionalRectEdgeLeading;
    configuration.imagePadding = 12;
    configuration.titleAlignment = UIButtonConfigurationTitleAlignmentLeading;
    configuration.cornerStyle = UIButtonConfigurationCornerStyleLarge;
    configuration.contentInsets = NSDirectionalEdgeInsetsMake(10, 14, 10, 14);
    configuration.baseBackgroundColor = primary ? WQMTheme.inverseSurfaceColor : WQMTheme.surfaceColor;
    configuration.baseForegroundColor = primary ? WQMTheme.inverseTextColor : WQMTheme.textPrimaryColor;
    configuration.titleTextAttributesTransformer =
        ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *attributes) {
        NSMutableDictionary *updated = [attributes mutableCopy];
        updated[NSFontAttributeName] = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
        return updated;
    };
    UIButton *button = [UIButton buttonWithConfiguration:configuration primaryAction:nil];
    button.tag = action;
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
    [button addTarget:self action:@selector(actionTapped:) forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)actionTapped:(UIButton *)sender
{
    WQMAppAction action = (WQMAppAction)sender.tag;
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [feedback impactOccurred];
    void (^handler)(WQMAppAction) = self.actionHandler;
    [self dismissViewControllerAnimated:YES completion:^{
        if (handler) handler(action);
    }];
}

@end

