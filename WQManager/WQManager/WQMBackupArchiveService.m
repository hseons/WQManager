#import "WQMBackupArchiveService.h"
#import "WQMBackupStore.h"
#import "WQMLanguageManager.h"
#import "WQMOperationStore.h"
#import "WQAppsSupport.h"

#import <sys/stat.h>

static NSError *WQMArchiveError(NSInteger code, NSString *message)
{
    return [NSError errorWithDomain:@"WQMBackupArchiveService" code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSString *WQMArchiveSafeName(NSString *name)
{
    NSCharacterSet *bad = [NSCharacterSet characterSetWithCharactersInString:@"/:\\?%*|\"<>"];
    NSString *safe = [[name componentsSeparatedByCharactersInSet:bad] componentsJoinedByString:@"-"];
    safe = [safe stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return safe.length ? safe : @"WQManager Backup";
}

static BOOL WQMArchivePathInsideRoot(NSString *path, NSString *root)
{
    NSString *standardPath = path.stringByStandardizingPath;
    NSString *standardRoot = root.stringByStandardizingPath;
    return [standardPath hasPrefix:[standardRoot stringByAppendingString:@"/"]];
}

static BOOL WQMArchiveVerifyPayload(WQMBackupRecord *backup, NSString **reason)
{
    for (NSString *part in backup.parts) {
        NSString *partPath = [backup.path stringByAppendingPathComponent:part];
        struct stat st = {0};
        if (lstat(partPath.fileSystemRepresentation, &st) != 0 || !S_ISDIR(st.st_mode)) {
            if (reason) *reason = [NSString stringWithFormat:
                                   WQML(@"ARCHIVE_ERROR_PART_NOT_DIRECTORY",
                                        @"备份中的 %@ 不是普通目录"), part];
            return NO;
        }
        BOOL exists = NO;
        NSString *hash = WQAppsSupportTreeContentSignature(partPath, &exists, reason);
        if (!hash || !exists || ![hash isEqualToString:backup.partHashes[part]]) {
            if (reason && !*reason) *reason = [NSString stringWithFormat:
                                               WQML(@"ARCHIVE_ERROR_HASH_MISMATCH",
                                                    @"%@ 的内容哈希不匹配"), part];
            return NO;
        }
    }
    return YES;
}

@implementation WQMBackupArchiveService

+ (NSString *)backupContentTypeIdentifier
{
    return @"com.mumu.wqmanager.backup";
}

- (void)prepareExportForBackup:(WQMBackupRecord *)backup
                    completion:(void (^)(NSURL *_Nullable exportURL, NSError *_Nullable error))completion
{
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        void (^finish)(NSURL *, NSError *) = ^(NSURL *url, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(url, error); });
        };
        NSString *root = WQMBackupStore.backupRoot;
        if (!WQMArchivePathInsideRoot(backup.path, root)) {
            finish(nil, WQMArchiveError(1, WQML(@"ARCHIVE_ERROR_OUTSIDE_ROOT",
                                                @"备份不在 WQManager 备份目录内")));
            return;
        }
        NSString *reason = nil;
        WQMBackupRecord *verified = [WQMBackupRecord recordAtPath:backup.path error:&reason];
        if (!verified || !WQMArchiveVerifyPayload(verified, &reason)) {
            finish(nil, WQMArchiveError(2, reason ?: WQML(@"BACKUP_ERROR_VALIDATION",
                                                          @"备份校验失败")));
            return;
        }

        WQMOperationRecord *operation = [WQMOperationStore beginOperation:WQMOperationKindExport
                                                                  appName:verified.displayName
                                                         bundleIdentifier:verified.bundleIdentifier];
        operation.backupPath = verified.path;
        operation.bytes = verified.totalBytes;
        [WQMOperationStore updateRecord:operation];

        NSDateFormatter *stamp = [NSDateFormatter new];
        stamp.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        stamp.dateFormat = @"yyyyMMdd-HHmmss";
        NSString *name = [NSString stringWithFormat:@"%@_%@.wqbackup",
                          WQMArchiveSafeName(verified.displayName), [stamp stringFromDate:verified.createdAt]];
        unsigned long long freeBytes = WQMAppsSupportVolumeAvailableBytes(NSTemporaryDirectory());
        if (freeBytes < WQM_MIN_FREE_SPACE) {
            finish(nil, WQMArchiveError(5, [NSString stringWithFormat:
                                            WQML(@"ARCHIVE_ERROR_NO_SPACE",
                                                 @"可用空间不足：至少需要 %@，当前 %@。"),
                                            WQMFormatBytes(WQM_MIN_FREE_SPACE),
                                            WQMFormatBytes(freeBytes)]));
            return;
        }
        NSURL *destination = [NSURL fileURLWithPath:
            [NSTemporaryDirectory() stringByAppendingPathComponent:
             [NSString stringWithFormat:@"WQMExport-%@/%@", NSUUID.UUID.UUIDString, name]]
                                           isDirectory:YES];
        NSError *error = nil;
        [NSFileManager.defaultManager createDirectoryAtURL:destination.URLByDeletingLastPathComponent
                               withIntermediateDirectories:YES
                                                attributes:nil
                                                     error:&error];
        if (!error) {
            [NSFileManager.defaultManager copyItemAtURL:[NSURL fileURLWithPath:verified.path]
                                                  toURL:destination
                                                  error:&error];
        }
        if (!error) {
            NSString *validationError = nil;
            WQMBackupRecord *copy = [WQMBackupRecord recordAtPath:destination.path error:&validationError];
            if (!copy || !WQMArchiveVerifyPayload(copy, &reason)) {
                error = WQMArchiveError(3, validationError ?: reason
                                          ?: WQML(@"ARCHIVE_ERROR_EXPORT_VALIDATION",
                                                  @"导出的备份校验失败"));
            }
        }
        operation.status = error ? WQMOperationStatusFailure : WQMOperationStatusSuccess;
        operation.finishedAt = NSDate.date;
        operation.errorMessage = error.localizedDescription ?: @"";
        operation.message = error
            ? WQML(@"ARCHIVE_EXPORT_FAILED", @"导出失败")
            : WQML(@"ARCHIVE_EXPORTED", @"备份包已生成");
        [WQMOperationStore updateRecord:operation];
        if (error) {
            [NSFileManager.defaultManager removeItemAtURL:destination.URLByDeletingLastPathComponent error:nil];
            finish(nil, error);
            return;
        }
        finish(destination, nil);
    });
}

- (void)importBackupAtURL:(NSURL *)sourceURL
               completion:(void (^)(WQMBackupRecord *_Nullable backup, NSError *_Nullable error))completion
{
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        void (^finish)(WQMBackupRecord *, NSError *) = ^(WQMBackupRecord *backup, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(backup, error); });
        };
        BOOL scoped = [sourceURL startAccessingSecurityScopedResource];
        unsigned long long packageBytes = WQMAppsSupportTreeSize(sourceURL.path);
        unsigned long long freeBytes = WQMAppsSupportVolumeAvailableBytes(NSTemporaryDirectory());
        unsigned long long requiredBytes = packageBytes + WQM_MIN_FREE_SPACE;
        if (freeBytes < requiredBytes) {
            if (scoped) [sourceURL stopAccessingSecurityScopedResource];
            finish(nil, WQMArchiveError(6, [NSString stringWithFormat:
                                            WQML(@"ARCHIVE_ERROR_NO_SPACE",
                                                 @"可用空间不足：至少需要 %@，当前 %@。"),
                                            WQMFormatBytes(requiredBytes),
                                            WQMFormatBytes(freeBytes)]));
            return;
        }
        NSError *error = nil;
        NSURL *temporary = [NSURL fileURLWithPath:
            [NSTemporaryDirectory() stringByAppendingPathComponent:
             [NSString stringWithFormat:@"WQMImport-%@.wqbackup", NSUUID.UUID.UUIDString]]];
        [NSFileManager.defaultManager copyItemAtURL:sourceURL toURL:temporary error:&error];
        if (scoped) [sourceURL stopAccessingSecurityScopedResource];
        if (error) {
            finish(nil, error);
            return;
        }

        NSString *reason = nil;
        WQMBackupRecord *imported = [WQMBackupRecord recordAtPath:temporary.path error:&reason];
        if (!imported || !WQMArchiveVerifyPayload(imported, &reason)) {
            [NSFileManager.defaultManager removeItemAtURL:temporary error:nil];
            finish(nil, WQMArchiveError(4, reason ?: WQML(@"ARCHIVE_ERROR_IMPORT_INVALID",
                                                          @"导入的备份包无效")));
            return;
        }

        WQMOperationRecord *operation = [WQMOperationStore beginOperation:WQMOperationKindImport
                                                                  appName:imported.displayName
                                                         bundleIdentifier:imported.bundleIdentifier];
        operation.bytes = imported.totalBytes;
        [WQMOperationStore updateRecord:operation];

        NSString *bundleRoot = [[WQMBackupStore backupRoot]
                                stringByAppendingPathComponent:imported.bundleIdentifier];
        [NSFileManager.defaultManager createDirectoryAtPath:bundleRoot
                                withIntermediateDirectories:YES
                                                 attributes:nil
                                                      error:&error];
        NSDateFormatter *stamp = [NSDateFormatter new];
        stamp.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        stamp.dateFormat = @"yyyyMMdd-HHmmss-SSS";
        NSString *base = [stamp stringFromDate:imported.createdAt];
        NSString *destination = [bundleRoot stringByAppendingPathComponent:base];
        NSUInteger sequence = 2;
        while ([NSFileManager.defaultManager fileExistsAtPath:destination]) {
            destination = [bundleRoot stringByAppendingPathComponent:
                           [NSString stringWithFormat:@"%@-%lu", base, (unsigned long)sequence++]];
        }
        if (!error) {
            [NSFileManager.defaultManager moveItemAtURL:temporary
                                                  toURL:[NSURL fileURLWithPath:destination]
                                                  error:&error];
        }
        WQMBackupRecord *saved = nil;
        if (!error) {
            NSString *validationError = nil;
            saved = [WQMBackupRecord recordAtPath:destination error:&validationError];
            if (!saved) error = WQMArchiveError(7, validationError
                                                ?: WQML(@"ARCHIVE_ERROR_IMPORT_VALIDATION",
                                                        @"导入后的备份校验失败"));
            if (!saved) {
                [NSFileManager.defaultManager removeItemAtPath:destination error:nil];
            }
        }
        operation.status = error ? WQMOperationStatusFailure : WQMOperationStatusSuccess;
        operation.finishedAt = NSDate.date;
        operation.backupPath = saved.path ?: @"";
        operation.errorMessage = error.localizedDescription ?: @"";
        operation.message = error
            ? WQML(@"ARCHIVE_IMPORT_FAILED", @"导入失败")
            : WQML(@"ARCHIVE_IMPORTED", @"备份已导入");
        [WQMOperationStore updateRecord:operation];
        if (!error) {
            [[NSNotificationCenter defaultCenter] postNotificationName:WQMBackupStoreDidChangeNotification object:nil];
        }
        if (error) {
            [NSFileManager.defaultManager removeItemAtURL:temporary error:nil];
            finish(nil, error);
            return;
        }
        finish(saved, nil);
    });
}

- (void)deleteBackup:(WQMBackupRecord *)backup
           completion:(void (^)(BOOL success, NSError *_Nullable error))completion
{
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        void (^finish)(BOOL, NSError *) = ^(BOOL success, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(success, error); });
        };
        NSString *root = WQMBackupStore.backupRoot;
        if (!WQMArchivePathInsideRoot(backup.path, root)) {
            finish(NO, WQMArchiveError(5, WQML(@"ARCHIVE_ERROR_DELETE_OUTSIDE_ROOT",
                                               @"备份路径不在 WQManager 备份目录内")));
            return;
        }
        NSString *reason = nil;
        WQMBackupRecord *verified = [WQMBackupRecord recordAtPath:backup.path error:&reason];
        if (!verified) {
            finish(NO, WQMArchiveError(6, reason ?: WQML(@"ARCHIVE_ERROR_RECORD_INVALID",
                                                         @"备份记录无效")));
            return;
        }
        WQMOperationRecord *operation = [WQMOperationStore beginOperation:WQMOperationKindDeleteBackup
                                                                  appName:verified.displayName
                                                         bundleIdentifier:verified.bundleIdentifier];
        operation.backupPath = verified.path;
        operation.bytes = verified.totalBytes;
        [WQMOperationStore updateRecord:operation];
        NSError *error = nil;
        [NSFileManager.defaultManager removeItemAtPath:verified.path error:&error];
        operation.status = error ? WQMOperationStatusFailure : WQMOperationStatusSuccess;
        operation.finishedAt = NSDate.date;
        operation.errorMessage = error.localizedDescription ?: @"";
        operation.message = error
            ? WQML(@"ARCHIVE_DELETE_FAILED", @"删除备份失败")
            : WQML(@"ARCHIVE_DELETED", @"备份已删除");
        [WQMOperationStore updateRecord:operation];
        if (!error) {
            [[NSNotificationCenter defaultCenter] postNotificationName:WQMBackupStoreDidChangeNotification object:nil];
        }
        finish(error == nil, error);
    });
}

@end

