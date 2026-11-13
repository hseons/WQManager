//
//  WQMTrashStore.h
//  WQManager
//
//  The Space Lens recycle bin. Deletions move items here instead of unlinking
//  them, so a mis-tap is recoverable until the user empties the bin.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface WQMTrashItem : NSObject

@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *path;
@property (nonatomic) unsigned long long bytes;
@property (nonatomic) BOOL directory;
/// Where the item used to live. Nil for sessions recorded before manifests.
@property (nonatomic, copy, nullable) NSString *originalPath;

@end

@interface WQMTrashSession : NSObject

@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *path;
/// Container directory the items were removed from, when the manifest is known.
@property (nonatomic, copy, nullable) NSString *sourcePath;
@property (nonatomic, strong) NSDate *createdAt;
@property (nonatomic, copy) NSArray<WQMTrashItem *> *items;
@property (nonatomic) unsigned long long totalBytes;

@end

@interface WQMTrashStore : NSObject

+ (NSString *)rootPath;
+ (NSArray<WQMTrashSession *> *)sessions;
+ (NSUInteger)itemCount;
+ (unsigned long long)totalBytes;

/// Creates (and returns) a fresh session directory for a deletion from `level`.
+ (nullable NSString *)createSessionForLevel:(nullable NSString *)level;
/// Writes manifest.plist so the bin can restore items to their original place.
/// Each entry needs Name, Bytes and Directory keys.
+ (void)recordSession:(NSString *)sessionPath
               source:(nullable NSString *)sourcePath
                items:(NSArray<NSDictionary<NSString *, id> *> *)items;

+ (BOOL)restoreItem:(WQMTrashItem *)item error:(NSError *_Nullable *_Nullable)error;
+ (void)removeItem:(WQMTrashItem *)item;
+ (void)emptyAll;

@end

NS_ASSUME_NONNULL_END
