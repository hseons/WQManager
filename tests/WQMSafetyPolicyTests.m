#import <Foundation/Foundation.h>
#import "WQMAppModel.h"
#import "WQMSafetyPolicy.h"

static NSUInteger gFailures = 0;

static void WQMAssert(BOOL condition, NSString *message)
{
    if (condition) return;
    gFailures++;
    fprintf(stderr, "FAIL: %s\n", message.UTF8String);
}

int main(void)
{
    @autoreleasepool {
        NSString *container = @"/private/var/mobile/Containers/Data/Application/AAAAAAAA-BBBB";
        NSString *reason = nil;

        WQMAssert([WQMSafetyPolicy isAllowedCleanupPath:
                   [container stringByAppendingPathComponent:@"Library/Caches"]
                                         inAppDataContainer:container
                                                      reason:&reason],
                  @"Library/Caches should be allowed");
        WQMAssert([WQMSafetyPolicy isAllowedCleanupPath:
                   [container stringByAppendingPathComponent:@"tmp"]
                                         inAppDataContainer:container
                                                      reason:&reason],
                  @"tmp should be allowed");
        WQMAssert(![WQMSafetyPolicy isAllowedCleanupPath:
                    [container stringByAppendingPathComponent:@"Documents"]
                                          inAppDataContainer:container
                                                       reason:&reason],
                  @"Documents must not be a cleanup target");
        WQMAssert(![WQMSafetyPolicy isAllowedCleanupPath:
                    [container stringByAppendingPathComponent:@"Library/Preferences"]
                                          inAppDataContainer:container
                                                       reason:&reason],
                  @"Preferences must not be a cleanup target");
        WQMAssert(![WQMSafetyPolicy isAllowedCleanupPath:
                    [container stringByAppendingPathComponent:@"Library/Caches/../../Documents"]
                                          inAppDataContainer:container
                                                       reason:&reason],
                  @"Parent traversal must not escape the allowlist");
        WQMAssert(![WQMSafetyPolicy isAllowedCleanupPath:@"/var/mobile/Library/Caches/com.apple.test"
                                          inAppDataContainer:@"/var/mobile"
                                                       reason:&reason],
                  @"System cache must remain protected");
        WQMAssert([WQMSafetyPolicy isProtectedSystemPath:@"/var/db/diagnostics/Persist"],
                  @"diagnostics must be protected");
        WQMAssert([WQMSafetyPolicy isProtectedSystemPath:@"/private/var/db/diagnostics/Persist"],
                  @"private diagnostics alias must be protected");
        WQMAssert([WQMSafetyPolicy isProtectedSystemPath:@"/private/var/containers/Shared/SystemGroup/test"],
                  @"SystemGroup must be protected");
        WQMAssert([WQMSafetyPolicy isProtectedSystemPath:@"/private/var/mobile/Library/Caches/com.apple.test"],
                  @"system cache alias must be protected");

        WQMConfirmationGate *gate = [WQMConfirmationGate new];
        WQMAssert(![gate authorizeExecutionForOperation:@"clean:test"],
                  @"Final authorization must fail before the scope stage");
        WQMAssert([gate beginForOperation:@"clean:test"], @"A valid operation ID must begin");
        WQMAssert(![gate acknowledgeScopeForOperation:@"other"], @"A different operation cannot advance");
        WQMAssert([gate acknowledgeScopeForOperation:@"clean:test"], @"Scope acknowledgement must advance");
        WQMAssert(![gate authorizeExecutionForOperation:@"other"], @"A different operation cannot authorize");
        WQMAssert([gate authorizeExecutionForOperation:@"clean:test"], @"Final authorization must require the matching operation");
        [gate cancel];
        WQMAssert(gate.state == WQMConfirmationStateIdle, @"Cancel must reset the gate");

        WQMAssert([WQMBackupScopeDescriptor allDescriptors].count == 3,
                  @"All backup scopes must be described");
    }

    if (gFailures) {
        fprintf(stderr, "%lu safety test(s) failed\n", (unsigned long)gFailures);
        return 1;
    }
    printf("WQM safety tests passed\n");
    return 0;
}

