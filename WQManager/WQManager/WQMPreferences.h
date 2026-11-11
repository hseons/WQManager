#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// User defaults key for the optional second confirmation before cleaning caches.
FOUNDATION_EXPORT NSString * const WQMCleanDoubleConfirmPreferenceKey;

/// Defaults to YES. When enabled, cleaning caches requires typing the
/// confirmation word a second time.
BOOL WQMCleanDoubleConfirmEnabled(void);
void WQMCleanDoubleConfirmSetEnabled(BOOL enabled);

NS_ASSUME_NONNULL_END
