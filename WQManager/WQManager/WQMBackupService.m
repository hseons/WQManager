#import "WQMBackupService.h"
#import "WQMAppModel.h"
#import "WQMBackupStore.h"
#import "WQMLanguageManager.h"
#import "WQMOperationStore.h"
#import "WQAccess.h"
#import "WQAppsSupport.h"

#import <errno.h>
#import <sys/stat.h>

static NSString *const kWQMBackupManifestName = @"manifest.plist";
static NSString *const kWQMBackupStagingPrefix = @".incomplete-";

@implementation WQMBackupService

- (void)backupApp:(WQMAppModel *)app
            scope:(NSInteger)scope
           reason:(nullable NSString *)reason
         progress:(nullable void (^)(NSString *status))progress
       completion:(void (^)(WQMBackupRecord *_Nullable backup, NSError *_Nullable error))completion
{
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        __block WQMOperationRecord *operation = nil;
        void (^report)(NSString *) = ^(NSString *status) {
            if (progress) dispatch_async(dispatch_get_main_queue(), ^{ progress(status); });
        };
        void (^finish)(WQMBackupRecord *, NSError *) = ^(WQMBackupRecord *backup, NSError *error) {
            if (operation) {
                operation.status = backup ? WQMOperationStatusSuccess : WQMOperationStatusFailure;
                operation.finishedAt = NSDate.date;
                operation.backupPath = backup.path ?: operation.backupPath;
                operation.bytes = backup.totalBytes;
                operation.errorMessage = error.localizedDescription ?: @"";
                [WQMOperationStore updateRecord:operation];
            }
            dispatch_async(dispatch_get_main_queue(), ^{ completion(backup, error); });
        };

        WQMBackupScopeDescriptor *descriptor =
            [WQMBackupScopeDescriptor descriptorForScope:(WQMBackupScope)scope];
        if (!descriptor || descriptor.relativePaths.count == 0) {
            finish(nil, [NSError errorWithDomain:@"WQMBackupService" code:1
                                        userInfo:@{NSLocalizedDescriptionKey:
                                                       WQML(@"BACKUP_ERROR_INVALID_SCOPE", @"备份范围无效")}]);
            return;
        }
        operation = [WQMOperationStore beginOperation:
                     reason.length ? WQMOperationKindSafetyBackup : WQMOperationKindBackup
                                               appName:app.displayName
                                      bundleIdentifier:app.bundleIdentifier];
        operation.scope = descriptor.title;
        operation.reason = reason ?: @"";
        [WQMOperationStore updateRecord:operation];
        if (!WQAppsSupportBundleIDValid(app.bundleIdentifier) ||
            !app.accessAvailable || !app.identityKnown) {
            finish(nil, [NSError errorWithDomain:@"WQMBackupService" code:2
                                        userInfo:@{NSLocalizedDescriptionKey:
                                                       WQML(@"BACKUP_ERROR_NO_ACCESS",
                                                            @"当前 App 缺少有效访问或容器身份")}]);
            return;
        }

        struct stat containerStat = {0};
        if (!wq_stat(app.containerPath, &containerStat) || !S_ISDIR(containerStat.st_mode) ||
            containerStat.st_dev != app.containerDevice || containerStat.st_ino != app.containerInode) {
            finish(nil, [NSError errorWithDomain:@"WQMBackupService" code:3
                                        userInfo:@{NSLocalizedDescriptionKey:
                                                       WQML(@"BACKUP_ERROR_CONTAINER_CHANGED",
                                                            @"App 容器在扫描后发生变化，请刷新后重试")}]);
            return;
        }
        NSString *label = wq_container_label(app.containerPath);
        if (![label isEqualToString:app.bundleIdentifier]) {
            finish(nil, [NSError errorWithDomain:@"WQMBackupService" code:4
                                        userInfo:@{NSLocalizedDescriptionKey:
                                                       WQML(@"BACKUP_ERROR_ID_MISMATCH",
                                                            @"App 容器标识不再匹配")}]);
            return;
        }
        if (!wq_grant(app.containerPath)) {
            finish(nil, [NSError errorWithDomain:@"WQMBackupService" code:5
                                        userInfo:@{NSLocalizedDescriptionKey:
                                                       WQML(@"BACKUP_ERROR_GRANT_FAILED",
                                                            @"无法取得 App 容器访问权限")}]);
            return;
        }

        NSFileManager *fm = NSFileManager.defaultManager;
        NSString *root = [[WQMBackupStore backupRoot]
                          stringByAppendingPathComponent:app.bundleIdentifier];
        NSError *fileError = nil;
        if (![fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:&fileError]) {
            finish(nil, fileError);
            return;
        }

        NSDate *created = NSDate.date;
        NSDateFormatter *stamp = [NSDateFormatter new];
        stamp.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        stamp.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
        stamp.dateFormat = @"yyyyMMdd-HHmmss-SSS";
        NSString *baseName = [stamp stringFromDate:created];
        NSString *staging = [root stringByAppendingPathComponent:
                             [kWQMBackupStagingPrefix stringByAppendingString:NSUUID.UUID.UUIDString]];
        if (![fm createDirectoryAtPath:staging withIntermediateDirectories:NO attributes:nil error:&fileError]) {
            finish(nil, fileError);
            return;
        }

        NSMutableArray<NSString *> *parts = [NSMutableArray new];
        NSMutableDictionary<NSString *, NSString *> *hashes = [NSMutableDictionary new];
        NSMutableDictionary<NSString *, NSString *> *sourceStates = [NSMutableDictionary new];
        unsigned long long totalBytes = 0;
        NSString *failure = nil;

        for (NSString *part in descriptor.relativePaths) {
            @autoreleasepool {
                report([NSString stringWithFormat:WQML(@"BACKUP_PROGRESS_PART", @"正在备份 %@…"), part]);
                NSString *source = [app.containerPath stringByAppendingPathComponent:part];
                struct stat sourceStat = {0};
                if (!wq_stat(source, &sourceStat)) {
                    if (errno == ENOENT) continue;
                    failure = [NSString stringWithFormat:
                               WQML(@"BACKUP_ERROR_READ_PART", @"无法读取 %@"), part];
                    break;
                }
                if (!S_ISDIR(sourceStat.st_mode)) {
                    failure = [NSString stringWithFormat:
                               WQML(@"BACKUP_ERROR_PART_NOT_DIRECTORY", @"%@ 不是目录"), part];
                    break;
                }

                BOOL sourceExists = NO;
                NSString *sourceState = nil;
                NSString *sourceShape = nil;
                if (!WQAppsSupportTreeDigests(source, &sourceExists, &sourceState, &sourceShape, NULL, &failure) ||
                    !sourceExists) {
                    failure = failure ?: [NSString stringWithFormat:
                                          WQML(@"BACKUP_ERROR_VERIFY_PART", @"无法验证 %@"), part];
                    break;
                }
                sourceStates[part] = sourceState;

                NSString *destination = [staging stringByAppendingPathComponent:part];
                if (!wq_copy_contents(source, destination, &failure)) {
                    failure = failure ?: [NSString stringWithFormat:
                                          WQML(@"BACKUP_ERROR_COPY_PART", @"复制 %@ 失败"), part];
                    break;
                }

                // The identity comparison below proves the source did not change
                // while it was copied, so the pre-copy shape remains the shape to
                // compare against the destination. Doing the shape and byte count
                // in the destination walk removes two more full-tree passes.
                BOOL sourceAfterExists = NO;
                NSString *sourceAfter = WQAppsSupportTreeSignature(source, YES, &sourceAfterExists, &failure);
                BOOL destinationExists = NO;
                NSString *destinationShape = nil;
                unsigned long long destinationBytes = 0;
                BOOL destinationDigestsOK = WQAppsSupportTreeDigests(destination, &destinationExists, NULL,
                                                                     &destinationShape, &destinationBytes,
                                                                     &failure);
                if (!destinationDigestsOK || !sourceAfter || !sourceAfterExists ||
                    !destinationShape || !destinationExists ||
                    ![sourceState isEqualToString:sourceAfter] ||
                    ![sourceShape isEqualToString:destinationShape]) {
                    failure = failure ?: [NSString stringWithFormat:
                                          WQML(@"BACKUP_ERROR_PART_CHANGED",
                                               @"%@ 在复制过程中发生变化或复制不完整"), part];
                    break;
                }
                totalBytes += destinationBytes;

                BOOL stagedExists = NO;
                report([NSString stringWithFormat:
                        WQML(@"BACKUP_PROGRESS_VERIFY_PART", @"正在校验 %@…"), part]);
                NSString *contentHash = WQAppsSupportTreeContentSignature(destination, &stagedExists, &failure);
                if (!contentHash || !stagedExists) {
                    failure = failure ?: [NSString stringWithFormat:
                                          WQML(@"BACKUP_ERROR_HASH_PART", @"无法校验 %@"), part];
                    break;
                }
                hashes[part] = contentHash;
                [parts addObject:part];
            }
        }

        if (!failure) {
            for (NSString *part in parts) {
                NSString *source = [app.containerPath stringByAppendingPathComponent:part];
                BOOL exists = NO;
                NSString *current = WQAppsSupportTreeSignature(source, YES, &exists, &failure);
                if (!current || !exists || ![current isEqualToString:sourceStates[part]]) {
                    failure = failure ?: WQML(@"BACKUP_ERROR_SOURCE_CHANGED",
                                              @"App 数据在备份过程中发生变化，未生成完整备份");
                    break;
                }
            }
        }

        NSString *systemVersion = NSProcessInfo.processInfo.operatingSystemVersionString ?: @"unknown";
        NSDictionary *manifest = @{
            @"Complete": @YES,
            @"Format": @2,
            @"BundleID": app.bundleIdentifier,
            @"DisplayName": app.displayName ?: app.bundleIdentifier,
            @"Scope": descriptor.title,
            @"ScopeCode": scope == WQMBackupScopeFull ? @"full" : @"quick",
            @"Reason": reason ?: @"",
            @"Created": created,
            @"Parts": parts,
            @"PartHashes": hashes,
            @"TotalBytes": @(totalBytes),
            @"SystemVersion": systemVersion,
            @"SourceDevice": @(app.containerDevice),
            @"SourceInode": @(app.containerInode),
        };
        NSString *manifestPath = [staging stringByAppendingPathComponent:kWQMBackupManifestName];
        if (!failure && ![manifest writeToFile:manifestPath atomically:YES]) {
            failure = WQML(@"BACKUP_ERROR_WRITE_MANIFEST", @"无法写入备份清单");
        }

        WQMBackupRecord *record = nil;
        NSString *finalPath = nil;
        if (!failure) {
            finalPath = [root stringByAppendingPathComponent:baseName];
            NSUInteger sequence = 2;
            while ([fm fileExistsAtPath:finalPath]) {
                finalPath = [root stringByAppendingPathComponent:
                             [NSString stringWithFormat:@"%@-%lu", baseName, (unsigned long)sequence++]];
            }
            if (rename(staging.fileSystemRepresentation, finalPath.fileSystemRepresentation) != 0) {
                failure = [NSString stringWithFormat:
                           WQML(@"BACKUP_ERROR_PUBLISH", @"无法发布备份（errno %d）"), errno];
            } else {
                NSString *validationError = nil;
                record = [WQMBackupRecord recordAtPath:finalPath error:&validationError];
                if (!record) failure = validationError ?: WQML(@"BACKUP_ERROR_VALIDATION", @"备份校验失败");
            }
        }

        if (failure) {
            if ([fm fileExistsAtPath:staging]) [fm removeItemAtPath:staging error:nil];
            wq_log(@"backup %@: FAILED (%@)", app.bundleIdentifier, failure);
            finish(nil, [NSError errorWithDomain:@"WQMBackupService" code:10
                                        userInfo:@{NSLocalizedDescriptionKey: failure}]);
            return;
        }

        wq_log(@"backup %@: OK (%@)", app.bundleIdentifier, finalPath);
        [[NSNotificationCenter defaultCenter] postNotificationName:WQMBackupStoreDidChangeNotification object:nil];
        finish(record, nil);
    });
}

@end

