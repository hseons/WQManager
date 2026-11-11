#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const WQMBackupStoreDidChangeNotification;

@interface WQMBackupRecord : NSObject

@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSString *bundleIdentifier;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *scopeName;
@property (nonatomic, copy) NSString *scopeCode;
@property (nonatomic, copy) NSString *reason;
@property (nonatomic, copy) NSArray<NSString *> *parts;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *partHashes;
@property (nonatomic, copy) NSString *systemVersion;
@property (nonatomic, strong) NSDate *createdAt;
@property (nonatomic) unsigned long long totalBytes;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
+ (nullable instancetype)recordAtPath:(NSString *)path error:(NSString *_Nullable *_Nullable)error;

@end

@interface WQMBackupStore : NSObject

+ (NSString *)backupRoot;
+ (NSArray<WQMBackupRecord *> *)allBackups;
+ (void)setBackupRootForTesting:(nullable NSString *)root;

@end

NS_ASSUME_NONNULL_END

