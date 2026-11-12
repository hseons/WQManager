//
//  SceneDelegate.m
//  WQManager
//
//  Created by 木木 on 2026/11/10.
//

#import "SceneDelegate.h"
#import "WQMConsentStore.h"
#import "WQMLegalViewController.h"
#import "WQMLanguageManager.h"
#import "WQMMainTabBarController.h"
#import "WQMSharedInbox.h"
#import "WQMTheme.h"
#import "WQMHousekeeping.h"
#import "WQMStorageViewController.h"
#if DEBUG
#import "WQMLongOperationBanner.h"
#endif

@interface SceneDelegate ()

@property (nonatomic, strong) NSURL *pendingImportURL;
@property (nonatomic) BOOL processingSharedInbox;
@property (nonatomic) BOOL pendingManualImportPicker;

@end

@implementation SceneDelegate


- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:UIWindowScene.class]) return;

    UIWindow *window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window = window;
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(languageDidChange:)
                                               name:WQMLanguageDidChangeNotification
                                             object:nil];
    [self showLegalGateIfNeeded];
    [window makeKeyAndVisible];
    [WQMHousekeeping runAtLaunch];
#if DEBUG
    if (getenv("WQM_UI_STORAGE")) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            UIViewController *root = self.window.rootViewController;
            if ([root isKindOfClass:UITabBarController.class]) {
                root = ((UITabBarController *)root).selectedViewController;
            }
            if ([root isKindOfClass:UINavigationController.class]) {
                [(UINavigationController *)root pushViewController:[WQMStorageViewController new]
                                                          animated:NO];
            }
        });
    }
    if (getenv("WQM_BANNER_DEMO")) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [WQMLongOperationBanner.shared
                showWithTitle:WQML(@"RESTORE_PROGRESS_TITLE", @"正在恢复")
                       status:WQML(@"IMPORT_VERIFYING", @"校验备份包…")
                cancelHandler:^{}];
        });
    }
#endif
    [self enqueueImportFromURLContexts:connectionOptions.URLContexts];
    [self enqueuePendingSharedInbox];
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)languageDidChange:(__unused NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{ [self rebuildRootForCurrentLanguage]; });
}

- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts
{
    [self enqueueImportFromURLContexts:URLContexts];
}

- (void)enqueueImportFromURLContexts:(NSSet<UIOpenURLContext *> *)contexts
{
    BOOL requestedSharedImport = NO;
    for (UIOpenURLContext *context in contexts) {
        NSURL *url = context.URL;
        if ([url.scheme caseInsensitiveCompare:@"wqmanager"] == NSOrderedSame &&
            [url.host caseInsensitiveCompare:@"import"] == NSOrderedSame) {
            self.pendingManualImportPicker = YES;
            requestedSharedImport = YES;
            continue;
        }
        if (!url.isFileURL ||
            [url.pathExtension caseInsensitiveCompare:@"wqbackup"] != NSOrderedSame) {
            continue;
        }
        self.pendingManualImportPicker = NO;
        self.pendingImportURL = url;
        break;
    }
    if (requestedSharedImport) {
        [self enqueuePendingSharedInbox];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{ [self processPendingImport]; });
    }
}

- (void)enqueuePendingSharedInbox
{
    if (self.pendingImportURL || self.processingSharedInbox) return;
    self.processingSharedInbox = YES;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        NSURL *url = [WQMSharedInbox takeNextPendingURL:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.processingSharedInbox = NO;
            if (!url) {
                if (self.pendingManualImportPicker) [self processPendingImport];
                return;
            }
            self.pendingManualImportPicker = NO;
            self.pendingImportURL = url;
            [self processPendingImport];
        });
    });
}

- (void)processPendingImport
{
    NSURL *url = self.pendingImportURL;
    BOOL manualPicker = self.pendingManualImportPicker;
    if ((!url && !manualPicker) || ![WQMConsentStore hasAcceptedCurrentDisclaimer]) return;
    WQMMainTabBarController *main = nil;
    UIViewController *root = self.window.rootViewController;
    if ([root isKindOfClass:WQMMainTabBarController.class]) {
        main = (WQMMainTabBarController *)root;
    } else if ([root isKindOfClass:UINavigationController.class]) {
        UINavigationController *navigation = (UINavigationController *)root;
        if ([navigation.viewControllers.firstObject isKindOfClass:WQMLegalViewController.class]) {
            return;
        }
    }
    if (!main) {
        [self showLegalGateIfNeeded];
        root = self.window.rootViewController;
        if (![root isKindOfClass:WQMMainTabBarController.class]) return;
        main = (WQMMainTabBarController *)root;
    }
    if (!url && manualPicker) {
        self.pendingManualImportPicker = NO;
        [self.window makeKeyAndVisible];
        [main openImportPicker];
        return;
    }
    self.pendingImportURL = nil;
    [self.window makeKeyAndVisible];
    [main openSharedBackupAtURL:url];
}

- (void)showLegalGateIfNeeded
{
    if ([WQMConsentStore hasAcceptedCurrentDisclaimer]) {
        WQMMainTabBarController *main = [WQMMainTabBarController new];
        self.window.rootViewController = main;
        return;
    }

    WQMLegalViewController *legal = [WQMLegalViewController new];
    __weak typeof(self) weakSelf = self;
    legal.acceptanceHandler = ^{
        weakSelf.window.rootViewController = [WQMMainTabBarController new];
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf processPendingImport]; });
    };
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:legal];
    navigation.navigationBar.prefersLargeTitles = YES;
    [WQMTheme configureNavigationBar:navigation.navigationBar];
    self.window.rootViewController = navigation;
}

- (void)rebuildRootForCurrentLanguage
{
    NSInteger selectedIndex = 0;
    UIViewController *current = self.window.rootViewController;
    if ([current isKindOfClass:WQMMainTabBarController.class]) {
        selectedIndex = ((WQMMainTabBarController *)current).selectedIndex;
    }
    [self showLegalGateIfNeeded];
    UIViewController *rebuilt = self.window.rootViewController;
    if ([rebuilt isKindOfClass:WQMMainTabBarController.class]) {
        ((WQMMainTabBarController *)rebuilt).selectedIndex = selectedIndex;
    }
    dispatch_async(dispatch_get_main_queue(), ^{ [self processPendingImport]; });
}


- (void)sceneDidDisconnect:(UIScene *)scene {
    // Called as the scene is being released by the system.
    // This occurs shortly after the scene enters the background, or when its session is discarded.
    // Release any resources associated with this scene that can be re-created the next time the scene connects.
    // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
}


- (void)sceneDidBecomeActive:(UIScene *)scene {
    [self enqueuePendingSharedInbox];
}


- (void)sceneWillResignActive:(UIScene *)scene {
    // Called when the scene will move from an active state to an inactive state.
    // This may occur due to temporary interruptions (ex. an incoming phone call).
}


- (void)sceneWillEnterForeground:(UIScene *)scene {
    // Called as the scene transitions from the background to the foreground.
    // Use this method to undo the changes made on entering the background.
}


- (void)sceneDidEnterBackground:(UIScene *)scene {
    // Called as the scene transitions from the foreground to the background.
    // Use this method to save data, release shared resources, and store enough scene-specific state information
    // to restore the scene back to its current state.
}


@end
