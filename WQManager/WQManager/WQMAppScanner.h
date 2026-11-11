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

- (void)scanWithCancellation:(WQScanCancellation *)cancellation
                    progress:(void (^_Nullable)(NSString *status))progress
                  completion:(void (^)(WQMAppScanResult *result))completion;

@end

NS_ASSUME_NONNULL_END

