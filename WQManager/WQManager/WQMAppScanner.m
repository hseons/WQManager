#import "WQMAppScanner.h"
#import "WQMAppModel.h"
#import "WQMLanguageManager.h"
#import "WQAccess.h"
#import "WQLaunchServices.h"

#import <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

static NSString *const kWQMAppDataRoot = @"/private/var/mobile/Containers/Data/Application";

static NSString *WQMScanDiagPath(void)
{
    static NSString *path;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        path = [docs stringByAppendingPathComponent:@"scan-diag-latest.log"];
    });
    return path;
}

// Diagnostics use raw file descriptors and volatile scalars on purpose: if the
// scan thread or the main thread wedges, a plain GCD watchdog can end up
// blocked behind the same machinery. A dedicated thread writing with write(2)
// keeps reporting as long as the process is alive.
static int gScanDiagFD = -1;
static volatile BOOL gScanDiagRunning = NO;
static volatile int32_t gScanDiagStage = 0;
static volatile int64_t gScanDiagIndex = 0;
static volatile double gScanDiagStarted = 0;
static volatile double gScanDiagMainPing = 0;
static dispatch_source_t gScanDiagPing;

static NSString *WQMScanDiagStageName(int32_t stage)
{
    switch (stage) {
        case 1: return @"enumerate";
        case 2: return @"grant";
        case 3: return @"label";
        case 4: return @"measure";
        case 5: return @"drop";
        case 6: return @"sort";
        default: return @"idle";
    }
}

static void WQMScanDiagWrite(NSString *line)
{
    if (gScanDiagFD < 0 || !line.length) return;
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (!data.length) return;
    const char *bytes = data.bytes;
    size_t remaining = data.length;
    while (remaining > 0) {
        ssize_t written = write(gScanDiagFD, bytes, remaining);
        if (written <= 0) break;
        bytes += written;
        remaining -= (size_t)written;
    }
}

static void WQMScanDiagAppend(NSString *line)
{
    WQMScanDiagWrite(line);
}

static void WQMScanDiagSetStage(NSInteger index, NSString *stage)
{
    int32_t value = 0;
    if ([stage isEqualToString:@"enumerate"]) value = 1;
    else if ([stage isEqualToString:@"grant"]) value = 2;
    else if ([stage isEqualToString:@"label"]) value = 3;
    else if ([stage isEqualToString:@"measure"]) value = 4;
    else if ([stage isEqualToString:@"drop"]) value = 5;
    else if ([stage isEqualToString:@"sort"]) value = 6;
    gScanDiagIndex = index;
    gScanDiagStage = value;
}

static void WQMScanDiagStart(NSUInteger total)
{
    if (gScanDiagFD >= 0) close(gScanDiagFD);
    NSString *path = WQMScanDiagPath();
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    gScanDiagFD = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_APPEND, 0644);
    gScanDiagRunning = YES;
    gScanDiagStarted = CFAbsoluteTimeGetCurrent();
    gScanDiagMainPing = gScanDiagStarted;
    gScanDiagIndex = 0;
    gScanDiagStage = 1;
    WQMScanDiagWrite([NSString stringWithFormat:@"scan diag start %@ total=%lu pid=%d\n",
                      NSDate.date, (unsigned long)total, getpid()]);

    if (gScanDiagPing) dispatch_source_cancel(gScanDiagPing);
    gScanDiagPing = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(gScanDiagPing, dispatch_time(DISPATCH_TIME_NOW, 0),
                              1 * NSEC_PER_SEC, 200 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(gScanDiagPing, ^{
        gScanDiagMainPing = CFAbsoluteTimeGetCurrent();
    });
    dispatch_resume(gScanDiagPing);

    [NSThread detachNewThreadWithBlock:^{
        while (gScanDiagRunning) {
            [NSThread sleepForTimeInterval:2.0];
            if (!gScanDiagRunning) break;
            double elapsed = CFAbsoluteTimeGetCurrent() - gScanDiagStarted;
            double age = CFAbsoluteTimeGetCurrent() - gScanDiagMainPing;
            WQMScanDiagWrite([NSString stringWithFormat:
                @"watchdog idx=%lld stage=%@ elapsed=%.0fs main=%@\n",
                (long long)gScanDiagIndex, WQMScanDiagStageName(gScanDiagStage),
                elapsed, age > 3.0 ? @"blocked" : @"alive"]);
        }
    }];
}

static void WQMScanDiagStop(NSString *note)
{
    gScanDiagRunning = NO;
    if (gScanDiagPing) { dispatch_source_cancel(gScanDiagPing); gScanDiagPing = nil; }
    WQMScanDiagWrite([NSString stringWithFormat:@"scan diag stop %@ %@\n", note, NSDate.date]);
    if (gScanDiagFD >= 0) { close(gScanDiagFD); gScanDiagFD = -1; }
}

static BOOL WQMBundleIdentifierLooksValid(NSString *identifier)
{
    if (identifier.length < 3 || identifier.length > 255 ||
        [identifier containsString:@".."] ||
        [identifier hasPrefix:@"."] || [identifier hasSuffix:@"."]) {
        return NO;
    }
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
                               @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-"];
    return [identifier rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound;
}

@implementation WQMAppScanResult

- (instancetype)init
{
    self = [super init];
    if (self) {
        _apps = @[];
        _status = @"";
    }
    return self;
}

@end

@implementation WQMAppScanner

- (void)scanWithCancellation:(WQScanCancellation *)cancellation
                    progress:(void (^_Nullable)(NSString *status))progress
                  completion:(void (^)(WQMAppScanResult *result))completion
{
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        void (^report)(NSString *) = ^(NSString *status) {
            if (progress) dispatch_async(dispatch_get_main_queue(), ^{ progress(status); });
        };

        WQMAppScanResult *result = [WQMAppScanResult new];
        report(WQML(@"SCAN_FINDING_CONTAINERS", @"正在查找 App 容器…"));
        WQMScanDiagStart(0);

#if DEBUG
        if ([NSProcessInfo.processInfo.environment[@"WQM_UI_FIXTURES"] boolValue]) {
            NSArray<NSArray *> *fixtures = @[
                @[@"微信", @"com.tencent.xin", @(12884901888ULL)],
                @[@"照片", @"com.apple.mobileslideshow", @(8697308774ULL)],
                @[@"剪映", @"com.lemon.lv", @(4939212390ULL)],
                @[@"抖音", @"com.ss.iphone.ugc.Aweme", @(3758096384ULL)],
                @[@"文件", @"com.apple.DocumentsApp", @(2473901162ULL)],
            ];
            NSMutableArray<WQMAppModel *> *apps = [NSMutableArray new];
            BOOL limitedFixture =
                [NSProcessInfo.processInfo.environment[@"WQM_UI_FIXTURES_LIMITED"] boolValue];
            for (NSArray *fixture in fixtures) {
                WQMAppModel *app = [[WQMAppModel alloc]
                    initWithBundleIdentifier:fixture[1]
                                displayName:fixture[0]
                              containerPath:[@"/private/var/mobile/Containers/Data/Application/"
                                             stringByAppendingString:NSUUID.UUID.UUIDString]
                                   dataSize:[fixture[2] unsignedLongLongValue]];
                app.accessAvailable = YES;
                app.identityKnown = YES;
                app.containerDevice = 1;
                app.containerInode = 1;
                if (limitedFixture && apps.count == 1) {
                    app.accessAvailable = NO;
                    app.identityKnown = NO;
                    app.sizeKnown = NO;
                    app.dataSize = 0;
                }
                [apps addObject:app];
            }
            result.apps = apps;
            result.limitedCount = limitedFixture ? 1 : 0;
            result.status = limitedFixture
                ? [NSString stringWithFormat:
                   WQML(@"SCAN_LIMITED_STATUS",
                        @"%lu 个 App · %lu 个项目的访问、身份或大小受限"),
                   (unsigned long)apps.count, 1UL]
                : [NSString stringWithFormat:
                   WQML(@"SCAN_FIXTURE_STATUS", @"%lu 个 App · UI 测试数据"),
                   (unsigned long)apps.count];
            WQMScanDiagStop(@"fixtures");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ completion(result); });
            return;
        }
#endif

        NSArray<NSString *> *containers = wq_enumerate(kWQMAppDataRoot, 0, cancellation,
            ^(int64_t done, int64_t total, NSUInteger found) {
                NSString *status = total > 0
                    ? [NSString stringWithFormat:WQML(@"SCAN_FINDING_PROGRESS", @"正在查找 App… %lld%%"),
                       (long long)(done * 100 / total)]
                    : [NSString stringWithFormat:WQML(@"SCAN_FINDING_FOUND", @"正在查找 App… 已找到 %lu 个"),
                       (unsigned long)found];
                report(status);
            });

        if (cancellation.isCancelled) {
            result.cancelled = YES;
            result.status = WQML(@"SCAN_CANCELLED", @"扫描已取消");
            WQMScanDiagStop(@"cancelled after enumerate");
            dispatch_async(dispatch_get_main_queue(), ^{ completion(result); });
            return;
        }

        if (!containers) {
            result.fullScanDeclined = wq_full_scan_was_declined();
            result.status = result.fullScanDeclined
                ? WQML(@"SCAN_DATABASE_UNAVAILABLE",
                       @"未找到可用的 App 数据库；本阶段不启动耗时的全盘扫描。")
                : WQML(@"SCAN_ENUMERATION_FAILED", @"无法枚举 App 容器，请查看日志或稍后重试。");
            WQMScanDiagStop(@"no containers");
            dispatch_async(dispatch_get_main_queue(), ^{ completion(result); });
            return;
        }

        report(WQML(@"SCAN_READING_NAMES", @"正在读取 App 名称…"));
        if (!wq_display_names_loaded()) wq_load_display_names();

        NSString *home = [NSHomeDirectory() stringByResolvingSymlinksInPath];
        WQMScanDiagSetStage(0, @"loop");
        WQMScanDiagAppend([NSString stringWithFormat:@"enumerated=%lu\n",
                           (unsigned long)containers.count]);
        NSMutableArray<WQMAppModel *> *apps = [NSMutableArray arrayWithCapacity:containers.count];
        NSMutableArray<WQMAppModel *> *deferred = [NSMutableArray new];
        NSUInteger limited = 0;
        NSUInteger index = 0;

        for (NSString *container in containers) {
            if (cancellation.isCancelled) {
                result.cancelled = YES;
                break;
            }
            index++;
            if ([[container stringByResolvingSymlinksInPath] isEqualToString:home]) continue;

            report([NSString stringWithFormat:WQML(@"SCAN_READING_PROGRESS", @"正在读取 %lu/%lu…"),
                    (unsigned long)index, (unsigned long)containers.count]);

            CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
            WQMScanDiagAppend([NSString stringWithFormat:@"enter %lu/%lu %@\n",
                               (unsigned long)index, (unsigned long)containers.count,
                               container.lastPathComponent]);
            WQMScanDiagSetStage(index, @"grant");
            BOOL granted = wq_grant(container);
            CFAbsoluteTime t1 = CFAbsoluteTimeGetCurrent();
            WQMScanDiagSetStage(index, @"label");
            NSString *bundleID = wq_container_label(container);
            CFAbsoluteTime t2 = CFAbsoluteTimeGetCurrent();
            if (!WQMBundleIdentifierLooksValid(bundleID)) bundleID = nil;

            struct stat identity = {0};
            BOOL hasIdentity = granted && wq_stat(container, &identity) && S_ISDIR(identity.st_mode);
            NSString *name = bundleID.length
                ? (wq_display_name(bundleID) ?: bundleID)
                : WQML(@"UNKNOWN_CONTAINER", @"未知容器");

            WQMAppModel *app = [[WQMAppModel alloc] initWithBundleIdentifier:bundleID ?: @""
                                                                  displayName:name
                                                                containerPath:container
                                                                     dataSize:0];
            app.accessAvailable = granted;
            app.identityKnown = hasIdentity;
            app.containerDevice = hasIdentity ? identity.st_dev : 0;
            app.containerInode = hasIdentity ? identity.st_ino : 0;

            unsigned long long bytes = 0;
            WQMScanDiagSetStage(index, @"measure");
            if (granted && hasIdentity) {
                WQMeasureBudget budget = { .maxEntries = 12000, .maxSeconds = 0.25 };
                WQMeasureResult measured = wq_measure_tree_budgeted(container, cancellation, &bytes, budget);
                if (measured == WQMeasureResultCancelled) {
                    result.cancelled = YES;
                    break;
                }
                app.dataSize = bytes;
                app.sizeKnown = measured == WQMeasureResultKnown;
                if (measured == WQMeasureResultBudgetExceeded) {
                    // Huge or badly fragmented trees are measured after the quick
                    // pass so one container cannot stall the whole scan.
                    [deferred addObject:app];
                }
            } else {
                app.sizeKnown = NO;
            }
            // Holding one sandbox extension per app makes the kernel release
            // and re-query tokens once the LRU limit is reached, which stalls
            // large scans. The measurement is done, so give the token back.
            CFAbsoluteTime t3 = CFAbsoluteTimeGetCurrent();
            WQMScanDiagSetStage(index, @"drop");
            wq_drop_grant(container);
            WQMScanDiagAppend([NSString stringWithFormat:
                @"%lu/%lu grant=%.0fms label=%.0fms measure=%.0fms ok=%d %@\n",
                (unsigned long)index, (unsigned long)containers.count,
                (t1 - t0) * 1000.0, (t2 - t1) * 1000.0, (t3 - t2) * 1000.0,
                granted, container.lastPathComponent]);
            [apps addObject:app];
        }

        if (!result.cancelled && deferred.count > 0) {
            NSUInteger done = 0;
            for (WQMAppModel *app in deferred) {
                if (cancellation.isCancelled) {
                    result.cancelled = YES;
                    break;
                }
                done++;
                report([NSString stringWithFormat:
                        WQML(@"SCAN_DEFERRED_PROGRESS", @"正在统计大型 App %lu/%lu…"),
                        (unsigned long)done, (unsigned long)deferred.count]);
                @autoreleasepool {
                    NSString *path = app.containerPath;
                    if (path.length && wq_grant(path)) {
                        unsigned long long bytes = 0;
                        WQMeasureResult measured = wq_measure_tree(path, cancellation, &bytes);
                        if (measured == WQMeasureResultCancelled) {
                            wq_drop_grant(path);
                            result.cancelled = YES;
                            break;
                        }
                        app.dataSize = bytes;
                        app.sizeKnown = measured != WQMeasureResultLimited;
                    }
                    if (path.length) wq_drop_grant(path);
                }
            }
        }

        for (WQMAppModel *app in apps) {
            if (!app.accessAvailable || !app.bundleIdentifier.length ||
                !app.identityKnown || !app.sizeKnown) limited++;
        }

        if (result.cancelled) {
            result.status = WQML(@"SCAN_CANCELLED", @"扫描已取消");
        } else {
            [apps sortUsingComparator:^NSComparisonResult(WQMAppModel *a, WQMAppModel *b) {
                if (!a.sizeKnown && b.sizeKnown) return NSOrderedDescending;
                if (a.sizeKnown && !b.sizeKnown) return NSOrderedAscending;
                if (a.dataSize == b.dataSize) {
                    return [a.displayName localizedStandardCompare:b.displayName];
                }
                return a.dataSize > b.dataSize ? NSOrderedAscending : NSOrderedDescending;
            }];
            result.apps = [apps copy];
            result.limitedCount = limited;
            if (limited > 0) {
                result.status = [NSString stringWithFormat:
                                 WQML(@"SCAN_LIMITED_STATUS",
                                      @"%lu 个 App · %lu 个项目的访问、身份或大小受限"),
                                 (unsigned long)apps.count, (unsigned long)limited];
            } else {
                result.status = [NSString stringWithFormat:WQML(@"APP_COUNT", @"%lu 个 App"),
                                 (unsigned long)apps.count];
            }
        }

        WQMScanDiagStop(result.cancelled ? @"cancelled" : @"done");
        dispatch_async(dispatch_get_main_queue(), ^{ completion(result); });
    });
}

@end

