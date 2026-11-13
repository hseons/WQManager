#import <Foundation/Foundation.h>
#import "WQMBubbleLayout.h"

static NSUInteger gFailures = 0;

static void WQMAssert(BOOL condition, NSString *message)
{
    if (condition) return;
    gFailures++;
    fprintf(stderr, "FAIL: %s\n", message.UTF8String);
}

static WQMBubbleLayoutItem *WQMItem(NSString *identifier, unsigned long long bytes)
{
    return [[WQMBubbleLayoutItem alloc] initWithIdentifier:identifier bytes:bytes];
}

static BOOL WQMSeparated(NSArray<WQMBubblePlacement *> *placements)
{
    for (NSUInteger i = 0; i < placements.count; i++) {
        for (NSUInteger j = i + 1; j < placements.count; j++) {
            WQMBubblePlacement *a = placements[i];
            WQMBubblePlacement *b = placements[j];
            CGFloat dx = a.center.x - b.center.x;
            CGFloat dy = a.center.y - b.center.y;
            CGFloat needed = a.radius + b.radius;
            if (dx * dx + dy * dy < needed * needed) return NO;
        }
    }
    return YES;
}

static BOOL WQMInside(NSArray<WQMBubblePlacement *> *placements, CGSize size)
{
    for (WQMBubblePlacement *placement in placements) {
        if (placement.center.x - placement.radius < -0.01) return NO;
        if (placement.center.y - placement.radius < -0.01) return NO;
        if (placement.center.x + placement.radius > size.width + 0.01) return NO;
        if (placement.center.y + placement.radius > size.height + 0.01) return NO;
    }
    return YES;
}

int main(void)
{
    @autoreleasepool {
        CGSize canvas = CGSizeMake(360, 420);

        // The largest bubble is in the middle and areas follow the byte shares.
        NSArray<WQMBubbleLayoutItem *> *items = @[
            WQMItem(@"documents", 600),
            WQMItem(@"library", 300),
            WQMItem(@"tmp", 100),
        ];
        NSArray<WQMBubblePlacement *> *placements = [WQMBubbleLayout placementsForItems:items
                                                                                inSize:canvas
                                                                             fillRatio:0.6];
        WQMAssert(placements.count == 3, @"every item should get a placement");
        WQMBubblePlacement *largest = placements.firstObject;
        WQMAssert([largest.identifier isEqualToString:@"documents"], @"ties break by identifier, so the big one leads");
        CGRect box = CGRectNull;
        for (WQMBubblePlacement *placement in placements) {
            CGRect circle = CGRectMake(placement.center.x - placement.radius,
                                       placement.center.y - placement.radius,
                                       placement.radius * 2, placement.radius * 2);
            box = CGRectIsNull(box) ? circle : CGRectUnion(box, circle);
        }
        WQMAssert(fabs(CGRectGetMidX(box) - canvas.width / 2) < 1.0 &&
                  fabs(CGRectGetMidY(box) - canvas.height / 2) < 1.0,
                  @"the bubble cluster should be centered in the canvas");
        WQMAssert(WQMSeparated(placements), @"bubbles must not overlap");
        WQMAssert(WQMInside(placements, canvas), @"bubbles must stay inside the canvas");

        double areaLarge = M_PI * pow(largest.radius, 2);
        WQMBubblePlacement *small = placements.lastObject;
        double areaSmall = M_PI * pow(small.radius, 2);
        WQMAssert(areaLarge / areaSmall > 4.0,
                  @"a six-times larger item should be clearly larger in area");

        // Many items: the tail folds into one bucket and the total bytes survive.
        NSMutableArray<WQMBubbleLayoutItem *> *many = [NSMutableArray new];
        unsigned long long total = 0;
        for (NSUInteger i = 0; i < 40; i++) {
            unsigned long long bytes = (40 - i) * 1000ULL;
            total += bytes;
            [many addObject:WQMItem([NSString stringWithFormat:@"item-%lu", (unsigned long)i], bytes)];
        }
        NSArray<WQMBubbleLayoutItem *> *folded = [WQMBubbleLayout foldedItems:many
                                                                       inSize:canvas
                                                                     maxCount:8
                                                                    minRadius:24
                                                                    fillRatio:0.6
                                                              otherIdentifier:@"other"];
        WQMAssert(folded.count <= 9, @"folded list should keep at most maxCount plus the bucket");
        WQMBubbleLayoutItem *bucket = folded.lastObject;
        WQMAssert([bucket.identifier isEqualToString:@"other"], @"the bucket should be last");
        WQMAssert(bucket.foldedCount > 1, @"the bucket should remember how many items it stands for");
        unsigned long long sum = 0;
        for (WQMBubbleLayoutItem *item in folded) sum += item.bytes;
        WQMAssert(sum == total, @"folding must not lose bytes");
        NSArray<WQMBubblePlacement *> *foldedPlacements = [WQMBubbleLayout placementsForItems:folded
                                                                                        inSize:canvas
                                                                                     fillRatio:0.6];
        WQMAssert(foldedPlacements.count == folded.count,
                  @"every folded item should be placed");
        WQMBubbleLayoutItem *biggest = folded.firstObject;
        for (WQMBubbleLayoutItem *item in folded) {
            if (item.bytes > biggest.bytes) biggest = item;
        }
        WQMAssert([foldedPlacements.firstObject.identifier isEqualToString:biggest.identifier],
                  @"the largest folded item should own the centre bubble");
        WQMAssert(WQMSeparated(foldedPlacements), @"folded bubbles must not overlap");

        // Empty and zero-byte items are dropped instead of drawn.
        NSArray<WQMBubbleLayoutItem *> *nothing = [WQMBubbleLayout foldedItems:@[WQMItem(@"empty", 0)]
                                                                        inSize:canvas
                                                                      maxCount:8
                                                                     minRadius:24
                                                                     fillRatio:0.6
                                                               otherIdentifier:@"other"];
        WQMAssert(nothing.count == 0, @"zero-byte items should not be drawn");
        WQMAssert([WQMBubbleLayout placementsForItems:@[] inSize:canvas fillRatio:0.6].count == 0,
                  @"no items means no placements");

        // A single item fills the middle without crashing on tiny canvases.
        NSArray<WQMBubblePlacement *> *one = [WQMBubbleLayout placementsForItems:@[WQMItem(@"only", 1)]
                                                                         inSize:CGSizeMake(80, 80)
                                                                      fillRatio:0.6];
        WQMAssert(one.count == 1 && one.firstObject.radius > 0, @"a tiny canvas still yields a bubble");

        if (gFailures == 0) {
            fprintf(stdout, "WQMBubbleLayoutTests: all checks passed\n");
            return 0;
        }
        fprintf(stderr, "WQMBubbleLayoutTests: %lu failure(s)\n", (unsigned long)gFailures);
        return 1;
    }
}
