#import "WQMStorageViewController.h"
#import "WQMStorageService.h"
#import "WQMRestoreService.h"
#import "WQMTheme.h"
#import "WQMLanguageManager.h"
#import "WQMLongOperationBanner.h"
#import "WQMAlertPresenter.h"

static NSString *WQMStorageBytes(unsigned long long bytes)
{
    NSByteCountFormatter *formatter = [NSByteCountFormatter new];
    formatter.countStyle = NSByteCountFormatterCountStyleFile;
    formatter.allowedUnits = NSByteCountFormatterUseAll;
    return [formatter stringFromByteCount:(long long)bytes];
}

@interface WQMStorageViewController ()

@property (nonatomic, strong, nullable) WQMStorageBreakdown *breakdown;
@property (nonatomic) BOOL computing;
@property (nonatomic) NSUInteger generation;

@end

@implementation WQMStorageViewController

- (instancetype)init
{
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = WQML(@"STORAGE_TITLE", @"存储占用");
    self.view.backgroundColor = WQMTheme.canvasColor;
    self.tableView.backgroundColor = WQMTheme.canvasColor;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self refresh];
}

- (void)refresh
{
    self.generation += 1;
    NSUInteger generation = self.generation;
    self.computing = YES;
    [self.tableView reloadData];

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        WQMStorageBreakdown *breakdown = [WQMStorageService breakdown];
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) self = weakSelf;
            if (!self || self.generation != generation) return;
            self.breakdown = breakdown;
            self.computing = NO;
            [self.tableView reloadData];
        });
    });
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return section == 0 ? 5 : 3;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return section == 0
        ? WQML(@"STORAGE_SECTION_USAGE", @"当前占用")
        : WQML(@"STORAGE_SECTION_ACTIONS", @"清理");
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (section == 0) {
        return WQML(@"STORAGE_USAGE_FOOTER",
                    @"备份列表只显示校验通过的备份；中断或校验失败的目录不会出现在列表里，但仍占用空间。");
    }
    return WQML(@"STORAGE_ACTIONS_FOOTER",
                @"清理前请确认没有正在进行的备份或恢复，未完成恢复引用的备份不会被删除。");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *identifier = @"storage";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                             reuseIdentifier:identifier];
    UIListContentConfiguration *content = cell.defaultContentConfiguration;
    content.textProperties.color = WQMTheme.textPrimaryColor;
    content.secondaryTextProperties.color = WQMTheme.textSecondaryColor;
    cell.backgroundColor = WQMTheme.surfaceColor;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.textLabel.enabled = YES;

    WQMStorageBreakdown *breakdown = self.breakdown;
    NSString *placeholder = self.computing ? WQML(@"STORAGE_COMPUTING", @"正在计算…") : @"—";

    if (indexPath.section == 0) {
        switch (indexPath.row) {
            case 0:
                content.text = WQML(@"STORAGE_BACKUPS", @"备份");
                content.secondaryText = breakdown
                    ? [NSString stringWithFormat:@"%lu · %@",
                       (unsigned long)breakdown.backupCount,
                       WQMStorageBytes(breakdown.backupBytes)]
                    : placeholder;
                content.image = [UIImage systemImageNamed:@"archivebox"];
                break;
            case 1:
                content.text = WQML(@"STORAGE_SAFETY", @"恢复前自动安全备份");
                content.secondaryText = breakdown
                    ? [NSString stringWithFormat:@"%lu · %@",
                       (unsigned long)breakdown.safetyCount,
                       WQMStorageBytes(breakdown.safetyBytes)]
                    : placeholder;
                content.image = [UIImage systemImageNamed:@"shield.lefthalf.filled"];
                break;
            case 2:
                content.text = WQML(@"STORAGE_INVALID", @"无效或中断的备份");
                content.secondaryText = breakdown
                    ? [NSString stringWithFormat:@"%lu · %@",
                       (unsigned long)(breakdown.invalidCount + breakdown.incompleteCount),
                       WQMStorageBytes(breakdown.invalidBytes + breakdown.incompleteBytes)]
                    : placeholder;
                content.image = [UIImage systemImageNamed:@"exclamationmark.triangle"];
                break;
            case 3:
                content.text = WQML(@"STORAGE_TEMP", @"导入/导出临时文件");
                content.secondaryText = breakdown
                    ? WQMStorageBytes(breakdown.temporaryBytes) : placeholder;
                content.image = [UIImage systemImageNamed:@"arrow.up.arrow.down"];
                break;
            default:
                content.text = WQML(@"STORAGE_CACHE", @"图标与索引缓存");
                content.secondaryText = breakdown
                    ? WQMStorageBytes(breakdown.cacheBytes) : placeholder;
                content.image = [UIImage systemImageNamed:@"square.stack.3d.up"];
                break;
        }
    } else {
        NSArray<NSString *> *titles = @[
            WQML(@"STORAGE_CLEAN_INVALID", @"清理无效与中断的备份"),
            WQML(@"STORAGE_PRUNE_SAFETY", @"只保留最近一份安全备份"),
            WQML(@"STORAGE_CLEAN_TEMP", @"清理导入/导出临时文件"),
        ];
        NSArray<NSString *> *symbols = @[@"trash", @"clock.badge.checkmark", @"trash.slash"];
        content.text = titles[(NSUInteger)indexPath.row];
        content.secondaryText = nil;
        content.image = [UIImage systemImageNamed:symbols[(NSUInteger)indexPath.row]];
        BOOL enabled = !self.computing;
        cell.selectionStyle = enabled ? UITableViewCellSelectionStyleDefault
                                      : UITableViewCellSelectionStyleNone;
        content.textProperties.color = enabled ? WQMTheme.textPrimaryColor
                                               : WQMTheme.textSecondaryColor;
    }

    content.imageProperties.tintColor = WQMTheme.textPrimaryColor;
    cell.contentConfiguration = content;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.computing || indexPath.section != 1) return;
    if (WQMLongOperationBanner.shared.isBusy) {
        [WQMAlertPresenter presentAlertWithTitle:WQML(@"OPERATION_BUSY_TITLE", @"有操作正在进行")
                                         message:WQML(@"OPERATION_BUSY_MESSAGE", @"请等待当前操作完成后再试。")];
        return;
    }

    if (indexPath.row == 0) {
        WQMStorageCleanupOptions options = WQMStorageCleanupInvalid | WQMStorageCleanupIncomplete;
        [self confirmCleanupWithTitle:WQML(@"STORAGE_CLEAN_INVALID", @"清理无效与中断的备份")
                              message:WQML(@"STORAGE_CLEAN_INVALID_CONFIRM",
                                           @"将删除校验失败和未完成的备份目录，且无法恢复。已确认过的正常备份不会受影响。")
                                 options:options];
        return;
    }
    if (indexPath.row == 1) {
        [self confirmPruneSafety];
        return;
    }
    [self confirmCleanupWithTitle:WQML(@"STORAGE_CLEAN_TEMP", @"清理导入/导出临时文件")
                          message:WQML(@"STORAGE_CLEAN_TEMP_CONFIRM",
                                       @"将删除导入、导出时留下的临时目录。不会影响已有备份。")
                             options:WQMStorageCleanupTemporary];
}

- (void)confirmCleanupWithTitle:(NSString *)title
                        message:(NSString *)message
                        options:(WQMStorageCleanupOptions)options
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:WQML(@"CANCEL", @"取消")
                                              style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:WQML(@"CLEAN", @"清理")
                                              style:UIAlertActionStyleDestructive
                                              handler:^(__unused UIAlertAction *action) {
        [self runCleanupWithOptions:options title:title];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)confirmPruneSafety
{
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:WQML(@"STORAGE_PRUNE_SAFETY", @"只保留最近一份安全备份")
                         message:WQML(@"STORAGE_PRUNE_SAFETY_CONFIRM",
                                      @"将按 App 保留最新的一份「恢复前自动安全备份」，删除更早的。普通备份不受影响。")
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:WQML(@"CANCEL", @"取消")
                                              style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:WQML(@"CLEAN", @"清理")
                                              style:UIAlertActionStyleDestructive
                                              handler:^(__unused UIAlertAction *action) {
        [self runPruneSafety];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSSet<NSString *> *)protectedPaths
{
    return [NSSet setWithArray:[WQMRestoreService pendingRecoveryBackupPaths]];
}

- (void)runCleanupWithOptions:(WQMStorageCleanupOptions)options title:(NSString *)title
{
    if (![WQMLongOperationBanner startOperationWithTitle:title status:nil cancelHandler:nil]) return;
    NSSet<NSString *> *protectedPaths = [self protectedPaths];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        unsigned long long freed = 0;
        [WQMStorageService cleanupWithOptions:options
                                    excluding:protectedPaths
                                   freedBytes:&freed
                                        error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) self = weakSelf;
            [WQMLongOperationBanner.shared hideWithCompletion:^{
                [self refresh];
                [WQMAlertPresenter presentAlertWithTitle:WQML(@"STORAGE_CLEANED_TITLE", @"已清理")
                                                 message:[NSString stringWithFormat:
                                                          WQML(@"STORAGE_CLEANED_MESSAGE", @"已释放 %@"),
                                                          WQMStorageBytes(freed)]];
            }];
        });
    });
}

- (void)runPruneSafety
{
    NSString *title = WQML(@"STORAGE_PRUNE_SAFETY", @"只保留最近一份安全备份");
    if (![WQMLongOperationBanner startOperationWithTitle:title status:nil cancelHandler:nil]) return;
    NSSet<NSString *> *protectedPaths = [self protectedPaths];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        unsigned long long freed = 0;
        NSUInteger removed = [WQMStorageService pruneSafetyBackupsKeeping:1
                                                                excluding:protectedPaths
                                                              deletedBytes:&freed];
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) self = weakSelf;
            [WQMLongOperationBanner.shared hideWithCompletion:^{
                [self refresh];
                NSString *message = removed > 0
                    ? [NSString stringWithFormat:WQML(@"STORAGE_PRUNED_MESSAGE", @"删除 %lu 份，释放 %@"),
                       (unsigned long)removed, WQMStorageBytes(freed)]
                    : WQML(@"STORAGE_NOTHING_TO_CLEAN", @"没有需要清理的内容");
                [WQMAlertPresenter presentAlertWithTitle:WQML(@"STORAGE_PRUNED_TITLE", @"已处理")
                                                 message:message];
            }];
        });
    });
}

@end
