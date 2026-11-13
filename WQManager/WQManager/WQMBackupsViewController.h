#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface WQMBackupsViewController : UITableViewController <UIDocumentPickerDelegate, UISearchBarDelegate>
- (void)importBackupAtURL:(NSURL *)url;
- (void)presentImportPicker;
@end

NS_ASSUME_NONNULL_END

