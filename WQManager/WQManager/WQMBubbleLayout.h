//
//  WQMBubbleLayout.h
//  WQManager
//
//  Bubble geometry for the space lens. Pure computation: no UIKit, no I/O,
//  so the packing rules are unit tested.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@interface WQMBubbleLayoutItem : NSObject

/// Stable identifier (used to map a placement back to the thing it stands for).
@property (nonatomic, copy) NSString *identifier;
/// What this bubble is worth on disk.
@property (nonatomic) unsigned long long bytes;
/// How many original items this bubble stands for (1 unless folded).
@property (nonatomic) NSUInteger foldedCount;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)initWithIdentifier:(NSString *)identifier bytes:(unsigned long long)bytes
    NS_DESIGNATED_INITIALIZER;

@end

@interface WQMBubblePlacement : NSObject

@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, readonly) CGPoint center;
@property (nonatomic, readonly) CGFloat radius;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)initWithIdentifier:(NSString *)identifier center:(CGPoint)center radius:(CGFloat)radius
    NS_DESIGNATED_INITIALIZER;

@end

@interface WQMBubbleLayout : NSObject

/// Keeps the largest `maxCount` items, then folds everything smaller than
/// `minRadius` (given the area that `size` and `fillRatio` allow) and everything
/// past `maxCount` into a single bucket with `otherIdentifier` and the summed
/// bytes. Items with no bytes are dropped, because they cannot be drawn.
+ (NSArray<WQMBubbleLayoutItem *> *)foldedItems:(NSArray<WQMBubbleLayoutItem *> *)items
                                         inSize:(CGSize)size
                                       maxCount:(NSUInteger)maxCount
                                      minRadius:(CGFloat)minRadius
                                      fillRatio:(CGFloat)fillRatio
                                otherIdentifier:(NSString *)otherIdentifier;

/// Bubble area is proportional to bytes; the largest sits in the middle and the
/// rest are packed around it without overlapping. Always returns one placement
/// per item, shrinking the whole set if the requested fill ratio cannot fit.
+ (NSArray<WQMBubblePlacement *> *)placementsForItems:(NSArray<WQMBubbleLayoutItem *> *)items
                                               inSize:(CGSize)size
                                            fillRatio:(CGFloat)fillRatio;

@end

NS_ASSUME_NONNULL_END
