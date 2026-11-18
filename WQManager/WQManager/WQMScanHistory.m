#import "WQMScanHistory.h"
#import "WQMAppModel.h"

static NSString *gWQMHistoryPath;
static NSArray<NSDictionary *> *gWQMSnapshots;
@implementation WQMScanHistory
+ (NSString *)storagePath
{
    if (gWQMHistoryPath) return gWQMHistoryPath;
    return [[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject
             stringByAppendingPathComponent:@"WQManager"] stringByAppendingPathComponent:@"ScanHistory.plist"];
}
+ (void)setStoragePathForTesting:(NSString *)path { @synchronized(self) { gWQMHistoryPath = [path copy]; gWQMSnapshots = nil; } }
+ (NSArray<NSDictionary *> *)snapshots
{
    if (gWQMSnapshots) return gWQMSnapshots;
    NSArray *stored = [NSArray arrayWithContentsOfFile:self.storagePath];
    if (![stored isKindOfClass:NSArray.class]) return @[];
    NSMutableArray *result = [NSMutableArray new];
    for (id row in stored) {
        if (![row isKindOfClass:NSDictionary.class] || ![row[@"Date"] isKindOfClass:NSDate.class] ||
            ![row[@"Apps"] isKindOfClass:NSDictionary.class]) continue;
        [result addObject:row];
    }
    gWQMSnapshots = result.count > 60 ? [result subarrayWithRange:NSMakeRange(result.count - 60, 60)] : [result copy];
    return gWQMSnapshots;
}
+ (NSArray<NSDictionary *> *)totalSamples
{
    @synchronized(self) {
        NSMutableArray *samples = [NSMutableArray new];
        for (NSDictionary *snapshot in self.snapshots) {
            unsigned long long total = 0;
            NSUInteger measured = 0;
            for (id entry in [snapshot[@"Apps"] allValues]) {
                if (![entry isKindOfClass:NSDictionary.class] || ![entry[@"Bytes"] isKindOfClass:NSNumber.class]) continue;
                total += [entry[@"Bytes"] unsignedLongLongValue];
                measured++;
            }
            if (!measured) continue;
            [samples addObject:@{@"Date": snapshot[@"Date"], @"Bytes": @(total), @"AppCount": @(measured)}];
        }
        return samples;
    }
}
+ (void)recordApps:(NSArray<WQMAppModel *> *)apps atDate:(NSDate *)date
{
    @synchronized(self) {
        NSMutableDictionary *entries = [NSMutableDictionary new];
        for (WQMAppModel *app in apps) {
            if (!app.sizeKnown || !app.identityKnown || !app.accessAvailable || !app.bundleIdentifier.length) continue;
            entries[app.bundleIdentifier] = @{@"Bytes": @(app.dataSize), @"Device": @(app.containerDevice), @"Inode": @(app.containerInode)};
        }
        if (!apps.count) return;
        NSMutableArray *snapshots = [self.snapshots mutableCopy];
        [snapshots addObject:@{@"Date": date, @"Apps": entries}];
        if (snapshots.count > 60) [snapshots removeObjectsInRange:NSMakeRange(0, snapshots.count - 60)];
        NSString *path = self.storagePath;
        [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent
                              withIntermediateDirectories:YES attributes:nil error:nil];
        if ([snapshots writeToFile:path atomically:YES]) gWQMSnapshots = [snapshots copy];
    }
}
+ (NSArray<NSDictionary *> *)samplesForApp:(WQMAppModel *)app
{
    @synchronized(self) {
        NSMutableArray *samples = [NSMutableArray new];
        for (NSDictionary *snapshot in self.snapshots) {
            id entry = snapshot[@"Apps"][app.bundleIdentifier];
            // Start a new series after an absent measurement or container change.
            if (![entry isKindOfClass:NSDictionary.class] ||
                ![entry[@"Bytes"] isKindOfClass:NSNumber.class] ||
                ![entry[@"Device"] isKindOfClass:NSNumber.class] || ![entry[@"Inode"] isKindOfClass:NSNumber.class] ||
                [entry[@"Device"] unsignedLongLongValue] != (unsigned long long)app.containerDevice ||
                [entry[@"Inode"] unsignedLongLongValue] != (unsigned long long)app.containerInode) {
                [samples removeAllObjects]; continue;
            }
            [samples addObject:@{@"Date": snapshot[@"Date"], @"Bytes": entry[@"Bytes"]}];
        }
        return samples;
    }
}
+ (NSNumber *)changeForApp:(WQMAppModel *)app
{
    if (!app.sizeKnown || !app.identityKnown || !app.accessAvailable) return nil;
    NSArray *samples = [self samplesForApp:app];
    if (samples.count < 2) return nil;
    unsigned long long before = [samples[samples.count - 2][@"Bytes"] unsignedLongLongValue];
    unsigned long long after = [samples.lastObject[@"Bytes"] unsignedLongLongValue];
    if (before > LLONG_MAX || after > LLONG_MAX) return nil;
    return @((long long)after - (long long)before);
}
+ (NSNumber *)changeForApp:(WQMAppModel *)app overDays:(NSInteger)days
{
    if (days <= 0) return [self changeForApp:app];
    if (!app.sizeKnown || !app.identityKnown || !app.accessAvailable) return nil;
    NSArray<NSDictionary *> *samples = [self samplesForApp:app];
    if (samples.count < 2) return nil;
    NSDate *latestDate = samples.lastObject[@"Date"];
    NSDate *cutoff = [latestDate dateByAddingTimeInterval:-(NSTimeInterval)days * 24 * 60 * 60];
    NSUInteger baselineIndex = 0;
    while (baselineIndex < samples.count &&
           [samples[baselineIndex][@"Date"] compare:cutoff] == NSOrderedAscending) {
        baselineIndex++;
    }
    // Only the newest sample falls inside the window: there is nothing to compare.
    if (baselineIndex >= samples.count - 1) return nil;
    unsigned long long before = [samples[baselineIndex][@"Bytes"] unsignedLongLongValue];
    unsigned long long after = [samples.lastObject[@"Bytes"] unsignedLongLongValue];
    if (before > LLONG_MAX || after > LLONG_MAX) return nil;
    return @((long long)after - (long long)before);
}
@end
