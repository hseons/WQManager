#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const WQMSharedAppGroupIdentifier;

@interface WQMSharedInbox : NSObject

+ (nullable NSURL *)inboxURLCreatingIfNeeded:(BOOL)create error:(NSError *_Nullable *_Nullable)error;
+ (NSArray<NSURL *> *)pendingURLs;
+ (BOOL)enqueueURL:(NSURL *)sourceURL error:(NSError *_Nullable *_Nullable)error;
+ (nullable NSURL *)takeNextPendingURL:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END
