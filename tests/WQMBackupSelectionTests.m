#import <Foundation/Foundation.h>
#import "WQMBackupSelection.h"
#import "WQMBackupStore.h"
static NSUInteger failures;
static void Check(BOOL ok, NSString *message) { if (!ok) { failures++; fprintf(stderr, "FAIL: %s\n", message.UTF8String); } }
int main(void) { @autoreleasepool {
    for (id bad in @[@"", @"/Documents", @"Documents/../Library", @"Library//Caches", @"Library/./Caches", @"Library\\Caches", @"System", @"Documents/\n", @42]) Check(![WQMBackupSelection isAllowedPath:bad], @"invalid selection path rejected");
    Check([[WQMBackupSelection canonicalPaths:@[@"Library/Preferences", @"Documents/a", @"Documents"]] isEqual:@[@"Documents", @"Library/Preferences"]], @"parent selection deduplicates descendants");
    Check([WQMBackupSelection canonicalPaths:@[@"Documents/A", @"Documents/a"]] == nil, @"case aliases rejected");
    Check([WQMBackupSelection canonicalPaths:@[@"Documents/A", @"Documents/a/child"]] == nil, @"case-folded ancestor overlap rejected");
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:[root stringByAppendingPathComponent:@"Library/Preferences"] withIntermediateDirectories:YES attributes:nil error:nil];
    NSMutableDictionary *manifest = [@{@"Format":@3, @"Complete":@YES, @"BundleID":@"com.fixture.app", @"DisplayName":@"Fixture", @"ScopeCode":@"custom", @"Created":NSDate.date,
        @"RequestedParts":@[@"Documents/Missing", @"Library/Preferences"], @"Parts":@[@"Library/Preferences"], @"PartHashes":@{@"Library/Preferences":@"hash"}} mutableCopy];
    NSString *manifestPath = [root stringByAppendingPathComponent:@"manifest.plist"];
    [manifest writeToFile:manifestPath atomically:YES];
    WQMBackupRecord *record = [WQMBackupRecord recordAtPath:root error:nil];
    Check(record && record.formatVersion == 3 && record.requestedParts.count == 2, @"format 3 preserves selected absent directories as well as backed-up directories");
    [fm createDirectoryAtPath:[root stringByAppendingPathComponent:@"Library/Unexpected"] withIntermediateDirectories:YES attributes:nil error:nil];
    Check([WQMBackupRecord recordAtPath:root error:nil] == nil, @"unregistered intermediate siblings rejected");
    [fm removeItemAtPath:[root stringByAppendingPathComponent:@"Library/Unexpected"] error:nil];
    manifest[@"RequestedParts"] = @[@"Library/Preferences/Child"];
    [manifest writeToFile:manifestPath atomically:YES];
    Check([WQMBackupRecord recordAtPath:root error:nil] == nil, @"payload outside requested restore scope rejected");
    manifest[@"RequestedParts"] = @[@"Library/Preferences"];
    [manifest writeToFile:manifestPath atomically:YES];
    [fm moveItemAtPath:[root stringByAppendingPathComponent:@"Library"] toPath:[root stringByAppendingPathComponent:@"Saved"] error:nil];
    [fm createSymbolicLinkAtPath:[root stringByAppendingPathComponent:@"Library"] withDestinationPath:[root stringByAppendingPathComponent:@"Saved"] error:nil];
    Check([WQMBackupRecord recordAtPath:root error:nil] == nil, @"symlink payload ancestors rejected");
    [fm removeItemAtPath:root error:nil];
} printf("WQM backup selection tests: %s\n", failures ? "FAILED" : "passed"); return failures ? 1 : 0; }
