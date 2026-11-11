#import "WQMAppCache.h"
#import "WQMAppModel.h"
#import "WQMAppScanner.h"

#import <sys/stat.h>

static NSString *WQMAppCachePath(void)
{
    NSString *root = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                                                          NSUserDomainMask, YES).firstObject
                      stringByAppendingPathComponent:@"WQManager"];
    [NSFileManager.defaultManager createDirectoryAtPath:root
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:nil];
    return [root stringByAppendingPathComponent:@"AppIndex.plist"];
}

@implementation WQMAppCacheSnapshot
@end

@implementation WQMAppCache

+ (nullable WQMAppCacheSnapshot *)load
{
    NSDictionary *root = [NSDictionary dictionaryWithContentsOfFile:WQMAppCachePath()];
    if (![root isKindOfClass:NSDictionary.class] ||
        ![root[@"Format"] isEqual:@1] ||
        ![root[@"UpdatedAt"] isKindOfClass:NSDate.class] ||
        ![root[@"Apps"] isKindOfClass:NSArray.class]) {
        return nil;
    }

    NSMutableArray<WQMAppModel *> *apps = [NSMutableArray new];
    for (id value in root[@"Apps"]) {
        if (![value isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *entry = value;
        NSString *bundleID = entry[@"BundleID"];
        NSString *name = entry[@"DisplayName"];
        NSString *container = entry[@"Container"];
        if (![bundleID isKindOfClass:NSString.class] ||
            ![name isKindOfClass:NSString.class] ||
            ![container isKindOfClass:NSString.class] ||
            !container.isAbsolutePath) {
            continue;
        }
        WQMAppModel *app = [[WQMAppModel alloc] initWithBundleIdentifier:bundleID
                                                            displayName:name
                                                          containerPath:container
                                                               dataSize:[entry[@"DataSize"] unsignedLongLongValue]];
        app.accessAvailable = [entry[@"AccessAvailable"] boolValue];
        app.identityKnown = [entry[@"IdentityKnown"] boolValue];
        app.sizeKnown = [entry[@"SizeKnown"] boolValue];
        app.containerDevice = (dev_t)[entry[@"ContainerDevice"] unsignedLongLongValue];
        app.containerInode = (ino_t)[entry[@"ContainerInode"] unsignedLongLongValue];
        [apps addObject:app];
    }

    WQMAppCacheSnapshot *snapshot = [WQMAppCacheSnapshot new];
    snapshot.apps = apps;
    snapshot.updatedAt = root[@"UpdatedAt"];
    snapshot.status = [root[@"Status"] isKindOfClass:NSString.class] ? root[@"Status"] : @"";
    snapshot.limitedCount = [root[@"LimitedCount"] unsignedIntegerValue];
    return snapshot;
}

+ (void)saveResult:(WQMAppScanResult *)result
{
    if (!result || result.cancelled || result.apps.count == 0) return;
    NSMutableArray<NSDictionary *> *entries = [NSMutableArray arrayWithCapacity:result.apps.count];
    for (WQMAppModel *app in result.apps) {
        [entries addObject:@{
            @"BundleID": app.bundleIdentifier ?: @"",
            @"DisplayName": app.displayName ?: @"",
            @"Container": app.containerPath ?: @"",
            @"DataSize": @(app.dataSize),
            @"AccessAvailable": @(app.accessAvailable),
            @"IdentityKnown": @(app.identityKnown),
            @"SizeKnown": @(app.sizeKnown),
            @"ContainerDevice": @(app.containerDevice),
            @"ContainerInode": @(app.containerInode),
        }];
    }
    NSDictionary *root = @{
        @"Format": @1,
        @"UpdatedAt": NSDate.date,
        @"Status": result.status ?: @"",
        @"LimitedCount": @(result.limitedCount),
        @"Apps": entries,
    };
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:root
                                                               format:NSPropertyListBinaryFormat_v1_0
                                                              options:0
                                                                error:nil];
    [data writeToFile:WQMAppCachePath() options:NSDataWritingAtomic error:nil];
}

+ (void)clear
{
    [NSFileManager.defaultManager removeItemAtPath:WQMAppCachePath() error:nil];
}

@end

