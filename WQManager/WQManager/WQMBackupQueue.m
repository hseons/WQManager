#import "WQMBackupQueue.h"
#import "WQMAppModel.h"
@implementation WQMBackupJob
@end
@implementation WQMBackupQueue {
    WQMBackupQueueExecutor _executor;
    NSInteger _scope;
}
- (instancetype)initWithExecutor:(WQMBackupQueueExecutor)executor
{
    if ((self = [super init])) { _executor = [executor copy]; _jobs = @[]; }
    return self;
}
- (BOOL)startApps:(NSArray<WQMAppModel *> *)apps scope:(NSInteger)scope
{
    NSAssert(NSThread.isMainThread, @"Queue is main-thread owned");
    if (_running || !apps.count || (scope != WQMBackupScopeQuick && scope != WQMBackupScopeFull)) return NO;
    NSMutableSet *seen = [NSMutableSet new];
    NSMutableArray *jobs = [NSMutableArray new];
    for (WQMAppModel *app in apps) {
        if (!app.accessAvailable || !app.identityKnown || !app.bundleIdentifier.length || [seen containsObject:app.bundleIdentifier]) continue;
        [seen addObject:app.bundleIdentifier];
        WQMBackupJob *job = [WQMBackupJob new]; job.app = app; job.message = @"";
        [jobs addObject:job];
    }
    if (!jobs.count) return NO;
    _jobs = jobs; _scope = scope; _running = YES;
    [self next]; return YES;
}
- (BOOL)retryFailures
{
    NSAssert(NSThread.isMainThread, @"Queue is main-thread owned");
    if (_running) return NO;
    BOOL found = NO;
    for (WQMBackupJob *job in _jobs) {
        if (job.status != WQMBackupJobFailed) continue;
        job.status = WQMBackupJobPending; job.message = @""; found = YES;
    }
    if (!found) return NO;
    _running = YES; [self next]; return YES;
}
- (void)stopRemaining
{
    NSAssert(NSThread.isMainThread, @"Queue is main-thread owned");
    for (WQMBackupJob *job in _jobs) if (job.status == WQMBackupJobPending) job.status = WQMBackupJobCancelled;
    if (self.didChange) self.didChange();
}
- (void)next
{
    WQMBackupJob *next = nil;
    for (WQMBackupJob *job in _jobs) if (job.status == WQMBackupJobPending) { next = job; break; }
    if (!next) {
        _running = NO;
        if (self.didChange) self.didChange();
        if (self.didFinish) self.didFinish();
        return;
    }
    next.status = WQMBackupJobRunning;
    if (self.didChange) self.didChange();
    _executor(next.app, _scope, ^(NSString *message) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (next.status != WQMBackupJobRunning) return;
            next.message = message;
            if (self.didChange) self.didChange();
        });
    }, ^(BOOL success, NSString *message) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (next.status != WQMBackupJobRunning) return;
            next.status = success ? WQMBackupJobSucceeded : WQMBackupJobFailed;
            next.message = message ?: @"";
            [self next];
        });
    });
}
@end
