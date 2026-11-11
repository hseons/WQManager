#import <Foundation/Foundation.h>
#import "WQMBackupArchiveService.h"
#import "WQMBackupStore.h"
#import "WQMOperationStore.h"
#import "WQAppsSupport.h"

static NSUInteger gFailures = 0;

static void WQMAssert(BOOL condition, NSString *message)
{
    if (condition) return;
    gFailures++;
    fprintf(stderr, "FAIL: %s\n", message.UTF8String);
}

static BOOL WQMWaitUntil(BOOL (^condition)(void))
{
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
    while (!condition() && [deadline timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }
    return condition();
}

int main(void)
{
    @autoreleasepool {
        NSString *base = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        NSString *backupRoot = [base stringByAppendingPathComponent:@"AppBackups"];
        NSString *operationRoot = [base stringByAppendingPathComponent:@"Operations"];
        [WQMBackupStore setBackupRootForTesting:backupRoot];
        [WQMOperationStore setStorageRootForTesting:operationRoot];
        [WQMOperationStore clear];

        NSString *backupPath = [backupRoot stringByAppendingPathComponent:
                                @"com.example.archive/20261111-120000-000"];
        NSString *documents = [backupPath stringByAppendingPathComponent:@"Documents"];
        [NSFileManager.defaultManager createDirectoryAtPath:documents
                                withIntermediateDirectories:YES
                                                 attributes:nil
                                                      error:nil];
        [@"archive fixture" writeToFile:[documents stringByAppendingPathComponent:@"note.txt"]
                              atomically:YES
                                encoding:NSUTF8StringEncoding
                                   error:nil];
        BOOL exists = NO;
        NSString *hash = WQAppsSupportTreeContentSignature(documents, &exists, nil);
        NSDictionary *manifest = @{
            @"Complete": @YES,
            @"Format": @2,
            @"BundleID": @"com.example.archive",
            @"DisplayName": @"Archive Test",
            @"Scope": @"快速备份",
            @"ScopeCode": @"quick",
            @"Reason": @"test",
            @"Created": NSDate.date,
            @"Parts": @[@"Documents"],
            @"PartHashes": @{@"Documents": hash ?: @""},
            @"TotalBytes": @15,
            @"SystemVersion": @"26.0",
        };
        [manifest writeToFile:[backupPath stringByAppendingPathComponent:@"manifest.plist"] atomically:YES];
        WQMBackupRecord *source = [WQMBackupRecord recordAtPath:backupPath error:nil];
        WQMAssert(source != nil, @"source fixture should be valid");

        WQMBackupArchiveService *service = [WQMBackupArchiveService new];
        __block NSURL *exportURL = nil;
        __block NSError *exportError = nil;
        [service prepareExportForBackup:source completion:^(NSURL *url, NSError *error) {
            exportURL = url;
            exportError = error;
        }];
        WQMAssert(WQMWaitUntil(^BOOL { return exportURL != nil || exportError != nil; }),
                  @"export should complete");
        WQMAssert(exportURL != nil, exportError.localizedDescription ?: @"export should produce a package");

        __block WQMBackupRecord *imported = nil;
        __block NSError *importError = nil;
        [service importBackupAtURL:exportURL completion:^(WQMBackupRecord *backup, NSError *error) {
            imported = backup;
            importError = error;
        }];
        WQMAssert(WQMWaitUntil(^BOOL { return imported != nil || importError != nil; }),
                  @"import should complete");
        WQMAssert(imported != nil, importError.localizedDescription ?: @"import should create a backup");
        WQMAssert([imported.bundleIdentifier isEqualToString:@"com.example.archive"],
                  @"import should preserve the bundle id");

        __block BOOL deleted = NO;
        __block NSError *deleteError = nil;
        [service deleteBackup:imported completion:^(BOOL success, NSError *error) {
            deleted = success;
            deleteError = error;
        }];
        WQMAssert(WQMWaitUntil(^BOOL { return deleted || deleteError != nil; }),
                  @"delete should complete");
        WQMAssert(deleted, deleteError.localizedDescription ?: @"delete should remove imported backup");
        WQMAssert(![NSFileManager.defaultManager fileExistsAtPath:imported.path],
                  @"deleted backup path should be gone");

        if (exportURL) [NSFileManager.defaultManager removeItemAtURL:exportURL.URLByDeletingLastPathComponent error:nil];
        [NSFileManager.defaultManager removeItemAtPath:base error:nil];
        [WQMBackupStore setBackupRootForTesting:nil];
        [WQMOperationStore setStorageRootForTesting:nil];
    }

    if (gFailures) {
        fprintf(stderr, "%lu archive test(s) failed\n", (unsigned long)gFailures);
        return 1;
    }
    printf("WQM backup archive tests passed\n");
    return 0;
}

