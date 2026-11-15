#import "WQMBackupStore.h"
#import "WQMLanguageManager.h"
#import "WQAppsSupport.h"
#import "WQMBackupSelection.h"
#import "WQAccessSafety.h"

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
    if (!WQAppsSupportIsInteger(format) || (format.unsignedIntegerValue != 2 && format.unsignedIntegerValue != 3)) {
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
    BOOL custom = format.unsignedIntegerValue == 3;
    NSString *scopeCode = [manifest[@"ScopeCode"] isKindOfClass:NSString.class] ? manifest[@"ScopeCode"] :
        ([parts containsObject:@"tmp"] ? @"full" : @"quick");
    NSArray *requested = custom ? [WQMBackupSelection canonicalPaths:manifest[@"RequestedParts"]] :
        [scopeCode isEqual:@"full"] ? @[@"Documents", @"Library", @"tmp"] :
        [scopeCode isEqual:@"quick"] ? @[@"Documents", @"Library"] : @[];
    NSArray<NSString *> *canonical = custom ? (parts.count ? [WQMBackupSelection canonicalPaths:parts] : @[]) : WQMCanonicalParts(parts);
    if (!requested || !canonical || (custom && (![manifest[@"ScopeCode"] isEqual:@"custom"] ||
        ![requested isEqualToArray:manifest[@"RequestedParts"]] || ![canonical isEqualToArray:parts] ||
        ![[NSSet setWithArray:parts] isSubsetOfSet:[NSSet setWithArray:requested]])) ||
        canonical.count != parts.count ||
        ![[NSSet setWithArray:hashes.allKeys] isEqualToSet:[NSSet setWithArray:canonical]]) {
        if (error) *error = WQML(@"BACKUP_ERROR_INVALID_PARTS", @"备份目录或哈希列表无效");
        return nil;
    }

    NSFileManager *fm = NSFileManager.defaultManager;
    if (![WQMBackupSelection validatePayloadAtPath:path parts:canonical]) {
        if (error) *error = WQML(@"BACKUP_ERROR_UNREGISTERED_CONTENT", @"备份目录包含未登记内容或链接");
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

    NSString *fingerprint = WQAppsSupportFileFingerprint(manifestPath);
    if (!fingerprint) {
        if (error) *error = WQML(@"BACKUP_ERROR_MANIFEST_UNREADABLE", @"备份清单无法读取");
        return nil;
    }

    WQMBackupRecord *record = [WQMBackupRecord new];
    record.manifestFingerprint = fingerprint;
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
    } else if ([record.scopeCode isEqualToString:@"custom"]) {
        record.scopeName = WQML(@"CUSTOM_BACKUP", @"自定义备份");
    } else {
        record.scopeName = [manifest[@"Scope"] isKindOfClass:NSString.class]
            ? manifest[@"Scope"] : WQML(@"CUSTOM_BACKUP", @"自定义备份");
    }
    record.formatVersion = format.unsignedIntegerValue;
    record.requestedParts = requested;
    record.note = [manifest[@"Note"] isKindOfClass:NSString.class] ? manifest[@"Note"] : @"";
    record.protectedBackup = WQAppsSupportIsBool(manifest[@"Protected"]) && [manifest[@"Protected"] boolValue];
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

@implementation WQMBackupGroup

- (unsigned long long)totalBytes
{
    unsigned long long total = 0;
    for (WQMBackupRecord *record in self.backups) total += record.totalBytes;
    return total;
}

- (NSDate *)latestAt
{
    return self.backups.firstObject.createdAt ?: NSDate.distantPast;
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

+ (BOOL)updateBackup:(WQMBackupRecord *)backup note:(NSString *)note
          protected:(BOOL)protectedBackup error:(NSError **)error
{
    @synchronized(self) {
        NSString *root = self.backupRoot.stringByStandardizingPath;
        NSString *path = backup.path.stringByStandardizingPath;
        NSString *relative = [path hasPrefix:[root stringByAppendingString:@"/"]]
            ? [path substringFromIndex:root.length + 1] : @"";
        int fd = relative.pathComponents.count == 2 ? WQOpenDirectoryNoLinks(path) : -1;
        WQMBackupRecord *fresh = fd >= 0 ? [WQMBackupRecord recordAtPath:path error:nil] : nil;
        if (fd >= 0) close(fd);
        if (!fresh || ![fresh.manifestFingerprint isEqual:backup.manifestFingerprint] || note.length > 300) {
            if (error) *error = [NSError errorWithDomain:@"WQMBackupStore" code:1 userInfo:@{
                NSLocalizedDescriptionKey: WQML(@"BACKUP_METADATA_CHANGED", @"备份已变化或备注超过 300 字，请刷新后重试。") }];
            return NO;
        }
        NSString *manifestPath = [path stringByAppendingPathComponent:kWQMBackupManifestName];
        NSMutableDictionary *manifest = [[NSDictionary dictionaryWithContentsOfFile:manifestPath] mutableCopy];
        manifest[@"Note"] = note ?: @"";
        manifest[@"Protected"] = @(protectedBackup);
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:manifest format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
        if (!data) return NO;
        int directory = WQOpenDirectoryNoLinks(path);
        int parent = WQOpenDirectoryNoLinks(path.stringByDeletingLastPathComponent);
        NSString *temporary = [NSString stringWithFormat:@".metadata-%@.plist", NSUUID.UUID.UUIDString];
        int output = parent >= 0 ? openat(parent, temporary.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600) : -1;
        BOOL written = directory >= 0 && output >= 0 && WQWriteBytes(output, data) && fsync(output) == 0;
        if (output >= 0 && close(output) != 0) written = NO;
        WQMBackupRecord *current = written ? [WQMBackupRecord recordAtPath:path error:nil] : nil;
        written = written && [current.manifestFingerprint isEqual:backup.manifestFingerprint];
        if (written) written = renameat(parent, temporary.fileSystemRepresentation, directory, kWQMBackupManifestName.fileSystemRepresentation) == 0;
        if (written) written = WQSyncDirectory(directory) && WQSyncDirectory(parent);
        if (parent >= 0) { if (output >= 0) unlinkat(parent, temporary.fileSystemRepresentation, 0); close(parent); }
        if (directory >= 0) close(directory);
        if (!written) {
            if (error) *error = [NSError errorWithDomain:@"WQMBackupStore" code:2 userInfo:@{
                NSLocalizedDescriptionKey: WQML(@"BACKUP_METADATA_WRITE_FAILED", @"备份信息写入失败，请刷新后核对。") }];
            return NO;
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:WQMBackupStoreDidChangeNotification object:nil];
        return YES;
    }
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


+ (NSArray<WQMBackupGroup *> *)groupsForRecords:(NSArray<WQMBackupRecord *> *)records
{
    NSMutableDictionary<NSString *, NSMutableArray<WQMBackupRecord *> *> *grouped = [NSMutableDictionary new];
    NSMutableArray<NSString *> *order = [NSMutableArray new];
    for (WQMBackupRecord *record in records) {
        NSString *key = record.bundleIdentifier.length ? record.bundleIdentifier : record.displayName ?: @"";
        NSMutableArray *bucket = grouped[key];
        if (!bucket) {
            bucket = [NSMutableArray new];
            grouped[key] = bucket;
            [order addObject:key];
        }
        [bucket addObject:record];
    }

    NSMutableArray<WQMBackupGroup *> *groups = [NSMutableArray arrayWithCapacity:order.count];
    for (NSString *key in order) {
        NSArray<WQMBackupRecord *> *bucket = grouped[key];
        NSArray<WQMBackupRecord *> *sorted = [bucket sortedArrayUsingComparator:
            ^NSComparisonResult(WQMBackupRecord *a, WQMBackupRecord *b) {
                return [b.createdAt compare:a.createdAt];
            }];
        WQMBackupGroup *group = [WQMBackupGroup new];
        group.bundleIdentifier = key;
        WQMBackupRecord *newest = sorted.firstObject;
        group.displayName = newest.displayName.length ? newest.displayName : key;
        group.backups = sorted;
        [groups addObject:group];
    }
    [groups sortUsingComparator:^NSComparisonResult(WQMBackupGroup *a, WQMBackupGroup *b) {
        return [b.latestAt compare:a.latestAt];
    }];
    return groups;
}

@end