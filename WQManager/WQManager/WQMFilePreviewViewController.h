//
//  WQMFilePreviewViewController.h
//  WQManager
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Read-only preview of a file inside an app container: images zoom, JSON/plist/text
/// render as monospaced text, media plays inline, anything else falls back to a hex dump.
@interface WQMFilePreviewViewController : UIViewController

- (instancetype)initWithFilePath:(NSString *)path name:(nullable NSString *)name;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil
                         bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
