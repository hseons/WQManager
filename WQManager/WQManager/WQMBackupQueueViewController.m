#import "WQMBackupQueueViewController.h"
#import "WQMBackupQueue.h"
#import "WQMBackupService.h"
#import "WQMBackupStore.h"
#import "WQMAppModel.h"
#import "WQMLongOperationBanner.h"
#import "WQMAlertPresenter.h"
#import "WQMLanguageManager.h"
#import "WQMTheme.h"

@implementation WQMBackupQueueViewController {
    NSArray<WQMAppModel *> *_apps;
    NSMutableSet<NSString *> *_selected;
    WQMBackupQueue *_queue;
    BOOL _previousIdleTimerDisabled;
}
- (instancetype)initWithApps:(NSArray<WQMAppModel *> *)apps
{
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _apps = apps;
        _selected = [NSMutableSet new];
        _queue = [[WQMBackupQueue alloc] initWithExecutor:^(WQMAppModel *app, NSInteger scope, void (^progress)(NSString *), void (^completion)(BOOL, NSString *)) {
            [[WQMBackupService new] backupApp:app scope:scope reason:@"" progress:progress completion:^(WQMBackupRecord *backup, NSError *error) { completion(backup != nil, error.localizedDescription ?: WQML(@"BACKUP_COMPLETE_TITLE", @"备份完成")); }];
        }];
        __weak typeof(self) weakSelf = self;
        _queue.didChange = ^{ [weakSelf updateQueue]; };
        _queue.didFinish = ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            UIApplication.sharedApplication.idleTimerDisabled = self->_previousIdleTimerDisabled;
            [WQMLongOperationBanner.shared hide];
            [self updateQueue];
        };
    }
    return self;
}
- (void)updateApps:(NSArray<WQMAppModel *> *)apps
{
    if (_queue.running) return;
    _apps = apps;
    for (WQMBackupJob *job in _queue.jobs) {
        if (job.status != WQMBackupJobFailed) continue;
        for (WQMAppModel *app in apps) if ([app.bundleIdentifier isEqual:job.app.bundleIdentifier]) { job.app = app; break; }
    }
    NSMutableSet *available = [NSMutableSet new];
    for (WQMAppModel *app in apps) if (app.accessAvailable && app.identityKnown && app.bundleIdentifier.length) [available addObject:app.bundleIdentifier];
    [_selected intersectSet:available];
    if (self.isViewLoaded) [self.tableView reloadData];
}
- (void)viewDidLoad
{
    [super viewDidLoad]; self.title = WQML(@"BATCH_BACKUP", @"批量备份");
    self.tableView.backgroundColor = WQMTheme.canvasColor;
    self.view.tintColor = WQMTheme.accentColor;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.accessibilityIdentifier = @"backup.queue.table";
    [self updateQueue];
}
- (void)updateQueue
{
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:_queue.running ? WQML(@"BATCH_STOP_REMAINING", @"停止剩余") : WQML(@"BATCH_ACTIONS", @"操作") style:UIBarButtonItemStylePlain target:self action:@selector(actions)];
    if (_queue.running) {
        NSUInteger finished = 0;
        NSString *current = @"";
        for (WQMBackupJob *job in _queue.jobs) {
            if (job.status == WQMBackupJobSucceeded || job.status == WQMBackupJobFailed || job.status == WQMBackupJobCancelled) finished++;
            if (job.status == WQMBackupJobRunning) current = [NSString stringWithFormat:@"%@ · %@", job.app.displayName, job.message];
        }
        [WQMLongOperationBanner.shared updateStatus:[NSString stringWithFormat:@"%lu/%lu · %@", (unsigned long)finished, (unsigned long)_queue.jobs.count, current]];
    }
    if (self.isViewLoaded) [self.tableView reloadData];
}
- (void)actions
{
    if (_queue.running) { [_queue stopRemaining]; return; }
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:WQML(@"BATCH_BACKUP", @"批量备份") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:WQML(@"BATCH_SELECT_ALL", @"选择所有可用 App") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        for (WQMAppModel *app in self->_apps) if (app.accessAvailable && app.identityKnown && app.bundleIdentifier.length) [self->_selected addObject:app.bundleIdentifier];
        [self.tableView reloadData];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:WQML(@"BATCH_DESELECT", @"取消全选") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [self->_selected removeAllObjects]; [self.tableView reloadData]; }]];
    for (NSNumber *scope in @[@(WQMBackupScopeQuick), @(WQMBackupScopeFull)]) {
        NSString *title = scope.integerValue == WQMBackupScopeQuick ? WQML(@"QUICK_BACKUP", @"快速备份") : WQML(@"FULL_BACKUP", @"完整备份");
        UIAlertAction *start = [UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [self confirmScope:scope.integerValue retry:NO]; }];
        start.enabled = _selected.count > 0;
        [sheet addAction:start];
    }
    BOOL failed = NO;
    for (WQMBackupJob *job in _queue.jobs) if (job.status == WQMBackupJobFailed) failed = YES;
    if (failed) [sheet addAction:[UIAlertAction actionWithTitle:WQML(@"BATCH_RETRY", @"重试失败项") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [self confirmScope:0 retry:YES]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:WQML(@"CANCEL", @"取消") style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:sheet animated:YES completion:nil];
}
- (void)confirmScope:(NSInteger)scope retry:(BOOL)retry
{
    NSMutableArray *apps = [NSMutableArray new], *names = [NSMutableArray new];
    for (WQMAppModel *app in _apps) if ([_selected containsObject:app.bundleIdentifier]) { [apps addObject:app]; [names addObject:app.displayName]; }
    if (retry) { [names removeAllObjects]; for (WQMBackupJob *job in _queue.jobs) if (job.status == WQMBackupJobFailed) [names addObject:job.app.displayName]; }
    NSString *detail = retry ? WQML(@"BATCH_RETRY", @"重试失败项") : [WQMBackupScopeDescriptor descriptorForScope:scope].detail;
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:WQML(@"BACKUP_CONFIRM_TITLE", @"开始备份？") message:[NSString stringWithFormat:@"%@\n\n%@\n\n%@", [names componentsJoinedByString:@", "], detail, WQML(@"BATCH_CONFIRM_MESSAGE", @"请先关闭这些 App，并保持 WQManager 在前台。将逐个备份；停止剩余任务会等待当前备份完成。中断后保留已完成的备份，剩余项需重新选择。")] preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:WQML(@"CANCEL", @"取消") style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:WQML(@"BACKUP_START", @"开始备份") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        if (![WQMLongOperationBanner startOperationWithTitle:WQML(@"BATCH_BACKUP", @"批量备份") status:WQML(@"PREPARING", @"准备中…") cancelHandler:^{ [self->_queue stopRemaining]; }]) return;
        self->_previousIdleTimerDisabled = UIApplication.sharedApplication.idleTimerDisabled;
        UIApplication.sharedApplication.idleTimerDisabled = YES;
        BOOL started = retry ? [self->_queue retryFailures] : [self->_queue startApps:apps scope:scope];
        if (!started) { UIApplication.sharedApplication.idleTimerDisabled = self->_previousIdleTimerDisabled; [WQMLongOperationBanner.shared hide]; }
    }]];
    [self presentViewController:confirm animated:YES completion:nil];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return _queue.jobs.count ? 2 : 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 0 ? _apps.count : _queue.jobs.count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return section == 0 ? [NSString stringWithFormat:WQML(@"BATCH_SELECTED_COUNT", @"已选择 %lu 个 App"), (unsigned long)_selected.count] : WQML(@"BATCH_RESULTS", @"本轮任务"); }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section { return section == 0 ? WQML(@"BATCH_SELECTION_FOOTER", @"串行执行，沿用设置中的负载模式。每个任务开始时重新核对容器身份；自定义范围请进入单个 App 设置。") : nil; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    UIListContentConfiguration *content = [cell defaultContentConfiguration];
    content.secondaryTextProperties.numberOfLines = 0;
    if (indexPath.section == 0) {
        WQMAppModel *app = _apps[indexPath.row]; content.text = app.displayName; content.secondaryText = app.statusText;
        BOOL enabled = app.accessAvailable && app.identityKnown && app.bundleIdentifier.length;
        content.textProperties.color = enabled ? WQMTheme.textPrimaryColor : WQMTheme.textSecondaryColor;
        cell.accessoryType = [_selected containsObject:app.bundleIdentifier] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        cell.userInteractionEnabled = enabled && !_queue.running;
    } else {
        WQMBackupJob *job = _queue.jobs[indexPath.row]; content.text = job.app.displayName;
        NSArray *states = @[WQML(@"BATCH_PENDING", @"等待"), WQML(@"BATCH_RUNNING", @"进行中"), WQML(@"BATCH_SUCCEEDED", @"已完成"), WQML(@"BATCH_FAILED", @"失败"), WQML(@"BATCH_CANCELLED", @"已停止")];
        content.secondaryText = [NSString stringWithFormat:@"%@ · %@", states[job.status], job.message];
    }
    cell.contentConfiguration = content; return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section || _queue.running) return;
    WQMAppModel *app = _apps[indexPath.row];
    if ([_selected containsObject:app.bundleIdentifier]) [_selected removeObject:app.bundleIdentifier]; else [_selected addObject:app.bundleIdentifier];
    [self.tableView reloadData];
}
@end
