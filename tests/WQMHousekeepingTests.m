#import <Foundation/Foundation.h>
#import "WQMHousekeeping.h"

static NSUInteger gFailures = 0;

static void WQMAssert(BOOL condition, NSString *message)
{
    if (condition) return;
    gFailures++;
    fprintf(stderr, "FAIL: %s\n", message.UTF8String);
}

static NSString *WQMMakeDirectory(NSString *parent, NSString *name, NSTimeInterval age)
{
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *path = [parent stringByAppendingPathComponent:name];
    [fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    if (age > 0) {
        [fm setAttributes:@{NSFileModificationDate: [NSDate dateWithTimeIntervalSinceNow:-age]}
              ofItemAtPath:path error:nil];
    }
    return path;
}

int main(void)
{
    @autoreleasepool {
        NSFileManager *fm = NSFileManager.defaultManager;
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        NSString *backupRoot = [root stringByAppendingPathComponent:@"AppBackups"];
        NSString *recoveryRoot = [root stringByAppendingPathComponent:@"RestoreRecovery"];
        NSString *tempRoot = [root stringByAppendingPathComponent:@"tmp"];
        [fm createDirectoryAtPath:backupRoot withIntermediateDirectories:YES attributes:nil error:nil];
        [fm createDirectoryAtPath:recoveryRoot withIntermediateDirectories:YES attributes:nil error:nil];
        [fm createDirectoryAtPath:tempRoot withIntermediateDirectories:YES attributes:nil error:nil];

        NSString *oldStaging = WQMMakeDirectory(backupRoot, @".incomplete-old", 7200);
        NSString *freshStaging = WQMMakeDirectory(backupRoot, @".incomplete-new", 0);
        NSString *keptBackup = WQMMakeDirectory(backupRoot, @"com.example.app", 7200);
        NSString *oldDone = [recoveryRoot stringByAppendingPathComponent:@"old.plist.done"];
        NSString *freshDone = [recoveryRoot stringByAppendingPathComponent:@"new.plist.done"];
        NSString *activeJournal = [recoveryRoot stringByAppendingPathComponent:@"active.plist"];
        for (NSString *path in @[oldDone, freshDone, activeJournal]) {
            [@"x" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
        [fm setAttributes:@{NSFileModificationDate: [NSDate dateWithTimeIntervalSinceNow:-7200]}
              ofItemAtPath:oldDone error:nil];
        NSString *oldJournalTemp = [recoveryRoot stringByAppendingPathComponent:@".abc.journal"];
        [@"x" writeToFile:oldJournalTemp atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [fm setAttributes:@{NSFileModificationDate: [NSDate dateWithTimeIntervalSinceNow:-7200]}
              ofItemAtPath:oldJournalTemp error:nil];
        NSString *oldImport = WQMMakeDirectory(tempRoot, @"WQMImport-old", 7200);
        NSString *freshImport = WQMMakeDirectory(tempRoot, @"WQMImport-new", 0);
        NSString *oldExport = WQMMakeDirectory(tempRoot, @"WQMExport-old", 7200);
        NSString *unrelated = WQMMakeDirectory(tempRoot, @"unrelated", 7200);

        [WQMHousekeeping runWithBackupRoot:backupRoot
                             recoveryRoot:recoveryRoot
                            temporaryRoot:tempRoot
                                   maxAge:3600];

        WQMAssert(![fm fileExistsAtPath:oldStaging], @"old backup staging should be removed");
        WQMAssert([fm fileExistsAtPath:freshStaging], @"fresh backup staging should be kept");
        WQMAssert([fm fileExistsAtPath:keptBackup], @"published backups must be kept");
        WQMAssert(![fm fileExistsAtPath:oldDone], @"finished journals should be removed");
        WQMAssert([fm fileExistsAtPath:freshDone], @"fresh finished journals should be kept");
        WQMAssert([fm fileExistsAtPath:activeJournal], @"active journals must be kept");
        WQMAssert(![fm fileExistsAtPath:oldJournalTemp], @"stale journal temp should be removed");
        WQMAssert(![fm fileExistsAtPath:oldImport], @"old import dir should be removed");
        WQMAssert([fm fileExistsAtPath:freshImport], @"fresh import dir should be kept");
        WQMAssert(![fm fileExistsAtPath:oldExport], @"old export dir should be removed");
        WQMAssert([fm fileExistsAtPath:unrelated], @"unrelated temp content must be kept");

        [fm removeItemAtPath:root error:nil];

        if (gFailures == 0) fprintf(stdout, "WQMHousekeepingTests: all checks passed\n");
        return gFailures == 0 ? 0 : 1;
    }
}
