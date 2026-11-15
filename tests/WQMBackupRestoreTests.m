#import <Foundation/Foundation.h>
#import "WQMBackupService.h"
#import "WQMBackupArchiveService.h"
#import "WQMRestoreService.h"
#import "WQMBackupStore.h"
#import "WQMStorageService.h"
#import "WQMOperationStore.h"
#import "WQMAppModel.h"
#import "WQMPreferences.h"
#import "WQAccess.h"
#import <stdarg.h>

// The real backup/restore services run against a test-owned filesystem. These
// stubs replace only the privileged access bridge, including one copy failure.
static NSString *containerRoot;
static NSUInteger failTargetCopies;
static NSUInteger failures;
static void Check(BOOL ok, NSString *message) { if (!ok) { failures++; fprintf(stderr, "FAIL: %s\n", message.UTF8String); } }
static BOOL Wait(BOOL (^condition)(void)) { NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:15]; while (!condition() && deadline.timeIntervalSinceNow > 0) [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]]; return condition(); }
BOOL wq_grant(NSString *path) { return YES; }
BOOL wq_stat(NSString *path, struct stat *st) { return lstat(path.fileSystemRepresentation, st) == 0; }
NSString *wq_container_label(NSString *path) { return @"com.fixture.restore"; }
int wq_process_id_for_bundle(NSString *bundleID) { return 0; }
void wq_log(NSString *format, ...) { }
BOOL wq_copy_contents_paced(NSString *source, NSString *destination, void (^consume)(void), NSString **reason) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSError *error;
    if (![fm createDirectoryAtPath:destination withIntermediateDirectories:YES attributes:nil error:&error]) { if (reason) *reason = error.localizedDescription; return NO; }
    NSArray *children = [fm contentsOfDirectoryAtPath:source error:&error];
    if (!children) { if (reason) *reason = error.localizedDescription; return NO; }
    for (NSString *child in children) {
        if (![fm copyItemAtPath:[source stringByAppendingPathComponent:child] toPath:[destination stringByAppendingPathComponent:child] error:&error]) { if (reason) *reason = error.localizedDescription; return NO; }
        if (consume) consume();
        if (failTargetCopies && [destination hasPrefix:[containerRoot stringByAppendingString:@"/"]]) {
            failTargetCopies -= 1; if (reason) *reason = @"injected apply failure"; return NO;
        }
    }
    return YES;
}
BOOL wq_purge_contents(NSString *path, unsigned long long *freed) {
    NSFileManager *fm = NSFileManager.defaultManager;
    struct stat st;
    if (lstat(path.fileSystemRepresentation, &st) != 0) return errno == ENOENT;
    if (!S_ISDIR(st.st_mode)) return NO;
    for (NSString *child in [fm contentsOfDirectoryAtPath:path error:nil]) if (![fm removeItemAtPath:[path stringByAppendingPathComponent:child] error:nil]) return NO;
    return YES;
}
static void Write(NSString *path, NSString *text) { [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil]; [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]; }
static NSString *Read(NSString *path) { return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil]; }
int main(void) { @autoreleasepool {
    NSString *base = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    containerRoot = [base stringByAppendingPathComponent:@"Container"];
    NSString *backupRoot = [base stringByAppendingPathComponent:@"AppBackups"];
    [WQMBackupStore setBackupRootForTesting:backupRoot];
    [WQMStorageService setRootsForTesting:backupRoot temporaryRoot:[base stringByAppendingPathComponent:@"tmp"]];
    [WQMOperationStore setStorageRootForTesting:[base stringByAppendingPathComponent:@"Operations"]];
    [WQMRestoreService setRecoveryRootForTesting:[base stringByAppendingPathComponent:@"Recovery"]];
    WQMLoadProfile previous = WQMLoadProfileCurrent(); WQMLoadProfileSetCurrent(WQMLoadProfileStandard);
    NSString *selected = [containerRoot stringByAppendingPathComponent:@"Library/Preferences/value.txt"];
    NSString *sibling = [containerRoot stringByAppendingPathComponent:@"Library/Caches/untouched.txt"];
    NSString *document = [containerRoot stringByAppendingPathComponent:@"Documents/untouched.txt"];
    Write(selected, @"old selected"); Write(sibling, @"keep cache"); Write(document, @"keep documents");
    struct stat st; lstat(containerRoot.fileSystemRepresentation, &st);
    WQMAppModel *app = [[WQMAppModel alloc] initWithBundleIdentifier:@"com.fixture.restore" displayName:@"Fixture" containerPath:containerRoot dataSize:1];
    app.accessAvailable = app.identityKnown = app.sizeKnown = YES; app.containerDevice = st.st_dev; app.containerInode = st.st_ino;
    WQMBackupScopeDescriptor *selection = [WQMBackupScopeDescriptor descriptorForPaths:@[@"Library/Preferences"]];
    __block WQMBackupRecord *backup;
    __block BOOL finished = NO;
    [[WQMBackupService new] backupApp:app selection:selection reason:@"" progress:nil completion:^(WQMBackupRecord *record, NSError *error) { backup = record; finished = YES; if (error) fprintf(stderr, "backup error: %s\n", error.localizedDescription.UTF8String); }];
    Check(Wait(^BOOL{ return finished; }) && backup != nil, @"custom backup service publishes a valid format 3 package");
    Check(backup.formatVersion == 3 && [backup.requestedParts isEqual:@[@"Library/Preferences"]], @"partial restore scope round-trips");
    __block NSURL *exportURL;
    finished = NO;
    WQMBackupArchiveService *archive = [WQMBackupArchiveService new];
    [archive prepareExportForBackup:backup completion:^(NSURL *url, NSError *error) { exportURL = url; finished = YES; }];
    Check(Wait(^BOOL{ return finished; }) && exportURL != nil, @"custom backup exports with nested paths");
    finished = NO; __block WQMBackupRecord *imported;
    [archive importBackupAtURL:exportURL completion:^(WQMBackupRecord *record, NSError *error) { imported = record; finished = YES; }];
    Check(Wait(^BOOL{ return finished; }) && [imported.requestedParts isEqual:backup.requestedParts], @"format 3 export/import preserves exact restore scope");
    if (exportURL) [NSFileManager.defaultManager removeItemAtURL:exportURL.URLByDeletingLastPathComponent error:nil];
    Write(selected, @"new selected");
    finished = NO; __block BOOL restored = NO;
    [[WQMRestoreService new] restoreBackup:backup toApp:app progress:nil completion:^(BOOL success, NSString *message, NSError *error) { restored = success; finished = YES; if (!success) fprintf(stderr, "restore error: %s\n", message.UTF8String); }];
    Check(Wait(^BOOL{ return finished; }) && restored, @"real restore service restores selected nested directory");
    Check([Read(selected) isEqual:@"old selected"], @"selected payload restored");
    Check([Read(sibling) isEqual:@"keep cache"] && [Read(document) isEqual:@"keep documents"], @"sibling and unselected roots untouched");
    WQMLoadProfileSetCurrent(WQMLoadProfileLowLoad);
    Write(selected, @"new low-load data");
    finished = NO; restored = NO;
    [[WQMRestoreService new] restoreBackup:backup toApp:app progress:nil completion:^(BOOL success, NSString *message, NSError *error) { restored = success; finished = YES; }];
    Check(Wait(^BOOL{ return finished; }) && restored && [Read(selected) isEqual:@"old selected"], @"partial restore works with reduced metadata verification");
    WQMLoadProfileSetCurrent(WQMLoadProfileStandard);
    Write(selected, @"before failing restore");
    failTargetCopies = 1; finished = NO; restored = YES;
    [[WQMRestoreService new] restoreBackup:backup toApp:app progress:nil completion:^(BOOL success, NSString *message, NSError *error) { restored = success; finished = YES; }];
    Check(Wait(^BOOL{ return finished; }) && !restored, @"injected partial apply is reported as failure");
    Check([Read(selected) isEqual:@"before failing restore"], @"automatic safety backup rolls selected subtree back");
    Check([Read(sibling) isEqual:@"keep cache"] && [Read(document) isEqual:@"keep documents"], @"rollback does not widen the directory scope");
    Check([WQMRestoreService activeRecoverySummary] == nil, @"successful rollback clears recovery journal");
    Write(selected, @"before manual recovery");
    failTargetCopies = 2; finished = NO;
    [[WQMRestoreService new] restoreBackup:backup toApp:app progress:nil completion:^(BOOL success, NSString *message, NSError *error) { finished = YES; }];
    Check(Wait(^BOOL{ return finished; }) && [WQMRestoreService activeRecoverySummary] != nil, @"failed apply and rollback retain a recoverable journal");
    finished = NO; __block BOOL recovered = NO;
    [WQMRestoreService recoverActiveRecoveryWithProgress:nil completion:^(BOOL success, NSString *message, NSError *error) { recovered = success; finished = YES; }];
    Check(Wait(^BOOL{ return finished; }) && recovered, @"manual journal recovery supports nested custom selections");
    Check([Read(selected) isEqual:@"before manual recovery"] && [Read(sibling) isEqual:@"keep cache"], @"manual recovery preserves the exact recorded scope");
    Check([WQMRestoreService activeRecoverySummary] == nil, @"manual recovery clears its journal");
    // A linked parent must fail before backup publication or target mutation.
    [NSFileManager.defaultManager moveItemAtPath:[containerRoot stringByAppendingPathComponent:@"Library"] toPath:[base stringByAppendingPathComponent:@"MovedLibrary"] error:nil];
    [NSFileManager.defaultManager createSymbolicLinkAtPath:[containerRoot stringByAppendingPathComponent:@"Library"] withDestinationPath:[base stringByAppendingPathComponent:@"MovedLibrary"] error:nil];
    finished = NO; __block WQMBackupRecord *linked;
    [[WQMBackupService new] backupApp:app selection:selection reason:@"" progress:nil completion:^(WQMBackupRecord *record, NSError *error) { linked = record; finished = YES; }];
    Check(Wait(^BOOL{ return finished; }) && linked == nil, @"linked selection ancestors rejected by backup service");
    WQMLoadProfileSetCurrent(previous);
    [NSFileManager.defaultManager removeItemAtPath:base error:nil];
    // Leave injected roots pointing at this test's directory until process exit:
    // a background retention callback must never fall back to real Documents.
} printf("WQM backup/restore integration tests: %s\n", failures ? "FAILED" : "passed"); return failures ? 1 : 0; }
