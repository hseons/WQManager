#import <Foundation/Foundation.h>

@class WQMBackupRecord;

NS_ASSUME_NONNULL_BEGIN

@interface WQMBackupArchiveService : NSObject

+ (NSString *)backupContentTypeIdentifier;

- (void)prepareExportForBackup:(WQMBackupRecord *)backup
                    completion:(void (^)(NSURL *_Nullable exportURL, NSError *_Nullable error))completion;

- (void)importBackupAtURL:(NSURL *)sourceURL
               completion:(void (^)(WQMBackupRecord *_Nullable backup, NSError *_Nullable error))completion;

- (void)deleteBackup:(WQMBackupRecord *)backup
           completion:(void (^)(BOOL success, NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END

