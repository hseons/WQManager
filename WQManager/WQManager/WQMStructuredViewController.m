#import "WQMStructuredViewController.h"
#import "WQMStructuredFile.h"
#import "WQMLanguageManager.h"
#import "WQMTheme.h"
#import "WQMLongOperationBanner.h"

@implementation WQMStructuredViewController {
    NSString *_path, *_table, *_status;
    WQMStructuredFile *_file;
    id _node;
    NSArray *_keys, *_rows;
    NSUInteger _offset, _generation, _treeOffset;
    dispatch_queue_t _worker;
    BOOL _loading, _ownsFile;
}
- (instancetype)initWithPath:(NSString *)path
{
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _path = [path copy]; _ownsFile = YES;
        _worker = dispatch_queue_create("mumu.wqmanager.inspect", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}
- (instancetype)initWithFile:(WQMStructuredFile *)file node:(id)node table:(NSString *)table worker:(dispatch_queue_t)worker
{
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) { _file = file; _node = node; _table = table; _worker = worker; }
    return self;
}
- (void)viewDidLoad
{
    [super viewDidLoad];
    self.tableView.backgroundColor = WQMTheme.canvasColor;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 72;
    self.tableView.accessibilityIdentifier = @"inspect.table";
    _status = WQML(@"INSPECT_INTRO", @"只读查看。请先关闭来源 App，再制作工作副本。plist 上限 8 MB；数据库与 WAL 合计上限 512 MB。正在变化或带恢复日志的数据库会停止读取。");
    if (_node) [self prepareKeys];
    if (_table) [self loadPage:0];
}
- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    if (self.isMovingFromParentViewController || self.parentViewController.isMovingFromParentViewController) {
        _generation++;
        if (_ownsFile) _file.cancelled = YES;
    }
}
- (void)prepareKeys
{
    if ([_node isKindOfClass:NSDictionary.class]) _keys = [[_node allKeys] sortedArrayUsingSelector:@selector(compare:)];
    else _keys = nil;
    _status = WQML(@"INSPECT_PLIST_NOTE", @"plist 树 · 每页最多 200 项。点击容器展开，点击值查看详情。");
    [self.tableView reloadData];
}
- (void)prepare
{
    if (_loading) return;
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:WQML(@"INSPECT_OPEN", @"制作只读工作副本") message:_status preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:WQML(@"CANCEL", @"取消") style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:WQML(@"CONTINUE", @"继续") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        if (![WQMLongOperationBanner startOperationWithTitle:WQML(@"INSPECT_OPEN", @"制作只读工作副本") status:nil cancelHandler:nil]) return;
        self->_loading = YES;
        NSUInteger generation = ++self->_generation;
        NSString *path = self->_path;
        [self.tableView reloadData];
        __weak typeof(self) weakSelf = self;
        dispatch_async(self->_worker, ^{
            NSError *error;
            WQMStructuredFile *file = [[WQMStructuredFile alloc] initWithPath:path error:&error];
            dispatch_async(dispatch_get_main_queue(), ^{
                [WQMLongOperationBanner.shared hide];
                __strong typeof(weakSelf) self = weakSelf;
                if (!self || generation != self->_generation) return;
                self->_loading = NO; self->_file = file;
                self->_status = error.localizedDescription ?: WQML(@"INSPECT_DB_NOTE", @"工作副本 · 点击表查看结构和数据。每页 100 行；每个值最多显示 4 KB，BLOB 显示大小。");
                if (file.propertyList) { self->_node = file.propertyList; [self prepareKeys]; }
                [self.tableView reloadData];
            });
        });
    }]];
    [self presentViewController:confirm animated:YES completion:nil];
}
- (void)loadPage:(NSUInteger)offset
{
    if (_loading) return;
    _loading = YES; NSUInteger generation = ++_generation;
    WQMStructuredFile *file = _file; NSString *table = _table;
    __weak typeof(self) weakSelf = self;
    dispatch_async(_worker, ^{
        NSError *error;
        NSArray *rows = [file rowsForTable:table offset:offset error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || generation != self->_generation) return;
            self->_loading = NO;
            if (rows) { self->_offset = offset; self->_rows = rows; }
            self->_status = error.localizedDescription ?: [NSString stringWithFormat:WQML(@"INSPECT_PAGE", @"第 %lu–%lu 行 · 每个值最多 4 KB，BLOB 显示大小。"), (unsigned long)(offset + (rows.count ? 1 : 0)), (unsigned long)(offset + rows.count)];
            [self.tableView reloadData];
        });
    });
}
- (void)exportTable
{
    if (_loading) return;
    _loading = YES; NSUInteger generation = ++_generation;
    WQMStructuredFile *file = _file; NSString *table = _table;
    [self.tableView reloadData];
    __weak typeof(self) weakSelf = self;
    dispatch_async(_worker, ^{
        NSError *error; NSURL *url = [file exportTable:table error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || generation != self->_generation) return;
            self->_loading = NO;
            if (!url) { self->_status = error.localizedDescription; [self.tableView reloadData]; return; }
            UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
            share.popoverPresentationController.sourceView = self.tableView;
            share.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:[NSIndexPath indexPathForRow:2 inSection:0]];
            share.completionWithItemsHandler = ^(UIActivityType type, BOOL completed, NSArray *items, NSError *shareError) {
                dispatch_async(self->_worker, ^{ [NSFileManager.defaultManager removeItemAtURL:url error:nil]; });
            };
            // Retain the workspace throughout sharing, even if its screen is dismissed.
            [self presentViewController:share animated:YES completion:nil];
            [self.tableView reloadData];
        });
    });
}
- (NSUInteger)nodeCount { return [_node isKindOfClass:NSDictionary.class] ? [_node count] : [_node isKindOfClass:NSArray.class] ? [_node count] : 1; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == 0) return _table ? 3 : _node && self.nodeCount > 200 ? 2 : _file ? 0 : 1;
    if (_node) return MIN(200, self.nodeCount - MIN(_treeOffset, self.nodeCount));
    return _table ? _rows.count : _file.tables.count;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (section == 0) return WQML(@"INSPECT_TITLE", @"结构化文件");
    if (_table) return _table;
    return _node ? WQML(@"INSPECT_PLIST", @"属性列表") : WQML(@"INSPECT_TABLES", @"数据库表");
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (section == 0) return _loading ? WQML(@"INSPECT_LOADING", @"正在读取…") : _status;
    if (_table) {
        for (NSDictionary *entry in _file.tables) if ([entry[@"Name"] isEqual:_table]) return [NSString stringWithFormat:@"%@\n%@", entry[@"SQL"], WQML(@"INSPECT_EXPORT_NOTE", @"CSV 导出上限 10000 行／16 MB；每个值最多 4 KB，BLOB 仅导出大小。达到上限会停止并移除未完成文件。")];
    }
    return nil;
}
- (id)valueAt:(NSUInteger)index { return _keys ? _node[_keys[index]] : [_node isKindOfClass:NSArray.class] ? _node[index] : _node; }
- (NSString *)summary:(id)value
{
    if ([value isKindOfClass:NSDictionary.class]) return [NSString stringWithFormat:@"Dictionary · %lu", (unsigned long)[value count]];
    if ([value isKindOfClass:NSArray.class]) return [NSString stringWithFormat:@"Array · %lu", (unsigned long)[value count]];
    if ([value isKindOfClass:NSData.class]) return [NSString stringWithFormat:@"Data · %lu bytes", (unsigned long)[value length]];
    NSString *text = [value description] ?: @"";
    return text.length > 4096 ? [[text substringToIndex:4096] stringByAppendingString:@"…"] : text;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"inspect"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"inspect"];
    UIListContentConfiguration *content = cell.defaultContentConfiguration;
    BOOL scalar = _node && ![_node isKindOfClass:NSDictionary.class] && ![_node isKindOfClass:NSArray.class];
    content.textProperties.numberOfLines = 2; content.secondaryTextProperties.numberOfLines = scalar ? 0 : 4;
    cell.accessoryType = UITableViewCellAccessoryNone; cell.userInteractionEnabled = !_loading;
    if (indexPath.section == 0) {
        content.text = _table ? @[WQML(@"INSPECT_PREVIOUS", @"上一页"), WQML(@"INSPECT_NEXT", @"下一页"), WQML(@"INSPECT_EXPORT", @"导出此表 CSV")][indexPath.row] : _node ? @[WQML(@"INSPECT_PREVIOUS", @"上一页"), WQML(@"INSPECT_NEXT", @"下一页")][indexPath.row] : WQML(@"INSPECT_OPEN", @"制作只读工作副本");
        content.textProperties.color = WQMTheme.accentColor;
        if ((_table || _node) && indexPath.row == 0 && (_table ? !_offset : !_treeOffset)) cell.userInteractionEnabled = NO;
        if ((_table || _node) && indexPath.row == 1 && (_table ? _rows.count < 100 || _offset >= 10000000 : _treeOffset + 200 >= self.nodeCount)) cell.userInteractionEnabled = NO;
    } else if (_node) {
        NSUInteger index = _treeOffset + indexPath.row; id value = [self valueAt:index];
        content.text = _keys ? _keys[index] : [NSString stringWithFormat:@"%lu", (unsigned long)index];
        content.secondaryText = [self summary:value];
        cell.accessoryType = scalar ? UITableViewCellAccessoryNone : UITableViewCellAccessoryDisclosureIndicator;
        if (scalar) cell.userInteractionEnabled = NO;
    } else if (_table) {
        NSDictionary *row = _rows[indexPath.row];
        content.text = [NSString stringWithFormat:WQML(@"INSPECT_ROW", @"第 %lu 行"), (unsigned long)(_offset + indexPath.row + 1)];
        content.secondaryText = [row[@"Values"] componentsJoinedByString:@" · "];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        NSDictionary *entry = _file.tables[indexPath.row]; content.text = entry[@"Name"]; content.secondaryText = entry[@"SQL"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    cell.contentConfiguration = content; return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (_loading) return;
    if (_node && ![_node isKindOfClass:NSDictionary.class] && ![_node isKindOfClass:NSArray.class]) return;
    if (indexPath.section == 0) {
        if (_table) { if (indexPath.row == 2) [self exportTable]; else [self loadPage:indexPath.row ? _offset + 100 : _offset >= 100 ? _offset - 100 : 0]; }
        else if (_node) { _treeOffset = indexPath.row ? MIN(_treeOffset + 200, self.nodeCount) : _treeOffset >= 200 ? _treeOffset - 200 : 0; [self.tableView reloadData]; }
        else [self prepare];
        return;
    }
    id node = _node ? [self valueAt:_treeOffset + indexPath.row] : nil;
    if (_table) {
        NSDictionary *row = _rows[indexPath.row];
        NSMutableDictionary *fields = [NSMutableDictionary new];
        for (NSUInteger index = 0; index < [row[@"Columns"] count]; index++) fields[[NSString stringWithFormat:@"%lu · %@", (unsigned long)(index + 1), row[@"Columns"][index]]] = row[@"Values"][index];
        node = fields;
    }
    NSString *table = !_node && !_table ? _file.tables[indexPath.row][@"Name"] : nil;
    WQMStructuredViewController *child = [[WQMStructuredViewController alloc] initWithFile:_file node:node table:table worker:_worker];
    child.title = table ?: (_keys ? _keys[_treeOffset + indexPath.row] : self.title);
    [self.navigationController pushViewController:child animated:YES];
}
@end
