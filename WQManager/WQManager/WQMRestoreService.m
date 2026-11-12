#import "WQMRestoreService.h"
#import "WQMAppModel.h"
#import "WQMBackupService.h"
#import "WQMBackupStore.h"
#import "WQMLanguageManager.h"
#import "WQMLoadController.h"
#import "WQMOperationStore.h"
#import "WQAccess.h"
#import "WQAppsSupport.h"

#import <errno.h>
#import <fcntl.h>
#import <sys/stat.h>
#import <unistd.h>

static NSString *const kWQMRestoreFormat = @"WQMRestoreJournal";

static NSString *WQMRestoreDirectory(void)
{
    return [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject]
            stringByAppendingPathComponent:@"RestoreRecovery"];
}

static NSArray<NSDictionary *> *WQMRestoreJournals(void)
{
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *root = WQMRestoreDirectory();
    [fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
    NSMutableArray<NSDictionary *> *journals = [NSMutableArray new];
    for (NSString *name in [fm contentsOfDirectoryAtPath:root error:nil] ?: @[]) {
        if (![name.pathExtension isEqualToString:@"plist"]) continue;
        NSString *path = [root stringByAppendingPathComponent:name];
        NSDictionary *journal = [NSDictionary dictionaryWithContentsOfFile:path];
        if (![journal isKindOfClass:NSDictionary.class] ||
            ![journal[@"Format"] isEqualToString:kWQMRestoreFormat]) {
            [journals addObject:@{@"JournalPath": path, @"State": @"Invalid"}];
            continue;
        }
        {
            NSMutableDictionary *copy = [journal mutableCopy];
            copy[@"JournalPath"] = path;
            [journals addObject:copy];
        }
    }
    return journals;
}

static BOOL WQMRestoreSyncDirectory(NSString *path)
{
    int fd = open(path.fileSystemRepresentation, O_RDONLY);
    if (fd < 0) return NO;
    BOOL synced = (fsync(fd) == 0);
    close(fd);
    return synced;
}

static BOOL WQMRestoreRemoveJournal(NSString *path)
{
    if (!path.length) return YES;
    if (unlink(path.fileSystemRepresentation) != 0 && errno != ENOENT) return NO;
    return WQMRestoreSyncDirectory(path.stringByDeletingLastPathComponent);
}

static BOOL WQMRestoreWriteJournal(NSDictionary *journal, NSString *path, NSError **error)
{
    if (![NSPropertyListSerialization propertyList:journal isValidForFormat:NSPropertyListBinaryFormat_v1_0]) {
        if (error) *error = [NSError errorWithDomain:@"WQMRestoreService" code:20
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                           WQML(@"RESTORE_ERROR_INVALID_JOURNAL",
                                                                @"恢复日志格式无效")}];
        return NO;
    }
    NSError *serializationError = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:journal
                                                               format:NSPropertyListBinaryFormat_v1_0
                                                              options:0
                                                                error:&serializationError];
    if (!data) {
        if (error) *error = serializationError;
        return NO;
    }
    NSString *directory = path.stringByDeletingLastPathComponent;
    NSString *temporary = [directory stringByAppendingPathComponent:
                           [NSString stringWithFormat:@".%@.journal", NSUUID.UUID.UUIDString]];
    int fd = open(temporary.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL, 0644);
    if (fd < 0) {
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                           [NSString stringWithFormat:
                                                            WQML(@"RESTORE_ERROR_JOURNAL_WRITE",
                                                                 @"无法写入恢复日志（errno %d）"), errno]}];
        return NO;
    }
    const uint8_t *bytes = data.bytes;
    NSUInteger offset = 0;
    BOOL written = YES;
    int failureErrno = 0;
    while (offset < data.length) {
        ssize_t count = write(fd, bytes + offset, data.length - offset);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) { written = NO; failureErrno = errno; break; }
        offset += (NSUInteger)count;
    }
    if (written && fsync(fd) != 0) { written = NO; failureErrno = errno; }
    close(fd);
    if (written && rename(temporary.fileSystemRepresentation, path.fileSystemRepresentation) != 0) {
        written = NO;
        failureErrno = errno;
    }
    if (!written) {
        unlink(temporary.fileSystemRepresentation);
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:failureErrno
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                           [NSString stringWithFormat:
                                                            WQML(@"RESTORE_ERROR_JOURNAL_WRITE",
                                                                 @"无法写入恢复日志（errno %d）"), failureErrno]}];
        return NO;
    }
    if (!WQMRestoreSyncDirectory(directory)) {
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                           WQML(@"RESTORE_ERROR_JOURNAL_SYNC",
                                                                @"无法将恢复日志写入磁盘")}];
        return NO;
    }
    return YES;
}

static BOOL WQMRestoreAllowedPart(NSString *part)
{
    return [part isEqualToString:@"Documents"] ||
           [part isEqualToString:@"Library"] ||
           [part isEqualToString:@"tmp"];
}

static NSArray<NSString *> *WQMRestorePartsForScopeCode(NSString *scopeCode)
{
    if ([scopeCode isEqualToString:@"quick"]) return @[@"Documents", @"Library"];
    if ([scopeCode isEqualToString:@"full"]) return @[@"Documents", @"Library", @"tmp"];
    return @[];
}

static BOOL WQMRestoreValidateApp(WQMAppModel *app, NSString **reason)
{
    if (!WQAppsSupportBundleIDValid(app.bundleIdentifier) ||
        !app.accessAvailable || !app.identityKnown) {
        if (reason) *reason = WQML(@"RESTORE_ERROR_TARGET_INVALID",
                                   @"目标 App 缺少有效 Bundle ID、访问权限或容器身份");
        return NO;
    }
    struct stat current = {0};
    if (!wq_stat(app.containerPath, &current) || !S_ISDIR(current.st_mode) ||
        current.st_dev != app.containerDevice || current.st_ino != app.containerInode) {
        if (reason) *reason = WQML(@"RESTORE_ERROR_CONTAINER_CHANGED",
                                   @"目标 App 容器在扫描后发生变化");
        return NO;
    }
    NSString *label = wq_container_label(app.containerPath);
    if (![label isEqualToString:app.bundleIdentifier]) {
        if (reason) *reason = WQML(@"RESTORE_ERROR_ID_MISMATCH",
                                   @"目标 App 的容器标识不再匹配");
        return NO;
    }
    if (!wq_grant(app.containerPath)) {
        if (reason) *reason = WQML(@"RESTORE_ERROR_GRANT_FAILED",
                                   @"无法取得目标 App 的访问权限");
        return NO;
    }
    return YES;
}

static BOOL WQMRestoreVerifyBackup(WQMBackupRecord *record, WQMLoadController *load, NSString **reason)
{
    NSString *root = [WQMBackupStore backupRoot].stringByStandardizingPath;
    NSString *path = record.path.stringByStandardizingPath;
    if (![path hasPrefix:[root stringByAppendingString:@"/"]]) {
        if (reason) *reason = WQML(@"RESTORE_ERROR_BACKUP_OUTSIDE_ROOT",
                                   @"备份不在 WQManager 的备份目录内");
        return NO;
    }
    NSString *loadError = nil;
    WQMBackupRecord *fresh = [WQMBackupRecord recordAtPath:path error:&loadError];
    if (!fresh || ![fresh.bundleIdentifier isEqualToString:record.bundleIdentifier]) {
        if (reason) *reason = loadError ?: WQML(@"RESTORE_ERROR_BACKUP_CHANGED",
                                                @"备份清单已变化或无效");
        return NO;
    }
    for (NSString *part in fresh.parts) {
        BOOL exists = NO;
        NSString *partPath = [path stringByAppendingPathComponent:part];
        NSString *hash = WQAppsSupportTreeContentSignaturePaced(
            partPath, &exists,
            ^(unsigned long long bytes) { [load consumeBytes:bytes]; }, reason);
        if (!hash || !exists || ![hash isEqualToString:fresh.partHashes[part]]) {
            if (reason && !*reason) *reason = [NSString stringWithFormat:
                                               WQML(@"RESTORE_ERROR_BACKUP_PART_CHANGED",
                                                    @"备份的 %@ 内容已变化"), part];
            return NO;
        }
    }
    return YES;
}

// The safety backup was hashed by WQMBackupService while it read the staged
// tree back, so its PartHashes are already verified. Re-reading every part here
// would duplicate that work; instead prove the record still describes the files
// on disk by reloading the manifest and comparing its fingerprint, bundle ID,
// parts and hashes.
static BOOL WQMRestoreSafetyBackupIntact(WQMBackupRecord *record, NSString **reason)
{
    NSString *root = [WQMBackupStore backupRoot].stringByStandardizingPath;
    NSString *path = record.path.stringByStandardizingPath;
    if (!record.manifestFingerprint ||
        ![path hasPrefix:[root stringByAppendingString:@"/"]]) {
        if (reason) *reason = WQML(@"RESTORE_ERROR_BACKUP_OUTSIDE_ROOT",
                                   @"备份不在 WQManager 的备份目录内");
        return NO;
    }
    NSString *loadError = nil;
    WQMBackupRecord *fresh = [WQMBackupRecord recordAtPath:path error:&loadError];
    if (!fresh ||
        ![fresh.manifestFingerprint isEqualToString:record.manifestFingerprint] ||
        ![fresh.bundleIdentifier isEqualToString:record.bundleIdentifier] ||
        ![fresh.parts isEqualToArray:record.parts] ||
        ![fresh.partHashes isEqualToDictionary:record.partHashes]) {
        if (reason) *reason = loadError ?: WQML(@"RESTORE_ERROR_BACKUP_CHANGED",
                                                @"备份清单已变化或无效");
        return NO;
    }
    return YES;
}

// Captures identity and shape digests for the named parts without reading file
// bytes. A reduced-verification restore reads content once, then proves nothing
// changed from inode/mtime/ctime/size instead of re-reading every byte.
static NSDictionary<NSString *, NSString *> *WQMRestoreCaptureMetadata(NSString *root,
                                                                       NSArray<NSString *> *parts,
                                                                       NSString **reason)
{
    NSMutableDictionary<NSString *, NSString *> *captured = [NSMutableDictionary new];
    for (NSString *part in parts) {
        BOOL exists = NO;
        NSString *identity = nil;
        NSString *shape = nil;
        NSString *error = nil;
        if (!WQAppsSupportTreeDigests([root stringByAppendingPathComponent:part], &exists,
                                      &identity, &shape, NULL, &error)) {
            if (reason && !*reason) *reason = error ?: WQML(@"RESTORE_ERROR_BACKUP_VALIDATION",
                                                            @"备份校验失败。");
            return nil;
        }
        captured[part] = [NSString stringWithFormat:@"%d|%@|%@", exists ? 1 : 0, identity, shape];
    }
    return captured;
}

static BOOL WQMRestoreTargetMatchesBackupMetadata(NSString *container,
                                                  NSArray<NSString *> *requestedParts,
                                                  WQMBackupRecord *backup,
                                                  NSDictionary<NSString *, NSString *> *captured,
                                                  NSString **reason)
{
    for (NSString *part in backup.parts) {
        if (captured[part]) continue;
        if (reason) *reason = WQML(@"RESTORE_ERROR_TARGET_VALIDATION", @"目标 App 校验失败。");
        return NO;
    }
    NSDictionary<NSString *, NSString *> *current =
        WQMRestoreCaptureMetadata(container, backup.parts, reason);
    if (!current) return NO;
    for (NSString *part in backup.parts) {
        if ([current[part] isEqualToString:captured[part]]) continue;
        if (reason) *reason = [NSString stringWithFormat:
            WQML(@"RESTORE_ERROR_TARGET_CHANGED_AFTER_SAFETY",
                 @"目标 %@ 在安全备份后发生变化，请关闭 App 后重试"), part];
        return NO;
    }
    for (NSString *part in requestedParts) {
        if ([backup.parts containsObject:part]) continue;
        NSString *target = [container stringByAppendingPathComponent:part];
        struct stat st = {0};
        if (!wq_stat(target, &st)) continue;
        NSArray *children = [NSFileManager.defaultManager contentsOfDirectoryAtPath:target error:nil];
        if (!children || children.count) {
            if (reason) *reason = [NSString stringWithFormat:
                WQML(@"RESTORE_ERROR_TARGET_NEW_CONTENT_AFTER_SAFETY",
                     @"目标 %@ 在安全备份后出现了新内容"), part];
            return NO;
        }
    }
    return YES;
}

static BOOL WQMRestoreBackupMetadataUnchanged(WQMBackupRecord *backup,
                                              NSDictionary<NSString *, NSString *> *captured,
                                              NSString **reason)
{
    NSString *loadError = nil;
    WQMBackupRecord *fresh = [WQMBackupRecord recordAtPath:backup.path error:&loadError];
    if (!fresh || ![fresh.manifestFingerprint isEqualToString:backup.manifestFingerprint]) {
        if (reason) *reason = loadError ?: WQML(@"RESTORE_ERROR_BACKUP_CHANGED",
                                                @"备份清单已变化或无效");
        return NO;
    }
    NSDictionary<NSString *, NSString *> *current =
        WQMRestoreCaptureMetadata(backup.path, backup.parts, reason);
    if (!current) return NO;
    for (NSString *part in backup.parts) {
        if ([current[part] isEqualToString:captured[part]]) continue;
        if (reason) *reason = [NSString stringWithFormat:
            WQML(@"RESTORE_ERROR_BACKUP_PART_CHANGED", @"备份的 %@ 内容已变化"), part];
        return NO;
    }
    return YES;
}

static BOOL WQMRestoreApply(NSString *container, NSArray<NSString *> *requestedParts,
                            WQMBackupRecord *source, WQMLoadController *load,
                            NSString **reason)
{
    for (NSString *part in requestedParts) {
        if (!WQMRestoreAllowedPart(part)) {
            if (reason) *reason = WQML(@"RESTORE_ERROR_PART_NOT_ALLOWED",
                                       @"恢复目录不在允许范围内");
            return NO;
        }
        NSString *target = [container stringByAppendingPathComponent:part];
        struct stat current = {0};
        if (wq_stat(target, &current) && !S_ISDIR(current.st_mode)) {
            if (reason) *reason = [NSString stringWithFormat:
                                   WQML(@"RESTORE_ERROR_TARGET_NOT_DIRECTORY",
                                        @"目标 %@ 不是目录"), part];
            return NO;
        }
        if (current.st_mode) (void)wq_grant(target);
        unsigned long long freed = 0;
        if (!wq_purge_contents(target, &freed)) {
            if (reason) *reason = [NSString stringWithFormat:
                                   WQML(@"RESTORE_ERROR_PURGE_TARGET",
                                        @"无法清空目标 %@（errno %d）"), part, errno];
            return NO;
        }

        if ([source.parts containsObject:part]) {
            NSString *sourcePart = [source.path stringByAppendingPathComponent:part];
            if (!wq_copy_contents_paced(sourcePart, target,
                                        ^{ [load consumeEntry]; }, reason)) {
                if (reason && !*reason) *reason = [NSString stringWithFormat:
                                                   WQML(@"RESTORE_ERROR_COPY_TARGET",
                                                        @"复制 %@ 到目标失败"), part];
                return NO;
            }
        }
    }

    for (NSString *part in requestedParts) {
        NSString *target = [container stringByAppendingPathComponent:part];
        if ([source.parts containsObject:part]) {
            BOOL exists = NO;
            NSString *hash = WQAppsSupportTreeContentSignaturePaced(
                target, &exists,
                ^(unsigned long long bytes) { [load consumeBytes:bytes]; }, reason);
            if (!hash || !exists || ![hash isEqualToString:source.partHashes[part]]) {
                if (reason && !*reason) *reason = [NSString stringWithFormat:
                                                   WQML(@"RESTORE_ERROR_VERIFY_TARGET",
                                                        @"目标 %@ 恢复后校验失败"), part];
                return NO;
            }
        } else {
            struct stat st = {0};
            if (wq_stat(target, &st)) {
                NSError *listError = nil;
                NSArray *children = [NSFileManager.defaultManager contentsOfDirectoryAtPath:target error:&listError];
                if (!children || children.count) {
                    if (reason) *reason = [NSString stringWithFormat:
                                           WQML(@"RESTORE_ERROR_TARGET_NOT_EMPTY",
                                                @"目标 %@ 应保持为空（%@）"), part,
                                           listError.localizedDescription
                                               ?: WQML(@"RESTORE_STILL_HAS_CONTENT", @"仍有内容")];
                    return NO;
                }
            }
        }
    }
    return YES;
}

static BOOL WQMRestoreTargetMatchesBackup(NSString *container, NSArray<NSString *> *requestedParts,
                                          WQMBackupRecord *backup, NSString **reason)
{
    for (NSString *part in requestedParts) {
        if (!WQMRestoreAllowedPart(part)) {
            if (reason) *reason = WQML(@"RESTORE_ERROR_PART_NOT_ALLOWED",
                                       @"恢复目录不在允许范围内");
            return NO;
        }
        NSString *target = [container stringByAppendingPathComponent:part];
        if ([backup.parts containsObject:part]) {
            BOOL exists = NO;
            NSString *hash = WQAppsSupportTreeContentSignature(target, &exists, reason);
            if (!hash || !exists || ![hash isEqualToString:backup.partHashes[part]]) {
                if (reason && !*reason) {
                    *reason = [NSString stringWithFormat:
                               WQML(@"RESTORE_ERROR_TARGET_CHANGED_AFTER_SAFETY",
                                    @"目标 %@ 在安全备份后发生变化，请关闭 App 后重试"), part];
                }
                return NO;
            }
        } else {
            struct stat st = {0};
            if (wq_stat(target, &st)) {
                NSArray *children = [NSFileManager.defaultManager contentsOfDirectoryAtPath:target error:nil];
                if (!children || children.count) {
                    if (reason) *reason = [NSString stringWithFormat:
                                           WQML(@"RESTORE_ERROR_TARGET_NEW_CONTENT_AFTER_SAFETY",
                                                @"目标 %@ 在安全备份后出现了新内容"), part];
                    return NO;
                }
            }
        }
    }
    return YES;
}

@implementation WQMRestoreService

- (void)restoreBackup:(WQMBackupRecord *)backup
                toApp:(WQMAppModel *)app
             progress:(nullable void (^)(NSString *status))progress
           completion:(void (^)(BOOL success, NSString *message, NSError *_Nullable error))completion
{
    void (^report)(NSString *) = ^(NSString *status) {
        if (progress) dispatch_async(dispatch_get_main_queue(), ^{ progress(status); });
    };
    __block WQMOperationRecord *operation = nil;
    void (^finish)(BOOL, NSString *, NSError *) = ^(BOOL success, NSString *message, NSError *error) {
        if (operation) {
            if (operation.status == WQMOperationStatusRunning) {
                operation.status = success ? WQMOperationStatusSuccess : WQMOperationStatusFailure;
            }
            operation.finishedAt = NSDate.date;
            operation.message = message ?: @"";
            operation.errorMessage = error.localizedDescription ?: @"";
            [WQMOperationStore updateRecord:operation];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(success, message, error); });
    };

    WQMLoadController *load = [WQMLoadController controllerForCurrentPreferences];
    dispatch_async(dispatch_get_global_queue(load.plan.qos, 0), ^{
        for (NSDictionary *journal in WQMRestoreJournals()) {
            NSString *state = journal[@"State"];
            if ([state isEqualToString:@"Active"]) {
                finish(NO, WQML(@"RESTORE_ERROR_ACTIVE_JOURNAL",
                                @"存在尚未处理的恢复日志，请先修复上次中断的操作。"), nil);
                return;
            }
            if (![state isEqualToString:@"Committed"]) {
                finish(NO, [NSString stringWithFormat:
                            WQML(@"RESTORE_ERROR_JOURNAL_INVALID",
                                 @"恢复日志无法读取或状态未知：%@。请检查 Documents/RestoreRecovery 后重试。"),
                            [journal[@"JournalPath"] lastPathComponent]], nil);
                return;
            }
        }
        NSString *reason = nil;
        if (![backup.bundleIdentifier isEqualToString:app.bundleIdentifier]) {
            finish(NO, WQML(@"RESTORE_ERROR_BUNDLE_ID_MISMATCH",
                            @"备份与目标 App 的 Bundle ID 不一致。"), nil);
            return;
        }
        NSArray<NSString *> *requestedParts = WQMRestorePartsForScopeCode(backup.scopeCode);
        if (!requestedParts.count) {
            finish(NO, WQML(@"RESTORE_ERROR_UNKNOWN_SCOPE", @"备份范围无法识别。"), nil);
            return;
        }
        if (!WQMRestoreValidateApp(app, &reason)) {
            finish(NO, reason ?: WQML(@"RESTORE_ERROR_TARGET_VALIDATION", @"目标 App 校验失败。"), nil);
            return;
        }
        report(WQML(@"RESTORE_PROGRESS_VERIFY_BACKUP", @"正在校验备份内容…"));
        if (!WQMRestoreVerifyBackup(backup, load, &reason)) {
            finish(NO, reason ?: WQML(@"RESTORE_ERROR_BACKUP_VALIDATION", @"备份校验失败。"), nil);
            return;
        }
        BOOL reducePasses = load.reduceVerificationPasses;
        NSDictionary<NSString *, NSString *> *sourceMetadata = nil;
        NSDictionary<NSString *, NSString *> *targetMetadata = nil;
        if (reducePasses) {
            sourceMetadata = WQMRestoreCaptureMetadata(backup.path, backup.parts, &reason);
            targetMetadata = WQMRestoreCaptureMetadata(app.containerPath, requestedParts, &reason);
            if (!sourceMetadata || !targetMetadata) {
                finish(NO, reason ?: WQML(@"RESTORE_ERROR_BACKUP_VALIDATION", @"备份校验失败。"), nil);
                return;
            }
        }
        operation = [WQMOperationStore beginOperation:WQMOperationKindRestore
                                              appName:app.displayName
                                     bundleIdentifier:app.bundleIdentifier];
        operation.scope = backup.scopeName;
        operation.backupPath = backup.path;
        [WQMOperationStore updateRecord:operation];

        NSInteger safetyScope = [backup.scopeCode isEqualToString:@"full"]
            ? WQMBackupScopeFull : WQMBackupScopeQuick;
        report(WQML(@"RESTORE_PROGRESS_SAFETY_BACKUP", @"正在备份目标当前数据…"));
        WQMBackupService *backupService = [WQMBackupService new];
        [backupService backupApp:app scope:safetyScope
                          reason:WQML(@"RESTORE_SAFETY_REASON", @"恢复前自动安全备份")
                        progress:report
                      completion:^(WQMBackupRecord *safety, NSError *backupError) {
            if (!safety) {
                finish(NO, [NSString stringWithFormat:
                            WQML(@"RESTORE_ERROR_SAFETY_FAILED",
                                 @"安全备份失败，未修改目标 App。%@"),
                            backupError.localizedDescription ?: @""], backupError);
                return;
            }
            operation.safetyBackupPath = safety.path;
            [WQMOperationStore updateRecord:operation];
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                NSString *validation = nil;
                if (!WQMRestoreSafetyBackupIntact(safety, &validation)) {
                    finish(NO, [NSString stringWithFormat:
                                WQML(@"RESTORE_ERROR_SAFETY_VALIDATION",
                                     @"安全备份校验失败，未修改目标 App。%@"),
                                validation ?: @""], nil);
                    return;
                }
                if (!WQMRestoreValidateApp(app, &validation)) {
                    finish(NO, [NSString stringWithFormat:
                                WQML(@"RESTORE_ERROR_APP_CHANGED_AFTER_SAFETY",
                                     @"目标 App 在安全备份后发生变化，未修改数据。%@"),
                                validation ?: @""], nil);
                    return;
                }
                BOOL targetMatches = reducePasses
                    ? WQMRestoreTargetMatchesBackupMetadata(app.containerPath, requestedParts,
                                                            safety, targetMetadata, &validation)
                    : WQMRestoreTargetMatchesBackup(app.containerPath, requestedParts, safety,
                                                    &validation);
                if (!targetMatches) {
                    finish(NO, [NSString stringWithFormat:
                                WQML(@"RESTORE_ERROR_TARGET_CHANGED_AFTER_SAFETY_SHORT",
                                     @"目标数据在安全备份后发生变化，未修改数据。%@"),
                                validation ?: @""], nil);
                    return;
                }
                BOOL sourceOK = reducePasses
                    ? WQMRestoreBackupMetadataUnchanged(backup, sourceMetadata, &validation)
                    : WQMRestoreVerifyBackup(backup, load, &validation);
                if (!sourceOK) {
                    finish(NO, [NSString stringWithFormat:
                                WQML(@"RESTORE_ERROR_SOURCE_CHANGED",
                                     @"源备份在恢复前发生变化，未修改数据。%@"),
                                validation ?: @""], nil);
                    return;
                }

                int targetPID = wq_process_id_for_bundle(app.bundleIdentifier);
                if (targetPID > 0) {
                    finish(NO, [NSString stringWithFormat:
                                WQML(@"RESTORE_ERROR_APP_RUNNING",
                                     @"目标 App 正在运行（pid %d）。请从多任务界面关闭它后再试。"),
                                targetPID], nil);
                    return;
                }
                unsigned long long freeBytes = WQMAppsSupportVolumeAvailableBytes(app.containerPath);
                if (freeBytes < WQM_MIN_FREE_SPACE) {
                    finish(NO, [NSString stringWithFormat:
                                WQML(@"RESTORE_ERROR_NO_SPACE",
                                     @"可用空间不足：至少需要 %@，当前 %@。未修改目标 App。"),
                                WQMFormatBytes(WQM_MIN_FREE_SPACE), WQMFormatBytes(freeBytes)], nil);
                    return;
                }
                NSString *journalPath = [WQMRestoreDirectory()
                    stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingString:@".plist"]];
                operation.journalPath = journalPath;
                [WQMOperationStore updateRecord:operation];
                NSDictionary *journal = @{
                    @"Format": kWQMRestoreFormat,
                    @"State": @"Active",
                    @"BundleID": app.bundleIdentifier,
                    @"DisplayName": app.displayName ?: app.bundleIdentifier,
                    @"Container": app.containerPath,
                    @"Device": @(app.containerDevice),
                    @"Inode": @(app.containerInode),
                    @"RequestedParts": requestedParts,
                    @"SourceBackup": backup.path,
                    @"SafetyBackup": safety.path,
                    @"Created": NSDate.date,
                };
                NSError *journalError = nil;
                if (!WQMRestoreWriteJournal(journal, journalPath, &journalError)) {
                    finish(NO, [NSString stringWithFormat:
                                WQML(@"RESTORE_ERROR_JOURNAL_CREATE",
                                     @"无法创建恢复日志，未修改目标 App。%@"),
                                journalError.localizedDescription ?: @""], journalError);
                    return;
                }

                report(WQML(@"RESTORE_PROGRESS_REPLACE", @"正在替换 App 数据…"));
                NSString *applyError = nil;
                BOOL applied = WQMRestoreApply(app.containerPath, requestedParts, backup, load, &applyError);
                if (applied) {
                    NSMutableDictionary *committed = [journal mutableCopy];
                    committed[@"State"] = @"Committed";
                    committed[@"Completed"] = NSDate.date;
                    if (!WQMRestoreWriteJournal(committed, journalPath, NULL) ||
                        !WQMRestoreRemoveJournal(journalPath)) {
                        NSString *donePath = [journalPath stringByAppendingString:@".done"];
                        if (rename(journalPath.fileSystemRepresentation,
                                   donePath.fileSystemRepresentation) == 0) {
                            WQMRestoreSyncDirectory(journalPath.stringByDeletingLastPathComponent);
                        }
                        wq_log(@"restore %@: journal cleanup failed, demoted %@", app.bundleIdentifier, donePath);
                    }
                    wq_log(@"restore %@: OK from %@; safety %@", app.bundleIdentifier,
                           backup.path, safety.path);
                    finish(YES, [NSString stringWithFormat:
                                 WQML(@"RESTORE_SUCCESS",
                                      @"恢复完成。\n\n恢复前数据已保存在：\n%@\n\n请打开目标 App 验证登录状态和功能。"),
                                 safety.path], nil);
                    return;
                }

                report(WQML(@"RESTORE_PROGRESS_ROLLBACK", @"替换失败，正在回滚…"));
                NSString *rollbackError = nil;
                BOOL rolledBack = WQMRestoreApply(app.containerPath, requestedParts, safety, load, &rollbackError);
                if (rolledBack) {
                    (void)WQMRestoreRemoveJournal(journalPath);
                    operation.status = WQMOperationStatusRolledBack;
                    wq_log(@"restore %@: FAILED (%@), rolled back from %@", app.bundleIdentifier,
                           applyError ?: @"unknown", safety.path);
                    finish(NO, [NSString stringWithFormat:
                                WQML(@"RESTORE_ROLLED_BACK",
                                     @"恢复失败，已从自动安全备份回滚。\n\n失败原因：%@"),
                                applyError ?: WQML(@"UNKNOWN_ERROR", @"未知错误")], nil);
                    return;
                }

                wq_log(@"restore %@: FAILED (%@), rollback FAILED (%@), journal %@",
                       app.bundleIdentifier, applyError ?: @"unknown",
                       rollbackError ?: @"unknown", journalPath);
                finish(NO, [NSString stringWithFormat:
                            WQML(@"RESTORE_ROLLBACK_FAILED",
                                 @"恢复失败，自动回滚也未完成。\n\n失败：%@\n回滚：%@\n\n恢复日志：%@\n安全备份：%@"),
                            applyError ?: WQML(@"UNKNOWN_ERROR", @"未知错误"),
                            rollbackError ?: WQML(@"UNKNOWN_ERROR", @"未知错误"),
                            journalPath, safety.path], nil);
            });
        }];
    });
}

+ (nullable NSString *)activeRecoverySummary
{
    NSString *invalidName = nil;
    for (NSDictionary *journal in WQMRestoreJournals()) {
        NSString *state = journal[@"State"];
        if ([state isEqualToString:@"Active"]) {
            NSString *name = journal[@"DisplayName"];
            NSString *bundleID = journal[@"BundleID"];
            return [NSString stringWithFormat:@"%@（%@）",
                    name ?: bundleID ?: WQML(@"UNKNOWN_APP", @"未知 App"),
                    bundleID ?: @"unknown"];
        }
        if (![state isEqualToString:@"Committed"] && !invalidName) {
            invalidName = [journal[@"JournalPath"] lastPathComponent];
        }
    }
    if (invalidName) {
        return [NSString stringWithFormat:
                WQML(@"RECOVERY_SUMMARY_INVALID", @"发现无法读取的恢复日志：%@"), invalidName];
    }
    return nil;
}

+ (NSArray<NSString *> *)pendingRecoveryBackupPaths
{
    NSMutableArray<NSString *> *paths = [NSMutableArray new];
    for (NSDictionary *journal in WQMRestoreJournals()) {
        if (![journal[@"State"] isEqualToString:@"Active"]) continue;
        for (NSString *key in @[@"SourceBackup", @"SafetyBackup"]) {
            id value = journal[key];
            if ([value isKindOfClass:NSString.class] && [value length]) [paths addObject:value];
        }
    }
    return paths;
}

+ (void)recoverActiveRecoveryWithProgress:(nullable void (^)(NSString *status))progress
                                completion:(void (^)(BOOL success, NSString *message,
                                                     NSError *_Nullable error))completion
{
    void (^report)(NSString *) = ^(NSString *status) {
        if (progress) dispatch_async(dispatch_get_main_queue(), ^{ progress(status); });
    };
    __block WQMOperationRecord *operation = nil;
    void (^finish)(BOOL, NSString *, NSError *) = ^(BOOL success, NSString *message, NSError *error) {
        if (operation) {
            operation.status = success ? WQMOperationStatusSuccess : WQMOperationStatusFailure;
            operation.finishedAt = NSDate.date;
            operation.message = message ?: @"";
            operation.errorMessage = error.localizedDescription ?: @"";
            [WQMOperationStore updateRecord:operation];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(success, message, error); });
    };
    WQMLoadController *load = [WQMLoadController controllerForCurrentPreferences];
    dispatch_async(dispatch_get_global_queue(load.plan.qos, 0), ^{
        NSDictionary *active = nil;
        for (NSDictionary *journal in WQMRestoreJournals()) {
            if ([journal[@"State"] isEqualToString:@"Active"]) {
                active = journal;
                break;
            }
        }
        if (!active) {
            for (NSDictionary *journal in WQMRestoreJournals()) {
                if ([journal[@"State"] isEqualToString:@"Committed"]) continue;
                finish(NO, [NSString stringWithFormat:
                            WQML(@"RECOVERY_ERROR_JOURNAL_INVALID",
                                 @"恢复日志无法读取或状态未知：%@，需要人工检查。"),
                            [journal[@"JournalPath"] lastPathComponent]], nil);
                return;
            }
            finish(NO, WQML(@"RECOVERY_ERROR_NONE", @"没有需要修复的中断恢复。"), nil);
            return;
        }
        operation = [WQMOperationStore beginOperation:WQMOperationKindRecovery
                                              appName:active[@"DisplayName"] ?: active[@"BundleID"]
                                     bundleIdentifier:active[@"BundleID"] ?: @""];
        operation.safetyBackupPath = active[@"SafetyBackup"] ?: @"";
        operation.journalPath = active[@"JournalPath"] ?: @"";
        [WQMOperationStore updateRecord:operation];
        NSString *bundleID = active[@"BundleID"];
        NSString *container = active[@"Container"];
        NSArray *parts = active[@"RequestedParts"];
        NSString *safetyPath = active[@"SafetyBackup"];
        BOOL partsValid = [parts isKindOfClass:NSArray.class];
        if (partsValid) {
            for (id part in parts) {
                if (![part isKindOfClass:NSString.class] || !WQMRestoreAllowedPart(part)) {
                    partsValid = NO;
                    break;
                }
            }
        }
        if (!WQAppsSupportBundleIDValid(bundleID) || ![container isKindOfClass:NSString.class] ||
            !partsValid || ![safetyPath isKindOfClass:NSString.class]) {
            finish(NO, WQML(@"RECOVERY_ERROR_INVALID_JOURNAL", @"恢复日志字段无效，需要人工检查。"), nil);
            return;
        }
        WQMBackupRecord *safety = [WQMBackupRecord recordAtPath:safetyPath error:nil];
        NSString *reason = nil;
        if (!safety || ![safety.bundleIdentifier isEqualToString:bundleID] ||
            !WQMRestoreVerifyBackup(safety, load, &reason)) {
            finish(NO, reason ?: WQML(@"RECOVERY_ERROR_SAFETY_UNAVAILABLE",
                                      @"自动安全备份已不可用，需要人工检查。"), nil);
            return;
        }
        struct stat current = {0};
        if (!wq_stat(container, &current) || !S_ISDIR(current.st_mode) ||
            current.st_dev != [active[@"Device"] intValue] ||
            current.st_ino != [active[@"Inode"] unsignedLongLongValue]) {
            finish(NO, WQML(@"RECOVERY_ERROR_CONTAINER_CHANGED",
                            @"目标 App 容器身份已变化，不能自动回滚。"), nil);
            return;
        }
        if (!wq_grant(container)) {
            finish(NO, WQML(@"RECOVERY_ERROR_GRANT_FAILED",
                            @"无法取得目标 App 的访问权限，不能自动回滚。"), nil);
            return;
        }
        if (![wq_container_label(container) isEqualToString:bundleID]) {
            finish(NO, WQML(@"RECOVERY_ERROR_ID_MISMATCH",
                            @"目标 App 的容器标识不再匹配，不能自动回滚。"), nil);
            return;
        }
        int targetPID = wq_process_id_for_bundle(bundleID);
        if (targetPID > 0) {
            finish(NO, [NSString stringWithFormat:
                        WQML(@"RECOVERY_ERROR_APP_RUNNING",
                             @"目标 App 正在运行（pid %d），请从多任务界面关闭它后再修复。"),
                        targetPID], nil);
            return;
        }
        report(WQML(@"RECOVERY_PROGRESS", @"正在回滚上次中断的恢复…"));
        if (!WQMRestoreApply(container, parts, safety, load, &reason)) {
            finish(NO, reason ?: WQML(@"RECOVERY_ERROR_FAILED", @"中断恢复回滚失败。"), nil);
            return;
        }
        NSString *journalPath = active[@"JournalPath"];
        (void)WQMRestoreRemoveJournal(journalPath);
        finish(YES, WQML(@"RECOVERY_SUCCESS", @"已从自动安全备份回滚上次中断的恢复。"), nil);
    });
}

@end

