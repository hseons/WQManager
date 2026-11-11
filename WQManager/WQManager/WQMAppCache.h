#import <Foundation/Foundation.h>

@class WQMAppModel;
@class WQMAppScanResult;

NS_ASSUME_NONNULL_BEGIN

@interface WQMAppCacheSnapshot : NSObject

@property (nonatomic, copy) NSArray<WQMAppModel *> *apps;
@property (nonatomic, copy) NSString *status;
@property (nonatomic, strong) NSDate *updatedAt;
@property (nonatomic) NSUInteger limitedCount;

@end

@interface WQMAppCache : NSObject

+ (nullable WQMAppCacheSnapshot *)load;
+ (void)saveResult:(WQMAppScanResult *)result;
+ (void)clear;

@end

NS_ASSUME_NONNULL_END

