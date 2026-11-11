//
//  WQMAppIconService.h
//  WQManager
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const WQMAppIconDidResolveNotification;
extern NSString *const WQMAppIconBundleIdentifierKey;

@interface WQMAppIconService : NSObject

+ (UIImage *)iconForBundleIdentifier:(NSString *_Nullable)bundleIdentifier
                         displayName:(NSString *_Nullable)displayName;
+ (void)requestIconForBundleIdentifier:(NSString *_Nullable)bundleIdentifier
                           displayName:(NSString *_Nullable)displayName;
+ (void)cancelPendingRequests;
+ (void)clearCache;

@end

NS_ASSUME_NONNULL_END
