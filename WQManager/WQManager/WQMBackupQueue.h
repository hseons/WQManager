#import <Foundation/Foundation.h>
@class WQMAppModel, WQMBackupRecord;
NS_ASSUME_NONNULL_BEGIN
typedef NS_ENUM(NSInteger, WQMBackupJobStatus) {
    WQMBackupJobPending, WQMBackupJobRunning, WQMBackupJobSucceeded, WQMBackupJobFailed, WQMBackupJobCancelled, WQMBackupJobInterrupted
};
@interface WQMBackupJob : NSObject
@property (nonatomic, strong) WQMAppModel *app;
@property (nonatomic) WQMBackupJobStatus status;
@property (nonatomic, copy) NSString *message;
@end
typedef void (^WQMBackupQueueExecutor)(WQMAppModel *app, NSInteger scope, void (^progress)(NSString *), void (^completion)(BOOL, NSString *));
/// Main-thread-owned serial queue. Stopping finishes the current atomic backup.
@interface WQMBackupQueue : NSObject
@property (nonatomic, copy, readonly) NSArray<WQMBackupJob *> *jobs;
@property (nonatomic, readonly, getter=isRunning) BOOL running;
@property (nonatomic, readonly) NSInteger scope;
@property (nonatomic) BOOL suspended;
@property (nonatomic, copy, readonly, nullable) NSString *persistenceError;
@property (nonatomic, copy, nullable) void (^didChange)(void);
@property (nonatomic, copy, nullable) void (^didFinish)(void);
- (instancetype)initWithExecutor:(WQMBackupQueueExecutor)executor;
- (instancetype)initWithExecutor:(WQMBackupQueueExecutor)executor storagePath:(nullable NSString *)path;
- (void)resolveApps:(NSArray<WQMAppModel *> *)apps;
- (BOOL)resumeRemaining;
- (BOOL)startApps:(NSArray<WQMAppModel *> *)apps scope:(NSInteger)scope;
- (BOOL)retryFailures;
- (void)stopRemaining;
@end
NS_ASSUME_NONNULL_END
