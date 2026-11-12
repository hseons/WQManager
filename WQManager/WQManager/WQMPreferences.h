#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// User defaults key for the optional second confirmation before cleaning caches.
FOUNDATION_EXPORT NSString * const WQMCleanDoubleConfirmPreferenceKey;

/// Defaults to YES. When enabled, cleaning caches requires typing the
/// confirmation word a second time.
BOOL WQMCleanDoubleConfirmEnabled(void);
void WQMCleanDoubleConfirmSetEnabled(BOOL enabled);

/// How much paced resting backup and restore operations should do.
/// `Standard` runs at full speed. `Automatic` starts at full speed and adds
/// rests only while the device reports a serious thermal state. `LowLoad`
/// always paces the work and may reuse verification results.
typedef NS_ENUM(NSInteger, WQMLoadProfile) {
    WQMLoadProfileStandard = 0,
    WQMLoadProfileAutomatic = 1,
    WQMLoadProfileLowLoad = 2,
};

FOUNDATION_EXPORT NSString * const WQMLoadProfilePreferenceKey;

/// Defaults to `WQMLoadProfileAutomatic`; out-of-range values fall back to it.
WQMLoadProfile WQMLoadProfileCurrent(void);
void WQMLoadProfileSetCurrent(WQMLoadProfile profile);

NS_ASSUME_NONNULL_END
