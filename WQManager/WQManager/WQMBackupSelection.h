#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Canonical directory selections inside Documents, Library or tmp. Format 3
/// stores these paths explicitly so restore never widens a partial selection.
@interface WQMBackupSelection : NSObject
+ (BOOL)isAllowedPath:(id)path;
+ (nullable NSArray<NSString *> *)canonicalPaths:(NSArray *)paths;
+ (BOOL)validatePayloadAtPath:(NSString *)root parts:(NSArray<NSString *> *)parts;
@end

NS_ASSUME_NONNULL_END
