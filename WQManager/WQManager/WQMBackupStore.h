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
// Size/mtime/inode/digest of the manifest captured when this record was loaded.
// Restore compares it against a fresh load to reuse the safety backup's hashes
// without re-reading every part.
@property (nonatomic, copy, nullable) NSString *manifestFingerprint;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
+ (nullable instancetype)recordAtPath:(NSString *)path error:(NSString *_Nullable *_Nullable)error;

@end

/// Every backup of one app, newest first. The backup screen lists one section
/// per group so several backups of the same app stay together.
@interface WQMBackupGroup : NSObject

@property (nonatomic, copy) NSString *bundleIdentifier;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSArray<WQMBackupRecord *> *backups;
@property (nonatomic, readonly) unsigned long long totalBytes;
@property (nonatomic, readonly) NSDate *latestAt;

@end

@interface WQMBackupStore : NSObject

+ (NSString *)backupRoot;
+ (NSArray<WQMBackupRecord *> *)allBackups;
+ (void)setBackupRootForTesting:(nullable NSString *)root;

/// Groups records by Bundle ID, keeping each group's records newest first and
/// ordering the groups by their most recent backup.
+ (NSArray<WQMBackupGroup *> *)groupsForRecords:(NSArray<WQMBackupRecord *> *)records;

@end

NS_ASSUME_NONNULL_END

