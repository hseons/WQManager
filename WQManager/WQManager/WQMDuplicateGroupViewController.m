#import "WQMDuplicateGroupViewController.h"
#import "WQMAppModel.h"
#import "WQMAlertPresenter.h"
#import "WQMFileAudit.h"
#import "WQMFileCatalog.h"
#import "WQMLanguageManager.h"
#import "WQMLongOperationBanner.h"
#import "WQMOperationStore.h"
#import "WQMTheme.h"
#import "WQMTrashStore.h"
#import "WQAccess.h"
#import "WQAccessSafety.h"
#import "WQAppsSupport.h"
#import "WQMContainerAccess.h"

@implementation WQMDuplicateGroupViewController {
    NSArray<WQMAuditFile *> *_candidates;
    NSDictionary<NSString *, WQMAppModel *> *_apps;
    NSArray<NSArray<WQMAuditFile *> *> *_confirmedGroups;
    NSMutableSet<NSString *> *_selectedKeys;
    WQMFileCatalogCancellation *_cancellation;
    UILabel *_statusLabel;
    UILabel *_selectionLabel;
    UIButton *_trashButton;
    void (^_completion)(void);
    BOOL _verified, _verifying, _started;
    NSUInteger _generation;
}

- (instancetype)initWithFiles:(NSArray<WQMAuditFile *> *)files
                         apps:(NSArray<WQMAppModel *> *)apps
                   completion:(void (^)(void))completion
{
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _candidates = [files copy];
        NSMutableDictionary *byBundle = [NSMutableDictionary new];
        for (WQMAppModel *app in apps) if (app.bundleIdentifier.length) byBundle[app.bundleIdentifier] = app;
        _apps = byBundle;
        _completion = [completion copy];
        _selectedKeys = [NSMutableSet new];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = WQML(@"DUPLICATE_TITLE", @"重复文件");
    self.tableView.backgroundColor = WQMTheme.canvasColor;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 78;
    self.tableView.accessibilityIdentifier = @"duplicate.table";
    [self configureHeader];
    [self configureActionBar];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    if (!_started) {
        _started = YES;
        [self verifyContents];
    }
}

- (void)dealloc
{
    [_cancellation cancel];
}

- (void)configureHeader
{
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 72)];
    _statusLabel = [UILabel new];
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _statusLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    _statusLabel.textColor = WQMTheme.textSecondaryColor;
    _statusLabel.numberOfLines = 0;
    _statusLabel.text = [NSString stringWithFormat:WQML(@"DUPLICATE_CANDIDATE_SUMMARY", @"%lu 个文件大小相同，正在准备内容校验。"),
                         (unsigned long)_candidates.count];
    [header addSubview:_statusLabel];
    [NSLayoutConstraint activateConstraints:@[
        [_statusLabel.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:4],
        [_statusLabel.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-4],
        [_statusLabel.topAnchor constraintEqualToAnchor:header.topAnchor constant:6],
    ]];
    self.tableView.tableHeaderView = header;
}

- (void)configureActionBar
{
    UIView *bar = [UIView new];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    bar.backgroundColor = WQMTheme.surfaceColor;
    bar.layer.cornerRadius = WQMTheme.largeRadius;
    bar.layer.cornerCurve = kCACornerCurveContinuous;
    bar.layer.masksToBounds = YES;
    [self.view addSubview:bar];

    _selectionLabel = [UILabel new];
    _selectionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _selectionLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    _selectionLabel.textColor = WQMTheme.textSecondaryColor;
    _selectionLabel.text = WQML(@"DUPLICATE_SELECT_HINT", @"选择要移入回收站的文件");
    _selectionLabel.accessibilityIdentifier = @"duplicate.selection";

    _trashButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _trashButton.translatesAutoresizingMaskIntoConstraints = NO;
    UIButtonConfiguration *configuration = [UIButtonConfiguration filledButtonConfiguration];
    configuration.title = WQML(@"DUPLICATE_TRASH_ACTION", @"移入回收站");
    configuration.baseBackgroundColor = WQMTheme.dangerColor;
    configuration.baseForegroundColor = UIColor.whiteColor;
    configuration.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    _trashButton.configuration = configuration;
    _trashButton.accessibilityIdentifier = @"duplicate.trash";
    _trashButton.enabled = NO;
    [_trashButton addTarget:self action:@selector(confirmTrash) forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:_selectionLabel];
    [bar addSubview:_trashButton];
    [NSLayoutConstraint activateConstraints:@[
        [bar.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:18],
        [bar.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-18],
        [bar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-8],
        [bar.heightAnchor constraintGreaterThanOrEqualToConstant:62],
        [_selectionLabel.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:16],
        [_selectionLabel.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [_selectionLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_trashButton.leadingAnchor constant:-12],
        [_trashButton.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-12],
        [_trashButton.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [_trashButton.widthAnchor constraintGreaterThanOrEqualToConstant:108],
    ]];
    self.tableView.contentInset = UIEdgeInsetsMake(4, 0, 82, 0);
    self.tableView.verticalScrollIndicatorInsets = UIEdgeInsetsMake(0, 0, 82, 0);
}

- (NSString *)keyForFile:(WQMAuditFile *)file
{
    return [WQMFileAudit duplicateSelectionKeyForFile:file];
}

- (WQMAuditFile *)fileAtIndexPath:(NSIndexPath *)indexPath
{
    if (!_verified || !_confirmedGroups.count) return nil;
    if (indexPath.section >= (NSInteger)_confirmedGroups.count) return nil;
    NSArray *group = _confirmedGroups[(NSUInteger)indexPath.section];
    return indexPath.row < (NSInteger)group.count ? group[(NSUInteger)indexPath.row] : nil;
}

- (NSArray<WQMAuditFile *> *)selectedFiles
{
    NSMutableArray *files = [NSMutableArray new];
    for (NSArray<WQMAuditFile *> *group in _confirmedGroups) {
        for (WQMAuditFile *file in group) if ([_selectedKeys containsObject:[self keyForFile:file]]) [files addObject:file];
    }
    return files;
}

- (void)updateSelectionState
{
    NSArray *selected = [self selectedFiles];
    unsigned long long bytes = 0;
    for (WQMAuditFile *file in selected) bytes += file.bytes;
    BOOL keepsOne = [WQMFileAudit duplicateSelectionKeepsOnePerGroup:_confirmedGroups
                                                       selectedKeys:_selectedKeys];
    NSString *text;
    if (!keepsOne) {
        text = WQML(@"DUPLICATE_KEEP_ONE_HINT", @"每组至少保留一项");
    } else if (selected.count) {
        text = [NSString stringWithFormat:WQML(@"DUPLICATE_SELECTED", @"已选 %lu 项 · %@"),
                (unsigned long)selected.count, WQMFormatBytes(bytes)];
    } else {
        text = WQML(@"DUPLICATE_SELECT_HINT", @"选择要移入回收站的文件");
    }
    _selectionLabel.text = text;
    _trashButton.enabled = selected.count > 0 && !_verifying && keepsOne;
}

- (NSUInteger)selectedCountInGroup:(NSArray<WQMAuditFile *> *)group
{
    NSUInteger count = 0;
    for (WQMAuditFile *file in group) {
        if ([_selectedKeys containsObject:[self keyForFile:file]]) count++;
    }
    return count;
}

- (void)showKeepOneAlert
{
    [WQMAlertPresenter presentAlertWithTitle:WQML(@"DUPLICATE_KEEP_ONE_TITLE", @"每组至少保留一项")
                                        message:WQML(@"DUPLICATE_KEEP_ONE_MESSAGE",
                                                    @"把一组副本全部移入回收站会让对应 App 失去这个文件。请取消勾选同组的一项，再处理其他副本。")];
}

- (void)verifyContents
{
    if (_verifying || !_candidates.count) return;
    WQMFileCatalogCancellation *cancellation = [WQMFileCatalogCancellation new];
    if (![WQMLongOperationBanner startOperationWithTitle:WQML(@"DUPLICATE_VERIFYING", @"正在校验文件内容…")
        status:nil cancelHandler:^{ [cancellation cancel]; }]) return;
    _cancellation = cancellation;
    _verifying = YES;
    NSUInteger generation = ++_generation;
    _statusLabel.text = WQML(@"DUPLICATE_VERIFYING", @"正在校验文件内容…");
    [self updateSelectionState];
    [self.tableView reloadData];
    NSArray *candidates = [_candidates copy];
    NSDictionary *apps = [_apps copy];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSMutableDictionary<NSString *, NSMutableArray<WQMAuditFile *> *> *byDigest = [NSMutableDictionary new];
        NSUInteger failures = 0;
        for (NSUInteger index = 0; index < candidates.count; index++) {
            if (cancellation.cancelled) break;
            WQMAuditFile *file = candidates[index];
            WQMAppModel *app = apps[file.bundleIdentifier];
            if (!app) { failures++; continue; }
            dispatch_async(dispatch_get_main_queue(), ^{
                [WQMLongOperationBanner.shared updateStatus:[NSString stringWithFormat:
                    WQML(@"DUPLICATE_VERIFY_PROGRESS", @"正在校验 %lu/%lu…"),
                    (unsigned long)(index + 1), (unsigned long)candidates.count]];
            });
            int access = WQMOpenAppContainer(app);
            NSData *digest = access >= 0 ? [WQMFileCatalog digestForEntry:file.entry root:app.containerPath cancellation:cancellation] : nil;
            if (access >= 0) close(access);
            wq_drop_grant(app.containerPath);
            if (!digest) { failures++; continue; }
            // Group by app as well as content: an identical file in another app
            // is not a usable replacement for this app's copy.
            NSString *key = [NSString stringWithFormat:@"%@|%@", file.bundleIdentifier ?: @"",
                             [digest base64EncodedStringWithOptions:0]];
            NSMutableArray *group = byDigest[key];
            if (!group) { group = [NSMutableArray new]; byDigest[key] = group; }
            [group addObject:file];
        }
        NSMutableArray<NSArray<WQMAuditFile *> *> *groups = [NSMutableArray new];
        for (NSMutableArray *group in byDigest.allValues) if (group.count > 1) [groups addObject:group];
        [groups sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {
            WQMAuditFile *firstA = a.firstObject;
            WQMAuditFile *firstB = b.firstObject;
            unsigned long long saveA = firstA.bytes * (a.count - 1);
            unsigned long long saveB = firstB.bytes * (b.count - 1);
            if (saveA != saveB) return saveA > saveB ? NSOrderedAscending : NSOrderedDescending;
            NSComparisonResult app = [firstA.appName localizedStandardCompare:firstB.appName];
            if (app != NSOrderedSame) return app;
            return [firstA.relativePath compare:firstB.relativePath];
        }];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || generation != self->_generation) return;
            [WQMLongOperationBanner.shared hide];
            self->_verifying = NO;
            self->_verified = YES;
            self->_confirmedGroups = groups;
            if (cancellation.cancelled) {
                self->_statusLabel.text = WQML(@"DUPLICATE_CANCELLED", @"校验已取消。");
            } else if (!groups.count) {
                self->_statusLabel.text = failures
                    ? [NSString stringWithFormat:WQML(@"DUPLICATE_NO_MATCH_WITH_FAILURES", @"没有确认重复项；%lu 个文件无法完成校验。"), (unsigned long)failures]
                    : WQML(@"DUPLICATE_NO_MATCH", @"同大小文件的 SHA-256 内容不同，没有确认重复项。");
            } else {
                self->_statusLabel.text = [NSString stringWithFormat:
                    WQML(@"DUPLICATE_VERIFIED", @"已确认 %lu 组重复文件；每组至少保留一项。"),
                    (unsigned long)groups.count];
            }
            [self.tableView reloadData];
            [self updateSelectionState];
        });
    });
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return MAX(1, _verified && _confirmedGroups.count ? (NSInteger)_confirmedGroups.count : 1);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (!_verified || !_confirmedGroups.count) return 1;
    return (NSInteger)_confirmedGroups[(NSUInteger)section].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (!_verified || !_confirmedGroups.count) return WQML(@"DUPLICATE_CANDIDATES", @"同大小候选");
    NSArray<WQMAuditFile *> *group = _confirmedGroups[(NSUInteger)section];
    WQMAuditFile *first = group.firstObject;
    return [NSString stringWithFormat:WQML(@"DUPLICATE_GROUP_HEADER_APP", @"第 %ld 组 · %@ · 每个 %@"),
            (long)(section + 1), first.appName ?: first.bundleIdentifier ?: @"",
            WQMFormatBytes(first.bytes)];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (!_verified || !_confirmedGroups.count) return WQML(@"DUPLICATE_SAFETY_FOOTER", @"同大小不代表重复。内容校验完成前不会开放移入回收站。");
    return WQML(@"DUPLICATE_GROUP_FOOTER", @"这是内容完全相同的文件。请至少保留一项，再将其他副本移入回收站。");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"duplicate"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"duplicate"];
    UIListContentConfiguration *content = [cell defaultContentConfiguration];
    content.textProperties.numberOfLines = 0;
    content.secondaryTextProperties.numberOfLines = 0;
    WQMAuditFile *file = [self fileAtIndexPath:indexPath];
    if (!file) {
        cell.accessibilityIdentifier = @"duplicate.status";
        content.text = _verifying ? WQML(@"DUPLICATE_VERIFYING", @"正在校验文件内容…") : WQML(@"DUPLICATE_NO_MATCH", @"同大小文件的 SHA-256 内容不同，没有确认重复项。");
        content.secondaryText = _verified ? WQML(@"DUPLICATE_NO_MATCH_SUB", @"可以返回后重新扫描其他文件。") : WQML(@"DUPLICATE_CANDIDATE_SUB", @"先核对大小，再读取内容生成 SHA-256。");
        content.image = [UIImage systemImageNamed:@"doc.on.doc"];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryType = UITableViewCellAccessoryNone;
    } else {
        cell.accessibilityIdentifier = [NSString stringWithFormat:@"duplicate.file.%ld.%ld",
                                        (long)indexPath.section, (long)indexPath.row];
        content.text = file.relativePath.lastPathComponent;
        content.secondaryText = [NSString stringWithFormat:@"%@ · %@\n%@",
            WQMFormatBytes(file.bytes), file.appName, file.relativePath];
        content.image = [UIImage systemImageNamed:@"doc"];
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        cell.accessoryType = [_selectedKeys containsObject:[self keyForFile:file]]
            ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    }
    content.textProperties.color = WQMTheme.textPrimaryColor;
    content.secondaryTextProperties.color = WQMTheme.textSecondaryColor;
    content.imageProperties.tintColor = WQMTheme.accentColor;
    cell.backgroundColor = WQMTheme.surfaceColor;
    cell.contentConfiguration = content;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    WQMAuditFile *file = [self fileAtIndexPath:indexPath];
    if (!file || _verifying) return;
    NSString *key = [self keyForFile:file];
    BOOL wasSelected = [_selectedKeys containsObject:key];
    if (!wasSelected && indexPath.section < (NSInteger)_confirmedGroups.count) {
        NSArray<WQMAuditFile *> *group = _confirmedGroups[(NSUInteger)indexPath.section];
        // Selecting the last remaining copy would move the whole group to the
        // trash. Keep at least one file per group (and therefore per app).
        if (group.count && [self selectedCountInGroup:group] >= group.count - 1) {
            [self showKeepOneAlert];
            return;
        }
    }
    if (wasSelected) [_selectedKeys removeObject:key];
    else [_selectedKeys addObject:key];
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    [self updateSelectionState];
}

- (void)confirmTrash
{
    NSArray *selected = [self selectedFiles];
    if (!selected.count) return;
    if (![WQMFileAudit duplicateSelectionKeepsOnePerGroup:_confirmedGroups selectedKeys:_selectedKeys]) {
        [self showKeepOneAlert];
        return;
    }
    unsigned long long bytes = 0;
    for (WQMAuditFile *file in selected) bytes += file.bytes;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:WQML(@"DUPLICATE_TRASH_CONFIRM_TITLE", @"移入回收站？")
        message:[NSString stringWithFormat:WQML(@"DUPLICATE_TRASH_CONFIRM_MESSAGE", @"将把 %lu 个重复文件移入 WQManager 回收站，共 %@。请先关闭相关 App；之后可以在设置 → 数据中还原。"),
                 (unsigned long)selected.count, WQMFormatBytes(bytes)]
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:WQML(@"CANCEL", @"取消") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:WQML(@"DUPLICATE_TRASH_ACTION", @"移入回收站")
        style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        [self performTrash:selected bytes:bytes];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)performTrash:(NSArray<WQMAuditFile *> *)selected bytes:(unsigned long long)bytes
{
    if (![WQMLongOperationBanner startOperationWithTitle:WQML(@"DUPLICATE_TRASHING", @"正在移入回收站…")
        status:nil cancelHandler:nil]) return;
    NSString *session = [WQMTrashStore createSessionForLevel:WQML(@"DUPLICATE_TRASH_SOURCE", @"重复文件清理")];
    if (!session.length) {
        [WQMLongOperationBanner.shared hide];
        [WQMAlertPresenter presentAlertWithTitle:WQML(@"DUPLICATE_TRASH_ACTION", @"移入回收站")
                                             message:WQML(@"DUPLICATE_TRASH_UNAVAILABLE", @"无法创建回收站目录，请检查存储空间后重试。")];
        return;
    }
    NSDictionary *apps = [_apps copy];
    WQMAppModel *recordApp = apps[selected.firstObject.bundleIdentifier];
    NSString *recordAppName = recordApp.displayName.length ? recordApp.displayName : WQML(@"DUPLICATE_MULTIPLE_APPS", @"多个 App");
    WQMOperationRecord *record = [WQMOperationStore beginOperation:WQMOperationKindDeleteFiles
                                                          appName:recordAppName
                                                 bundleIdentifier:recordApp.bundleIdentifier ?: @""];
    record.scope = WQML(@"DUPLICATE_TITLE", @"重复文件");
    record.safetyBackupPath = session;
    [WQMOperationStore updateRecord:record];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSMutableArray<NSDictionary *> *moved = [NSMutableArray new];
        unsigned long long movedBytes = 0;
        NSUInteger failures = 0, index = 0;
        for (WQMAuditFile *file in selected) {
            index++;
            WQMAppModel *app = apps[file.bundleIdentifier];
            if (!app || wq_process_id_for_bundle(app.bundleIdentifier) > 0) { failures++; continue; }
            int access = WQMOpenAppContainer(app);
            if (access < 0) { failures++; continue; }
            close(access);
            NSDictionary *version = wq_file_version(file.absolutePath);
            int parent = WQOpenDirectoryNoLinks(file.absolutePath.stringByDeletingLastPathComponent);
            BOOL valid = parent >= 0 && [WQMFileAudit fileVersion:version matchesEntry:file.entry] &&
                [file.absolutePath hasPrefix:[app.containerPath stringByAppendingString:@"/"]];
            if (parent >= 0) close(parent);
            if (!valid) { wq_drop_grant(app.containerPath); failures++; continue; }
            NSString *storedName = [NSString stringWithFormat:@"%03lu-%@", (unsigned long)index,
                                    file.relativePath.lastPathComponent];
            NSString *target = [session stringByAppendingPathComponent:storedName];
            NSError *error = nil;
            BOOL movedOK = [[NSFileManager defaultManager] moveItemAtPath:file.absolutePath toPath:target error:&error];
            wq_drop_grant(app.containerPath);
            if (!movedOK) { failures++; continue; }
            movedBytes += file.bytes;
            [moved addObject:@{
                @"Name": storedName,
                @"DisplayName": file.relativePath.lastPathComponent,
                @"OriginalPath": file.absolutePath,
                @"BundleID": app.bundleIdentifier,
                @"Container": app.containerPath,
                @"ContainerDevice": @(app.containerDevice),
                @"ContainerInode": @(app.containerInode),
                @"Bytes": @(file.bytes),
                @"Directory": @NO,
            }];
        }
        if (moved.count) {
            [WQMTrashStore recordSession:session source:WQML(@"DUPLICATE_TRASH_SOURCE", @"重复文件清理") items:moved];
        } else {
            // Nothing could be moved; do not leave an empty folder in the bin.
            [[NSFileManager defaultManager] removeItemAtPath:session error:NULL];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [WQMLongOperationBanner.shared hide];
            record.bytes = movedBytes;
            record.finishedAt = NSDate.date;
            record.status = moved.count && !failures ? WQMOperationStatusSuccess : WQMOperationStatusFailure;
            if (!moved.count) record.safetyBackupPath = @"";
            if (moved.count) {
                record.message = [NSString stringWithFormat:WQML(@"DUPLICATE_HISTORY_MOVED", @"移入回收站 %lu 项"),
                                  (unsigned long)moved.count];
            }
            if (failures) {
                record.errorMessage = [NSString stringWithFormat:WQML(@"DUPLICATE_HISTORY_FAILED", @"%lu 项未移动"),
                                       (unsigned long)failures];
            }
            [WQMOperationStore updateRecord:record];
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            [self removeMovedFiles:moved];
            if (self->_completion) self->_completion();
            NSString *message;
            if (!moved.count) {
                message = WQML(@"DUPLICATE_TRASH_NONE", @"没有文件被移动。请先完全关闭相关 App，再重试；如果仍然失败，请刷新列表后重试。");
            } else {
                message = [NSString stringWithFormat:WQML(@"DUPLICATE_TRASH_RESULT", @"已将 %lu 项移入回收站；%lu 项未处理。"),
                           (unsigned long)moved.count, (unsigned long)failures];
            }
            [WQMAlertPresenter presentAlertWithTitle:WQML(@"DUPLICATE_TRASH_ACTION", @"移入回收站") message:message];
        });
    });
}

- (void)removeMovedFiles:(NSArray<NSDictionary *> *)moved
{
    NSMutableSet<NSString *> *paths = [NSMutableSet new];
    for (NSDictionary *item in moved) if ([item[@"OriginalPath"] isKindOfClass:NSString.class]) [paths addObject:item[@"OriginalPath"]];
    NSMutableArray *groups = [NSMutableArray new];
    for (NSArray<WQMAuditFile *> *group in _confirmedGroups) {
        NSMutableArray *kept = [NSMutableArray new];
        for (WQMAuditFile *file in group) if (![paths containsObject:file.absolutePath]) [kept addObject:file];
        if (kept.count > 1) [groups addObject:kept];
    }
    _confirmedGroups = groups;
    [_selectedKeys removeAllObjects];
    [self.tableView reloadData];
    [self updateSelectionState];
}

@end
