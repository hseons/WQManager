#import "WQMExportCenterViewController.h"
#import "WQMAppModel.h"
#import "WQMAlertPresenter.h"
#import "WQMFileAudit.h"
#import "WQMFileCatalog.h"
#import "WQMFilePreviewViewController.h"
#import "WQMLanguageManager.h"
#import "WQMLongOperationBanner.h"
#import "WQMOperationStore.h"
#import "WQMTheme.h"
#import "WQAccess.h"
#import "WQAppsSupport.h"
#import "WQMContainerAccess.h"

static const NSUInteger WQMExportSelectionLimit = 100;

/// Removes one export tree. Only the WQMDataExport-<stamp> wrapper is deleted,
/// never the app's whole temporary directory. Deletion runs off the main queue
/// because an export can be several gigabytes.
static void WQMRemoveExportRoot(NSString *root)
{
    NSString *wrapper = root.stringByDeletingLastPathComponent;
    if (![wrapper.lastPathComponent hasPrefix:@"WQMDataExport-"]) return;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [NSFileManager.defaultManager removeItemAtPath:wrapper error:NULL];
    });
}

@interface WQMExportCenterViewController () <UIDocumentPickerDelegate>
@end

@implementation WQMExportCenterViewController {
    WQMAppModel *_app;
    WQMFileCatalogCancellation *_cancellation;
    NSArray<WQMAuditFile *> *_allFiles;
    NSArray<WQMAuditFile *> *_visibleFiles;
    NSMutableSet<NSString *> *_selectedKeys;
    WQMFileCategory _category;
    UILabel *_summaryLabel;
    UILabel *_selectionLabel;
    UIButton *_previewButton;
    UIButton *_exportButton;
    BOOL _scanning;
    BOOL _exporting;
    NSUInteger _generation;
    WQMOperationRecord *_pendingRecord;
    NSString *_pendingRoot;
}

- (instancetype)initWithApp:(WQMAppModel *)app
{
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) _app = app;
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = WQML(@"EXPORT_CENTER_TITLE", @"数据导出");
    self.tableView.backgroundColor = WQMTheme.canvasColor;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 74;
    self.tableView.accessibilityIdentifier = @"export.table";
    self.tableView.allowsMultipleSelection = NO;
    _selectedKeys = [NSMutableSet new];
    self.refreshControl = [UIRefreshControl new];
    [self.refreshControl addTarget:self action:@selector(loadFiles) forControlEvents:UIControlEventValueChanged];
    [self configureHeader];
    [self configureActionBar];
    [self updateNavigationItem];
    [self loadFiles];
}

- (void)dealloc
{
    [_cancellation cancel];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    if (self.isMovingFromParentViewController) [_cancellation cancel];
}

- (void)configureHeader
{
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 108)];
    _summaryLabel = [UILabel new];
    _summaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _summaryLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    _summaryLabel.textColor = WQMTheme.textSecondaryColor;
    _summaryLabel.numberOfLines = 0;

    UISegmentedControl *segments = [[UISegmentedControl alloc] initWithItems:@[
        WQML(@"EXPORT_CATEGORY_ALL", @"全部"),
        WQML(@"EXPORT_CATEGORY_IMAGE", @"图片"),
        WQML(@"EXPORT_CATEGORY_VIDEO", @"视频"),
        WQML(@"EXPORT_CATEGORY_AUDIO", @"音频"),
        WQML(@"EXPORT_CATEGORY_DOCUMENT", @"文档"),
        WQML(@"EXPORT_CATEGORY_ARCHIVE", @"压缩包"),
    ]];
    segments.translatesAutoresizingMaskIntoConstraints = NO;
    segments.selectedSegmentIndex = 0;
    segments.apportionsSegmentWidthsByContent = YES;
    segments.accessibilityIdentifier = @"export.categories";
    [segments addTarget:self action:@selector(categoryChanged:) forControlEvents:UIControlEventValueChanged];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_summaryLabel, segments]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    [header addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:4],
        [stack.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-4],
        [stack.topAnchor constraintEqualToAnchor:header.topAnchor constant:4],
        [stack.bottomAnchor constraintLessThanOrEqualToAnchor:header.bottomAnchor constant:-8],
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

    UILabel *selection = [UILabel new];
    selection.translatesAutoresizingMaskIntoConstraints = NO;
    selection.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    selection.textColor = WQMTheme.textSecondaryColor;
    selection.text = WQML(@"EXPORT_NOTHING_SELECTED", @"选择要导出的文件");
    selection.accessibilityIdentifier = @"export.selection";
    _selectionLabel = selection;

    _previewButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _previewButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_previewButton setTitle:WQML(@"PREVIEW", @"预览") forState:UIControlStateNormal];
    _previewButton.accessibilityIdentifier = @"export.preview";
    [_previewButton addTarget:self action:@selector(previewSelected) forControlEvents:UIControlEventTouchUpInside];

    _exportButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _exportButton.translatesAutoresizingMaskIntoConstraints = NO;
    UIButtonConfiguration *configuration = [UIButtonConfiguration filledButtonConfiguration];
    configuration.title = WQML(@"EXPORT_ACTION", @"导出");
    configuration.baseBackgroundColor = WQMTheme.inverseSurfaceColor;
    configuration.baseForegroundColor = WQMTheme.inverseTextColor;
    configuration.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    _exportButton.configuration = configuration;
    _exportButton.accessibilityIdentifier = @"export.action";
    [_exportButton addTarget:self action:@selector(exportSelected) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *actions = [[UIStackView alloc] initWithArrangedSubviews:@[_previewButton, _exportButton]];
    actions.translatesAutoresizingMaskIntoConstraints = NO;
    actions.axis = UILayoutConstraintAxisHorizontal;
    actions.spacing = 10;
    actions.alignment = UIStackViewAlignmentCenter;
    [bar addSubview:selection];
    [bar addSubview:actions];
    [NSLayoutConstraint activateConstraints:@[
        [bar.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:18],
        [bar.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-18],
        [bar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-8],
        [bar.heightAnchor constraintGreaterThanOrEqualToConstant:62],
        [selection.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:16],
        [selection.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [selection.trailingAnchor constraintLessThanOrEqualToAnchor:actions.leadingAnchor constant:-12],
        [actions.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-12],
        [actions.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [_exportButton.widthAnchor constraintGreaterThanOrEqualToConstant:74],
    ]];
    self.tableView.contentInset = UIEdgeInsetsMake(4, 0, 82, 0);
    self.tableView.verticalScrollIndicatorInsets = UIEdgeInsetsMake(0, 0, 82, 0);
    [self updateSelectionBar];
}

- (void)updateNavigationItem
{
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:WQML(@"SELECT_ALL", @"全选") style:UIBarButtonItemStylePlain
               target:self action:@selector(toggleSelectAll)];
}

- (void)loadFiles
{
    if (_scanning) { [self.refreshControl endRefreshing]; return; }
    WQMFileCatalogCancellation *cancellation = [WQMFileCatalogCancellation new];
    if (![WQMLongOperationBanner startOperationWithTitle:WQML(@"EXPORT_SCANNING", @"正在整理可导出文件…")
        status:nil cancelHandler:^{ [cancellation cancel]; }]) {
        [self.refreshControl endRefreshing];
        return;
    }
    _cancellation = cancellation;
    _scanning = YES;
    NSUInteger generation = ++_generation;
    _summaryLabel.text = WQML(@"EXPORT_SCANNING", @"正在整理可导出文件…");
    [self.tableView reloadData];
    WQMAppModel *app = _app;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        int access = WQMOpenAppContainer(app);
        WQMFileCatalog *catalog = access >= 0 ? [WQMFileCatalog scanRoot:app.containerPath cancellation:cancellation] : nil;
        if (access >= 0) close(access);
        NSArray *files = catalog ? [WQMFileAudit filesFromCatalog:catalog appName:app.displayName
                                                bundleIdentifier:app.bundleIdentifier
                                                   containerPath:app.containerPath includeCaches:NO] : nil;
        wq_drop_grant(app.containerPath);
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || generation != self->_generation) return;
            [WQMLongOperationBanner.shared hide];
            [self.refreshControl endRefreshing];
            self->_scanning = NO;
            if (cancellation.cancelled) {
                self->_summaryLabel.text = WQML(@"EXPORT_SCAN_CANCELLED", @"已取消，可下拉重新整理。");
                [self.tableView reloadData];
                return;
            }
            self->_allFiles = files ?: @[];
            if (!files) {
                self->_summaryLabel.text = WQML(@"EXPORT_SCAN_FAILED", @"当前 App 无法读取，请刷新索引后重试。");
            }
            [self applyCategory];
        });
    });
}

- (void)categoryChanged:(UISegmentedControl *)sender
{
    _category = (WQMFileCategory)sender.selectedSegmentIndex;
    [self applyCategory];
}

- (void)applyCategory
{
    [_selectedKeys removeAllObjects];
    NSMutableArray<WQMAuditFile *> *files = [NSMutableArray new];
    for (WQMAuditFile *file in _allFiles) {
        if (_category == WQMFileCategoryAll || file.category == _category) [files addObject:file];
    }
    _visibleFiles = files;
    unsigned long long bytes = 0;
    for (WQMAuditFile *file in files) bytes += file.bytes;
    if (_allFiles) {
        _summaryLabel.text = [NSString stringWithFormat:
            WQML(@"EXPORT_SUMMARY", @"%lu 个文件 · %@ · 默认不包含缓存与 tmp"),
            (unsigned long)files.count, WQMFormatBytes(bytes)];
    }
    [self.tableView reloadData];
    [self updateSelectionBar];
}

- (NSArray<WQMAuditFile *> *)selectedFiles
{
    NSMutableArray<WQMAuditFile *> *files = [NSMutableArray new];
    for (WQMAuditFile *file in _visibleFiles) if ([_selectedKeys containsObject:[self keyForFile:file]]) [files addObject:file];
    return files;
}

- (NSString *)keyForFile:(WQMAuditFile *)file
{
    return [NSString stringWithFormat:@"%@|%@", file.bundleIdentifier, file.relativePath];
}

- (void)toggleSelectAll
{
    if (_visibleFiles.count == 0) return;
    if (_selectedKeys.count) {
        [_selectedKeys removeAllObjects];
        [self.tableView reloadData];
        [self updateSelectionBar];
        return;
    }
    NSUInteger count = MIN(_visibleFiles.count, WQMExportSelectionLimit);
    for (NSUInteger index = 0; index < count; index++) {
        [_selectedKeys addObject:[self keyForFile:_visibleFiles[index]]];
    }
    if (_visibleFiles.count > count) {
        [WQMAlertPresenter presentAlertWithTitle:WQML(@"EXPORT_LIMIT_TITLE", @"已达到单次导出上限")
                                             message:[NSString stringWithFormat:
                                                      WQML(@"EXPORT_LIMIT_MESSAGE", @"单次最多导出 %lu 项，当前已选择前 %lu 项。"),
                                                      (unsigned long)WQMExportSelectionLimit,
                                                      (unsigned long)count]];
    }
    [self.tableView reloadData];
    [self updateSelectionBar];
}

- (void)updateSelectionBar
{
    NSArray<WQMAuditFile *> *selected = [self selectedFiles];
    unsigned long long bytes = 0;
    for (WQMAuditFile *file in selected) bytes += file.bytes;
    NSString *text = selected.count
        ? [NSString stringWithFormat:WQML(@"EXPORT_SELECTED", @"已选 %lu 项 · %@"),
           (unsigned long)selected.count, WQMFormatBytes(bytes)]
        : WQML(@"EXPORT_NOTHING_SELECTED", @"选择要导出的文件");
    _selectionLabel.text = text;
    _previewButton.enabled = selected.count == 1;
    _exportButton.enabled = selected.count > 0 && !_scanning && !_exporting;
    self.navigationItem.rightBarButtonItem.title = _selectedKeys.count
        ? WQML(@"DESELECT_ALL", @"取消全选") : WQML(@"SELECT_ALL", @"全选");
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return MAX(1, _visibleFiles.count);
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    return WQML(@"EXPORT_FOOTER", @"导出会保留文件在 App 容器内的相对目录。符号链接和特殊文件不会进入列表。");
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"export"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"export"];
    UIListContentConfiguration *content = [cell defaultContentConfiguration];
    content.textProperties.numberOfLines = 0;
    content.secondaryTextProperties.numberOfLines = 0;
    if (!_visibleFiles.count) {
        cell.accessibilityIdentifier = @"export.empty";
        content.text = _scanning ? WQML(@"EXPORT_SCANNING", @"正在整理可导出文件…") : WQML(@"EXPORT_EMPTY", @"这个分类没有可导出的文件");
        content.secondaryText = _scanning ? nil : WQML(@"EXPORT_EMPTY_SUB", @"切换类型或下拉重新整理。缓存与 tmp 默认不显示。");
        content.image = [UIImage systemImageNamed:@"tray"];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryType = UITableViewCellAccessoryNone;
    } else {
        WQMAuditFile *file = _visibleFiles[(NSUInteger)indexPath.row];
        cell.accessibilityIdentifier = [NSString stringWithFormat:@"export.file.%ld", (long)indexPath.row];
        content.text = file.relativePath.lastPathComponent;
        content.secondaryText = [NSString stringWithFormat:@"%@ · %@\n%@",
            WQMFormatBytes(file.bytes), file.appName, file.relativePath];
        content.image = [UIImage systemImageNamed:[self symbolForCategory:file.category]];
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

- (NSString *)symbolForCategory:(WQMFileCategory)category
{
    switch (category) {
        case WQMFileCategoryImage: return @"photo";
        case WQMFileCategoryVideo: return @"play.rectangle";
        case WQMFileCategoryAudio: return @"waveform";
        case WQMFileCategoryDocument: return @"doc.text";
        case WQMFileCategoryArchive: return @"archivebox";
        default: return @"doc";
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (!_visibleFiles.count) return;
    WQMAuditFile *file = _visibleFiles[(NSUInteger)indexPath.row];
    NSString *key = [self keyForFile:file];
    if (![_selectedKeys containsObject:key] && _selectedKeys.count >= WQMExportSelectionLimit) {
        [WQMAlertPresenter presentAlertWithTitle:WQML(@"EXPORT_LIMIT_TITLE", @"已达到单次导出上限")
                                             message:[NSString stringWithFormat:
                                                      WQML(@"EXPORT_LIMIT_MESSAGE", @"单次最多导出 %lu 项，当前已选择前 %lu 项。"),
                                                      (unsigned long)WQMExportSelectionLimit,
                                                      (unsigned long)WQMExportSelectionLimit]];
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        return;
    }
    if ([_selectedKeys containsObject:key]) [_selectedKeys removeObject:key];
    else [_selectedKeys addObject:key];
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    [self updateSelectionBar];
}

- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath
{
    (void)tableView;
    (void)indexPath;
}

- (void)previewSelected
{
    WQMAuditFile *file = [self selectedFiles].firstObject;
    if (!file) return;
    // loadFiles drops the container grant after scanning; restore it so the
    // preview can read the file directly.
    if (_app) {
        int access = WQMOpenAppContainer(_app);
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
}

- (void)exportSelected
{
    if (_exporting) return;
    NSArray<WQMAuditFile *> *selected = [self selectedFiles];
    if (!selected.count) return;
    unsigned long long totalBytes = 0;
    for (WQMAuditFile *file in selected) totalBytes += file.bytes;
    unsigned long long freeBytes = WQMAppsSupportVolumeAvailableBytes(NSTemporaryDirectory());
    if (totalBytes > freeBytes || freeBytes - totalBytes < WQM_MIN_FREE_SPACE) {
        [WQMAlertPresenter presentAlertWithTitle:WQML(@"EXPORT_NO_SPACE_TITLE", @"可用空间不足")
                                             message:[NSString stringWithFormat:
                                                      WQML(@"EXPORT_NO_SPACE_MESSAGE",
                                                           @"本次导出需要 %@，当前可用 %@。请取消部分文件或清理空间后重试。"),
                                                      WQMFormatBytes(totalBytes), WQMFormatBytes(freeBytes)]];
        return;
    }
    WQMFileCatalogCancellation *cancellation = [WQMFileCatalogCancellation new];
    if (![WQMLongOperationBanner startOperationWithTitle:WQML(@"EXPORT_RUNNING", @"正在导出数据…")
        status:nil cancelHandler:^{ [cancellation cancel]; }]) return;
    _exporting = YES;
    [self updateSelectionBar];

    NSDateFormatter *stamp = [NSDateFormatter new];
    stamp.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    stamp.dateFormat = @"yyyyMMdd-HHmmss";
    NSString *suffix = [[NSUUID UUID].UUIDString substringToIndex:8];
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"WQMDataExport-%@-%@", [stamp stringFromDate:NSDate.date], suffix]];
    NSString *safeName = _app.displayName.length ? _app.displayName : @"App";
    root = [root stringByAppendingPathComponent:safeName];
    [[NSFileManager defaultManager] createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:NULL];

    WQMOperationRecord *record = [WQMOperationStore beginOperation:WQMOperationKindExport
                                                          appName:_app.displayName
                                                 bundleIdentifier:_app.bundleIdentifier];
    record.scope = WQML(@"EXPORT_CENTER_TITLE", @"数据导出");
    [WQMOperationStore updateRecord:record];
    WQMAppModel *app = _app;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        int access = WQMOpenAppContainer(app);
        BOOL valid = access >= 0;
        if (access >= 0) close(access);
        NSMutableArray<NSURL *> *urls = [NSMutableArray new];
        unsigned long long copiedBytes = 0;
        NSUInteger failures = 0;
        for (WQMAuditFile *file in selected) {
            if (cancellation.cancelled || !valid) break;
            NSDictionary *version = wq_file_version(file.absolutePath);
            if (![WQMFileAudit fileVersion:version matchesEntry:file.entry]) { failures++; continue; }
            NSString *target = [root stringByAppendingPathComponent:file.relativePath];
            [[NSFileManager defaultManager] createDirectoryAtPath:target.stringByDeletingLastPathComponent
                                   withIntermediateDirectories:YES attributes:nil error:NULL];
            NSString *error = nil;
            if (wq_copy_to_local(file.absolutePath, target, &error)) {
                [urls addObject:[NSURL fileURLWithPath:target]];
                copiedBytes += file.bytes;
            } else {
                failures++;
            }
        }
        wq_drop_grant(app.containerPath);
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            [WQMLongOperationBanner.shared hide];
            if (!self) {
                record.bytes = 0;
                record.status = WQMOperationStatusFailure;
                record.message = @"";
                record.finishedAt = NSDate.date;
                [WQMOperationStore updateRecord:record];
                WQMRemoveExportRoot(root);
                return;
            }
            record.bytes = copiedBytes;
            record.finishedAt = NSDate.date;
            if (cancellation.cancelled) {
                [self finishExportRecord:record status:WQMOperationStatusCancelled bytes:0
                                 message:WQML(@"EXPORT_HISTORY_CANCELLED", @"导出已取消") error:@"" root:root];
                return;
            }
            if (!urls.count) {
                [self finishExportRecord:record status:WQMOperationStatusFailure bytes:0 message:@"" error:@"" root:root];
                [WQMAlertPresenter presentAlertWithTitle:WQML(@"EXPORT_FAILED_TITLE", @"导出失败")
                                                     message:WQML(@"EXPORT_FAILED_MESSAGE", @"没有文件成功导出，请刷新文件列表后重试。")];
                return;
            }
            if (!self.view.window) {
                [self finishExportRecord:record status:WQMOperationStatusFailure bytes:0
                                 message:WQML(@"EXPORT_HISTORY_INCOMPLETE", @"导出未完成") error:@"" root:root];
                return;
            }
            record.status = WQMOperationStatusRunning;
            record.message = [NSString stringWithFormat:WQML(@"EXPORT_HISTORY_ITEMS", @"导出 %lu 项"),
                              (unsigned long)urls.count];
            record.errorMessage = failures ? [NSString stringWithFormat:
                WQML(@"EXPORT_HISTORY_FAILED", @"%lu 项未导出"), (unsigned long)failures] : @"";
            [WQMOperationStore updateRecord:record];
            [self presentExportChoiceForRoot:root record:record urls:urls];
        });
    });
}

- (void)presentExportChoiceForRoot:(NSString *)root record:(WQMOperationRecord *)record urls:(NSArray<NSURL *> *)urls
{
    NSString *message = [NSString stringWithFormat:
        WQML(@"EXPORT_CHOOSE_MESSAGE", @"已导出 %lu 项（%@）。选择保存方式；取消会删除这次导出的临时副本。"),
        (unsigned long)urls.count, WQMFormatBytes(record.bytes)];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:WQML(@"EXPORT_CHOOSE_TITLE", @"导出完成")
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:WQML(@"EXPORT_ACTION_SHARE", @"分享…")
                                             style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) {
            record.status = WQMOperationStatusCancelled;
            record.finishedAt = NSDate.date;
            [WQMOperationStore updateRecord:record];
            WQMRemoveExportRoot(root);
            return;
        }
        [self presentShareForRoot:root record:record urls:urls];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:WQML(@"EXPORT_ACTION_SAVE", @"存储到「文件」…")
                                             style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { WQMRemoveExportRoot(root); return; }
        self->_pendingRecord = record;
        self->_pendingRoot = root;
        NSURL *folder = [NSURL fileURLWithPath:root isDirectory:YES];
        UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
            initForExportingURLs:@[folder] asCopy:YES];
        picker.delegate = self;
        [self presentViewController:picker animated:YES completion:nil];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:WQML(@"CANCEL", @"取消")
                                             style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *action) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { WQMRemoveExportRoot(root); return; }
        [self finishExportRecord:record status:WQMOperationStatusCancelled bytes:0
                         message:WQML(@"EXPORT_HISTORY_CANCELLED", @"导出已取消") error:@"" root:root];
    }]];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)presentShareForRoot:(NSString *)root record:(WQMOperationRecord *)record urls:(NSArray<NSURL *> *)urls
{
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:urls applicationActivities:nil];
    share.popoverPresentationController.sourceView = self->_exportButton;
    share.popoverPresentationController.sourceRect = self->_exportButton.bounds;
    __weak typeof(self) weakSelf = self;
    share.completionWithItemsHandler = ^(UIActivityType type, BOOL completed, NSArray *items, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) {
            record.status = completed ? WQMOperationStatusSuccess : WQMOperationStatusCancelled;
            record.finishedAt = NSDate.date;
            [WQMOperationStore updateRecord:record];
            WQMRemoveExportRoot(root);
            return;
        }
        if (completed) {
            WQMOperationStatus status = record.errorMessage.length ? WQMOperationStatusFailure : WQMOperationStatusSuccess;
            [self finishExportRecord:record status:status bytes:record.bytes message:nil
                               error:record.errorMessage root:root];
        } else {
            [self finishExportRecord:record status:WQMOperationStatusCancelled bytes:0
                             message:WQML(@"EXPORT_HISTORY_CANCELLED", @"导出已取消") error:@"" root:root];
        }
    };
    [self presentViewController:share animated:YES completion:nil];
}

- (void)finishExportRecord:(WQMOperationRecord *)record
                    status:(WQMOperationStatus)status
                     bytes:(unsigned long long)bytes
                   message:(NSString *)message
                     error:(NSString *)error
                      root:(NSString *)root
{
    record.status = status;
    record.bytes = bytes;
    record.finishedAt = NSDate.date;
    if (message) record.message = message;
    record.errorMessage = error ?: @"";
    [WQMOperationStore updateRecord:record];
    WQMRemoveExportRoot(root);
    _exporting = NO;
    [self updateSelectionBar];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
    WQMOperationRecord *record = _pendingRecord;
    NSString *root = _pendingRoot;
    _pendingRecord = nil;
    _pendingRoot = nil;
    if (!record) return;
    WQMOperationStatus status = record.errorMessage.length ? WQMOperationStatusFailure : WQMOperationStatusSuccess;
    [self finishExportRecord:record status:status bytes:record.bytes message:nil
                       error:record.errorMessage root:root];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller
{
    WQMOperationRecord *record = _pendingRecord;
    NSString *root = _pendingRoot;
    _pendingRecord = nil;
    _pendingRoot = nil;
    if (!record) return;
    [self finishExportRecord:record status:WQMOperationStatusCancelled bytes:0
                     message:WQML(@"EXPORT_HISTORY_CANCELLED", @"导出已取消") error:@"" root:root];
}

@end
