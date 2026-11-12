#import "WQMSharedInbox.h"
#import "WQAppsSupport.h"

NSString *const WQMSharedAppGroupIdentifier = @"group.mumu.wqmanager";
static NSString *const kWQMInboxDirectory = @"Library/WQMImportInbox";
static NSString *const kWQMBackupExtension = @"wqbackup";

@implementation WQMSharedInbox

+ (NSURL *)inboxURLCreatingIfNeeded:(BOOL)create error:(NSError **)error
{
    NSURL *groupURL = [NSFileManager.defaultManager
        containerURLForSecurityApplicationGroupIdentifier:WQMSharedAppGroupIdentifier];
    if (!groupURL) {
        if (error) {
            *error = [NSError errorWithDomain:@"WQMSharedInbox" code:1
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"WQManager App Group 不可用"}];
        }
        return nil;
    }
    NSURL *inbox = [groupURL URLByAppendingPathComponent:kWQMInboxDirectory isDirectory:YES];
    if (create && ![NSFileManager.defaultManager createDirectoryAtURL:inbox
                                          withIntermediateDirectories:YES
                                                           attributes:nil
                                                                error:error]) {
        return nil;
    }
    return inbox;
}

+ (NSArray<NSURL *> *)pendingURLs
{
    NSURL *inbox = [self inboxURLCreatingIfNeeded:YES error:nil];
    if (!inbox) return @[];
    NSArray<NSURL *> *items = [NSFileManager.defaultManager
        contentsOfDirectoryAtURL:inbox
      includingPropertiesForKeys:@[NSURLIsDirectoryKey, NSURLContentModificationDateKey]
                         options:NSDirectoryEnumerationSkipsHiddenFiles
                           error:nil] ?: @[];
    NSPredicate *backupPredicate = [NSPredicate predicateWithBlock:
        ^BOOL(NSURL *url, NSDictionary *__unused bindings) {
            return [url.pathExtension caseInsensitiveCompare:kWQMBackupExtension] == NSOrderedSame;
        }];
    return [[items filteredArrayUsingPredicate:backupPredicate]
            sortedArrayUsingComparator:^NSComparisonResult(NSURL *left, NSURL *right) {
                NSDate *leftDate = nil, *rightDate = nil;
                [left getResourceValue:&leftDate forKey:NSURLContentModificationDateKey error:nil];
                [right getResourceValue:&rightDate forKey:NSURLContentModificationDateKey error:nil];
                return [(rightDate ?: NSDate.distantPast) compare:(leftDate ?: NSDate.distantPast)];
            }];
}

+ (BOOL)enqueueURL:(NSURL *)sourceURL error:(NSError **)error
{
    if (!sourceURL.isFileURL) {
        if (error) {
            *error = [NSError errorWithDomain:@"WQMSharedInbox" code:2
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"分享项目不是文件 URL"}];
        }
        return NO;
    }
    NSURL *inbox = [self inboxURLCreatingIfNeeded:YES error:error];
    if (!inbox) return NO;

    NSString *identifier = NSUUID.UUID.UUIDString;
    NSURL *temporary = [inbox URLByAppendingPathComponent:
                        [NSString stringWithFormat:@".%@.incoming", identifier]
                                                   isDirectory:YES];
    NSURL *destination = [inbox URLByAppendingPathComponent:
                          [identifier stringByAppendingPathExtension:kWQMBackupExtension]
                                                     isDirectory:YES];
    BOOL scoped = [sourceURL startAccessingSecurityScopedResource];
    __block BOOL copied = NO;
    __block NSError *copyError = nil;
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    NSError *coordinationError = nil;
    [coordinator coordinateReadingItemAtURL:sourceURL options:0 error:&coordinationError
                                byAccessor:^(NSURL *readingURL) {
        copied = [NSFileManager.defaultManager copyItemAtURL:readingURL
                                                       toURL:temporary
                                                       error:&copyError];
    }];
    if (scoped) [sourceURL stopAccessingSecurityScopedResource];
    if (!copied) {
        [NSFileManager.defaultManager removeItemAtURL:temporary error:nil];
        if (error) *error = copyError ?: coordinationError;
        return NO;
    }
    if (![NSFileManager.defaultManager moveItemAtURL:temporary toURL:destination error:error]) {
        [NSFileManager.defaultManager removeItemAtURL:temporary error:nil];
        return NO;
    }
    return YES;
}

+ (NSURL *)takeNextPendingURL:(NSError **)error
{
    NSURL *source = self.pendingURLs.firstObject;
    if (!source) return nil;
    NSURL *temporaryRoot = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
    NSURL *destination = [temporaryRoot URLByAppendingPathComponent:
                          [NSString stringWithFormat:@"WQMSharedImport-%@.%@",
                           NSUUID.UUID.UUIDString, kWQMBackupExtension]
                                                        isDirectory:YES];
    if ([NSFileManager.defaultManager moveItemAtURL:source toURL:destination error:error]) {
        return destination;
    }
    NSError *moveError = error ? *error : nil;
    NSError *copyError = nil;
    if (![NSFileManager.defaultManager copyItemAtURL:source toURL:destination error:&copyError]) {
        if (error) *error = copyError ?: moveError;
        return nil;
    }
    [NSFileManager.defaultManager removeItemAtURL:source error:nil];
    return destination;
}


+ (nullable NSString *)inboxPath
{
    return [self inboxURLCreatingIfNeeded:NO error:nil].path;
}

+ (NSUInteger)purgeStaleItemsOlderThan:(NSTimeInterval)maxAge
                            freedBytes:(unsigned long long *)freedBytes
{
    if (freedBytes) *freedBytes = 0;
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *inbox = [self inboxPath];
    if (!inbox.length) return 0;
    NSArray<NSString *> *names = [fm contentsOfDirectoryAtPath:inbox error:nil] ?: @[];
    NSUInteger removed = 0;
    unsigned long long freed = 0;
    for (NSString *name in names) {
        BOOL isBackup = [name.pathExtension caseInsensitiveCompare:kWQMBackupExtension] == NSOrderedSame;
        BOOL isIncoming = [name hasPrefix:@"."] && [name hasSuffix:@".incoming"];
        if (!isBackup && !isIncoming) continue;
        NSString *path = [inbox stringByAppendingPathComponent:name];
        NSDictionary<NSFileAttributeKey, id> *attributes = [fm attributesOfItemAtPath:path error:nil];
        NSDate *modified = attributes[NSFileModificationDate];
        if (![modified isKindOfClass:NSDate.class]) continue;
        if (maxAge > 0 && -modified.timeIntervalSinceNow < maxAge) continue;
        freed += WQMAppsSupportTreeSize(path);
        if ([fm removeItemAtPath:path error:nil]) removed++;
    }
    if (freedBytes) *freedBytes = freed;
    return removed;
}
@end
