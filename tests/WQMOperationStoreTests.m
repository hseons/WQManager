#import <Foundation/Foundation.h>
#import "WQMOperationStore.h"

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
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        [WQMOperationStore setStorageRootForTesting:root];
        [WQMOperationStore clear];

        WQMOperationRecord *record = [WQMOperationStore beginOperation:WQMOperationKindBackup
                                                               appName:@"微信"
                                                      bundleIdentifier:@"com.tencent.xin"];
        WQMAssert(record != nil, @"begin should return a record");
        WQMAssert([WQMOperationStore allOperations].count == 1, @"running record should persist");
        record.status = WQMOperationStatusSuccess;
        record.finishedAt = NSDate.date;
        record.bytes = 1024;
        record.backupPath = @"/tmp/backup";
        [WQMOperationStore updateRecord:record];

        [WQMOperationStore setStorageRootForTesting:root];
        NSArray<WQMOperationRecord *> *loaded = [WQMOperationStore allOperations];
        WQMAssert(loaded.count == 1, @"record should reload from disk");
        WQMAssert(loaded.firstObject.status == WQMOperationStatusSuccess, @"status should round-trip");
        WQMAssert(loaded.firstObject.bytes == 1024, @"byte count should round-trip");
        WQMAssert([loaded.firstObject.bundleIdentifier isEqualToString:@"com.tencent.xin"],
                  @"bundle id should round-trip");

        [WQMOperationStore clear];
        WQMAssert([WQMOperationStore allOperations].count == 0, @"clear should remove records");
        [NSFileManager.defaultManager removeItemAtPath:root error:nil];
    }

    if (gFailures) {
        fprintf(stderr, "%lu operation test(s) failed\n", (unsigned long)gFailures);
        return 1;
    }
    printf("WQM operation store tests passed\n");
    return 0;
}

