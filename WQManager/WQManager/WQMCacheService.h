#import <Foundation/Foundation.h>

@class WQScanCancellation;

NS_ASSUME_NONNULL_BEGIN

@interface WQMCleanTarget : NSObject
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSString *relativePath;
@property (nonatomic) BOOL existed;
@property (nonatomic) BOOL identityKnown;
@property (nonatomic) dev_t device;
@property (nonatomic) ino_t inode;
@property (nonatomic) mode_t mode;
@property (nonatomic) unsigned long long bytes;
@property (nonatomic) BOOL bytesKnown;
@property (nonatomic) BOOL limited;
@property (nonatomic) BOOL selected;
@end

@interface WQMCleanItem : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *bundleIdentifier;
@property (nonatomic, copy) NSString *containerPath;
@property (nonatomic) dev_t containerDevice;
@property (nonatomic) ino_t containerInode;
@property (nonatomic, copy) NSArray<WQMCleanTarget *> *targets;
@property (nonatomic) BOOL selected;
@property (nonatomic) BOOL eligible;
@property (nonatomic, copy) NSString *limitedReason;
@property (nonatomic, readonly) unsigned long long bytes;
@property (nonatomic, readonly) unsigned long long selectedBytes;
@end

@interface WQMCacheService : NSObject

- (void)scanWithCancellation:(WQScanCancellation *)cancellation
                    progress:(nullable void (^)(NSString *status))progress
                  completion:(void (^)(NSArray<WQMCleanItem *> *items,
                                       NSString *status))completion;

- (void)cleanItems:(NSArray<WQMCleanItem *> *)items
        cancellation:(WQScanCancellation *)cancellation
            progress:(nullable void (^)(NSString *status))progress
          completion:(void (^)(unsigned long long freed,
                               NSUInteger cleanedCount,
                               NSUInteger failedCount,
                               BOOL cancelled))completion;

@end

NS_ASSUME_NONNULL_END

