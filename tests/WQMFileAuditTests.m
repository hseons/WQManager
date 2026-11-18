#import <Foundation/Foundation.h>
#import "WQMFileAudit.h"

static NSUInteger WQMFailures = 0;

static void WQMAssert(BOOL condition, NSString *message)
{
    if (condition) return;
    WQMFailures += 1;
    fprintf(stderr, "FAIL: %s\n", message.UTF8String);
}

static WQMAuditFile *WQMFile(NSString *name, unsigned long long bytes)
{
    WQMAuditFile *file = [WQMAuditFile new];
    file.appName = @"Fixture";
    file.bundleIdentifier = @"example.fixture";
    file.containerPath = @"/tmp/WQMFileAuditFixture";
    file.relativePath = name;
    file.bytes = bytes;
    WQMFileEntry *entry = [WQMFileEntry new];
    entry.relativePath = name;
    entry.bytes = bytes;
    file.entry = entry;
    return file;
}

static WQMAuditFile *WQMFileInBundle(NSString *name, NSString *bundle, unsigned long long bytes)
{
    WQMAuditFile *file = WQMFile(name, bytes);
    file.bundleIdentifier = bundle;
    return file;
}

int main(void)
{
    @autoreleasepool {
        WQMAssert([WQMFileAudit categoryForPath:@"photo.HEIC"] == WQMFileCategoryImage, @"image extension");
        WQMAssert([WQMFileAudit categoryForPath:@"clip.mov"] == WQMFileCategoryVideo, @"video extension");
        WQMAssert([WQMFileAudit categoryForPath:@"voice.m4a"] == WQMFileCategoryAudio, @"audio extension");
        WQMAssert([WQMFileAudit categoryForPath:@"report.pdf"] == WQMFileCategoryDocument, @"document extension");
        WQMAssert([WQMFileAudit categoryForPath:@"archive.zip"] == WQMFileCategoryArchive, @"archive extension");
        WQMAssert([WQMFileAudit categoryForPath:@"cache.bin"] == WQMFileCategoryOther, @"other extension");

        WQMAssert([WQMFileAudit isUserDataRelativePath:@"Documents/photo.jpg"], @"documents are user data");
        WQMAssert(![WQMFileAudit isUserDataRelativePath:@"Library/Caches/cache.jpg"], @"caches excluded");
        WQMAssert(![WQMFileAudit isUserDataRelativePath:@"tmp/upload.jpg"], @"tmp excluded");

        NSArray *files = @[
            WQMFile(@"Documents/a.jpg", 2 * 1024 * 1024),
            WQMFile(@"Documents/b.jpg", 2 * 1024 * 1024),
            WQMFile(@"Documents/c.jpg", 2 * 1024 * 1024),
            WQMFile(@"Documents/d.mov", 8 * 1024 * 1024),
            WQMFile(@"Documents/e.mov", 8 * 1024 * 1024),
            WQMFile(@"Documents/small.txt", 1024),
        ];
        NSArray *large = [WQMFileAudit largeFiles:files minimumBytes:4 * 1024 * 1024 limit:2];
        WQMAssert(large.count == 2, @"large file limit");
        WQMAssert([(WQMAuditFile *)large.firstObject bytes] == 8 * 1024 * 1024, @"large files sorted by size");

        NSArray *groups = [WQMFileAudit duplicateSizeBuckets:files minimumBytes:1024 * 1024];
        WQMAssert(groups.count == 2, @"two same-size groups");
        NSArray<WQMAuditFile *> *firstGroup = groups.firstObject;
        WQMAssert(firstGroup.count == 2, @"largest reclaimable group sorts first");
        WQMAssert(firstGroup.firstObject.bytes == 8 * 1024 * 1024,
                  @"largest reclaimable size leads");
        WQMAssert([groups.lastObject count] == 3, @"second group retained");

        // Size buckets are per app: one app's copy cannot stand in for another's.
        NSArray *mixedApps = @[
            WQMFileInBundle(@"Documents/shared.jpg", @"example.one", 3 * 1024 * 1024),
            WQMFileInBundle(@"Documents/shared-copy.jpg", @"example.one", 3 * 1024 * 1024),
            WQMFileInBundle(@"Documents/shared.jpg", @"example.two", 3 * 1024 * 1024),
            WQMFileInBundle(@"Documents/shared-copy.jpg", @"example.two", 3 * 1024 * 1024),
        ];
        NSArray *appGroups = [WQMFileAudit duplicateSizeBuckets:mixedApps minimumBytes:1024 * 1024];
        WQMAssert(appGroups.count == 2, @"size buckets stay inside one app");
        for (NSArray<WQMAuditFile *> *group in appGroups) {
            NSString *bundle = group.firstObject.bundleIdentifier;
            for (WQMAuditFile *file in group) {
                WQMAssert([file.bundleIdentifier isEqualToString:bundle], @"bucket never spans apps");
            }
        }
        NSArray *crossApp = @[
            WQMFileInBundle(@"Documents/only.jpg", @"example.one", 5 * 1024 * 1024),
            WQMFileInBundle(@"Documents/only.jpg", @"example.two", 5 * 1024 * 1024),
        ];
        WQMAssert([WQMFileAudit duplicateSizeBuckets:crossApp minimumBytes:1024 * 1024].count == 0,
                  @"same size across apps is not a duplicate candidate");

        WQMFileEntry *entry = [WQMFileEntry new];
        entry.identity = @{@"Device": @1, @"Inode": @2, @"Size": @3, @"MTime": @4,
            @"MTimeNS": @5, @"CTime": @6, @"CTimeNS": @7};
        NSDictionary *version = @{@"device": @1, @"inode": @2, @"size": @3,
            @"modifiedSeconds": @4, @"modifiedNanoseconds": @5,
            @"changedSeconds": @6, @"changedNanoseconds": @7};
        WQMAssert([WQMFileAudit fileVersion:version matchesEntry:entry], @"identity matches");
        WQMAssert(![WQMFileAudit fileVersion:@{@"device": @9} matchesEntry:entry], @"identity mismatch");

        // Duplicate cleanup must leave one file in every confirmed group, and a
        // group never spans apps, so "one per group" is "one per app".
        WQMAuditFile *a = WQMFileInBundle(@"Documents/a.jpg", @"example.one", 100);
        WQMAuditFile *b = WQMFileInBundle(@"Documents/b.jpg", @"example.one", 100);
        WQMAuditFile *c = WQMFileInBundle(@"Documents/a.jpg", @"example.two", 100);
        WQMAuditFile *d = WQMFileInBundle(@"Documents/d.jpg", @"example.two", 100);
        NSArray *dupGroups = @[@[a, b]];
        NSString *keyA = [WQMFileAudit duplicateSelectionKeyForFile:a];
        NSString *keyB = [WQMFileAudit duplicateSelectionKeyForFile:b];
        NSString *keyC = [WQMFileAudit duplicateSelectionKeyForFile:c];
        WQMAssert(![keyA isEqualToString:keyC], @"same relative path in different apps must differ");
        WQMAssert([WQMFileAudit duplicateSelectionKeepsOnePerGroup:dupGroups selectedKeys:[NSSet set]],
                  @"nothing selected keeps every group valid");
        WQMAssert([WQMFileAudit duplicateSelectionKeepsOnePerGroup:dupGroups
                                                      selectedKeys:[NSSet setWithObject:keyA]],
                  @"one selected out of two is valid");
        WQMAssert(![WQMFileAudit duplicateSelectionKeepsOnePerGroup:dupGroups
                                                       selectedKeys:[NSSet setWithObjects:keyA, keyB, nil]],
                  @"selecting an entire group must be rejected");
        WQMAssert([WQMFileAudit duplicateSelectionKeepsOnePerGroup:@[@[a, b], @[c, d]]
                                                     selectedKeys:[NSSet setWithObjects:keyA, keyC, nil]],
                  @"each app group keeps its own remaining copy");
        WQMAssert([WQMFileAudit duplicateSelectionKeepsOnePerGroup:@[] selectedKeys:[NSSet set]],
                  @"no groups is valid");

        // Global search: tokens match app name and path, filters and sorts are stable.
        NSDate *older = [NSDate dateWithTimeIntervalSince1970:1000];
        NSDate *newer = [NSDate dateWithTimeIntervalSince1970:2000];
        WQMAuditFile *photo = WQMFile(@"Documents/trip/photo.JPG", 3 * 1024 * 1024);
        photo.appName = @"Photos";
        photo.modifiedAt = older;
        WQMAuditFile *clip = WQMFile(@"Documents/clip.mov", 8 * 1024 * 1024);
        clip.appName = @"Camera";
        clip.modifiedAt = newer;
        WQMAuditFile *note = WQMFile(@"Documents/notes.txt", 1024);
        note.appName = @"Notes";
        note.modifiedAt = older;
        NSArray *searchable = @[photo, clip, note];

        WQMAssert([WQMFileAudit file:photo matchesQuery:@"photo"], @"query matches file name");
        WQMAssert([WQMFileAudit file:photo matchesQuery:@"PHOTOS trip"], @"tokens match app and path");
        WQMAssert(![WQMFileAudit file:photo matchesQuery:@"photo missing"], @"all tokens must match");
        WQMAssert([WQMFileAudit file:photo matchesQuery:@"   "], @"blank query matches everything");

        NSArray *byName = [WQMFileAudit searchFiles:searchable query:@"photo" category:WQMFileCategoryAll
            minimumBytes:0 sort:WQMFileSortOrderPath limit:0];
        WQMAssert(byName.count == 1 && byName.firstObject == photo, @"name search returns one file");
        NSArray *images = [WQMFileAudit searchFiles:searchable query:@"" category:WQMFileCategoryImage
            minimumBytes:0 sort:WQMFileSortOrderPath limit:0];
        WQMAssert(images.count == 1 && images.firstObject == photo, @"category filter");
        NSArray *largeBySize = [WQMFileAudit searchFiles:searchable query:nil category:WQMFileCategoryAll
            minimumBytes:1024 * 1024 sort:WQMFileSortOrderSizeDescending limit:0];
        WQMAssert(largeBySize.count == 2 && largeBySize.firstObject == clip, @"minimum size and size sort");
        NSArray *newest = [WQMFileAudit searchFiles:searchable query:nil category:WQMFileCategoryAll
            minimumBytes:0 sort:WQMFileSortOrderNewest limit:1];
        WQMAssert(newest.count == 1 && newest.firstObject == clip, @"newest sort and limit");
        NSArray *limited = [WQMFileAudit searchFiles:searchable query:nil category:WQMFileCategoryAll
            minimumBytes:0 sort:WQMFileSortOrderPath limit:2];
        WQMAssert(limited.count == 2, @"search limit caps results");
    }
    if (WQMFailures == 0) {
        fprintf(stdout, "WQM file audit tests passed\n");
        return 0;
    }
    fprintf(stderr, "%lu file audit checks failed\n", (unsigned long)WQMFailures);
    return 1;
}
