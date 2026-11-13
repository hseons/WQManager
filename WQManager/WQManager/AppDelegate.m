//
//  AppDelegate.m
//  WQManager
//
//  Created by 木木 on 2026/11/10.
//

#import "AppDelegate.h"
#import "WQMBackupStore.h"
#import "WQMOperationStore.h"

@interface AppDelegate ()

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
#if DEBUG
    if ([NSProcessInfo.processInfo.environment[@"WQM_UI_FIXTURES"] boolValue] &&
        [WQMOperationStore allOperations].count == 0) {
        NSArray<NSArray *> *fixtures = @[
            @[@"微信", @"com.tencent.xin", @(WQMOperationKindBackup), @(WQMOperationStatusSuccess), @"快速备份", @(6442450944ULL)],
            @[@"微信", @"com.tencent.xin", @(WQMOperationKindSafetyBackup), @(WQMOperationStatusSuccess), @"恢复前自动安全备份", @(6186598400ULL)],
            @[@"剪映", @"com.lemon.lv", @(WQMOperationKindRestore), @(WQMOperationStatusRolledBack), @"完整备份", @(4939212390ULL)],
            @[@"抖音", @"com.ss.iphone.ugc.Aweme", @(WQMOperationKindBackup), @(WQMOperationStatusFailure), @"快速备份", @(0)],
        ];
        for (NSArray *fixture in fixtures) {
            WQMOperationRecord *record = [WQMOperationStore beginOperation:[fixture[2] integerValue]
                                                                  appName:fixture[0]
                                                         bundleIdentifier:fixture[1]];
            record.status = [fixture[3] integerValue];
            record.scope = fixture[4];
            record.bytes = [fixture[5] unsignedLongLongValue];
            record.finishedAt = NSDate.date;
            if (record.status == WQMOperationStatusFailure) {
                record.errorMessage = @"目标 App 未完全关闭";
            }
            [WQMOperationStore updateRecord:record];
        }
    }
    if ([NSProcessInfo.processInfo.environment[@"WQM_UI_FIXTURES"] boolValue] &&
        [WQMBackupStore allBackups].count == 0) {
        [self seedBackupFixtures];
    }
#endif
    return YES;
}


#if DEBUG
- (void)seedBackupFixtures
{
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *root = [WQMBackupStore backupRoot];
    NSDate *now = NSDate.date;
    NSArray<NSArray *> *fixtures = @[
        @[@"微信", @"com.tencent.xin", @"快速备份", @"quick", @(6442450944ULL), @0, @(-2)],
        @[@"微信", @"com.tencent.xin", @"完整备份", @"full", @(12884901888ULL), @1, @(-26)],
        @[@"剪映", @"com.lemon.lv", @"快速备份", @"quick", @(4939212390ULL), @2, @(-50)],
        @[@"抖音", @"com.ss.iphone.ugc.Aweme", @"恢复前自动安全备份", @"safety", @(3758096384ULL), @3, @(-74)],
    ];
    for (NSArray *fixture in fixtures) {
        NSDateFormatter *formatter = [NSDateFormatter new];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.dateFormat = @"yyyyMMdd-HHmmss";
        NSDate *created = [now dateByAddingTimeInterval:[fixture[6] doubleValue] * 3600];
        NSString *directory = [[root stringByAppendingPathComponent:fixture[1]]
                               stringByAppendingPathComponent:[formatter stringFromDate:created]];
        NSString *documents = [directory stringByAppendingPathComponent:@"Documents"];
        [fm createDirectoryAtPath:documents withIntermediateDirectories:YES attributes:nil error:nil];
        [@"fixture" writeToFile:[documents stringByAppendingPathComponent:@"note.txt"]
                     atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSDictionary *manifest = @{
            @"Complete": @YES,
            @"Format": @2,
            @"BundleID": fixture[1],
            @"DisplayName": fixture[0],
            @"Scope": fixture[2],
            @"ScopeCode": fixture[3],
            @"Reason": fixture[2],
            @"Created": created,
            @"Parts": @[@"Documents"],
            @"PartHashes": @{@"Documents": @"fixture"},
            @"TotalBytes": fixture[4],
            @"SystemVersion": @"26.0",
        };
        [manifest writeToFile:[directory stringByAppendingPathComponent:@"manifest.plist"] atomically:YES];
    }
}
#endif

#pragma mark - UISceneSession lifecycle


- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options {
    // Called when a new scene session is being created.
    // Use this method to select a configuration to create the new scene with.
    return [[UISceneConfiguration alloc] initWithName:@"Default Configuration" sessionRole:connectingSceneSession.role];
}


- (void)application:(UIApplication *)application didDiscardSceneSessions:(NSSet<UISceneSession *> *)sceneSessions {
    // Called when the user discards a scene session.
    // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
    // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
}


@end
