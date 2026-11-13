#import <Foundation/Foundation.h>
#import "WQMFilePreviewModel.h"

static void WQMAssert(BOOL condition, NSString *message);

static void WQMAssert(BOOL condition, NSString *message)
{
    if (!condition) {
        fprintf(stderr, "FAILED: %s\n", message.UTF8String);
        exit(1);
    }
}

int main(void)
{
    @autoreleasepool {
        WQMAssert([WQMFilePreviewModel kindForPath:@"/tmp/a.PNG"] == WQMFilePreviewKindImage, @"png is image");
        WQMAssert([WQMFilePreviewModel kindForPath:@"settings.json"] == WQMFilePreviewKindText, @"json is text");
        WQMAssert([WQMFilePreviewModel kindForPath:@"notes.md"] == WQMFilePreviewKindText, @"md is text");
        WQMAssert([WQMFilePreviewModel kindForPath:@"clip.mp4"] == WQMFilePreviewKindVideo, @"mp4 is video");
        WQMAssert([WQMFilePreviewModel kindForPath:@"voice.m4a"] == WQMFilePreviewKindAudio, @"m4a is audio");
        WQMAssert([WQMFilePreviewModel kindForPath:@"chat.db"] == WQMFilePreviewKindUnknown, @"db is binary");
        WQMAssert([WQMFilePreviewModel kindForPath:@"noext"] == WQMFilePreviewKindUnknown, @"no ext is binary");
        WQMAssert([WQMFilePreviewModel isJSONPath:@"Settings.JSON"], @"json detection is case insensitive");

        const unsigned char bytes[16] = {'{', '"', 'a', '"', ':', '1', '}', '\n', 'h', 'e', 'l', 'l', 'o', 0x00, 0xFF, 'z'};
        NSData *data = [NSData dataWithBytes:bytes length:sizeof(bytes)];
        NSString *dump = [WQMFilePreviewModel hexDumpForData:data maxBytes:sizeof(bytes)];
        WQMAssert([dump hasPrefix:@"00000000  7B 22 61 22 3A 31 7D 0A  |{\"a\":1}.|"],
                  @"first line keeps offset, bytes and ascii gutter");
        WQMAssert([dump containsString:@"00000008  68 65 6C 6C 6F 00 FF 7A  |hello..z|"],
                  @"second line starts at offset 8");

        NSString *shortDump = [WQMFilePreviewModel hexDumpForData:data maxBytes:4];
        WQMAssert([shortDump componentsSeparatedByString:@"\n"].count == 2, @"maxBytes truncates to a single line");

        NSString *text = [WQMFilePreviewModel textForData:[@"hello" dataUsingEncoding:NSUTF8StringEncoding]
                                                 maxBytes:1024 truncated:NULL];
        WQMAssert([text isEqualToString:@"hello"], @"utf8 text survives");

        BOOL truncated = NO;
        NSString *cut = [WQMFilePreviewModel textForData:[@"abcdefghij" dataUsingEncoding:NSUTF8StringEncoding]
                                                maxBytes:4 truncated:&truncated];
        WQMAssert(truncated && [cut isEqualToString:@"abcd"], @"text truncation is reported");

        NSData *json = [@"{\"b\":2,\"a\":[1,true]}" dataUsingEncoding:NSUTF8StringEncoding];
        NSString *pretty = [WQMFilePreviewModel prettyJSONForData:json maxBytes:1024];
        WQMAssert([pretty containsString:@"\"a\" : ["], @"pretty json is expanded");
        WQMAssert([WQMFilePreviewModel prettyJSONForData:[@"not json" dataUsingEncoding:NSUTF8StringEncoding]
                                                maxBytes:1024] == nil, @"invalid json returns nil");
        WQMAssert([WQMFilePreviewModel prettyJSONForData:json maxBytes:4] == nil, @"oversized json is skipped");

        WQMAssert([WQMFilePreviewModel hexDumpForData:[NSData data] maxBytes:16].length == 0, @"empty data yields empty dump");
        printf("WQM file preview tests passed\n");
    }
    return 0;
}
