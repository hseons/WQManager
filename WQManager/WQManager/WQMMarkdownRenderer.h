#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface WQMMarkdownRenderer : NSObject

+ (NSAttributedString *)attributedStringFromMarkdown:(NSString *)markdown;

@end

NS_ASSUME_NONNULL_END
