#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface WQMFileCatalogCancellation : NSObject
@property (atomic, readonly, getter=isCancelled) BOOL cancelled;
- (void)cancel;
@end
@interface WQMFileEntry : NSObject
@property (nonatomic, copy) NSString *relativePath;
@property (nonatomic) unsigned long long bytes;
@property (nonatomic, strong) NSDate *modifiedAt;
@property (nonatomic, copy) NSDictionary<NSString *, NSNumber *> *identity;
@end
@interface WQMFileCatalog : NSObject
@property (nonatomic, copy) NSString *root;
@property (nonatomic, copy) NSArray<WQMFileEntry *> *files;
@property (nonatomic) BOOL complete;
@property (nonatomic) NSUInteger skippedEntries;
/// Metadata only, bounded to 50,000 files / 100,000 entries / 64 levels.
+ (instancetype)scanRoot:(NSString *)root cancellation:(WQMFileCatalogCancellation *)cancellation;
- (NSArray<WQMFileEntry *> *)filesMatching:(NSString *)query extension:(NSString *)extension
                            minimumBytes:(unsigned long long)minimumBytes limit:(NSUInteger)limit;
/// Returns nil if cancelled, unreadable, changed during reading, or incomplete.
/// Added/removed/changed only; exact mode hashes equal-sized file contents.
+ (nullable NSArray<NSDictionary *> *)compareOlder:(WQMFileCatalog *)older
                                            newer:(WQMFileCatalog *)newer
                                            exact:(BOOL)exact
                                     cancellation:(WQMFileCatalogCancellation *)cancellation;
@end
NS_ASSUME_NONNULL_END
