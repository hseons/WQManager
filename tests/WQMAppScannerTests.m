#import <Foundation/Foundation.h>
#import "WQMAppScanner.h"
#import "WQMAppModel.h"
#import "WQAccess.h"
#import <sys/stat.h>
static NSArray<NSString *> *paths;
static dispatch_semaphore_t deferredGate;
static NSUInteger failures, drops, measured;
static BOOL labelsValid = YES;
static void Check(BOOL ok, NSString *message) { if (!ok) { failures++; fprintf(stderr, "FAIL: %s\n", message.UTF8String); } }
static BOOL Wait(BOOL (^condition)(void)) { NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5]; while (!condition() && deadline.timeIntervalSinceNow > 0) [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]]; return condition(); }
@implementation WQScanCancellation { BOOL _cancelled; }
- (BOOL)isCancelled { @synchronized(self) { return _cancelled; } }
- (void)cancel { @synchronized(self) { _cancelled = YES; } }
@end
BOOL wq_grant(NSString *path) { return YES; }
void wq_drop_grant(NSString *path) { drops++; }
BOOL wq_stat(NSString *path, struct stat *st) { return lstat(path.fileSystemRepresentation, st) == 0; }
NSString *wq_container_label(NSString *path) { return labelsValid ? [@"com.fixture." stringByAppendingString:path.lastPathComponent] : @"com.fixture.changed"; }
BOOL wq_display_names_loaded(void) { return YES; }
void wq_load_display_names(void) { }
NSString *wq_display_name(NSString *bundle) { return bundle; }
BOOL wq_full_scan_was_declined(void) { return NO; }
NSArray<NSString *> *wq_enumerate(NSString *dir, int64_t max, WQScanCancellation *cancel, void (^progress)(int64_t, int64_t, NSUInteger)) { return paths; }
WQMeasureResult wq_measure_tree_budgeted(NSString *dir, WQScanCancellation *cancel, unsigned long long *bytes, WQMeasureBudget budget) { *bytes = 10; return WQMeasureResultBudgetExceeded; }
WQMeasureResult wq_measure_tree(NSString *dir, WQScanCancellation *cancel, unsigned long long *bytes) {
    measured++;
    if (deferredGate) dispatch_semaphore_wait(deferredGate, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
    if (cancel.cancelled) return WQMeasureResultCancelled;
    *bytes = 100; return WQMeasureResultKnown;
}
int main(void) { @autoreleasepool {
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSString *one = [root stringByAppendingPathComponent:@"one"], *two = [root stringByAppendingPathComponent:@"two"];
    for (NSString *path in @[one, two]) [NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    paths = @[one, two]; deferredGate = dispatch_semaphore_create(0);
    __block BOOL finished = NO;
    __block NSArray *initial;
    __block WQMAppScanResult *result;
    WQMAppScanner *scanner = [WQMAppScanner new]; WQScanCancellation *cancel = [WQScanCancellation new];
    [scanner scanWithCancellation:cancel progress:nil partial:^(NSArray *apps) {
        Check(NSThread.isMainThread, @"partial snapshots arrive on main thread");
        if (!initial) initial = apps;
    } completion:^(WQMAppScanResult *value) { result = value; finished = YES; }];
    Check(Wait(^BOOL{ return initial != nil; }) && !finished, @"app list is published before slow measurement completes");
    dispatch_semaphore_signal(deferredGate); dispatch_semaphore_signal(deferredGate);
    Check(Wait(^BOOL{ return finished; }) && result.apps.count == 2, @"final scan completes");
    Check(![initial[0] sizeKnown] && [initial[0] dataSize] == 10 && result.apps[0].sizeKnown, @"partial models stay detached when worker measurements change");
    Check(drops == 4, @"all quick and deferred grants are released");
    deferredGate = nil; finished = NO;
    WQMAppModel *app = result.apps[0];
    [scanner refreshApp:app cancellation:[WQScanCancellation new] completion:^(WQMAppModel *value) { Check(value.sizeKnown && value.dataSize == 100, @"single-app refresh returns a known measurement"); finished = YES; }];
    Check(Wait(^BOOL{ return finished; }), @"single-app refresh completes");
    labelsValid = NO; measured = 0; finished = NO;
    [scanner refreshApp:app cancellation:[WQScanCancellation new] completion:^(WQMAppModel *value) { Check(!value.identityKnown && !value.accessAvailable, @"changed identity is reported without reading children"); finished = YES; }];
    Check(Wait(^BOOL{ return finished; }) && measured == 0, @"identity mismatch never starts measurement");
    labelsValid = YES; finished = NO; initial = nil;
    cancel = [WQScanCancellation new];
    [scanner scanWithCancellation:cancel progress:nil partial:^(NSArray *apps) { [cancel cancel]; } completion:^(WQMAppScanResult *value) { result = value; finished = YES; }];
    // Cancellation remains deterministic even if the tiny synthetic scan already finished.
    [cancel cancel];
    Check(Wait(^BOOL{ return finished; }) && result.cancelled && result.apps.count == 0, @"cancelled scan does not publish a persistable final index");
    [NSFileManager.defaultManager removeItemAtPath:root error:nil];
} printf("WQM app scanner tests: %s\n", failures ? "FAILED" : "passed"); return failures ? 1 : 0; }
