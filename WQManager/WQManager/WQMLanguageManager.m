#import "WQMLanguageManager.h"

NSNotificationName const WQMLanguageDidChangeNotification = @"WQMLanguageDidChangeNotification";
static NSString *const kWQMLanguagePreference = @"WQManagerLanguage";

@interface WQMLanguageManager () {
    NSBundle *_localizationBundle;
}
@end

@implementation WQMLanguageManager

+ (instancetype)sharedManager
{
    static WQMLanguageManager *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ manager = [self new]; });
    return manager;
}

+ (NSString *)simplifiedChinese { return @"zh-Hans"; }
+ (NSString *)english { return @"en"; }

- (instancetype)init
{
    self = [super init];
    if (self) {
        NSString *saved = [NSUserDefaults.standardUserDefaults stringForKey:kWQMLanguagePreference];
        _languageCode = [saved isEqualToString:self.class.english]
            ? self.class.english : self.class.simplifiedChinese;
        _locale = [NSLocale localeWithLocaleIdentifier:_languageCode];
        NSString *path = [NSBundle.mainBundle pathForResource:_languageCode ofType:@"lproj"];
        _localizationBundle = path ? [NSBundle bundleWithPath:path] : nil;
    }
    return self;
}

- (void)setLanguageCode:(NSString *)languageCode
{
    NSString *normalized = [languageCode isEqualToString:self.class.english]
        ? self.class.english : self.class.simplifiedChinese;
    if ([_languageCode isEqualToString:normalized]) return;
    _languageCode = [normalized copy];
    _locale = [NSLocale localeWithLocaleIdentifier:_languageCode];
    NSString *path = [NSBundle.mainBundle pathForResource:_languageCode ofType:@"lproj"];
    _localizationBundle = path ? [NSBundle bundleWithPath:path] : nil;
    [NSUserDefaults.standardUserDefaults setObject:_languageCode forKey:kWQMLanguagePreference];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:WQMLanguageDidChangeNotification object:nil];
    });
}

- (NSString *)localizedStringForKey:(NSString *)key fallback:(NSString *)fallback
{
    if (!_localizationBundle) return fallback;
    NSString *value = [_localizationBundle localizedStringForKey:key value:fallback table:nil];
    return value.length ? value : fallback;
}

- (NSString *)formattedByteCount:(unsigned long long)byteCount
{
    if (byteCount == 0) return @"0 KB";
    NSArray<NSString *> *units = @[@"B", @"KB", @"MB", @"GB", @"TB", @"PB"];
    double value = (double)byteCount;
    NSUInteger unitIndex = 0;
    while (value >= 1000.0 && unitIndex + 1 < units.count) {
        value /= 1000.0;
        unitIndex++;
    }
    NSNumberFormatter *formatter = [NSNumberFormatter new];
    formatter.locale = self.locale;
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    formatter.minimumFractionDigits = unitIndex == 0 ? 0 : 2;
    formatter.maximumFractionDigits = unitIndex == 0 ? 0 : 2;
    return [NSString stringWithFormat:@"%@ %@",
            [formatter stringFromNumber:@(value)], units[unitIndex]];
}

@end

