#import <Foundation/Foundation.h>
#import "WQMAppModel.h"

static NSUInteger gFailures = 0;

static void WQMAssert(BOOL condition, NSString *message)
{
    if (condition) return;
    gFailures++;
    fprintf(stderr, "FAIL: %s\n", message.UTF8String);
}

static WQMAppModel *WQMApp(NSString *name, NSString *bundle, unsigned long long size, BOOL sizeKnown)
{
    WQMAppModel *app = [[WQMAppModel alloc] initWithBundleIdentifier:bundle
                                                         displayName:name
                                                       containerPath:[@"/tmp" stringByAppendingPathComponent:name]
                                                            dataSize:size];
    app.sizeKnown = sizeKnown;
    return app;
}

static NSArray<NSString *> *WQMNames(NSArray<WQMAppModel *> *apps)
{
    NSMutableArray<NSString *> *names = [NSMutableArray new];
    for (WQMAppModel *app in apps) [names addObject:app.displayName];
    return names;
}

int main(void)
{
    @autoreleasepool {
        WQMAppModel *small = WQMApp(@"Alpha", @"com.example.alpha", 100, YES);
        WQMAppModel *big = WQMApp(@"beta", @"com.example.beta", 900, YES);
        WQMAppModel *unknown = WQMApp(@"Gamma", @"com.example.gamma", 0, NO);
        NSArray<WQMAppModel *> *apps = @[small, big, unknown];

        NSArray<WQMAppModel *> *defaultOrder = [WQMAppModel apps:apps sortedByOrder:WQMAppSortOrderDefault];
        WQMAssert(defaultOrder == apps, @"default order should keep the scan order untouched");

        NSArray<WQMAppModel *> *byName = [WQMAppModel apps:apps sortedByOrder:WQMAppSortOrderName];
        WQMAssert([WQMNames(byName) isEqualToArray:(@[@"Alpha", @"beta", @"Gamma"])],
                  @"name order should be case insensitive and locale aware");

        NSArray<WQMAppModel *> *bySize = [WQMAppModel apps:apps sortedByOrder:WQMAppSortOrderSizeDescending];
        WQMAssert([WQMNames(bySize) isEqualToArray:(@[@"beta", @"Alpha", @"Gamma"])],
                  @"size order should be descending with unknown sizes last");

        NSArray<WQMAppModel *> *single = [WQMAppModel apps:@[small] sortedByOrder:WQMAppSortOrderSizeDescending];
        WQMAssert(single.count == 1 && single.firstObject == small, @"a single app should pass through");

        WQMAppModel *twinA = WQMApp(@"Alpha", @"com.example.alpha", 500, YES);
        WQMAppModel *twinB = WQMApp(@"Alpha", @"com.example.other", 500, YES);
        NSArray<WQMAppModel *> *ties = [WQMAppModel apps:@[twinB, twinA]
                                            sortedByOrder:WQMAppSortOrderSizeDescending];
        WQMAssert([WQMNames(ties) isEqualToArray:(@[@"Alpha", @"Alpha"])],
                  @"equal sizes should fall back to the bundle identifier");
        WQMAssert([ties.firstObject.bundleIdentifier isEqualToString:@"com.example.alpha"],
                  @"tie breaker should be deterministic");
    }

    if (gFailures) {
        fprintf(stderr, "%lu sort assertion(s) failed\n", (unsigned long)gFailures);
        return 1;
    }
    printf("WQMAppSortTests passed\n");
    return 0;
}
