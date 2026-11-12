#import "WQMBackupsViewController.h"
#import "WQMBackupArchiveService.h"
#import "WQMBackupStore.h"
#import "WQMLongOperationBanner.h"
#import "WQMAlertPresenter.h"
#import "WQMLanguageManager.h"
#import "WQMRestoreService.h"
#import "WQMSafetyPolicy.h"
#import "WQMTheme.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static NSString *WQMBackupReasonText(NSString *reason)
{
    if ([reason isEqualToString:@"恢复前自动安全备份"] ||
        [reason isEqualToString:@"Automatic safety backup before restore"]) {
        return WQML(@"RESTORE_SAFETY_REASON", @"恢复前自动安全备份");
    }
    return reason;
}

@interface WQMBackupsSummaryView : UIView
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, strong) UILabel *detailLabel;
- (void)setBackups:(NSArray<WQMBackupRecord *> *)backups;
@end

@implementation WQMBackupsSummaryView {
    WQMSoftSurfaceView *_card;
    BOOL _playedEntrance;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        _card = [[WQMSoftSurfaceView alloc] initWithElevated:YES];
        _card.translatesAutoresizingMaskIntoConstraints = NO;

        UILabel *caption = [UILabel new];
        caption.text = WQML(@"LOCAL_BACKUPS", @"本地备份");
        caption.font = [WQMTheme sectionTitleFont];
        caption.textColor = WQMTheme.textSecondaryColor;

        _valueLabel = [UILabel new];
        _valueLabel.text = @"0";
        _valueLabel.font = [WQMTheme displayNumberFont];
        _valueLabel.textColor = WQMTheme.textPrimaryColor;
        _valueLabel.adjustsFontForContentSizeCategory = YES;

        _detailLabel = [UILabel new];
        _detailLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
        _detailLabel.textColor = WQMTheme.textSecondaryColor;
        _detailLabel.numberOfLines = 2;

        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[caption, _valueLabel, _detailLabel]];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 6;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [stack setCustomSpacing:3 afterView:caption];
        [_card addSubview:stack];
        [self addSubview:_card];

        NSLayoutConstraint *headerFill = [_card.widthAnchor constraintEqualToAnchor:self.widthAnchor constant:-24];
        headerFill.priority = 999;
        [NSLayoutConstraint activateConstraints:@[
            [stack.topAnchor constraintEqualToAnchor:_card.topAnchor constant:19],
            [stack.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:20],
            [stack.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-20],
            [stack.bottomAnchor constraintEqualToAnchor:_card.bottomAnchor constant:-17],
            [_card.topAnchor constraintEqualToAnchor:self.topAnchor constant:8],
            [_card.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_card.widthAnchor constraintLessThanOrEqualToConstant:760],
            headerFill,
            [_card.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-8],
        ]];
    }
    return self;
}

- (void)setBackups:(NSArray<WQMBackupRecord *> *)backups
{
    unsigned long long total = 0;
    for (WQMBackupRecord *backup in backups) total += backup.totalBytes;
    [WQMTheme animateLabelChange:self.valueLabel update:^{
        self.valueLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)backups.count];
    }];
    NSString *size = WQMFormatBytes(total);
    [WQMTheme animateLabelChange:self.detailLabel update:^{
        if (!backups.count) {
            self.detailLabel.text = WQML(@"BACKUPS_EMPTY_DETAIL",
                                         @"还没有备份。可在“应用”页面选择 App 创建。");
        } else if (total == 0) {
            self.detailLabel.text = WQML(@"BACKUPS_LEGACY_SIZE",
                                         @"清单完整 · 旧备份体积待统计");
        } else {
            self.detailLabel.text = [NSString stringWithFormat:
                                     WQML(@"BACKUPS_VALIDATED_DETAIL", @"%@ · 清单完整且已校验"), size];
        }
    }];
    if (!_playedEntrance) {
        _playedEntrance = YES;
        [WQMTheme animateEntrance:_card delay:0.02];
    }
}

@end

@interface WQMBackupCardCell : UITableViewCell
@property (nonatomic, strong) WQMSoftSurfaceView *cardView;
@property (nonatomic, strong) UIListContentView *listContentView;
- (void)configureWithBackup:(WQMBackupRecord *)backup;
- (void)configureEmpty;
- (void)playEntranceWithDelay:(NSTimeInterval)delay;
@end

@implementation WQMBackupCardCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.clipsToBounds = NO;
        self.contentView.clipsToBounds = NO;
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _cardView = [[WQMSoftSurfaceView alloc] initWithElevated:NO];
        _cardView.layer.cornerRadius = 22;
        _cardView.translatesAutoresizingMaskIntoConstraints = NO;

        UIListContentConfiguration *configuration = [UIListContentConfiguration subtitleCellConfiguration];
        configuration.image = [UIImage systemImageNamed:@"externaldrive.fill"];
        configuration.imageProperties.maximumSize = CGSizeMake(46, 46);
        configuration.imageProperties.reservedLayoutSize = CGSizeMake(46, 46);
        configuration.imageProperties.cornerRadius = 14;
        configuration.imageProperties.tintColor = WQMTheme.textPrimaryColor;
        _listContentView = [[UIListContentView alloc] initWithConfiguration:configuration];
        _listContentView.translatesAutoresizingMaskIntoConstraints = NO;
        [_cardView addSubview:_listContentView];
        [self.contentView addSubview:_cardView];
        NSLayoutConstraint *cardFill = [_cardView.widthAnchor constraintEqualToAnchor:self.contentView.widthAnchor
                                                                             constant:-24];
        cardFill.priority = 999;
        [NSLayoutConstraint activateConstraints:@[
            [_cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:5],
            [_cardView.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
            [_cardView.widthAnchor constraintLessThanOrEqualToConstant:760],
            cardFill,
            [_cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-5],
            [_listContentView.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:10],
            [_listContentView.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:14],
            [_listContentView.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-14],
            [_listContentView.bottomAnchor constraintEqualToAnchor:_cardView.bottomAnchor constant:-10],
            [_cardView.heightAnchor constraintGreaterThanOrEqualToConstant:70],
        ]];
    }
    return self;
}

- (void)configureWithBackup:(WQMBackupRecord *)backup
{
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [WQMLanguageManager sharedManager].locale;
    formatter.dateStyle = NSDateFormatterMediumStyle;
    formatter.timeStyle = NSDateFormatterShortStyle;
    UIListContentConfiguration *configuration = (UIListContentConfiguration *)self.listContentView.configuration;
    configuration.text = backup.displayName;
    NSString *sizeText = backup.totalBytes
        ? WQMFormatBytes(backup.totalBytes)
        : WQML(@"BACKUP_SIZE_PENDING", @"大小待统计");
    NSString *reason = WQMBackupReasonText(backup.reason);
    configuration.secondaryText = [NSString stringWithFormat:@"%@%@ · %@ · %@",
                                   backup.scopeName,
                                   reason.length ? [NSString stringWithFormat:@" · %@", reason] : @"",
                                   [formatter stringFromDate:backup.createdAt],
                                   sizeText];
    configuration.textProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    configuration.textProperties.color = WQMTheme.textPrimaryColor;
    configuration.secondaryTextProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    configuration.secondaryTextProperties.color = WQMTheme.textSecondaryColor;
    self.listContentView.configuration = configuration;
    self.accessibilityLabel = [NSString stringWithFormat:@"%@，%@，%@",
                               backup.displayName, configuration.secondaryText, configuration.text];
}

- (void)configureEmpty
{
    UIListContentConfiguration *configuration = (UIListContentConfiguration *)self.listContentView.configuration;
    configuration.text = WQML(@"BACKUPS_EMPTY_TITLE", @"还没有备份");
    configuration.secondaryText = WQML(@"BACKUPS_EMPTY_HINT",
                                       @"在“应用”页面选择一个 App 开始备份。");
    configuration.textProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    configuration.textProperties.color = WQMTheme.textPrimaryColor;
    configuration.secondaryTextProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    configuration.secondaryTextProperties.color = WQMTheme.textSecondaryColor;
    configuration.image = [UIImage systemImageNamed:@"externaldrive.badge.xmark"];
    self.listContentView.configuration = configuration;
    self.accessibilityLabel = WQML(@"BACKUPS_EMPTY_TITLE", @"还没有备份");
}

- (void)playEntranceWithDelay:(NSTimeInterval)delay
{
    [WQMTheme animateEntrance:self.cardView delay:delay];
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated
{
    [super setHighlighted:highlighted animated:animated];
    [WQMTheme animatePress:self.cardView pressed:highlighted];
}

@end

@implementation WQMBackupsViewController {
    NSArray<WQMBackupRecord *> *_backups;
    WQMConfirmationGate *_recoveryGate;
    BOOL _recoveryPrompted;
    WQMBackupsSummaryView *_summaryView;
    NSMutableSet<NSString *> *_animatedBackups;
    NSUInteger _reloadGeneration;
    WQMBackupArchiveService *_archiveService;
    WQMConfirmationGate *_deleteGate;
    NSURL *_temporaryExportURL;
    BOOL _importing;
}

- (instancetype)init
{
    return [super initWithStyle:UITableViewStylePlain];
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = WQML(@"TAB_BACKUPS", @"备份");
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.tableView.accessibilityIdentifier = @"backups.table";
    self.tableView.backgroundColor = WQMTheme.canvasColor;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 90;
    self.tableView.cellLayoutMarginsFollowReadableWidth = YES;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    _animatedBackups = [NSMutableSet new];
    _archiveService = [WQMBackupArchiveService new];
    _summaryView = [[WQMBackupsSummaryView alloc] initWithFrame:
                    CGRectMake(0, 0, self.tableView.bounds.size.width, 138)];
    self.tableView.tableHeaderView = _summaryView;
    self.refreshControl = [UIRefreshControl new];
    [self.refreshControl addTarget:self action:@selector(reloadBackups) forControlEvents:UIControlEventValueChanged];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(reloadBackups)
                                               name:WQMBackupStoreDidChangeNotification
                                             object:nil];
    [self reloadBackups];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self reloadBackups];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    if (!_recoveryPrompted && [WQMRestoreService activeRecoverySummary]) {
        _recoveryPrompted = YES;
        [self showRecoveryConfirmation];
    }
}

- (void)reloadBackups
{
    NSUInteger generation = ++_reloadGeneration;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<WQMBackupRecord *> *backups = [WQMBackupStore allBackups];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self->_reloadGeneration) return;
            self->_backups = backups;
            [self->_animatedBackups removeAllObjects];
            [self->_summaryView setBackups:backups];
            NSString *recovery = [WQMRestoreService activeRecoverySummary];
            self.navigationItem.rightBarButtonItem = recovery
                ? [[UIBarButtonItem alloc] initWithTitle:WQML(@"RECOVERY_ACTION", @"修复中断")
                                                  style:UIBarButtonItemStylePlain
                                                 target:self
                                                 action:@selector(showRecoveryConfirmation)]
                : nil;
            self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
                initWithImage:[UIImage systemImageNamed:@"square.and.arrow.down"]
                        style:UIBarButtonItemStylePlain
                       target:self
                       action:@selector(importBackup)];
            [self.refreshControl endRefreshing];
            [self.tableView reloadData];
        });
    });
}

- (void)importBackup
{
    UTType *type = [UTType typeWithIdentifier:[WQMBackupArchiveService backupContentTypeIdentifier]];
    if (!type) type = UTTypeFolder;
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[type] asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)presentImportPicker
{
    [self loadViewIfNeeded];
    if (self.presentedViewController) {
        [self dismissViewControllerAnimated:NO completion:^{ [self importBackup]; }];
    } else {
        [self importBackup];
    }
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
 didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
    NSURL *url = urls.firstObject;
    if (!url) return;
    [self importBackupAtURL:url];
}

- (void)importBackupAtURL:(NSURL *)url
{
    if (!url.isFileURL || _importing) return;
    [self loadViewIfNeeded];
    _importing = YES;
    void (^startImport)(void) = ^{
        if (![WQMLongOperationBanner startOperationWithTitle:WQML(@"IMPORT_PROGRESS_TITLE", @"正在导入")
                                                      status:WQML(@"IMPORT_VERIFYING", @"校验备份包…")
                                               cancelHandler:nil]) {
            self->_importing = NO;
            return;
        }
        WQMLongOperationBanner *banner = WQMLongOperationBanner.shared;
        [self->_archiveService importBackupAtURL:url completion:^(WQMBackupRecord *backup, NSError *error) {
            self->_importing = NO;
            [banner hideWithCompletion:^{
                [self reloadBackups];
                UIAlertController *result = [UIAlertController
                    alertControllerWithTitle:error
                        ? WQML(@"IMPORT_FAILED_TITLE", @"导入失败")
                        : WQML(@"IMPORT_COMPLETE_TITLE", @"导入完成")
                                     message:error ? error.localizedDescription
                                                   : [NSString stringWithFormat:@"%@ · %@",
                                                      backup.displayName, backup.scopeName]
                              preferredStyle:UIAlertControllerStyleAlert];
                [result addAction:[UIAlertAction actionWithTitle:WQML(@"OK", @"确定")
                                                           style:UIAlertActionStyleDefault handler:nil]];
                [WQMAlertPresenter presentViewController:result animated:YES completion:nil];
            }];
        }];
    };
    if (self.presentedViewController) {
        [self dismissViewControllerAnimated:NO completion:startImport];
    } else {
        startImport();
    }
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
}

- (void)showRecoveryConfirmation
{
    NSString *summary = [WQMRestoreService activeRecoverySummary];
    if (!summary) return;
    _recoveryGate = [WQMConfirmationGate new];
    NSString *operation = [@"recover:" stringByAppendingString:NSUUID.UUID.UUIDString];
    if (![_recoveryGate beginForOperation:operation]) return;

    UIAlertController *scope = [UIAlertController
        alertControllerWithTitle:WQML(@"RECOVERY_FOUND_TITLE", @"发现中断的恢复")
                         message:[NSString stringWithFormat:
                                  WQML(@"RECOVERY_FOUND_MESSAGE",
                                       @"%@ 上次恢复没有正常完成。\n\n"
                                        "可尝试用自动安全备份回滚目标数据。请先关闭目标 App。"),
                                  summary]
                  preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [scope addAction:[UIAlertAction actionWithTitle:WQML(@"RECOVERY_LATER", @"稍后处理") style:UIAlertActionStyleCancel
                                            handler:^(__unused UIAlertAction *a) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        [self->_recoveryGate cancel];
    }]];
    [scope addAction:[UIAlertAction actionWithTitle:WQML(@"RECOVERY_CONTINUE", @"继续修复") style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *a) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || ![self->_recoveryGate acknowledgeScopeForOperation:operation]) return;
        [self showFinalRecoveryConfirmation:operation];
    }]];
    [self presentViewController:scope animated:YES completion:nil];
}

- (void)showFinalRecoveryConfirmation:(NSString *)operation
{
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:WQML(@"RECOVERY_FINAL_TITLE", @"最终确认：回滚中断恢复")
                         message:WQML(@"RECOVERY_FINAL_MESSAGE",
                                      @"第二次确认。执行后会再次清空目标目录，并从恢复前自动安全备份复制数据。")
                  preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:WQML(@"CANCEL", @"取消") style:UIAlertActionStyleCancel
                                            handler:^(__unused UIAlertAction *a) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        [self->_recoveryGate cancel];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:WQML(@"RECOVERY_EXECUTE", @"执行回滚")
                                             style:UIAlertActionStyleDestructive
                                           handler:^(__unused UIAlertAction *a) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || ![self->_recoveryGate authorizeExecutionForOperation:operation]) return;
        [self runRecovery];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)runRecovery
{
    if (![WQMLongOperationBanner startOperationWithTitle:WQML(@"RECOVERY_PROGRESS_TITLE", @"正在修复")
                                                  status:WQML(@"PREPARING", @"准备中…")
                                           cancelHandler:nil]) return;
    WQMLongOperationBanner *banner = WQMLongOperationBanner.shared;
    [WQMRestoreService recoverActiveRecoveryWithProgress:^(NSString *status) {
        [banner updateStatus:status];
    } completion:^(BOOL success, NSString *message, NSError *error) {
        [banner hideWithCompletion:^{
            self->_recoveryPrompted = YES;
            [self reloadBackups];
            UIAlertController *result = [UIAlertController
                alertControllerWithTitle:success
                    ? WQML(@"RECOVERY_COMPLETE_TITLE", @"修复完成")
                    : WQML(@"RECOVERY_INCOMPLETE_TITLE", @"修复未完成")
                                 message:message ?: error.localizedDescription
                          preferredStyle:UIAlertControllerStyleAlert];
            [result addAction:[UIAlertAction actionWithTitle:WQML(@"OK", @"确定")
                                                       style:UIAlertActionStyleDefault handler:nil]];
            [WQMAlertPresenter presentViewController:result animated:YES completion:nil];
        }];
    }];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return MAX((NSInteger)_backups.count, 1);
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (_backups.count) {
        return [NSString stringWithFormat:WQML(@"BACKUP_COUNT", @"%lu 个有效备份"),
                (unsigned long)_backups.count];
    }
    return WQML(@"BACKUP_BOX", @"备份箱");
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    WQMBackupCardCell *cell = [tableView dequeueReusableCellWithIdentifier:@"backup"];
    if (!cell) {
        cell = [[WQMBackupCardCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"backup"];
    }
    if (!_backups.count) {
        [cell configureEmpty];
        return cell;
    }

    WQMBackupRecord *backup = _backups[(NSUInteger)indexPath.row];
    [cell configureWithBackup:backup];
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (![cell isKindOfClass:WQMBackupCardCell.class] || indexPath.row >= (NSInteger)_backups.count) return;
    WQMBackupRecord *backup = _backups[(NSUInteger)indexPath.row];
    if ([_animatedBackups containsObject:backup.path]) return;
    [_animatedBackups addObject:backup.path];
    [(WQMBackupCardCell *)cell playEntranceWithDelay:MIN(indexPath.row, 6) * 0.03];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row >= (NSInteger)_backups.count) return;
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [feedback impactOccurred];
    WQMBackupRecord *backup = _backups[(NSUInteger)indexPath.row];
    UIAlertController *sheet = [UIAlertController
        alertControllerWithTitle:backup.displayName
                         message:[NSString stringWithFormat:@"%@ · %@",
                                  backup.scopeName,
                                  WQMFormatBytes(backup.totalBytes)]
                  preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:WQML(@"EXPORT_BACKUP", @"导出备份包") style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        [self exportBackup:backup];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:WQML(@"VIEW_DETAILS", @"查看详情") style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        [self showDetailsForBackup:backup];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:WQML(@"DELETE_BACKUP", @"删除备份") style:UIAlertActionStyleDestructive
                                            handler:^(__unused UIAlertAction *action) {
        [self confirmDeleteBackup:backup];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:WQML(@"CANCEL", @"取消") style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = tableView;
    sheet.popoverPresentationController.sourceRect = [tableView rectForRowAtIndexPath:indexPath];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)showDetailsForBackup:(WQMBackupRecord *)backup
{
    NSString *reason = WQMBackupReasonText(backup.reason);
    NSString *message = [NSString stringWithFormat:
                         WQML(@"BACKUP_DETAILS_MESSAGE",
                              @"Bundle ID: %@\n范围: %@\n原因: %@\n目录: %@\n系统: %@\n\n%@"),
                         backup.bundleIdentifier,
                         backup.scopeName,
                         reason.length ? reason : WQML(@"BACKUP_REASON_USER", @"用户备份"),
                         [backup.parts componentsJoinedByString:@", "],
                         backup.systemVersion,
                         backup.path];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:WQML(@"BACKUP_DETAILS_TITLE", @"备份详情")
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:WQML(@"COPY_PATH", @"复制路径") style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        UIPasteboard.generalPasteboard.string = backup.path;
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:WQML(@"CLOSE", @"关闭") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)exportBackup:(WQMBackupRecord *)backup
{
    if (![WQMLongOperationBanner startOperationWithTitle:WQML(@"EXPORT_PROGRESS_TITLE", @"正在准备导出")
                                                  status:WQML(@"EXPORT_PROGRESS_MESSAGE", @"校验并复制备份包…")
                                           cancelHandler:nil]) return;
    WQMLongOperationBanner *banner = WQMLongOperationBanner.shared;
    [_archiveService prepareExportForBackup:backup completion:^(NSURL *exportURL, NSError *error) {
        [banner hideWithCompletion:^{
            if (!exportURL) {
                UIAlertController *alert = [UIAlertController
                    alertControllerWithTitle:WQML(@"EXPORT_FAILED_TITLE", @"导出失败")
                                     message:error.localizedDescription
                              preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:WQML(@"OK", @"确定") style:UIAlertActionStyleDefault handler:nil]];
                [WQMAlertPresenter presentViewController:alert animated:YES completion:nil];
                return;
            }
            self->_temporaryExportURL = exportURL;
            UIActivityViewController *share = [[UIActivityViewController alloc]
                initWithActivityItems:@[exportURL] applicationActivities:nil];
            share.popoverPresentationController.sourceView = self.view;
            share.popoverPresentationController.sourceRect = self.view.bounds;
            __weak typeof(self) weakSelf = self;
            share.completionWithItemsHandler = ^(UIActivityType __unused type, BOOL __unused completed,
                                                 NSArray *__unused items, NSError *__unused activityError) {
                [[NSFileManager defaultManager] removeItemAtURL:exportURL.URLByDeletingLastPathComponent error:nil];
                __strong typeof(weakSelf) self = weakSelf;
                self->_temporaryExportURL = nil;
            };
            [WQMAlertPresenter presentViewController:share animated:YES completion:nil];
        }];
    }];
}

- (void)confirmDeleteBackup:(WQMBackupRecord *)backup
{
    _deleteGate = [WQMConfirmationGate new];
    NSString *operation = [@"delete-backup:" stringByAppendingString:backup.path];
    if (![_deleteGate beginForOperation:operation]) return;
    UIAlertController *scope = [UIAlertController
        alertControllerWithTitle:WQML(@"DELETE_BACKUP", @"删除备份")
                         message:[NSString stringWithFormat:
                                  WQML(@"DELETE_BACKUP_MESSAGE",
                                       @"将永久删除 %@ 的 %@ 备份。\n\n删除后无法恢复。"),
                                  backup.displayName, backup.scopeName]
                  preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [scope addAction:[UIAlertAction actionWithTitle:WQML(@"CANCEL", @"取消") style:UIAlertActionStyleCancel
                                            handler:^(__unused UIAlertAction *action) {
        __strong typeof(weakSelf) self = weakSelf;
        [self->_deleteGate cancel];
    }]];
    [scope addAction:[UIAlertAction actionWithTitle:WQML(@"CONTINUE", @"继续") style:UIAlertActionStyleDestructive
                                            handler:^(__unused UIAlertAction *action) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || ![self->_deleteGate acknowledgeScopeForOperation:operation]) return;
        UIAlertController *final = [UIAlertController
            alertControllerWithTitle:WQML(@"DELETE_BACKUP_FINAL_TITLE", @"最终确认：删除备份")
                             message:WQML(@"DELETE_BACKUP_FINAL_MESSAGE",
                                          @"这是第二次确认。备份内容删除后无法恢复。")
                      preferredStyle:UIAlertControllerStyleAlert];
        [final addAction:[UIAlertAction actionWithTitle:WQML(@"CANCEL", @"取消") style:UIAlertActionStyleCancel
                                                handler:^(__unused UIAlertAction *a) {
            [self->_deleteGate cancel];
        }]];
        [final addAction:[UIAlertAction actionWithTitle:WQML(@"DELETE_PERMANENTLY", @"永久删除") style:UIAlertActionStyleDestructive
                                                handler:^(__unused UIAlertAction *a) {
            if (![self->_deleteGate authorizeExecutionForOperation:operation]) return;
            if (![WQMLongOperationBanner startOperationWithTitle:WQML(@"DELETE_PROGRESS_TITLE", @"正在删除")
                                                          status:nil
                                                   cancelHandler:nil]) return;
            [self->_archiveService deleteBackup:backup completion:^(BOOL success, NSError *error) {
                [WQMLongOperationBanner.shared hideWithCompletion:^{
                    [self reloadBackups];
                    UIAlertController *result = [UIAlertController
                        alertControllerWithTitle:success
                            ? WQML(@"DELETED_TITLE", @"已删除")
                            : WQML(@"DELETE_FAILED_TITLE", @"删除失败")
                                         message:error.localizedDescription
                                  preferredStyle:UIAlertControllerStyleAlert];
                    [result addAction:[UIAlertAction actionWithTitle:WQML(@"OK", @"确定")
                                                               style:UIAlertActionStyleDefault handler:nil]];
                    [WQMAlertPresenter presentViewController:result animated:YES completion:nil];
                }];
            }];
        }]];
        [self presentViewController:final animated:YES completion:nil];
    }]];
    [self presentViewController:scope animated:YES completion:nil];
}

@end
