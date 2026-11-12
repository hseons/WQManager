#import "WQMSettingsViewController.h"
#import "WQMProjectLinks.h"
#import "WQMAppCache.h"
#import "WQMAppIconService.h"
#import "WQMConsentStore.h"
#import "WQMLanguageManager.h"
#import "WQMCreditsViewController.h"
#import "WQMMarkdownRenderer.h"
#import "WQMOperationStore.h"
#import "WQMPreferences.h"
#import "WQMTheme.h"
#import "WQAccess.h"

static NSString *WQMLoadProfileName(WQMLoadProfile profile)
{
    switch (profile) {
        case WQMLoadProfileStandard: return WQML(@"LOAD_PROFILE_STANDARD", @"标准");
        case WQMLoadProfileLowLoad: return WQML(@"LOAD_PROFILE_LOWLOAD", @"低负载");
        case WQMLoadProfileAutomatic:
        default: return WQML(@"LOAD_PROFILE_AUTOMATIC", @"自动");
    }
}

@interface WQMTextDocumentViewController : UIViewController

@property (nonatomic, copy) NSString *documentTitle;
@property (nonatomic, copy) NSString *documentText;
@property (nonatomic) BOOL reflowPlainText;

@end

@implementation WQMTextDocumentViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = self.documentTitle;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor = WQMTheme.canvasColor;

    UITextView *textView = [UITextView new];
    textView.editable = NO;
    textView.selectable = YES;
    textView.backgroundColor = WQMTheme.surfaceColor;
    textView.textColor = WQMTheme.textPrimaryColor;
    textView.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    textView.dataDetectorTypes = UIDataDetectorTypeLink;
    textView.linkTextAttributes = @{
        NSForegroundColorAttributeName: WQMTheme.textPrimaryColor,
        NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
    };
    if (self.reflowPlainText) {
        textView.attributedText = [self reflowedLicenseText:self.documentText];
        textView.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
    } else {
        textView.attributedText = [WQMMarkdownRenderer attributedStringFromMarkdown:self.documentText];
    }
    textView.textContainerInset = UIEdgeInsetsMake(18, 16, 22, 16);
    textView.layer.cornerRadius = WQMTheme.mediumRadius;
    textView.layer.cornerCurve = kCACornerCurveContinuous;
    textView.layer.borderWidth = 1;
    textView.layer.borderColor = WQMTheme.separatorColor.CGColor;
    textView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:textView];
    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [textView.topAnchor constraintEqualToAnchor:guide.topAnchor constant:16],
        [textView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:16],
        [textView.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-16],
        [textView.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor constant:-16],
    ]];
}

- (NSAttributedString *)reflowedLicenseText:(NSString *)text
{
    NSMutableAttributedString *result = [NSMutableAttributedString new];
    NSArray<NSString *> *paragraphs = [text componentsSeparatedByString:@"\n\n"];
    NSMutableParagraphStyle *bodyStyle = [NSMutableParagraphStyle new];
    bodyStyle.paragraphSpacing = 12;
    bodyStyle.lineSpacing = 4;
    for (NSString *raw in paragraphs) {
        NSString *paragraph = [[raw componentsSeparatedByCharactersInSet:
                                NSCharacterSet.whitespaceAndNewlineCharacterSet]
                               componentsJoinedByString:@" "];
        paragraph = [paragraph stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (!paragraph.length) continue;
        BOOL heading = (paragraph.length < 100 && [paragraph isEqualToString:paragraph.uppercaseString]) ||
            [paragraph isEqualToString:@"Preamble"] ||
            [paragraph hasPrefix:@"How to Apply"] ||
            [paragraph rangeOfString:@"^\\d+\\. [A-Z]" options:NSRegularExpressionSearch].location != NSNotFound;
        NSDictionary *attributes = @{
            NSFontAttributeName: heading
                ? [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline]
                : [UIFont preferredFontForTextStyle:UIFontTextStyleBody],
            NSForegroundColorAttributeName: WQMTheme.textPrimaryColor,
            NSParagraphStyleAttributeName: bodyStyle,
        };
        if (result.length) [result appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];
        [result appendAttributedString:[[NSAttributedString alloc] initWithString:paragraph
                                                                       attributes:attributes]];
    }
    return result;
}

@end

typedef NS_ENUM(NSInteger, WQMSettingsRow) {
    WQMSettingsRowLanguage = 0,
    WQMSettingsRowVersion,
    WQMSettingsRowCheckUpdate,
    WQMSettingsRowSigning,
    WQMSettingsRowIndex,
    WQMSettingsRowClearIndex,
    WQMSettingsRowOperations,
    WQMSettingsRowCleanConfirmation,
    WQMSettingsRowDisclaimer,
    WQMSettingsRowSafety,
    WQMSettingsRowLicense,
    WQMSettingsRowNotices,
};

@implementation WQMSettingsViewController {
    NSString *_versionText;
    NSString *_signingText;
    NSString *_indexText;
    NSString *_languageText;
    NSUInteger _operationCount;
    BOOL _hasAppGroup;
    BOOL _presentedFixtureDocument;
    BOOL _checkingUpdate;
}

- (instancetype)init
{
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = WQML(@"TAB_SETTINGS", @"设置");
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.tableView.backgroundColor = WQMTheme.canvasColor;
    self.tableView.cellLayoutMarginsFollowReadableWidth = YES;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;

    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    NSString *version = info[@"CFBundleShortVersionString"] ?: @"0.1";
    NSString *build = info[@"CFBundleVersion"] ?: @"1";
    _versionText = [NSString stringWithFormat:@"%@ (%@)", version, build];
    _signingText = WQML(@"DETECTING", @"检测中");
    _indexText = WQML(@"READING", @"读取中");
    _languageText = [[WQMLanguageManager sharedManager].languageCode isEqualToString:[WQMLanguageManager english]]
        ? WQML(@"LANGUAGE_EN", @"English")
        : WQML(@"LANGUAGE_ZH", @"简体中文");
    [self reloadState];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self reloadState];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
#if DEBUG
    if ([NSProcessInfo.processInfo.environment[@"WQM_UI_SETTINGS_SCROLL"] boolValue]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            CGFloat bottom = self.tableView.contentSize.height - self.tableView.bounds.size.height
                           + self.tableView.adjustedContentInset.bottom + 96;
            if (bottom > 0) [self.tableView setContentOffset:CGPointMake(0, bottom) animated:NO];
        });
    }
#endif
#if DEBUG
    NSString *fixtureRow = NSProcessInfo.processInfo.environment[@"WQM_UI_SETTINGS_DOC"];
    if (fixtureRow.length && !_presentedFixtureDocument) {
        _presentedFixtureDocument = YES;
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:fixtureRow.integerValue inSection:2];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self tableView:self.tableView didSelectRowAtIndexPath:indexPath];
        });
    }
#endif
}

- (void)reloadState
{
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *group = wq_app_group();
        WQMAppCacheSnapshot *snapshot = [WQMAppCache load];
        NSArray<WQMOperationRecord *> *operations = [WQMOperationStore allOperations];
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_signingText = group.length
                ? [NSString stringWithFormat:@"App Group · %@", group]
                : WQML(@"NO_APP_GROUP", @"未配置 App Group");
            self->_hasAppGroup = group.length > 0;
            if (snapshot) {
                NSDateFormatter *formatter = [NSDateFormatter new];
                formatter.locale = [WQMLanguageManager sharedManager].locale;
                formatter.dateStyle = NSDateFormatterShortStyle;
                formatter.timeStyle = NSDateFormatterShortStyle;
                self->_indexText = [NSString stringWithFormat:WQML(@"APP_INDEX_DETAIL", @"%lu 个 App · %@"),
                                    (unsigned long)snapshot.apps.count,
                                    [formatter stringFromDate:snapshot.updatedAt]];
            } else {
                self->_indexText = WQML(@"NO_APP_INDEX", @"尚未建立索引");
            }
            self->_operationCount = operations.count;
            [self.tableView reloadData];
        });
    });
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 4; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == 0) return 4;
    if (section == 1) return 5;
    if (section == 2) return 4;
    return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (section == 0) return WQML(@"SETTINGS_APP", @"应用");
    if (section == 1) return WQML(@"SETTINGS_DATA", @"数据");
    if (section == 2) return WQML(@"SETTINGS_DOCS", @"文档与许可");
    return WQML(@"SETTINGS_ABOUT", @"关于");
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (section == 3) return [NSString stringWithFormat:WQML(@"DEVELOPMENT_FOOTER", @"WQManager %@ 为开发预览版本。"), _versionText ?: @""];
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *identifier = @"setting";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    UIListContentConfiguration *content = cell.defaultContentConfiguration;
    content.textProperties.color = WQMTheme.textPrimaryColor;
    content.secondaryTextProperties.color = WQMTheme.textSecondaryColor;
    cell.backgroundColor = WQMTheme.surfaceColor;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    if (indexPath.section == 0 && indexPath.row == 0) {
        content.text = WQML(@"LANGUAGE", @"语言");
        content.secondaryText = _languageText;
        content.image = [UIImage systemImageNamed:@"globe"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 0 && indexPath.row == 1) {
        content.text = WQML(@"VERSION", @"版本");
        content.secondaryText = _versionText;
        content.image = [UIImage systemImageNamed:@"app.badge"];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (indexPath.section == 0 && indexPath.row == 2) {
        content.text = WQML(@"SETTINGS_CHECK_UPDATE", @"检测更新");
        content.secondaryText = [NSString stringWithFormat:
                                 WQML(@"SETTINGS_CHECK_UPDATE_SUB", @"当前 %@"), _versionText ?: @""];
        content.image = [UIImage systemImageNamed:@"arrow.triangle.2.circlepath"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 0 && indexPath.row == 3) {
        content.text = WQML(@"SIGNING_STATUS", @"签名状态");
        content.secondaryText = _signingText;
        content.image = [UIImage systemImageNamed:
                         _hasAppGroup ? @"checkmark.seal.fill" : @"exclamationmark.triangle.fill"];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (indexPath.section == 1 && indexPath.row == 0) {
        content.text = WQML(@"APP_INDEX", @"App 索引");
        content.secondaryText = _indexText;
        content.image = [UIImage systemImageNamed:@"bolt.horizontal.circle"];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (indexPath.section == 1 && indexPath.row == 1) {
        content.text = WQML(@"CLEAR_INDEX", @"清除 App 索引缓存");
        content.secondaryText = WQML(@"CLEAR_INDEX_SUB", @"下次打开应用时重新扫描");
        content.image = [UIImage systemImageNamed:@"arrow.clockwise.circle"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 1 && indexPath.row == 2) {
        content.text = WQML(@"OPERATION_RECORDS", @"操作记录");
        content.secondaryText = [NSString stringWithFormat:WQML(@"RECORD_COUNT", @"%lu 条"), (unsigned long)_operationCount];
        content.image = [UIImage systemImageNamed:@"clock.arrow.circlepath"];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (indexPath.section == 1 && indexPath.row == 3) {
        content.text = WQML(@"SETTINGS_CLEAN_CONFIRM", @"清理二次确认");
        content.secondaryText = WQML(@"SETTINGS_CLEAN_CONFIRM_SUB", @"清理前需要再次输入确认文字");
        content.image = [UIImage systemImageNamed:@"checkmark.shield"];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        UISwitch *toggle = [UISwitch new];
        toggle.onTintColor = UIColor.systemGreenColor;
        toggle.on = WQMCleanDoubleConfirmEnabled();
        toggle.accessibilityLabel = content.text;
        [toggle addTarget:self
                   action:@selector(cleanDoubleConfirmToggled:)
         forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
    } else if (indexPath.section == 1 && indexPath.row == 4) {
        content.text = WQML(@"SETTINGS_LOAD_PROFILE", @"备份与恢复负载");
        content.secondaryText = [NSString stringWithFormat:
                                 WQML(@"SETTINGS_LOAD_PROFILE_SUB", @"当前：%@"),
                                 WQMLoadProfileName(WQMLoadProfileCurrent())];
        content.image = [UIImage systemImageNamed:@"thermometer.medium"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 3 && indexPath.row == 0) {
        content.text = WQML(@"TELEGRAM_CHANNEL", @"Telegram 频道");
        content.secondaryText = WQML(@"TELEGRAM_CHANNEL_SUB", @"@TheBallnow · t.me/TheBallnow");
        content.image = [UIImage systemImageNamed:@"paperplane.fill"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 3) {
        content.text = @"GitHub";
        content.secondaryText = WQML(@"SETTINGS_GITHUB_SUBTITLE", @"给个 star 吧～");
        UIImage *star = [UIImage imageNamed:@"Star"];
        content.image = star ? [star imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal]
                             : [UIImage systemImageNamed:@"star.fill"];
        content.imageProperties.maximumSize = CGSizeMake(24, 24);
        content.imageProperties.reservedLayoutSize = CGSizeMake(24, 24);
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        NSArray<NSString *> *titles = @[
            WQML(@"DISCLAIMER", @"免责协议"),
            WQML(@"SAFETY", @"安全说明"),
            WQML(@"LICENSE", @"开源许可证"),
            WQML(@"THIRD_PARTY", @"第三方项目致谢")
        ];
        NSArray<NSString *> *symbols = @[@"exclamationmark.shield", @"lock.shield", @"doc.text", @"heart.text.square"];
        NSInteger row = indexPath.row;
        content.text = titles[(NSUInteger)row];
        content.secondaryText = nil;
        content.image = [UIImage systemImageNamed:symbols[(NSUInteger)row]];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    content.imageProperties.tintColor = WQMTheme.textPrimaryColor;
    cell.contentConfiguration = content;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0 && indexPath.row == 0) {
        [self showLanguageSelectorFromCell:[tableView cellForRowAtIndexPath:indexPath]];
        return;
    }
    if (indexPath.section == 0 && indexPath.row == 2) {
        [self checkForUpdatesFromCell:[tableView cellForRowAtIndexPath:indexPath]];
        return;
    }
    if (indexPath.section == 1 && indexPath.row == 3) {
        UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
        UISwitch *toggle = [cell.accessoryView isKindOfClass:UISwitch.class]
            ? (UISwitch *)cell.accessoryView : nil;
        [toggle setOn:!toggle.isOn animated:YES];
        [self cleanDoubleConfirmToggled:toggle];
        return;
    }
    if (indexPath.section == 1 && indexPath.row == 4) {
        [self showLoadProfileSelectorFromCell:[tableView cellForRowAtIndexPath:indexPath]];
        return;
    }
    if (indexPath.section == 1 && indexPath.row == 1) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:WQML(@"CLEAR_INDEX_TITLE", @"清除 App 索引？")
                                                                       message:WQML(@"CLEAR_INDEX_MESSAGE", @"只删除索引缓存，不会删除备份或 App 数据。")
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:WQML(@"CANCEL", @"取消") style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:WQML(@"CLEAR", @"清除") style:UIAlertActionStyleDestructive
                                                handler:^(__unused UIAlertAction *action) {
            [WQMAppCache clear];
            [WQMAppIconService clearCache];
            [self reloadState];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    if (indexPath.section == 3 && indexPath.row == 0) {
        NSURL *url = [NSURL URLWithString:WQM_TELEGRAM_CHANNEL_URL];
        if (url) [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        return;
    }
    if (indexPath.section == 3) {
        NSURL *url = [NSURL URLWithString:WQM_REPOSITORY_URL];
        if (url) [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        return;
    }
    if (indexPath.section != 2) return;

    if (indexPath.row == 3) {
        [self.navigationController pushViewController:[WQMCreditsViewController new] animated:YES];
        return;
    }

    NSArray<NSString *> *titles = @[
        WQML(@"DISCLAIMER", @"免责协议"),
        WQML(@"SAFETY", @"安全说明"),
        @"GNU GPL v3",
        WQML(@"THIRD_PARTY", @"第三方项目致谢")
    ];
    NSArray<NSString *> *files = @[@"DISCLAIMER", @"SAFETY", @"LICENSE", @"THIRD_PARTY_NOTICES"];
    BOOL english = [[WQMLanguageManager sharedManager].languageCode isEqualToString:[WQMLanguageManager english]];
    NSString *resource = files[(NSUInteger)indexPath.row];
    if (!english && indexPath.row != 2) resource = [resource stringByAppendingString:@"_zh-Hans"];
    NSString *path = [NSBundle.mainBundle pathForResource:resource ofType:@"md"];
    NSString *text = path ? [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] : nil;
    if (!text.length && indexPath.row == 0) text = [WQMConsentStore disclaimerText];
    if (!text.length) text = WQML(@"DOC_NOT_FOUND", @"文档资源未找到。");
    WQMTextDocumentViewController *controller = [WQMTextDocumentViewController new];
    controller.documentTitle = titles[(NSUInteger)indexPath.row];
    controller.documentText = text;
    controller.reflowPlainText = indexPath.row == 2;
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)checkForUpdatesFromCell:(UITableViewCell *)cell
{
    if (_checkingUpdate) return;
    _checkingUpdate = YES;
    if (cell) {
        UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc]
            initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        spinner.color = WQMTheme.textSecondaryColor;
        [spinner startAnimating];
        cell.accessoryView = spinner;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:
        [NSURL URLWithString:[WQM_REPOSITORY_RELEASES_URL stringByAppendingString:@"/latest"]]];
    request.timeoutInterval = 12;
    [request setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) WQManager"
   forHTTPHeaderField:@"User-Agent"];
    __weak typeof(self) weakSelf = self;
    [[NSURLSession.sharedSession dataTaskWithRequest:request
        completionHandler:^(__unused NSData *data, NSURLResponse *response, NSError *error) {
        NSString *tag = nil;
        NSString *page = nil;
        if (!error) {
            NSURL *finalURL = response.URL;
            NSString *path = finalURL.path ?: @"";
            NSRange marker = [path rangeOfString:@"/releases/tag/"];
            if (marker.location != NSNotFound) {
                tag = [path substringFromIndex:NSMaxRange(marker)];
                page = finalURL.absoluteString;
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            WQMSettingsViewController *strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf->_checkingUpdate = NO;
            UITableViewCell *row = [strongSelf.tableView
                cellForRowAtIndexPath:[NSIndexPath indexPathForRow:WQMSettingsRowCheckUpdate inSection:0]];
            row.accessoryView = nil;
            row.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            if (!tag.length) {
                [strongSelf showUpdateAlertWithTitle:WQML(@"UPDATE_FAILED_TITLE", @"检测失败")
                                             message:WQML(@"UPDATE_FAILED_MESSAGE",
                                                          @"无法连接 GitHub，请稍后重试。")
                                                 url:nil];
                return;
            }
            if ([strongSelf versionTag:tag isNewerThan:strongSelf->_versionText]) {
                [strongSelf showUpdateAlertWithTitle:
                    [NSString stringWithFormat:WQML(@"UPDATE_AVAILABLE_TITLE", @"发现新版本 %@"), tag]
                                             message:[NSString stringWithFormat:
                                                      WQML(@"UPDATE_AVAILABLE_MESSAGE",
                                                           @"当前 %@，是否前往 GitHub 查看？"),
                                                      strongSelf->_versionText]
                                                 url:page ?: WQM_REPOSITORY_RELEASES_URL];
            } else {
                [strongSelf showUpdateAlertWithTitle:WQML(@"UPDATE_UP_TO_DATE_TITLE", @"已是最新版本")
                                             message:[NSString stringWithFormat:
                                                      WQML(@"UPDATE_UP_TO_DATE_MESSAGE",
                                                           @"当前 %@ 已是最新版本。"),
                                                      strongSelf->_versionText]
                                                 url:nil];
            }
        });
    }] resume];
}

- (BOOL)versionTag:(NSString *)tag isNewerThan:(NSString *)current
{
    NSString *clean = [tag hasPrefix:@"v"] ? [tag substringFromIndex:1] : tag;
    clean = [[clean componentsSeparatedByCharactersInSet:
              [NSCharacterSet characterSetWithCharactersInString:@" -+"]].firstObject
             stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    NSString *currentClean = [[current componentsSeparatedByString:@" "].firstObject
                              stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    NSArray<NSString *> *newParts = [clean componentsSeparatedByString:@"."];
    NSArray<NSString *> *oldParts = [currentClean componentsSeparatedByString:@"."];
    NSUInteger count = MAX(newParts.count, oldParts.count);
    for (NSUInteger index = 0; index < count; index++) {
        NSInteger newValue = index < newParts.count ? newParts[index].integerValue : 0;
        NSInteger oldValue = index < oldParts.count ? oldParts[index].integerValue : 0;
        if (newValue != oldValue) return newValue > oldValue;
    }
    return NO;
}

- (void)showUpdateAlertWithTitle:(NSString *)title message:(NSString *)message url:(NSString *)urlString
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:WQML(@"CANCEL", @"取消")
                                              style:UIAlertActionStyleCancel handler:nil]];
    if (urlString.length) {
        [alert addAction:[UIAlertAction actionWithTitle:WQML(@"UPDATE_OPEN", @"前往查看")
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction *action) {
            NSURL *url = [NSURL URLWithString:urlString];
            if (url) [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        }]];
    }
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showLoadProfileSelectorFromCell:(UITableViewCell *)cell
{
    WQMLoadProfile current = WQMLoadProfileCurrent();
    UIAlertController *sheet = [UIAlertController
        alertControllerWithTitle:WQML(@"LOAD_PROFILE_TITLE", @"备份与恢复负载")
                         message:WQML(@"LOAD_PROFILE_FOOTER",
                                      @"低负载模式会更慢，但能降低备份和恢复时的发热。"
                                       "安全备份、SHA-256 校验、恢复日志和回滚始终保留。")
                  preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray<NSNumber *> *profiles = @[@(WQMLoadProfileAutomatic),
                                      @(WQMLoadProfileLowLoad),
                                      @(WQMLoadProfileStandard)];
    for (NSNumber *number in profiles) {
        WQMLoadProfile profile = number.integerValue;
        NSString *title = [NSString stringWithFormat:@"%@%@",
                           profile == current ? @"✓ " : @"",
                           WQMLoadProfileName(profile)];
        [sheet addAction:[UIAlertAction actionWithTitle:title
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction *action) {
            WQMLoadProfileSetCurrent(profile);
            [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:4 inSection:1]]
                                  withRowAnimation:UITableViewRowAnimationNone];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:WQML(@"CANCEL", @"取消")
                                              style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = cell ?: self.tableView;
    sheet.popoverPresentationController.sourceRect = cell ? cell.bounds : CGRectZero;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)cleanDoubleConfirmToggled:(UISwitch *)sender
{
    if (!sender) return;
    WQMCleanDoubleConfirmSetEnabled(sender.isOn);
}

- (void)showLanguageSelectorFromCell:(UITableViewCell *)cell
{
    UIAlertController *sheet = [UIAlertController
        alertControllerWithTitle:WQML(@"LANGUAGE", @"语言")
                         message:nil
                  preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:WQML(@"LANGUAGE_ZH", @"简体中文")
                                             style:UIAlertActionStyleDefault
                                           handler:^(__unused UIAlertAction *action) {
        [[WQMLanguageManager sharedManager] setLanguageCode:[WQMLanguageManager simplifiedChinese]];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:WQML(@"LANGUAGE_EN", @"English")
                                             style:UIAlertActionStyleDefault
                                           handler:^(__unused UIAlertAction *action) {
        [[WQMLanguageManager sharedManager] setLanguageCode:[WQMLanguageManager english]];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:WQML(@"CANCEL", @"取消")
                                             style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = cell;
    sheet.popoverPresentationController.sourceRect = cell.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

@end

