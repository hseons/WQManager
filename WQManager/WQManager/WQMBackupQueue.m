#import "WQMBackupQueue.h"
#import "WQMAppModel.h"
#import "WQMLanguageManager.h"
@implementation WQMBackupJob
@end
@implementation WQMBackupQueue {
    WQMBackupQueueExecutor _executor;
    NSString *_storagePath;
    NSDictionary<NSString *, WQMAppModel *> *_currentApps;
}
@synthesize scope = _scope;
- (instancetype)initWithExecutor:(WQMBackupQueueExecutor)executor
{
    return [self initWithExecutor:executor storagePath:nil];
}
- (instancetype)initWithExecutor:(WQMBackupQueueExecutor)executor storagePath:(NSString *)path
{
    if ((self = [super init])) {
        _executor = [executor copy]; _jobs = @[]; _storagePath = [path copy];
        NSDictionary *stored = path ? [NSDictionary dictionaryWithContentsOfFile:path] : nil;
        if ([stored[@"Format"] isEqual:@1] && [stored[@"Scope"] isKindOfClass:NSNumber.class] &&
            [stored[@"Jobs"] isKindOfClass:NSArray.class] && [stored[@"Jobs"] count] <= 2000 &&
            ([stored[@"Scope"] integerValue] == WQMBackupScopeQuick || [stored[@"Scope"] integerValue] == WQMBackupScopeFull)) {
            _scope = [stored[@"Scope"] integerValue];
            NSMutableArray *jobs = [NSMutableArray new]; NSMutableSet *seen = [NSMutableSet new];
            for (id value in stored[@"Jobs"]) {
                if (![value isKindOfClass:NSDictionary.class]) continue;
                NSString *bundle = value[@"BundleID"], *name = value[@"Name"];
                NSNumber *state = value[@"Status"];
                if (![bundle isKindOfClass:NSString.class] || !bundle.length || bundle.length > 255 ||
                    ![name isKindOfClass:NSString.class] || ![state isKindOfClass:NSNumber.class] ||
                    state.integerValue < 0 || state.integerValue > WQMBackupJobInterrupted || [seen containsObject:bundle]) continue;
                [seen addObject:bundle];
                WQMBackupJob *job = [WQMBackupJob new];
                job.app = [[WQMAppModel alloc] initWithBundleIdentifier:bundle displayName:name containerPath:@"" dataSize:0];
                job.app.accessAvailable = NO; job.app.identityKnown = NO;
                job.status = state.integerValue == WQMBackupJobRunning ? WQMBackupJobInterrupted : state.integerValue;
                job.message = @""; [jobs addObject:job];
            }
            _jobs = jobs;
        }
    }
    return self;
}
- (BOOL)persist
{
    if (!_storagePath) return YES;
    NSMutableArray *jobs = [NSMutableArray new];
    for (WQMBackupJob *job in _jobs) [jobs addObject:@{@"BundleID":job.app.bundleIdentifier, @"Name":job.app.displayName, @"Status":@(job.status)}];
    NSError *error;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:@{@"Format":@1, @"Scope":@(_scope), @"Jobs":jobs} format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
    BOOL ok = data && [NSFileManager.defaultManager createDirectoryAtPath:_storagePath.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&error] && [data writeToFile:_storagePath options:NSDataWritingAtomic error:&error];
    _persistenceError = ok ? nil : error.localizedDescription ?: WQML(@"BATCH_SAVE_FAILED", @"任务记录保存失败");
    return ok;
}
- (void)resolveApps:(NSArray<WQMAppModel *> *)apps
{
    NSAssert(NSThread.isMainThread, @"Queue is main-thread owned");
    if (_running) return;
    NSMutableDictionary *current = [NSMutableDictionary new];
    NSMutableSet *duplicates = [NSMutableSet new];
    for (WQMAppModel *app in apps) {
        if (current[app.bundleIdentifier]) [duplicates addObject:app.bundleIdentifier];
        else if (app.bundleIdentifier.length) current[app.bundleIdentifier] = [app snapshotCopy];
    }
    [current removeObjectsForKeys:duplicates.allObjects]; _currentApps = current;
    for (WQMBackupJob *job in _jobs) {
        WQMAppModel *app = current[job.app.bundleIdentifier];
        if (app) job.app = app;
        else { job.app.accessAvailable = NO; job.app.identityKnown = NO; }
    }
}
- (BOOL)resumeRemaining
{
    NSAssert(NSThread.isMainThread, @"Queue is main-thread owned");
    if (_running) return NO;
    BOOL found = NO;
    for (WQMBackupJob *job in _jobs) if (job.status == WQMBackupJobInterrupted || job.status == WQMBackupJobPending) { job.status = WQMBackupJobPending; found = YES; }
    if (!found || ![self persist]) return NO;
    _running = YES; [self next]; return YES;
}
- (void)setSuspended:(BOOL)suspended
{
    NSAssert(NSThread.isMainThread, @"Queue is main-thread owned");
    if (_suspended == suspended) return;
    _suspended = suspended;
    if (!suspended && _running) {
        for (WQMBackupJob *job in _jobs) if (job.status == WQMBackupJobRunning) return;
        [self next];
    }
}
- (BOOL)startApps:(NSArray<WQMAppModel *> *)apps scope:(NSInteger)scope
{
    NSAssert(NSThread.isMainThread, @"Queue is main-thread owned");
    if (_running || !apps.count || apps.count > 2000 || (scope != WQMBackupScopeQuick && scope != WQMBackupScopeFull)) return NO;
    NSMutableSet *seen = [NSMutableSet new];
    NSMutableArray *jobs = [NSMutableArray new];
    for (WQMAppModel *app in apps) {
        if (!app.accessAvailable || !app.identityKnown || !app.bundleIdentifier.length || [seen containsObject:app.bundleIdentifier]) continue;
        [seen addObject:app.bundleIdentifier];
        WQMBackupJob *job = [WQMBackupJob new]; job.app = app; job.message = @"";
        [jobs addObject:job];
    }
    if (!jobs.count) return NO;
    _jobs = jobs; _scope = scope;
    if (![self persist]) return NO;
    _running = YES;
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
    if (!found || ![self persist]) return NO;
    _running = YES; [self next]; return YES;
}
- (void)stopRemaining
{
    NSAssert(NSThread.isMainThread, @"Queue is main-thread owned");
    for (WQMBackupJob *job in _jobs) if (job.status == WQMBackupJobPending) job.status = WQMBackupJobCancelled;
    [self persist];
    if (_running && _suspended) {
        BOOL active = NO;
        for (WQMBackupJob *job in _jobs) if (job.status == WQMBackupJobRunning) active = YES;
        if (!active) { _running = NO; if (self.didFinish) self.didFinish(); }
    }
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
    if (_suspended) return;
    if (_currentApps) {
        WQMAppModel *current = _currentApps[next.app.bundleIdentifier];
        if (!current || !current.accessAvailable || !current.identityKnown) {
            next.status = WQMBackupJobFailed; next.message = WQML(@"BATCH_REFRESH_REQUIRED", @"请先刷新应用索引，再重试此项。");
            [self persist];
            dispatch_async(dispatch_get_main_queue(), ^{ [self next]; }); return;
        }
        next.app = [current snapshotCopy];
    }
    next.status = WQMBackupJobRunning;
    if (![self persist]) {
        next.status = WQMBackupJobInterrupted; _running = NO;
        if (self.didChange) self.didChange(); if (self.didFinish) self.didFinish(); return;
    }
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
            if (![self persist]) { self->_running = NO; if (self.didFinish) self.didFinish(); return; }
            if (self.didChange) self.didChange();
            [self next];
        });
    });
}
@end
