#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, WQMBackupScope) {
    WQMBackupScopeQuick = 0,
    WQMBackupScopeFull,
    WQMBackupScopeCustom,
};

@interface WQMAppModel : NSObject

@property (nonatomic, copy) NSString *bundleIdentifier;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *containerPath;
@property (nonatomic) unsigned long long dataSize;
@property (nonatomic) BOOL accessAvailable;
@property (nonatomic) BOOL identityKnown;
@property (nonatomic) BOOL sizeKnown;
@property (nonatomic) dev_t containerDevice;
@property (nonatomic) ino_t containerInode;
- (NSString *)formattedSize;
- (NSString *)statusText;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier
                             displayName:(NSString *)displayName
                           containerPath:(NSString *)containerPath
                                dataSize:(unsigned long long)dataSize NS_DESIGNATED_INITIALIZER;

@end

@interface WQMBackupScopeDescriptor : NSObject

@property (nonatomic, readonly) WQMBackupScope scope;
@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, copy, readonly) NSString *detail;
@property (nonatomic, copy, readonly) NSArray<NSString *> *relativePaths;

+ (NSArray<WQMBackupScopeDescriptor *> *)allDescriptors;
+ (nullable instancetype)descriptorForScope:(WQMBackupScope)scope;

@end

NS_ASSUME_NONNULL_END

