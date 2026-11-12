#import "WQMPreferences.h"

NSString * const WQMCleanDoubleConfirmPreferenceKey = @"WQMCleanDoubleConfirmEnabled";

BOOL WQMCleanDoubleConfirmEnabled(void)
{
    id value = [NSUserDefaults.standardUserDefaults objectForKey:WQMCleanDoubleConfirmPreferenceKey];
    if (!value) return YES;
    return [NSUserDefaults.standardUserDefaults boolForKey:WQMCleanDoubleConfirmPreferenceKey];
}

void WQMCleanDoubleConfirmSetEnabled(BOOL enabled)
{
    [NSUserDefaults.standardUserDefaults setBool:enabled
                                         forKey:WQMCleanDoubleConfirmPreferenceKey];
}

NSString * const WQMLoadProfilePreferenceKey = @"WQMLoadProfile";

WQMLoadProfile WQMLoadProfileCurrent(void)
{
    id value = [NSUserDefaults.standardUserDefaults objectForKey:WQMLoadProfilePreferenceKey];
    if (![value isKindOfClass:NSNumber.class]) return WQMLoadProfileAutomatic;
    NSInteger raw = [value integerValue];
    if (raw < WQMLoadProfileStandard || raw > WQMLoadProfileLowLoad) return WQMLoadProfileAutomatic;
    return (WQMLoadProfile)raw;
}

void WQMLoadProfileSetCurrent(WQMLoadProfile profile)
{
    [NSUserDefaults.standardUserDefaults setInteger:profile forKey:WQMLoadProfilePreferenceKey];
}
