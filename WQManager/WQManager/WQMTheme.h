#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface WQMTheme : NSObject

+ (UIColor *)canvasColor;
+ (UIColor *)surfaceColor;
+ (UIColor *)raisedSurfaceColor;
+ (UIColor *)textPrimaryColor;
+ (UIColor *)textSecondaryColor;
+ (UIColor *)separatorColor;
+ (UIColor *)inverseSurfaceColor;
+ (UIColor *)inverseTextColor;
+ (UIColor *)dangerColor;
+ (UIColor *)accentColor;
+ (UIColor *)warningColor;

+ (CGFloat)smallRadius;
+ (CGFloat)mediumRadius;
+ (CGFloat)largeRadius;

+ (UIFont *)displayNumberFont;
+ (UIFont *)titleFont;
+ (UIFont *)sectionTitleFont;

+ (BOOL)shouldReduceMotion;
+ (void)configureNavigationBar:(UINavigationBar *)navigationBar;
+ (void)animateLabelChange:(UILabel *)label update:(void (^)(void))update;
+ (void)animateEntrance:(UIView *)view delay:(NSTimeInterval)delay;
+ (void)animatePress:(UIView *)view pressed:(BOOL)pressed;

+ (UIViewController *)placeholderViewControllerWithTitle:(NSString *)title
                                                   symbol:(NSString *)symbol
                                                 message:(NSString *)message;

@end

@interface WQMSoftSurfaceView : UIView

@property (nonatomic, getter=isElevated) BOOL elevated;

- (instancetype)initWithElevated:(BOOL)elevated NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithFrame:(CGRect)frame NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

