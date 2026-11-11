//
//  main.m
//  WQManager
//
//  Created by 木木 on 2026/11/10.
//

#import <UIKit/UIKit.h>
#import "AppDelegate.h"
#import "WQAccess.h"
#import "WQLaunchServices.h"

int main(int argc, char * argv[]) {
    NSString * appDelegateClassName;
    @autoreleasepool {
        // Resolve app and extension container identifiers from Apple's
        // LaunchServices database when the container metadata can't be read.
        wq_set_container_label_resolver(wq_bundle_id_for_container);
        wq_set_container_list_provider(wq_ls_container_paths);
        // This milestone does not start the minutes-long full inode scan.
        wq_set_full_scan_ui(NULL, NULL);
        appDelegateClassName = NSStringFromClass([AppDelegate class]);
    }
    return UIApplicationMain(argc, argv, nil, appDelegateClassName);
}
