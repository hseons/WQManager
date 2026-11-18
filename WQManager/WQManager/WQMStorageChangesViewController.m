#import "WQMStorageChangesViewController.h"
#import "WQMScanHistory.h"
#import "WQMAppModel.h"
#import "WQMSpaceLensViewController.h"
#import "WQMLanguageManager.h"
#import "WQMTheme.h"

typedef NS_ENUM(NSInteger, WQMStorageWindow) {
    WQMStorageWindowPrevious = 0,
    WQMStorageWindowSevenDays,
    WQMStorageWindowThirtyDays,
};

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
@property (nonatomic, copy) NSDictionary<NSString *, NSNumber *> *deltas;
@property (nonatomic) WQMStorageWindow window;
@property (nonatomic) unsigned long long knownBytes;
@property (nonatomic) long long totalDelta;
@property (nonatomic) BOOL hasTotalDelta;
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
    self.tableView.estimatedRowHeight = 68;
    self.tableView.contentInset = UIEdgeInsetsMake(4, 0, 82, 0);
    self.tableView.scrollIndicatorInsets = UIEdgeInsetsMake(0, 0, 82, 0);
    if (self.selectedApp) {
        self.samples = [[[WQMScanHistory samplesForApp:self.selectedApp] reverseObjectEnumerator] allObjects];
        [self configureDetailHeader];
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:WQML(@"LENS_TITLE", @"空间透镜") style:UIBarButtonItemStylePlain target:self action:@selector(openLens)];
    } else {
        [self configureWindowHeader];
        [self reloadRanking];
    }
}

- (void)configureWindowHeader
{
    UISegmentedControl *control = [[UISegmentedControl alloc] initWithItems:@[
        WQML(@"SPACE_WINDOW_PREVIOUS", @"较上次"),
        WQML(@"SPACE_WINDOW_7D", @"近 7 天"),
        WQML(@"SPACE_WINDOW_30D", @"近 30 天"),
    ]];
    control.selectedSegmentIndex = WQMStorageWindowPrevious;
    control.accessibilityIdentifier = @"storage.window";
    [control addTarget:self action:@selector(windowChanged:) forControlEvents:UIControlEventValueChanged];

    NSMutableArray<UIView *> *views = [NSMutableArray new];
    NSArray<NSDictionary *> *totals = [WQMScanHistory totalSamples];
    if (totals.count >= 2) {
        UILabel *caption = [UILabel new];
        caption.text = WQML(@"SPACE_TOTAL_TREND", @"全部 App 合计占用趋势");
        caption.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
        caption.textColor = WQMTheme.textSecondaryColor;
        [views addObject:caption];
        WQMStorageTrendView *chart = [[WQMStorageTrendView alloc] init];
        chart.samples = totals;
        chart.backgroundColor = UIColor.clearColor;
        chart.isAccessibilityElement = YES;
        chart.accessibilityLabel = WQML(@"SPACE_TOTAL_TREND_ACCESSIBILITY", @"合计占用趋势图。");
        [chart.heightAnchor constraintEqualToConstant:120].active = YES;
        [views addObject:chart];
    }
    [views addObject:control];
    [control.heightAnchor constraintEqualToConstant:32].active = YES;

    UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:views];
    header.axis = UILayoutConstraintAxisVertical;
    header.spacing = 8;
    header.layoutMarginsRelativeArrangement = YES;
    header.layoutMargins = UIEdgeInsetsMake(12, 16, 12, 16);
    header.frame = CGRectMake(0, 0, self.tableView.bounds.size.width, totals.count >= 2 ? 211 : 56);
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.tableView.tableHeaderView = header;
}

- (void)configureDetailHeader
{
    UILabel *summary = [UILabel new];
    summary.numberOfLines = 0;
    summary.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    summary.textColor = WQMTheme.textSecondaryColor;
    summary.accessibilityIdentifier = @"storage.detail.summary";

    NSString *current = self.samples.count
        ? WQMFormatBytes([self.samples.lastObject[@"Bytes"] unsignedLongLongValue])
        : WQML(@"SPACE_NEEDS_SAMPLES", @"等待两次可比较的扫描");
    summary.text = [NSString stringWithFormat:WQML(@"SPACE_DETAIL_SUMMARY", @"当前 %@ · 较上次 %@ · 近 7 天 %@"),
                    current, [self changeTextForDays:0], [self changeTextForDays:7]];

    NSMutableArray<UIView *> *views = [NSMutableArray arrayWithObject:summary];
    if (self.samples.count >= 2) {
        WQMStorageTrendView *chart = [[WQMStorageTrendView alloc] init];
        chart.samples = [[self.samples reverseObjectEnumerator] allObjects];
        chart.backgroundColor = UIColor.clearColor;
        chart.isAccessibilityElement = YES;
        chart.accessibilityLabel = WQML(@"SPACE_TREND_ACCESSIBILITY", @"占用趋势图，具体时间和大小见下方记录。");
        [chart.heightAnchor constraintEqualToConstant:140].active = YES;
        [views addObject:chart];
    }

    UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:views];
    header.axis = UILayoutConstraintAxisVertical;
    header.spacing = 8;
    header.layoutMarginsRelativeArrangement = YES;
    header.layoutMargins = UIEdgeInsetsMake(12, 16, 12, 16);
    header.frame = CGRectMake(0, 0, self.tableView.bounds.size.width, self.samples.count >= 2 ? 214 : 66);
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.tableView.tableHeaderView = header;
}

- (void)windowChanged:(UISegmentedControl *)control
{
    self.window = (WQMStorageWindow)control.selectedSegmentIndex;
    [self reloadRanking];
}

- (NSInteger)windowDays
{
    if (self.window == WQMStorageWindowSevenDays) return 7;
    if (self.window == WQMStorageWindowThirtyDays) return 30;
    return 0;
}

- (void)reloadRanking
{
    NSInteger days = [self windowDays];
    NSMutableDictionary<NSString *, NSNumber *> *deltas = [NSMutableDictionary new];
    unsigned long long knownBytes = 0;
    long long totalDelta = 0;
    for (WQMAppModel *app in self.apps) {
        if (app.sizeKnown) knownBytes += app.dataSize;
        NSNumber *delta = days > 0 ? [WQMScanHistory changeForApp:app overDays:days] : [WQMScanHistory changeForApp:app];
        if (delta != nil) {
            deltas[app.bundleIdentifier] = delta;
            totalDelta += delta.longLongValue;
        }
    }
    self.deltas = deltas;
    self.knownBytes = knownBytes;
    self.totalDelta = totalDelta;
    self.hasTotalDelta = deltas.count > 0;
    self.apps = [self.apps sortedArrayUsingComparator:^NSComparisonResult(WQMAppModel *a, WQMAppModel *b) {
        NSNumber *x = deltas[a.bundleIdentifier], *y = deltas[b.bundleIdentifier];
        if (x == nil || y == nil) {
            if (x != nil) return NSOrderedAscending;
            if (y != nil) return NSOrderedDescending;
        } else {
            NSComparisonResult order = [y compare:x];
            if (order != NSOrderedSame) return order;
        }
        NSComparisonResult name = [a.displayName localizedStandardCompare:b.displayName];
        return name != NSOrderedSame ? name : [a.bundleIdentifier compare:b.bundleIdentifier];
    }];
    [self.tableView reloadData];
}

- (void)openLens { [self.navigationController pushViewController:[[WQMSpaceLensViewController alloc] initWithApp:self.selectedApp] animated:YES]; }

- (NSString *)signedBytes:(long long)bytes
{
    if (!bytes) return @"0 B";
    return [NSString stringWithFormat:@"%@%@", bytes < 0 ? @"−" : @"+", WQMFormatBytes((unsigned long long)llabs(bytes))];
}

- (NSString *)changeTextForDays:(NSInteger)days
{
    NSNumber *change = days > 0 ? [WQMScanHistory changeForApp:self.selectedApp overDays:days] : [WQMScanHistory changeForApp:self.selectedApp];
    return change != nil ? [self signedBytes:change.longLongValue] : @"—";
}

- (NSString *)rankingTitle
{
    if (self.window == WQMStorageWindowSevenDays) return WQML(@"SPACE_RANKING_7D", @"近 7 天 · 按增长排序");
    if (self.window == WQMStorageWindowThirtyDays) return WQML(@"SPACE_RANKING_30D", @"近 30 天 · 按增长排序");
    return WQML(@"SPACE_GROWTH_RANKING", @"较上次扫描 · 按增长排序");
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return MAX(1, self.selectedApp ? self.samples.count : self.apps.count); }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return self.selectedApp ? WQML(@"SPACE_SAMPLES", @"扫描记录") : [self rankingTitle]; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (self.selectedApp) return WQML(@"SPACE_HISTORY_FOOTER", @"仅记录扫描时测得的大小，保留最近 60 次扫描。首次记录、缺失测量或容器更换后重新累计；变化不等同于可清理空间。");
    NSString *change = self.hasTotalDelta ? [self signedBytes:self.totalDelta] : @"—";
    NSString *summary = [NSString stringWithFormat:WQML(@"SPACE_TOTAL_SUMMARY", @"已知占用 %@ · 合计变化 %@"),
                         WQMFormatBytes(self.knownBytes), change];
    return [summary stringByAppendingFormat:@"\n%@",
            WQML(@"SPACE_HISTORY_FOOTER", @"仅记录扫描时测得的大小，保留最近 60 次扫描。首次记录、缺失测量或容器更换后重新累计；变化不等同于可清理空间。")];
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
        NSNumber *delta = self.deltas[app.bundleIdentifier];
        NSString *change = delta != nil ? [self signedBytes:delta.longLongValue] : WQML(@"SPACE_NEEDS_SAMPLES", @"等待两次可比较的扫描");
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
    WQMStorageChangesViewController *detail = [[WQMStorageChangesViewController alloc] initWithApp:self.apps[indexPath.row]];
    [self.navigationController pushViewController:detail animated:YES];
}
@end
