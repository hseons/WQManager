//
//  WQMSpaceLensViewController.m
//  WQManager
//

#import "WQMSpaceLensViewController.h"
#import "WQMSpaceLensView.h"
#import "WQMAppModel.h"
#import "WQAccess.h"
#import "WQMLanguageManager.h"
#import "WQMTheme.h"
#import "WQMSafetyPolicy.h"
#import "WQMOperationStore.h"
#import "WQMTrashStore.h"
#import "WQMFilePreviewViewController.h"
#import "WQMSharedInbox.h"
#import "WQMPreferences.h"

@interface WQMSpaceLensViewController () <UITableViewDataSource, UITableViewDelegate,
                                              UIGestureRecognizerDelegate>
@end

@interface WQMLensCell : UITableViewCell
@property (nonatomic, strong) UIView *card;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIImageView *chevronView;
@property (nonatomic, strong) UIImageView *checkView;
@property (nonatomic) BOOL showsDisclosure;
- (void)configureTitle:(NSString *)title subtitle:(NSString *)subtitle directory:(BOOL)directory;
- (void)setPicking:(BOOL)picking picked:(BOOL)picked;
@end

@implementation WQMLensCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return nil;
    self.backgroundColor = UIColor.clearColor;
    self.selectionStyle = UITableViewCellSelectionStyleNone;

    _card = [UIView new];
    _card.translatesAutoresizingMaskIntoConstraints = NO;
    _card.backgroundColor = [WQMTheme.surfaceColor colorWithAlphaComponent:0.75];
    _card.layer.cornerRadius = 16;
    _card.layer.cornerCurve = kCACornerCurveContinuous;
    [self.contentView addSubview:_card];

    _iconView = [UIImageView new];
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;
    _iconView.contentMode = UIViewContentModeScaleAspectFit;
    _iconView.tintColor = WQMTheme.textSecondaryColor;
    [_card addSubview:_iconView];

    _titleLabel = [UILabel new];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    _titleLabel.textColor = WQMTheme.textPrimaryColor;
    [_card addSubview:_titleLabel];

    _subtitleLabel = [UILabel new];
    _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _subtitleLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    _subtitleLabel.textColor = WQMTheme.textSecondaryColor;
    [_card addSubview:_subtitleLabel];

    _chevronView = [UIImageView new];
    _chevronView.translatesAutoresizingMaskIntoConstraints = NO;
    _chevronView.image = [UIImage systemImageNamed:@"chevron.right"];
    _chevronView.contentMode = UIViewContentModeScaleAspectFit;
    _chevronView.tintColor = WQMTheme.separatorColor;
    [_card addSubview:_chevronView];

    _checkView = [UIImageView new];
    _checkView.translatesAutoresizingMaskIntoConstraints = NO;
    _checkView.contentMode = UIViewContentModeScaleAspectFit;
    _checkView.image = [UIImage systemImageNamed:@"circle"];
    _checkView.tintColor = WQMTheme.textSecondaryColor;
    _checkView.hidden = YES;
    [_card addSubview:_checkView];

    [NSLayoutConstraint activateConstraints:@[
        [_card.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:3],
        [_card.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-3],
        [_card.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [_card.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],

        [_iconView.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:16],
        [_iconView.centerYAnchor constraintEqualToAnchor:_card.centerYAnchor],
        [_iconView.widthAnchor constraintEqualToConstant:22],
        [_iconView.heightAnchor constraintEqualToConstant:22],

        [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:12],
        [_titleLabel.topAnchor constraintEqualToAnchor:_card.topAnchor constant:12],
        [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_chevronView.leadingAnchor constant:-8],

        [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:2],
        [_subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_chevronView.leadingAnchor constant:-8],

        [_chevronView.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-14],
        [_chevronView.centerYAnchor constraintEqualToAnchor:_card.centerYAnchor],
        [_chevronView.widthAnchor constraintEqualToConstant:12],
        [_chevronView.heightAnchor constraintEqualToConstant:20],

        [_checkView.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-14],
        [_checkView.centerYAnchor constraintEqualToAnchor:_card.centerYAnchor],
        [_checkView.widthAnchor constraintEqualToConstant:22],
        [_checkView.heightAnchor constraintEqualToConstant:22],
    ]];
    return self;
}

- (void)configureTitle:(NSString *)title subtitle:(NSString *)subtitle directory:(BOOL)directory
{
    self.titleLabel.text = title;
    self.subtitleLabel.text = subtitle;
    // Small rows keep the plain symbol: the detailed folder artwork turns to
    // mush below ~40 pt, so it stays in the bubbles where it has room.
    self.iconView.image = [UIImage systemImageNamed:[WQMSpaceLensIcon symbolNameForName:title
                                                                           directory:directory
                                                                           aggregate:NO]];
    self.iconView.tintColor = [WQMSpaceLensIcon tintForName:title directory:directory aggregate:NO];
    self.showsDisclosure = directory;
    self.chevronView.hidden = !directory;
    self.checkView.hidden = YES;
}

- (void)setPicking:(BOOL)picking picked:(BOOL)picked
{
    self.checkView.hidden = !picking;
    self.chevronView.hidden = picking || !self.showsDisclosure;
    self.checkView.image = [UIImage systemImageNamed:picked ? @"checkmark.circle.fill" : @"circle"];
    self.checkView.tintColor = picked ? WQMTheme.accentColor : WQMTheme.textSecondaryColor;
}

@end

typedef NS_ENUM(NSInteger, WQMLensSortOrder) {
    WQMLensSortOrderSize = 0,
    WQMLensSortOrderName,
};

@implementation WQMSpaceLensViewController {
    WQMAppModel *_app;
    WQMSpaceLensView *_lensView;
    UITableView *_tableView;
    UILabel *_crumbLabel;
    UILabel *_summaryLabel;
    UILabel *_footnoteLabel;
    UIButton *_backButton;
    UIBarButtonItem *_modeItem;
    UIScreenEdgePanGestureRecognizer *_edgeBackGesture;
    WQScanCancellation *_cancellation;
    dispatch_queue_t _scanQueue;
    NSMutableArray<NSString *> *_titles;
    NSMutableArray<NSString *> *_paths;
    NSMutableDictionary<NSString *, NSArray<NSDictionary<NSString *, id> *> *> *_cache;
    NSArray<NSDictionary<NSString *, id> *> *_children;
    BOOL _listMode;
    BOOL _lensDebugFinished;
    BOOL _loading;
    UIView *_actionBar;
    UILabel *_actionLabel;
    UIButton *_exportButton;
    UIButton *_deleteButton;
    UIBarButtonItem *_refreshItem;
    UIBarButtonItem *_sortItem;
    UIBarButtonItem *_editItem;
    NSMutableIndexSet *_picked;
    BOOL _picking;
    WQMLensSortOrder _sortOrder;
    WQMConfirmationGate *_deleteGate;
}

- (instancetype)initWithApp:(WQMAppModel *)app
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _app = app;
        _titles = [NSMutableArray new];
        _paths = [NSMutableArray new];
        _cache = [NSMutableDictionary new];
        _scanQueue = dispatch_queue_create("com.wqmanager.spacelens", DISPATCH_QUEUE_SERIAL);
        if (app.containerPath.length) {
            [_titles addObject:WQML(@"LENS_ROOT", @"App 容器")];
            [_paths addObject:app.containerPath];
        }
    }
    return self;
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    // A custom left bar item hides the system back button, which also switches the
    // edge-swipe gesture off; re-enable it so the map still swipes back.
    [self updateEdgeNavigation];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
{
    if (gestureRecognizer == _edgeBackGesture) {
        return _paths.count > 1;
    }
    if (gestureRecognizer == self.navigationController.interactivePopGestureRecognizer) {
        return _paths.count <= 1 && self.navigationController.viewControllers.count > 1;
    }
    return YES;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = WQMTheme.canvasColor;
    self.navigationItem.title = _app.displayName;
    [WQMTheme configureNavigationBar:self.navigationController.navigationBar];

    _modeItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"list.bullet"]
                                                style:UIBarButtonItemStylePlain
                                               target:self
                                               action:@selector(toggleMode:)];
    _modeItem.accessibilityLabel = WQML(@"LENS_LIST_MODE", @"列表");
    self.navigationItem.rightBarButtonItem = _modeItem;

    _refreshItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"]
                                                    style:UIBarButtonItemStylePlain
                                                   target:self
                                                   action:@selector(refreshCurrentLevel:)];
    _refreshItem.accessibilityLabel = WQML(@"LENS_REFRESH", @"重新测量");
    self.navigationItem.leftBarButtonItem = _refreshItem;

    _sortItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.up.arrow.down"]
                                                 style:UIBarButtonItemStylePlain
                                                target:self
                                                action:@selector(sortTapped:)];
    _sortItem.accessibilityLabel = WQML(@"LENS_SORT_TITLE", @"排序");

    _editItem = [[UIBarButtonItem alloc] initWithTitle:WQML(@"LENS_SELECT", @"选择")
                                                 style:UIBarButtonItemStylePlain
                                                target:self
                                                action:@selector(togglePicking:)];
    _picked = [NSMutableIndexSet new];
    _deleteGate = [WQMConfirmationGate new];

    _crumbLabel = [UILabel new];
    _crumbLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    _crumbLabel.textColor = WQMTheme.textSecondaryColor;
    _crumbLabel.lineBreakMode = NSLineBreakByTruncatingHead;
    _crumbLabel.accessibilityTraits = UIAccessibilityTraitButton;
    _crumbLabel.userInteractionEnabled = YES;
    [_crumbLabel addGestureRecognizer:[[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(crumbTapped:)]];

    _backButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_backButton setImage:[UIImage systemImageNamed:@"chevron.left"] forState:UIControlStateNormal];
    _backButton.tintColor = WQMTheme.textSecondaryColor;
    [_backButton addTarget:self action:@selector(goUp:) forControlEvents:UIControlEventTouchUpInside];
    _backButton.accessibilityLabel = WQML(@"LENS_UP", @"上一级");
    [_backButton.widthAnchor constraintEqualToConstant:28].active = YES;

    UIStackView *crumbs = [[UIStackView alloc] initWithArrangedSubviews:@[_backButton, _crumbLabel]];
    crumbs.axis = UILayoutConstraintAxisHorizontal;
    crumbs.alignment = UIStackViewAlignmentCenter;
    crumbs.spacing = 6;

    _summaryLabel = [UILabel new];
    _summaryLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    _summaryLabel.textColor = WQMTheme.textSecondaryColor;

    _footnoteLabel = [UILabel new];
    _footnoteLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
    _footnoteLabel.textColor = WQMTheme.textSecondaryColor;
    _footnoteLabel.numberOfLines = 2;
    _footnoteLabel.textAlignment = NSTextAlignmentCenter;
    _footnoteLabel.hidden = YES;
    _footnoteLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _lensView = [WQMSpaceLensView new];
    _lensView.translatesAutoresizingMaskIntoConstraints = NO;
    __weak typeof(self) weakSelf = self;
    _lensView.selectionHandler = ^(WQMBubbleLayoutItem *item) {
        [weakSelf handleSelection:item];
    };
    _lensView.cancelHandler = ^{
        [weakSelf cancelLoading];
    };
    _lensView.contextMenuProvider = ^UIMenu * _Nullable(WQMBubbleLayoutItem *item) {
        return [weakSelf menuForItem:item];
    };

    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.contentInset = UIEdgeInsetsMake(12, 0, 12, 0);
    _tableView.backgroundColor = UIColor.clearColor;
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.rowHeight = 74;
    _tableView.hidden = YES;
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [_tableView registerClass:[WQMLensCell class] forCellReuseIdentifier:@"cell"];
    UIRefreshControl *pull = [UIRefreshControl new];
    [pull addTarget:self action:@selector(refreshPulled:) forControlEvents:UIControlEventValueChanged];
    _tableView.refreshControl = pull;

    _actionBar = [UIView new];
    _actionBar.translatesAutoresizingMaskIntoConstraints = NO;
    _actionBar.backgroundColor = WQMTheme.raisedSurfaceColor;
    _actionBar.layer.cornerRadius = 18;
    _actionBar.layer.cornerCurve = kCACornerCurveContinuous;
    _actionBar.hidden = YES;

    _actionLabel = [UILabel new];
    _actionLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    _actionLabel.textColor = WQMTheme.textSecondaryColor;

    _exportButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_exportButton setImage:[UIImage systemImageNamed:@"square.and.arrow.up"] forState:UIControlStateNormal];
    _exportButton.accessibilityLabel = WQML(@"LENS_EXPORT", @"导出");
    [_exportButton addTarget:self action:@selector(exportPicked) forControlEvents:UIControlEventTouchUpInside];

    _deleteButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_deleteButton setImage:[UIImage systemImageNamed:@"trash"] forState:UIControlStateNormal];
    _deleteButton.tintColor = WQMTheme.dangerColor;
    _deleteButton.accessibilityLabel = WQML(@"LENS_DELETE", @"删除");
    [_deleteButton addTarget:self action:@selector(deletePicked) forControlEvents:UIControlEventTouchUpInside];

    _exportButton.enabled = NO;
    _deleteButton.enabled = NO;

    UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[crumbs, _summaryLabel]];
    header.axis = UILayoutConstraintAxisVertical;
    header.spacing = 4;
    header.translatesAutoresizingMaskIntoConstraints = NO;

    [self.view addSubview:header];
    [self.view addSubview:_lensView];
    [self.view addSubview:_tableView];
    [self.view addSubview:_footnoteLabel];
    // The system pop gesture cannot step through the lens' own path stack, so the
    // left edge drives goUp: while inside a folder and the system gesture takes
    // over again once we are at the container root.
    _edgeBackGesture = [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self
                                                                        action:@selector(edgeBackPanned:)];
    _edgeBackGesture.edges = UIRectEdgeLeft;
    _edgeBackGesture.delegate = self;
    _edgeBackGesture.enabled = NO;
    [self.view addGestureRecognizer:_edgeBackGesture];

    [self.view addSubview:_actionBar];
    [_actionBar addSubview:_actionLabel];
    [_actionBar addSubview:_exportButton];
    [_actionBar addSubview:_deleteButton];
    _actionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _exportButton.translatesAutoresizingMaskIntoConstraints = NO;
    _deleteButton.translatesAutoresizingMaskIntoConstraints = NO;

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:guide.topAnchor constant:10],
        [header.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:20],
        [header.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-20],

        [_lensView.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:8],
        [_lensView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:10],
        [_lensView.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-10],
        [_lensView.bottomAnchor constraintEqualToAnchor:_footnoteLabel.topAnchor constant:-8],

        [_tableView.topAnchor constraintEqualToAnchor:_lensView.topAnchor],
        [_tableView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:16],
        [_tableView.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-16],
        [_tableView.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor],

        [_footnoteLabel.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:24],
        [_footnoteLabel.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-24],
        [_footnoteLabel.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor constant:-8],

        [_actionBar.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:16],
        [_actionBar.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-16],
        [_actionBar.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor constant:-8],
        [_actionBar.heightAnchor constraintEqualToConstant:48],

        [_actionLabel.leadingAnchor constraintEqualToAnchor:_actionBar.leadingAnchor constant:16],
        [_actionLabel.centerYAnchor constraintEqualToAnchor:_actionBar.centerYAnchor],
        [_actionLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_exportButton.leadingAnchor constant:-8],

        [_exportButton.trailingAnchor constraintEqualToAnchor:_deleteButton.leadingAnchor constant:-18],
        [_exportButton.centerYAnchor constraintEqualToAnchor:_actionBar.centerYAnchor],
        [_exportButton.widthAnchor constraintEqualToConstant:34],
        [_exportButton.heightAnchor constraintEqualToConstant:34],

        [_deleteButton.trailingAnchor constraintEqualToAnchor:_actionBar.trailingAnchor constant:-16],
        [_deleteButton.centerYAnchor constraintEqualToAnchor:_actionBar.centerYAnchor],
        [_deleteButton.widthAnchor constraintEqualToConstant:34],
        [_deleteButton.heightAnchor constraintEqualToConstant:34],
    ]];

    [self reloadCurrentLevel];
}

#pragma mark - Level loading

- (NSString *)currentPath
{
    return _paths.lastObject;
}

/// The breadcrumb is a jump menu, not decoration: pick any ancestor level.
- (void)crumbTapped:(UITapGestureRecognizer *)gesture
{
    if (_paths.count <= 1) return;
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:WQML(@"LENS_JUMP", @"跳到")
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSInteger i = (NSInteger)_paths.count - 1; i >= 0; i--) {
        NSString *title = _titles[(NSUInteger)i];
        NSString *name = (i == (NSInteger)_paths.count - 1)
            ? [NSString stringWithFormat:@"%@ ✓", title]
            : title;
        [sheet addAction:[UIAlertAction actionWithTitle:name
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
            [self jumpToLevel:(NSUInteger)i];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:WQML(@"CANCEL", @"取消")
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    sheet.popoverPresentationController.sourceView = _crumbLabel;
    sheet.popoverPresentationController.sourceRect = _crumbLabel.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)jumpToLevel:(NSUInteger)level
{
    if (level >= _paths.count || level == _paths.count - 1) return;
    while (_paths.count > level + 1) {
        [_paths removeLastObject];
        [_titles removeLastObject];
    }
    [self reloadCurrentLevel];
}

- (void)edgeBackPanned:(UIScreenEdgePanGestureRecognizer *)gesture
{
    if (gesture.state != UIGestureRecognizerStateEnded) return;
    CGPoint velocity = [gesture velocityInView:self.view];
    CGFloat travelled = [gesture translationInView:self.view].x;
    if (travelled < 60 && velocity.x < 600) return;
    [self goUp:nil];
}

- (void)updateEdgeNavigation
{
    BOOL insideFolder = _paths.count > 1;
    _edgeBackGesture.enabled = insideFolder;
    UIGestureRecognizer *pop = self.navigationController.interactivePopGestureRecognizer;
    // Both recognizers must never be live at once, or one swipe would pop the
    // screen and the folder at the same time.
    pop.enabled = !insideFolder;
    pop.delegate = self;
}

- (void)goUp:(id)sender
{
    if (_paths.count > 1) {
        [_paths removeLastObject];
        [_titles removeLastObject];
        [self reloadCurrentLevel];
        return;
    }
    [self dismissSelf];
}

- (void)dismissSelf
{
    [_cancellation cancel];
    if (self.navigationController.presentingViewController) {
        [self.navigationController dismissViewControllerAnimated:YES completion:nil];
    } else {
        [self.navigationController popViewControllerAnimated:YES];
    }
}

- (void)reloadCurrentLevel
{
    NSString *path = [self currentPath];
    if (!path.length) {
        [self showUnavailable:nil];
        return;
    }
    _backButton.hidden = NO;
    _crumbLabel.text = [_titles componentsJoinedByString:@"  /  "];
    [self updateEdgeNavigation];
    NSArray<NSDictionary<NSString *, id> *> *cached = _cache[path];
    if (cached) {
        [self applyChildren:cached result:WQMeasureResultKnown];
        return;
    }
    [self loadChildrenAtPath:path];
}

- (void)loadChildrenAtPath:(NSString *)path
{
    [_cancellation cancel];
    _cancellation = [WQScanCancellation new];
    WQScanCancellation *token = _cancellation;
    _loading = YES;
    NSString *name = [_titles.lastObject length] ? _titles.lastObject : _app.displayName;
    [_lensView setItems:@[] animated:NO];
    [_lensView setScanning:YES text:[NSString stringWithFormat:WQML(@"LENS_MEASURING", @"正在测量 %@"), name]];
    _summaryLabel.text = @"";
    _footnoteLabel.hidden = YES;

    dispatch_async(_scanQueue, ^{
        WQMeasureBudget budget = {0, 20.0};
        WQMeasureResult result = WQMeasureResultMissing;
        NSArray<NSDictionary<NSString *, id> *> *children =
            wq_measure_children(path, token, budget, &result);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (token.isCancelled) return;
            self->_loading = NO;
            [self->_lensView cancelScanning];
            if (!children) {
                [self showUnavailable:result];
                return;
            }
            self->_cache[path] = children;
            [self applyChildren:children result:result];
        });
    });
}

- (void)cancelLoading
{
    [_cancellation cancel];
    _loading = NO;
    [_lensView cancelScanning];
    if (_children.count) {
        [self applyChildren:_children result:WQMeasureResultLimited];
    } else {
        [self showUnavailable:WQMeasureResultCancelled];
    }
}

- (void)showUnavailable:(WQMeasureResult)result
{
    [_lensView cancelScanning];
    [_lensView setItems:@[] animated:NO];
    _children = @[];
    [_tableView reloadData];
    _footnoteLabel.hidden = NO;
    _footnoteLabel.text = result == WQMeasureResultCancelled
        ? WQML(@"LENS_CANCELLED", @"已取消测量")
        : WQML(@"LENS_UNREADABLE", @"无法读取这个目录");
    _summaryLabel.text = @"";
}

- (void)applyChildren:(NSArray<NSDictionary<NSString *, id> *> *)children result:(WQMeasureResult)result
{
    _children = children;
    unsigned long long total = 0;
    for (NSDictionary *child in children) total += [child[WQChildBytesKey] unsignedLongLongValue];
    _summaryLabel.text = [NSString stringWithFormat:WQML(@"LENS_SUMMARY", @"%lu 项 · %@"),
                          (unsigned long)children.count, WQMFormatBytes(total)];

    if (children.count == 0) {
        [self showUnavailable:WQMeasureResultMissing];
        _footnoteLabel.text = WQML(@"LENS_EMPTY", @"这个目录是空的");
        return;
    }

    UIEdgeInsets insets = UIEdgeInsetsMake(14, 16, 14, 16);
    CGSize size = CGSizeMake(CGRectGetWidth(_lensView.bounds) - insets.left - insets.right,
                             CGRectGetHeight(_lensView.bounds) - insets.top - insets.bottom);
    if (size.width < 40 || size.height < 40) size = CGSizeMake(340, 420);

    NSMutableArray<WQMBubbleLayoutItem *> *items = [NSMutableArray new];
    for (NSDictionary *child in children) {
        NSString *name = child[WQChildNameKey];
        unsigned long long bytes = [child[WQChildBytesKey] unsignedLongLongValue];
        BOOL directory = [child[WQChildIsDirectoryKey] boolValue];
        WQMBubbleLayoutItem *item = [[WQMBubbleLayoutItem alloc]
            initWithIdentifier:[(directory ? @"dir:" : @"file:") stringByAppendingString:name ?: @""]
                         bytes:bytes];
        [items addObject:item];
    }
    NSArray<WQMBubbleLayoutItem *> *folded = [WQMBubbleLayout foldedItems:items
                                                                   inSize:size
                                                                 maxCount:8
                                                                minRadius:25
                                                                fillRatio:0.58
                                                          otherIdentifier:@"other"];
    [_lensView setItems:folded animated:YES];

    BOOL partial = result == WQMeasureResultLimited || result == WQMeasureResultBudgetExceeded;
    _footnoteLabel.hidden = !partial;
    _footnoteLabel.text = WQML(@"LENS_PARTIAL", @"测量被截断，显示的是部分数据");
    [_tableView reloadData];

#if DEBUG
    [self applyLensDebugHooksForChildren:children];
#endif
}

#if DEBUG
- (void)applyLensDebugHooksForChildren:(NSArray<NSDictionary<NSString *, id> *> *)children
{
    if (_lensDebugFinished) return;
    NSString *drill = NSProcessInfo.processInfo.environment[@"WQM_UI_LENS_DRILL"];
    NSArray<NSString *> *steps = drill.length ? [drill componentsSeparatedByString:@"/"] : @[];
    NSUInteger depth = _paths.count - 1;
    if (depth < steps.count) {
        NSString *wanted = steps[depth];
        for (NSDictionary<NSString *, id> *child in children) {
            if (![child[WQChildIsDirectoryKey] boolValue]) continue;
            if (![child[WQChildNameKey] isEqualToString:wanted]) continue;
            [_titles addObject:wanted];
            [_paths addObject:[[self currentPath] stringByAppendingPathComponent:wanted]];
            BOOL done = depth + 1 >= steps.count;
            dispatch_async(dispatch_get_main_queue(), ^{
                [self reloadCurrentLevel];
                if (done) {
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                                   dispatch_get_main_queue(), ^{ [self applyLensInteractionDebugHooks]; });
                }
            });
            _lensDebugFinished = done;
            return;
        }
        _lensDebugFinished = YES;
    }
    [self applyLensInteractionDebugHooks];
}

- (void)applyLensInteractionDebugHooks
{
    if ([NSProcessInfo.processInfo.environment[@"WQM_UI_LENS_LIST"] boolValue]) {
        [self setListMode:YES];
        NSInteger picks = [NSProcessInfo.processInfo.environment[@"WQM_UI_LENS_PICK"] integerValue];
        if (picks > 0) {
            [self setPicking:YES];
            NSInteger count = MIN(picks, (NSInteger)[self rows].count);
            for (NSInteger i = 0; i < count; i++) [_picked addIndex:(NSUInteger)i];
            [_tableView reloadData];
            [self updateActionBar];
        }
        if ([NSProcessInfo.processInfo.environment[@"WQM_UI_LENS_EXPORT"] boolValue]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ [self exportPicked]; });
        }
        if ([NSProcessInfo.processInfo.environment[@"WQM_UI_LENS_DELETE_PROMPT"] boolValue]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ [self deletePicked]; });
        }
        if ([NSProcessInfo.processInfo.environment[@"WQM_UI_LENS_DELETE_NOW"] boolValue]) {
            NSArray *target = [[self pickedChildren] copy];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [self performDelete:target operation:NSUUID.UUID.UUIDString];
            });
        }
    }
    NSInteger backs = [NSProcessInfo.processInfo.environment[@"WQM_UI_LENS_BACK"] integerValue];
    for (NSInteger i = 0; i < backs; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((0.9 + 0.7 * i) * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [self goUp:nil]; });
    }
    if ([NSProcessInfo.processInfo.environment[@"WQM_UI_LENS_MENU_LOG"] boolValue] && _children.count) {
        NSDictionary *first = _children.firstObject;
        WQMBubbleLayoutItem *item = [[WQMBubbleLayoutItem alloc]
            initWithIdentifier:[NSString stringWithFormat:@"%@:%@",
                                [first[WQChildIsDirectoryKey] boolValue] ? @"dir" : @"file",
                                first[WQChildNameKey]]
                         bytes:[first[WQChildBytesKey] unsignedLongLongValue]];
        UIMenu *menu = [self menuForItem:item];
        NSMutableArray<NSString *> *titles = [NSMutableArray new];
        for (UIMenuElement *element in menu.children) [titles addObject:element.title];
        NSLog(@"[lens] menu: %@", [titles componentsJoinedByString:@", "]);
    }
    NSString *previewName = NSProcessInfo.processInfo.environment[@"WQM_UI_LENS_PREVIEW"];
    if (previewName.length) {
        NSString *path = [[self currentPath] stringByAppendingPathComponent:previewName];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [self openPreviewForPath:path name:previewName]; });
    }
}
#endif

#pragma mark - Selection

- (void)handleSelection:(WQMBubbleLayoutItem *)item
{
    if ([item.identifier isEqualToString:@"other"]) {
        [self setListMode:YES];
        return;
    }
    NSString *name = item.identifier;
    if ([name hasPrefix:@"dir:"]) {
        name = [name substringFromIndex:4];
    } else if ([name hasPrefix:@"file:"]) {
        name = [name substringFromIndex:5];
    }
    BOOL directory = [item.identifier hasPrefix:@"dir:"];
    NSString *path = [[self currentPath] stringByAppendingPathComponent:name];
    if (!directory) {
        if (path.length) [self presentFileInfo:path name:name bytes:item.bytes];
        return;
    }
    [_titles addObject:name];
    [_paths addObject:path];
    [self reloadCurrentLevel];
}

- (void)openPreviewForPath:(NSString *)path name:(NSString *)name
{
    WQMFilePreviewViewController *preview = [[WQMFilePreviewViewController alloc] initWithFilePath:path
                                                                                             name:name];
    if (self.navigationController) {
        [self.navigationController pushViewController:preview animated:YES];
        return;
    }
    UINavigationController *wrapper = [[UINavigationController alloc] initWithRootViewController:preview];
    [self presentViewController:wrapper animated:YES completion:nil];
}

- (void)presentFileInfo:(NSString *)path name:(NSString *)name bytes:(unsigned long long)bytes
{
    if (path.length) {
        [self openPreviewForPath:path name:name];
        return;
    }
    NSString *message = [NSString stringWithFormat:@"%@\n%@", WQMFormatBytes(bytes), path];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:name
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:WQML(@"LENS_COPY_PATH", @"复制路径")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        UIPasteboard.generalPasteboard.string = path;
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:WQML(@"OK", @"好")
                                              style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - List mode

- (void)toggleMode:(id)sender
{
    [self setListMode:!_listMode];
}

- (void)setListMode:(BOOL)listMode
{
    _listMode = listMode;
    _lensView.hidden = listMode;
    _tableView.hidden = !listMode;
    _modeItem.image = [UIImage systemImageNamed:listMode ? @"square.grid.2x2" : @"list.bullet"];
    _modeItem.accessibilityLabel = listMode ? WQML(@"LENS_BUBBLE_MODE", @"气泡") : WQML(@"LENS_LIST_MODE", @"列表");
    if (!listMode) [self setPicking:NO];
    self.navigationItem.rightBarButtonItems = listMode
        ? @[_modeItem, _sortItem, _editItem]
        : @[_modeItem];
    [_tableView reloadData];
}

#pragma mark - Sorting and refreshing

- (NSArray<NSDictionary<NSString *, id> *> *)rows
{
    if (_sortOrder == WQMLensSortOrderName) {
        return [_children sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [a[WQChildNameKey] localizedStandardCompare:b[WQChildNameKey]];
        }];
    }
    return _children ?: @[];
}

- (void)sortTapped:(id)sender
{
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:WQML(@"LENS_SORT_TITLE", @"排序")
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    void (^pick)(WQMLensSortOrder) = ^(WQMLensSortOrder order) {
        self->_sortOrder = order;
        [self->_tableView reloadData];
        [self updateActionBar];
    };
    NSString *sizeTitle = WQML(@"LENS_SORT_SIZE", @"按大小");
    NSString *nameTitle = WQML(@"LENS_SORT_NAME", @"按名称");
    if (_sortOrder == WQMLensSortOrderSize) sizeTitle = [sizeTitle stringByAppendingString:@" ✓"];
    else nameTitle = [nameTitle stringByAppendingString:@" ✓"];
    [sheet addAction:[UIAlertAction actionWithTitle:sizeTitle style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) { pick(WQMLensSortOrderSize); }]];
    [sheet addAction:[UIAlertAction actionWithTitle:nameTitle style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) { pick(WQMLensSortOrderName); }]];
    [sheet addAction:[UIAlertAction actionWithTitle:WQML(@"CANCEL", @"取消") style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.barButtonItem = _sortItem;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)refreshCurrentLevel:(id)sender
{
    NSString *path = [self currentPath];
    if (path.length) [_cache removeObjectForKey:path];
    [self reloadCurrentLevel];
}

- (void)refreshPulled:(UIRefreshControl *)control
{
    NSString *path = [self currentPath];
    if (path.length) [_cache removeObjectForKey:path];
    [control endRefreshing];
    [self reloadCurrentLevel];
}

#pragma mark - Picking

- (void)togglePicking:(id)sender
{
    if (!_listMode) [self setListMode:YES];
    [self setPicking:!_picking];
}

- (void)setPicking:(BOOL)picking
{
    _picking = picking;
    if (!picking) [_picked removeAllIndexes];
    _editItem.title = picking ? WQML(@"LENS_DONE", @"完成") : WQML(@"LENS_SELECT", @"选择");
    _tableView.contentInset = UIEdgeInsetsMake(12, 0, picking ? 64 : 12, 0);
    // While picking, the only escape hatch is 完成; sorting or switching views mid-selection
    // would silently drop the chosen rows.
    if (_listMode) {
        self.navigationItem.rightBarButtonItems = picking ? @[_editItem]
                                                          : @[_modeItem, _sortItem, _editItem];
    }
    _tableView.refreshControl.enabled = !picking;
    [self updateActionBar];
    [_tableView reloadData];
}

- (NSArray<NSDictionary<NSString *, id> *> *)pickedChildren
{
    NSArray<NSDictionary<NSString *, id> *> *rows = [self rows];
    NSMutableArray<NSDictionary<NSString *, id> *> *picked = [NSMutableArray new];
    [_picked enumerateIndexesUsingBlock:^(NSUInteger idx, __unused BOOL *stop) {
        if (idx < rows.count) [picked addObject:rows[idx]];
    }];
    return picked;
}

- (void)updateActionBar
{
    _actionBar.hidden = !_picking;
    NSArray<NSDictionary<NSString *, id> *> *picked = [self pickedChildren];
    unsigned long long bytes = 0;
    for (NSDictionary *child in picked) bytes += [child[WQChildBytesKey] unsignedLongLongValue];
    _actionLabel.text = picked.count
        ? [NSString stringWithFormat:WQML(@"LENS_SELECTED", @"已选 %lu 项 · %@"),
           (unsigned long)picked.count, WQMFormatBytes(bytes)]
        : WQML(@"LENS_NOTHING_SELECTED", @"请先选择项目。");
    _exportButton.enabled = picked.count > 0;
    _deleteButton.enabled = picked.count > 0;
}

#pragma mark - Export and delete

- (void)exportPicked
{
    NSArray<NSDictionary<NSString *, id> *> *picked = [self pickedChildren];
    if (!picked.count) return;
    NSString *level = [self currentPath];
    NSDateFormatter *stamp = [NSDateFormatter new];
    stamp.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    stamp.dateFormat = @"yyyyMMdd-HHmmss";
    NSString *folder = [NSTemporaryDirectory() stringByAppendingPathComponent:
                        [NSString stringWithFormat:@"SpaceLensExport-%@", [stamp stringFromDate:NSDate.date]]];
    if (![[NSFileManager defaultManager] createDirectoryAtPath:folder
                                   withIntermediateDirectories:YES
                                                    attributes:nil
                                                         error:NULL]) {
        [self presentMessage:WQML(@"LENS_EXPORT", @"导出") body:WQML(@"LENS_UNREADABLE", @"无法读取这个目录")];
        return;
    }
    WQMOperationRecord *record = [WQMOperationStore beginOperation:WQMOperationKindExport
                                                          appName:_app.displayName
                                                 bundleIdentifier:_app.bundleIdentifier];
    record.scope = [_titles componentsJoinedByString:@" / "];
    [WQMOperationStore updateRecord:record];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableArray<NSURL *> *urls = [NSMutableArray new];
        unsigned long long bytes = 0;
        for (NSDictionary<NSString *, id> *child in picked) {
            NSString *name = child[WQChildNameKey];
            if (!name.length) continue;
            NSString *source = [level stringByAppendingPathComponent:name];
            NSString *target = [folder stringByAppendingPathComponent:name];
            if ([[NSFileManager defaultManager] copyItemAtPath:source toPath:target error:NULL]) {
                [urls addObject:[NSURL fileURLWithPath:target]];
                bytes += [child[WQChildBytesKey] unsignedLongLongValue];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            record.bytes = bytes;
            record.finishedAt = NSDate.date;
            record.status = urls.count ? WQMOperationStatusSuccess : WQMOperationStatusFailure;
            record.message = [NSString stringWithFormat:@"导出 %lu 项", (unsigned long)urls.count];
            if (!urls.count) record.errorMessage = WQML(@"LENS_UNREADABLE", @"无法读取这个目录");
            [WQMOperationStore updateRecord:record];
            if (!urls.count) {
                [self presentMessage:WQML(@"LENS_EXPORT", @"导出") body:WQML(@"LENS_UNREADABLE", @"无法读取这个目录")];
                return;
            }
            UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:urls
                                                                                applicationActivities:nil];
            share.popoverPresentationController.sourceView = self->_actionBar;
            share.popoverPresentationController.sourceRect = self->_actionBar.bounds;
            [self presentViewController:share animated:YES completion:nil];
        });
    });
}

- (void)deletePicked
{
    [self confirmDeletionOfChildren:[self pickedChildren]];
}

- (void)confirmDeletionOfChildren:(NSArray<NSDictionary<NSString *, id> *> *)picked
{
    if (!picked.count) return;
    unsigned long long bytes = 0;
    for (NSDictionary *child in picked) bytes += [child[WQChildBytesKey] unsignedLongLongValue];
    NSString *operation = NSUUID.UUID.UUIDString;
    [_deleteGate beginForOperation:operation];

    UIAlertController *scope = [UIAlertController
        alertControllerWithTitle:[NSString stringWithFormat:WQML(@"LENS_DELETE_TITLE", @"删除 %lu 项？"),
                                  (unsigned long)picked.count]
                         message:[NSString stringWithFormat:WQML(@"LENS_DELETE_MESSAGE",
                                                                 @"将从该 App 容器移除约 %@。%@"),
                                  WQMFormatBytes(bytes),
                                  WQML(@"LENS_TRASH_NOTE",
                                       @"删除的项目会移入 WQManager 内的空间透镜回收站，可以找回。")]
                  preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [scope addAction:[UIAlertAction actionWithTitle:WQML(@"CANCEL", @"取消")
                                              style:UIAlertActionStyleCancel
                                            handler:^(__unused UIAlertAction *action) {
        __strong typeof(weakSelf) self = weakSelf;
        [self->_deleteGate cancel];
    }]];
    [scope addAction:[UIAlertAction actionWithTitle:WQML(@"UNDERSTOOD_CONTINUE", @"我已了解，继续")
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || ![self->_deleteGate acknowledgeScopeForOperation:operation]) return;
        // A single file is one alert away from the bin; the typed word is reserved for
        // batches and folders, where an accidental tap would cost more.
        BOOL folder = NO;
        for (NSDictionary *child in picked) {
            if ([child[WQChildIsDirectoryKey] boolValue]) { folder = YES; break; }
        }
        BOOL needsTypedConfirmation = WQMCleanDoubleConfirmEnabled() && (picked.count > 1 || folder);
        if (!needsTypedConfirmation) {
            if (![self->_deleteGate authorizeExecutionForOperation:operation]) return;
            [self performDelete:picked operation:operation];
            return;
        }
        [self showFinalDeleteConfirmation:picked operation:operation];
    }]];
    [self presentViewController:scope animated:YES completion:nil];
}

- (void)showFinalDeleteConfirmation:(NSArray<NSDictionary<NSString *, id> *> *)picked
                          operation:(NSString *)operation
{
    NSString *word = WQML(@"LENS_DELETE_WORD", @"删除");
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:WQML(@"LENS_DELETE_FINAL_TITLE", @"最终确认")
                         message:[NSString stringWithFormat:WQML(@"LENS_DELETE_FINAL_MESSAGE",
                                                                 @"这是第二次确认。请输入「%@」以删除 %lu 项。"),
                                  word, (unsigned long)picked.count]
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = word;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:WQML(@"CANCEL", @"取消")
                                              style:UIAlertActionStyleCancel
                                            handler:^(__unused UIAlertAction *action) {
        __strong typeof(weakSelf) self = weakSelf;
        [self->_deleteGate cancel];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:WQML(@"LENS_DELETE_START", @"立即删除")
                                              style:UIAlertActionStyleDestructive
                                            handler:^(__unused UIAlertAction *action) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        NSString *typed = [alert.textFields.firstObject.text
                           stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (![typed isEqualToString:word]) {
            [self presentMessage:WQML(@"LENS_DELETE_MISMATCH_TITLE", @"确认文字不匹配")
                            body:WQML(@"LENS_DELETE_MISMATCH_MESSAGE", @"没有执行任何删除。")];
            return;
        }
        if (![self->_deleteGate authorizeExecutionForOperation:operation]) return;
        [self performDelete:picked operation:operation];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSString *)trashFolderForLevel:(NSString *)level
{
    return [WQMTrashStore createSessionForLevel:level];
}

- (void)performDelete:(NSArray<NSDictionary<NSString *, id> *> *)picked operation:(NSString *)operation
{
    NSString *level = [self currentPath];
    NSString *trash = [self trashFolderForLevel:level];
    WQMOperationRecord *record = [WQMOperationStore beginOperation:WQMOperationKindDeleteFiles
                                                          appName:_app.displayName
                                                 bundleIdentifier:_app.bundleIdentifier];
    record.scope = [_titles componentsJoinedByString:@" / "];
    record.safetyBackupPath = trash;
    [WQMOperationStore updateRecord:record];

    unsigned long long freed = 0;
    NSUInteger removed = 0;
    NSMutableSet<NSString *> *names = [NSMutableSet new];
    NSMutableArray<NSDictionary<NSString *, id> *> *moved = [NSMutableArray new];
    for (NSDictionary<NSString *, id> *child in picked) {
        NSString *name = child[WQChildNameKey];
        if (!name.length) continue;
        NSString *source = [level stringByAppendingPathComponent:name];
        NSString *target = [trash stringByAppendingPathComponent:name];
        if ([[NSFileManager defaultManager] moveItemAtPath:source toPath:target error:NULL]) {
            freed += [child[WQChildBytesKey] unsignedLongLongValue];
            removed += 1;
            [names addObject:name];
            [moved addObject:@{
                @"Name": name,
                @"Bytes": child[WQChildBytesKey] ?: @0,
                @"Directory": child[WQChildIsDirectoryKey] ?: @NO,
            }];
        }
    }
    if (moved.count) {
        [WQMTrashStore recordSession:trash source:level items:moved];
    }
    record.bytes = freed;
    record.finishedAt = NSDate.date;
    record.status = removed == picked.count ? WQMOperationStatusSuccess : WQMOperationStatusFailure;
    record.message = [NSString stringWithFormat:@"删除 %lu 项", (unsigned long)removed];
    if (record.status == WQMOperationStatusFailure) {
        record.errorMessage = [NSString stringWithFormat:@"%lu 项未能删除",
                               (unsigned long)(picked.count - removed)];
    }
    [WQMOperationStore updateRecord:record];

    NSMutableArray<NSDictionary<NSString *, id> *> *kept = [NSMutableArray new];
    for (NSDictionary<NSString *, id> *child in _children) {
        if (![names containsObject:child[WQChildNameKey] ?: @""]) [kept addObject:child];
    }
    _children = kept;
    if (level.length) _cache[level] = kept;
    [self setPicking:NO];
    [self applyChildren:kept result:WQMeasureResultKnown];
    if (removed) {
        UINotificationFeedbackGenerator *generator = [UINotificationFeedbackGenerator new];
        [generator notificationOccurred:UINotificationFeedbackTypeSuccess];
    }
    if (removed < picked.count) {
        [self presentMessage:WQML(@"LENS_DELETE", @"删除")
                        body:[NSString stringWithFormat:WQML(@"LENS_DELETE_FAILED", @"%lu 项未能删除"),
                              (unsigned long)(picked.count - removed)]];
    }
}

- (void)presentMessage:(NSString *)title body:(NSString *)body
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                  message:body
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:WQML(@"OK", @"好")
                                              style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Long press

- (UIMenu *)menuForItem:(WQMBubbleLayoutItem *)item
{
    if ([item.identifier isEqualToString:@"other"]) return nil;
    BOOL directory = [item.identifier hasPrefix:@"dir:"];
    NSString *name = [item.identifier substringFromIndex:directory ? 4 : 5];
    if (!name.length) return nil;
    NSString *path = [[self currentPath] stringByAppendingPathComponent:name];
    NSMutableArray<UIMenuElement *> *actions = [NSMutableArray new];
    __weak typeof(self) weakSelf = self;
    if (directory) {
        [actions addObject:[UIAction actionWithTitle:WQML(@"LENS_OPEN", @"打开")
                                               image:[UIImage systemImageNamed:@"chevron.right.circle"]
                                          identifier:nil
                                             handler:^(__unused UIAction *action) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            [self->_titles addObject:name];
            [self->_paths addObject:path];
            [self reloadCurrentLevel];
        }]];
    }
    if (!directory) {
        [actions addObject:[UIAction actionWithTitle:WQML(@"LENS_PREVIEW", @"预览")
                                               image:[UIImage systemImageNamed:@"eye"]
                                          identifier:nil
                                             handler:^(__unused UIAction *action) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            [self openPreviewForPath:path name:name];
        }]];
        [actions addObject:[UIAction actionWithTitle:WQML(@"LENS_SHARE", @"分享")
                                               image:[UIImage systemImageNamed:@"square.and.arrow.up"]
                                          identifier:nil
                                             handler:^(__unused UIAction *action) {
            UIActivityViewController *share = [[UIActivityViewController alloc]
                                               initWithActivityItems:@[[NSURL fileURLWithPath:path]]
                                               applicationActivities:nil];
            share.popoverPresentationController.sourceView = self->_lensView;
            share.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self->_lensView.bounds),
                                                                       CGRectGetMidY(self->_lensView.bounds),
                                                                       1, 1);
            [self presentViewController:share animated:YES completion:nil];
        }]];
    }
    // Copy last, right before the destructive item: the menu reads as a task list.
    [actions addObject:[UIAction actionWithTitle:WQML(@"LENS_COPY_PATH", @"复制路径")
                                           image:[UIImage systemImageNamed:@"doc.on.doc"]
                                      identifier:nil
                                         handler:^(__unused UIAction *action) {
        UIPasteboard.generalPasteboard.string = path;
    }]];
    [actions addObject:[UIAction actionWithTitle:WQML(@"LENS_DELETE", @"删除")
                                           image:[UIImage systemImageNamed:@"trash"]
                                      identifier:nil
                                     handler:^(__unused UIAction *action) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        [self confirmDeletionOfChildren:@[@{
            WQChildNameKey: name,
            WQChildBytesKey: @(item.bytes),
            WQChildIsDirectoryKey: @(directory),
        }]];
    }]];
    UIAction *deleteAction = actions.lastObject;
    deleteAction.attributes = UIMenuElementAttributesDestructive;

    return [UIMenu menuWithTitle:name children:actions];
}

#pragma mark - Swipe actions

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
        trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Selected rows already have the action bar; a swipe there would be ambiguous.
    if (_picking) return nil;
    NSArray<NSDictionary<NSString *, id> *> *rows = [self rows];
    if ((NSUInteger)indexPath.row >= rows.count) return nil;
    NSDictionary *child = rows[(NSUInteger)indexPath.row];
    BOOL directory = [child[WQChildIsDirectoryKey] boolValue];
    NSString *name = child[WQChildNameKey] ?: @"";
    NSString *path = [[self currentPath] stringByAppendingPathComponent:name];

    __weak typeof(self) weakSelf = self;
    UIContextualAction *delete = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleDestructive
                            title:WQML(@"LENS_DELETE", @"删除")
                          handler:^(__unused UIContextualAction *action,
                                    __unused UIView *sourceView,
                                    void (^completion)(BOOL)) {
        completion(YES);
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        [self confirmDeletionOfChildren:@[child]];
    }];
    delete.image = [UIImage systemImageNamed:@"trash"];

    NSMutableArray<UIContextualAction *> *actions = [NSMutableArray arrayWithObject:delete];
    if (!directory) {
        UIContextualAction *share = [UIContextualAction
            contextualActionWithStyle:UIContextualActionStyleNormal
                                title:WQML(@"LENS_SHARE", @"分享")
                              handler:^(__unused UIContextualAction *action,
                                        __unused UIView *sourceView,
                                        void (^completion)(BOOL)) {
            completion(YES);
            UIActivityViewController *sheet = [[UIActivityViewController alloc]
                                               initWithActivityItems:@[[NSURL fileURLWithPath:path]]
                                               applicationActivities:nil];
            sheet.popoverPresentationController.sourceView = sourceView;
            sheet.popoverPresentationController.sourceRect = sourceView.bounds;
            [weakSelf presentViewController:sheet animated:YES completion:nil];
        }];
        share.image = [UIImage systemImageNamed:@"square.and.arrow.up"];
        [actions insertObject:share atIndex:0];
    }

    UISwipeActionsConfiguration *config = [UISwipeActionsConfiguration configurationWithActions:actions];
    // Deleting a whole folder by accident must never be one careless swipe away.
    config.performsFirstActionWithFullSwipe = NO;
    return config;
}

- (void)tapHaptic
{
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [generator impactOccurred];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return (NSInteger)[self rows].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    WQMLensCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
    NSDictionary *child = [self rows][(NSUInteger)indexPath.row];
    BOOL directory = [child[WQChildIsDirectoryKey] boolValue];
    NSString *subtitle = [NSString stringWithFormat:@"%@%@",
                          WQMFormatBytes([child[WQChildBytesKey] unsignedLongLongValue]),
                          directory ? WQML(@"LENS_FOLDER", @" · 文件夹") : @""];
    [cell configureTitle:child[WQChildNameKey] subtitle:subtitle directory:directory];
    [cell setPicking:_picking picked:[_picked containsIndex:(NSUInteger)indexPath.row]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (_picking) {
        if ([_picked containsIndex:(NSUInteger)indexPath.row]) {
            [_picked removeIndex:(NSUInteger)indexPath.row];
        } else {
            [_picked addIndex:(NSUInteger)indexPath.row];
        }
        [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
        [self tapHaptic];
        [self updateActionBar];
        return;
    }
    NSDictionary *child = [self rows][(NSUInteger)indexPath.row];
    NSString *name = child[WQChildNameKey];
    NSString *path = [[self currentPath] stringByAppendingPathComponent:name ?: @""];
    if ([child[WQChildIsDirectoryKey] boolValue]) {
        [_titles addObject:name];
        [_paths addObject:path];
        [self reloadCurrentLevel];
    } else {
        [self presentFileInfo:path name:name bytes:[child[WQChildBytesKey] unsignedLongLongValue]];
    }
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section
{
    return [UIView new];
}

@end
