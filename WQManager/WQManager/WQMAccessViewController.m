#import "WQMAccessViewController.h"
#import "WQMAccessDiagnostics.h"
#import "WQMAppCache.h"
#import "WQMAppModel.h"
#import "WQAccess.h"
#import "WQMLanguageManager.h"
#import "WQMLongOperationBanner.h"
#import "WQMTheme.h"

@interface WQMAccessAppPicker : UITableViewController <UISearchResultsUpdating>
@property (nonatomic, copy) NSArray<WQMAppModel *> *apps;
@property (nonatomic, copy) NSArray<WQMAppModel *> *filtered;
@property (nonatomic, copy) void (^selected)(WQMAppModel *);
@end

@implementation WQMAccessAppPicker
- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = WQML(@"ACCESS_SELECT", @"选择检查的 App");
    self.tableView.backgroundColor = WQMTheme.canvasColor;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    UISearchController *search = [[UISearchController alloc] initWithSearchResultsController:nil];
    search.searchResultsUpdater = self;
    search.obscuresBackgroundDuringPresentation = NO;
    self.navigationItem.searchController = search;
    self.definesPresentationContext = YES;
    self.filtered = self.apps;
}
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController
{
    NSString *query = searchController.searchBar.text ?: @"";
    self.filtered = !query.length ? self.apps : [self.apps filteredArrayUsingPredicate:
        [NSPredicate predicateWithBlock:^BOOL(WQMAppModel *app, NSDictionary *bindings) {
            return [app.displayName localizedCaseInsensitiveContainsString:query] ||
                [app.bundleIdentifier localizedCaseInsensitiveContainsString:query];
        }]];
    [self.tableView reloadData];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.filtered.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"app"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"app"];
    WQMAppModel *app = self.filtered[indexPath.row];
    UIListContentConfiguration *content = cell.defaultContentConfiguration;
    content.text = app.displayName;
    content.secondaryText = app.bundleIdentifier.length ? app.bundleIdentifier : WQML(@"UNKNOWN_CONTAINER", @"未知容器");
    content.textProperties.color = WQMTheme.textPrimaryColor;
    content.secondaryTextProperties.color = WQMTheme.textSecondaryColor;
    cell.backgroundColor = WQMTheme.surfaceColor;
    cell.contentConfiguration = content;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    WQMAppModel *app = self.filtered[indexPath.row];
    self.navigationItem.searchController.active = NO;
    self.selected(app);
    [self.navigationController popViewControllerAnimated:YES];
}
@end

@implementation WQMAccessViewController {
    NSDictionary *_environment;
    WQMAppCacheSnapshot *_snapshot;
    WQMAppModel *_selectedApp;
    WQMAccessReport *_report;
    WQScanCancellation *_cancellation;
    BOOL _running;
    BOOL _loading;
    UIBarButtonItem *_shareItem;
}
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (instancetype)initWithApp:(WQMAppModel *)app { if ((self = [self init])) _selectedApp = [app snapshotCopy]; return self; }
- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = WQML(@"ACCESS_TITLE", @"访问能力");
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.tableView.backgroundColor = WQMTheme.canvasColor;
    self.tableView.cellLayoutMarginsFollowReadableWidth = YES;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 90;
    _shareItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"square.and.arrow.up"]
        style:UIBarButtonItemStylePlain target:self action:@selector(exportReport)];
    _shareItem.accessibilityLabel = WQML(@"ACCESS_EXPORT", @"导出脱敏报告");
    _shareItem.enabled = NO;
    self.navigationItem.rightBarButtonItem = _shareItem;
    [self loadEnvironment];
}
- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    if (self.isMovingFromParentViewController) [_cancellation cancel];
}
- (void)loadEnvironment
{
    _loading = YES;
    BOOL protectedData = UIApplication.sharedApplication.protectedDataAvailable;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSDictionary *environment = [WQMAccessDiagnostics environmentWithProtectedDataAvailable:protectedData];
        WQMAppCacheSnapshot *snapshot = [WQMAppCache load];
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_environment = environment;
            self->_snapshot = snapshot;
            self->_loading = NO;
            [self.tableView reloadData];
        });
    });
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 4; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == 0) return 5;
    if (section == 1) return 2;
    if (section == 2) return _report.checks.count ?: 1;
    return 1;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return @[
        WQML(@"ACCESS_ENVIRONMENT", @"当前运行环境"),
        WQML(@"ACCESS_TARGET", @"按需检查一个 App"),
        WQML(@"ACCESS_RESULTS", @"本次检查结果"),
        WQML(@"ACCESS_SCOPE", @"结果范围"),
    ][section];
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (section == 0) return WQML(@"ACCESS_SIGNING_FOOTER", @"签名信息来自当前进程的实际权限。App Group 可用不代表其他 App 已可访问；证书品牌与签名工具不作推断。");
    if (section == 1) {
        if (!_snapshot.apps.count) return WQML(@"ACCESS_NO_INDEX", @"先在「应用」页完成扫描，再回来选择目标；此页不启动全盘扫描。");
        NSDateFormatter *formatter = [NSDateFormatter new];
        formatter.locale = WQMLanguageManager.sharedManager.locale;
        formatter.dateStyle = NSDateFormatterShortStyle;
        formatter.timeStyle = NSDateFormatterShortStyle;
        return [NSString stringWithFormat:WQML(@"ACCESS_INDEX_DATE", @"索引时间：%@。检查只读取所选 App，不会刷新索引。"), [formatter stringFromDate:_snapshot.updatedAt]];
    }
    if (section == 2 && _report) {
        NSDateFormatter *formatter = [NSDateFormatter new];
        formatter.locale = WQMLanguageManager.sharedManager.locale;
        formatter.dateStyle = NSDateFormatterShortStyle; formatter.timeStyle = NSDateFormatterMediumStyle;
        return [NSString stringWithFormat:WQML(@"ACCESS_CHECK_DATE", @"检查时间：%@ · %.2f 秒。导出包含上述环境与错误码，移除 App 名、Bundle ID、路径、token 和文件内容。"),
            [formatter stringFromDate:_report.createdAt], _report.duration];
    }
    return nil;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"access"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"access"];
    UIListContentConfiguration *content = cell.defaultContentConfiguration;
    content.textProperties.color = WQMTheme.textPrimaryColor;
    content.secondaryTextProperties.color = WQMTheme.textSecondaryColor;
    content.textProperties.numberOfLines = 0;
    content.secondaryTextProperties.numberOfLines = 0;
    content.imageProperties.tintColor = WQMTheme.textPrimaryColor;
    cell.backgroundColor = WQMTheme.surfaceColor;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessibilityIdentifier = nil;
    NSInteger row = indexPath.row;
    if (indexPath.section == 0) {
        content.image = [UIImage systemImageNamed:@[@"iphone", @"checkmark.seal", @"signature", @"lock.open", @"app.badge"][row]];
        content.text = @[
            WQML(@"ACCESS_DEVICE", @"设备与系统"), @"App Group",
            WQML(@"ACCESS_SIGNING", @"签名证据"),
            WQML(@"ACCESS_PROTECTION", @"受保护数据"),
            WQML(@"VERSION", @"版本"),
        ][row];
        if (!_environment) content.secondaryText = WQML(@"DETECTING", @"检测中");
        else if (row == 0) content.secondaryText = [NSString stringWithFormat:@"%@ · iOS %@ (%@)\n%@",
            _environment[@"Hardware"] ?: @"—", _environment[@"OSVersion"], _environment[@"OSBuild"] ?: @"—",
            [_environment[@"Simulator"] boolValue] ? WQML(@"ACCESS_SIMULATOR", @"模拟器 · 仅用于 UI／服务验证") : WQML(@"ACCESS_DEVICE_RUNTIME", @"真机 · 以本次观察结果为准")];
        else if (row == 1) content.secondaryText = ![_environment[@"SigningEntitlementsReadable"] boolValue]
            ? WQML(@"ACCESS_SIGNING_UNKNOWN", @"本次未取得完整签名权限信息；请以真机检查和实际目录访问结果为准。")
            : [_environment[@"UsableAppGroup"] boolValue]
            ? WQML(@"ACCESS_GROUP_OK", @"签名包含 App Group，且共享目录可打开。")
            : [_environment[@"AppGroupEntitlementCount"] unsignedIntegerValue]
                ? WQML(@"ACCESS_GROUP_UNREACHABLE", @"签名包含 App Group，但共享目录打开失败；请检查签名配置。")
                : WQML(@"ACCESS_GROUP_MISSING", @"当前签名未保留 App Group；请保留该权限重新签名。它是 WQ 访问的前置条件。");
        else if (row == 2) content.secondaryText = [NSString stringWithFormat:WQML(@"ACCESS_SIGNING_VALUES", @"开发调试权限：%@\n内嵌描述文件：%@"),
            [_environment[@"DevelopmentEntitlement"] boolValue] ? WQML(@"ACCESS_PRESENT", @"存在") : WQML(@"ACCESS_NOT_OBSERVED", @"未观察到"),
            [_environment[@"EmbeddedProfilePresent"] boolValue] ? WQML(@"ACCESS_PRESENT", @"存在") : WQML(@"ACCESS_NOT_OBSERVED", @"未观察到")];
        else if (row == 3) content.secondaryText = [_environment[@"ProtectedDataAvailable"] boolValue]
            ? WQML(@"ACCESS_PROTECTION_OK", @"当前进程可访问受保护数据；其他 App 的单个文件仍需实测。")
            : WQML(@"ACCESS_PROTECTION_LOCKED", @"当前受保护数据不可用；请解锁设备后重试。");
        else content.secondaryText = [NSString stringWithFormat:@"%@ (%@)", _environment[@"AppVersion"], _environment[@"AppBuild"]];
    } else if (indexPath.section == 1) {
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        if (row == 0) {
            content.text = _selectedApp.displayName ?: WQML(@"ACCESS_SELECT", @"选择检查的 App");
            content.secondaryText = WQML(@"ACCESS_SELECT_SUB", @"从已有 App 索引选择目标，包括受限项目");
            content.image = [UIImage systemImageNamed:@"square.grid.2x2"];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.accessibilityIdentifier = @"access.select";
        } else {
            content.text = _running ? WQML(@"ACCESS_STOP", @"停止检查") : WQML(@"ACCESS_RUN", @"开始检查");
            content.secondaryText = WQML(@"ACCESS_RUN_SUB", @"逐项检查目录与文件读取样本；不写入目标 App");
            content.image = [UIImage systemImageNamed:_running ? @"stop.circle" : @"stethoscope"];
            cell.accessibilityIdentifier = @"access.run";
        }
        BOOL enabled = !_loading && (row == 0 ? !_running && _snapshot.apps.count > 0 : _running || _selectedApp != nil);
        if (!enabled) { content.textProperties.color = WQMTheme.textSecondaryColor; cell.selectionStyle = UITableViewCellSelectionStyleNone; }
    } else if (indexPath.section == 2) {
        if (_report.checks.count) {
            WQMAccessCheck *check = _report.checks[row];
            content.text = check.title;
            content.secondaryText = check.detail;
            content.image = [UIImage systemImageNamed:[check.status isEqual:@"passed"] ? @"checkmark.circle" : [check.status isEqual:@"failed"] ? @"exclamationmark.circle" : @"minus.circle"];
        } else {
            content.text = _running ? WQML(@"ACCESS_RUNNING", @"正在检查…") : WQML(@"ACCESS_NOT_TESTED", @"未验证");
            content.secondaryText = WQML(@"ACCESS_EMPTY", @"选中一个 App 后开始。失败时会显示具体阶段与下一步建议。");
            content.image = [UIImage systemImageNamed:@"stethoscope"];
        }
    } else {
        content.text = WQML(@"ACCESS_SCOPE_TITLE", @"App 数据容器 · 有限抽样");
        content.secondaryText = WQML(@"ACCESS_SCOPE_DETAIL", @"每个目录最多检查 64 个直接条目，Documents／Library／tmp 各读取一个普通文件的最多 1 字节。空目录或未发现样本会标记未验证。\n\n共享 App Groups、扩展、系统容器和写入能力尚未验证。访问 token 沿用现有 WQ 流程，会临时使用工具自己的 App Group 缓存目录。");
        content.image = [UIImage systemImageNamed:@"info.circle"];
    }
    cell.contentConfiguration = content;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 1 || _loading) return;
    if (indexPath.row == 1) { if (_running) [_cancellation cancel]; else if (_selectedApp) [self runCheck]; return; }
    if (_running || !_snapshot.apps.count) return;
    WQMAccessAppPicker *picker = [[WQMAccessAppPicker alloc] initWithStyle:UITableViewStyleInsetGrouped];
    picker.apps = [WQMAppModel apps:_snapshot.apps sortedByOrder:WQMAppSortOrderName];
    __weak typeof(self) weakSelf = self;
    picker.selected = ^(WQMAppModel *app) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self->_selectedApp = app; self->_report = nil; self->_shareItem.enabled = NO;
        [self.tableView reloadData];
    };
    [self.navigationController pushViewController:picker animated:YES];
}
- (void)runCheck
{
    WQScanCancellation *cancellation = [WQScanCancellation new];
    if (![WQMLongOperationBanner startOperationWithTitle:WQML(@"ACCESS_RUNNING", @"正在检查…") status:nil
        cancelHandler:^{ [cancellation cancel]; }]) return;
    _cancellation = cancellation; _running = YES; _report = nil; _shareItem.enabled = NO;
    [self.tableView reloadData];
    WQMAppModel *app = _selectedApp;
    BOOL protectedData = UIApplication.sharedApplication.protectedDataAvailable;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSString *root = @"/private/var/mobile/Containers/Data/Application";
        BOOL fixture = NO;
#if DEBUG
        fixture = [NSProcessInfo.processInfo.environment[@"WQM_UI_FIXTURES"] boolValue] &&
            [app.bundleIdentifier isEqual:@"com.tencent.xin"] &&
            [app.containerPath isEqual:[NSTemporaryDirectory() stringByAppendingPathComponent:@"WQMContainerFixture"]];
        if (fixture) root = app.containerPath.stringByDeletingLastPathComponent;
#endif
        WQMAccessDiagnostics *diagnostics = [[WQMAccessDiagnostics alloc] initWithContainerRoot:root
            grant:^BOOL(NSString *path, NSInteger *code, int *systemError) {
                return fixture ? YES : wq_grant_with_diagnostics(path, code, systemError);
            } label:^NSString *(NSString *path) { return fixture ? app.bundleIdentifier : wq_container_label(path); }];
        NSMutableDictionary *environment = [[WQMAccessDiagnostics environmentWithProtectedDataAvailable:protectedData] mutableCopy];
        environment[@"SyntheticTarget"] = @(fixture);
        WQMAccessReport *report = [diagnostics probeApp:app environment:environment cancelled:^BOOL { return cancellation.cancelled; }];
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_running = NO; self->_report = report; self->_environment = environment;
            self->_shareItem.enabled = YES;
            [WQMLongOperationBanner.shared hide];
            [self.tableView reloadData];
            UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,
                WQML(@"ACCESS_FINISHED", @"检查已结束，可查看结果。"));
        });
    });
}
- (void)exportReport
{
    NSData *data = [_report redactedJSONData];
    if (!data) return;
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"WQManager-access-%@.json", NSUUID.UUID.UUIDString]]];
    if (![data writeToURL:url options:NSDataWritingAtomic error:nil]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:WQML(@"ACCESS_EXPORT", @"导出脱敏报告")
            message:WQML(@"ACCESS_EXPORT_FAILED", @"报告生成失败，请稍后重试。") preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:WQML(@"OK", @"好") style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil]; return;
    }
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    activity.popoverPresentationController.barButtonItem = _shareItem;
    activity.completionWithItemsHandler = ^(UIActivityType type, BOOL completed, NSArray *items, NSError *error) {
        [NSFileManager.defaultManager removeItemAtURL:url error:nil];
    };
    [self presentViewController:activity animated:YES completion:nil];
}
@end
