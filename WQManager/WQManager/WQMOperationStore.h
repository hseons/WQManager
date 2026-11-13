#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const WQMOperationStoreDidChangeNotification;

typedef NS_ENUM(NSInteger, WQMOperationKind) {
    WQMOperationKindBackup = 0,
    WQMOperationKindSafetyBackup,
    WQMOperationKindRestore,
    WQMOperationKindRollback,
    WQMOperationKindRecovery,
    WQMOperationKindExport,
    WQMOperationKindImport,
    WQMOperationKindDeleteBackup,
    WQMOperationKindCleanCache,
    WQMOperationKindDeleteFiles,
};

typedef NS_ENUM(NSInteger, WQMOperationStatus) {
    WQMOperationStatusRunning = 0,
    WQMOperationStatusSuccess,
    WQMOperationStatusFailure,
    WQMOperationStatusRolledBack,
    WQMOperationStatusInterrupted,
    WQMOperationStatusCancelled,
};

@interface WQMOperationRecord : NSObject

@property (nonatomic, copy) NSString *identifier;
@property (nonatomic) WQMOperationKind kind;
@property (nonatomic) WQMOperationStatus status;
@property (nonatomic, copy) NSString *appName;
@property (nonatomic, copy) NSString *bundleIdentifier;
@property (nonatomic, copy) NSString *scope;
@property (nonatomic, copy) NSString *reason;
@property (nonatomic, copy) NSString *message;
@property (nonatomic, copy) NSString *errorMessage;
@property (nonatomic, copy) NSString *backupPath;
@property (nonatomic, copy) NSString *safetyBackupPath;
@property (nonatomic, copy) NSString *journalPath;
@property (nonatomic) unsigned long long bytes;
@property (nonatomic, strong) NSDate *startedAt;
@property (nonatomic, strong, nullable) NSDate *finishedAt;

+ (NSString *)displayNameForKind:(WQMOperationKind)kind;
+ (NSString *)displayNameForStatus:(WQMOperationStatus)status;

@end

@interface WQMOperationStore : NSObject

+ (WQMOperationRecord *)beginOperation:(WQMOperationKind)kind
                               appName:(NSString *)appName
                      bundleIdentifier:(NSString *)bundleIdentifier;
+ (void)updateRecord:(WQMOperationRecord *)record;
+ (NSArray<WQMOperationRecord *> *)allOperations;
+ (void)clear;

/// Comma separated export of the given records, UTF-8 with a byte order mark so
/// spreadsheet apps on both macOS and Windows open the Chinese columns directly.
+ (NSString *)CSVExportForRecords:(NSArray<WQMOperationRecord *> *)records;
/// Suggested file name for an export taken at `date`, e.g. WQManager-history-20261113-104100.csv
+ (NSString *)CSVExportFileNameForDate:(NSDate *)date;

+ (void)setStorageRootForTesting:(nullable NSString *)root;

@end

NS_ASSUME_NONNULL_END

