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

NSString * const WQMBackupRetentionPreferenceKey = @"WQMBackupRetentionLimit";

NSInteger WQMBackupRetentionLimit(void)
{
    id value = [NSUserDefaults.standardUserDefaults objectForKey:WQMBackupRetentionPreferenceKey];
    if (![value isKindOfClass:NSNumber.class]) return 0;
    NSInteger limit = [value integerValue];
    if (limit == 1 || limit == 3 || limit == 5 || limit == 10) return limit;
    return 0;
}

void WQMBackupRetentionSetLimit(NSInteger limit)
{
    [NSUserDefaults.standardUserDefaults setInteger:limit forKey:WQMBackupRetentionPreferenceKey];
}
