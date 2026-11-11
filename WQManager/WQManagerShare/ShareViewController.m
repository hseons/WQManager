#import "ShareViewController.h"
#import "WQMSharedInbox.h"

@interface ShareViewController ()
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic) BOOL started;
@end

@implementation ShareViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.preferredContentSize = CGSizeMake(0, 260);

    UILabel *title = [UILabel new];
    title.text = @"WQManager";
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle2];
    title.textAlignment = NSTextAlignmentCenter;

    UIImageView *icon = [[UIImageView alloc] initWithImage:
                         [UIImage systemImageNamed:@"externaldrive.fill.badge.timemachine"]];
    icon.tintColor = UIColor.labelColor;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    [icon.heightAnchor constraintEqualToConstant:48].active = YES;

    self.statusLabel = [UILabel new];
    self.statusLabel.text = @"正在交给 WQManager…";
    self.statusLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.statusLabel.textColor = UIColor.secondaryLabelColor;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.numberOfLines = 0;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:
                          @[icon, title, self.statusLabel]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 14;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:guide.leadingAnchor constant:24],
        [stack.trailingAnchor constraintLessThanOrEqualToAnchor:guide.trailingAnchor constant:-24],
        [stack.centerXAnchor constraintEqualToAnchor:guide.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:guide.centerYAnchor],
    ]];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    if (self.started) return;
    self.started = YES;
    [self receiveSharedBackup];
}

- (void)receiveSharedBackup
{
    NSExtensionItem *item = self.extensionContext.inputItems.firstObject;
    NSItemProvider *provider = nil;
    NSString *typeIdentifier = nil;
    for (NSItemProvider *candidate in item.attachments ?: @[]) {
        for (NSString *identifier in candidate.registeredTypeIdentifiers) {
            if ([identifier isEqualToString:@"com.mumu.wqmanager.backup"]) {
                provider = candidate;
                typeIdentifier = identifier;
                break;
            }
        }
        if (provider) break;
    }
    if (!provider) {
        [self finishWithMessage:@"没有找到可导入的 .wqbackup 文件。" success:NO];
        return;
    }

    __weak typeof(self) weakSelf = self;
    [provider loadFileRepresentationForTypeIdentifier:typeIdentifier
                                   completionHandler:^(NSURL *url, NSError *loadError) {
        NSError *inboxError = nil;
        BOOL saved = url && [WQMSharedInbox enqueueURL:url error:&inboxError];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!saved) {
                if (inboxError.code == 1) {
                    [weakSelf openManualImportAfterAppGroupFailure];
                    return;
                }
                [weakSelf finishWithMessage:
                    inboxError.localizedDescription ?: loadError.localizedDescription
                                         success:NO];
                return;
            }
            [weakSelf finishWithMessage:@"已交给 WQManager，正在打开…" success:YES];
            if (![weakSelf openHostApp]) {
                weakSelf.statusLabel.text = @"已保存。若没有自动打开，请回到 WQManager，进入备份页后会继续导入。";
            }
        });
    }];
}

- (void)openManualImportAfterAppGroupFailure
{
    self.statusLabel.text = @"当前签名未启用 App Group，正在打开手动导入…";
    self.statusLabel.textColor = UIColor.secondaryLabelColor;
    if (![self openHostApp]) {
        [self finishWithMessage:
            @"当前签名未启用 App Group。请打开 WQManager → 备份 → 左上角导入。"
                             success:NO];
    }
}

- (BOOL)openHostApp
{
    NSURL *url = [NSURL URLWithString:@"wqmanager://import"];
    SEL selector = NSSelectorFromString(@"openURL:");
    UIResponder *responder = self;
    while ((responder = [responder nextResponder])) {
        if ([responder respondsToSelector:selector]) {
            IMP implementation = [responder methodForSelector:selector];
            void (*function)(id, SEL, id) = (void *)implementation;
            function(responder, selector, url);
            return YES;
        }
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [self.extensionContext openURL:url completionHandler:nil];
#pragma clang diagnostic pop
    return NO;
}

- (void)finishWithMessage:(NSString *)message success:(BOOL)success
{
    self.statusLabel.text = message;
    self.statusLabel.textColor = success ? UIColor.secondaryLabelColor : UIColor.systemRedColor;
    if (!success) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self.extensionContext completeRequestReturningItems:@[]
                                           completionHandler:nil];
    });
}

@end
