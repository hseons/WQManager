#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const WQMLanguageDidChangeNotification;

@interface WQMLanguageManager : NSObject

+ (instancetype)sharedManager;

@property (nonatomic, copy, readonly) NSString *languageCode;
@property (nonatomic, strong, readonly) NSLocale *locale;

+ (NSString *)simplifiedChinese;
+ (NSString *)english;

- (void)setLanguageCode:(NSString *)languageCode;
- (NSString *)localizedStringForKey:(NSString *)key fallback:(NSString *)fallback;
- (NSString *)formattedByteCount:(unsigned long long)byteCount;

@end

static inline NSString *WQML(NSString *key, NSString *fallback)
{
    return [[WQMLanguageManager sharedManager] localizedStringForKey:key fallback:fallback];
}

static inline NSString *WQMFormatBytes(unsigned long long byteCount)
{
    return [[WQMLanguageManager sharedManager] formattedByteCount:byteCount];
}

NS_ASSUME_NONNULL_END

