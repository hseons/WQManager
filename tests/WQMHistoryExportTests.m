#import <Foundation/Foundation.h>
#import "WQMOperationStore.h"

static NSUInteger gFailures = 0;

static void WQMAssert(BOOL condition, NSString *message)
{
    if (condition) return;
    gFailures++;
    fprintf(stderr, "FAIL: %s\n", message.UTF8String);
}

int main(void)
{
    @autoreleasepool {
        NSDateComponents *parts = [NSDateComponents new];
        parts.year = 2026;
        parts.month = 11;
        parts.day = 12;
        parts.hour = 10;
        parts.minute = 30;
        parts.second = 15;
        NSDate *day = [NSCalendar.currentCalendar dateFromComponents:parts];
        WQMOperationRecord *first = [WQMOperationRecord new];
        first.identifier = @"a";
        first.kind = WQMOperationKindBackup;
        first.status = WQMOperationStatusSuccess;
        first.appName = @"微信,\"大\"";
        first.bundleIdentifier = @"com.tencent.xin";
        first.scope = @"快速备份";
        first.bytes = 1024;
        first.startedAt = day;

        WQMOperationRecord *second = [WQMOperationRecord new];
        second.identifier = @"b";
        second.kind = WQMOperationKindRestore;
        second.status = WQMOperationStatusFailure;
        second.appName = @"剪映";
        second.startedAt = [day dateByAddingTimeInterval:60];
        second.errorMessage = @"line one\nline two";

        NSString *csv = [WQMOperationStore CSVExportForRecords:@[first, second]];
        WQMAssert([csv hasPrefix:@"\uFEFF"], @"export should start with a UTF-8 byte order mark");

        NSString *body = [csv substringFromIndex:1];
        NSArray<NSString *> *lines = [body componentsSeparatedByString:@"\r\n"];
        WQMAssert(lines.count == 3, @"two records should produce a header and two rows");

        NSArray<NSString *> *headerColumns = [lines[0] componentsSeparatedByString:@","];
        WQMAssert(headerColumns.count == 9, @"header should have nine columns");

        NSString *firstRow = lines[1];
        WQMAssert([firstRow containsString:@"\"微信,\"\"大\"\"\""], @"commas and quotes must be escaped");
        WQMAssert([firstRow containsString:@"快速备份"], @"scope should be exported verbatim");
        WQMAssert([firstRow containsString:@"1024"], @"byte count should be exported");
        WQMAssert([firstRow containsString:@"com.tencent.xin"], @"bundle id should be exported");
        WQMAssert([firstRow hasPrefix:@"2026-11-12 10:30:15,"],
                  @"start time should be formatted as a local second-precision stamp");

        WQMAssert([lines[2] containsString:@"\"line one\nline two\""],
                  @"newlines inside a field must be quoted so the row stays intact");
        WQMAssert([lines[2] componentsSeparatedByString:@"\"line one\nline two\""].count == 2,
                  @"a quoted newline must not split the record");

        NSArray<NSString *> *secondColumns = [lines[2] componentsSeparatedByString:@","];
        WQMAssert(secondColumns.count > 4, @"failure row should still expose the leading columns");
        WQMAssert([secondColumns[6] isEqualToString:@"0"], @"missing byte count should export as zero");

        NSString *name = [WQMOperationStore CSVExportFileNameForDate:day];
        WQMAssert([name hasPrefix:@"WQManager-history-"], @"file name should be prefixed");
        WQMAssert([name hasSuffix:@".csv"], @"file name should end in .csv");
        NSRegularExpression *pattern = [NSRegularExpression regularExpressionWithPattern:
                                        @"^WQManager-history-\\d{8}-\\d{6}\\.csv$" options:0 error:nil];
        WQMAssert([pattern numberOfMatchesInString:name options:0
                                            range:NSMakeRange(0, name.length)] == 1,
                  [NSString stringWithFormat:@"file name should carry a timestamp, got: %@", name]);

        NSString *empty = [WQMOperationStore CSVExportForRecords:@[]];
        WQMAssert([[empty substringFromIndex:1] componentsSeparatedByString:@"\r\n"].count == 1,
                  @"empty export should only contain the header");
    }

    if (gFailures) {
        fprintf(stderr, "%lu export assertion(s) failed\n", (unsigned long)gFailures);
        return 1;
    }
    printf("WQMHistoryExportTests passed\n");
    return 0;
}
