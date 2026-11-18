#import "WQMGlobalFileSearchViewController.h"
#import "WQMAppModel.h"
#import "WQMAlertPresenter.h"
#import "WQMContainerAccess.h"
#import "WQMFileAudit.h"
#import "WQMFileCatalog.h"
#import "WQMFilePreviewViewController.h"
#import "WQMLanguageManager.h"
#import "WQMLongOperationBanner.h"
#import "WQMSpaceLensViewController.h"
#import "WQMTheme.h"
#import "WQAccess.h"

static const NSUInteger WQMGlobalSearchDisplayLimit = 300;

@interface WQMGlobalFileSearchViewController () <UISearchResultsUpdating>
@end

@implementation WQMGlobalFileSearchViewController {
    NSArray<WQMAppModel *> *_apps;
    NSDictionary<NSString *, WQMAppModel *> *_appsByBundle;
    NSMutableArray<WQMAuditFile *> *_allFiles;
    NSArray<WQMAuditFile *> *_visibleFiles;
    WQMFileCatalogCancellation *_cancellation;
    UISearchController *_searchController;
    UILabel *_summaryLabel;
    UIButton *_categoryButton;
    UIButton *_sizeButton;
    UIButton *_sortButton;
    NSString *_query;
    WQMFileCategory _category;
    unsigned long long _minimumBytes;
    WQMFileSortOrder _sortOrder;
    NSUInteger _matchedTotal;
    unsigned long long _matchedBytes;
    NSUInteger _generation;
    BOOL _scanning;
    BOOL _cancelled;
    BOOL _refreshScheduled;
}

- (instancetype)initWithApps:(NSArray<WQMAppModel *> *)apps
{
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _apps = [apps copy];
        NSMutableDictionary *byBundle = [NSMutableDictionary new];
        for (WQMAppModel *app in apps) if (app.bundleIdentifier.length) byBundle[app.bundleIdentifier] = app;
        _appsByBundle = byBundle;
        _allFiles = [NSMutableArray new];
        _visibleFiles = @[];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = WQML(@"GLOBAL_SEARCH_TITLE", @"全局文件搜索");
    self.tableView.backgroundColor = WQMTheme.canvasColor;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.contentInset = UIEdgeInsetsMake(4, 0, 82, 0);
    self.tableView.scrollIndicatorInsets = UIEdgeInsetsMake(0, 0, 82, 0);
    self.tableView.estimatedRowHeight = 84;
    self.tableView.accessibilityIdentifier = @"global-search.table";
    [self configureSearch];
    [self configureFilters];
    self.refreshControl = [UIRefreshControl new];
    [self.refreshControl addTarget:self action:@selector(refreshPulled) forControlEvents:UIControlEventValueChanged];
    [self loadFiles];
}

- (void)dealloc
{
    [_cancellation cancel];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    if (self.isMovingFromParentViewController) {
        [_cancellation cancel];
        [WQMLongOperationBanner.shared hide];
    }
}

- (void)configureSearch
{
    _searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    _searchController.searchResultsUpdater = self;
    _searchController.obscuresBackgroundDuringPresentation = NO;
    _searchController.searchBar.placeholder = WQML(@"GLOBAL_SEARCH_PLACEHOLDER", @"搜索文件名、路径或 App");
    _searchController.searchBar.searchTextField.accessibilityIdentifier = @"global-search.field";
    self.navigationItem.searchController = _searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
}

- (void)configureFilters
{
    _categoryButton = [self filterButtonWithIdentifier:@"global-search.category"];
    _sizeButton = [self filterButtonWithIdentifier:@"global-search.size"];
    _sortButton = [self filterButtonWithIdentifier:@"global-search.sort"];

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[_categoryButton, _sizeButton, _sortButton]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.distribution = UIStackViewDistributionFillEqually;
    row.spacing = 8;

    _summaryLabel = [UILabel new];
    _summaryLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    _summaryLabel.textColor = WQMTheme.textSecondaryColor;
    _summaryLabel.numberOfLines = 0;

    UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[row, _summaryLabel]];
    header.axis = UILayoutConstraintAxisVertical;
    header.spacing = 8;
    header.layoutMarginsRelativeArrangement = YES;
    header.layoutMargins = UIEdgeInsetsMake(8, 16, 8, 16);
    header.frame = CGRectMake(0, 0, self.tableView.bounds.size.width, 96);
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.tableView.tableHeaderView = header;

    [self refreshFilterMenus];
    _summaryLabel.text = WQML(@"GLOBAL_SEARCH_HINT", @"输入关键字，或选择类型/大小开始搜索。");
}

- (UIButton *)filterButtonWithIdentifier:(NSString *)identifier
{
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *configuration = [UIButtonConfiguration grayButtonConfiguration];
    configuration.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    configuration.contentInsets = NSDirectionalEdgeInsetsMake(6, 10, 6, 10);
    configuration.titleLineBreakMode = NSLineBreakByTruncatingTail;
    button.configuration = configuration;
    button.showsMenuAsPrimaryAction = YES;
    button.accessibilityIdentifier = identifier;
    [button.heightAnchor constraintEqualToConstant:32].active = YES;
    return button;
}

- (void)setTitle:(NSString *)title forFilterButton:(UIButton *)button
{
    UIButtonConfiguration *configuration = button.configuration;
    configuration.title = title;
    button.configuration = configuration;
}

- (void)refreshFilterMenus
{
    _categoryButton.menu = [self categoryMenu];
    _sizeButton.menu = [self sizeMenu];
    _sortButton.menu = [self sortMenu];

    NSArray<NSString *> *categoryTitles = @[
        WQML(@"EXPORT_CATEGORY_ALL", @"全部"),
        WQML(@"EXPORT_CATEGORY_IMAGE", @"图片"),
        WQML(@"EXPORT_CATEGORY_VIDEO", @"视频"),
        WQML(@"EXPORT_CATEGORY_AUDIO", @"音频"),
        WQML(@"EXPORT_CATEGORY_DOCUMENT", @"文档"),
        WQML(@"EXPORT_CATEGORY_ARCHIVE", @"压缩包"),
    ];
    [self setTitle:categoryTitles[(NSUInteger)_category] forFilterButton:_categoryButton];
    _categoryButton.accessibilityLabel = WQML(@"GLOBAL_SEARCH_FILTER_TYPE", @"类型");
    _categoryButton.accessibilityValue = categoryTitles[(NSUInteger)_category];

    [self setTitle:(_minimumBytes ? [self sizeTitleForBytes:_minimumBytes] : WQML(@"GLOBAL_SEARCH_SIZE_ANY", @"不限"))
        forFilterButton:_sizeButton];
    _sizeButton.accessibilityLabel = WQML(@"GLOBAL_SEARCH_FILTER_SIZE", @"大小");

    NSArray<NSString *> *sortTitles = @[
        WQML(@"GLOBAL_SEARCH_SORT_PATH", @"路径"),
        WQML(@"LENS_SORT_SIZE", @"大小"),
        WQML(@"GLOBAL_SEARCH_SORT_NEWEST", @"最新"),
    ];
    [self setTitle:sortTitles[(NSUInteger)_sortOrder] forFilterButton:_sortButton];
    _sortButton.accessibilityLabel = WQML(@"GLOBAL_SEARCH_FILTER_SORT", @"排序");
    _sortButton.accessibilityValue = sortTitles[(NSUInteger)_sortOrder];
}

- (NSString *)sizeTitleForBytes:(unsigned long long)bytes
{
    return [NSString stringWithFormat:@"≥ %@", WQMFormatBytes(bytes)];
}

- (UIMenu *)categoryMenu
{
    __weak typeof(self) weakSelf = self;
    NSArray<NSString *> *titles = @[
        WQML(@"EXPORT_CATEGORY_ALL", @"全部"),
        WQML(@"EXPORT_CATEGORY_IMAGE", @"图片"),
        WQML(@"EXPORT_CATEGORY_VIDEO", @"视频"),
        WQML(@"EXPORT_CATEGORY_AUDIO", @"音频"),
        WQML(@"EXPORT_CATEGORY_DOCUMENT", @"文档"),
        WQML(@"EXPORT_CATEGORY_ARCHIVE", @"压缩包"),
    ];
    NSMutableArray<UIAction *> *actions = [NSMutableArray new];
    for (NSUInteger index = 0; index < titles.count; index++) {
        WQMFileCategory category = (WQMFileCategory)index;
        UIAction *action = [UIAction actionWithTitle:titles[index] image:nil identifier:nil handler:^(__unused UIAction *selected) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self->_category = category;
            [self refreshFilterMenus];
            [self reapplyFilter];
        }];
        action.state = _category == category ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:action];
    }
    return [UIMenu menuWithTitle:WQML(@"GLOBAL_SEARCH_FILTER_TYPE", @"类型") children:actions];
}

- (UIMenu *)sizeMenu
{
    __weak typeof(self) weakSelf = self;
    NSArray<NSNumber *> *values = @[@0, @(1ULL * 1024ULL * 1024ULL), @(10ULL * 1024ULL * 1024ULL),
                                    @(100ULL * 1024ULL * 1024ULL)];
    NSMutableArray<UIAction *> *actions = [NSMutableArray new];
    for (NSNumber *value in values) {
        unsigned long long bytes = value.unsignedLongLongValue;
        NSString *title = bytes ? [self sizeTitleForBytes:bytes] : WQML(@"GLOBAL_SEARCH_SIZE_ANY", @"不限");
        UIAction *action = [UIAction actionWithTitle:title image:nil identifier:nil handler:^(__unused UIAction *selected) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self->_minimumBytes = bytes;
            [self refreshFilterMenus];
            [self reapplyFilter];
        }];
        action.state = _minimumBytes == bytes ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:action];
    }
    return [UIMenu menuWithTitle:WQML(@"GLOBAL_SEARCH_FILTER_SIZE", @"大小") children:actions];
}

- (UIMenu *)sortMenu
{
    __weak typeof(self) weakSelf = self;
    NSArray<NSString *> *titles = @[
        WQML(@"GLOBAL_SEARCH_SORT_PATH", @"路径"),
        WQML(@"LENS_SORT_SIZE", @"大小"),
        WQML(@"GLOBAL_SEARCH_SORT_NEWEST", @"最新"),
    ];
    NSMutableArray<UIAction *> *actions = [NSMutableArray new];
    for (NSUInteger index = 0; index < titles.count; index++) {
        WQMFileSortOrder order = (WQMFileSortOrder)index;
        UIAction *action = [UIAction actionWithTitle:titles[index] image:nil identifier:nil handler:^(__unused UIAction *selected) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self->_sortOrder = order;
            [self refreshFilterMenus];
            [self reapplyFilter];
        }];
        action.state = _sortOrder == order ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:action];
    }
    return [UIMenu menuWithTitle:WQML(@"GLOBAL_SEARCH_FILTER_SORT", @"排序") children:actions];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController
{
    _query = [searchController.searchBar.text copy];
    [self reapplyFilter];
}

- (BOOL)hasActiveQuery
{
    NSString *trimmed = [_query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return trimmed.length > 0 || _category != WQMFileCategoryAll || _minimumBytes > 0;
}

- (void)refreshPulled
{
    [self loadFiles];
}

- (void)loadFiles
{
    if (_scanning) {
        [self.refreshControl endRefreshing];
        return;
    }
    WQMFileCatalogCancellation *cancellation = [WQMFileCatalogCancellation new];
    if (![WQMLongOperationBanner startOperationWithTitle:WQML(@"GLOBAL_SEARCH_SCANNING", @"正在扫描可访问的 App…")
        status:nil cancelHandler:^{ [cancellation cancel]; }]) {
        [self.refreshControl endRefreshing];
        _summaryLabel.text = WQML(@"GLOBAL_SEARCH_BUSY", @"另一个操作正在进行，请稍后再试。");
        [self.tableView reloadData];
        return;
    }
    _cancellation = cancellation;
    _scanning = YES;
    _cancelled = NO;
    _generation += 1;
    NSUInteger generation = _generation;
    [_allFiles removeAllObjects];
    _visibleFiles = @[];
    _matchedTotal = 0;
    _matchedBytes = 0;
    [self updateSummary];
    [self.tableView reloadData];

    NSArray<WQMAppModel *> *apps = [_apps copy];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        for (NSUInteger index = 0; index < apps.count; index++) {
            if (cancellation.cancelled) break;
            WQMAppModel *app = apps[index];
            dispatch_async(dispatch_get_main_queue(), ^{
                [WQMLongOperationBanner.shared updateStatus:[NSString stringWithFormat:
                    WQML(@"GLOBAL_SEARCH_PROGRESS", @"正在扫描 %lu/%lu · %@"),
                    (unsigned long)(index + 1), (unsigned long)apps.count, app.displayName]];
            });
            if (!app.bundleIdentifier.length || !app.accessAvailable || !app.identityKnown) continue;
            int access = WQMOpenAppContainer(app);
            WQMFileCatalog *catalog = access >= 0 ? [WQMFileCatalog scanRoot:app.containerPath cancellation:cancellation] : nil;
            if (access >= 0) close(access);
            NSArray<WQMAuditFile *> *files = nil;
            if (catalog) {
                files = [WQMFileAudit filesFromCatalog:catalog appName:app.displayName
                                     bundleIdentifier:app.bundleIdentifier
                                        containerPath:app.containerPath includeCaches:NO];
            }
            wq_drop_grant(app.containerPath);
            if (!files.count) continue;
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) self = weakSelf;
                if (!self || generation != self->_generation) return;
                [self->_allFiles addObjectsFromArray:files];
                [self scheduleRefresh];
            });
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || generation != self->_generation) return;
            [WQMLongOperationBanner.shared hide];
            [self.refreshControl endRefreshing];
            self->_scanning = NO;
            self->_cancelled = cancellation.cancelled;
            self->_cancellation = nil;
            [self reapplyFilter];
        });
    });
}

- (void)scheduleRefresh
{
    if (_refreshScheduled) return;
    _refreshScheduled = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self->_refreshScheduled = NO;
        [self reapplyFilter];
    });
}

- (void)reapplyFilter
{
    NSArray<WQMAuditFile *> *matched = [WQMFileAudit searchFiles:_allFiles query:_query category:_category
        minimumBytes:_minimumBytes sort:_sortOrder limit:0];
    _matchedTotal = matched.count;
    unsigned long long bytes = 0;
    for (WQMAuditFile *file in matched) bytes += file.bytes;
    _matchedBytes = bytes;
    if (![self hasActiveQuery]) {
        _visibleFiles = @[];
    } else if (matched.count > WQMGlobalSearchDisplayLimit) {
        _visibleFiles = [matched subarrayWithRange:NSMakeRange(0, WQMGlobalSearchDisplayLimit)];
    } else {
        _visibleFiles = matched;
    }
    [self updateSummary];
    [self.tableView reloadData];
}

- (void)updateSummary
{
    if (_scanning) {
        if (![self hasActiveQuery]) {
            _summaryLabel.text = WQML(@"GLOBAL_SEARCH_SCANNING", @"正在扫描可访问的 App…");
        } else {
            _summaryLabel.text = [NSString stringWithFormat:
                WQML(@"GLOBAL_SEARCH_FOUND", @"已找到 %lu 个文件 · 正在扫描…"), (unsigned long)_matchedTotal];
        }
        return;
    }
    if (_cancelled) {
        _summaryLabel.text = WQML(@"GLOBAL_SEARCH_CANCELLED", @"扫描已取消。");
        return;
    }
    if (![self hasActiveQuery]) {
        _summaryLabel.text = WQML(@"GLOBAL_SEARCH_HINT", @"输入关键字，或选择类型/大小开始搜索。");
        return;
    }
    if (!_matchedTotal) {
        _summaryLabel.text = WQML(@"GLOBAL_SEARCH_EMPTY", @"没有匹配的文件。");
        return;
    }
    if (_matchedTotal > _visibleFiles.count) {
        _summaryLabel.text = [NSString stringWithFormat:
            WQML(@"GLOBAL_SEARCH_LIMIT", @"显示前 %lu 个 · 共 %lu 个匹配"),
            (unsigned long)_visibleFiles.count, (unsigned long)_matchedTotal];
        return;
    }
    _summaryLabel.text = [NSString stringWithFormat:
        WQML(@"GLOBAL_SEARCH_SUMMARY", @"%lu 个文件 · 共 %@"),
        (unsigned long)_matchedTotal, WQMFormatBytes(_matchedBytes)];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return MAX(1, (NSInteger)_visibleFiles.count);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"global-search"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"global-search"];
    UIListContentConfiguration *content = [cell defaultContentConfiguration];
    content.textProperties.numberOfLines = 0;
    content.secondaryTextProperties.numberOfLines = 2;

    if (!_visibleFiles.count) {
        cell.accessibilityIdentifier = @"global-search.empty";
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryType = UITableViewCellAccessoryNone;
        if (_scanning) {
            content.text = WQML(@"GLOBAL_SEARCH_SCANNING", @"正在扫描可访问的 App…");
            content.secondaryText = WQML(@"GLOBAL_SEARCH_SCANNING_SUB", @"匹配的文件会随着扫描实时出现。");
        } else if (![self hasActiveQuery]) {
            content.text = WQML(@"GLOBAL_SEARCH_HINT", @"输入关键字，或选择类型/大小开始搜索。");
            content.secondaryText = WQML(@"GLOBAL_SEARCH_HINT_SUB", @"可按文件名、路径或 App 名称搜索。");
        } else {
            content.text = WQML(@"GLOBAL_SEARCH_EMPTY", @"没有匹配的文件。");
            content.secondaryText = WQML(@"GLOBAL_SEARCH_EMPTY_SUB", @"试试更短的关键字，或放宽类型与大小筛选。");
        }
        content.image = [UIImage systemImageNamed:@"magnifyingglass"];
    } else {
        cell.accessibilityIdentifier = [NSString stringWithFormat:@"global-search.file.%ld", (long)indexPath.row];
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        WQMAuditFile *file = _visibleFiles[(NSUInteger)indexPath.row];
        content.text = file.relativePath.lastPathComponent;
        content.secondaryText = [NSString stringWithFormat:@"%@ · %@\n%@",
            WQMFormatBytes(file.bytes), file.appName, file.relativePath];
        content.image = [UIImage systemImageNamed:[self symbolNameForCategory:file.category]];
    }
    content.textProperties.color = WQMTheme.textPrimaryColor;
    content.secondaryTextProperties.color = WQMTheme.textSecondaryColor;
    content.imageProperties.tintColor = WQMTheme.accentColor;
    cell.backgroundColor = WQMTheme.surfaceColor;
    cell.contentConfiguration = content;
    return cell;
}

- (NSString *)symbolNameForCategory:(WQMFileCategory)category
{
    switch (category) {
        case WQMFileCategoryImage: return @"photo";
        case WQMFileCategoryVideo: return @"film";
        case WQMFileCategoryAudio: return @"waveform";
        case WQMFileCategoryDocument: return @"doc.text";
        case WQMFileCategoryArchive: return @"archivebox";
        default: return @"doc";
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (!_visibleFiles.count) return;
    [self presentActionsForFile:_visibleFiles[(NSUInteger)indexPath.row] indexPath:indexPath];
}

- (void)presentActionsForFile:(WQMAuditFile *)file indexPath:(NSIndexPath *)indexPath
{
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:file.relativePath.lastPathComponent
                                                                  message:file.relativePath
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    WQMAppModel *app = _appsByBundle[file.bundleIdentifier];
    [sheet addAction:[UIAlertAction actionWithTitle:WQML(@"PREVIEW", @"预览") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
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
    if (app) {
        [sheet addAction:[UIAlertAction actionWithTitle:WQML(@"FILE_OPEN_FOLDER", @"打开所在目录") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            WQMSpaceLensViewController *lens = [[WQMSpaceLensViewController alloc]
                initWithApp:app relativePath:file.relativePath.stringByDeletingLastPathComponent];
            [self.navigationController pushViewController:lens animated:YES];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:WQML(@"CANCEL", @"取消") style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.tableView;
    sheet.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:indexPath];
    [self presentViewController:sheet animated:YES completion:nil];
}

@end
