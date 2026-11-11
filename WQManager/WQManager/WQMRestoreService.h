#import <Foundation/Foundation.h>

@class WQMAppModel;
@class WQMBackupRecord;

NS_ASSUME_NONNULL_BEGIN

@interface WQMRestoreService : NSObject

- (void)restoreBackup:(WQMBackupRecord *)backup
                toApp:(WQMAppModel *)app
             progress:(nullable void (^)(NSString *status))progress
           completion:(void (^)(BOOL success, NSString *message, NSError *_Nullable error))completion;

+ (nullable NSString *)activeRecoverySummary;
+ (void)recoverActiveRecoveryWithProgress:(nullable void (^)(NSString *status))progress
                                completion:(void (^)(BOOL success, NSString *message,
                                                     NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END

