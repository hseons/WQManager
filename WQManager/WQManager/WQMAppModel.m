#import "WQMAppModel.h"
#import "WQMLanguageManager.h"
#import <sys/stat.h>

@implementation WQMAppModel

- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier
                             displayName:(NSString *)displayName
                           containerPath:(NSString *)containerPath
                                dataSize:(unsigned long long)dataSize
{
    self = [super init];
    if (self) {
        _bundleIdentifier = [bundleIdentifier copy];
        _displayName = [displayName copy];
        _containerPath = [containerPath copy];
        _dataSize = dataSize;
        _accessAvailable = NO;
        _identityKnown = NO;
        _sizeKnown = YES;
        _containerDevice = 0;
        _containerInode = 0;
    }
    return self;
}

- (NSString *)formattedSize
{
    if (!self.sizeKnown) return WQML(@"SIZE_UNKNOWN", @"大小未知");
    return WQMFormatBytes(self.dataSize);
}

- (NSString *)statusText
{
    NSString *identifier = self.bundleIdentifier.length ? self.bundleIdentifier : self.containerPath.lastPathComponent;
    if (!self.accessAvailable) {
        return [NSString stringWithFormat:WQML(@"ACCESS_UNAVAILABLE_DETAIL", @"访问不可用 · %@"), identifier];
    }
    if (!self.bundleIdentifier.length) {
        return [NSString stringWithFormat:WQML(@"NO_CONTAINER_ID_DETAIL", @"%@ · 无容器标识"), self.formattedSize];
    }
    if (!self.identityKnown) {
        return [NSString stringWithFormat:WQML(@"CONTAINER_ID_UNAVAILABLE_DETAIL", @"%@ · 容器身份不可用"),
                self.formattedSize];
    }
    return [NSString stringWithFormat:@"%@ · %@", self.formattedSize, self.bundleIdentifier];
}

@end

@interface WQMBackupScopeDescriptor ()

@property (nonatomic) WQMBackupScope scope;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *detail;
@property (nonatomic, copy) NSArray<NSString *> *relativePaths;

@end

@implementation WQMBackupScopeDescriptor

+ (NSArray<WQMBackupScopeDescriptor *> *)allDescriptors
{
    WQMBackupScopeDescriptor *quick = [WQMBackupScopeDescriptor new];
    quick.scope = WQMBackupScopeQuick;
    quick.title = WQML(@"QUICK_BACKUP", @"快速备份");
    quick.detail = WQML(@"QUICK_BACKUP_DETAIL", @"备份 Documents 与 Library，不包含 tmp。");
    quick.relativePaths = @[@"Documents", @"Library"];

    WQMBackupScopeDescriptor *full = [WQMBackupScopeDescriptor new];
    full.scope = WQMBackupScopeFull;
    full.title = WQML(@"FULL_BACKUP", @"完整备份");
    full.detail = WQML(@"FULL_BACKUP_DETAIL", @"备份 Documents、Library 和 tmp，占用空间更大。");
    full.relativePaths = @[@"Documents", @"Library", @"tmp"];

    WQMBackupScopeDescriptor *custom = [WQMBackupScopeDescriptor new];
    custom.scope = WQMBackupScopeCustom;
    custom.title = WQML(@"CUSTOM_BACKUP", @"自定义备份");
    custom.detail = WQML(@"CUSTOM_BACKUP_DETAIL", @"后续可选择具体目录；当前阶段仅展示范围模型。");
    custom.relativePaths = @[];

    return @[quick, full, custom];
}

+ (nullable instancetype)descriptorForScope:(WQMBackupScope)scope
{
    for (WQMBackupScopeDescriptor *descriptor in self.allDescriptors) {
        if (descriptor.scope == scope) return descriptor;
    }
    return nil;
}

@end

