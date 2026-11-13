//
//  WQMFilePreviewModel.m
//  WQManager
//

#import "WQMFilePreviewModel.h"

@implementation WQMFilePreviewModel

+ (NSSet<NSString *> *)imageExtensions
{
    static NSSet<NSString *> *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        set = [NSSet setWithArray:@[@"png", @"jpg", @"jpeg", @"heic", @"heif", @"gif",
                                    @"webp", @"bmp", @"tiff", @"tif", @"ico"]];
    });
    return set;
}

+ (NSSet<NSString *> *)textExtensions
{
    static NSSet<NSString *> *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        set = [NSSet setWithArray:@[@"json", @"plist", @"txt", @"md", @"xml", @"csv", @"log",
                                    @"sql", @"js", @"ts", @"html", @"htm", @"css", @"yml",
                                    @"yaml", @"strings", @"conf", @"ini", @"sh", @"pbxproj"]];
    });
    return set;
}

+ (NSSet<NSString *> *)videoExtensions
{
    static NSSet<NSString *> *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        set = [NSSet setWithArray:@[@"mp4", @"mov", @"m4v", @"avi", @"mkv", @"3gp"]];
    });
    return set;
}

+ (NSSet<NSString *> *)audioExtensions
{
    static NSSet<NSString *> *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        set = [NSSet setWithArray:@[@"mp3", @"m4a", @"wav", @"aac", @"caf", @"flac"]];
    });
    return set;
}

+ (WQMFilePreviewKind)kindForPath:(NSString *)path
{
    NSString *ext = path.pathExtension.lowercaseString;
    if (!ext.length) return WQMFilePreviewKindUnknown;
    if ([[self imageExtensions] containsObject:ext]) return WQMFilePreviewKindImage;
    if ([[self textExtensions] containsObject:ext]) return WQMFilePreviewKindText;
    if ([[self videoExtensions] containsObject:ext]) return WQMFilePreviewKindVideo;
    if ([[self audioExtensions] containsObject:ext]) return WQMFilePreviewKindAudio;
    return WQMFilePreviewKindUnknown;
}

+ (BOOL)isJSONPath:(NSString *)path
{
    return [path.pathExtension.lowercaseString isEqualToString:@"json"];
}

+ (NSData *)headOfFile:(NSString *)path maxBytes:(NSUInteger)maxBytes
{
    if (!path.length || maxBytes == 0) return nil;
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!handle) return nil;
    NSData *data = nil;
    @try {
        data = [handle readDataOfLength:maxBytes];
    } @catch (__unused NSException *exception) {
        data = nil;
    }
    [handle closeFile];
    return data;
}

+ (NSString *)stringForData:(NSData *)data
{
    if (!data.length) return @"";
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (text) return text;
    text = [[NSString alloc] initWithData:data encoding:NSUTF16StringEncoding];
    if (text) return text;
    return [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] ?: @"";
}

+ (NSString *)textForData:(NSData *)data maxBytes:(NSUInteger)maxBytes truncated:(BOOL *)truncated
{
    if (!data) return nil;
    BOOL cut = data.length >= maxBytes;
    NSData *head = cut ? [data subdataWithRange:NSMakeRange(0, maxBytes)] : data;
    if (truncated) *truncated = cut;
    return [self stringForData:head];
}

+ (NSString *)prettyJSONForData:(NSData *)data maxBytes:(NSUInteger)maxBytes
{
    if (!data.length || data.length > maxBytes) return nil;
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (!object) return nil;
    NSData *pretty = [NSJSONSerialization dataWithJSONObject:object
                                                     options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                       error:NULL];
    if (!pretty) return nil;
    return [[NSString alloc] initWithData:pretty encoding:NSUTF8StringEncoding];
}

+ (NSString *)hexDumpForData:(NSData *)data maxBytes:(NSUInteger)maxBytes
{
    if (!data.length || maxBytes == 0) return @"";
    NSUInteger length = MIN(data.length, maxBytes);
    const unsigned char *bytes = data.bytes;
    NSMutableString *dump = [NSMutableString string];
    // Eight bytes per line so the ASCII gutter still fits an iPhone at 12 pt monospace.
    const NSUInteger perLine = 8;
    for (NSUInteger offset = 0; offset < length; offset += perLine) {
        NSUInteger lineLength = MIN(perLine, length - offset);
        [dump appendFormat:@"%08lX  ", (unsigned long)offset];
        NSMutableString *ascii = [NSMutableString string];
        for (NSUInteger i = 0; i < perLine; i++) {
            if (i < lineLength) {
                unsigned char byte = bytes[offset + i];
                [dump appendFormat:@"%02X ", byte];
                if (byte >= 0x20 && byte < 0x7F) {
                    [ascii appendFormat:@"%c", byte];
                } else {
                    [ascii appendString:@"."];
                }
            } else {
                [dump appendString:@"   "];
            }
        }
        [dump appendFormat:@" |%@|\n", ascii];
    }
    return dump;
}

@end
