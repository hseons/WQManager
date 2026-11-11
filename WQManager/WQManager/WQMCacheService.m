#import "WQMCacheService.h"
#import "WQMAppCache.h"
#import "WQMAppModel.h"
#import "WQMLanguageManager.h"
#import "WQMOperationStore.h"
#import "WQMSafetyPolicy.h"
#import "WQAccess.h"
#import "WQAppsSupport.h"
#import "WQCacheSafety.h"

#import <errno.h>
#import <sys/stat.h>

@implementation WQMCleanTarget
@end

@implementation WQMCleanItem

- (unsigned long long)bytes
{
    unsigned long long total = 0;
    for (WQMCleanTarget *target in self.targets) total += target.bytes;
    return total;
}

- (unsigned long long)selectedBytes
{
    unsigned long long total = 0;
    for (WQMCleanTarget *target in self.targets) {
        if (target.selected) total += target.bytes;
    }
    return total;
}

- (BOOL)selected
{
    for (WQMCleanTarget *target in self.targets) {
        if (target.selected) return YES;
    }
    return NO;
}

- (void)setSelected:(BOOL)selected
{
    for (WQMCleanTarget *target in self.targets) target.selected = selected;
}

@end

static WQMCleanTarget *WQMScanTarget(NSString *container, NSString *relative,
                                     WQScanCancellation *cancellation,
                                     BOOL *limited)
{
    WQMCleanTarget *target = [WQMCleanTarget new];
    target.path = [container stringByAppendingPathComponent:relative];
    target.relativePath = relative;
    target.bytesKnown = NO;
    target.selected = YES;

    NSString *reason = nil;
    if (![WQMSafetyPolicy isAllowedCleanupPath:target.path
                            inAppDataContainer:container
                                         reason:&reason] ||
        !WQCacheSafetyTargetMatchesContainer(target.path, container, relative)) {
        target.limited = YES;
        *limited = YES;
        return target;
    }

    struct stat st = {0};
    if (lstat(target.path.fileSystemRepresentation, &st) != 0) {
        if (errno == ENOENT) {
            target.bytesKnown = YES;
            return target;
        }
        *limited = YES;
        return target;
    }
    target.existed = YES;
    target.identityKnown = YES;
    target.device = st.st_dev;
    target.inode = st.st_ino;
    target.mode = st.st_mode & S_IFMT;
    if (!S_ISDIR(st.st_mode)) {
        *limited = YES;
        target.limited = YES;
        return target;
    }

    unsigned long long measuredBytes = 0;
    WQMeasureResult result = wq_measure_tree(target.path, cancellation, &measuredBytes);
    target.bytes = measuredBytes;
    if (result == WQMeasureResultKnown) {
        target.bytesKnown = YES;
    } else if (result == WQMeasureResultLimited) {
        target.limited = YES;
        *limited = YES;
    }
    return target;
}

static BOOL WQMValidateCleanItem(WQMCleanItem *item, NSString **reason)
{
    struct stat container = {0};
    if (!wq_stat(item.containerPath, &container) || !S_ISDIR(container.st_mode) ||
        container.st_dev != item.containerDevice || container.st_ino != item.containerInode) {
        if (reason) *reason = WQML(@"CLEAN_ERROR_CONTAINER_CHANGED", @"App 容器在扫描后发生变化");
        return NO;
    }
    NSString *label = wq_container_label(item.containerPath);
    if (![label isEqualToString:item.bundleIdentifier]) {
        if (reason) *reason = WQML(@"CLEAN_ERROR_CONTAINER_ID_MISMATCH", @"App 容器标识不再匹配");
        return NO;
    }
    for (WQMCleanTarget *target in item.targets) {
        if (!target.selected) continue;
        if (![WQMSafetyPolicy isAllowedCleanupPath:target.path
                                inAppDataContainer:item.containerPath
                                             reason:reason] ||
            !WQCacheSafetyTargetMatchesContainer(target.path, item.containerPath, target.relativePath)) {
            return NO;
        }
        struct stat current = {0};
        int result = lstat(target.path.fileSystemRepresentation, &current);
        if (target.existed) {
            if (result != 0 || !S_ISDIR(current.st_mode) ||
                current.st_dev != target.device || current.st_ino != target.inode ||
                (current.st_mode & S_IFMT) != target.mode) {
                if (reason) *reason = [NSString stringWithFormat:
                                       WQML(@"CLEAN_ERROR_TARGET_CHANGED", @"%@ 在扫描后发生变化"),
                                       target.relativePath];
                return NO;
            }
        } else if (result == 0) {
            if (reason) *reason = [NSString stringWithFormat:
                                   WQML(@"CLEAN_ERROR_TARGET_APPEARED", @"%@ 在扫描后出现"),
                                   target.relativePath];
            return NO;
        } else if (errno != ENOENT) {
            if (reason) *reason = [NSString stringWithFormat:
                                   WQML(@"CLEAN_ERROR_TARGET_CHECK", @"无法检查 %@"),
                                   target.relativePath];
            return NO;
        }
    }
    return YES;
}

@implementation WQMCacheService

- (void)scanWithCancellation:(WQScanCancellation *)cancellation
                    progress:(void (^_Nullable)(NSString *status))progress
                  completion:(void (^)(NSArray<WQMCleanItem *> *items, NSString *status))completion
{
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        void (^report)(NSString *) = ^(NSString *status) {
            if (progress) dispatch_async(dispatch_get_main_queue(), ^{ progress(status); });
        };
#if DEBUG
        if ([NSProcessInfo.processInfo.environment[@"WQM_UI_FIXTURES"] boolValue]) {
            NSArray<NSArray *> *fixtures = @[
                @[@"微信", @"com.tencent.xin", @(1845493760ULL)],
                @[@"照片", @"com.apple.mobileslideshow", @(838860800ULL)],
                @[@"剪映", @"com.lemon.lv", @(367001600ULL)],
                @[@"抖音", @"com.ss.iphone.ugc.Aweme", @(125829120ULL)],
                @[@"文件", @"com.apple.DocumentsApp", @(31457280ULL)],
            ];
            NSMutableArray<WQMCleanItem *> *items = [NSMutableArray new];
            for (NSArray *fixture in fixtures) {
                WQMCleanTarget *target = [WQMCleanTarget new];
                target.relativePath = @"Library/Caches";
                target.bytesKnown = YES;
                target.selected = YES;
                unsigned long long total = [fixture[2] unsignedLongLongValue];
                BOOL split = [fixture[1] isEqualToString:@"com.tencent.xin"];
                target.bytes = split ? total * 4 / 5 : total;
                WQMCleanItem *item = [WQMCleanItem new];
                item.name = fixture[0];
                item.bundleIdentifier = fixture[1];
                item.targets = @[target];
                if (split) {
                    WQMCleanTarget *tmp = [WQMCleanTarget new];
                    tmp.relativePath = @"tmp";
                    tmp.bytesKnown = YES;
                    tmp.selected = YES;
                    tmp.bytes = total - target.bytes;
                    item.targets = @[target, tmp];
                }
                item.eligible = YES;
                item.selected = YES;
                [items addObject:item];
            }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                completion(items, [NSString stringWithFormat:
                                   WQML(@"SCAN_FIXTURE_STATUS", @"%lu 个 App · UI 测试数据"),
                                   (unsigned long)items.count]);
            });
            return;
        }
#endif
        WQMAppCacheSnapshot *snapshot = [WQMAppCache load];
        if (!snapshot.apps.count) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(@[], WQML(@"CLEAN_NEEDS_APP_SCAN", @"请先到“应用”页面完成一次 App 扫描"));
            });
            return;
        }

        NSMutableArray<WQMCleanItem *> *items = [NSMutableArray new];
        NSUInteger index = 0;
        BOOL anyLimited = NO;
        for (WQMAppModel *app in snapshot.apps) {
            if (cancellation.isCancelled) break;
            index++;
            report([NSString stringWithFormat:WQML(@"CLEAN_SCANNING_PROGRESS", @"正在扫描缓存 %lu/%lu…"),
                    (unsigned long)index, (unsigned long)snapshot.apps.count]);

            BOOL limited = NO;
            if (!app.accessAvailable || !app.identityKnown) continue;
            if (!wq_grant(app.containerPath)) continue;
            if (![wq_container_label(app.containerPath) isEqualToString:app.bundleIdentifier]) continue;

            WQMCleanTarget *cache = WQMScanTarget(app.containerPath, @"Library/Caches", cancellation, &limited);
            WQMCleanTarget *temp = WQMScanTarget(app.containerPath, @"tmp", cancellation, &limited);
            if (cancellation.isCancelled) break;
            if (cache.bytes + temp.bytes == 0 && !limited) continue;

            struct stat container = {0};
            if (!wq_stat(app.containerPath, &container) || !S_ISDIR(container.st_mode)) continue;
            WQMCleanItem *item = [WQMCleanItem new];
            item.name = app.displayName;
            item.bundleIdentifier = app.bundleIdentifier;
            item.containerPath = app.containerPath;
            item.containerDevice = container.st_dev;
            item.containerInode = container.st_ino;
            item.targets = @[cache, temp];
            item.eligible = !limited;
            item.selected = item.eligible;
            if (limited) {
                item.limitedReason = WQML(@"CLEAN_LIMITED_REASON", @"访问、路径或缓存大小不完整");
                anyLimited = YES;
            }
            [items addObject:item];
        }

        [items sortUsingComparator:^NSComparisonResult(WQMCleanItem *a, WQMCleanItem *b) {
            return a.bytes > b.bytes ? NSOrderedAscending : (a.bytes < b.bytes ? NSOrderedDescending : NSOrderedSame);
        }];
        NSString *status = cancellation.isCancelled ? WQML(@"SCAN_CANCELLED", @"扫描已取消")
            : [NSString stringWithFormat:WQML(@"CLEAN_SCAN_RESULT", @"%lu 个 App 有可清理内容%@"),
               (unsigned long)items.count,
               anyLimited ? WQML(@"CLEAN_PARTIALLY_LIMITED", @" · 部分项目受限") : @""];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(items, status); });
    });
}

- (void)cleanItems:(NSArray<WQMCleanItem *> *)items
        cancellation:(WQScanCancellation *)cancellation
            progress:(void (^_Nullable)(NSString *status))progress
          completion:(void (^)(unsigned long long freed,
                               NSUInteger cleanedCount,
                               NSUInteger failedCount,
                               BOOL cancelled))completion
{
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        unsigned long long freed = 0;
        NSUInteger cleaned = 0, failed = 0;
        BOOL cancelled = NO;
        for (NSUInteger i = 0; i < items.count; i++) {
            if (cancellation.isCancelled) { cancelled = YES; break; }
            WQMCleanItem *item = items[i];
            if (progress) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    progress([NSString stringWithFormat:WQML(@"CLEAN_PROGRESS", @"正在清理 %lu/%lu：%@"),
                              (unsigned long)(i + 1), (unsigned long)items.count, item.name]);
                });
            }
            WQMOperationRecord *operation = [WQMOperationStore beginOperation:WQMOperationKindCleanCache
                                                                      appName:item.name
                                                             bundleIdentifier:item.bundleIdentifier];
            NSMutableArray<NSString *> *scopeParts = [NSMutableArray new];
            for (WQMCleanTarget *target in item.targets) {
                if (target.selected) [scopeParts addObject:target.relativePath];
            }
            operation.scope = [scopeParts componentsJoinedByString:@"、"];
            [WQMOperationStore updateRecord:operation];
            NSString *reason = nil;
            BOOL ok = WQMValidateCleanItem(item, &reason);
            if (!ok) {
                failed++;
                operation.status = WQMOperationStatusFailure;
                operation.errorMessage = reason ?: WQML(@"CLEAN_SAFETY_CHECK_FAILED", @"安全检查失败");
                operation.finishedAt = NSDate.date;
                [WQMOperationStore updateRecord:operation];
                continue;
            }
            unsigned long long itemFreed = 0;
            BOOL allTargets = YES;
            for (WQMCleanTarget *target in item.targets) {
                if (!target.selected) continue;
                if (cancellation.isCancelled) { cancelled = YES; break; }
                if (!wq_purge_contents_cancellable(target.path, &itemFreed, cancellation)) {
                    allTargets = NO;
                    if (cancellation.isCancelled) cancelled = YES;
                }
            }
            freed += itemFreed;
            operation.bytes = itemFreed;
            operation.status = cancelled ? WQMOperationStatusCancelled
                : (allTargets ? WQMOperationStatusSuccess : WQMOperationStatusFailure);
            operation.message = allTargets
                ? WQML(@"CLEAN_SUCCESS_MESSAGE", @"缓存已清理")
                : WQML(@"CLEAN_PARTIAL_MESSAGE", @"部分缓存未能删除");
            operation.errorMessage = allTargets
                ? @""
                : (reason ?: WQML(@"CLEAN_DELETE_FAILED", @"目录内容删除失败"));
            operation.finishedAt = NSDate.date;
            [WQMOperationStore updateRecord:operation];
            if (allTargets) cleaned++; else failed++;
            if (cancelled) break;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(freed, cleaned, failed, cancelled);
        });
    });
}

@end

