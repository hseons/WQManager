#import <Foundation/Foundation.h>
#import "WQMAccessDiagnostics.h"
#import "WQMAppModel.h"
#import <sys/stat.h>
#import <unistd.h>

static NSUInteger failures;
static void Check(BOOL value, NSString *message) { if (!value) { failures++; fprintf(stderr, "FAIL: %s\n", message.UTF8String); } }
static WQMAccessCheck *Stage(WQMAccessReport *report, NSString *stage) {
    for (WQMAccessCheck *check in report.checks) if ([check.stage isEqual:stage]) return check;
    return nil;
}
static void Write(NSString *path, NSString *text) {
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
int main(void) { @autoreleasepool {
    NSString *base = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSString *root = [base stringByAppendingPathComponent:@"PRIVATE-CONTAINER-ID"];
    NSString *sample = [root stringByAppendingPathComponent:@"Documents/PRIVATE-FILENAME.txt"];
    Write(sample, @"PRIVATE-FILE-CONTENTS");
    [NSFileManager.defaultManager createDirectoryAtPath:[root stringByAppendingPathComponent:@"Library"] withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *outside = [base stringByAppendingPathComponent:@"outside"];
    Write([outside stringByAppendingPathComponent:@"secret.txt"], @"OUTSIDE-SECRET");
    [NSFileManager.defaultManager createSymbolicLinkAtPath:[root stringByAppendingPathComponent:@"tmp"] withDestinationPath:outside error:nil];
    WQMAppModel *app = [[WQMAppModel alloc] initWithBundleIdentifier:@"private.bundle.id" displayName:@"PRIVATE-APP-NAME" containerPath:root dataSize:0];
    struct stat st; lstat(root.fileSystemRepresentation, &st);
    app.identityKnown = YES; app.containerDevice = st.st_dev; app.containerInode = st.st_ino;
    __block NSInteger grantCode = 0;
    __block int grantErrno = 0;
    __block NSUInteger grants = 0, labels = 0;
    WQMAccessDiagnostics *service = [[WQMAccessDiagnostics alloc] initWithContainerRoot:base grant:^BOOL(NSString *path, NSInteger *code, int *err) {
        grants++; *code = grantCode; *err = grantErrno; return grantCode == 0;
    } label:^NSString *(NSString *path) { labels++; return @"private.bundle.id"; }];
    BOOL (^notCancelled)(void) = ^BOOL { return NO; };
    NSDictionary *environment = @{@"OSBuild": @"TEST-BUILD", @"AppVersion": @"0.4", @"Simulator": @YES, @"SyntheticTarget": @YES,
        @"RawLog": @"TOKEN-SECRET", @"Container": root, @"AppName": app.displayName};
    NSDictionary *before = [NSFileManager.defaultManager attributesOfItemAtPath:sample error:nil];
    WQMAccessReport *report = [service probeApp:app environment:environment cancelled:notCancelled];
    Check([Stage(report, @"identity").status isEqual:@"passed"], @"current descriptor and container label are verified");
    Check([Stage(report, @"documents-read").status isEqual:@"passed"], @"a real file read succeeds");
    Check([Stage(report, @"library-list").status isEqual:@"passed"] && [Stage(report, @"library-read").status isEqual:@"not-tested"], @"an empty directory is readable but not evidence of file reads");
    Check([Stage(report, @"tmp-open").status isEqual:@"failed"] && !Stage(report, @"tmp-read"), @"linked subdirectories are never sampled");
    NSDictionary *after = [NSFileManager.defaultManager attributesOfItemAtPath:sample error:nil];
    Check([before[NSFileSize] isEqual:after[NSFileSize]] && [before[NSFileModificationDate] isEqual:after[NSFileModificationDate]] &&
        [[NSString stringWithContentsOfFile:sample encoding:NSUTF8StringEncoding error:nil] isEqual:@"PRIVATE-FILE-CONTENTS"], @"diagnostics preserve target bytes, size and mtime");
    NSData *json = report.redactedJSONData;
    NSString *text = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    NSDictionary *parsed = [NSJSONSerialization JSONObjectWithData:json options:0 error:nil];
    for (NSString *secret in @[root, app.bundleIdentifier, app.displayName, @"PRIVATE-FILENAME", @"PRIVATE-FILE-CONTENTS", @"TOKEN-SECRET", @"OUTSIDE-SECRET"])
        Check(![text containsString:secret], @"report excludes identities, paths, filenames, bytes and raw logs");
    Check([parsed[@"Environment"][@"OSBuild"] isEqual:@"TEST-BUILD"] && [parsed[@"WriteCapability"] isEqual:@"not-tested"] &&
        [parsed[@"UntestedCategories"] containsObject:@"shared-app-groups"], @"report retains environment evidence and untested boundaries");
    Check([parsed[@"Environment"][@"SyntheticTarget"] boolValue], @"synthetic targets cannot be mistaken for real device evidence");
    chmod(sample.fileSystemRepresentation, 0000);
    report = [service probeApp:app environment:environment cancelled:notCancelled];
    Check([Stage(report, @"documents-read").reason isEqual:@"permission"] && Stage(report, @"documents-read").systemError == EACCES,
        @"an actual unreadable file is not reported as a successful content read");
    chmod(sample.fileSystemRepresentation, 0600);
    app.containerInode++;
    report = [service probeApp:app environment:environment cancelled:notCancelled];
    Check([Stage(report, @"identity").reason isEqual:@"changed"] && !Stage(report, @"documents-open"), @"stale identity stops all child reads");
    app.containerInode--;
    WQMAccessDiagnostics *wrongLabel = [[WQMAccessDiagnostics alloc] initWithContainerRoot:base grant:^BOOL(NSString *path, NSInteger *code, int *err) { return YES; }
        label:^NSString *(NSString *path) { return @"different.bundle.id"; }];
    report = [wrongLabel probeApp:app environment:environment cancelled:notCancelled];
    Check([Stage(report, @"identity").reason isEqual:@"changed"] && !Stage(report, @"root-list"), @"wrong bundle label stops directory reads");
    WQMAccessDiagnostics *noLabel = [[WQMAccessDiagnostics alloc] initWithContainerRoot:base grant:^BOOL(NSString *path, NSInteger *code, int *err) { return YES; }
        label:^NSString *(NSString *path) { return nil; }];
    report = [noLabel probeApp:app environment:environment cancelled:notCancelled];
    Check([Stage(report, @"identity").status isEqual:@"not-tested"] && !Stage(report, @"root-list"), @"unknown ownership is not reported as full access");
    NSArray *reasonCodes = @[@"", @"no-group", @"api", @"query", @"prepare", @"result", @"token", @"consume", @"recovery", @"exception", @"denied", @"permission"];
    for (NSInteger code = -1; code >= -11; code--) {
        grantCode = code; grantErrno = code == -11 ? EACCES : 0;
        report = [service probeApp:app environment:environment cancelled:notCancelled];
        Check([Stage(report, @"grant").reason isEqual:reasonCodes[-code]], @"grant failure stages remain distinct");
        Check([Stage(report, @"root-open").status isEqual:@"passed"], @"token failure is distinct from an observed direct open");
    }
    grantCode = 0; grantErrno = 0;
    report = [service probeApp:app environment:environment cancelled:^BOOL { return YES; }];
    Check(report.cancelled && report.checks.count == 1 && !Stage(report, @"grant"), @"pre-cancelled checks never acquire access");
    __block BOOL cancelAfterGrant = NO;
    WQMAccessDiagnostics *cancelService = [[WQMAccessDiagnostics alloc] initWithContainerRoot:base
        grant:^BOOL(NSString *path, NSInteger *code, int *err) { cancelAfterGrant = YES; return YES; }
        label:^NSString *(NSString *path) { return @"private.bundle.id"; }];
    report = [cancelService probeApp:app environment:environment cancelled:^BOOL { return cancelAfterGrant; }];
    Check(report.cancelled && !Stage(report, @"root-open"), @"cancellation after grant prevents further reads");
    NSString *original = app.containerPath;
    NSUInteger grantsBefore = grants;
    app.containerPath = [root stringByAppendingPathComponent:@"../outside"];
    report = [service probeApp:app environment:environment cancelled:notCancelled];
    Check([Stage(report, @"target").reason isEqual:@"path"] && grants == grantsBefore, @"traversal is rejected before requesting a token");
    app.containerPath = @"/private/var/mobile/Library";
    report = [service probeApp:app environment:environment cancelled:notCancelled];
    Check([Stage(report, @"target").reason isEqual:@"path"] && grants == grantsBefore, @"out-of-scope roots are rejected before requesting access");
    app.containerPath = [base stringByAppendingPathComponent:@"missing"];
    report = [service probeApp:app environment:environment cancelled:notCancelled];
    Check(Stage(report, @"root-open").systemError == ENOENT, @"missing containers retain a numeric errno");
    app.containerPath = original;
    NSString *linkedRoot = [base stringByAppendingPathComponent:@"linked-root"];
    [NSFileManager.defaultManager createSymbolicLinkAtPath:linkedRoot withDestinationPath:root error:nil];
    app.containerPath = linkedRoot;
    report = [service probeApp:app environment:environment cancelled:notCancelled];
    Check([Stage(report, @"root-open").status isEqual:@"failed"] && !Stage(report, @"identity"), @"linked roots never proceed to ownership or content checks");
    app.containerPath = original;
    for (NSUInteger i = 0; i < 80; i++) Write([root stringByAppendingPathComponent:[NSString stringWithFormat:@"Documents/%lu.txt", (unsigned long)i]], @"x");
    report = [service probeApp:app environment:environment cancelled:notCancelled];
    Check(Stage(report, @"documents-list").sampleLimited && Stage(report, @"documents-list").sampledEntries == 64, @"large directories stop at a fixed sample bound");
    WQMAccessDiagnostics *replace = [[WQMAccessDiagnostics alloc] initWithContainerRoot:base grant:^BOOL(NSString *path, NSInteger *code, int *err) { return YES; }
        label:^NSString *(NSString *path) {
            [NSFileManager.defaultManager moveItemAtPath:root toPath:[base stringByAppendingPathComponent:@"old-root"] error:nil];
            [NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
            return @"private.bundle.id";
        }];
    report = [replace probeApp:app environment:environment cancelled:notCancelled];
    Check([Stage(report, @"identity").reason isEqual:@"changed"] && !Stage(report, @"root-list"), @"a root replaced during label lookup invalidates access");
    Check(labels > 0, @"ownership lookup exercised");
    [NSFileManager.defaultManager removeItemAtPath:base error:nil];
} printf("WQM access diagnostics tests: %s\n", failures ? "FAILED" : "passed"); return failures ? 1 : 0; }
