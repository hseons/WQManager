#import <Foundation/Foundation.h>
@class WQMAppModel;

NS_ASSUME_NONNULL_BEGIN

@interface WQMAccessCheck : NSObject
@property (nonatomic, copy) NSString *stage;
@property (nonatomic, copy) NSString *status;
@property (nonatomic, copy) NSString *reason;
@property (nonatomic) NSInteger code;
@property (nonatomic) int systemError;
@property (nonatomic) NSUInteger sampledEntries;
@property (nonatomic) BOOL sampleLimited;
- (NSString *)title;
- (NSString *)detail;
@end

@interface WQMAccessReport : NSObject
@property (nonatomic, copy) NSDictionary *environment;
@property (nonatomic, copy) NSArray<WQMAccessCheck *> *checks;
@property (nonatomic, strong) NSDate *createdAt;
@property (nonatomic) NSTimeInterval duration;
@property (nonatomic) BOOL cancelled;
/// Explicit schema; no app identity, raw errors, paths, names, or contents.
- (nullable NSData *)redactedJSONData;
@end

typedef BOOL (^WQMAccessGrant)(NSString *path, NSInteger *code, int *systemError);
typedef NSString *_Nullable (^WQMAccessLabel)(NSString *path);

/// Bounded, nonrecursive reads of one previously discovered container.
/// The grant may use WQ's existing tool-owned App Group cache swap.
@interface WQMAccessDiagnostics : NSObject
- (instancetype)initWithContainerRoot:(NSString *)root
                                 grant:(WQMAccessGrant)grant
                                 label:(WQMAccessLabel)label;
- (WQMAccessReport *)probeApp:(WQMAppModel *)app
                 environment:(NSDictionary *)environment
                   cancelled:(BOOL (^)(void))cancelled;
/// Signing evidence, not a guess about the certificate/vendor used to install.
+ (NSDictionary *)environmentWithProtectedDataAvailable:(BOOL)available;
@end

NS_ASSUME_NONNULL_END
