#import "WQMConsentStore.h"
#import "WQMLanguageManager.h"

static NSString *const kWQMAcceptedDisclaimerVersion = @"WQMAcceptedDisclaimerVersion";

@implementation WQMConsentStore

+ (NSString *)currentDisclaimerVersion
{
    return @"2026-11-10-v1";
}

+ (NSString *)disclaimerText
{
    if ([[WQMLanguageManager sharedManager].languageCode isEqualToString:[WQMLanguageManager english]]) {
        return
        @"WQManager is experimental open-source software that can read, copy, modify, replace, or delete app data.\n\n"
        @"Before continuing:\n"
        @"• Keep an independent backup of important data.\n"
        @"• Close the target app during backup, restore, replace, and cleanup.\n"
        @"• A successful restore does not guarantee that login state, purchases, Keychain items, or App Group data can migrate.\n"
        @"• Cleanup, replace, and restore require a scope preview and two independent confirmations.\n"
        @"• System data, system caches, crash reports, App Groups, and Keychain are outside this app's scope.\n\n"
        @"You are responsible for data loss, account issues, app failures, or other damage caused by using this software. "
        @"WQManager is not affiliated with Apple or the developers of managed apps.";
    }
    return
    @"WQManager 是实验性开源软件，可读取、复制、修改、替换或删除应用数据。\n\n"
    @"使用前请确认：\n"
    @"• 重要数据应保留独立备份。\n"
    @"• 备份、恢复、替换和清理期间应关闭目标 App。\n"
    @"• 恢复成功不代表登录状态、购买记录、Keychain 或 App Group 数据可以迁移。\n"
    @"• 清理、替换和恢复前需要完成范围提示与二次确认。\n"
    @"• 系统数据、系统缓存、崩溃日志、App Groups 和 Keychain 不在本应用处理范围。\n\n"
    @"因使用本软件导致的数据丢失、账号异常、App 故障或其他损失，由使用者自行承担。"
    @"本软件与 Apple 及被管理的 App 开发者无关联。";
}

+ (BOOL)hasAcceptedCurrentDisclaimer
{
    NSString *accepted = [NSUserDefaults.standardUserDefaults stringForKey:kWQMAcceptedDisclaimerVersion];
    return [accepted isEqualToString:self.currentDisclaimerVersion];
}

+ (void)acceptCurrentDisclaimer
{
    [NSUserDefaults.standardUserDefaults setObject:self.currentDisclaimerVersion
                                            forKey:kWQMAcceptedDisclaimerVersion];
}

+ (void)resetConsent
{
    [NSUserDefaults.standardUserDefaults removeObjectForKey:kWQMAcceptedDisclaimerVersion];
}

@end

