#import "WQMHousekeeping.h"
#import "WQMSharedInbox.h"

@implementation WQMHousekeeping

+ (void)runAtLaunch
{
    NSString *documents = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)
                           firstObject];
    if (!documents.length) return;
    NSString *backupRoot = [documents stringByAppendingPathComponent:@"AppBackups"];
    NSString *recoveryRoot = [documents stringByAppendingPathComponent:@"RestoreRecovery"];
    NSString *temporaryRoot = NSTemporaryDirectory();
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [self runWithBackupRoot:backupRoot
                   recoveryRoot:recoveryRoot
                  temporaryRoot:temporaryRoot
                         maxAge:3600.0];
    });
}

+ (void)runWithBackupRoot:(NSString *)backupRoot
             recoveryRoot:(NSString *)recoveryRoot
            temporaryRoot:(NSString *)temporaryRoot
                   maxAge:(NSTimeInterval)maxAge
{
    if (maxAge < 0) maxAge = 0;
    // Interrupted backups keep their staging tree next to the published ones.
    [self sweepDirectory:backupRoot prefix:@".incomplete-" suffix:nil maxAge:maxAge];
    // Interrupted journal writes and finished-but-unremoved journals.
    [self sweepDirectory:recoveryRoot prefix:@"." suffix:@".journal" maxAge:maxAge];
    [self sweepDirectory:recoveryRoot prefix:nil suffix:@".done" maxAge:maxAge];
    // Import/export work directories in the app's temporary directory.
    [self sweepDirectory:temporaryRoot prefix:@"WQMImport-" suffix:nil maxAge:maxAge];
    [self sweepDirectory:temporaryRoot prefix:@"WQMExport-" suffix:nil maxAge:maxAge];
    [self sweepDirectory:temporaryRoot prefix:@"WQMSharedImport-" suffix:nil maxAge:maxAge];
    [WQMSharedInbox purgeStaleItemsOlderThan:maxAge freedBytes:NULL];
}

+ (void)sweepDirectory:(NSString *)directory
                prefix:(NSString *)prefix
                suffix:(NSString *)suffix
                maxAge:(NSTimeInterval)maxAge
{
    if (!directory.length || (!prefix.length && !suffix.length)) return;
    NSFileManager *fm = NSFileManager.defaultManager;
    NSArray<NSString *> *names = [fm contentsOfDirectoryAtPath:directory error:nil] ?: @[];
    for (NSString *name in names) {
        if (prefix.length && ![name hasPrefix:prefix]) continue;
        if (suffix.length && ![name hasSuffix:suffix]) continue;
        NSString *path = [directory stringByAppendingPathComponent:name];
        NSDictionary<NSFileAttributeKey, id> *attributes = [fm attributesOfItemAtPath:path error:nil];
        NSDate *modified = attributes[NSFileModificationDate];
        if (![modified isKindOfClass:NSDate.class]) continue;
        if (-modified.timeIntervalSinceNow < maxAge) continue;
        [fm removeItemAtPath:path error:nil];
    }
}

@end
