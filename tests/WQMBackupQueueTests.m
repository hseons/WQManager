#import <Foundation/Foundation.h>
#import "WQMBackupQueue.h"
#import "WQMAppModel.h"
static NSUInteger failures;
static void Check(BOOL ok, NSString *message) { if (!ok) { failures++; fprintf(stderr, "FAIL: %s\n", message.UTF8String); } }
static BOOL Wait(BOOL (^condition)(void)) { NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5]; while (!condition() && deadline.timeIntervalSinceNow > 0) [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]]; return condition(); }
int main(void) { @autoreleasepool {
    NSMutableArray *apps = [NSMutableArray new];
    for (NSString *name in @[@"one", @"two", @"three"]) {
        WQMAppModel *app = [[WQMAppModel alloc] initWithBundleIdentifier:[@"com.test." stringByAppendingString:name] displayName:name containerPath:@"/fixture" dataSize:1];
        app.accessAvailable = app.identityKnown = YES; [apps addObject:app];
    }
    __block NSUInteger calls = 0;
    __block void (^complete)(BOOL, NSString *);
    WQMBackupQueue *queue = [[WQMBackupQueue alloc] initWithExecutor:^(WQMAppModel *app, NSInteger scope, void (^progress)(NSString *), void (^completion)(BOOL, NSString *)) { calls++; complete = completion; }];
    Check([queue startApps:apps scope:WQMBackupScopeQuick], @"queue starts");
    Check(calls == 1 && queue.jobs[0].status == WQMBackupJobRunning && queue.jobs[1].status == WQMBackupJobPending, @"only one task starts at a time");
    Check(![queue startApps:apps scope:0], @"overlapping start is rejected");
    complete(NO, @"fixture failure");
    Check(Wait(^BOOL{ return calls == 2; }), @"a failure does not stall following tasks");
    [queue stopRemaining];
    Check(queue.jobs[1].status == WQMBackupJobRunning && queue.jobs[2].status == WQMBackupJobCancelled, @"stop preserves active backup and cancels pending tasks");
    complete(YES, @"done");
    Check(Wait(^BOOL{ return !queue.running; }), @"queue finishes after the active task");
    Check(calls == 2, @"stopped task never executes");
    Check([queue retryFailures] && calls == 3, @"only failed job retries");
    complete(YES, @"retried");
    Check(Wait(^BOOL{ return !queue.running; }), @"retry finishes");
    Check(queue.jobs[0].status == WQMBackupJobSucceeded && queue.jobs[2].status == WQMBackupJobCancelled, @"retry leaves cancelled job untouched");
    Check([queue startApps:@[apps[0], apps[0]] scope:0] && queue.jobs.count == 1, @"duplicate bundle IDs are queued once");
    complete(YES, @"done"); Wait(^BOOL{ return !queue.running; }); complete = nil;
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSString *path = [root stringByAppendingPathComponent:@"queue.plist"];
    WQMBackupQueueExecutor executor = ^(WQMAppModel *app, NSInteger scope, void (^progress)(NSString *), void (^completion)(BOOL, NSString *)) { calls++; complete = completion; };
    WQMBackupQueue *persistent = [[WQMBackupQueue alloc] initWithExecutor:executor storagePath:path];
    [persistent resolveApps:apps];
    Check([persistent startApps:apps scope:WQMBackupScopeFull], @"persistent batch starts");
    NSDictionary *stored = [NSDictionary dictionaryWithContentsOfFile:path];
    Check(stored[@"Jobs"][0][@"Container"] == nil && stored[@"Jobs"][0][@"Status"] != nil, @"persisted intent does not contain a container path");
    persistent.suspended = YES;
    NSUInteger beforeCalls = calls; complete(YES, @"done");
    Check(Wait(^BOOL{ return persistent.jobs[0].status == WQMBackupJobSucceeded; }) && calls == beforeCalls, @"background completion starts no subsequent job");
    WQMBackupQueue *restored = [[WQMBackupQueue alloc] initWithExecutor:executor storagePath:path];
    [restored resolveApps:apps];
    Check(restored.jobs[0].status == WQMBackupJobSucceeded && restored.jobs[1].status == WQMBackupJobPending, @"relaunch preserves completed and pending tasks");
    [persistent stopRemaining]; complete = nil;
    Check([restored resumeRemaining], @"remaining tasks resume explicitly");
    stored = [NSDictionary dictionaryWithContentsOfFile:path];
    WQMBackupQueue *interrupted = [[WQMBackupQueue alloc] initWithExecutor:executor storagePath:path];
    Check(interrupted.jobs[1].status == WQMBackupJobInterrupted, @"crashed active task becomes interrupted");
    [interrupted resolveApps:@[]];
    Check([interrupted resumeRemaining], @"missing-app queue can be reconciled");
    Check(Wait(^BOOL{ return !interrupted.running; }) && interrupted.jobs[1].status == WQMBackupJobFailed, @"unresolved apps fail without executing stale paths");
    complete(YES, @"done");
    Check(Wait(^BOOL{ return restored.jobs[2].status == WQMBackupJobRunning; }), @"resume skips already-completed tasks");
    complete(YES, @"done"); Wait(^BOOL{ return !restored.running; }); complete = nil;
    WQMBackupQueue *bad = [[WQMBackupQueue alloc] initWithExecutor:executor storagePath:[path stringByAppendingPathComponent:@"bad"]];
    Check(![bad startApps:apps scope:0] && bad.persistenceError.length > 0, @"failed persistence prevents execution");
    [NSFileManager.defaultManager removeItemAtPath:root error:nil];

} printf("WQM backup queue tests: %s\n", failures ? "FAILED" : "passed"); return failures ? 1 : 0; }
