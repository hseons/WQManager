#import "WQMSafetyPolicy.h"
#import "WQMLanguageManager.h"

static BOOL WQMPathHasComponentPrefix(NSString *path, NSString *prefix)
{
    if ([path isEqualToString:prefix]) return YES;
    return [path hasPrefix:[prefix stringByAppendingString:@"/"]];
}

@implementation WQMSafetyPolicy

+ (NSArray<NSString *> *)allowedCleanupRelativePaths
{
    return @[@"Library/Caches", @"tmp"];
}

+ (NSArray<NSString *> *)protectedAbsolutePaths
{
    return @[
        @"/var/db",
        @"/private/var/db",
        @"/var/MobileAsset",
        @"/private/var/MobileAsset",
        @"/var/db/uuidtext",
        @"/private/var/db/uuidtext",
        @"/var/mobile/Library/Caches",
        @"/private/var/mobile/Library/Caches",
        @"/var/mobile/Library/Safari",
        @"/private/var/mobile/Library/Safari",
        @"/private/var/containers/Data/System",
        @"/private/var/containers/Shared/SystemGroup",
        @"/private/var/mobile/Containers/Data/InternalDaemon",
    ];
}

+ (BOOL)isProtectedSystemPath:(NSString *)path
{
    NSString *normalized = path.stringByStandardizingPath;
    if (!normalized.isAbsolutePath || normalized.length == 0 || [normalized isEqualToString:@"/"]) {
        return YES;
    }
    for (NSString *protectedPath in self.protectedAbsolutePaths) {
        if (WQMPathHasComponentPrefix(normalized, protectedPath.stringByStandardizingPath)) {
            return YES;
        }
    }
    return NO;
}

+ (BOOL)isAllowedCleanupPath:(NSString *)targetPath
          inAppDataContainer:(NSString *)containerPath
                       reason:(NSString *_Nullable *_Nullable)reason
{
    NSString *target = targetPath.stringByStandardizingPath;
    NSString *container = containerPath.stringByStandardizingPath;

    if (!target.isAbsolutePath || !container.isAbsolutePath) {
        if (reason) *reason = WQML(@"SAFETY_ERROR_ABSOLUTE_PATH", @"目标或容器路径不是绝对路径");
        return NO;
    }
    if ([container isEqualToString:@"/"] || container.length == 0) {
        if (reason) *reason = WQML(@"SAFETY_ERROR_CONTAINER_BROAD", @"容器路径过于宽泛");
        return NO;
    }
    if ([self isProtectedSystemPath:container] || [self isProtectedSystemPath:target]) {
        if (reason) *reason = WQML(@"SAFETY_ERROR_SYSTEM_PATH", @"系统路径不在清理范围内");
        return NO;
    }
    if (!WQMPathHasComponentPrefix(target, container) || [target isEqualToString:container]) {
        if (reason) *reason = WQML(@"SAFETY_ERROR_OUTSIDE_CONTAINER",
                                   @"目标不在指定的 App Data 容器内");
        return NO;
    }

    NSUInteger prefixLength = container.length;
    NSString *relative = [target substringFromIndex:prefixLength];
    if ([relative hasPrefix:@"/"]) relative = [relative substringFromIndex:1];
    if (![self.allowedCleanupRelativePaths containsObject:relative]) {
        if (reason) *reason = WQML(@"SAFETY_ERROR_NOT_ALLOWED", @"相对路径不在清理白名单中");
        return NO;
    }
    return YES;
}

@end

@implementation WQMConfirmationGate

- (BOOL)beginForOperation:(NSString *)operationIdentifier
{
    NSString *trimmed = [operationIdentifier stringByTrimmingCharactersInSet:
                         NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) return NO;
    _operationIdentifier = [trimmed copy];
    _state = WQMConfirmationStateIdle;
    return YES;
}

- (BOOL)acknowledgeScopeForOperation:(NSString *)operationIdentifier
{
    if (self.state != WQMConfirmationStateIdle ||
        ![self.operationIdentifier isEqualToString:operationIdentifier]) {
        return NO;
    }
    _state = WQMConfirmationStateScopeAcknowledged;
    return YES;
}

- (BOOL)authorizeExecutionForOperation:(NSString *)operationIdentifier
{
    if (self.state != WQMConfirmationStateScopeAcknowledged ||
        ![self.operationIdentifier isEqualToString:operationIdentifier]) {
        return NO;
    }
    _state = WQMConfirmationStateAuthorized;
    return YES;
}

- (void)cancel
{
    _operationIdentifier = nil;
    _state = WQMConfirmationStateIdle;
}

@end

