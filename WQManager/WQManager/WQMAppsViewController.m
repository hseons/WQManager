#import "WQMAppsViewController.h"
#import "WQMAppModel.h"
#import "WQMAppScanner.h"
#import "WQMAppCache.h"
#import "WQMAppIconService.h"
#import "WQMAppActionsViewController.h"
#import "WQMBackupService.h"
#import "WQMBackupStore.h"
#import "WQMLanguageManager.h"
#import "WQMRestoreService.h"
#import "WQMLoadController.h"
#import "WQMLongOperationBanner.h"
#import "WQMAlertPresenter.h"
#import "WQMSafetyPolicy.h"
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

static NSString *WQMLoadProfileConfirmationLine(void)
{
    return [NSString stringWithFormat:@"\n\n%@",
            [NSString stringWithFormat:WQML(@"LOAD_PROFILE_CONFIRM", @"负载模式：%@"),
             WQMLoadProfileName(WQMLoadProfileCurrent())]];
}

@interface WQMAppsSummaryView : UIView

@property (nonatomic, strong) UILabel *totalLabel;
@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UISearchBar *searchBar;

- (void)setApps:(NSArray<WQMAppModel *> *)apps status:(NSString *)status scanning:(BOOL)scanning;

@end

@implementation WQMAppsSummaryView {
    WQMSoftSurfaceView *_card;
    BOOL _playedEntrance;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        _searchBar = [[UISearchBar alloc] init];
        _searchBar.searchBarStyle = UISearchBarStyleMinimal;
        _searchBar.placeholder = WQML(@"SEARCH_APPS", @"搜索 App");
        _searchBar.translatesAutoresizingMaskIntoConstraints = NO;
        _searchBar.searchTextField.backgroundColor = WQMTheme.surfaceColor;
        _searchBar.searchTextField.layer.cornerRadius = 17;
        _searchBar.searchTextField.layer.cornerCurve = kCACornerCurveContinuous;
        _searchBar.searchTextField.clipsToBounds = YES;

        _card = [[WQMSoftSurfaceView alloc] initWithElevated:YES];
        _card.translatesAutoresizingMaskIntoConstraints = NO;

        UILabel *caption = [UILabel new];
        caption.text = WQML(@"APP_TOTAL_COUNT", @"应用数量");
        caption.font = [WQMTheme sectionTitleFont];
        caption.textColor = WQMTheme.textSecondaryColor;

        _totalLabel = [UILabel new];
        _totalLabel.text = @"—";
        _totalLabel.font = [WQMTheme displayNumberFont];
        _totalLabel.textColor = WQMTheme.textPrimaryColor;
        _totalLabel.adjustsFontForContentSizeCategory = YES;

        _countLabel = [UILabel new];
        _countLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
        _countLabel.textColor = WQMTheme.textSecondaryColor;
        _countLabel.textAlignment = NSTextAlignmentRight;

        _statusLabel = [UILabel new];
        _statusLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
        _statusLabel.textColor = WQMTheme.textSecondaryColor;
        _statusLabel.numberOfLines = 2;

        UIView *rule = [UIView new];
        rule.backgroundColor = WQMTheme.separatorColor;
        rule.translatesAutoresizingMaskIntoConstraints = NO;

        UIStackView *top = [[UIStackView alloc] initWithArrangedSubviews:@[caption, _countLabel]];
        top.axis = UILayoutConstraintAxisHorizontal;
        top.alignment = UIStackViewAlignmentCenter;
        top.spacing = 12;

        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[top, _totalLabel, rule, _statusLabel]];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.alignment = UIStackViewAlignmentFill;
        stack.spacing = 9;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [stack setCustomSpacing:3 afterView:top];
        [stack setCustomSpacing:13 afterView:_totalLabel];
        [_card addSubview:stack];
        UIStackView *outer = [[UIStackView alloc] initWithArrangedSubviews:@[_searchBar, _card]];
        outer.axis = UILayoutConstraintAxisVertical;
        outer.spacing = 8;
        outer.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:outer];

        NSLayoutConstraint *headerFill = [outer.widthAnchor constraintEqualToAnchor:self.widthAnchor constant:-24];
        headerFill.priority = 999;
        [NSLayoutConstraint activateConstraints:@[
            [_searchBar.heightAnchor constraintGreaterThanOrEqualToConstant:48],
            [_statusLabel.heightAnchor constraintGreaterThanOrEqualToConstant:34],
            [rule.heightAnchor constraintEqualToConstant:1],
            [stack.topAnchor constraintEqualToAnchor:_card.topAnchor constant:20],
            [stack.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:20],
            [stack.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-20],
            [stack.bottomAnchor constraintEqualToAnchor:_card.bottomAnchor constant:-18],
            [outer.topAnchor constraintEqualToAnchor:self.topAnchor constant:6],
            [outer.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [outer.widthAnchor constraintLessThanOrEqualToConstant:760],
            headerFill,
            [outer.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-8],
        ]];
    }
    return self;
}

- (void)setApps:(NSArray<WQMAppModel *> *)apps status:(NSString *)status scanning:(BOOL)scanning
{
    unsigned long long total = 0;
    NSUInteger known = 0;
    for (WQMAppModel *app in apps) {
        if (!app.sizeKnown) continue;
        total += app.dataSize;
        known++;
    }
    NSString *sizeText = @"—";
    if (!scanning && known > 0) {
        NSString *knownSize = WQMFormatBytes(total);
        sizeText = known == apps.count
            ? knownSize
            : [NSString stringWithFormat:WQML(@"APP_TOTAL_PARTIAL_FORMAT", @"≥ %@"), knownSize];
    }
    [WQMTheme animateLabelChange:self.totalLabel update:^{
        self.totalLabel.text = scanning && apps.count == 0
            ? @"—"
            : [NSString stringWithFormat:@"%lu", (unsigned long)apps.count];
    }];
    [WQMTheme animateLabelChange:self.countLabel update:^{
        self.countLabel.text = scanning
            ? WQML(@"SCANNING", @"扫描中")
            : (known > 0 ? sizeText : WQML(@"APP_SIZE_UNKNOWN_SHORT", @"容量未知"));
    }];
    [WQMTheme animateLabelChange:self.statusLabel update:^{
        self.statusLabel.text = status ?: @"";
    }];
    if (!_playedEntrance) {
        _playedEntrance = YES;
        [WQMTheme animateEntrance:_card delay:0.02];
    }
}

@end

@interface WQMAppCardCell : UITableViewCell

@property (nonatomic, strong) WQMSoftSurfaceView *cardView;
@property (nonatomic, strong) UIListContentView *listContentView;

- (void)configureWithApp:(WQMAppModel *)app;
- (void)configureEmptyScanning:(BOOL)scanning status:(NSString *)status;
- (void)playEntranceWithDelay:(NSTimeInterval)delay;

@end

@implementation WQMAppCardCell

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
        configuration.imageProperties.maximumSize = CGSizeMake(32, 32);
        configuration.imageProperties.cornerRadius = 10;
        configuration.imageProperties.reservedLayoutSize = CGSizeMake(32, 32);
        configuration.textProperties.numberOfLines = 2;
        configuration.textToSecondaryTextVerticalPadding = 2;
        _listContentView = [[UIListContentView alloc] initWithConfiguration:configuration];
        _listContentView.translatesAutoresizingMaskIntoConstraints = NO;
        _listContentView.directionalLayoutMargins = NSDirectionalEdgeInsetsZero;
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
            [_listContentView.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:8],
            [_listContentView.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:14],
            [_listContentView.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-14],
            [_listContentView.bottomAnchor constraintEqualToAnchor:_cardView.bottomAnchor constant:-8],
            [_cardView.heightAnchor constraintGreaterThanOrEqualToConstant:64],
        ]];
    }
    return self;
}

- (void)configureWithApp:(WQMAppModel *)app
{
    UIListContentConfiguration *configuration = (UIListContentConfiguration *)self.listContentView.configuration;
    configuration.attributedText = nil;
    configuration.text = app.displayName ?: app.bundleIdentifier ?: WQML(@"UNKNOWN_APP", @"未知 App");
    configuration.secondaryText = [NSString stringWithFormat:@"%@  ·  %@",
                                   app.bundleIdentifier.length
                                       ? app.bundleIdentifier
                                       : WQML(@"NO_BUNDLE_ID", @"无 Bundle ID"),
                                   app.formattedSize];
    configuration.textProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    configuration.textProperties.color = WQMTheme.textPrimaryColor;
    configuration.secondaryTextProperties.font =
        [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    configuration.secondaryTextProperties.color = WQMTheme.textSecondaryColor;
    configuration.secondaryTextProperties.lineBreakMode = NSLineBreakByTruncatingMiddle;
    configuration.image = [WQMAppIconService iconForBundleIdentifier:app.bundleIdentifier
                                                         displayName:app.displayName];
    self.listContentView.configuration = configuration;
    self.accessibilityIdentifier = [@"app." stringByAppendingString:app.bundleIdentifier ?: @"unknown"];
    self.accessibilityLabel = [NSString stringWithFormat:@"%@，%@", app.displayName, app.statusText];
}

- (void)refreshIconWithApp:(WQMAppModel *)app
{
    UIListContentConfiguration *configuration =
        (UIListContentConfiguration *)self.listContentView.configuration;
    configuration.image = [WQMAppIconService iconForBundleIdentifier:app.bundleIdentifier
                                                         displayName:app.displayName];
    self.listContentView.configuration = configuration;
}

- (void)configureEmptyScanning:(BOOL)scanning status:(NSString *)status
{
    UIListContentConfiguration *configuration = (UIListContentConfiguration *)self.listContentView.configuration;
    configuration.attributedText = nil;
    configuration.text = scanning
        ? WQML(@"SCANNING_APPS", @"正在扫描")
        : WQML(@"NO_APPS_FOUND", @"未找到 App");
    configuration.secondaryText = status.length
        ? status
        : WQML(@"APPS_EMPTY_HINT", @"下拉刷新或检查 App Group");
    configuration.textProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    configuration.textProperties.color = WQMTheme.textPrimaryColor;
    configuration.secondaryTextProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    configuration.secondaryTextProperties.color = WQMTheme.textSecondaryColor;
    configuration.image = scanning
        ? [UIImage imageNamed:@"Scan"]
        : [UIImage systemImageNamed:@"rectangle.dashed"];
    configuration.imageProperties.tintColor = WQMTheme.textSecondaryColor;
    self.listContentView.configuration = configuration;
    self.accessibilityIdentifier = scanning ? @"apps.loading" : @"apps.empty";
    self.accessibilityLabel = scanning
        ? WQML(@"SCANNING_APPS_A11Y", @"正在扫描应用")
        : WQML(@"NO_APPS_FOUND_A11Y", @"未找到应用");
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

@implementation WQMAppsViewController {
    NSArray<WQMAppModel *> *_apps;
    NSArray<WQMAppModel *> *_visibleApps;
    NSString *_query;
    NSString *_status;
    WQScanCancellation *_scanCancellation;
    NSUInteger _scanGeneration;
    BOOL _scanning;
    WQMConfirmationGate *_restoreGate;
    WQMAppsSummaryView *_summaryView;
    NSMutableSet<NSString *> *_animatedApps;
    NSDate *_cacheLoadedAt;
    BOOL _presentedFixtureActions;
    BOOL _pendingDataReload;
}

- (instancetype)init
{
    return [super initWithStyle:UITableViewStylePlain];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = WQML(@"TAB_APPS", @"应用");
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.tableView.accessibilityIdentifier = @"apps.table";
    self.tableView.backgroundColor = WQMTheme.canvasColor;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 68;
    self.tableView.cellLayoutMarginsFollowReadableWidth = YES;
    self.tableView.contentInset = UIEdgeInsetsMake(4, 0, 24, 0);
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.definesPresentationContext = YES;
    _animatedApps = [NSMutableSet new];

    _summaryView = [[WQMAppsSummaryView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 146)];
    _summaryView.searchBar.delegate = self;
    self.tableView.tableHeaderView = _summaryView;
    [_summaryView setApps:@[] status:WQML(@"PREPARING_SCAN", @"准备扫描") scanning:YES];
    UITapGestureRecognizer *dismissTap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard:)];
    dismissTap.cancelsTouchesInView = NO;
    dismissTap.delegate = self;
    [self.tableView addGestureRecognizer:dismissTap];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(appIconDidResolve:)
                                               name:WQMAppIconDidResolveNotification
                                             object:nil];

    self.refreshControl = [UIRefreshControl new];
    [self.refreshControl addTarget:self action:@selector(refreshApps) forControlEvents:UIControlEventValueChanged];
    [self loadInitialIndex];
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [WQMAppIconService cancelPendingRequests];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    if (_scanning && _scanCancellation.isCancelled) [self scan];
    if (!_scanning && _cacheLoadedAt &&
        -[_cacheLoadedAt timeIntervalSinceNow] > 30 * 60) {
        [self scan];
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
#if DEBUG
    if (!_presentedFixtureActions &&
        [NSProcessInfo.processInfo.environment[@"WQM_UI_ACTION_PANEL"] boolValue] &&
        _visibleApps.count) {
        _presentedFixtureActions = YES;
        [self presentActionsForApp:_visibleApps.firstObject];
    }
#endif
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self dismissSearchKeyboard];
    [WQMAppIconService cancelPendingRequests];
    _pendingDataReload = NO;
    if (_scanning) [_scanCancellation cancel];
}

- (void)dismissKeyboard:(__unused UITapGestureRecognizer *)gesture
{
    [self dismissSearchKeyboard];
}

- (void)dismissSearchKeyboard
{
    [self.view endEditing:YES];
    [_summaryView.searchBar resignFirstResponder];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
       shouldReceiveTouch:(UITouch *)touch
{
    if (gestureRecognizer.view == self.tableView &&
        [touch.view isDescendantOfView:_summaryView.searchBar]) {
        return NO;
    }
    return YES;
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText
{
    [WQMAppIconService cancelPendingRequests];
    _query = [searchText stringByTrimmingCharactersInSet:
              NSCharacterSet.whitespaceAndNewlineCharacterSet];
    [self rebuildVisibleApps];
    [_animatedApps removeAllObjects];
    _pendingDataReload = NO;
    [self.tableView reloadData];
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
    [WQMAppIconService cancelPendingRequests];
    searchBar.text = @"";
    _query = nil;
    [self rebuildVisibleApps];
    [self dismissSearchKeyboard];
    _pendingDataReload = NO;
    [self.tableView reloadData];
}

- (void)refreshApps
{
    [WQMAppIconService clearCache];
    wq_enumerate_invalidate();
    wq_display_names_reset_miss();
    [self scan];
}

- (void)loadInitialIndex
{
#if DEBUG
    if ([NSProcessInfo.processInfo.environment[@"WQM_UI_FIXTURES"] boolValue]) {
        [self scan];
        return;
    }
    if ([NSProcessInfo.processInfo.environment[@"WQM_UI_FORCE_SCAN"] boolValue]) {
        [self scan];
        return;
    }
#endif
    WQMAppCacheSnapshot *cache = [WQMAppCache load];
    if (cache.apps.count) {
        _apps = cache.apps;
        _cacheLoadedAt = cache.updatedAt;
        _scanning = NO;
        _status = [self cacheStatusForDate:cache.updatedAt];
        if (cache.limitedCount > 0) {
            _status = [NSString stringWithFormat:
                       WQML(@"APP_INDEX_LIMITED_SUFFIX", @"%@ · %lu 个受限"),
                       _status, (unsigned long)cache.limitedCount];
        }
        [self rebuildVisibleApps];
        [self updateSummary];
        [self.tableView reloadData];

        NSTimeInterval age = -[cache.updatedAt timeIntervalSinceNow];
        if (age < 30 * 60) return;
        [self scan];
        return;
    }
    [self scan];
}

- (NSString *)cacheStatusForDate:(NSDate *)date
{
    NSTimeInterval age = MAX(0, -[date timeIntervalSinceNow]);
    NSString *relative;
    if (age < 60) relative = WQML(@"TIME_JUST_NOW", @"刚刚");
    else if (age < 3600) relative = [NSString stringWithFormat:
                                     WQML(@"TIME_MINUTES_AGO", @"%ld 分钟前"), (long)(age / 60)];
    else if (age < 86400) relative = [NSString stringWithFormat:
                                      WQML(@"TIME_HOURS_AGO", @"%ld 小时前"), (long)(age / 3600)];
    else relative = [NSString stringWithFormat:
                     WQML(@"TIME_DAYS_AGO", @"%ld 天前"), (long)(age / 86400)];
    return [NSString stringWithFormat:WQML(@"APP_INDEX_UPDATED", @"App 索引 · %@更新"), relative];
}

- (void)scan
{
    [_scanCancellation cancel];
    WQScanCancellation *cancellation = [WQScanCancellation new];
    _scanCancellation = cancellation;
    NSUInteger generation = ++_scanGeneration;
    _scanning = YES;
    [WQMAppIconService cancelPendingRequests];
    _status = _apps.count
        ? WQML(@"APP_INDEX_REFRESHING", @"正在后台更新 App 索引…")
        : WQML(@"SCANNING_APPS", @"正在查找 App…");
    [_animatedApps removeAllObjects];
    [_summaryView setApps:_apps status:_status scanning:YES];
    [self.refreshControl beginRefreshing];
    if (!_apps.count) [self.tableView reloadData];

    WQMAppScanner *scanner = [WQMAppScanner new];
    __weak typeof(self) weakSelf = self;
    [scanner scanWithCancellation:cancellation progress:^(NSString *status) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || generation != self->_scanGeneration || cancellation.isCancelled) return;
        self->_status = status;
        [self updateSummary];
    } completion:^(WQMAppScanResult *result) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || generation != self->_scanGeneration) return;
        self->_scanning = NO;
        self->_scanCancellation = nil;
        if (result.apps.count) {
            self->_apps = result.apps;
            self->_status = result.status;
            self->_cacheLoadedAt = NSDate.date;
            [self->_animatedApps removeAllObjects];
            [WQMAppCache saveResult:result];
        } else if (self->_apps.count) {
            self->_cacheLoadedAt = NSDate.date;
            self->_status = result.cancelled
                ? WQML(@"APP_INDEX_UPDATE_CANCELLED", @"更新已取消，继续显示缓存索引")
                : WQML(@"APP_INDEX_REFRESH_FAILED", @"刷新失败，继续显示上次索引");
        } else {
            self->_apps = @[];
            self->_status = result.status;
        }
        [self rebuildVisibleApps];
        [self updateSummary];
        [self.refreshControl endRefreshing];
        [self reloadAppListForDataChange];
#if DEBUG
        if (!self->_presentedFixtureActions &&
            [NSProcessInfo.processInfo.environment[@"WQM_UI_ACTION_PANEL"] boolValue] &&
            self->_visibleApps.count) {
            self->_presentedFixtureActions = YES;
            WQMAppModel *fixture = self->_visibleApps.firstObject;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [self presentActionsForApp:fixture];
            });
        }
#endif
    }];
}

- (void)appIconDidResolve:(NSNotification *)notification
{
    NSString *bundleIdentifier = notification.userInfo[WQMAppIconBundleIdentifierKey];
    if (!bundleIdentifier.length) return;
    NSUInteger index = [_visibleApps indexOfObjectPassingTest:
        ^BOOL(WQMAppModel *app, NSUInteger __unused idx, BOOL *__unused stop) {
            return [app.bundleIdentifier isEqualToString:bundleIdentifier];
        }];
    if (index == NSNotFound || index >= (NSUInteger)[self.tableView numberOfRowsInSection:0]) return;
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:(NSInteger)index inSection:0];
    WQMAppCardCell *cell = (WQMAppCardCell *)[self.tableView cellForRowAtIndexPath:indexPath];
    if (cell) [cell refreshIconWithApp:_visibleApps[index]];
}

- (void)reloadAppListForDataChange
{
    if (self.tableView.isTracking || self.tableView.isDragging || self.tableView.isDecelerating) {
        _pendingDataReload = YES;
        return;
    }
    [self.tableView reloadData];
}

- (void)flushDeferredListUpdates
{
    if (_pendingDataReload) {
        _pendingDataReload = NO;
        [self.tableView reloadData];
    }
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
    if (!decelerate) [self flushDeferredListUpdates];
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{
    [self flushDeferredListUpdates];
}

- (void)updateSummary
{
    [_summaryView setApps:_apps status:_status scanning:_scanning];
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

- (void)rebuildVisibleApps
{
    if (!_query.length) {
        _visibleApps = _apps;
        return;
    }
    _visibleApps = [_apps filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:
        ^BOOL(WQMAppModel *app, NSDictionary *__unused bindings) {
            return [app.displayName localizedCaseInsensitiveContainsString:self->_query] ||
                   [app.bundleIdentifier localizedCaseInsensitiveContainsString:self->_query];
        }]];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (!_visibleApps.count) return 1;
    return _visibleApps.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (_query.length && _apps.count) {
        return [NSString stringWithFormat:WQML(@"APP_SEARCH_COUNT", @"%lu / %lu 个 App"),
                (unsigned long)_visibleApps.count, (unsigned long)_apps.count];
    }
    return WQML(@"APP_LIST", @"应用列表");
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    WQMAppCardCell *cell = [tableView dequeueReusableCellWithIdentifier:@"app"];
    if (!cell) {
        cell = [[WQMAppCardCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"app"];
    }

    if (!_visibleApps.count) {
        [cell configureEmptyScanning:_scanning status:_status];
        return cell;
    }

    if (indexPath.row < 0 || indexPath.row >= (NSInteger)_visibleApps.count) return cell;
    WQMAppModel *app = _visibleApps[(NSUInteger)indexPath.row];
    [cell configureWithApp:app];
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (![cell isKindOfClass:WQMAppCardCell.class] || indexPath.row >= (NSInteger)_visibleApps.count ||
        !_animatedApps) return;
    WQMAppModel *app = _visibleApps[(NSUInteger)indexPath.row];
    [WQMAppIconService requestIconForBundleIdentifier:app.bundleIdentifier
                                          displayName:app.displayName];
    NSString *key = app.bundleIdentifier.length ? app.bundleIdentifier : app.containerPath;
    if ([_animatedApps containsObject:key]) return;
    [_animatedApps addObject:key];
    if (self.tableView.isTracking || self.tableView.isDragging || self.tableView.isDecelerating ||
        indexPath.row >= 8) {
        return;
    }
    NSTimeInterval delay = MIN(indexPath.row, 6) * 0.025;
    [(WQMAppCardCell *)cell playEntranceWithDelay:delay];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row >= (NSInteger)_visibleApps.count) return;
    [self dismissSearchKeyboard];
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [feedback impactOccurred];
    WQMAppModel *app = _visibleApps[(NSUInteger)indexPath.row];
    [self presentActionsForApp:app];
}

- (void)presentActionsForApp:(WQMAppModel *)app
{
    [self dismissSearchKeyboard];
    WQMAppActionsViewController *actions = [[WQMAppActionsViewController alloc] initWithApp:app];
    actions.actionHandler = ^(WQMAppAction action) {
        if (action == WQMAppActionCopyBundleID) {
            if (!app.bundleIdentifier.length) return;
            UIPasteboard.generalPasteboard.string = app.bundleIdentifier;
            UINotificationFeedbackGenerator *done = [UINotificationFeedbackGenerator new];
            [done notificationOccurred:UINotificationFeedbackTypeSuccess];
            return;
        }
        if (action == WQMAppActionRestore) {
            [self loadBackupsAndShowRestorePickerForApp:app];
            return;
        }
        WQMBackupScope scope = action == WQMAppActionFullBackup
            ? WQMBackupScopeFull : WQMBackupScopeQuick;
        WQMBackupScopeDescriptor *descriptor = [WQMBackupScopeDescriptor descriptorForScope:scope];
        if (descriptor) [self confirmBackupForApp:app scope:descriptor];
    };
    [self presentViewController:actions animated:YES completion:nil];
}

- (void)loadBackupsAndShowRestorePickerForApp:(WQMAppModel *)app
{
    UIAlertController *loading = [UIAlertController alertControllerWithTitle:WQML(@"RESTORE_LOADING_TITLE", @"正在读取备份")
                                                                     message:WQML(@"PLEASE_WAIT", @"请稍候…")
                                                              preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loading animated:YES completion:nil];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<WQMBackupRecord *> *matching = [[WQMBackupStore allBackups]
            filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:
            ^BOOL(WQMBackupRecord *backup, NSDictionary *__unused bindings) {
                return [backup.bundleIdentifier isEqualToString:app.bundleIdentifier];
            }]];
        dispatch_async(dispatch_get_main_queue(), ^{
            [loading dismissViewControllerAnimated:YES completion:^{
                if (!matching.count) {
                    UIAlertController *empty = [UIAlertController
                        alertControllerWithTitle:WQML(@"RESTORE_NO_BACKUPS_TITLE", @"没有可用备份")
                        message:[NSString stringWithFormat:
                                 WQML(@"RESTORE_NO_BACKUPS_MESSAGE", @"%@ 还没有备份记录。"),
                                 app.displayName]
                        preferredStyle:UIAlertControllerStyleAlert];
                    [empty addAction:[UIAlertAction actionWithTitle:WQML(@"OK", @"确定")
                                                              style:UIAlertActionStyleDefault
                                                            handler:nil]];
                    [self presentViewController:empty animated:YES completion:nil];
                    return;
                }
                [self showRestorePickerForApp:app backups:matching];
            }];
        });
    });
}

- (void)showRestorePickerForApp:(WQMAppModel *)app
                        backups:(NSArray<WQMBackupRecord *> *)backups
{
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:WQML(@"RESTORE_CHOOSER_TITLE", @"选择恢复备份")
                                                                   message:app.displayName
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [WQMLanguageManager sharedManager].locale;
    formatter.dateStyle = NSDateFormatterMediumStyle;
    formatter.timeStyle = NSDateFormatterShortStyle;
    for (WQMBackupRecord *backup in backups) {
        NSString *title = [NSString stringWithFormat:@"%@ · %@%@",
                           backup.scopeName,
                           [formatter stringFromDate:backup.createdAt],
                           backup.reason.length ? [NSString stringWithFormat:@" · %@", backup.reason] : @""];
        [sheet addAction:[UIAlertAction actionWithTitle:title
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction *action) {
            [self beginRestoreConfirmationForBackup:backup app:app];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:WQML(@"CANCEL", @"取消") style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.tableView;
    sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)beginRestoreConfirmationForBackup:(WQMBackupRecord *)backup app:(WQMAppModel *)app
{
    _restoreGate = [WQMConfirmationGate new];
    NSString *operation = [@"restore:" stringByAppendingString:NSUUID.UUID.UUIDString];
    if (![_restoreGate beginForOperation:operation]) return;

    NSString *message = [NSString stringWithFormat:
                         WQML(@"RESTORE_SCOPE_MESSAGE",
                              @"目标：%@\nBundle ID：%@\n\n将用以下备份替换目标 App 的 %@：\n%@\n\n"
                               "执行前会先自动备份目标当前数据。恢复期间目标 App 必须保持关闭。"),
                         app.displayName, app.bundleIdentifier,
                         [backup.parts componentsJoinedByString:WQML(@"LIST_SEPARATOR", @"、")],
                         backup.path];
    message = [message stringByAppendingString:WQMLoadProfileConfirmationLine()];
    UIAlertController *scopeAlert = [UIAlertController
        alertControllerWithTitle:WQML(@"RESTORE_SCOPE_TITLE", @"恢复范围确认")
                         message:message preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [scopeAlert addAction:[UIAlertAction actionWithTitle:WQML(@"CANCEL", @"取消") style:UIAlertActionStyleCancel
                                                handler:^(__unused UIAlertAction *action) {
        __strong typeof(weakSelf) self = weakSelf;
        [self->_restoreGate cancel];
    }]];
    [scopeAlert addAction:[UIAlertAction actionWithTitle:WQML(@"UNDERSTOOD_CONTINUE", @"我已了解，继续")
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction *action) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || ![self->_restoreGate acknowledgeScopeForOperation:operation]) return;
        [self showFinalRestoreConfirmationForBackup:backup app:app operation:operation];
    }]];
    [self presentViewController:scopeAlert animated:YES completion:nil];
}

- (void)showFinalRestoreConfirmationForBackup:(WQMBackupRecord *)backup
                                          app:(WQMAppModel *)app
                                    operation:(NSString *)operation
{
    NSString *message = [NSString stringWithFormat:
                         WQML(@"RESTORE_FINAL_MESSAGE",
                              @"这是第二次确认。目标 App 当前数据将被清空并由备份替换。\n\n"
                               "请输入 App 名称“%@”以确认执行。"), app.displayName];
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:WQML(@"RESTORE_FINAL_TITLE", @"最终确认：替换 App 数据")
                         message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = app.displayName;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:WQML(@"CANCEL", @"取消") style:UIAlertActionStyleCancel
                                            handler:^(__unused UIAlertAction *action) {
        __strong typeof(weakSelf) self = weakSelf;
        [self->_restoreGate cancel];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:WQML(@"RESTORE_REPLACE_ACTION", @"替换数据")
                                              style:UIAlertActionStyleDestructive
                                            handler:^(__unused UIAlertAction *action) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        NSString *typed = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:
                           NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (![typed isEqualToString:app.displayName]) {
            UIAlertController *error = [UIAlertController
                alertControllerWithTitle:WQML(@"RESTORE_NAME_MISMATCH_TITLE", @"名称不匹配")
                                 message:WQML(@"RESTORE_NAME_MISMATCH_MESSAGE",
                                              @"没有执行任何操作，请重新确认。")
                preferredStyle:UIAlertControllerStyleAlert];
            [error addAction:[UIAlertAction actionWithTitle:WQML(@"REENTER", @"重新输入") style:UIAlertActionStyleDefault
                                                    handler:^(__unused UIAlertAction *a) {
                [self showFinalRestoreConfirmationForBackup:backup app:app operation:operation];
            }]];
            [self presentViewController:error animated:YES completion:nil];
            return;
        }
        if (![self->_restoreGate authorizeExecutionForOperation:operation]) return;
        [self startRestoreBackup:backup app:app];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)startRestoreBackup:(WQMBackupRecord *)backup app:(WQMAppModel *)app
{
    WQMLongOperationBanner *banner = WQMLongOperationBanner.shared;
    if (![WQMLongOperationBanner startOperationWithTitle:WQML(@"RESTORE_PROGRESS_TITLE", @"正在恢复")
                                                  status:WQML(@"PREPARING", @"准备中…")
                                           cancelHandler:nil]) return;
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    WQMRestoreService *service = [WQMRestoreService new];
    [service restoreBackup:backup toApp:app progress:^(NSString *status) {
        [banner updateStatus:status];
    } completion:^(BOOL success, NSString *message, NSError *error) {
        [UIApplication sharedApplication].idleTimerDisabled = NO;
        [banner hideWithCompletion:^{
            UIAlertController *result = [UIAlertController
                alertControllerWithTitle:success
                    ? WQML(@"RESTORE_COMPLETE_TITLE", @"恢复完成")
                    : WQML(@"RESTORE_INCOMPLETE_TITLE", @"恢复未完成")
                                 message:message ?: error.localizedDescription
                          preferredStyle:UIAlertControllerStyleAlert];
            __weak typeof(self) weakSelf = self;
            [result addAction:[UIAlertAction actionWithTitle:WQML(@"OK", @"确定")
                                                       style:UIAlertActionStyleDefault
                                                     handler:^(__unused UIAlertAction *a) {
                [weakSelf scan];
            }]];
            [WQMAlertPresenter presentViewController:result animated:YES completion:nil];
        }];
    }];
}

- (void)confirmBackupForApp:(WQMAppModel *)app scope:(WQMBackupScopeDescriptor *)scope
{
    NSString *message = [NSString stringWithFormat:
                         WQML(@"BACKUP_CONFIRM_MESSAGE",
                              @"%@\n\n%@\n目录：%@\n\n备份期间请保持目标 App 关闭。"
                               "这不是文件系统快照，运行中的数据可能导致备份失败。"),
                         scope.title, scope.detail,
                         [scope.relativePaths componentsJoinedByString:@", "]];
    message = [message stringByAppendingString:WQMLoadProfileConfirmationLine()];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:WQML(@"BACKUP_CONFIRM_TITLE", @"开始备份？")
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:WQML(@"CANCEL", @"取消") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:WQML(@"BACKUP_START", @"开始备份")
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        [self startBackupForApp:app scope:scope];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)startBackupForApp:(WQMAppModel *)app scope:(WQMBackupScopeDescriptor *)scope
{
    WQMLongOperationBanner *banner = WQMLongOperationBanner.shared;
    if (![WQMLongOperationBanner startOperationWithTitle:WQML(@"BACKUP_PROGRESS_TITLE", @"正在备份")
                                                  status:WQML(@"PREPARING", @"准备中…")
                                           cancelHandler:nil]) return;
    [UIApplication sharedApplication].idleTimerDisabled = YES;

    WQMBackupService *service = [WQMBackupService new];
    [service backupApp:app scope:scope.scope reason:@"" progress:^(NSString *status) {
        [banner updateStatus:status];
    } completion:^(WQMBackupRecord *backup, NSError *error) {
        [UIApplication sharedApplication].idleTimerDisabled = NO;
        [banner hideWithCompletion:^{
            UIAlertController *result = [UIAlertController
                alertControllerWithTitle:error
                    ? WQML(@"BACKUP_FAILED_TITLE", @"备份失败")
                    : WQML(@"BACKUP_COMPLETE_TITLE", @"备份完成")
                message:error ? error.localizedDescription
                               : [NSString stringWithFormat:@"%@\n%@\n%@",
                                  backup.displayName, backup.scopeName, backup.path]
                preferredStyle:UIAlertControllerStyleAlert];
            [result addAction:[UIAlertAction actionWithTitle:WQML(@"OK", @"确定")
                                                       style:UIAlertActionStyleDefault
                                                     handler:nil]];
            [WQMAlertPresenter presentViewController:result animated:YES completion:nil];
        }];
    }];
}

@end

