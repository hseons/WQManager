#import <Foundation/Foundation.h>
@class WQMAppModel;
NS_ASSUME_NONNULL_BEGIN
@interface WQMScanHistory : NSObject
+ (void)recordApps:(NSArray<WQMAppModel *> *)apps atDate:(NSDate *)date;
+ (NSArray<NSDictionary *> *)samplesForApp:(WQMAppModel *)app;
/// Sum of every known app size per snapshot. Snapshots without any measured app
/// are skipped, and apps missing from one scan simply do not contribute to it.
+ (NSArray<NSDictionary *> *)totalSamples;
/// nil means fewer than two comparable scans, unknown size, or a new container.
+ (nullable NSNumber *)changeForApp:(WQMAppModel *)app;
/// Change between the newest sample and the first sample at or after the
/// window start. nil when the series has only one sample inside the window.
+ (nullable NSNumber *)changeForApp:(WQMAppModel *)app overDays:(NSInteger)days;
+ (void)setStoragePathForTesting:(nullable NSString *)path;
@end
NS_ASSUME_NONNULL_END
