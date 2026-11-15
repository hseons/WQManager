#import <Foundation/Foundation.h>
@class WQMAppModel;
NS_ASSUME_NONNULL_BEGIN
@interface WQMScanHistory : NSObject
+ (void)recordApps:(NSArray<WQMAppModel *> *)apps atDate:(NSDate *)date;
+ (NSArray<NSDictionary *> *)samplesForApp:(WQMAppModel *)app;
/// nil means fewer than two comparable scans, unknown size, or a new container.
+ (nullable NSNumber *)changeForApp:(WQMAppModel *)app;
+ (void)setStoragePathForTesting:(nullable NSString *)path;
@end
NS_ASSUME_NONNULL_END
