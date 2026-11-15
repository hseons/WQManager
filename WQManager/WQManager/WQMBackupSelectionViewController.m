#import "WQMBackupSelectionViewController.h"
#import "WQMBackupSelection.h"
#import "WQMAppModel.h"
#import "WQMAlertPresenter.h"
#import "WQMLanguageManager.h"
#import "WQMTheme.h"
#import "WQAccess.h"
#import "WQAccessSafety.h"
#import "WQMContainerAccess.h"
#import "WQMLongOperationBanner.h"

@implementation WQMBackupSelectionViewController {
    WQMAppModel *_app;
    NSString *_relative;
    NSMutableSet<NSString *> *_selected;
    NSArray<NSString *> *_folders;
    NSString *_errorText;
    void (^_completion)(WQMBackupScopeDescriptor *);
    BOOL _loading;
}
- (instancetype)initWithApp:(WQMAppModel *)app completion:(void (^)(WQMBackupScopeDescriptor *))completion
{
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) { _app = app; _relative = @""; _selected = [NSMutableSet new]; _completion = [completion copy]; }
    return self;
}
- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = _relative.length ? _relative.lastPathComponent : WQML(@"CUSTOM_BACKUP", @"自定义备份");
    self.tableView.backgroundColor = WQMTheme.canvasColor;
    self.view.tintColor = WQMTheme.accentColor;
    self.tableView.accessibilityIdentifier = @"backup.selection.table";
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:WQML(@"BACKUP_USE_SELECTION", @"使用所选") style:UIBarButtonItemStylePlain target:self action:@selector(done)];
    self.refreshControl = [UIRefreshControl new];
    [self.refreshControl addTarget:self action:@selector(loadFolders) forControlEvents:UIControlEventValueChanged];
    [self loadFolders];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.tableView reloadData]; [self updateSelection]; }
- (void)updateSelection { self.navigationItem.rightBarButtonItem.enabled = _selected.count > 0; }
- (void)loadFolders
{
    if (_loading) return;
    if (![WQMLongOperationBanner startOperationWithTitle:WQML(@"CUSTOM_BACKUP", @"自定义备份") status:WQML(@"FILE_SCANNING", @"正在读取文件索引…") cancelHandler:nil]) {
        _errorText = WQML(@"FILE_OPERATION_BUSY", @"请等待当前操作完成后下拉刷新。");
        [self.refreshControl endRefreshing]; [self.tableView reloadData]; return;
    }
    _loading = YES;
    WQMAppModel *app = _app;
    NSString *relative = _relative;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSMutableArray *folders = [NSMutableArray new];
        struct stat st;
        int access = WQMOpenAppContainer(app);
        BOOL valid = access >= 0;
        if (access >= 0) close(access);
        NSString *path = [app.containerPath stringByAppendingPathComponent:relative];
        int fd = valid ? WQOpenDirectoryNoLinks(path) : -1;
        if (fd >= 0) {
            NSArray *names = relative.length ? [NSFileManager.defaultManager contentsOfDirectoryAtPath:path error:nil] : @[@"Documents", @"Library", @"tmp"];
            for (NSString *name in names) {
                NSString *child = relative.length ? [relative stringByAppendingPathComponent:name] : name;
                if ([WQMBackupSelection isAllowedPath:child] && fstatat(fd, name.fileSystemRepresentation, &st, AT_SYMLINK_NOFOLLOW) == 0 && S_ISDIR(st.st_mode)) [folders addObject:child];
            }
            close(fd);
        }
        wq_drop_grant(app.containerPath);
        dispatch_async(dispatch_get_main_queue(), ^{
            [WQMLongOperationBanner.shared hide];
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self->_loading = NO;
            [self.refreshControl endRefreshing];
            self->_folders = [folders sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
            self->_errorText = fd < 0 ? WQML(@"FILE_SCAN_FAILED", @"目录已变化或访问受限，请刷新应用列表后重试。") : nil;
            [self.tableView reloadData];
        });
    });
}
- (BOOL)isCovered:(NSString *)path
{
    for (NSString *selected in _selected) if ([path hasPrefix:[selected stringByAppendingString:@"/"]]) return YES;
    return NO;
}
- (void)togglePath:(NSString *)path
{
    if ([self isCovered:path]) return;
    if ([_selected containsObject:path]) [_selected removeObject:path];
    else {
        NSArray *canonical = [WQMBackupSelection canonicalPaths:[_selected.allObjects arrayByAddingObject:path]];
        if (!canonical) { [WQMAlertPresenter presentAlertWithTitle:WQML(@"CUSTOM_BACKUP", @"自定义备份") message:WQML(@"BACKUP_SELECTION_LIMIT", @"最多选择 128 个目录，目录名称须互不冲突。")]; return; }
        [_selected setSet:[NSSet setWithArray:canonical]];
    }
    [self updateSelection]; [self.tableView reloadData];
}
- (void)done
{
    WQMBackupScopeDescriptor *descriptor = [WQMBackupScopeDescriptor descriptorForPaths:_selected.allObjects];
    if (!descriptor) return;
    UIViewController *owner = self.navigationController.viewControllers.firstObject;
    for (UIViewController *candidate in self.navigationController.viewControllers) {
        if ([candidate isKindOfClass:WQMBackupSelectionViewController.class]) break;
        owner = candidate;
    }
    void (^completion)(WQMBackupScopeDescriptor *) = _completion;
    [self.navigationController popToViewController:owner animated:YES];
    id<UIViewControllerTransitionCoordinator> transition = self.navigationController.transitionCoordinator;
    if (transition) [transition animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) { if (completion) completion(descriptor); }];
    else if (completion) completion(descriptor);
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return MAX(1, _folders.count); }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return [NSString stringWithFormat:WQML(@"BACKUP_SELECTED_FOLDERS", @"已选 %lu 个目录"), (unsigned long)_selected.count]; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    return _errorText ?: WQML(@"BACKUP_SELECTION_FOOTER", @"点击目录进入，点击圆圈选择。只备份并恢复勾选目录；选择父目录会包含其全部内容。恢复会替换所选目录，保留其他目录。只选 Documents 可创建精简的文稿备份，可能不包含设置或登录状态。");
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    UIListContentConfiguration *content = [cell defaultContentConfiguration];
    content.secondaryTextProperties.numberOfLines = 0;
    if (!_folders.count) content.text = WQML(@"BACKUP_NO_FOLDERS", @"没有可选的子目录");
    else {
        NSString *path = _folders[indexPath.row];
        BOOL covered = [self isCovered:path];
        content.text = path.lastPathComponent;
        content.secondaryText = covered ? WQML(@"BACKUP_PARENT_SELECTED", @"已包含在选中的父目录中") : path;
        content.image = [UIImage systemImageNamed:@"folder"];
        UIButton *check = [UIButton buttonWithType:UIButtonTypeSystem];
        [check setImage:[UIImage systemImageNamed:([_selected containsObject:path] || covered) ? @"checkmark.circle.fill" : @"circle"] forState:UIControlStateNormal];
        check.frame = CGRectMake(0, 0, 44, 44); check.enabled = !covered;
        check.accessibilityLabel = path; check.accessibilityTraits |= [_selected containsObject:path] ? UIAccessibilityTraitSelected : UIAccessibilityTraitNone;
        __weak typeof(self) weakSelf = self;
        [check addAction:[UIAction actionWithHandler:^(UIAction *action) { [weakSelf togglePath:path]; }] forControlEvents:UIControlEventTouchUpInside];
        cell.accessoryView = check;
    }
    cell.contentConfiguration = content; return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (!_folders.count || _loading) return;
    WQMBackupSelectionViewController *child = [[WQMBackupSelectionViewController alloc] initWithApp:_app completion:_completion];
    child->_relative = _folders[indexPath.row]; child->_selected = _selected;
    [self.navigationController pushViewController:child animated:YES];
}
@end
