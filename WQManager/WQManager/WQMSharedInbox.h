#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const WQMSharedAppGroupIdentifier;

@interface WQMSharedInbox : NSObject

+ (nullable NSURL *)inboxURLCreatingIfNeeded:(BOOL)create error:(NSError *_Nullable *_Nullable)error;
+ (NSArray<NSURL *> *)pendingURLs;
+ (BOOL)enqueueURL:(NSURL *)sourceURL error:(NSError *_Nullable *_Nullable)error;
+ (nullable NSURL *)takeNextPendingURL:(NSError *_Nullable *_Nullable)error;

/// Absolute path of the App Group inbox, or nil when the group is unavailable.
+ (nullable NSString *)inboxPath;

/// Removes inbox items (backup packages and .incoming staging directories)
/// older than `maxAge` seconds. Returns the number removed; `freedBytes`
/// receives the reclaimed size.
+ (NSUInteger)purgeStaleItemsOlderThan:(NSTimeInterval)maxAge
                            freedBytes:(nullable unsigned long long *)freedBytes;

@end

NS_ASSUME_NONNULL_END
