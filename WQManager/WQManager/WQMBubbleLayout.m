//
//  WQMBubbleLayout.m
//  WQManager
//

#import "WQMBubbleLayout.h"

@implementation WQMBubbleLayoutItem

- (instancetype)initWithIdentifier:(NSString *)identifier bytes:(unsigned long long)bytes
{
    self = [super init];
    if (self) {
        _identifier = [identifier copy];
        _bytes = bytes;
        _foldedCount = 1;
    }
    return self;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<bubble %@ %llu B x%lu>", self.identifier, self.bytes,
                                      (unsigned long)self.foldedCount];
}

@end

@implementation WQMBubblePlacement

- (instancetype)initWithIdentifier:(NSString *)identifier center:(CGPoint)center radius:(CGFloat)radius
{
    self = [super init];
    if (self) {
        _identifier = [identifier copy];
        _center = center;
        _radius = radius;
    }
    return self;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<placement %@ (%.1f, %.1f) r=%.1f>", self.identifier,
                                      self.center.x, self.center.y, self.radius];
}

@end

static BOOL WQMOverlapsAny(CGPoint center, CGFloat radius, NSArray<WQMBubblePlacement *> *placed)
{
    for (WQMBubblePlacement *other in placed) {
        CGFloat dx = other.center.x - center.x;
        CGFloat dy = other.center.y - center.y;
        CGFloat gap = radius + other.radius + 1.0;
        if (dx * dx + dy * dy < gap * gap) return YES;
    }
    return NO;
}

@implementation WQMBubbleLayout

+ (NSArray<WQMBubbleLayoutItem *> *)foldedItems:(NSArray<WQMBubbleLayoutItem *> *)items
                                         inSize:(CGSize)size
                                       maxCount:(NSUInteger)maxCount
                                      minRadius:(CGFloat)minRadius
                                      fillRatio:(CGFloat)fillRatio
                                otherIdentifier:(NSString *)otherIdentifier
{
    NSMutableArray<WQMBubbleLayoutItem *> *visible = [NSMutableArray new];
    for (WQMBubbleLayoutItem *item in items) {
        if (item.bytes > 0) [visible addObject:item];
    }
    [visible sortUsingComparator:^NSComparisonResult(WQMBubbleLayoutItem *a, WQMBubbleLayoutItem *b) {
        if (a.bytes != b.bytes) return a.bytes > b.bytes ? NSOrderedAscending : NSOrderedDescending;
        return [a.identifier localizedStandardCompare:b.identifier];
    }];

    unsigned long long foldedBytes = 0;
    NSUInteger foldedCount = 0;
    while (visible.count > 0) {
        NSArray<NSNumber *> *radii = [self radiiForItems:visible inSize:size fillRatio:fillRatio];
        BOOL overCount = visible.count > MAX((NSUInteger)1, maxCount);
        CGFloat smallest = radii.lastObject.doubleValue;
        if (!overCount && (minRadius <= 0 || smallest >= minRadius)) break;
        WQMBubbleLayoutItem *dropped = visible.lastObject;
        foldedBytes += dropped.bytes;
        foldedCount += dropped.foldedCount;
        [visible removeLastObject];
    }

    if (foldedCount > 0) {
        WQMBubbleLayoutItem *bucket = [[WQMBubbleLayoutItem alloc] initWithIdentifier:otherIdentifier
                                                                               bytes:foldedBytes];
        bucket.foldedCount = foldedCount;
        [visible addObject:bucket];
    }
    return visible;
}

+ (NSArray<NSNumber *> *)radiiForItems:(NSArray<WQMBubbleLayoutItem *> *)items
                                inSize:(CGSize)size
                             fillRatio:(CGFloat)fillRatio
{
    unsigned long long total = 0;
    for (WQMBubbleLayoutItem *item in items) total += item.bytes;
    CGFloat usable = MAX(size.width, 0) * MAX(size.height, 0) * MAX(MIN(fillRatio, 1.0), 0.01);
    NSMutableArray<NSNumber *> *radii = [NSMutableArray arrayWithCapacity:items.count];
    if (total == 0 || usable <= 0) return radii;
    for (WQMBubbleLayoutItem *item in items) {
        double share = (double)item.bytes / (double)total;
        CGFloat radius = (CGFloat)sqrt(share * usable / M_PI);
        [radii addObject:@(radius)];
    }
    return radii;
}

+ (NSArray<WQMBubblePlacement *> *)placementsForItems:(NSArray<WQMBubbleLayoutItem *> *)items
                                               inSize:(CGSize)size
                                            fillRatio:(CGFloat)fillRatio
{
    if (items.count == 0 || size.width <= 0 || size.height <= 0) return @[];
    NSArray<WQMBubbleLayoutItem *> *ordered = [items sortedArrayUsingComparator:
        ^NSComparisonResult(WQMBubbleLayoutItem *a, WQMBubbleLayoutItem *b) {
            if (a.bytes != b.bytes) return a.bytes > b.bytes ? NSOrderedAscending : NSOrderedDescending;
            return [a.identifier localizedStandardCompare:b.identifier];
        }];

    NSArray<NSNumber *> *base = [self radiiForItems:ordered inSize:size fillRatio:fillRatio];
    for (NSUInteger attempt = 0; attempt <= 12; attempt++) {
        CGFloat scale = pow(0.88, (double)attempt);
        NSMutableArray<NSNumber *> *radii = [NSMutableArray arrayWithCapacity:base.count];
        for (NSNumber *value in base) {
            [radii addObject:@(MAX(value.doubleValue * scale, 0.75))];
        }
        NSArray<WQMBubblePlacement *> *placements = [self packOrdered:ordered radii:radii inSize:size];
        if (placements) return placements;
    }
    // Last resort: smallest possible equal circles on a grid, still no overlap.
    NSMutableArray<WQMBubblePlacement *> *fallback = [NSMutableArray new];
    NSUInteger count = ordered.count;
    CGFloat columns = ceil(sqrt((double)count));
    CGFloat cell = MIN(size.width, size.height) / MAX(columns, 1);
    CGFloat radius = MAX(cell * 0.42, 0.5);
    for (NSUInteger i = 0; i < count; i++) {
        CGFloat cx = (i % (NSUInteger)columns) * cell + cell / 2;
        CGFloat cy = (i / (NSUInteger)columns) * cell + cell / 2;
        CGPoint center = CGPointMake(MIN(cx, size.width - radius), MIN(cy, size.height - radius));
        center.x = MAX(center.x, radius);
        center.y = MAX(center.y, radius);
        [fallback addObject:[[WQMBubblePlacement alloc] initWithIdentifier:ordered[i].identifier
                                                                    center:center
                                                                    radius:radius]];
    }
    return fallback;
}

+ (nullable NSArray<WQMBubblePlacement *> *)packOrdered:(NSArray<WQMBubbleLayoutItem *> *)items
                                                  radii:(NSArray<NSNumber *> *)radii
                                                 inSize:(CGSize)size
{
    if (items.count == 0) return @[];
    NSMutableArray<WQMBubblePlacement *> *placed = [NSMutableArray new];
    CGFloat firstRadius = radii[0].doubleValue;
    if (firstRadius * 2 > MIN(size.width, size.height)) return nil;
    // Start in a corner, pack neighbours greedily next to the cluster, then
    // translate the whole cluster so it sits centered in the canvas.
    [placed addObject:[[WQMBubblePlacement alloc] initWithIdentifier:items[0].identifier
                                                              center:CGPointMake(firstRadius + 1, firstRadius + 1)
                                                              radius:firstRadius]];

    for (NSUInteger i = 1; i < items.count; i++) {
        CGFloat radius = radii[i].doubleValue;
        if (radius * 2 > MIN(size.width, size.height)) return nil;
        CGPoint centroid = CGPointZero;
        for (WQMBubblePlacement *placement in placed) {
            centroid.x += placement.center.x;
            centroid.y += placement.center.y;
        }
        centroid.x /= placed.count;
        centroid.y /= placed.count;

        CGFloat step = MAX(MIN(radius * 0.4, 6.0), 2.0);
        CGPoint best = CGPointZero;
        CGFloat bestDistance = CGFLOAT_MAX;
        BOOL found = NO;
        for (CGFloat y = radius; y <= size.height - radius + 0.01; y += step) {
            for (CGFloat x = radius; x <= size.width - radius + 0.01; x += step) {
                CGPoint candidate = CGPointMake(x, y);
                if (WQMOverlapsAny(candidate, radius, placed)) continue;
                CGFloat dx = candidate.x - centroid.x;
                CGFloat dy = candidate.y - centroid.y;
                CGFloat distance = dx * dx + dy * dy;
                if (distance < bestDistance) {
                    bestDistance = distance;
                    best = candidate;
                    found = YES;
                }
            }
        }
        if (!found) return nil;
        [placed addObject:[[WQMBubblePlacement alloc] initWithIdentifier:items[i].identifier
                                                                  center:best
                                                                  radius:radius]];
    }

    CGRect box = CGRectNull;
    for (WQMBubblePlacement *placement in placed) {
        CGRect circle = CGRectMake(placement.center.x - placement.radius,
                                   placement.center.y - placement.radius,
                                   placement.radius * 2, placement.radius * 2);
        box = CGRectIsNull(box) ? circle : CGRectUnion(box, circle);
    }
    if (box.size.width > size.width + 0.01 || box.size.height > size.height + 0.01) return nil;
    CGFloat dx = (size.width - box.size.width) / 2 - CGRectGetMinX(box);
    CGFloat dy = (size.height - box.size.height) / 2 - CGRectGetMinY(box);

    NSMutableArray<WQMBubblePlacement *> *centered = [NSMutableArray arrayWithCapacity:placed.count];
    for (WQMBubblePlacement *placement in placed) {
        CGPoint center = CGPointMake(placement.center.x + dx, placement.center.y + dy);
        [centered addObject:[[WQMBubblePlacement alloc] initWithIdentifier:placement.identifier
                                                                    center:center
                                                                    radius:placement.radius]];
    }
    return centered;
}
@end
