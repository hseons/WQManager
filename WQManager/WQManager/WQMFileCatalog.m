#import "WQMFileCatalog.h"
#import "WQAccessSafety.h"
#import <CommonCrypto/CommonDigest.h>
#import <dirent.h>

@implementation WQMFileCatalogCancellation {
    BOOL _cancelled;
}
- (BOOL)isCancelled { @synchronized(self) { return _cancelled; } }
- (void)cancel { @synchronized(self) { _cancelled = YES; } }
@end
@implementation WQMFileEntry
@end

static NSDictionary *WQMCatalogIdentity(const struct stat *st)
{
    return @{@"Device": @(st->st_dev), @"Inode": @(st->st_ino), @"Size": @(st->st_size),
        @"MTime": @(st->st_mtimespec.tv_sec), @"MTimeNS": @(st->st_mtimespec.tv_nsec),
        @"CTime": @(st->st_ctimespec.tv_sec), @"CTimeNS": @(st->st_ctimespec.tv_nsec)};
}

static void WQMCatalogWalk(int fd, NSString *relative, NSMutableArray *files,
                          NSUInteger *visited, NSUInteger *skipped, BOOL *complete,
                          WQMFileCatalogCancellation *cancellation, NSUInteger depth)
{
    if (depth > 64) { *complete = NO; return; }
    int listing = dup(fd);
    if (listing < 0) { *complete = NO; return; }
    DIR *directory = fdopendir(listing);
    if (!directory) { close(listing); *complete = NO; return; }
    for (;;) {
        errno = 0;
        struct dirent *entry = readdir(directory);
        if (!entry) { if (errno) *complete = NO; break; }
        if (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, "..")) continue;
        if (cancellation.cancelled || *visited >= 100000 || files.count >= 50000) { *complete = NO; break; }
        (*visited)++;
        @autoreleasepool {
            NSString *name = [NSFileManager.defaultManager stringWithFileSystemRepresentation:entry->d_name length:strlen(entry->d_name)];
            struct stat st;
            if (!name || fstatat(fd, entry->d_name, &st, AT_SYMLINK_NOFOLLOW) != 0) { *complete = NO; (*skipped)++; continue; }
            NSString *path = relative.length ? [relative stringByAppendingPathComponent:name] : name;
            if (S_ISDIR(st.st_mode)) {
                int child = openat(fd, entry->d_name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
                struct stat opened;
                if (child < 0 || fstat(child, &opened) != 0 || !WQSameObject(&st, &opened)) {
                    if (child >= 0) close(child);
                    *complete = NO; (*skipped)++; continue;
                }
                WQMCatalogWalk(child, path, files, visited, skipped, complete, cancellation, depth + 1);
                close(child);
            } else if (S_ISREG(st.st_mode)) {
                WQMFileEntry *file = [WQMFileEntry new];
                file.relativePath = path;
                file.bytes = MAX(0, st.st_size);
                file.identity = WQMCatalogIdentity(&st);
                file.modifiedAt = [NSDate dateWithTimeIntervalSince1970:st.st_mtimespec.tv_sec + st.st_mtimespec.tv_nsec / 1e9];
                [files addObject:file];
            } else { (*skipped)++; }
        }
    }
    closedir(directory);
}

static NSData *WQMCatalogDigest(NSString *root, WQMFileEntry *entry, WQMFileCatalogCancellation *cancellation)
{
    NSString *path = [root stringByAppendingPathComponent:entry.relativePath];
    int parent = WQOpenDirectoryNoLinks(path.stringByDeletingLastPathComponent);
    if (parent < 0) return nil;
    int fd = WQOpenRegularAt(parent, path.lastPathComponent.fileSystemRepresentation, O_RDONLY, 0);
    close(parent);
    if (fd < 0) return nil;
    struct stat before, after;
    if (fstat(fd, &before) != 0 || ![WQMCatalogIdentity(&before) isEqual:entry.identity]) { close(fd); return nil; }
    CC_SHA256_CTX context;
    CC_SHA256_Init(&context);
    uint8_t buffer[64 * 1024];
    BOOL ok = YES;
    unsigned long long readBytes = 0;
    for (;;) {
        if (cancellation.cancelled) { ok = NO; break; }
        ssize_t count = read(fd, buffer, sizeof(buffer));
        if (count < 0 && errno == EINTR) continue;
        if (count < 0) { ok = NO; break; }
        if (!count) break;
        readBytes += count;
        CC_SHA256_Update(&context, buffer, (CC_LONG)count);
    }
    if (fstat(fd, &after) != 0 || !WQSameObject(&before, &after) || before.st_size != after.st_size ||
        before.st_mtimespec.tv_sec != after.st_mtimespec.tv_sec || before.st_mtimespec.tv_nsec != after.st_mtimespec.tv_nsec ||
        before.st_ctimespec.tv_sec != after.st_ctimespec.tv_sec || before.st_ctimespec.tv_nsec != after.st_ctimespec.tv_nsec || readBytes != entry.bytes) ok = NO;
    close(fd);
    if (!ok) return nil;
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &context);
    return [NSData dataWithBytes:digest length:sizeof(digest)];
}

@implementation WQMFileCatalog
+ (instancetype)scanRoot:(NSString *)root cancellation:(WQMFileCatalogCancellation *)cancellation
{
    WQMFileCatalog *catalog = [self new];
    catalog.root = root;
    NSMutableArray *files = [NSMutableArray new];
    BOOL complete = YES;
    NSUInteger visited = 0, skipped = 0;
    int fd = WQOpenDirectoryNoLinks(root);
    if (fd < 0) complete = NO;
    else { WQMCatalogWalk(fd, @"", files, &visited, &skipped, &complete, cancellation, 0); close(fd); }
    catalog.files = [files sortedArrayUsingComparator:^NSComparisonResult(WQMFileEntry *a, WQMFileEntry *b) {
        return a.bytes == b.bytes ? [a.relativePath compare:b.relativePath] : a.bytes > b.bytes ? NSOrderedAscending : NSOrderedDescending;
    }];
    catalog.complete = complete && !cancellation.cancelled;
    catalog.skippedEntries = skipped;
    return catalog;
}
- (NSArray<WQMFileEntry *> *)filesMatching:(NSString *)query extension:(NSString *)extension
                            minimumBytes:(unsigned long long)minimumBytes limit:(NSUInteger)limit
{
    NSMutableArray *matched = [NSMutableArray new];
    NSString *suffix = [extension.lowercaseString stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"."]];
    for (WQMFileEntry *file in self.files) {
        if (file.bytes < minimumBytes || (query.length && [file.relativePath rangeOfString:query options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location == NSNotFound) ||
            (suffix.length && ![file.relativePath.pathExtension.lowercaseString isEqualToString:suffix])) continue;
        if (matched.count >= limit) break;
        [matched addObject:file];
    }
    return matched;
}
+ (NSData *)digestForEntry:(WQMFileEntry *)entry root:(NSString *)root
              cancellation:(WQMFileCatalogCancellation *)cancellation
{
    return WQMCatalogDigest(root, entry, cancellation);
}
+ (NSArray<NSDictionary *> *)compareOlder:(WQMFileCatalog *)older newer:(WQMFileCatalog *)newer
                                    exact:(BOOL)exact cancellation:(WQMFileCatalogCancellation *)cancellation
{
    if (!older.complete || !newer.complete) return nil;
    NSMutableDictionary *before = [NSMutableDictionary new], *after = [NSMutableDictionary new];
    for (WQMFileEntry *file in older.files) if (![file.relativePath isEqual:@"manifest.plist"]) before[file.relativePath] = file;
    for (WQMFileEntry *file in newer.files) if (![file.relativePath isEqual:@"manifest.plist"]) after[file.relativePath] = file;
    NSMutableSet *paths = [NSMutableSet setWithArray:before.allKeys];
    [paths addObjectsFromArray:after.allKeys];
    NSMutableArray *changes = [NSMutableArray new];
    for (NSString *path in [paths.allObjects sortedArrayUsingSelector:@selector(compare:)]) {
        if (cancellation.cancelled) return nil;
        WQMFileEntry *a = before[path], *b = after[path];
        NSString *kind = !a ? @"added" : !b ? @"removed" : nil;
        if (a && b) {
            BOOL changed = a.bytes != b.bytes;
            if (!changed && exact) {
                NSData *hashA = WQMCatalogDigest(older.root, a, cancellation);
                NSData *hashB = WQMCatalogDigest(newer.root, b, cancellation);
                if (!hashA || !hashB) return nil;
                changed = ![hashA isEqual:hashB];
            } else if (!changed) changed = ![a.modifiedAt isEqualToDate:b.modifiedAt];
            if (changed) kind = @"changed";
        }
        if (kind) [changes addObject:@{@"Path": path, @"Kind": kind, @"Before": @(a.bytes), @"After": @(b.bytes)}];
    }
    return changes;
}
@end
