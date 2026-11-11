#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface WQMConsentStore : NSObject

+ (NSString *)currentDisclaimerVersion;
+ (NSString *)disclaimerText;
+ (BOOL)hasAcceptedCurrentDisclaimer;
+ (void)acceptCurrentDisclaimer;
+ (void)resetConsent;

@end

NS_ASSUME_NONNULL_END

