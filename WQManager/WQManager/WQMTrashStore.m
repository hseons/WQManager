//
//  WQMTrashStore.m
//  WQManager
//

#import "WQMTrashStore.h"
#import "WQAppsSupport.h"
#import "WQMSharedInbox.h"

static NSString *const kWQMTrashFolder = @"SpaceLensTrash";
static NSString *const kWQMTrashManifest = @"manifest.plist";
static NSString *const kWQMTrashManifestSource = @"Source";
static NSString *const kWQMTrashManifestCreated = @"Created";
static NSString *const kWQMTrashManifestItems = @"Items";
static NSString *const kWQMTrashItemName = @"Name";
static NSString *const kWQMTrashItemBytes = @"Bytes";
static NSString *const kWQMTrashItemDirectory = @"Directory";

@implementation WQMTrashItem
@end

@implementation WQMTrashSession
@end

@implementation WQMTrashStore

+ (NSString *)rootPath
{
    // Tests point the bin at a scratch directory so they never touch the real
    // library or the App Group.
    NSString *override = NSProcessInfo.processInfo.environment[@"WQM_TRASH_ROOT"];
    if (override.length) return override;
    NSURL *group = [NSFileManager.defaultManager
                    containerURLForSecurityApplicationGroupIdentifier:WQMSharedAppGroupIdentifier];
    NSString *base = group.path;
    if (!base.length) {
        base = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
    }
    return [base stringByAppendingPathComponent:kWQMTrashFolder];
}

+ (nullable NSString *)createSessionForLevel:(nullable NSString *)level
{
    NSFileManager *manager = NSFileManager.defaultManager;
    NSString *root = [self rootPath];
    [manager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:NULL];

    NSDateFormatter *stamp = [NSDateFormatter new];
    stamp.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    stamp.dateFormat = @"yyyyMMdd-HHmmss";
    NSString *leaf = level.lastPathComponent.length ? level.lastPathComponent : @"container";
    NSString *name = [NSString stringWithFormat:@"%@-%@", [stamp stringFromDate:NSDate.date], leaf];
    NSString *path = [root stringByAppendingPathComponent:name];
    NSInteger suffix = 2;
    while ([manager fileExistsAtPath:path]) {
        path = [root stringByAppendingPathComponent:
                [NSString stringWithFormat:@"%@-%ld", name, (long)suffix]];
        suffix += 1;
    }
    if (![manager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:NULL]) {
        return nil;
    }
    return path;
}

+ (void)recordSession:(NSString *)sessionPath
               source:(nullable NSString *)sourcePath
                items:(NSArray<NSDictionary<NSString *, id> *> *)items
{
    if (!sessionPath.length) return;
    NSDictionary *manifest = @{
        kWQMTrashManifestSource: sourcePath ?: @"",
        kWQMTrashManifestCreated: [NSDate date],
        kWQMTrashManifestItems: items ?: @[],
    };
    [manifest writeToFile:[sessionPath stringByAppendingPathComponent:kWQMTrashManifest]
               atomically:YES];
}

+ (NSArray<WQMTrashSession *> *)sessions
{
    NSFileManager *manager = NSFileManager.defaultManager;
    NSString *root = [self rootPath];
    NSArray<NSString *> *names = [manager contentsOfDirectoryAtPath:root error:NULL] ?: @[];
    NSMutableArray<WQMTrashSession *> *sessions = [NSMutableArray new];
    for (NSString *name in names) {
        if ([name hasPrefix:@"."]) continue;
        NSString *path = [root stringByAppendingPathComponent:name];
        BOOL directory = NO;
        if (![manager fileExistsAtPath:path isDirectory:&directory] || !directory) continue;

        WQMTrashSession *session = [WQMTrashSession new];
        session.name = name;
        session.path = path;
        NSDictionary *attributes = [manager attributesOfItemAtPath:path error:NULL];
        session.createdAt = attributes[NSFileCreationDate] ?: attributes[NSFileModificationDate] ?: NSDate.date;

        NSDictionary *manifest = [NSDictionary dictionaryWithContentsOfFile:
                                  [path stringByAppendingPathComponent:kWQMTrashManifest]];
        NSString *source = manifest[kWQMTrashManifestSource];
        session.sourcePath = [source isKindOfClass:NSString.class] && [source length] ? source : nil;
        NSArray *entries = [manifest[kWQMTrashManifestItems] isKindOfClass:NSArray.class]
            ? manifest[kWQMTrashManifestItems] : nil;

        NSMutableArray<WQMTrashItem *> *items = [NSMutableArray new];
        unsigned long long total = 0;
        if (entries) {
            for (id entry in entries) {
                if (![entry isKindOfClass:NSDictionary.class]) continue;
                NSString *itemName = entry[kWQMTrashItemName];
                if (![itemName isKindOfClass:NSString.class] || !itemName.length) continue;
                WQMTrashItem *item = [WQMTrashItem new];
                item.name = itemName;
                item.path = [path stringByAppendingPathComponent:itemName];
                item.directory = [entry[kWQMTrashItemDirectory] boolValue];
                item.bytes = [entry[kWQMTrashItemBytes] unsignedLongLongValue];
                item.originalPath = session.sourcePath
                    ? [session.sourcePath stringByAppendingPathComponent:itemName] : nil;
                if (![manager fileExistsAtPath:item.path]) continue;
                total += item.bytes;
                [items addObject:item];
            }
        } else {
            // Session recorded before manifests existed: list whatever is there
            // and let the user delete it, but do not guess where it came from.
            NSArray<NSString *> *children = [manager contentsOfDirectoryAtPath:path error:NULL] ?: @[];
            for (NSString *child in children) {
                if ([child isEqualToString:kWQMTrashManifest] || [child hasPrefix:@"."]) continue;
                WQMTrashItem *item = [WQMTrashItem new];
                item.name = child;
                item.path = [path stringByAppendingPathComponent:child];
                BOOL childDirectory = NO;
                if (![manager fileExistsAtPath:item.path isDirectory:&childDirectory]) continue;
                item.directory = childDirectory;
                item.bytes = childDirectory
                    ? WQMAppsSupportTreeSize(item.path)
                    : [[manager attributesOfItemAtPath:item.path error:NULL][NSFileSize]
                       unsignedLongLongValue];
                total += item.bytes;
                [items addObject:item];
            }
        }
        if (!items.count) continue;
        session.items = items;
        session.totalBytes = total;
        [sessions addObject:session];
    }
    [sessions sortUsingComparator:^NSComparisonResult(WQMTrashSession *a, WQMTrashSession *b) {
        return [b.createdAt compare:a.createdAt];
    }];
    return sessions;
}

+ (NSUInteger)itemCount
{
    NSUInteger count = 0;
    for (WQMTrashSession *session in [self sessions]) count += session.items.count;
    return count;
}

+ (unsigned long long)totalBytes
{
    unsigned long long total = 0;
    for (WQMTrashSession *session in [self sessions]) total += session.totalBytes;
    return total;
}

+ (BOOL)restoreItem:(WQMTrashItem *)item error:(NSError *_Nullable *_Nullable)error
{
    if (!item.originalPath.length) {
        if (error) {
            *error = [NSError errorWithDomain:@"WQMTrash"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"unknown destination"}];
        }
        return NO;
    }
    NSFileManager *manager = NSFileManager.defaultManager;
    if ([manager fileExistsAtPath:item.originalPath]) {
        if (error) {
            *error = [NSError errorWithDomain:@"WQMTrash"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"destination exists"}];
        }
        return NO;
    }
    NSString *parent = [item.originalPath stringByDeletingLastPathComponent];
    [manager createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:nil error:NULL];
    BOOL ok = [manager moveItemAtPath:item.path toPath:item.originalPath error:error];
    if (ok) {
        [self removeEmptySessionDirectoriesForItem:item];
    }
    return ok;
}

+ (void)removeEmptySessionDirectoriesForItem:(WQMTrashItem *)item
{
    NSString *directory = [item.path stringByDeletingLastPathComponent];
    NSArray<NSString *> *left = [NSFileManager.defaultManager contentsOfDirectoryAtPath:directory
                                                                                 error:NULL] ?: @[];
    NSMutableArray<NSString *> *real = [NSMutableArray new];
    for (NSString *name in left) {
        if (![name hasPrefix:@"."]) [real addObject:name];
    }
    if (real.count == 1 && [real.firstObject isEqualToString:kWQMTrashManifest]) {
        [NSFileManager.defaultManager removeItemAtPath:directory error:NULL];
    }
}

+ (void)removeItem:(WQMTrashItem *)item
{
    [NSFileManager.defaultManager removeItemAtPath:item.path error:NULL];
    [self removeEmptySessionDirectoriesForItem:item];
}

+ (void)emptyAll
{
    NSFileManager *manager = NSFileManager.defaultManager;
    NSString *root = [self rootPath];
    NSArray<NSString *> *names = [manager contentsOfDirectoryAtPath:root error:NULL] ?: @[];
    for (NSString *name in names) {
        [manager removeItemAtPath:[root stringByAppendingPathComponent:name] error:NULL];
    }
}

@end
