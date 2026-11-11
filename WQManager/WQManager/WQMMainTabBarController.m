#import "WQMMainTabBarController.h"
#import "WQMAppModel.h"
#import "WQMAppsViewController.h"
#import "WQMBackupsViewController.h"
#import "WQMCleanerViewController.h"
#import "WQMHistoryViewController.h"
#import "WQMLanguageManager.h"
#import "WQMRestoreService.h"
#import "WQMSettingsViewController.h"
#import "WQMTheme.h"

@interface WQMMainTabBarController () {
    NSURL *_pendingSharedBackupURL;
    BOOL _hasAppeared;
}
@end

@implementation WQMMainTabBarController

- (void)viewDidLoad
{
    [super viewDidLoad];

    WQMAppsViewController *appsRoot = [WQMAppsViewController new];
    UINavigationController *apps = [[UINavigationController alloc] initWithRootViewController:appsRoot];
    apps.navigationBar.prefersLargeTitles = YES;
    apps.tabBarItem = [[UITabBarItem alloc] initWithTitle:WQML(@"TAB_APPS", @"应用")
                                                   image:[self tabImageNamed:@"AppsTab" fallback:@"square.grid.2x2"]
                                                     tag:0];

    WQMBackupsViewController *backupsRoot = [WQMBackupsViewController new];
    UINavigationController *backups = [[UINavigationController alloc] initWithRootViewController:backupsRoot];
    backups.navigationBar.prefersLargeTitles = YES;
    backups.tabBarItem = [[UITabBarItem alloc] initWithTitle:WQML(@"TAB_BACKUPS", @"备份")
                                                      image:[UIImage systemImageNamed:@"externaldrive.fill.badge.timemachine"]
                                                        tag:0];

    WQMCleanerViewController *cleanerRoot = [WQMCleanerViewController new];
    UINavigationController *cleaner = [[UINavigationController alloc] initWithRootViewController:cleanerRoot];
    cleaner.navigationBar.prefersLargeTitles = YES;
    cleaner.tabBarItem = [[UITabBarItem alloc] initWithTitle:WQML(@"TAB_CLEAN", @"清理")
                                                     image:[self tabImageNamed:@"Broom" fallback:@"trash"]
                                                       tag:0];

    WQMHistoryViewController *historyRoot = [WQMHistoryViewController new];
    UINavigationController *history = [[UINavigationController alloc] initWithRootViewController:historyRoot];
    history.navigationBar.prefersLargeTitles = YES;
    history.tabBarItem = [[UITabBarItem alloc] initWithTitle:WQML(@"TAB_HISTORY", @"记录")
                                                      image:[UIImage systemImageNamed:@"clock.arrow.circlepath"]
                                                        tag:0];

    UINavigationController *settings = [self settingsNavigationController];

    self.viewControllers = @[apps, backups, cleaner, history, settings];
    self.delegate = self;
    self.tabBar.tintColor = [WQMTheme accentColor];
    self.tabBar.unselectedItemTintColor = WQMTheme.textSecondaryColor;
    self.view.backgroundColor = WQMTheme.canvasColor;
    for (UINavigationController *navigation in self.viewControllers) {
        [WQMTheme configureNavigationBar:navigation.navigationBar];
    }
}

- (void)tabBarController:(UITabBarController *)tabBarController
 didSelectViewController:(UIViewController *)viewController
{
    for (UIViewController *controller in tabBarController.viewControllers) {
        [controller.view endEditing:YES];
    }
    [self.view endEditing:YES];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    _hasAppeared = YES;
    if (_pendingSharedBackupURL) {
        [self consumePendingSharedBackup];
        return;
    }
    static BOOL checkedRecovery;
    if (checkedRecovery) return;
    checkedRecovery = YES;
#if DEBUG
    NSString *fixtureTab = NSProcessInfo.processInfo.environment[@"WQM_UI_FIXTURES_TAB"];
    if (fixtureTab.length) {
        NSInteger index = fixtureTab.integerValue;
        if (index >= 0 && index < (NSInteger)self.viewControllers.count) self.selectedIndex = index;
        return;
    }
#endif
    if ([WQMRestoreService activeRecoverySummary]) self.selectedIndex = 1;
}

- (void)openSharedBackupAtURL:(NSURL *)url
{
    if (!url.isFileURL) return;
    _pendingSharedBackupURL = url;
    if (_hasAppeared) [self consumePendingSharedBackup];
}

- (void)consumePendingSharedBackup
{
    NSURL *url = _pendingSharedBackupURL;
    if (!url) return;
    _pendingSharedBackupURL = nil;
    self.selectedIndex = 1;
    dispatch_async(dispatch_get_main_queue(), ^{
        UINavigationController *navigation = self.viewControllers[1];
        [navigation popToRootViewControllerAnimated:NO];
        WQMBackupsViewController *backups = navigation.viewControllers.firstObject;
        [backups importBackupAtURL:url];
    });
}

- (void)openImportPicker
{
    self.selectedIndex = 1;
    dispatch_async(dispatch_get_main_queue(), ^{
        UINavigationController *navigation = self.viewControllers[1];
        [navigation popToRootViewControllerAnimated:NO];
        WQMBackupsViewController *backups = navigation.viewControllers.firstObject;
        [backups presentImportPicker];
    });
}

- (UINavigationController *)navigationControllerWithTitle:(NSString *)title
                                                   symbol:(NSString *)symbol
                                                  message:(NSString *)message
{
    UIViewController *root = [WQMTheme placeholderViewControllerWithTitle:title symbol:symbol message:message];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:root];
    navigation.navigationBar.prefersLargeTitles = YES;
    navigation.tabBarItem = [[UITabBarItem alloc] initWithTitle:title image:[UIImage systemImageNamed:symbol] tag:0];
    navigation.tabBarItem.title = title;
    return navigation;
}

- (UINavigationController *)settingsNavigationController
{
    WQMSettingsViewController *root = [WQMSettingsViewController new];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:root];
    navigation.navigationBar.prefersLargeTitles = YES;
    navigation.tabBarItem = [[UITabBarItem alloc] initWithTitle:WQML(@"TAB_SETTINGS", @"设置")
                                                         image:[UIImage systemImageNamed:@"gearshape"]
                                                           tag:0];
    return navigation;
}

- (UIImage *)tabImageNamed:(NSString *)name fallback:(NSString *)symbol
{
    UIImage *image = [UIImage imageNamed:name];
    if (!image) return [UIImage systemImageNamed:symbol];
    CGSize size = CGSizeMake(25, 25);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    UIImage *scaled = [renderer imageWithActions:^(UIGraphicsImageRendererContext *__unused context) {
        [image drawInRect:CGRectMake(0, 0, size.width, size.height)];
    }];
    return [scaled imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

@end
