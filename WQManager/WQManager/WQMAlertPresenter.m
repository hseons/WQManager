#import "WQMAlertPresenter.h"
#import "WQMLanguageManager.h"

@implementation WQMAlertPresenter

+ (UIWindow *)applicationWindow
{
    UIWindowScene *fallbackScene = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        if (!fallbackScene) fallbackScene = windowScene;
        for (UIWindow *window in windowScene.windows) {
            if (window.isKeyWindow && window.windowLevel <= UIWindowLevelAlert) return window;
        }
    }
    for (UIWindow *window in fallbackScene.windows) {
        if (window.rootViewController && window.windowLevel <= UIWindowLevelAlert) return window;
    }
    return nil;
}

+ (UIViewController *)deepestViewController:(UIViewController *)controller
{
    while (controller.presentedViewController) {
        controller = controller.presentedViewController;
    }
    if ([controller isKindOfClass:UITabBarController.class]) {
        UIViewController *selected = ((UITabBarController *)controller).selectedViewController;
        if (selected) return [self deepestViewController:selected];
    }
    if ([controller isKindOfClass:UINavigationController.class]) {
        UIViewController *top = ((UINavigationController *)controller).topViewController;
        if (top) return [self deepestViewController:top];
    }
    return controller;
}

+ (UIViewController *)topViewController
{
    UIWindow *window = [self applicationWindow];
    if (!window.rootViewController) return nil;
    return [self deepestViewController:window.rootViewController];
}

+ (void)presentViewController:(UIViewController *)viewController
                     animated:(BOOL)animated
                   completion:(void (^)(void))completion
{
    UIViewController *top = [self topViewController];
    if (!top || !top.view.window) {
        top = [self applicationWindow].rootViewController;
    }
    if (!top) {
        if (completion) completion();
        return;
    }
    if (top.presentedViewController) {
        top = [self deepestViewController:top.presentedViewController];
    }
    [top presentViewController:viewController animated:animated completion:completion];
}

+ (void)presentAlertWithTitle:(NSString *)title message:(NSString *)message
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:WQML(@"OK", @"确定") style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
