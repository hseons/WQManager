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
} printf("WQM backup queue tests: %s\n", failures ? "FAILED" : "passed"); return failures ? 1 : 0; }
