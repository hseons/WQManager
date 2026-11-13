//
//  WQMTrashViewController.m
//  WQManager
//

#import "WQMTrashViewController.h"
#import "WQMTrashStore.h"
#import "WQMTheme.h"
#import "WQMLanguageManager.h"

static NSString *WQMTrashBytes(unsigned long long bytes)
{
    NSByteCountFormatter *formatter = [NSByteCountFormatter new];
    formatter.countStyle = NSByteCountFormatterCountStyleFile;
    formatter.allowedUnits = NSByteCountFormatterUseAll;
    return [formatter stringFromByteCount:(long long)bytes];
}

@interface WQMTrashViewController ()

@property (nonatomic, copy) NSArray<WQMTrashSession *> *sessions;
@property (nonatomic, strong) UIView *emptyView;

@end

@implementation WQMTrashViewController

- (instancetype)init
{
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = WQML(@"LENS_TRASH_TITLE", @"空间透镜回收站");
    self.tableView.backgroundColor = WQMTheme.canvasColor;
    self.tableView.separatorColor = WQMTheme.separatorColor;
    self.tableView.rowHeight = 64;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:WQML(@"LENS_TRASH_CLEAR", @"清空")
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(clearTapped)];
    [self buildEmptyView];
    [self reloadTrash];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self reloadTrash];
}

- (void)buildEmptyView
{
    UILabel *label = [UILabel new];
    label.text = WQML(@"LENS_TRASH_EMPTY_SUB", @"从空间透镜删除的文件会先放在这里，可以随时还原。");
    label.textColor = WQMTheme.textSecondaryColor;
    label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    label.translatesAutoresizingMaskIntoConstraints = NO;

    UIImageView *icon = [UIImageView new];
    icon.image = [UIImage systemImageNamed:@"trash"
                         withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:34
                                                                                          weight:UIImageSymbolWeightRegular]];
    icon.tintColor = WQMTheme.textSecondaryColor;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *stack = [UIStackView new];
    [stack addArrangedSubview:icon];
    [stack addArrangedSubview:label];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    // A UITableViewController's view *is* the table, so the empty state has to
    // live in backgroundView — hiding the table would hide it too.
    UIView *container = [[UIView alloc] initWithFrame:self.tableView.bounds];
    container.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [container addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:container.centerYAnchor constant:-40],
        [label.widthAnchor constraintLessThanOrEqualToConstant:280],
    ]];
    self.emptyView = container;
    self.tableView.backgroundView = container;
}

- (void)reloadTrash
{
    self.sessions = [WQMTrashStore sessions];
    BOOL empty = self.sessions.count == 0;
    self.emptyView.hidden = !empty;
    self.navigationItem.rightBarButtonItem.enabled = !empty;
    [self.tableView reloadData];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return (NSInteger)self.sessions.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return (NSInteger)self.sessions[(NSUInteger)section].items.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    WQMTrashSession *session = self.sessions[(NSUInteger)section];
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = NSLocale.currentLocale;
    formatter.dateFormat = WQML(@"LENS_TRASH_DATE_FORMAT", @"M月d日 HH:mm");
    NSString *when = [formatter stringFromDate:session.createdAt];
    if (!session.sourcePath.length) {
        return [NSString stringWithFormat:@"%@ · %@", when, WQML(@"LENS_TRASH_UNKNOWN_SOURCE", @"原位置未知")];
    }
    return [NSString stringWithFormat:@"%@ · %@ %@", when,
            WQML(@"LENS_TRASH_SOURCE", @"来自"), session.sourcePath.lastPathComponent];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    WQMTrashSession *session = self.sessions[(NSUInteger)section];
    return [NSString stringWithFormat:WQML(@"LENS_TRASH_ITEM_COUNT", @"%lu 项 · %@"),
            (unsigned long)session.items.count, WQMTrashBytes(session.totalBytes)];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *identifier = @"trash";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
        cell.backgroundColor = WQMTheme.surfaceColor;
        cell.textLabel.textColor = WQMTheme.textPrimaryColor;
        cell.detailTextLabel.textColor = WQMTheme.textSecondaryColor;
    }
    WQMTrashItem *item = self.sessions[(NSUInteger)indexPath.section].items[(NSUInteger)indexPath.row];
    cell.textLabel.text = item.name;
    cell.textLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    NSString *size = WQMTrashBytes(item.bytes);
    cell.detailTextLabel.text = item.directory
        ? [NSString stringWithFormat:@"%@%@", size, WQML(@"LENS_FOLDER", @" · 文件夹")]
        : size;
    cell.imageView.image = [UIImage systemImageNamed:item.directory ? @"folder.fill" : @"doc.fill"];
    cell.imageView.tintColor = item.directory
        ? [UIColor colorWithRed:0.16 green:0.62 blue:1.0 alpha:1.0]
        : WQMTheme.textSecondaryColor;
    cell.accessoryType = UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    WQMTrashItem *item = self.sessions[(NSUInteger)indexPath.section].items[(NSUInteger)indexPath.row];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:item.name
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    BOOL canRestore = item.originalPath.length > 0;
    [sheet addAction:[UIAlertAction actionWithTitle:WQML(@"LENS_TRASH_RESTORE", @"还原")
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        [self restoreItem:item];
    }]];
    if (!canRestore) {
        sheet.actions.firstObject.enabled = NO;
    }
    [sheet addAction:[UIAlertAction actionWithTitle:WQML(@"LENS_TRASH_DELETE", @"从回收站删除")
                                              style:UIAlertActionStyleDestructive
                                            handler:^(__unused UIAlertAction *action) {
        [WQMTrashStore removeItem:item];
        [self reloadTrash];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:WQML(@"CANCEL", @"取消")
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    sheet.popoverPresentationController.sourceView = [tableView cellForRowAtIndexPath:indexPath];
    sheet.popoverPresentationController.sourceRect = [tableView rectForRowAtIndexPath:indexPath];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)restoreItem:(WQMTrashItem *)item
{
    NSError *error = nil;
    BOOL ok = [WQMTrashStore restoreItem:item error:&error];
    [self reloadTrash];
    if (ok) {
        [self presentMessage:WQML(@"LENS_TRASH_RESTORED", @"已还原") body:item.name];
        return;
    }
    NSString *reason = [error.userInfo[NSLocalizedDescriptionKey] isEqualToString:@"destination exists"]
        ? WQML(@"LENS_TRASH_RESTORE_CONFLICT", @"原位置已有同名文件，未覆盖。")
        : WQML(@"LENS_TRASH_RESTORE_FAILED", @"无法还原这个项目。");
    [self presentMessage:WQML(@"LENS_TRASH_FAILED", @"还原失败") body:reason];
}

- (void)clearTapped
{
    unsigned long long bytes = [WQMTrashStore totalBytes];
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:WQML(@"LENS_TRASH_CLEAR_TITLE", @"清空回收站？")
                         message:[NSString stringWithFormat:
                                  WQML(@"LENS_TRASH_CLEAR_MESSAGE", @"将永久删除 %@，此操作无法撤销。"),
                                  WQMTrashBytes(bytes)]
                  preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:WQML(@"LENS_TRASH_CLEAR", @"清空")
                                              style:UIAlertActionStyleDestructive
                                            handler:^(__unused UIAlertAction *action) {
        [WQMTrashStore emptyAll];
        [self reloadTrash];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:WQML(@"CANCEL", @"取消")
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    alert.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:alert animated:YES completion:nil];
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

@end
