#import <Foundation/Foundation.h>
#import <sqlite3.h>
#import "WQMStructuredFile.h"
static NSUInteger failures;
static void Check(BOOL ok, NSString *message) { if (!ok) { failures++; fprintf(stderr, "FAIL: %s\n", message.UTF8String); } }
int main(void) { @autoreleasepool {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *plistPath = [root stringByAppendingPathComponent:@"test.plist"];
    NSDictionary *plist = @{@"nested":@[@1, @YES, @"中文"], @"bytes":[@"fixture" dataUsingEncoding:NSUTF8StringEncoding]};
    for (NSNumber *format in @[@(NSPropertyListBinaryFormat_v1_0), @(NSPropertyListXMLFormat_v1_0)]) {
        [[NSPropertyListSerialization dataWithPropertyList:plist format:format.integerValue options:0 error:nil] writeToFile:plistPath atomically:YES];
        WQMStructuredFile *file = [[WQMStructuredFile alloc] initWithPath:plistPath error:nil];
        Check([file.propertyList isEqual:plist], @"binary and XML plist preserve typed tree values");
        NSString *workspace = file.workspace; file = nil;
        Check(![fm fileExistsAtPath:workspace], @"workspace removed when inspector is released");
    }
    NSString *dbPath = [root stringByAppendingPathComponent:@"test.sqlite"];
    sqlite3 *source = NULL;
    Check(sqlite3_open(dbPath.fileSystemRepresentation, &source) == SQLITE_OK, @"source fixture opens");
    Check(sqlite3_exec(source, "PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0; CREATE TABLE \"odd\"\"name\" (id INTEGER, value TEXT, bytes BLOB); WITH RECURSIVE seq(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM seq WHERE n<205) INSERT INTO \"odd\"\"name\" SELECT n, CASE WHEN n=1 THEN '=formula' ELSE '中文' END, x'CAFE' FROM seq;", NULL, NULL, NULL) == SQLITE_OK, @"WAL-only committed rows prepared");
    NSData *mainBefore = [NSData dataWithContentsOfFile:dbPath], *walBefore = [NSData dataWithContentsOfFile:[dbPath stringByAppendingString:@"-wal"]];
    NSError *error;
    WQMStructuredFile *file = [[WQMStructuredFile alloc] initWithPath:dbPath error:&error];
    Check(file != nil && file.tables.count == 1, @"working copy sees table stored in WAL");
    NSString *table = @"odd\"name";
    NSArray *rows = [file rowsForTable:table offset:0 error:&error];
    Check(rows.count == 100 && [rows[0][@"Values"][1] isEqual:@"=formula"], @"first page bounded at 100 rows");
    Check([rows[0][@"Values"][2] isEqual:@"<BLOB: 2 bytes>"], @"BLOB rendered without materializing contents");
    Check([file rowsForTable:table offset:100 error:nil].count == 100 && [file rowsForTable:table offset:200 error:nil].count == 5, @"page offsets cover remaining rows");
    Check([file rowsForTable:@"odd; DROP TABLE test" offset:0 error:nil] == nil, @"only catalogued table names are accepted");
    NSURL *csv = [file exportTable:table error:&error];
    NSString *text = [NSString stringWithContentsOfURL:csv encoding:NSUTF8StringEncoding error:nil];
    Check([text containsString:@"'=formula"] && [text containsString:@"中文"], @"CSV quotes UTF-8 and neutralizes spreadsheet formulas");
    Check([mainBefore isEqual:[NSData dataWithContentsOfFile:dbPath]] && [walBefore isEqual:[NSData dataWithContentsOfFile:[dbPath stringByAppendingString:@"-wal"]]], @"source database and WAL are unchanged by inspection/export");
    file.cancelled = YES;
    Check([file rowsForTable:table offset:0 error:nil] == nil, @"cancelled reads return no page");
    file = nil;
    sqlite3_exec(source, "CREATE TABLE oversized(value TEXT); INSERT INTO oversized SELECT replace(hex(zeroblob(6000)), '00', 'a'); CREATE TABLE many(value); WITH RECURSIVE seq(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM seq WHERE n<10001) INSERT INTO many SELECT n FROM seq;", NULL, NULL, NULL);
    file = [[WQMStructuredFile alloc] initWithPath:dbPath error:nil];
    NSString *value = [file rowsForTable:@"oversized" offset:0 error:nil][0][@"Values"][0];
    Check(value.length == 4097 && [value hasSuffix:@"…"], @"large cell display bounded and marked");
    file = nil;
    sqlite3_exec(source, "CREATE TABLE unicode(value TEXT); INSERT INTO unicode SELECT replace(hex(zeroblob(2000)), '00', '中');", NULL, NULL, NULL);
    file = [[WQMStructuredFile alloc] initWithPath:dbPath error:nil];
    value = [file rowsForTable:@"unicode" offset:0 error:nil][0][@"Values"][0];
    Check(value.length == 1366 && [value hasPrefix:@"中中"] && [value hasSuffix:@"…"], @"bounded UTF-8 database cells retain the complete prefix");
    Check([file exportTable:@"many" error:nil] == nil, @"oversized export is rejected without a partial CSV");
    NSString *workspace = file.workspace;
    Check([fm contentsOfDirectoryAtPath:workspace error:nil].count <= 4, @"failed export does not leave CSV artifacts");
    file = nil; sqlite3_close(source);
    NSString *walFixture = [root stringByAppendingPathComponent:@"linked-wal.sqlite"];
    Check([fm copyItemAtPath:dbPath toPath:walFixture error:nil], @"independent WAL-link fixture created");
    Check([fm createSymbolicLinkAtPath:[walFixture stringByAppendingString:@"-wal"] withDestinationPath:plistPath error:nil], @"WAL link fixture created");
    Check([[WQMStructuredFile alloc] initWithPath:walFixture error:nil] == nil, @"linked WAL rejected before opening SQLite");
    NSString *link = [root stringByAppendingPathComponent:@"link.sqlite"];
    [fm createSymbolicLinkAtPath:link withDestinationPath:dbPath error:nil];
    Check([[WQMStructuredFile alloc] initWithPath:link error:nil] == nil, @"linked database rejected");
    [@"invalid database" writeToFile:dbPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    Check([[WQMStructuredFile alloc] initWithPath:dbPath error:nil] == nil, @"corrupt database rejected");
    [@"invalid plist" writeToFile:plistPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    Check([[WQMStructuredFile alloc] initWithPath:plistPath error:nil] == nil, @"corrupt plist rejected");
    NSFileHandle *large = [NSFileHandle fileHandleForWritingAtPath:plistPath]; [large truncateFileAtOffset:9 * 1024 * 1024]; [large closeFile];
    Check([[WQMStructuredFile alloc] initWithPath:plistPath error:nil] == nil, @"oversized plist rejected before decoding");
    [@"journal" writeToFile:[dbPath stringByAppendingString:@"-journal"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    Check([[WQMStructuredFile alloc] initWithPath:dbPath error:nil] == nil, @"active rollback journal fails closed");
    [fm removeItemAtPath:[dbPath stringByAppendingString:@"-journal"] error:nil];
    large = [NSFileHandle fileHandleForWritingAtPath:dbPath]; [large truncateFileAtOffset:513ULL * 1024 * 1024]; [large closeFile];
    Check([[WQMStructuredFile alloc] initWithPath:dbPath error:nil] == nil, @"oversized sparse database rejected before copying");
    [fm removeItemAtPath:root error:nil];
} printf("WQM structured file tests: %s\n", failures ? "FAILED" : "passed"); return failures ? 1 : 0; }
