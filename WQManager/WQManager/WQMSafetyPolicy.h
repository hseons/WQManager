#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, WQMConfirmationState) {
    WQMConfirmationStateIdle = 0,
    WQMConfirmationStateScopeAcknowledged,
    WQMConfirmationStateAuthorized,
};

@interface WQMSafetyPolicy : NSObject

+ (NSArray<NSString *> *)allowedCleanupRelativePaths;
+ (NSArray<NSString *> *)protectedAbsolutePaths;

+ (BOOL)isAllowedCleanupPath:(NSString *)targetPath
      inAppDataContainer:(NSString *)containerPath
                   reason:(NSString *_Nullable *_Nullable)reason;

+ (BOOL)isProtectedSystemPath:(NSString *)path;

@end

@interface WQMConfirmationGate : NSObject

@property (nonatomic, copy, readonly, nullable) NSString *operationIdentifier;
@property (nonatomic, readonly) WQMConfirmationState state;

- (BOOL)beginForOperation:(NSString *)operationIdentifier;
- (BOOL)acknowledgeScopeForOperation:(NSString *)operationIdentifier;
- (BOOL)authorizeExecutionForOperation:(NSString *)operationIdentifier;
- (void)cancel;

@end

NS_ASSUME_NONNULL_END

