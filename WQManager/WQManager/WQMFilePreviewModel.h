//
//  WQMFilePreviewModel.h
//  WQManager
//
//  Pure formatting and classification for the space lens file previewer.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, WQMFilePreviewKind) {
    WQMFilePreviewKindUnknown = 0,
    WQMFilePreviewKindImage,
    WQMFilePreviewKindText,
    WQMFilePreviewKindVideo,
    WQMFilePreviewKindAudio,
};

NS_ASSUME_NONNULL_BEGIN

@interface WQMFilePreviewModel : NSObject

+ (WQMFilePreviewKind)kindForPath:(NSString *)path;
+ (BOOL)isJSONPath:(NSString *)path;

/// Reads at most maxBytes from the head of the file, so a 3 GB database stays cheap.
+ (nullable NSData *)headOfFile:(NSString *)path maxBytes:(NSUInteger)maxBytes;

/// UTF-8 first, then a lossy fallback. Sets truncated when the file is longer than maxBytes.
+ (nullable NSString *)textForData:(NSData *)data
                          maxBytes:(NSUInteger)maxBytes
                         truncated:(nullable BOOL *)truncated;

/// Pretty prints valid JSON, returns nil when the payload is not JSON.
+ (nullable NSString *)prettyJSONForData:(NSData *)data maxBytes:(NSUInteger)maxBytes;

/// Classic 16 bytes per line dump with an ASCII gutter.
+ (NSString *)hexDumpForData:(NSData *)data maxBytes:(NSUInteger)maxBytes;

@end

NS_ASSUME_NONNULL_END
