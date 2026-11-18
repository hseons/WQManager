#import <Foundation/Foundation.h>
#import "WQMFileCatalog.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, WQMFileCategory) {
    WQMFileCategoryAll = 0,
    WQMFileCategoryImage,
    WQMFileCategoryVideo,
    WQMFileCategoryAudio,
    WQMFileCategoryDocument,
    WQMFileCategoryArchive,
    WQMFileCategoryOther,
};

typedef NS_ENUM(NSInteger, WQMFileSortOrder) {
    WQMFileSortOrderPath = 0,
    WQMFileSortOrderSizeDescending,
    WQMFileSortOrderNewest,
};

@interface WQMAuditFile : NSObject

@property (nonatomic, copy) NSString *appName;
@property (nonatomic, copy) NSString *bundleIdentifier;
@property (nonatomic, copy) NSString *containerPath;
@property (nonatomic, copy) NSString *relativePath;
@property (nonatomic) unsigned long long bytes;
@property (nonatomic, strong) NSDate *modifiedAt;
@property (nonatomic, strong) WQMFileEntry *entry;

@property (nonatomic, readonly) NSString *absolutePath;
@property (nonatomic, readonly) WQMFileCategory category;

@end

@interface WQMFileAudit : NSObject

+ (WQMFileCategory)categoryForPath:(NSString *)path;
+ (BOOL)isUserDataRelativePath:(NSString *)relativePath;
+ (NSArray<WQMAuditFile *> *)filesFromCatalog:(WQMFileCatalog *)catalog
                                     appName:(NSString *)appName
                            bundleIdentifier:(NSString *)bundleIdentifier
                               containerPath:(NSString *)containerPath
                                includeCaches:(BOOL)includeCaches;

+ (NSArray<WQMAuditFile *> *)largeFiles:(NSArray<WQMAuditFile *> *)files
                          minimumBytes:(unsigned long long)minimumBytes
                                 limit:(NSUInteger)limit;

/// Returns exact-size candidate groups inside one app. Files in different
/// apps are never grouped because one app's copy cannot replace another's.
/// This is deliberately only a first filter; callers must compare SHA-256
/// content before presenting them as duplicates.
+ (NSArray<NSArray<WQMAuditFile *> *> *)duplicateSizeBuckets:(NSArray<WQMAuditFile *> *)files
                                                 minimumBytes:(unsigned long long)minimumBytes;

+ (BOOL)fileVersion:(NSDictionary<NSString *, NSNumber *> *)version
     matchesEntry:(WQMFileEntry *)entry;

/// Stable identity of one audit file inside its app. Used for duplicate
/// selection; two apps may hold the same relative path.
+ (NSString *)duplicateSelectionKeyForFile:(WQMAuditFile *)file;

/// YES when every confirmed duplicate group keeps at least one file out of the
/// trash. Size buckets never span apps, so "one per group" always means
/// "one per app".
+ (BOOL)duplicateSelectionKeepsOnePerGroup:(NSArray<NSArray<WQMAuditFile *> *> *)groups
                              selectedKeys:(NSSet<NSString *> *)selectedKeys;

/// Case- and diacritic-insensitive match over the app name and relative path.
/// Every whitespace-separated token must appear somewhere in that combined text,
/// so "photo documents" matches "Documents/photo.jpg".
+ (BOOL)file:(WQMAuditFile *)file matchesQuery:(nullable NSString *)query;

/// Filters, sorts and caps a flat list for the global file search. `limit` of 0
/// returns every match. `WQMFileCategoryAll` and a zero `minimumBytes` disable
/// the corresponding filter.
+ (NSArray<WQMAuditFile *> *)searchFiles:(NSArray<WQMAuditFile *> *)files
                                   query:(nullable NSString *)query
                                category:(WQMFileCategory)category
                            minimumBytes:(unsigned long long)minimumBytes
                                    sort:(WQMFileSortOrder)sort
                                   limit:(NSUInteger)limit;

@end

NS_ASSUME_NONNULL_END
