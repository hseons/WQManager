#import <Foundation/Foundation.h>
#import "WQMBackupStore.h"

static NSUInteger gFailures = 0;

static void WQMAssert(BOOL condition, NSString *message)
{
    if (condition) return;
    gFailures++;
    fprintf(stderr, "FAIL: %s\n", message.UTF8String);
}

static NSString *WQMWriteBackup(NSString *root, NSString *bundleID, NSDate *created,
                                unsigned long long totalBytes, NSString *directory)
{
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *path = [[root stringByAppendingPathComponent:bundleID]
                      stringByAppendingPathComponent:directory];
    NSString *documents = [path stringByAppendingPathComponent:@"Documents"];
    [fm createDirectoryAtPath:documents withIntermediateDirectories:YES attributes:nil error:nil];
    [@"x" writeToFile:[documents stringByAppendingPathComponent:@"note.txt"]
           atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSDictionary *manifest = @{
        @"Complete": @YES,
        @"Format": @2,
        @"BundleID": bundleID,
        @"DisplayName": [bundleID componentsSeparatedByString:@"."].firstObject,
        @"Scope": @"快速备份",
        @"ScopeCode": @"quick",
        @"Reason": @"test",
        @"Created": created,
        @"Parts": @[@"Documents"],
        @"PartHashes": @{@"Documents": @"abc123"},
        @"TotalBytes": @(totalBytes),
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
        NSString *backup = [root stringByAppendingPathComponent:@"com.example.app/20261110-120000-000"];
        NSString *documents = [backup stringByAppendingPathComponent:@"Documents"];
        WQMAssert([fm createDirectoryAtPath:documents withIntermediateDirectories:YES attributes:nil error:nil],
                  @"fixture backup directory should be created");
        NSString *payload = [documents stringByAppendingPathComponent:@"note.txt"];
        [@"fixture" writeToFile:payload atomically:YES encoding:NSUTF8StringEncoding error:nil];

        NSDictionary *manifest = @{
            @"Complete": @YES,
            @"Format": @2,
            @"BundleID": @"com.example.app",
            @"DisplayName": @"Example",
            @"Scope": @"快速备份",
            @"ScopeCode": @"quick",
            @"Reason": @"test",
            @"Created": NSDate.date,
            @"Parts": @[@"Documents"],
            @"PartHashes": @{@"Documents": @"abc123"},
            @"TotalBytes": @7,
            @"SystemVersion": @"26.0",
        };
        [manifest writeToFile:[backup stringByAppendingPathComponent:@"manifest.plist"] atomically:YES];

        NSString *error = nil;
        WQMBackupRecord *record = [WQMBackupRecord recordAtPath:backup error:&error];
        WQMAssert(record != nil, error ?: @"valid fixture backup should load");
        WQMAssert([record.bundleIdentifier isEqualToString:@"com.example.app"], @"bundle id should round-trip");
        WQMAssert([record.parts isEqualToArray:@[@"Documents"]], @"parts should round-trip");
        WQMAssert([record.scopeCode isEqualToString:@"quick"], @"scope code should round-trip");
        WQMAssert(record.totalBytes == 7, @"backup size should come from the manifest");
        WQMAssert(record.manifestFingerprint.length > 0, @"manifest fingerprint should be captured");
        WQMAssert([record.manifestFingerprint isEqualToString:
                   [WQMBackupRecord recordAtPath:backup error:nil].manifestFingerprint],
                  @"manifest fingerprint should be stable across reloads");

        NSString *unexpected = [backup stringByAppendingPathComponent:@"Unexpected"];
        [fm createDirectoryAtPath:unexpected withIntermediateDirectories:NO attributes:nil error:nil];
        WQMAssert([WQMBackupRecord recordAtPath:backup error:&error] == nil,
                  @"unexpected contents must invalidate a backup");
        [fm removeItemAtPath:root error:nil];

        // Grouping keeps backups of one app together, newest first.
        NSString *groupRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        [WQMBackupStore setBackupRootForTesting:groupRoot];
        NSDate *now = [NSDate dateWithTimeIntervalSince1970:1763000000];
        NSString *older = WQMWriteBackup(groupRoot, @"com.example.app",
                                         [now dateByAddingTimeInterval:-3600], 10, @"a");
        NSString *newer = WQMWriteBackup(groupRoot, @"com.example.app", now, 20, @"b");
        NSString *other = WQMWriteBackup(groupRoot, @"com.other.app",
                                         [now dateByAddingTimeInterval:-60], 5, @"c");
        (void)older; (void)newer; (void)other;

        NSArray<WQMBackupGroup *> *groups = [WQMBackupStore groupsForRecords:[WQMBackupStore allBackups]];
        WQMAssert(groups.count == 2, @"two apps should produce two groups");
        if (groups.count == 2) {
            WQMAssert([groups[0].bundleIdentifier isEqualToString:@"com.example.app"],
                      @"the group with the newest backup comes first");
            WQMAssert(groups[0].backups.count == 2, @"app group should contain both backups");
            WQMAssert(groups[0].totalBytes == 30, @"group size should add up its backups");
            WQMAssert([groups[0].backups[0].createdAt compare:groups[0].backups[1].createdAt] == NSOrderedDescending,
                      @"backups inside a group are newest first");
            WQMAssert([groups[1].bundleIdentifier isEqualToString:@"com.other.app"],
                      @"the remaining app keeps its own group");
        }
        WQMAssert([WQMBackupStore groupsForRecords:@[]].count == 0, @"no records means no groups");
        [WQMBackupStore setBackupRootForTesting:nil];
        [fm removeItemAtPath:groupRoot error:nil];
    }

    if (gFailures) {
        fprintf(stderr, "%lu backup test(s) failed\n", (unsigned long)gFailures);
        return 1;
    }
    printf("WQM backup store tests passed\n");
    return 0;
}
