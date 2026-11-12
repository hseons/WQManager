#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Removes temporary artifacts left behind by interrupted backups, imports or
/// exports. Runs once at launch on a utility queue; never blocks the UI.
@interface WQMHousekeeping : NSObject

+ (void)runAtLaunch;

/// Testable core. Only entries older than `maxAge` are removed.
+ (void)runWithBackupRoot:(nullable NSString *)backupRoot
             recoveryRoot:(nullable NSString *)recoveryRoot
            temporaryRoot:(nullable NSString *)temporaryRoot
                   maxAge:(NSTimeInterval)maxAge;

@end

NS_ASSUME_NONNULL_END
