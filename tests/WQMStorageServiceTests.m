#import <Foundation/Foundation.h>
#import "WQMStorageService.h"

static NSUInteger gFailures = 0;

static void WQMAssert(BOOL condition, NSString *message)
{
    if (condition) return;
    gFailures++;
    fprintf(stderr, "FAIL: %s\n", message.UTF8String);
}

static NSString *WQMMakeBackup(NSString *root, NSString *bundle, NSString *name,
                               NSString *reason, NSDate *created, NSUInteger bytes)
{
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *path = [[root stringByAppendingPathComponent:bundle]
                      stringByAppendingPathComponent:name];
    NSString *documents = [path stringByAppendingPathComponent:@"Documents"];
    [fm createDirectoryAtPath:documents withIntermediateDirectories:YES attributes:nil error:nil];
    NSMutableData *payload = [NSMutableData dataWithLength:bytes];
    [payload writeToFile:[documents stringByAppendingPathComponent:@"payload.bin"] atomically:YES];
    NSDictionary *manifest = @{
        @"Complete": @YES,
        @"Format": @2,
        @"BundleID": bundle,
        @"DisplayName": bundle,
        @"Scope": @"快速备份",
        @"ScopeCode": @"quick",
        @"Reason": reason,
        @"Created": created,
        @"Parts": @[@"Documents"],
        @"PartHashes": @{@"Documents": @"abc123"},
        @"TotalBytes": @(bytes),
        @"SystemVersion": @"26.0",
    };
    [manifest writeToFile:[path stringByAppendingPathComponent:@"manifest.plist"] atomically:YES];
    return path;
}

int main(void)
{
    @autoreleasepool {
        NSFileManager *fm = NSFileManager.defaultManager;
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        NSString *backupRoot = [root stringByAppendingPathComponent:@"AppBackups"];
        NSString *tempRoot = [root stringByAppendingPathComponent:@"tmp"];
        [fm createDirectoryAtPath:backupRoot withIntermediateDirectories:YES attributes:nil error:nil];
        [fm createDirectoryAtPath:tempRoot withIntermediateDirectories:YES attributes:nil error:nil];

        NSDate *older = [NSDate dateWithTimeIntervalSince1970:1000];
        NSDate *newer = [NSDate dateWithTimeIntervalSince1970:2000];
        NSString *safetyOld = WQMMakeBackup(backupRoot, @"com.example.app", @"20260101-000000",
                                            @"恢复前自动安全备份", older, 4096);
        NSString *safetyNew = WQMMakeBackup(backupRoot, @"com.example.app", @"20260102-000000",
                                            @"Automatic safety backup before restore", newer, 4096);
        NSString *normal = WQMMakeBackup(backupRoot, @"com.example.app", @"20260103-000000",
                                         @"manual", newer, 2048);
        NSString *invalid = [[backupRoot stringByAppendingPathComponent:@"com.example.app"]
                             stringByAppendingPathComponent:@"20251231-000000"];
        NSString *invalidDocuments = [invalid stringByAppendingPathComponent:@"Documents"];
        [fm createDirectoryAtPath:invalidDocuments withIntermediateDirectories:YES attributes:nil error:nil];
        [[NSMutableData dataWithLength:1024] writeToFile:[invalidDocuments stringByAppendingPathComponent:@"leftover.bin"]
                                                atomically:YES];
        NSString *incomplete = [[backupRoot stringByAppendingPathComponent:@"com.example.app"]
                                stringByAppendingPathComponent:@".incomplete-test"];
        [fm createDirectoryAtPath:[incomplete stringByAppendingPathComponent:@"Documents"]
      withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *tempDir = [tempRoot stringByAppendingPathComponent:@"WQMExport-test"];
        [fm createDirectoryAtPath:tempDir withIntermediateDirectories:YES attributes:nil error:nil];
        [@"temp" writeToFile:[tempDir stringByAppendingPathComponent:@"part.bin"]
                  atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSString *sharedImport = [tempRoot stringByAppendingPathComponent:@"WQMSharedImport-test.wqbackup"];
        [fm createDirectoryAtPath:[sharedImport stringByAppendingPathComponent:@"Payload"]
      withIntermediateDirectories:YES attributes:nil error:nil];
        [[NSMutableData dataWithLength:512] writeToFile:[sharedImport stringByAppendingPathComponent:@"Payload/p.bin"]
                                               atomically:YES];
        [fm setAttributes:@{NSFileModificationDate: [NSDate dateWithTimeIntervalSinceNow:-3600]}
              ofItemAtPath:sharedImport error:nil];

        [WQMStorageService setRootsForTesting:backupRoot temporaryRoot:tempRoot];

        WQMStorageBreakdown *breakdown = [WQMStorageService breakdown];
        WQMAssert(breakdown.backupCount == 3, @"three valid backups should be counted");
        WQMAssert(breakdown.safetyCount == 2, @"two safety backups should be counted");
        WQMAssert(breakdown.invalidCount == 1, @"one invalid backup should be counted");
        WQMAssert(breakdown.incompleteCount == 1, @"one incomplete directory should be counted");
        WQMAssert(breakdown.temporaryCount == 2, @"temp and shared import should be counted");
        WQMAssert(breakdown.backupBytes >= 10240, @"backup bytes should include payloads");
        WQMAssert(breakdown.safetyBytes >= 8192, @"safety bytes should include both safety backups");

        unsigned long long freed = 0;
        NSError *error = nil;
        BOOL cleaned = [WQMStorageService cleanupWithOptions:WQMStorageCleanupInvalid
                                                    excluding:[NSSet set]
                                                   freedBytes:&freed
                                                        error:&error];
        WQMAssert(cleaned, error.localizedDescription ?: @"invalid cleanup should succeed");
        WQMAssert(freed > 0, @"invalid cleanup should report freed bytes");
        WQMAssert(![fm fileExistsAtPath:invalid], @"invalid backup should be deleted");
        WQMAssert([fm fileExistsAtPath:safetyOld], @"valid backup should survive invalid cleanup");

        NSString *invalidProtected = [[backupRoot stringByAppendingPathComponent:@"com.example.app"]
                                      stringByAppendingPathComponent:@"20251230-000000"];
        [fm createDirectoryAtPath:[invalidProtected stringByAppendingPathComponent:@"Documents"]
      withIntermediateDirectories:YES attributes:nil error:nil];
        [WQMStorageService cleanupWithOptions:WQMStorageCleanupInvalid
                                    excluding:[NSSet setWithObject:invalidProtected]
                                   freedBytes:NULL error:NULL];
        WQMAssert([fm fileExistsAtPath:invalidProtected],
                  @"protected invalid backup should not be deleted");

        (void)[WQMStorageService cleanupWithOptions:WQMStorageCleanupIncomplete
                                          excluding:[NSSet set]
                                         freedBytes:NULL error:NULL];
        WQMAssert(![fm fileExistsAtPath:incomplete], @"incomplete directory should be deleted");

        unsigned long long deleted = 0;
        NSUInteger removed = [WQMStorageService pruneSafetyBackupsKeeping:1
                                                                excluding:[NSSet set]
                                                              deletedBytes:&deleted];
        WQMAssert(removed == 1, @"prune should remove exactly one safety backup");
        WQMAssert(deleted > 0, @"prune should report deleted bytes");
        WQMAssert(![fm fileExistsAtPath:safetyOld], @"older safety backup should be removed");
        WQMAssert([fm fileExistsAtPath:safetyNew], @"newer safety backup should be kept");
        WQMAssert([fm fileExistsAtPath:normal], @"regular backup should never be pruned");

        NSString *safetyProtected = WQMMakeBackup(backupRoot, @"com.example.app",
                                                   @"20260104-000000", @"恢复前自动安全备份",
                                                   [NSDate dateWithTimeIntervalSince1970:500], 2048);
        removed = [WQMStorageService pruneSafetyBackupsKeeping:1
                                                      excluding:[NSSet setWithObject:safetyProtected]
                                                    deletedBytes:NULL];
        WQMAssert(removed == 0, @"protected safety backup should not be removed");
        WQMAssert([fm fileExistsAtPath:safetyProtected], @"protected safety backup should survive");

        cleaned = [WQMStorageService cleanupWithOptions:WQMStorageCleanupTemporary
                                               excluding:[NSSet set]
                                              freedBytes:NULL error:NULL];
        WQMAssert(cleaned, @"temporary cleanup should succeed");
        WQMAssert(![fm fileExistsAtPath:tempDir], @"temp directory should be deleted");
        WQMAssert(![fm fileExistsAtPath:sharedImport], @"stale shared import should be deleted");

        [WQMStorageService setRootsForTesting:nil temporaryRoot:nil];
        [fm removeItemAtPath:root error:nil];
        if (gFailures == 0) fprintf(stdout, "WQMStorageServiceTests passed\n");
        return gFailures == 0 ? 0 : 1;
    }
}
