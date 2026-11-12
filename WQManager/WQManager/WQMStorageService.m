#import "WQMStorageService.h"
#import "WQMBackupStore.h"
#import "WQAppsSupport.h"

static NSString *gWQMStorageBackupRoot;
static NSString *gWQMStorageTemporaryRoot;

BOOL WQMStorageReasonIsSafetyBackup(NSString *reason)
{
    return [reason isEqualToString:@"恢复前自动安全备份"] ||
           [reason isEqualToString:@"Automatic safety backup before restore"];
}

@implementation WQMStorageBreakdown
@end

@implementation WQMStorageService

+ (void)setRootsForTesting:(NSString *)backupRoot temporaryRoot:(NSString *)temporaryRoot
{
    gWQMStorageBackupRoot = [backupRoot copy];
    gWQMStorageTemporaryRoot = [temporaryRoot copy];
}

+ (NSString *)backupRoot
{
    return gWQMStorageBackupRoot.length ? gWQMStorageBackupRoot : WQMBackupStore.backupRoot;
}

+ (NSString *)temporaryRoot
{
    return gWQMStorageTemporaryRoot.length ? gWQMStorageTemporaryRoot : NSTemporaryDirectory();
}

+ (NSString *)cacheRoot
{
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory,
                                                                     NSUserDomainMask, YES);
    return paths.firstObject;
}

+ (BOOL)isTemporaryDirectoryName:(NSString *)name
{
    return [name hasPrefix:@"WQMImport-"] || [name hasPrefix:@"WQMExport-"];
}

+ (WQMStorageBreakdown *)breakdown
{
    WQMStorageBreakdown *breakdown = [WQMStorageBreakdown new];
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *root = [self backupRoot];

    NSArray<NSString *> *bundleNames = [fm contentsOfDirectoryAtPath:root error:nil] ?: @[];
    for (NSString *bundleName in bundleNames) {
        if ([bundleName hasPrefix:@"."]) continue;
        NSString *bundlePath = [root stringByAppendingPathComponent:bundleName];
        BOOL isDirectory = NO;
        if (![fm fileExistsAtPath:bundlePath isDirectory:&isDirectory] || !isDirectory) continue;

        NSArray<NSString *> *children = [fm contentsOfDirectoryAtPath:bundlePath error:nil] ?: @[];
        for (NSString *child in children) {
            NSString *path = [bundlePath stringByAppendingPathComponent:child];
            unsigned long long bytes = WQMAppsSupportTreeSize(path);
            if ([child hasPrefix:@"."]) {
                breakdown.incompleteBytes += bytes;
                breakdown.incompleteCount += 1;
                continue;
            }
            WQMBackupRecord *record = [WQMBackupRecord recordAtPath:path error:nil];
            if (!record) {
                breakdown.invalidBytes += bytes;
                breakdown.invalidCount += 1;
                continue;
            }
            breakdown.backupBytes += bytes;
            breakdown.backupCount += 1;
            if (WQMStorageReasonIsSafetyBackup(record.reason)) {
                breakdown.safetyBytes += bytes;
                breakdown.safetyCount += 1;
            }
        }
    }

    NSString *temporaryRoot = [self temporaryRoot];
    NSArray<NSString *> *temporaryNames = [fm contentsOfDirectoryAtPath:temporaryRoot error:nil] ?: @[];
    for (NSString *name in temporaryNames) {
        if (![self isTemporaryDirectoryName:name]) continue;
        NSString *path = [temporaryRoot stringByAppendingPathComponent:name];
        breakdown.temporaryBytes += WQMAppsSupportTreeSize(path);
        breakdown.temporaryCount += 1;
    }

    NSString *cacheRoot = [self cacheRoot];
    if (cacheRoot.length) breakdown.cacheBytes = WQMAppsSupportTreeSize(cacheRoot);
    return breakdown;
}

+ (BOOL)cleanupWithOptions:(WQMStorageCleanupOptions)options
                   excluding:(NSSet<NSString *> *)protectedPaths
                  freedBytes:(unsigned long long *)freedBytes
                       error:(NSError **)error
{
    (void)error;
    NSFileManager *fm = NSFileManager.defaultManager;
    NSMutableSet<NSString *> *protected = [NSMutableSet set];
    for (NSString *path in protectedPaths) {
        if ([path isKindOfClass:NSString.class] && path.length) {
            [protected addObject:path.stringByStandardizingPath];
        }
    }

    unsigned long long freed = 0;
    NSString *root = [self backupRoot];
    NSArray<NSString *> *bundleNames = [fm contentsOfDirectoryAtPath:root error:nil] ?: @[];
    for (NSString *bundleName in bundleNames) {
        if ([bundleName hasPrefix:@"."]) continue;
        NSString *bundlePath = [root stringByAppendingPathComponent:bundleName];
        BOOL isDirectory = NO;
        if (![fm fileExistsAtPath:bundlePath isDirectory:&isDirectory] || !isDirectory) continue;

        NSArray<NSString *> *children = [fm contentsOfDirectoryAtPath:bundlePath error:nil] ?: @[];
        for (NSString *child in children) {
            NSString *path = [bundlePath stringByAppendingPathComponent:child];
            if ([protected containsObject:path.stringByStandardizingPath]) continue;
            BOOL remove = NO;
            if ([child hasPrefix:@"."]) {
                remove = (options & WQMStorageCleanupIncomplete) != 0;
            } else if (![WQMBackupRecord recordAtPath:path error:nil]) {
                remove = (options & WQMStorageCleanupInvalid) != 0;
            }
            if (!remove) continue;
            freed += WQMAppsSupportTreeSize(path);
            [fm removeItemAtPath:path error:nil];
        }
        if (options != 0 &&
            [fm contentsOfDirectoryAtPath:bundlePath error:nil].count == 0) {
            [fm removeItemAtPath:bundlePath error:nil];
        }
    }

    NSString *temporaryRoot = [self temporaryRoot];
    if (temporaryRoot.length && (options & WQMStorageCleanupTemporary)) {
        NSArray<NSString *> *temporaryNames = [fm contentsOfDirectoryAtPath:temporaryRoot error:nil] ?: @[];
        for (NSString *name in temporaryNames) {
            if (![self isTemporaryDirectoryName:name]) continue;
            NSString *path = [temporaryRoot stringByAppendingPathComponent:name];
            if ([protected containsObject:path.stringByStandardizingPath]) continue;
            freed += WQMAppsSupportTreeSize(path);
            [fm removeItemAtPath:path error:nil];
        }
    }

    if (freedBytes) *freedBytes = freed;
    return YES;
}

+ (NSArray<WQMBackupRecord *> *)recordsInBackupRoot
{
    NSMutableArray<WQMBackupRecord *> *records = [NSMutableArray new];
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *root = [self backupRoot];
    for (NSString *bundleName in [fm contentsOfDirectoryAtPath:root error:nil] ?: @[]) {
        if ([bundleName hasPrefix:@"."]) continue;
        NSString *bundlePath = [root stringByAppendingPathComponent:bundleName];
        BOOL isDirectory = NO;
        if (![fm fileExistsAtPath:bundlePath isDirectory:&isDirectory] || !isDirectory) continue;
        for (NSString *child in [fm contentsOfDirectoryAtPath:bundlePath error:nil] ?: @[]) {
            if ([child hasPrefix:@"."]) continue;
            WQMBackupRecord *record = [WQMBackupRecord
                recordAtPath:[bundlePath stringByAppendingPathComponent:child] error:nil];
            if (record) [records addObject:record];
        }
    }
    return records;
}

+ (NSUInteger)pruneSafetyBackupsKeeping:(NSUInteger)keep
                              excluding:(NSSet<NSString *> *)protectedPaths
                            deletedBytes:(unsigned long long *)deletedBytes
{
    NSFileManager *fm = NSFileManager.defaultManager;
    NSMutableSet<NSString *> *protected = [NSMutableSet set];
    for (NSString *path in protectedPaths) {
        if ([path isKindOfClass:NSString.class] && path.length) {
            [protected addObject:path.stringByStandardizingPath];
        }
    }

    NSMutableDictionary<NSString *, NSMutableArray<WQMBackupRecord *> *> *groups = [NSMutableDictionary new];
    for (WQMBackupRecord *record in [self recordsInBackupRoot]) {
        if (!WQMStorageReasonIsSafetyBackup(record.reason)) continue;
        NSMutableArray *group = groups[record.bundleIdentifier];
        if (!group) {
            group = [NSMutableArray new];
            groups[record.bundleIdentifier] = group;
        }
        [group addObject:record];
    }

    NSUInteger removed = 0;
    unsigned long long freed = 0;
    for (NSMutableArray<WQMBackupRecord *> *group in groups.allValues) {
        [group sortUsingComparator:^NSComparisonResult(WQMBackupRecord *a, WQMBackupRecord *b) {
            return [b.createdAt compare:a.createdAt];
        }];
        for (NSUInteger index = keep; index < group.count; index++) {
            WQMBackupRecord *record = group[index];
            if ([protected containsObject:record.path.stringByStandardizingPath]) continue;
            freed += WQMAppsSupportTreeSize(record.path);
            if ([fm removeItemAtPath:record.path error:nil]) removed += 1;
        }
    }
    if (deletedBytes) *deletedBytes = freed;
    return removed;
}

@end
