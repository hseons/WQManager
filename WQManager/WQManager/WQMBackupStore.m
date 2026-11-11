#import "WQMBackupStore.h"
#import "WQMLanguageManager.h"
#import "WQAppsSupport.h"

NSNotificationName const WQMBackupStoreDidChangeNotification = @"WQMBackupStoreDidChangeNotification";

static NSString *const kWQMBackupManifestName = @"manifest.plist";
static NSString *gWQMBackupRootForTesting;

static NSArray<NSString *> *WQMCanonicalParts(NSArray<NSString *> *parts)
{
    NSSet *allowed = [NSSet setWithObjects:@"Documents", @"Library", @"tmp", nil];
    NSMutableSet *seen = [NSMutableSet set];
    for (id part in parts) {
        if (![part isKindOfClass:NSString.class] || ![allowed containsObject:part]) return @[];
        [seen addObject:part];
    }
    NSMutableArray *ordered = [NSMutableArray new];
    for (NSString *name in @[@"Documents", @"Library", @"tmp"]) {
        if ([seen containsObject:name]) [ordered addObject:name];
    }
    return ordered;
}

@implementation WQMBackupRecord

+ (nullable instancetype)recordAtPath:(NSString *)path error:(NSString *_Nullable *_Nullable)error
{
    NSString *manifestPath = [path stringByAppendingPathComponent:kWQMBackupManifestName];
    NSDictionary *manifest = [NSDictionary dictionaryWithContentsOfFile:manifestPath];
    if (![manifest isKindOfClass:NSDictionary.class]) {
        if (error) *error = WQML(@"BACKUP_ERROR_MANIFEST_MISSING", @"备份清单不存在或格式错误");
        return nil;
    }
    if (!WQAppsSupportIsBool(manifest[@"Complete"]) || ![manifest[@"Complete"] boolValue]) {
        if (error) *error = WQML(@"BACKUP_ERROR_INCOMPLETE", @"备份未标记为完整");
        return nil;
    }
    NSNumber *format = manifest[@"Format"];
    if (!WQAppsSupportIsInteger(format) || format.unsignedIntegerValue != 2) {
        if (error) *error = WQML(@"BACKUP_ERROR_UNSUPPORTED_FORMAT", @"不支持的备份格式");
        return nil;
    }
    NSString *bundleID = manifest[@"BundleID"];
    if (!WQAppsSupportBundleIDValid(bundleID)) {
        if (error) *error = WQML(@"BACKUP_ERROR_INVALID_BUNDLE_ID", @"备份中的 Bundle ID 无效");
        return nil;
    }
    NSDate *created = manifest[@"Created"];
    NSArray *parts = manifest[@"Parts"];
    NSDictionary *hashes = manifest[@"PartHashes"];
    if (![created isKindOfClass:NSDate.class] || ![parts isKindOfClass:NSArray.class] ||
        ![hashes isKindOfClass:NSDictionary.class]) {
        if (error) *error = WQML(@"BACKUP_ERROR_MANIFEST_FIELDS", @"备份清单字段缺失");
        return nil;
    }
    NSArray<NSString *> *canonical = WQMCanonicalParts(parts);
    if (canonical.count != parts.count ||
        ![[NSSet setWithArray:hashes.allKeys] isEqualToSet:[NSSet setWithArray:canonical]]) {
        if (error) *error = WQML(@"BACKUP_ERROR_INVALID_PARTS", @"备份目录或哈希列表无效");
        return nil;
    }

    NSFileManager *fm = NSFileManager.defaultManager;
    NSSet *children = [NSSet setWithArray:[fm contentsOfDirectoryAtPath:path error:nil] ?: @[]];
    NSMutableSet *expected = [NSMutableSet setWithObject:kWQMBackupManifestName];
    [expected addObjectsFromArray:canonical];
    if (![children isEqualToSet:expected]) {
        if (error) *error = WQML(@"BACKUP_ERROR_UNREGISTERED_CONTENT", @"备份目录包含未登记内容");
        return nil;
    }

    for (NSString *part in canonical) {
        NSString *partPath = [path stringByAppendingPathComponent:part];
        BOOL isDirectory = NO;
        if (![fm fileExistsAtPath:partPath isDirectory:&isDirectory] || !isDirectory) {
            if (error) *error = [NSString stringWithFormat:
                                 WQML(@"BACKUP_ERROR_MISSING_PART", @"备份缺少 %@ 目录"), part];
            return nil;
        }
        id hash = hashes[part];
        if (![hash isKindOfClass:NSString.class] || [hash length] == 0) {
            if (error) *error = [NSString stringWithFormat:
                                 WQML(@"BACKUP_ERROR_MISSING_HASH", @"%@ 缺少内容哈希"), part];
            return nil;
        }
    }

    WQMBackupRecord *record = [WQMBackupRecord new];
    record.path = path;
    record.bundleIdentifier = bundleID;
    record.displayName = [manifest[@"DisplayName"] isKindOfClass:NSString.class]
        ? manifest[@"DisplayName"] : bundleID;
    record.scopeCode = [manifest[@"ScopeCode"] isKindOfClass:NSString.class]
        ? manifest[@"ScopeCode"] : ([canonical containsObject:@"tmp"] ? @"full" : @"quick");
    if ([record.scopeCode isEqualToString:@"quick"]) {
        record.scopeName = WQML(@"QUICK_BACKUP", @"快速备份");
    } else if ([record.scopeCode isEqualToString:@"full"]) {
        record.scopeName = WQML(@"FULL_BACKUP", @"完整备份");
    } else {
        record.scopeName = [manifest[@"Scope"] isKindOfClass:NSString.class]
            ? manifest[@"Scope"] : WQML(@"CUSTOM_BACKUP", @"自定义备份");
    }
    record.reason = [manifest[@"Reason"] isKindOfClass:NSString.class]
        ? manifest[@"Reason"] : @"";
    record.parts = canonical;
    record.partHashes = hashes;
    record.systemVersion = [manifest[@"SystemVersion"] isKindOfClass:NSString.class]
        ? manifest[@"SystemVersion"] : WQML(@"UNKNOWN_SYSTEM", @"未知系统");
    record.createdAt = created;
    NSNumber *totalBytes = manifest[@"TotalBytes"];
    record.totalBytes = [totalBytes isKindOfClass:NSNumber.class] ? totalBytes.unsignedLongLongValue : 0;
    return record;
}

@end

@implementation WQMBackupStore

+ (NSString *)backupRoot
{
    if (gWQMBackupRootForTesting.length) return gWQMBackupRootForTesting;
    return [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject]
            stringByAppendingPathComponent:@"AppBackups"];
}

+ (void)setBackupRootForTesting:(NSString *)root
{
    gWQMBackupRootForTesting = [root copy];
}

+ (NSArray<WQMBackupRecord *> *)allBackups
{
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *root = self.backupRoot;
    [fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
    NSMutableArray<WQMBackupRecord *> *records = [NSMutableArray new];
    NSArray<NSString *> *bundleDirectories = [fm contentsOfDirectoryAtPath:root error:nil] ?: @[];
    for (NSString *bundleDirectory in bundleDirectories) {
        if ([bundleDirectory hasPrefix:@"."]) continue;
        NSString *bundlePath = [root stringByAppendingPathComponent:bundleDirectory];
        NSArray<NSString *> *backupDirectories = [fm contentsOfDirectoryAtPath:bundlePath error:nil] ?: @[];
        for (NSString *backupDirectory in backupDirectories) {
            if ([backupDirectory hasPrefix:@"."]) continue;
            NSString *path = [bundlePath stringByAppendingPathComponent:backupDirectory];
            WQMBackupRecord *record = [WQMBackupRecord recordAtPath:path error:nil];
            if (record) [records addObject:record];
        }
    }
    [records sortUsingComparator:^NSComparisonResult(WQMBackupRecord *a, WQMBackupRecord *b) {
        return [b.createdAt compare:a.createdAt];
    }];
    return records;
}

@end

