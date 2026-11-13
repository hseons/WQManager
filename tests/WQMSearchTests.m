#import <Foundation/Foundation.h>
#import "WQMAppModel.h"

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
        WQMAssert([[WQMAppModel searchInitialsForName:@"微信"] isEqualToString:@"wx"],
                  @"微信 should search as wx");
        WQMAssert([[WQMAppModel searchInitialsForName:@"照片"] isEqualToString:@"zp"],
                  @"照片 should search as zp");
        WQMAssert([[WQMAppModel searchInitialsForName:@"剪映"] isEqualToString:@"jy"],
                  @"剪映 should search as jy");
        WQMAssert([[WQMAppModel searchInitialsForName:@"文件"] isEqualToString:@"wj"],
                  @"文件 should search as wj");
        WQMAssert([[WQMAppModel searchInitialsForName:@"WeChat"] isEqualToString:@"w"],
                  @"latin names keep their first letter");
        WQMAssert([[WQMAppModel searchInitialsForName:@"抖音极速版"] isEqualToString:@"dyjsb"],
                  @"every word should contribute an initial");
        WQMAssert([[WQMAppModel searchInitialsForName:@""] isEqualToString:@""],
                  @"empty names have no initials");
        WQMAssert([[WQMAppModel searchInitialsForName:@"  "] isEqualToString:@""],
                  @"whitespace-only names have no initials");

        WQMAppModel *app = [[WQMAppModel alloc] initWithBundleIdentifier:@"com.tencent.xin"
                                                             displayName:@"微信"
                                                           containerPath:@"/tmp/xin"
                                                                dataSize:1024];
        WQMAssert([app.searchInitials isEqualToString:@"wx"], @"model exposes cached initials");
        WQMAssert(app.searchInitials == app.searchInitials, @"initials are computed once per model");
    }

    if (gFailures) {
        fprintf(stderr, "%lu search test(s) failed\n", (unsigned long)gFailures);
        return 1;
    }
    printf("WQM search tests passed\n");
    return 0;
}
