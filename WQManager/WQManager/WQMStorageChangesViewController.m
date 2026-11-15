#import "WQMStorageChangesViewController.h"
#import "WQMScanHistory.h"
#import "WQMAppModel.h"
#import "WQMSpaceLensViewController.h"
#import "WQMLanguageManager.h"
#import "WQMTheme.h"

@interface WQMStorageTrendView : UIView
@property (nonatomic, copy) NSArray<NSDictionary *> *samples;
@end
@implementation WQMStorageTrendView
- (void)drawRect:(CGRect)rect
{
    if (self.samples.count < 2) return;
    double minimum = DBL_MAX, maximum = 0;
    for (NSDictionary *sample in self.samples) { double value = [sample[@"Bytes"] doubleValue]; minimum = MIN(minimum, value); maximum = MAX(maximum, value); }
    UIBezierPath *line = [UIBezierPath bezierPath];
    NSTimeInterval start = [self.samples.firstObject[@"Date"] timeIntervalSince1970];
    NSTimeInterval duration = [self.samples.lastObject[@"Date"] timeIntervalSince1970] - start;
    for (NSUInteger i = 0; i < self.samples.count; i++) {
        double fraction = duration > 0 ? ([self.samples[i][@"Date"] timeIntervalSince1970] - start) / duration : (double)i / (self.samples.count - 1);
        double y = maximum > minimum ? ([self.samples[i][@"Bytes"] doubleValue] - minimum) / (maximum - minimum) : 0.5;
        CGPoint point = CGPointMake(20 + fraction * (rect.size.width - 40), rect.size.height - 24 - y * (rect.size.height - 48));
        if (!i) [line moveToPoint:point]; else [line addLineToPoint:point];
    }
    [WQMTheme.textPrimaryColor setStroke]; line.lineWidth = 2; line.lineJoinStyle = kCGLineJoinRound; [line stroke];
}
@end

@interface WQMStorageChangesViewController ()
@property (nonatomic, copy) NSArray<WQMAppModel *> *apps;
@property (nonatomic, strong) WQMAppModel *selectedApp;
@property (nonatomic, copy) NSArray<NSDictionary *> *samples;
@property (nonatomic, copy) NSDictionary<NSString *, NSNumber *> *changes;
@end
@implementation WQMStorageChangesViewController
- (instancetype)initWithApps:(NSArray<WQMAppModel *> *)apps
{
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) self.apps = apps;
    return self;
}
- (instancetype)initWithApp:(WQMAppModel *)app
{
    self = [self initWithApps:@[]];
    if (self) self.selectedApp = app;
    return self;
}
- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = self.selectedApp ? self.selectedApp.displayName : WQML(@"SPACE_CHANGES", @"空间变化");
    self.tableView.backgroundColor = WQMTheme.canvasColor;
    self.view.tintColor = WQMTheme.accentColor;
    self.tableView.accessibilityIdentifier = @"storage.changes.table";
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    if (self.selectedApp) {
        self.samples = [[[WQMScanHistory samplesForApp:self.selectedApp] reverseObjectEnumerator] allObjects];
        if (self.samples.count >= 2) {
            WQMStorageTrendView *chart = [[WQMStorageTrendView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 140)];
            chart.samples = [[self.samples reverseObjectEnumerator] allObjects];
            chart.backgroundColor = UIColor.clearColor;
            chart.isAccessibilityElement = YES;
            chart.accessibilityLabel = WQML(@"SPACE_TREND_ACCESSIBILITY", @"占用趋势图，具体时间和大小见下方记录。");
            self.tableView.tableHeaderView = chart;
        }
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:WQML(@"LENS_TITLE", @"空间透镜") style:UIBarButtonItemStylePlain target:self action:@selector(openLens)];
    } else {
        NSMutableDictionary *changes = [NSMutableDictionary new];
        for (WQMAppModel *app in self.apps) { NSNumber *change = [WQMScanHistory changeForApp:app]; if (change != nil) changes[app.bundleIdentifier] = change; }
        self.changes = changes;
        self.apps = [self.apps sortedArrayUsingComparator:^NSComparisonResult(WQMAppModel *a, WQMAppModel *b) {
            NSNumber *x = changes[a.bundleIdentifier], *y = changes[b.bundleIdentifier];
            if (x == nil || y == nil) return x != nil ? NSOrderedAscending : y != nil ? NSOrderedDescending : [a.displayName compare:b.displayName];
            NSComparisonResult order = [y compare:x];
            return order == NSOrderedSame ? [a.displayName compare:b.displayName] : order;
        }];
    }
}
- (void)openLens { [self.navigationController pushViewController:[[WQMSpaceLensViewController alloc] initWithApp:self.selectedApp] animated:YES]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return MAX(1, self.selectedApp ? self.samples.count : self.apps.count); }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return self.selectedApp ? WQML(@"SPACE_SAMPLES", @"扫描记录") : WQML(@"SPACE_GROWTH_RANKING", @"较上次扫描 · 按增长排序"); }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    return WQML(@"SPACE_HISTORY_FOOTER", @"仅记录扫描时测得的大小，保留最近 60 次扫描。首次记录、缺失测量或容器更换后重新累计；变化不等同于可清理空间。");
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    UIListContentConfiguration *content = [cell defaultContentConfiguration];
    if (self.selectedApp && self.samples.count) {
        NSDictionary *sample = self.samples[indexPath.row];
        content.text = [NSDateFormatter localizedStringFromDate:sample[@"Date"] dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterShortStyle];
        content.secondaryText = WQMFormatBytes([sample[@"Bytes"] unsignedLongLongValue]);
    } else if (!self.selectedApp && self.apps.count) {
        WQMAppModel *app = self.apps[indexPath.row];
        NSNumber *delta = self.changes[app.bundleIdentifier];
        long long bytes = delta.longLongValue;
        NSString *change = delta != nil ? [NSString stringWithFormat:@"%@%@", bytes < 0 ? @"−" : @"+", WQMFormatBytes(llabs(bytes))] : WQML(@"SPACE_NEEDS_SAMPLES", @"等待两次可比较的扫描");
        content.text = app.displayName;
        content.secondaryText = [NSString stringWithFormat:@"%@ · %@", app.formattedSize, change];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else { content.text = WQML(@"SPACE_HISTORY_EMPTY", @"还没有扫描记录"); }
    content.textProperties.color = WQMTheme.textPrimaryColor;
    content.secondaryTextProperties.color = WQMTheme.textSecondaryColor;
    cell.contentConfiguration = content;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.selectedApp || !self.apps.count) return;
    WQMStorageChangesViewController *detail = [[WQMStorageChangesViewController alloc] initWithApps:@[]];
    detail.selectedApp = self.apps[indexPath.row];
    [self.navigationController pushViewController:detail animated:YES];
}
@end
