#import "WQMOperationStore.h"
#import "WQMLanguageManager.h"

NSNotificationName const WQMOperationStoreDidChangeNotification = @"WQMOperationStoreDidChangeNotification";

static NSString *const kWQMOperationsFile = @"Operations.plist";
static const NSUInteger kWQMMaxOperationRecords = 300;
static NSLock *gOperationLock;
static NSMutableArray<WQMOperationRecord *> *gOperationRecords;
static NSString *gOperationStorageRoot;

static NSLock *WQMOperationLock(void)
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gOperationLock = [NSLock new];
    });
    return gOperationLock;
}

@implementation WQMOperationRecord

+ (NSString *)displayNameForKind:(WQMOperationKind)kind
{
    switch (kind) {
        case WQMOperationKindBackup: return WQML(@"OPERATION_BACKUP", @"备份");
        case WQMOperationKindSafetyBackup: return WQML(@"OPERATION_SAFETY_BACKUP", @"安全备份");
        case WQMOperationKindRestore: return WQML(@"OPERATION_RESTORE", @"恢复");
        case WQMOperationKindRollback: return WQML(@"OPERATION_ROLLBACK", @"回滚");
        case WQMOperationKindRecovery: return WQML(@"OPERATION_RECOVERY", @"中断修复");
        case WQMOperationKindExport: return WQML(@"OPERATION_EXPORT", @"导出备份");
        case WQMOperationKindImport: return WQML(@"OPERATION_IMPORT", @"导入备份");
        case WQMOperationKindDeleteBackup: return WQML(@"OPERATION_DELETE_BACKUP", @"删除备份");
        case WQMOperationKindCleanCache: return WQML(@"OPERATION_CLEAN_CACHE", @"清理缓存");
        case WQMOperationKindDeleteFiles: return WQML(@"OPERATION_DELETE_FILES", @"删除文件");
    }
    return WQML(@"OPERATION", @"操作");
}

+ (NSString *)displayNameForStatus:(WQMOperationStatus)status
{
    switch (status) {
        case WQMOperationStatusRunning: return WQML(@"STATUS_RUNNING", @"进行中");
        case WQMOperationStatusSuccess: return WQML(@"STATUS_SUCCESS", @"成功");
        case WQMOperationStatusFailure: return WQML(@"STATUS_FAILURE", @"失败");
        case WQMOperationStatusRolledBack: return WQML(@"STATUS_ROLLED_BACK", @"已回滚");
        case WQMOperationStatusInterrupted: return WQML(@"STATUS_INTERRUPTED", @"已中断");
        case WQMOperationStatusCancelled: return WQML(@"STATUS_CANCELLED", @"已取消");
    }
    return WQML(@"UNKNOWN", @"未知");
}

@end

static NSString *WQMOperationDefaultRoot(void)
{
    return [[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                                                 NSUserDomainMask, YES).firstObject
             stringByAppendingPathComponent:@"WQManager"]
            stringByAppendingPathComponent:@"Operations"];
}

static NSString *WQMOperationCurrentRoot(void)
{
    return gOperationStorageRoot ?: WQMOperationDefaultRoot();
}

static NSString *WQMOperationFile(void)
{
    return [WQMOperationCurrentRoot() stringByAppendingPathComponent:kWQMOperationsFile];
}

static NSDictionary *WQMOperationDictionary(WQMOperationRecord *record)
{
    NSMutableDictionary *dictionary = [@{
        @"Identifier": record.identifier ?: NSUUID.UUID.UUIDString,
        @"Kind": @(record.kind),
        @"Status": @(record.status),
        @"AppName": record.appName ?: @"",
        @"BundleID": record.bundleIdentifier ?: @"",
        @"Scope": record.scope ?: @"",
        @"Reason": record.reason ?: @"",
        @"Message": record.message ?: @"",
        @"ErrorMessage": record.errorMessage ?: @"",
        @"BackupPath": record.backupPath ?: @"",
        @"SafetyBackupPath": record.safetyBackupPath ?: @"",
        @"JournalPath": record.journalPath ?: @"",
        @"Bytes": @(record.bytes),
        @"StartedAt": record.startedAt ?: NSDate.date,
    } mutableCopy];
    if (record.finishedAt) dictionary[@"FinishedAt"] = record.finishedAt;
    return dictionary;
}

static WQMOperationRecord *WQMOperationRecordFromDictionary(NSDictionary *dictionary)
{
    if (![dictionary isKindOfClass:NSDictionary.class] ||
        ![dictionary[@"Identifier"] isKindOfClass:NSString.class] ||
        ![dictionary[@"StartedAt"] isKindOfClass:NSDate.class]) {
        return nil;
    }
    WQMOperationRecord *record = [WQMOperationRecord new];
    record.identifier = dictionary[@"Identifier"];
    record.kind = [dictionary[@"Kind"] integerValue];
    record.status = [dictionary[@"Status"] integerValue];
    record.appName = [dictionary[@"AppName"] isKindOfClass:NSString.class] ? dictionary[@"AppName"] : @"";
    record.bundleIdentifier = [dictionary[@"BundleID"] isKindOfClass:NSString.class] ? dictionary[@"BundleID"] : @"";
    record.scope = [dictionary[@"Scope"] isKindOfClass:NSString.class] ? dictionary[@"Scope"] : @"";
    record.reason = [dictionary[@"Reason"] isKindOfClass:NSString.class] ? dictionary[@"Reason"] : @"";
    record.message = [dictionary[@"Message"] isKindOfClass:NSString.class] ? dictionary[@"Message"] : @"";
    record.errorMessage = [dictionary[@"ErrorMessage"] isKindOfClass:NSString.class] ? dictionary[@"ErrorMessage"] : @"";
    record.backupPath = [dictionary[@"BackupPath"] isKindOfClass:NSString.class] ? dictionary[@"BackupPath"] : @"";
    record.safetyBackupPath = [dictionary[@"SafetyBackupPath"] isKindOfClass:NSString.class] ? dictionary[@"SafetyBackupPath"] : @"";
    record.journalPath = [dictionary[@"JournalPath"] isKindOfClass:NSString.class] ? dictionary[@"JournalPath"] : @"";
    record.bytes = [dictionary[@"Bytes"] unsignedLongLongValue];
    record.startedAt = dictionary[@"StartedAt"];
    record.finishedAt = [dictionary[@"FinishedAt"] isKindOfClass:NSDate.class] ? dictionary[@"FinishedAt"] : nil;
    return record;
}

@interface WQMOperationStore ()
+ (void)loadRecordsIfNeededLocked;
+ (void)writeRecordsLocked:(NSArray<NSDictionary *> *)records;
+ (void)persistLocked;
+ (void)addRecord:(WQMOperationRecord *)record;
@end

@implementation WQMOperationStore

+ (void)loadRecordsIfNeededLocked
{
    if (gOperationRecords) return;
    gOperationRecords = [NSMutableArray new];
    NSDictionary *root = [NSDictionary dictionaryWithContentsOfFile:WQMOperationFile()];
    NSArray *items = [root isKindOfClass:NSDictionary.class] ? root[@"Operations"] : nil;
    BOOL changed = NO;
    for (id item in [items isKindOfClass:NSArray.class] ? items : @[]) {
        WQMOperationRecord *record = WQMOperationRecordFromDictionary(item);
        if (!record) continue;
        if (record.status == WQMOperationStatusRunning) {
            record.status = WQMOperationStatusInterrupted;
            record.finishedAt = NSDate.date;
            record.message = WQML(@"OPERATION_INTERRUPTED_PREVIOUS", @"上次运行在操作完成前结束");
            changed = YES;
        }
        [gOperationRecords addObject:record];
    }
    if (changed) {
        NSMutableArray *saved = [NSMutableArray new];
        for (WQMOperationRecord *record in gOperationRecords) [saved addObject:WQMOperationDictionary(record)];
        [self writeRecordsLocked:saved];
    }
}

+ (void)writeRecordsLocked:(NSArray<NSDictionary *> *)records
{
    NSString *root = WQMOperationCurrentRoot();
    [NSFileManager.defaultManager createDirectoryAtPath:root
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:nil];
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:@{
        @"Format": @1,
        @"Operations": records,
    } format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    [data writeToFile:WQMOperationFile() options:NSDataWritingAtomic error:nil];
}

+ (void)persistLocked
{
    while (gOperationRecords.count > kWQMMaxOperationRecords) {
        [gOperationRecords removeObjectAtIndex:0];
    }
    NSMutableArray *items = [NSMutableArray new];
    for (WQMOperationRecord *record in gOperationRecords) [items addObject:WQMOperationDictionary(record)];
    [self writeRecordsLocked:items];
}

+ (WQMOperationRecord *)beginOperation:(WQMOperationKind)kind
                               appName:(NSString *)appName
                      bundleIdentifier:(NSString *)bundleIdentifier
{
    WQMOperationRecord *record = [WQMOperationRecord new];
    record.identifier = NSUUID.UUID.UUIDString;
    record.kind = kind;
    record.status = WQMOperationStatusRunning;
    record.appName = appName ?: bundleIdentifier ?: WQML(@"UNKNOWN_APP", @"未知 App");
    record.bundleIdentifier = bundleIdentifier ?: @"";
    record.startedAt = NSDate.date;
    [[self class] addRecord:record];
    return record;
}

+ (void)addRecord:(WQMOperationRecord *)record
{
    NSLock *lock = WQMOperationLock();
    [lock lock];
    [self loadRecordsIfNeededLocked];
    [gOperationRecords addObject:record];
    [self persistLocked];
    [lock unlock];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:WQMOperationStoreDidChangeNotification object:nil];
    });
}

+ (void)updateRecord:(WQMOperationRecord *)record
{
    if (!record.identifier.length) return;
    NSLock *lock = WQMOperationLock();
    [lock lock];
    [self loadRecordsIfNeededLocked];
    NSUInteger index = [gOperationRecords indexOfObjectPassingTest:
        ^BOOL(WQMOperationRecord *candidate, NSUInteger idx, BOOL *stop) {
            return [candidate.identifier isEqualToString:record.identifier];
        }];
    if (index != NSNotFound) gOperationRecords[index] = record;
    else [gOperationRecords addObject:record];
    [self persistLocked];
    [lock unlock];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:WQMOperationStoreDidChangeNotification object:nil];
    });
}

+ (NSArray<WQMOperationRecord *> *)allOperations
{
    NSLock *lock = WQMOperationLock();
    [lock lock];
    [self loadRecordsIfNeededLocked];
    NSArray *records = [gOperationRecords copy];
    [lock unlock];
    return [records sortedArrayUsingComparator:^NSComparisonResult(WQMOperationRecord *a, WQMOperationRecord *b) {
        return [b.startedAt compare:a.startedAt];
    }];
}

+ (void)clear
{
    NSLock *lock = WQMOperationLock();
    [lock lock];
    gOperationRecords = [NSMutableArray new];
    [self persistLocked];
    [lock unlock];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:WQMOperationStoreDidChangeNotification object:nil];
    });
}

+ (void)setStorageRootForTesting:(NSString *)root
{
    NSLock *lock = WQMOperationLock();
    [lock lock];
    gOperationStorageRoot = [root copy];
    gOperationRecords = nil;
    [lock unlock];
}

static NSString *WQMCSVField(NSString *value)
{
    if (!value.length) return @"";
    BOOL needsQuotes = [value containsString:@","] ||
                       [value containsString:@"\""] ||
                       [value containsString:@"\n"] ||
                       [value containsString:@"\r"];
    if (!needsQuotes) return value;
    NSString *escaped = [value stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""];
    return [NSString stringWithFormat:@"\"%@\"", escaped];
}

static NSString *WQMCSVTimestamp(NSDate *date)
{
    if (!date) return @"";
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    return [formatter stringFromDate:date];
}

+ (NSString *)CSVExportForRecords:(NSArray<WQMOperationRecord *> *)records
{
    NSArray<NSString *> *header = @[
        WQML(@"EXPORT_COLUMN_TIME", @"时间"),
        WQML(@"EXPORT_COLUMN_KIND", @"操作"),
        WQML(@"EXPORT_COLUMN_STATUS", @"状态"),
        WQML(@"EXPORT_COLUMN_APP", @"App"),
        @"Bundle ID",
        WQML(@"EXPORT_COLUMN_SCOPE", @"范围"),
        WQML(@"EXPORT_COLUMN_BYTES", @"大小（字节）"),
        WQML(@"EXPORT_COLUMN_MESSAGE", @"说明"),
        WQML(@"EXPORT_COLUMN_ERROR", @"错误"),
    ];
    NSMutableArray<NSString *> *lines = [NSMutableArray new];
    [lines addObject:[header componentsJoinedByString:@","]];
    for (WQMOperationRecord *record in records) {
        NSArray<NSString *> *fields = @[
            WQMCSVTimestamp(record.startedAt),
            [WQMOperationRecord displayNameForKind:record.kind],
            [WQMOperationRecord displayNameForStatus:record.status],
            WQMCSVField(record.appName),
            WQMCSVField(record.bundleIdentifier),
            WQMCSVField(record.scope),
            [NSString stringWithFormat:@"%llu", record.bytes],
            WQMCSVField(record.message),
            WQMCSVField(record.errorMessage),
        ];
        [lines addObject:[fields componentsJoinedByString:@","]];
    }
    // \uFEFF lets Excel detect UTF-8; other tools ignore it.
    return [@"\uFEFF" stringByAppendingString:[lines componentsJoinedByString:@"\r\n"]];
}

+ (NSString *)CSVExportFileNameForDate:(NSDate *)date
{
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.dateFormat = @"yyyyMMdd-HHmmss";
    return [NSString stringWithFormat:@"WQManager-history-%@.csv", [formatter stringFromDate:date ?: NSDate.date]];
}

@end

