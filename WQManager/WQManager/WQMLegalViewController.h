#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface WQMLegalViewController : UIViewController

@property (nonatomic, copy, nullable) void (^acceptanceHandler)(void);

@end

NS_ASSUME_NONNULL_END

