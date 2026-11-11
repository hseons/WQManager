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
