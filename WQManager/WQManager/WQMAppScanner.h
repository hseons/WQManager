#import <Foundation/Foundation.h>

@class WQMAppModel;
@class WQScanCancellation;

NS_ASSUME_NONNULL_BEGIN

@interface WQMAppScanResult : NSObject

@property (nonatomic, copy) NSArray<WQMAppModel *> *apps;
@property (nonatomic, copy) NSString *status;
@property (nonatomic) BOOL cancelled;
@property (nonatomic) BOOL fullScanDeclined;
@property (nonatomic) NSUInteger limitedCount;

@end

@interface WQMAppScanner : NSObject

/// Main-thread snapshots contain detached models; incomplete scans are never persisted.
- (void)scanWithCancellation:(WQScanCancellation *)cancellation
                    progress:(void (^_Nullable)(NSString *status))progress
                     partial:(void (^_Nullable)(NSArray<WQMAppModel *> *apps))partial
                  completion:(void (^)(WQMAppScanResult *result))completion;
- (void)refreshApp:(WQMAppModel *)app cancellation:(WQScanCancellation *)cancellation
       completion:(void (^)(WQMAppModel * _Nullable app))completion;

- (void)scanWithCancellation:(WQScanCancellation *)cancellation
                    progress:(void (^_Nullable)(NSString *status))progress
                  completion:(void (^)(WQMAppScanResult *result))completion;

@end

NS_ASSUME_NONNULL_END

