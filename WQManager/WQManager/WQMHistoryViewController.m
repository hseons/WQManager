#import "WQMHistoryViewController.h"
#import "WQMLanguageManager.h"
#import "WQMOperationStore.h"
#import "WQMSafetyPolicy.h"
#import "WQMTheme.h"

static NSString *WQMHistoryLocalizedScope(NSString *scope)
{
    if ([scope isEqualToString:@"快速备份"] || [scope isEqualToString:@"Quick Backup"]) {
        return WQML(@"QUICK_BACKUP", @"快速备份");
    }
    if ([scope isEqualToString:@"完整备份"] || [scope isEqualToString:@"Full Backup"]) {
        return WQML(@"FULL_BACKUP", @"完整备份");
    }
    if ([scope isEqualToString:@"自定义"] || [scope isEqualToString:@"Custom Backup"]) {
        return WQML(@"CUSTOM_BACKUP", @"自定义备份");
    }
    if ([scope isEqualToString:@"Library/Caches、tmp"] ||
        [scope isEqualToString:@"Library/Caches, tmp"]) {
        return WQML(@"CLEAN_SCOPE_SHORT", @"Library/Caches、tmp");
    }
    return scope;
}

static NSString *WQMHistoryLocalizedMessage(NSString *message)
{
    NSDictionary<NSString *, NSString *> *translations = @{
        @"缓存已清理": @"CLEAN_SUCCESS_MESSAGE",
        @"Cache cleaned": @"CLEAN_SUCCESS_MESSAGE",
        @"部分缓存未能删除": @"CLEAN_PARTIAL_MESSAGE",
        @"Some caches could not be deleted": @"CLEAN_PARTIAL_MESSAGE",
        @"导出失败": @"ARCHIVE_EXPORT_FAILED",
        @"Export failed": @"ARCHIVE_EXPORT_FAILED",
        @"备份包已生成": @"ARCHIVE_EXPORTED",
        @"Backup package created": @"ARCHIVE_EXPORTED",
        @"导入失败": @"ARCHIVE_IMPORT_FAILED",
        @"Import failed": @"ARCHIVE_IMPORT_FAILED",
        @"备份已导入": @"ARCHIVE_IMPORTED",
        @"Backup imported": @"ARCHIVE_IMPORTED",
        @"删除备份失败": @"ARCHIVE_DELETE_FAILED",
        @"Could not delete backup": @"ARCHIVE_DELETE_FAILED",
        @"备份已删除": @"ARCHIVE_DELETED",
        @"Backup deleted": @"ARCHIVE_DELETED",
        @"上次运行在操作完成前结束": @"OPERATION_INTERRUPTED_PREVIOUS",
        @"The previous run ended before the operation completed": @"OPERATION_INTERRUPTED_PREVIOUS",
    };
    NSString *key = translations[message];
    return key ? WQML(key, message) : message;
}

typedef NS_ENUM(NSInteger, WQMHistoryFilter) {
    WQMHistoryFilterAll = 0,
    WQMHistoryFilterSuccess,
    WQMHistoryFilterFailure,
    WQMHistoryFilterRollback,
};

@interface WQMHistoryCell : UITableViewCell
@property (nonatomic, strong) WQMSoftSurfaceView *cardView;
@property (nonatomic, strong) UIListContentView *listContentView;
- (void)configureWithOperation:(WQMOperationRecord *)operation indented:(BOOL)indented;
- (void)configureWithGroupKind:(WQMOperationKind)kind
                         count:(NSUInteger)count
                         bytes:(unsigned long long)bytes
                        latest:(NSDate *)latest
                      expanded:(BOOL)expanded;
@end

@implementation WQMHistoryCell {
    UIImageView *_chevronView;
    NSLayoutConstraint *_cardWidthConstraint;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.clipsToBounds = NO;
        self.contentView.clipsToBounds = NO;

        _cardView = [[WQMSoftSurfaceView alloc] initWithElevated:NO];
        _cardView.layer.cornerRadius = 20;
        _cardView.translatesAutoresizingMaskIntoConstraints = NO;

        UIListContentConfiguration *configuration = [UIListContentConfiguration subtitleCellConfiguration];
        configuration.imageProperties.maximumSize = CGSizeMake(34, 34);
        configuration.imageProperties.reservedLayoutSize = CGSizeMake(34, 34);
        configuration.textProperties.numberOfLines = 2;
        configuration.textToSecondaryTextVerticalPadding = 2;
        _listContentView = [[UIListContentView alloc] initWithConfiguration:configuration];
        _listContentView.translatesAutoresizingMaskIntoConstraints = NO;
        _listContentView.directionalLayoutMargins = NSDirectionalEdgeInsetsZero;
        [_cardView addSubview:_listContentView];

        _chevronView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.down"]];
        _chevronView.translatesAutoresizingMaskIntoConstraints = NO;
        _chevronView.contentMode = UIViewContentModeCenter;
        _chevronView.tintColor = WQMTheme.textSecondaryColor;
        _chevronView.preferredSymbolConfiguration =
            [UIImageSymbolConfiguration configurationWithPointSize:13
                                                            weight:UIImageSymbolWeightSemibold];
        [_cardView addSubview:_chevronView];
        [self.contentView addSubview:_cardView];

        _cardWidthConstraint = [_cardView.widthAnchor constraintEqualToAnchor:self.contentView.widthAnchor
                                                                     constant:-24];
        _cardWidthConstraint.priority = 999;
        [NSLayoutConstraint activateConstraints:@[
            [_cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:5],
            [_cardView.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
            [_cardView.widthAnchor constraintLessThanOrEqualToConstant:760],
            _cardWidthConstraint,
            [_cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-5],
            [_listContentView.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:9],
            [_listContentView.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:14],
            [_listContentView.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-30],
            [_listContentView.bottomAnchor constraintEqualToAnchor:_cardView.bottomAnchor constant:-9],
            [_cardView.heightAnchor constraintGreaterThanOrEqualToConstant:64],
            [_chevronView.centerYAnchor constraintEqualToAnchor:_cardView.centerYAnchor],
            [_chevronView.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-12],
            [_chevronView.widthAnchor constraintEqualToConstant:16],
            [_chevronView.heightAnchor constraintEqualToConstant:16],
        ]];
    }
    return self;
}

- (void)configureWithOperation:(WQMOperationRecord *)operation indented:(BOOL)indented
{
    _chevronView.hidden = YES;
    _cardWidthConstraint.constant = indented ? -56 : -24;
    UIListContentConfiguration *configuration = (UIListContentConfiguration *)self.listContentView.configuration;
    NSString *kind = [WQMOperationRecord displayNameForKind:operation.kind];
    NSString *status = [WQMOperationRecord displayNameForStatus:operation.status];
    configuration.text = [NSString stringWithFormat:@"%@ · %@", kind, operation.appName];

    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [WQMLanguageManager sharedManager].locale;
    formatter.dateStyle = NSDateFormatterNoStyle;
    formatter.timeStyle = NSDateFormatterShortStyle;
    NSMutableArray<NSString *> *details = [NSMutableArray new];
    if (operation.scope.length) [details addObject:WQMHistoryLocalizedScope(operation.scope)];
    if (operation.bytes > 0) {
        [details addObject:WQMFormatBytes(operation.bytes)];
    }
    [details addObject:[formatter stringFromDate:operation.startedAt]];
    [details addObject:status];
    configuration.secondaryText = [details componentsJoinedByString:@" · "];

    configuration.textProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    configuration.textProperties.color = WQMTheme.textPrimaryColor;
    configuration.secondaryTextProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    configuration.secondaryTextProperties.color =
        operation.status == WQMOperationStatusFailure ? WQMTheme.dangerColor : WQMTheme.textSecondaryColor;

    NSString *symbol = @"clock";
    switch (operation.kind) {
        case WQMOperationKindBackup: symbol = @"arrow.up.doc.fill"; break;
        case WQMOperationKindSafetyBackup: symbol = @"shield.fill"; break;
        case WQMOperationKindRestore: symbol = @"arrow.triangle.2.circlepath"; break;
        case WQMOperationKindRollback: symbol = @"arrow.uturn.backward.circle.fill"; break;
        case WQMOperationKindRecovery: symbol = @"wrench.and.screwdriver.fill"; break;
        case WQMOperationKindExport: symbol = @"square.and.arrow.up"; break;
        case WQMOperationKindImport: symbol = @"square.and.arrow.down"; break;
        case WQMOperationKindDeleteBackup: symbol = @"trash.fill"; break;
        case WQMOperationKindCleanCache: symbol = @"trash"; break;
    }
    configuration.image = [UIImage systemImageNamed:symbol];
    configuration.imageProperties.tintColor = WQMTheme.textPrimaryColor;
    configuration.imageProperties.maximumSize = CGSizeMake(indented ? 28 : 34, indented ? 28 : 34);
    configuration.imageProperties.reservedLayoutSize = CGSizeMake(indented ? 28 : 34, indented ? 28 : 34);
    configuration.textProperties.font = [UIFont preferredFontForTextStyle:
        indented ? UIFontTextStyleSubheadline : UIFontTextStyleHeadline];
    self.listContentView.configuration = configuration;
    self.accessibilityLabel = [NSString stringWithFormat:@"%@，%@", configuration.text, configuration.secondaryText];
}

- (void)configureWithGroupKind:(WQMOperationKind)kind
                         count:(NSUInteger)count
                         bytes:(unsigned long long)bytes
                        latest:(NSDate *)latest
                      expanded:(BOOL)expanded
{
    _chevronView.hidden = NO;
    _cardWidthConstraint.constant = -24;
    UIListContentConfiguration *configuration = (UIListContentConfiguration *)self.listContentView.configuration;
    NSString *kindName = [WQMOperationRecord displayNameForKind:kind];
    configuration.text = [NSString stringWithFormat:WQML(@"HISTORY_GROUP_TITLE", @"%@ · %lu 次"),
                          kindName, (unsigned long)count];
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [WQMLanguageManager sharedManager].locale;
    formatter.dateStyle = NSDateFormatterNoStyle;
    formatter.timeStyle = NSDateFormatterShortStyle;
    NSString *latestText = [formatter stringFromDate:latest];
    configuration.secondaryText = (bytes > 0)
        ? [NSString stringWithFormat:WQML(@"HISTORY_GROUP_SUMMARY", @"共 %@ · 最近 %@"),
           WQMFormatBytes(bytes), latestText]
        : [NSString stringWithFormat:WQML(@"HISTORY_GROUP_SUMMARY_PLAIN", @"最近 %@"), latestText];
    configuration.textProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    configuration.textProperties.color = WQMTheme.textPrimaryColor;
    configuration.secondaryTextProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    configuration.secondaryTextProperties.color = WQMTheme.textSecondaryColor;
    configuration.image = [UIImage systemImageNamed:@"square.stack.3d.up.fill"];
    configuration.imageProperties.maximumSize = CGSizeMake(34, 34);
    configuration.imageProperties.reservedLayoutSize = CGSizeMake(34, 34);
    configuration.imageProperties.tintColor = WQMTheme.textPrimaryColor;
    self.listContentView.configuration = configuration;
    _chevronView.transform = expanded ? CGAffineTransformMakeRotation((CGFloat)M_PI)
                                      : CGAffineTransformIdentity;
    self.accessibilityLabel = [NSString stringWithFormat:@"%@，%@", configuration.text, configuration.secondaryText];
}

@end

@implementation WQMHistoryViewController {
    NSArray<NSDictionary *> *_sections;
    NSArray<WQMOperationRecord *> *_operations;
    UISearchBar *_searchBar;
    UIView *_searchHeader;
    NSString *_query;
    WQMHistoryFilter _filter;
    NSUInteger _loadGeneration;
    WQMConfirmationGate *_clearGate;
    NSMutableSet<NSString *> *_expandedKeys;
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
    self.title = WQML(@"TAB_HISTORY", @"记录");
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.tableView.backgroundColor = WQMTheme.canvasColor;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 76;
    self.tableView.cellLayoutMarginsFollowReadableWidth = YES;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;

    _searchHeader = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 56)];
    _searchBar = [[UISearchBar alloc] initWithFrame:CGRectInset(_searchHeader.bounds, 12, 4)];
    _searchBar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _searchBar.searchBarStyle = UISearchBarStyleMinimal;
    _searchBar.placeholder = WQML(@"HISTORY_SEARCH", @"搜索 App 或操作");
    _searchBar.delegate = self;
    _searchBar.searchTextField.backgroundColor = WQMTheme.surfaceColor;
    _searchBar.searchTextField.layer.cornerRadius = 17;
    _searchBar.searchTextField.layer.cornerCurve = kCACornerCurveContinuous;
    _searchBar.searchTextField.clipsToBounds = YES;
    [_searchHeader addSubview:_searchBar];
    self.tableView.tableHeaderView = _searchHeader;
    UITapGestureRecognizer *dismissTap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard:)];
    dismissTap.cancelsTouchesInView = NO;
    dismissTap.delegate = self;
    [self.tableView addGestureRecognizer:dismissTap];

    [self updateFilterButton];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(reloadOperations)
                                               name:WQMOperationStoreDidChangeNotification
                                             object:nil];
    [self reloadOperations];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self dismissSearchKeyboard];
}

- (void)dismissKeyboard:(__unused UITapGestureRecognizer *)gesture
{
    [self dismissSearchKeyboard];
}

- (void)dismissSearchKeyboard
{
    [self.view endEditing:YES];
    [_searchBar resignFirstResponder];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
       shouldReceiveTouch:(UITouch *)touch
{
    if (gestureRecognizer.view == self.tableView &&
        [touch.view isDescendantOfView:_searchBar]) {
        return NO;
    }
    return YES;
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    CGRect frame = _searchHeader.frame;
    frame.size.width = self.tableView.bounds.size.width;
    frame.size.height = 56;
    _searchHeader.frame = frame;
    _searchBar.frame = CGRectInset(_searchHeader.bounds, 12, 4);
    if (self.tableView.tableHeaderView != _searchHeader) {
        self.tableView.tableHeaderView = _searchHeader;
    }
}

- (void)updateFilterButton
{
    NSString *title = _filter == WQMHistoryFilterAll ? WQML(@"HISTORY_FILTER", @"筛选")
        : _filter == WQMHistoryFilterSuccess ? WQML(@"HISTORY_SUCCESS", @"成功")
        : _filter == WQMHistoryFilterFailure ? WQML(@"HISTORY_FAILURE", @"失败")
        : WQML(@"HISTORY_ROLLED_BACK", @"已回滚");
    __weak typeof(self) weakSelf = self;
    UIMenu *menu = [UIMenu menuWithChildren:@[
        [UIAction actionWithTitle:WQML(@"HISTORY_ALL", @"全部") image:[UIImage systemImageNamed:@"tray.full"]
                       identifier:nil handler:^(__unused UIAction *action) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self->_filter = WQMHistoryFilterAll;
            [self updateFilterButton];
            [self rebuildSections];
        }],
        [UIAction actionWithTitle:WQML(@"HISTORY_SUCCESS", @"成功") image:[UIImage systemImageNamed:@"checkmark.circle"]
                       identifier:nil handler:^(__unused UIAction *action) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self->_filter = WQMHistoryFilterSuccess;
            [self updateFilterButton];
            [self rebuildSections];
        }],
        [UIAction actionWithTitle:WQML(@"HISTORY_FAILURE", @"失败") image:[UIImage systemImageNamed:@"xmark.circle"]
                       identifier:nil handler:^(__unused UIAction *action) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self->_filter = WQMHistoryFilterFailure;
            [self updateFilterButton];
            [self rebuildSections];
        }],
        [UIAction actionWithTitle:WQML(@"HISTORY_ROLLED_BACK", @"已回滚") image:[UIImage systemImageNamed:@"arrow.uturn.backward.circle"]
                       identifier:nil handler:^(__unused UIAction *action) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self->_filter = WQMHistoryFilterRollback;
            [self updateFilterButton];
            [self rebuildSections];
        }],
    ]];
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    [button setImage:[UIImage systemImageNamed:@"line.3.horizontal.decrease.circle"] forState:UIControlStateNormal];
    [button addTarget:self action:@selector(searchControlTouched)
     forControlEvents:UIControlEventTouchDown];
    button.menu = menu;
    button.showsMenuAsPrimaryAction = YES;
    UIBarButtonItem *filterItem = [[UIBarButtonItem alloc] initWithCustomView:button];
    UIButton *moreButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [moreButton setImage:[UIImage systemImageNamed:@"ellipsis.circle"] forState:UIControlStateNormal];
    [moreButton addTarget:self action:@selector(searchControlTouched)
         forControlEvents:UIControlEventTouchDown];
    moreButton.menu = [UIMenu menuWithChildren:@[
        [UIAction actionWithTitle:WQML(@"HISTORY_EXPAND_ALL", @"展开全部分组")
                            image:[UIImage systemImageNamed:@"chevron.down.circle"]
                       identifier:nil handler:^(__unused UIAction *action) {
            __strong typeof(weakSelf) self = weakSelf;
            [self expandAllGroups];
        }],
        [UIAction actionWithTitle:WQML(@"HISTORY_COLLAPSE_ALL", @"收起全部分组")
                            image:[UIImage systemImageNamed:@"chevron.up.circle"]
                       identifier:nil handler:^(__unused UIAction *action) {
            __strong typeof(weakSelf) self = weakSelf;
            [self collapseAllGroups];
        }],
        [UIAction actionWithTitle:WQML(@"CLEAR_HISTORY", @"清空记录") image:[UIImage systemImageNamed:@"trash"]
                       identifier:nil handler:^(__unused UIAction *action) {
            [weakSelf confirmClearHistory];
        }]
    ]];
    moreButton.showsMenuAsPrimaryAction = YES;
    UIBarButtonItem *moreItem = [[UIBarButtonItem alloc] initWithCustomView:moreButton];
    self.navigationItem.rightBarButtonItems = @[moreItem, filterItem];
}

- (void)searchControlTouched
{
    [self dismissSearchKeyboard];
}

- (void)expandAllGroups
{
    for (NSDictionary *section in _sections) {
        for (NSDictionary *row in section[@"items"]) {
            if ([row[@"type"] isEqualToString:@"group"]) [_expandedKeys addObject:row[@"key"]];
        }
    }
    [self rebuildSections];
}

- (void)collapseAllGroups
{
    [_expandedKeys removeAllObjects];
    [self rebuildSections];
}

- (void)confirmClearHistory
{
    if (!_operations.count) return;
    _clearGate = [WQMConfirmationGate new];
    NSString *operation = [@"clear-history:" stringByAppendingString:NSUUID.UUID.UUIDString];
    if (![_clearGate beginForOperation:operation]) return;
    UIAlertController *scope = [UIAlertController
        alertControllerWithTitle:WQML(@"CLEAR_HISTORY_TITLE", @"清空操作记录")
                         message:WQML(@"CLEAR_HISTORY_MESSAGE",
                                      @"将删除全部操作历史，不会删除备份、安全备份或恢复日志。")
                  preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [scope addAction:[UIAlertAction actionWithTitle:WQML(@"CANCEL", @"取消") style:UIAlertActionStyleCancel
                                            handler:^(__unused UIAlertAction *action) {
        __strong typeof(weakSelf) self = weakSelf;
        [self->_clearGate cancel];
    }]];
    [scope addAction:[UIAlertAction actionWithTitle:WQML(@"CONTINUE", @"继续") style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || ![self->_clearGate acknowledgeScopeForOperation:operation]) return;
        UIAlertController *final = [UIAlertController
            alertControllerWithTitle:WQML(@"FINAL_CONFIRM_TITLE", @"最终确认")
                             message:WQML(@"CLEAR_HISTORY_FINAL_MESSAGE", @"操作记录清除后无法恢复。")
                      preferredStyle:UIAlertControllerStyleAlert];
        [final addAction:[UIAlertAction actionWithTitle:WQML(@"CANCEL", @"取消") style:UIAlertActionStyleCancel
                                                handler:^(__unused UIAlertAction *a) {
            [self->_clearGate cancel];
        }]];
        [final addAction:[UIAlertAction actionWithTitle:WQML(@"CLEAR_HISTORY", @"清空记录") style:UIAlertActionStyleDestructive
                                                handler:^(__unused UIAlertAction *a) {
            if (![self->_clearGate authorizeExecutionForOperation:operation]) return;
            [WQMOperationStore clear];
        }]];
        [self presentViewController:final animated:YES completion:nil];
    }]];
    [self presentViewController:scope animated:YES completion:nil];
}

- (void)reloadOperations
{
    NSUInteger generation = ++_loadGeneration;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<WQMOperationRecord *> *operations = [WQMOperationStore allOperations];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self->_loadGeneration) return;
            self->_operations = operations;
            [self rebuildSections];
        });
    });
}

- (NSArray<NSDictionary *> *)buildSections
{
    NSArray<WQMOperationRecord *> *filtered = [_operations filteredArrayUsingPredicate:
        [NSPredicate predicateWithBlock:^BOOL(WQMOperationRecord *record, NSDictionary *__unused bindings) {
            BOOL matchesText = !self->_query.length ||
                [record.appName localizedCaseInsensitiveContainsString:self->_query] ||
                [record.bundleIdentifier localizedCaseInsensitiveContainsString:self->_query] ||
                [[WQMOperationRecord displayNameForKind:record.kind] localizedCaseInsensitiveContainsString:self->_query];
            BOOL matchesFilter = self->_filter == WQMHistoryFilterAll ||
                (self->_filter == WQMHistoryFilterSuccess && record.status == WQMOperationStatusSuccess) ||
                (self->_filter == WQMHistoryFilterFailure &&
                 (record.status == WQMOperationStatusFailure || record.status == WQMOperationStatusInterrupted)) ||
                (self->_filter == WQMHistoryFilterRollback && record.status == WQMOperationStatusRolledBack);
            return matchesText && matchesFilter;
        }]];
    if (!_expandedKeys) _expandedKeys = [NSMutableSet new];
#if DEBUG
    BOOL expandAll = NSProcessInfo.processInfo.environment[@"WQM_UI_HISTORY_EXPAND"].boolValue;
#else
    BOOL expandAll = NO;
#endif

    NSCalendar *calendar = NSCalendar.currentCalendar;
    NSMutableArray<NSDictionary *> *sections = [NSMutableArray new];
    NSMutableDictionary<NSDate *, NSMutableArray *> *groups = [NSMutableDictionary new];
    NSMutableArray<NSDate *> *days = [NSMutableArray new];
    for (WQMOperationRecord *record in filtered) {
        NSDate *day = [calendar startOfDayForDate:record.startedAt];
        if (!groups[day]) {
            groups[day] = [NSMutableArray new];
            [days addObject:day];
        }
        [groups[day] addObject:record];
    }
    [days sortUsingComparator:^NSComparisonResult(NSDate *a, NSDate *b) { return [b compare:a]; }];
    for (NSDate *day in days) {
        NSString *title;
        if ([calendar isDateInToday:day]) title = WQML(@"TODAY", @"今天");
        else if ([calendar isDateInYesterday:day]) title = WQML(@"YESTERDAY", @"昨天");
        else {
            NSDateFormatter *formatter = [NSDateFormatter new];
            formatter.locale = [WQMLanguageManager sharedManager].locale;
            formatter.dateStyle = NSDateFormatterMediumStyle;
            formatter.timeStyle = NSDateFormatterNoStyle;
            title = [formatter stringFromDate:day];
        }

        NSMutableArray<NSNumber *> *kinds = [NSMutableArray new];
        NSMutableDictionary<NSNumber *, NSMutableArray<WQMOperationRecord *> *> *byKind =
            [NSMutableDictionary new];
        for (WQMOperationRecord *record in groups[day]) {
            NSNumber *kind = @(record.kind);
            if (!byKind[kind]) {
                byKind[kind] = [NSMutableArray new];
                [kinds addObject:kind];
            }
            [byKind[kind] addObject:record];
        }
        [kinds sortUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
            NSDate *da = byKind[a].firstObject.startedAt;
            NSDate *db = byKind[b].firstObject.startedAt;
            return [db compare:da];
        }];

        NSMutableArray<NSDictionary *> *rows = [NSMutableArray new];
        for (NSNumber *kind in kinds) {
            NSArray<WQMOperationRecord *> *records = byKind[kind];
            if (records.count == 1) {
                [rows addObject:@{@"type": @"record", @"record": records.firstObject, @"indented": @NO}];
                continue;
            }
            NSString *key = [NSString stringWithFormat:@"%.0f-%ld",
                             day.timeIntervalSince1970, (long)kind.integerValue];
            BOOL expanded = expandAll || self->_query.length > 0 || [_expandedKeys containsObject:key];
            [rows addObject:@{@"type": @"group", @"kind": kind, @"records": records,
                              @"key": key, @"expanded": @(expanded)}];
            if (expanded) {
                for (WQMOperationRecord *record in records) {
                    [rows addObject:@{@"type": @"record", @"record": record, @"indented": @YES}];
                }
            }
        }
        [sections addObject:@{@"title": title, @"items": rows}];
    }
    return sections;
}

- (void)rebuildSections
{
    _sections = [self buildSections];
    [self.tableView reloadData];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText
{
    _query = [searchText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    [self rebuildSections];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar
{
    [self dismissSearchKeyboard];
}

- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar
{
    [searchBar setShowsCancelButton:YES animated:YES];
}

- (void)searchBarTextDidEndEditing:(UISearchBar *)searchBar
{
    [searchBar setShowsCancelButton:NO animated:NO];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar
{
    searchBar.text = @"";
    _query = nil;
    [self rebuildSections];
    [self dismissSearchKeyboard];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return MAX((NSInteger)_sections.count, 1);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (!_sections.count) return 1;
    return [_sections[(NSUInteger)section][@"items"] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return _sections.count
        ? _sections[(NSUInteger)section][@"title"]
        : WQML(@"OPERATION_HISTORY", @"操作记录");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    WQMHistoryCell *cell = [tableView dequeueReusableCellWithIdentifier:@"history"];
    if (!cell) {
        cell = [[WQMHistoryCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"history"];
    }
    if (!_sections.count) {
        UIListContentConfiguration *configuration = (UIListContentConfiguration *)cell.listContentView.configuration;
        configuration.text = _operations.count
            ? WQML(@"HISTORY_NO_MATCH", @"没有符合筛选的记录")
            : WQML(@"HISTORY_EMPTY", @"还没有操作记录");
        configuration.secondaryText = _operations.count
            ? WQML(@"HISTORY_ADJUST_FILTER", @"调整搜索或筛选条件")
            : WQML(@"HISTORY_EMPTY_DETAIL", @"备份和恢复操作会显示在这里");
        configuration.image = [UIImage systemImageNamed:@"clock.badge.questionmark"];
        configuration.imageProperties.tintColor = WQMTheme.textSecondaryColor;
        cell.listContentView.configuration = configuration;
        return cell;
    }
    NSDictionary *section = _sections[(NSUInteger)indexPath.section];
    NSDictionary *row = section[@"items"][(NSUInteger)indexPath.row];
    if ([row[@"type"] isEqualToString:@"group"]) {
        NSArray<WQMOperationRecord *> *records = row[@"records"];
        unsigned long long bytes = 0;
        for (WQMOperationRecord *record in records) bytes += record.bytes;
        [cell configureWithGroupKind:(WQMOperationKind)[row[@"kind"] integerValue]
                               count:records.count
                               bytes:bytes
                              latest:records.firstObject.startedAt
                            expanded:[row[@"expanded"] boolValue]];
    } else {
        [cell configureWithOperation:row[@"record"] indented:[row[@"indented"] boolValue]];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (!_sections.count) return;
    [self dismissSearchKeyboard];
    NSDictionary *row = _sections[(NSUInteger)indexPath.section][@"items"][(NSUInteger)indexPath.row];
    if ([row[@"type"] isEqualToString:@"group"]) {
        NSString *key = row[@"key"];
        if ([_expandedKeys containsObject:key]) [_expandedKeys removeObject:key];
        else [_expandedKeys addObject:key];
        _sections = [self buildSections];
        [tableView reloadSections:[NSIndexSet indexSetWithIndex:(NSUInteger)indexPath.section]
                 withRowAnimation:UITableViewRowAnimationAutomatic];
        return;
    }
    WQMOperationRecord *record = row[@"record"];
    NSMutableArray<NSString *> *lines = [NSMutableArray new];
    [lines addObject:[WQMOperationRecord displayNameForKind:record.kind]];
    [lines addObject:record.appName ?: @""];
    [lines addObject:record.bundleIdentifier ?: @""];
    [lines addObject:[WQMOperationRecord displayNameForStatus:record.status]];
    if (record.message.length) [lines addObject:WQMHistoryLocalizedMessage(record.message)];
    if (record.errorMessage.length) {
        [lines addObject:[NSString stringWithFormat:
                          WQML(@"HISTORY_ERROR_LINE", @"错误：%@"), record.errorMessage]];
    }
    if (record.backupPath.length) {
        [lines addObject:[NSString stringWithFormat:
                          WQML(@"HISTORY_BACKUP_LINE", @"备份：%@"), record.backupPath]];
    }
    if (record.safetyBackupPath.length) {
        [lines addObject:[NSString stringWithFormat:
                          WQML(@"HISTORY_SAFETY_BACKUP_LINE", @"安全备份：%@"), record.safetyBackupPath]];
    }
    if (record.journalPath.length) {
        [lines addObject:[NSString stringWithFormat:
                          WQML(@"HISTORY_JOURNAL_LINE", @"恢复日志：%@"), record.journalPath]];
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:WQML(@"HISTORY_DETAILS_TITLE", @"操作详情")
                                                                   message:[lines componentsJoinedByString:@"\n\n"]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    NSString *path = record.backupPath.length ? record.backupPath : record.safetyBackupPath;
    if (path.length) {
        [alert addAction:[UIAlertAction actionWithTitle:WQML(@"COPY_PATH", @"复制路径") style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction *action) {
            UIPasteboard.generalPasteboard.string = path;
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:WQML(@"CLOSE", @"关闭") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return nil;
}

@end

