#import <Foundation/Foundation.h>
#import "WQMBackupStore.h"

static NSUInteger gFailures = 0;

static void WQMAssert(BOOL condition, NSString *message)
{
    if (condition) return;
    gFailures++;
    fprintf(stderr, "FAIL: %s\n", message.UTF8String);
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
    }

    if (gFailures) {
        fprintf(stderr, "%lu backup test(s) failed\n", (unsigned long)gFailures);
        return 1;
    }
    printf("WQM backup store tests passed\n");
    return 0;
}
