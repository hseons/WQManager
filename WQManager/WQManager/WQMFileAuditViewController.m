#import "WQMFileAuditViewController.h"
#import "WQMAppModel.h"
#import "WQMAlertPresenter.h"
#import "WQMDuplicateGroupViewController.h"
#import "WQMFileAudit.h"
#import "WQMFileCatalog.h"
#import "WQMFilePreviewViewController.h"
#import "WQMLanguageManager.h"
#import "WQMLongOperationBanner.h"
#import "WQMSpaceLensViewController.h"
#import "WQMTheme.h"
#import "WQAccess.h"
#import "WQAppsSupport.h"
#import "WQMContainerAccess.h"

static const unsigned long long WQMLargeFileMinimum = 50ULL * 1024ULL * 1024ULL;
static const unsigned long long WQMDuplicateMinimum = 1ULL * 1024ULL * 1024ULL;

@implementation WQMFileAuditViewController {
    NSArray<WQMAppModel *> *_apps;
    NSDictionary<NSString *, WQMAppModel *> *_appsByBundle;
    WQMFileCatalogCancellation *_cancellation;
    NSArray<WQMAuditFile *> *_largeFiles;
    NSArray<NSArray<WQMAuditFile *> *> *_duplicateGroups;
    UILabel *_summaryLabel;
    UISegmentedControl *_segments;
    BOOL _duplicateMode;
    BOOL _loading;
    BOOL _needsRescan;
    NSUInteger _generation;
}

- (instancetype)initWithApps:(NSArray<WQMAppModel *> *)apps
{
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _apps = [apps copy];
        NSMutableDictionary *byBundle = [NSMutableDictionary new];
        for (WQMAppModel *app in apps) if (app.bundleIdentifier.length) byBundle[app.bundleIdentifier] = app;
        _appsByBundle = byBundle;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.tableView.backgroundColor = WQMTheme.canvasColor;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 82;
    self.tableView.accessibilityIdentifier = @"file-audit.table";
    _segments = [[UISegmentedControl alloc] initWithItems:@[
        WQML(@"AUDIT_LARGE_FILES", @"大文件"),
        WQML(@"AUDIT_DUPLICATES", @"重复文件"),
    ]];
    _segments.selectedSegmentIndex = 0;
    _segments.accessibilityIdentifier = @"file-audit.modes";
    [_segments addTarget:self action:@selector(modeChanged:) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = _segments;
    self.refreshControl = [UIRefreshControl new];
    [self.refreshControl addTarget:self action:@selector(loadAudit) forControlEvents:UIControlEventValueChanged];
    [self configureHeader];
    [self loadAudit];
}

- (void)dealloc
{
    [_cancellation cancel];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    if (_needsRescan) {
        _needsRescan = NO;
        [self loadAudit];
    }
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    if (self.isMovingFromParentViewController) [_cancellation cancel];
}

- (void)configureHeader
{
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 64)];
    _summaryLabel = [UILabel new];
    _summaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _summaryLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    _summaryLabel.textColor = WQMTheme.textSecondaryColor;
    _summaryLabel.numberOfLines = 0;
    _summaryLabel.text = WQML(@"AUDIT_SCANNING", @"正在扫描可访问的 App…");
    [header addSubview:_summaryLabel];
    [NSLayoutConstraint activateConstraints:@[
        [_summaryLabel.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:4],
        [_summaryLabel.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-4],
        [_summaryLabel.topAnchor constraintEqualToAnchor:header.topAnchor constant:6],
    ]];
    self.tableView.tableHeaderView = header;
}

- (void)modeChanged:(UISegmentedControl *)sender
{
    _duplicateMode = sender.selectedSegmentIndex == 1;
    [self updateSummary];
    [self.tableView reloadData];
}

- (void)loadAudit
{
    if (_loading) { [self.refreshControl endRefreshing]; return; }
    WQMFileCatalogCancellation *cancellation = [WQMFileCatalogCancellation new];
    if (![WQMLongOperationBanner startOperationWithTitle:WQML(@"AUDIT_SCANNING", @"正在扫描可访问的 App…")
        status:nil cancelHandler:^{ [cancellation cancel]; }]) {
        [self.refreshControl endRefreshing];
        return;
    }
    _cancellation = cancellation;
    _loading = YES;
    NSUInteger generation = ++_generation;
    _summaryLabel.text = WQML(@"AUDIT_SCANNING", @"正在扫描可访问的 App…");
    [self.tableView reloadData];
    NSArray *apps = [_apps copy];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSMutableArray<WQMAuditFile *> *allFiles = [NSMutableArray new];
        NSUInteger scanned = 0, skipped = 0;
        for (NSUInteger index = 0; index < apps.count; index++) {
            if (cancellation.cancelled) break;
            WQMAppModel *app = apps[index];
            dispatch_async(dispatch_get_main_queue(), ^{
                [WQMLongOperationBanner.shared updateStatus:[NSString stringWithFormat:
                    WQML(@"AUDIT_PROGRESS", @"正在扫描 %lu/%lu · %@"),
                    (unsigned long)(index + 1), (unsigned long)apps.count, app.displayName]];
            });
            if (!app.bundleIdentifier.length || !app.accessAvailable || !app.identityKnown) { skipped++; continue; }
            int access = WQMOpenAppContainer(app);
            WQMFileCatalog *catalog = access >= 0 ? [WQMFileCatalog scanRoot:app.containerPath cancellation:cancellation] : nil;
            if (access >= 0) close(access);
            if (catalog) {
                [allFiles addObjectsFromArray:[WQMFileAudit filesFromCatalog:catalog appName:app.displayName
                                                            bundleIdentifier:app.bundleIdentifier
                                                               containerPath:app.containerPath includeCaches:NO]];
                scanned++;
            } else {
                skipped++;
            }
            wq_drop_grant(app.containerPath);
        }
        NSArray *large = [WQMFileAudit largeFiles:allFiles minimumBytes:WQMLargeFileMinimum limit:200];
        NSArray *duplicates = [WQMFileAudit duplicateSizeBuckets:allFiles minimumBytes:WQMDuplicateMinimum];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || generation != self->_generation) return;
            [WQMLongOperationBanner.shared hide];
            [self.refreshControl endRefreshing];
            self->_loading = NO;
            self->_largeFiles = large;
            self->_duplicateGroups = duplicates;
            self->_summaryLabel.accessibilityValue = [NSString stringWithFormat:@"scanned:%lu skipped:%lu", (unsigned long)scanned, (unsigned long)skipped];
            if (cancellation.cancelled) {
                self->_summaryLabel.text = WQML(@"AUDIT_CANCELLED", @"扫描已取消。");
            } else {
                [self updateSummary];
            }
            [self.tableView reloadData];
        });
    });
}

- (void)updateSummary
{
    if (_duplicateMode) {
        NSUInteger files = 0;
        for (NSArray *group in _duplicateGroups) files += group.count;
        _summaryLabel.text = [NSString stringWithFormat:
            WQML(@"AUDIT_DUPLICATE_SUMMARY", @"%lu 组同大小候选 · %lu 个文件 · 内容校验前不会开放清理"),
            (unsigned long)_duplicateGroups.count, (unsigned long)files];
    } else {
        _summaryLabel.text = [NSString stringWithFormat:
            WQML(@"AUDIT_LARGE_SUMMARY", @"%lu 个大文件 · 最低 50 MB · 默认不包含缓存与 tmp"),
            (unsigned long)_largeFiles.count];
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return _duplicateMode ? MAX(1, (NSInteger)_duplicateGroups.count) : 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (!_duplicateMode) return MAX(1, _largeFiles.count);
    if (!_duplicateGroups.count) return 1;
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (_duplicateMode && _duplicateGroups.count) {
        NSArray<WQMAuditFile *> *group = _duplicateGroups[(NSUInteger)section];
        unsigned long long each = group.firstObject.bytes;
        unsigned long long save = each * (group.count - 1);
        return [NSString stringWithFormat:WQML(@"AUDIT_DUPLICATE_GROUP", @"%lu 个同大小文件 · 最多可释放 %@"),
                (unsigned long)group.count, WQMFormatBytes(save)];
    }
    return _duplicateMode ? WQML(@"AUDIT_DUPLICATES", @"重复文件") : WQML(@"AUDIT_LARGE_FILES", @"大文件");
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (_duplicateMode && _duplicateGroups.count) return nil;
    return _duplicateMode
        ? WQML(@"AUDIT_DUPLICATE_FOOTER", @"只按文件大小列出候选。进入分组后会读取 SHA-256，内容一致才允许移入回收站。")
        : WQML(@"AUDIT_LARGE_FOOTER", @"列出前 200 个大文件。缓存与 tmp 不在结果中；文件可能属于 App 的离线资源。");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"audit"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"audit"];
    UIListContentConfiguration *content = [cell defaultContentConfiguration];
    content.textProperties.numberOfLines = 0;
    content.secondaryTextProperties.numberOfLines = 0;
    if (_loading) {
        content.text = WQML(@"AUDIT_SCANNING", @"正在扫描可访问的 App…");
        content.image = [UIImage systemImageNamed:@"checklist"];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryType = UITableViewCellAccessoryNone;
    } else if (_duplicateMode) {
        if (!_duplicateGroups.count) {
            cell.accessibilityIdentifier = @"audit.duplicate.empty";
            content.text = WQML(@"AUDIT_NO_DUPLICATES", @"没有同大小候选");
            content.secondaryText = WQML(@"AUDIT_NO_DUPLICATES_SUB", @"至少需要两个大于 1 MB、大小完全相同的文件。");
            content.image = [UIImage systemImageNamed:@"doc.on.doc"];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.accessoryType = UITableViewCellAccessoryNone;
        } else {
            cell.accessibilityIdentifier = [NSString stringWithFormat:@"audit.duplicate.%ld", (long)indexPath.section];
            NSArray<WQMAuditFile *> *group = _duplicateGroups[(NSUInteger)indexPath.section];
            unsigned long long each = group.firstObject.bytes;
            WQMAuditFile *first = group.firstObject;
            content.text = [NSString stringWithFormat:WQML(@"AUDIT_DUPLICATE_ROW_TITLE", @"%lu 个文件 · 每个 %@"),
                            (unsigned long)group.count, WQMFormatBytes(each)];
            content.secondaryText = [NSString stringWithFormat:WQML(@"AUDIT_DUPLICATE_ROW_SUB", @"%@ · %@…"),
                first.appName, first.relativePath];
            content.image = [UIImage systemImageNamed:@"doc.on.doc"];
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    } else {
        if (!_largeFiles.count) {
            cell.accessibilityIdentifier = @"audit.large.empty";
            content.text = WQML(@"AUDIT_NO_LARGE_FILES", @"没有 50 MB 以上的文件");
            content.secondaryText = WQML(@"AUDIT_NO_LARGE_SUB", @"下拉重新扫描，或检查 App 是否仍可访问。");
            content.image = [UIImage systemImageNamed:@"externaldrive"];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.accessoryType = UITableViewCellAccessoryNone;
        } else {
            cell.accessibilityIdentifier = [NSString stringWithFormat:@"audit.large.%ld", (long)indexPath.row];
            WQMAuditFile *file = _largeFiles[(NSUInteger)indexPath.row];
            content.text = file.relativePath.lastPathComponent;
            content.secondaryText = [NSString stringWithFormat:@"%@ · %@\n%@",
                WQMFormatBytes(file.bytes), file.appName, file.relativePath];
            content.image = [UIImage systemImageNamed:@"externaldrive"];
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
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
    if (_loading) return;
    if (_duplicateMode) {
        if (!_duplicateGroups.count) return;
        NSArray *group = _duplicateGroups[(NSUInteger)indexPath.section];
        __weak typeof(self) weakSelf = self;
        WQMDuplicateGroupViewController *detail = [[WQMDuplicateGroupViewController alloc]
            initWithFiles:group apps:_apps completion:^{
                __strong typeof(weakSelf) self = weakSelf;
                self->_needsRescan = YES;
            }];
        [self.navigationController pushViewController:detail animated:YES];
        return;
    }
    if (!_largeFiles.count) return;
    [self presentActionsForFile:_largeFiles[(NSUInteger)indexPath.row] indexPath:indexPath];
}

- (void)presentActionsForFile:(WQMAuditFile *)file indexPath:(NSIndexPath *)indexPath
{
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:file.relativePath.lastPathComponent
                                                                  message:file.relativePath
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    WQMAppModel *app = _appsByBundle[file.bundleIdentifier];
    [sheet addAction:[UIAlertAction actionWithTitle:WQML(@"PREVIEW", @"预览") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        // The audit scan drops its grants, so re-open the container before the
        // preview reads the file directly.
        if (app) {
            int access = WQMOpenAppContainer(app);
            if (access < 0) {
                [WQMAlertPresenter presentAlertWithTitle:WQML(@"FILE_CHANGED", @"变化")
                                                     message:WQML(@"FILE_SCAN_FAILED", @"目录已变化或访问受限，请刷新应用列表后重试。")];
                return;
            }
            close(access);
        }
        WQMFilePreviewViewController *preview = [[WQMFilePreviewViewController alloc]
            initWithFilePath:file.absolutePath name:file.relativePath.lastPathComponent];
        [self.navigationController pushViewController:preview animated:YES];
    }]];
    if (app) [sheet addAction:[UIAlertAction actionWithTitle:WQML(@"FILE_OPEN_FOLDER", @"打开所在目录") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        WQMSpaceLensViewController *lens = [[WQMSpaceLensViewController alloc]
            initWithApp:app relativePath:file.relativePath.stringByDeletingLastPathComponent];
        [self.navigationController pushViewController:lens animated:YES];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:WQML(@"CANCEL", @"取消") style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.tableView;
    sheet.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:indexPath];
    [self presentViewController:sheet animated:YES completion:nil];
}

@end
