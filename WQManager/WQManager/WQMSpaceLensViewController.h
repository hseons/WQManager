//
//  WQMSpaceLensViewController.h
//  WQManager
//
//  Space lens: browse what fills an app's data container as bubbles, one level
//  at a time. Read only.
//

#import <UIKit/UIKit.h>

@class WQMAppModel;

NS_ASSUME_NONNULL_BEGIN

@interface WQMSpaceLensViewController : UIViewController

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)initWithApp:(WQMAppModel *)app NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil
    NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
