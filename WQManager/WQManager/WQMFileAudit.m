#import "WQMFileAudit.h"

static NSSet<NSString *> *WQMExtensions(NSArray<NSString *> *values)
{
    return [NSSet setWithArray:values];
}

@implementation WQMAuditFile
- (NSString *)absolutePath
{
    return [self.containerPath stringByAppendingPathComponent:self.relativePath];
}
- (WQMFileCategory)category
{
    return [WQMFileAudit categoryForPath:self.relativePath];
}
@end

@implementation WQMFileAudit

+ (WQMFileCategory)categoryForPath:(NSString *)path
{
    NSString *extension = path.pathExtension.lowercaseString;
    static NSSet<NSString *> *images;
    static NSSet<NSString *> *videos;
    static NSSet<NSString *> *audio;
    static NSSet<NSString *> *documents;
    static NSSet<NSString *> *archives;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        images = WQMExtensions(@[@"jpg", @"jpeg", @"png", @"heic", @"heif", @"gif", @"webp", @"tif", @"tiff", @"bmp", @"dng", @"raw"]);
        videos = WQMExtensions(@[@"mp4", @"mov", @"m4v", @"avi", @"mkv", @"webm", @"3gp"]);
        audio = WQMExtensions(@[@"mp3", @"m4a", @"aac", @"wav", @"flac", @"ogg", @"opus", @"caf"]);
        documents = WQMExtensions(@[@"pdf", @"doc", @"docx", @"xls", @"xlsx", @"ppt", @"pptx", @"txt", @"md", @"csv", @"json", @"xml", @"rtf", @"pages", @"numbers", @"key", @"epub"]);
        archives = WQMExtensions(@[@"zip", @"rar", @"7z", @"tar", @"gz", @"tgz", @"bz2", @"xz"]);
    });
    if ([images containsObject:extension]) return WQMFileCategoryImage;
    if ([videos containsObject:extension]) return WQMFileCategoryVideo;
    if ([audio containsObject:extension]) return WQMFileCategoryAudio;
    if ([documents containsObject:extension]) return WQMFileCategoryDocument;
    if ([archives containsObject:extension]) return WQMFileCategoryArchive;
    return WQMFileCategoryOther;
}

+ (BOOL)isUserDataRelativePath:(NSString *)relativePath
{
    if (!relativePath.length) return NO;
    return ![relativePath hasPrefix:@"Library/Caches/"] &&
           ![relativePath isEqualToString:@"Library/Caches"] &&
           ![relativePath hasPrefix:@"tmp/"] &&
           ![relativePath isEqualToString:@"tmp"];
}

+ (NSArray<WQMAuditFile *> *)filesFromCatalog:(WQMFileCatalog *)catalog
                                     appName:(NSString *)appName
                            bundleIdentifier:(NSString *)bundleIdentifier
                               containerPath:(NSString *)containerPath
                                includeCaches:(BOOL)includeCaches
{
    NSMutableArray<WQMAuditFile *> *result = [NSMutableArray new];
    for (WQMFileEntry *entry in catalog.files) {
        if (!includeCaches && ![self isUserDataRelativePath:entry.relativePath]) continue;
        WQMAuditFile *file = [WQMAuditFile new];
        file.appName = appName ?: bundleIdentifier ?: @"";
        file.bundleIdentifier = bundleIdentifier ?: @"";
        file.containerPath = containerPath ?: catalog.root ?: @"";
        file.relativePath = entry.relativePath;
        file.bytes = entry.bytes;
        file.modifiedAt = entry.modifiedAt;
        file.entry = entry;
        [result addObject:file];
    }
    return result;
}

+ (NSArray<WQMAuditFile *> *)largeFiles:(NSArray<WQMAuditFile *> *)files
                          minimumBytes:(unsigned long long)minimumBytes
                                 limit:(NSUInteger)limit
{
    NSMutableArray<WQMAuditFile *> *matched = [NSMutableArray new];
    for (WQMAuditFile *file in files) if (file.bytes >= minimumBytes) [matched addObject:file];
    [matched sortUsingComparator:^NSComparisonResult(WQMAuditFile *a, WQMAuditFile *b) {
        if (a.bytes != b.bytes) return a.bytes > b.bytes ? NSOrderedAscending : NSOrderedDescending;
        NSComparisonResult app = [a.appName localizedStandardCompare:b.appName];
        return app != NSOrderedSame ? app : [a.relativePath compare:b.relativePath];
    }];
    if (matched.count > limit) return [matched subarrayWithRange:NSMakeRange(0, limit)];
    return matched;
}

+ (NSArray<NSArray<WQMAuditFile *> *> *)duplicateSizeBuckets:(NSArray<WQMAuditFile *> *)files
                                                 minimumBytes:(unsigned long long)minimumBytes
{
    // Bucket per app as well as per size: an identical file inside another app
    // cannot replace this app's copy, so a group must never span apps.
    NSMutableDictionary<NSString *, NSMutableDictionary<NSNumber *, NSMutableArray<WQMAuditFile *> *> *> *byApp = [NSMutableDictionary new];
    for (WQMAuditFile *file in files) {
        if (file.bytes < minimumBytes || file.bytes == 0) continue;
        NSString *appKey = file.bundleIdentifier ?: @"";
        NSMutableDictionary<NSNumber *, NSMutableArray<WQMAuditFile *> *> *bySize = byApp[appKey];
        if (!bySize) { bySize = [NSMutableDictionary new]; byApp[appKey] = bySize; }
        NSNumber *size = @(file.bytes);
        NSMutableArray *bucket = bySize[size];
        if (!bucket) { bucket = [NSMutableArray new]; bySize[size] = bucket; }
        [bucket addObject:file];
    }
    NSMutableArray<NSArray<WQMAuditFile *> *> *groups = [NSMutableArray new];
    for (NSMutableDictionary<NSNumber *, NSMutableArray<WQMAuditFile *> *> *bySize in byApp.allValues) {
        for (NSMutableArray<WQMAuditFile *> *bucket in bySize.allValues) {
            if (bucket.count < 2) continue;
            [bucket sortUsingComparator:^NSComparisonResult(WQMAuditFile *a, WQMAuditFile *b) {
                NSComparisonResult app = [a.appName localizedStandardCompare:b.appName];
                if (app != NSOrderedSame) return app;
                NSComparisonResult bundle = [a.bundleIdentifier compare:b.bundleIdentifier];
                return bundle != NSOrderedSame ? bundle : [a.relativePath compare:b.relativePath];
            }];
            [groups addObject:bucket];
        }
    }
    [groups sortUsingComparator:^NSComparisonResult(NSArray<WQMAuditFile *> *a, NSArray<WQMAuditFile *> *b) {
        unsigned long long saveA = a.firstObject.bytes * (a.count - 1);
        unsigned long long saveB = b.firstObject.bytes * (b.count - 1);
        if (saveA != saveB) return saveA > saveB ? NSOrderedAscending : NSOrderedDescending;
        if (a.firstObject.bytes != b.firstObject.bytes) {
            return a.firstObject.bytes > b.firstObject.bytes ? NSOrderedAscending : NSOrderedDescending;
        }
        NSComparisonResult app = [a.firstObject.appName localizedStandardCompare:b.firstObject.appName];
        if (app != NSOrderedSame) return app;
        NSComparisonResult bundle = [a.firstObject.bundleIdentifier compare:b.firstObject.bundleIdentifier];
        return bundle != NSOrderedSame ? bundle : [a.firstObject.relativePath compare:b.firstObject.relativePath];
    }];
    return groups;
}

+ (BOOL)fileVersion:(NSDictionary<NSString *, NSNumber *> *)version
       matchesEntry:(WQMFileEntry *)entry
{
    if (!version || !entry.identity) return NO;
    return [version[@"device"] isEqual:entry.identity[@"Device"]] &&
           [version[@"inode"] isEqual:entry.identity[@"Inode"]] &&
           [version[@"size"] isEqual:entry.identity[@"Size"]] &&
           [version[@"modifiedSeconds"] isEqual:entry.identity[@"MTime"]] &&
           [version[@"modifiedNanoseconds"] isEqual:entry.identity[@"MTimeNS"]] &&
           [version[@"changedSeconds"] isEqual:entry.identity[@"CTime"]] &&
           [version[@"changedNanoseconds"] isEqual:entry.identity[@"CTimeNS"]];
}

+ (NSString *)duplicateSelectionKeyForFile:(WQMAuditFile *)file
{
    return [NSString stringWithFormat:@"%@|%@", file.bundleIdentifier ?: @"",
            file.relativePath ?: @""];
}

+ (BOOL)duplicateSelectionKeepsOnePerGroup:(NSArray<NSArray<WQMAuditFile *> *> *)groups
                              selectedKeys:(NSSet<NSString *> *)selectedKeys
{
    for (NSArray<WQMAuditFile *> *group in groups) {
        if (!group.count) continue;
        NSUInteger selected = 0;
        for (WQMAuditFile *file in group) {
            if ([selectedKeys containsObject:[self duplicateSelectionKeyForFile:file]]) selected++;
        }
        if (selected >= group.count) return NO;
    }
    return YES;
}

+ (BOOL)file:(WQMAuditFile *)file matchesQuery:(NSString *)query
{
    NSString *trimmed = [query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!trimmed.length) return YES;
    NSString *haystack = [NSString stringWithFormat:@"%@\n%@", file.appName ?: @"", file.relativePath ?: @""];
    NSArray<NSString *> *tokens = [trimmed componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    for (NSString *token in tokens) {
        if (!token.length) continue;
        NSRange range = [haystack rangeOfString:token options:NSCaseInsensitiveSearch |
            NSDiacriticInsensitiveSearch | NSWidthInsensitiveSearch];
        if (range.location == NSNotFound) return NO;
    }
    return YES;
}

+ (NSArray<WQMAuditFile *> *)searchFiles:(NSArray<WQMAuditFile *> *)files
                                   query:(NSString *)query
                                category:(WQMFileCategory)category
                            minimumBytes:(unsigned long long)minimumBytes
                                    sort:(WQMFileSortOrder)sort
                                   limit:(NSUInteger)limit
{
    NSMutableArray<WQMAuditFile *> *matched = [NSMutableArray new];
    for (WQMAuditFile *file in files) {
        if (minimumBytes && file.bytes < minimumBytes) continue;
        if (category != WQMFileCategoryAll && file.category != category) continue;
        if (![self file:file matchesQuery:query]) continue;
        [matched addObject:file];
    }
    [matched sortUsingComparator:^NSComparisonResult(WQMAuditFile *a, WQMAuditFile *b) {
        if (sort == WQMFileSortOrderSizeDescending && a.bytes != b.bytes) {
            return a.bytes > b.bytes ? NSOrderedAscending : NSOrderedDescending;
        }
        if (sort == WQMFileSortOrderNewest) {
            NSTimeInterval timeA = a.modifiedAt ? a.modifiedAt.timeIntervalSince1970 : 0;
            NSTimeInterval timeB = b.modifiedAt ? b.modifiedAt.timeIntervalSince1970 : 0;
            if (timeA != timeB) return timeA > timeB ? NSOrderedAscending : NSOrderedDescending;
        }
        NSComparisonResult path = [a.relativePath localizedStandardCompare:b.relativePath];
        if (path != NSOrderedSame) return path;
        NSComparisonResult app = [a.appName localizedStandardCompare:b.appName];
        return app != NSOrderedSame ? app : [a.bundleIdentifier compare:b.bundleIdentifier];
    }];
    if (limit && matched.count > limit) return [matched subarrayWithRange:NSMakeRange(0, limit)];
    return matched;
}

@end
