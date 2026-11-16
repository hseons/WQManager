#import "WQMFilesViewController.h"
#import "WQMFileCatalog.h"
#import "WQMFilePreviewViewController.h"
#import "WQMSpaceLensViewController.h"
#import "WQMAppModel.h"
#import "WQMBackupStore.h"
#import "WQMAlertPresenter.h"
#import "WQMLanguageManager.h"
#import "WQMTheme.h"
#import "WQAccess.h"
#import "WQAccessSafety.h"
#import "WQMContainerAccess.h"
#import "WQMLongOperationBanner.h"

@interface WQMFilesViewController () <UISearchResultsUpdating>
@end
@implementation WQMFilesViewController {
    WQMAppModel *_app;
    WQMBackupRecord *_backup, *_older;
    WQMFileCatalog *_catalog;
    WQMFileCatalogCancellation *_cancellation;
    NSArray<WQMFileEntry *> *_rows;
    NSArray<NSDictionary *> *_changes, *_visibleChanges;
    NSString *_status, *_extension;
    unsigned long long _minimum;
    BOOL _exact, _loading;
    UISearchController *_search;
    NSUInteger _generation, _queryGeneration;
    dispatch_queue_t _searchQueue;
}
- (instancetype)initWithApp:(WQMAppModel *)app { if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) _app = app; return self; }
- (instancetype)initWithBackup:(WQMBackupRecord *)backup { if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) _backup = backup; return self; }
- (instancetype)initComparingOlder:(WQMBackupRecord *)older newer:(WQMBackupRecord *)newer { self = [self initWithBackup:newer]; if (self) _older = older; return self; }
- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = _older ? WQML(@"BACKUP_COMPARE", @"备份对比") : _backup ? WQML(@"BACKUP_BROWSE", @"浏览备份内容") : WQML(@"FILE_FINDER", @"文件查找");
    self.tableView.backgroundColor = WQMTheme.canvasColor;
    self.view.tintColor = WQMTheme.accentColor;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 80;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.tableView.accessibilityIdentifier = @"files.table";
    _extension = @"";
    _searchQueue = dispatch_queue_create("mumu.wqmanager.search", DISPATCH_QUEUE_SERIAL);
    _search = [[UISearchController alloc] initWithSearchResultsController:nil];
    _search.searchResultsUpdater = self;
    _search.obscuresBackgroundDuringPresentation = NO;
    _search.searchBar.placeholder = WQML(@"FILE_SEARCH_PLACEHOLDER", @"搜索文件名或相对路径");
    self.navigationItem.searchController = _search;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:_older ? WQML(@"FILE_COMPARE_EXACT", @"内容校验") : WQML(@"FILE_FILTER", @"筛选") style:UIBarButtonItemStylePlain target:self action:@selector(options)];
    self.refreshControl = [UIRefreshControl new];
    [self.refreshControl addTarget:self action:@selector(reloadFiles) forControlEvents:UIControlEventValueChanged];
    [self reloadFiles];
}
- (void)dealloc { [_cancellation cancel]; }
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; if (self.isMovingFromParentViewController) { [_cancellation cancel]; _queryGeneration++; } }
- (void)reloadFiles
{
    if (_loading) { [self.refreshControl endRefreshing]; return; }
    WQMFileCatalogCancellation *cancellation = [WQMFileCatalogCancellation new];
    if (![WQMLongOperationBanner startOperationWithTitle:WQML(@"FILE_SCANNING", @"正在读取文件索引…") status:nil cancelHandler:^{ [cancellation cancel]; }]) {
        _status = WQML(@"FILE_OPERATION_BUSY", @"请等待当前操作完成后下拉刷新。");
        [self.refreshControl endRefreshing]; [self.tableView reloadData]; return;
    }
    _cancellation = cancellation;
    NSUInteger generation = ++_generation;
    _loading = YES;
    _status = WQML(@"FILE_SCANNING", @"正在读取文件索引…");
    [self.tableView reloadData];
    WQMAppModel *app = _app;
    WQMBackupRecord *backup = _backup, *older = _older;
    BOOL exact = _exact;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSString *root = app ? app.containerPath : backup.path;
        BOOL valid = NO;
        if (app) {
            int access = WQMOpenAppContainer(app);
            valid = access >= 0;
            if (access >= 0) close(access);
        } else {
            WQMBackupRecord *fresh = [WQMBackupRecord recordAtPath:root error:nil];
            valid = fresh && [fresh.manifestFingerprint isEqual:backup.manifestFingerprint];
        }
        WQMFileCatalog *catalog = valid ? [WQMFileCatalog scanRoot:root cancellation:cancellation] : nil;
        NSArray *changes = nil;
        if (older && catalog) {
            WQMBackupRecord *fresh = [WQMBackupRecord recordAtPath:older.path error:nil];
            if (fresh && [fresh.manifestFingerprint isEqual:older.manifestFingerprint]) {
                WQMFileCatalog *before = [WQMFileCatalog scanRoot:older.path cancellation:cancellation];
                changes = [WQMFileCatalog compareOlder:before newer:catalog exact:exact cancellation:cancellation];
            }
        }
        if (app) wq_drop_grant(root);
        dispatch_async(dispatch_get_main_queue(), ^{
            [WQMLongOperationBanner.shared hide];
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || generation != self->_generation) return;
            self->_loading = NO;
            if (cancellation.cancelled) {
                self->_status = WQML(@"FILE_SCAN_CANCELLED", @"已取消，可下拉刷新重试。");
                [self.refreshControl endRefreshing]; [self.tableView reloadData]; return;
            }
            self->_catalog = catalog;
            self->_changes = changes;
            self->_status = !catalog ? WQML(@"FILE_SCAN_FAILED", @"目录已变化或访问受限，请刷新应用列表后重试。") :
                older && !changes ? WQML(@"FILE_COMPARE_INCOMPLETE", @"对比未完成：目录过大、文件变化或读取受限。未生成完整差异结论。") :
                !catalog.complete ? WQML(@"FILE_SCAN_PARTIAL", @"部分结果：达到扫描上限或部分目录读取受限。") :
                older ? (exact ? WQML(@"FILE_COMPARE_EXACT_DONE", @"按文件内容比较；新增、删除方向以较新的备份为准。") :
                                 WQML(@"FILE_COMPARE_METADATA", @"按路径、大小和修改时间比较；点击内容校验可检查同大小文件。")) :
                WQML(@"FILE_SCAN_DONE", @"按大小排序，最多显示前 1000 项。符号链接与特殊文件已跳过。");
            [self applyQuery];
            [self.refreshControl endRefreshing];
        });
    });
}
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController { [self applyQuery]; }
- (void)applyQuery
{
    NSUInteger generation = ++_queryGeneration;
    NSString *query = [_search.searchBar.text copy] ?: @"";
    NSString *extension = [_extension copy];
    unsigned long long minimum = _minimum;
    WQMFileCatalog *catalog = _catalog;
    NSArray *changes = _changes;
    BOOL comparing = _older != nil, backup = _backup != nil;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.18 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || generation != self->_queryGeneration) return;
        dispatch_async(self->_searchQueue, ^{
            NSArray *rows;
            if (comparing) {
                NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *row, NSDictionary *bindings) {
                    return !query.length || [row[@"Path"] rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound;
                }];
                rows = [changes filteredArrayUsingPredicate:predicate];
            } else {
                rows = [catalog filesMatching:query extension:extension minimumBytes:minimum limit:1000];
                if (backup) {
                    rows = [rows filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(WQMFileEntry *file, NSDictionary *bindings) { return ![file.relativePath isEqual:@"manifest.plist"]; }]];
                }
            }
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || generation != self->_queryGeneration) return;
            if (comparing) self->_visibleChanges = rows; else self->_rows = rows;
            [self.tableView reloadData];
        });
        });
    });
}
- (void)options
{
    if (_older) {
        if (_loading) return;
        UIAlertController *confirm = [UIAlertController alertControllerWithTitle:WQML(@"FILE_COMPARE_EXACT", @"内容校验") message:WQML(@"FILE_COMPARE_EXACT_MESSAGE", @"将读取同大小文件的全部内容进行 SHA-256 对比，大备份可能耗时较长。返回上一页可取消。") preferredStyle:UIAlertControllerStyleAlert];
        [confirm addAction:[UIAlertAction actionWithTitle:WQML(@"CANCEL", @"取消") style:UIAlertActionStyleCancel handler:nil]];
        [confirm addAction:[UIAlertAction actionWithTitle:WQML(@"CONTINUE", @"继续") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { self->_exact = YES; [self reloadFiles]; }]];
        [self presentViewController:confirm animated:YES completion:nil]; return;
    }
    UIAlertController *filter = [UIAlertController alertControllerWithTitle:WQML(@"FILE_FILTER", @"筛选") message:WQML(@"FILE_FILTER_MESSAGE", @"扩展名可留空；最小大小以 MB 为单位。") preferredStyle:UIAlertControllerStyleAlert];
    [filter addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = WQML(@"FILE_EXTENSION", @"扩展名，例如 mp4"); field.text = self->_extension; field.autocapitalizationType = UITextAutocapitalizationTypeNone; }];
    [filter addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = WQML(@"FILE_MINIMUM_MB", @"最小大小（MB）"); field.keyboardType = UIKeyboardTypeNumberPad; field.text = self->_minimum ? [NSString stringWithFormat:@"%llu", self->_minimum / (1024 * 1024)] : @""; }];
    [filter addAction:[UIAlertAction actionWithTitle:WQML(@"CANCEL", @"取消") style:UIAlertActionStyleCancel handler:nil]];
    [filter addAction:[UIAlertAction actionWithTitle:WQML(@"OK", @"确定") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        self->_extension = [filter.textFields[0].text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        self->_minimum = MIN(1000000LL, MAX(0LL, filter.textFields[1].text.longLongValue)) * 1024ULL * 1024ULL;
        [self applyQuery];
    }]];
    [self presentViewController:filter animated:YES completion:nil];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return MAX(1, _older ? _visibleChanges.count : _rows.count); }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (!_older) return _app ? _app.displayName : _backup.displayName;
    return [NSString stringWithFormat:@"%@ · %@ → %@", _backup.displayName,
        [NSDateFormatter localizedStringFromDate:_older.createdAt dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle],
        [NSDateFormatter localizedStringFromDate:_backup.createdAt dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle]];
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (_older) return [NSString stringWithFormat:@"%@\n%@", _status ?: @"", WQML(@"FILE_COMPARE_REGULAR_ONLY", @"比较普通文件；不包含空目录、符号链接和特殊文件。")];
    return _status;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"file"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"file"];
    cell.accessoryType = UITableViewCellAccessoryNone;
    UIListContentConfiguration *content = [cell defaultContentConfiguration];
    content.textProperties.numberOfLines = 0; content.secondaryTextProperties.numberOfLines = 0;
    if (_older && _visibleChanges.count) {
        NSDictionary *row = _visibleChanges[indexPath.row];
        NSString *kind = [row[@"Kind"] isEqual:@"added"] ? WQML(@"FILE_ADDED", @"新增") : [row[@"Kind"] isEqual:@"removed"] ? WQML(@"FILE_REMOVED", @"删除") : WQML(@"FILE_CHANGED", @"变化");
        content.text = row[@"Path"];
        content.secondaryText = [NSString stringWithFormat:@"%@ · %@ → %@", kind, WQMFormatBytes([row[@"Before"] unsignedLongLongValue]), WQMFormatBytes([row[@"After"] unsignedLongLongValue])];
    } else if (!_older && _rows.count) {
        WQMFileEntry *file = _rows[indexPath.row]; content.text = file.relativePath.lastPathComponent;
        content.secondaryText = [NSString stringWithFormat:@"%@\n%@", WQMFormatBytes(file.bytes), file.relativePath];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else { content.text = _loading ? WQML(@"FILE_SCANNING", @"正在读取文件索引…") : WQML(@"FILE_NO_RESULTS", @"没有匹配的文件或差异"); }
    content.textProperties.color = WQMTheme.textPrimaryColor; content.secondaryTextProperties.color = WQMTheme.textSecondaryColor;
    cell.contentConfiguration = content;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (_older || !_rows.count || _loading) return;
    WQMFileEntry *file = _rows[indexPath.row];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:file.relativePath.lastPathComponent message:file.relativePath preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:WQML(@"PREVIEW", @"预览") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self previewFile:file];
    }]];
    if (_app) [sheet addAction:[UIAlertAction actionWithTitle:WQML(@"FILE_OPEN_FOLDER", @"打开所在目录") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        WQMSpaceLensViewController *lens = [[WQMSpaceLensViewController alloc] initWithApp:self->_app relativePath:file.relativePath.stringByDeletingLastPathComponent];
        [self.navigationController pushViewController:lens animated:YES];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:WQML(@"CANCEL", @"取消") style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = tableView; sheet.popoverPresentationController.sourceRect = [tableView rectForRowAtIndexPath:indexPath];
    [self presentViewController:sheet animated:YES completion:nil];
}
- (void)previewFile:(WQMFileEntry *)file
{
    if (WQMLongOperationBanner.shared.busy) {
        [WQMAlertPresenter presentAlertWithTitle:WQML(@"PREVIEW", @"预览") message:WQML(@"FILE_OPERATION_BUSY", @"请等待当前操作完成后下拉刷新。")];
        return;
    }
    NSString *root = _app ? _app.containerPath : _backup.path;
    if (_app) {
        int access = WQMOpenAppContainer(_app);
        if (access < 0) { [WQMAlertPresenter presentAlertWithTitle:WQML(@"FILE_CHANGED", @"变化") message:WQML(@"FILE_SCAN_FAILED", @"目录已变化或访问受限，请刷新应用列表后重试。")]; return; }
        close(access);
    }
    NSString *path = [root stringByAppendingPathComponent:file.relativePath];
    int parent = WQOpenDirectoryNoLinks(path.stringByDeletingLastPathComponent);
    int fd = parent >= 0 ? WQOpenRegularAt(parent, path.lastPathComponent.fileSystemRepresentation, O_RDONLY, 0) : -1;
    if (parent >= 0) close(parent);
    if (fd < 0) { [WQMAlertPresenter presentAlertWithTitle:WQML(@"FILE_CHANGED", @"变化") message:WQML(@"FILE_SCAN_FAILED", @"目录已变化或访问受限，请刷新应用列表后重试。")]; return; }
    close(fd);
    [self.navigationController pushViewController:[[WQMFilePreviewViewController alloc] initWithFilePath:path name:file.relativePath.lastPathComponent] animated:YES];
}
@end
