#import <Foundation/Foundation.h>
#import "WQMScanHistory.h"
#import "WQMAppModel.h"
static NSUInteger failures;
static void Check(BOOL ok, NSString *message) { if (!ok) { failures++; fprintf(stderr, "FAIL: %s\n", message.UTF8String); } }
int main(void) { @autoreleasepool {
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [WQMScanHistory setStoragePathForTesting:[root stringByAppendingPathComponent:@"history.plist"]];
    WQMAppModel *app = [[WQMAppModel alloc] initWithBundleIdentifier:@"com.fixture.app" displayName:@"Fixture" containerPath:root dataSize:100];
    app.accessAvailable = app.identityKnown = app.sizeKnown = YES; app.containerDevice = 1; app.containerInode = 2;
    [WQMScanHistory recordApps:@[app] atDate:[NSDate dateWithTimeIntervalSince1970:1]];
    Check([WQMScanHistory changeForApp:app] == nil, @"first scan has no delta");
    app.dataSize = 160;
    [WQMScanHistory recordApps:@[app] atDate:[NSDate dateWithTimeIntervalSince1970:2]];
    Check([[WQMScanHistory changeForApp:app] isEqual:@60], @"delta uses comparable completed scans");
    app.dataSize = 20;
    [WQMScanHistory recordApps:@[app] atDate:[NSDate dateWithTimeIntervalSince1970:3]];
    Check([[WQMScanHistory changeForApp:app] isEqual:@(-140)], @"shrinking stays signed");
    app.containerInode = 3;
    [WQMScanHistory recordApps:@[app] atDate:[NSDate dateWithTimeIntervalSince1970:4]];
    Check([WQMScanHistory changeForApp:app] == nil, @"reinstall starts a new series");
    for (NSUInteger i = 0; i < 70; i++) { app.dataSize = i; [WQMScanHistory recordApps:@[app] atDate:[NSDate dateWithTimeIntervalSince1970:i + 5]]; }
    Check([WQMScanHistory samplesForApp:app].count == 60, @"history remains bounded");
    NSArray<NSDictionary *> *totals = [WQMScanHistory totalSamples];
    Check(totals.count == 60, @"total samples skip empty snapshots");
    Check([totals.lastObject[@"Bytes"] isEqual:@69], @"total sum uses measured bytes");
    Check([totals.firstObject[@"Bytes"] isEqual:@10], @"total series stays aligned with retained snapshots");

    NSString *windowRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [WQMScanHistory setStoragePathForTesting:[windowRoot stringByAppendingPathComponent:@"history.plist"]];
    unsigned long long windowSizes[] = { 100, 110, 120, 130, 140, 150 };
    NSInteger windowDays[] = { 0, 10, 20, 30, 35, 40 };
    for (NSUInteger i = 0; i < 6; i++) {
        app.dataSize = windowSizes[i];
        [WQMScanHistory recordApps:@[app] atDate:[NSDate dateWithTimeIntervalSince1970:windowDays[i] * 24 * 60 * 60]];
    }
    Check([[WQMScanHistory changeForApp:app overDays:7] isEqual:@10], @"seven-day window compares against the first sample inside it");
    Check([[WQMScanHistory changeForApp:app overDays:30] isEqual:@40], @"thirty-day window uses the same rule");
    Check([[WQMScanHistory totalSamples].lastObject[@"Bytes"] isEqual:@150], @"total samples follow the current series");
    [NSFileManager.defaultManager removeItemAtPath:windowRoot error:nil];
    app.sizeKnown = NO;
    Check([WQMScanHistory changeForApp:app] == nil, @"unknown current size never yields a delta");
    [WQMScanHistory recordApps:@[app] atDate:NSDate.date];
    app.sizeKnown = YES;
    [WQMScanHistory recordApps:@[app] atDate:NSDate.date];
    Check([WQMScanHistory samplesForApp:app].count == 1, @"an entirely unknown scan also breaks continuity");
    app.sizeKnown = NO;
    WQMAppModel *other = [[WQMAppModel alloc] initWithBundleIdentifier:@"com.fixture.other" displayName:@"Other" containerPath:root dataSize:1];
    other.accessAvailable = other.identityKnown = other.sizeKnown = YES;
    [WQMScanHistory recordApps:@[app, other] atDate:NSDate.date];
    app.sizeKnown = YES;
    [WQMScanHistory recordApps:@[app] atDate:NSDate.date];
    Check([WQMScanHistory samplesForApp:app].count == 1, @"a missing measurement breaks continuity");
    [NSFileManager.defaultManager removeItemAtPath:root error:nil];
    [WQMScanHistory setStoragePathForTesting:nil];
} printf("WQM scan history tests: %s\n", failures ? "FAILED" : "passed"); return failures ? 1 : 0; }
