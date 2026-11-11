#import <Foundation/Foundation.h>

@class WQMAppModel;
@class WQMBackupRecord;

NS_ASSUME_NONNULL_BEGIN

@interface WQMBackupService : NSObject

- (void)backupApp:(WQMAppModel *)app
            scope:(NSInteger)scope
           reason:(nullable NSString *)reason
         progress:(nullable void (^)(NSString *status))progress
       completion:(void (^)(WQMBackupRecord *_Nullable backup, NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END

