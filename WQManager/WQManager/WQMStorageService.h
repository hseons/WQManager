#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Size breakdown of the data WQManager keeps in its own container.
@interface WQMStorageBreakdown : NSObject

@property (nonatomic) unsigned long long backupBytes;
@property (nonatomic) NSUInteger backupCount;
@property (nonatomic) unsigned long long safetyBytes;
@property (nonatomic) NSUInteger safetyCount;
@property (nonatomic) unsigned long long invalidBytes;
@property (nonatomic) NSUInteger invalidCount;
@property (nonatomic) unsigned long long incompleteBytes;
@property (nonatomic) NSUInteger incompleteCount;
@property (nonatomic) unsigned long long temporaryBytes;
@property (nonatomic) NSUInteger temporaryCount;
@property (nonatomic) unsigned long long cacheBytes;

@end

typedef NS_OPTIONS(NSUInteger, WQMStorageCleanupOptions) {
    WQMStorageCleanupInvalid = 1 << 0,
    WQMStorageCleanupIncomplete = 1 << 1,
    WQMStorageCleanupTemporary = 1 << 2,
};

/// Inspects and reclaims space used by backups, interrupted backups and
/// import/export staging. All operations are synchronous; call from a
/// background queue. A backup or restore must not be running.
@interface WQMStorageService : NSObject

+ (WQMStorageBreakdown *)breakdown;

/// Deletes backup directories that fail validation, `.incomplete-*` staging
/// directories and leftover WQMImport-*/WQMExport-* directories. Paths in
/// `protectedPaths` are never touched (paths referenced by an interrupted
/// restore).
+ (BOOL)cleanupWithOptions:(WQMStorageCleanupOptions)options
                   excluding:(NSSet<NSString *> *)protectedPaths
                  freedBytes:(nullable unsigned long long *)freedBytes
                       error:(NSError *_Nullable *_Nullable)error;

/// Keeps the newest `keep` automatic safety backups per app and deletes older
/// ones. Returns the number of removed backups.
+ (NSUInteger)pruneSafetyBackupsKeeping:(NSUInteger)keep
                              excluding:(NSSet<NSString *> *)protectedPaths
                            deletedBytes:(nullable unsigned long long *)deletedBytes;

+ (void)setRootsForTesting:(nullable NSString *)backupRoot
             temporaryRoot:(nullable NSString *)temporaryRoot;

@end

FOUNDATION_EXPORT BOOL WQMStorageReasonIsSafetyBackup(NSString *reason);

NS_ASSUME_NONNULL_END
