#import "WQMLegalViewController.h"
#import "WQMConsentStore.h"
#import "WQMLanguageManager.h"
#import "WQMTheme.h"

@implementation WQMLegalViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = WQML(@"DISCLAIMER", @"免责协议");
    self.view.backgroundColor = WQMTheme.canvasColor;

    UILabel *titleLabel = [UILabel new];
    titleLabel.text = WQML(@"READ_BEFORE_USE", @"使用前请阅读");
    titleLabel.font = [WQMTheme titleFont];
    titleLabel.textColor = WQMTheme.textPrimaryColor;
    titleLabel.textAlignment = NSTextAlignmentCenter;

    UILabel *subtitleLabel = [UILabel new];
    subtitleLabel.text = WQML(@"WQMANAGER_SUBTITLE", @"WQManager · 开源 App 数据管理器");
    subtitleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    subtitleLabel.textColor = WQMTheme.textSecondaryColor;
    subtitleLabel.textAlignment = NSTextAlignmentCenter;

    WQMSoftSurfaceView *textCard = [[WQMSoftSurfaceView alloc] initWithElevated:YES];
    textCard.layer.cornerRadius = WQMTheme.largeRadius;
    textCard.translatesAutoresizingMaskIntoConstraints = NO;

    UITextView *textView = [UITextView new];
    textView.text = [WQMConsentStore disclaimerText];
    textView.editable = NO;
    textView.selectable = YES;
    textView.backgroundColor = UIColor.clearColor;
    textView.layer.cornerRadius = WQMTheme.largeRadius;
    textView.layer.cornerCurve = kCACornerCurveContinuous;
    textView.textContainerInset = UIEdgeInsetsMake(20, 18, 20, 18);
    textView.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    textView.textColor = WQMTheme.textPrimaryColor;
    textView.translatesAutoresizingMaskIntoConstraints = NO;
    [textCard addSubview:textView];
    [NSLayoutConstraint activateConstraints:@[
        [textView.topAnchor constraintEqualToAnchor:textCard.topAnchor constant:2],
        [textView.leadingAnchor constraintEqualToAnchor:textCard.leadingAnchor constant:2],
        [textView.trailingAnchor constraintEqualToAnchor:textCard.trailingAnchor constant:-2],
        [textView.bottomAnchor constraintEqualToAnchor:textCard.bottomAnchor constant:-2],
    ]];

    UIButton *acceptButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [acceptButton setTitle:WQML(@"ACCEPT_DISCLAIMER", @"我已阅读并同意免责协议") forState:UIControlStateNormal];
    acceptButton.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    acceptButton.backgroundColor = WQMTheme.inverseSurfaceColor;
    [acceptButton setTitleColor:WQMTheme.inverseTextColor forState:UIControlStateNormal];
    acceptButton.layer.cornerRadius = 27;
    acceptButton.layer.cornerCurve = kCACornerCurveContinuous;
    [acceptButton addTarget:self action:@selector(acceptDisclaimer) forControlEvents:UIControlEventTouchUpInside];

    UIButton *openSourceButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [openSourceButton setTitle:WQML(@"OPEN_SOURCE_FOOTER", @"本项目以 GPL-3.0-or-later 开源") forState:UIControlStateNormal];
    openSourceButton.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    openSourceButton.userInteractionEnabled = NO;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        titleLabel, subtitleLabel, textCard, acceptButton, openSourceButton
    ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 16;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [stack setCustomSpacing:6 afterView:titleLabel];
    [stack setCustomSpacing:20 afterView:subtitleLabel];
    [self.view addSubview:stack];

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-20],
        [stack.topAnchor constraintEqualToAnchor:guide.topAnchor constant:24],
        [stack.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor constant:-16],
        [acceptButton.heightAnchor constraintGreaterThanOrEqualToConstant:52],
        [textCard.heightAnchor constraintGreaterThanOrEqualToConstant:300],
    ]];
    [WQMTheme animateEntrance:stack delay:0.04];
}

- (void)acceptDisclaimer
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:WQML(@"CONFIRM_DISCLAIMER", @"确认免责协议")
                                                                   message:WQML(@"CONFIRM_DISCLAIMER_MESSAGE", @"继续即表示你理解 App 数据操作可能导致数据丢失或 App 异常，并同意自行承担相关风险。")
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:WQML(@"BACK_TO_READING", @"返回阅读") style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:WQML(@"AGREE_AND_CONTINUE", @"同意并继续")
                                              style:UIAlertActionStyleDestructive
                                            handler:^(__unused UIAlertAction *action) {
        [WQMConsentStore acceptCurrentDisclaimer];
        if (weakSelf.acceptanceHandler) weakSelf.acceptanceHandler();
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

