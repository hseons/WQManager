#import <Foundation/Foundation.h>
#import "WQMFileCatalog.h"
static NSUInteger failures;
static void Check(BOOL ok, NSString *message) { if (!ok) { failures++; fprintf(stderr, "FAIL: %s\n", message.UTF8String); } }
static void Write(NSString *root, NSString *path, NSString *text) {
    NSString *target = [root stringByAppendingPathComponent:path];
    [NSFileManager.defaultManager createDirectoryAtPath:target.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    [text writeToFile:target atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
int main(void) { @autoreleasepool {
    NSString *base = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSString *left = [base stringByAppendingPathComponent:@"left"], *right = [base stringByAppendingPathComponent:@"right"];
    Write(left, @"Documents/一样.txt", @"same"); Write(right, @"Documents/一样.txt", @"same");
    Write(left, @"Library/config.json", @"AAAA"); Write(right, @"Library/config.json", @"BBBB");
    Write(left, @"Documents/removed.mp4", @"video fixture"); Write(right, @"Documents/added.txt", @"new");
    NSDate *fixedDate = [NSDate dateWithTimeIntervalSince1970:1000];
    for (NSString *root in @[left, right]) for (NSString *path in @[@"Documents/一样.txt", @"Library/config.json"])
        [NSFileManager.defaultManager setAttributes:@{NSFileModificationDate:fixedDate} ofItemAtPath:[root stringByAppendingPathComponent:path] error:nil];
    [NSFileManager.defaultManager createSymbolicLinkAtPath:[left stringByAppendingPathComponent:@"outside"] withDestinationPath:base error:nil];
    WQMFileCatalogCancellation *token = [WQMFileCatalogCancellation new];
    WQMFileCatalog *a = [WQMFileCatalog scanRoot:left cancellation:token], *b = [WQMFileCatalog scanRoot:right cancellation:token];
    Check(a.complete && b.complete, @"ordinary trees enumerate completely");
    Check(a.files.count == 3 && a.skippedEntries == 1, @"links are not followed or indexed as files");
    Check([a filesMatching:@"一样" extension:@"txt" minimumBytes:0 limit:1000].count == 1, @"unicode and extension filter work together");
    Check([a filesMatching:@"" extension:@"" minimumBytes:10 limit:1000].count == 1, @"minimum size filter works");
    NSArray *metadata = [WQMFileCatalog compareOlder:a newer:b exact:NO cancellation:token];
    Check(metadata.count == 2, @"metadata does not pretend equal-size, equal-time rewrites are detected");
    NSArray *exact = [WQMFileCatalog compareOlder:a newer:b exact:YES cancellation:token];
    Check(exact.count == 3, @"exact comparison detects same-size rewritten content");
    Check([exact[0][@"Kind"] isEqual:@"added"] && [exact[1][@"Kind"] isEqual:@"removed"], @"comparison direction is older to newer");
    Write(right, @"Library/config.json", @"CCCC");
    Check([WQMFileCatalog compareOlder:a newer:b exact:YES cancellation:token] == nil, @"a file replaced after indexing invalidates exact comparison");
    [token cancel];
    Check([WQMFileCatalog compareOlder:a newer:b exact:YES cancellation:token] == nil, @"cancellation has no complete result");
    Check(![WQMFileCatalog scanRoot:[left stringByAppendingPathComponent:@"outside"] cancellation:[WQMFileCatalogCancellation new]].complete, @"symlink roots are rejected");
    a.complete = NO;
    Check([WQMFileCatalog compareOlder:a newer:b exact:NO cancellation:[WQMFileCatalogCancellation new]] == nil, @"partial catalog never produces a complete comparison");
    [NSFileManager.defaultManager removeItemAtPath:base error:nil];
} printf("WQM file catalog tests: %s\n", failures ? "FAILED" : "passed"); return failures ? 1 : 0; }
