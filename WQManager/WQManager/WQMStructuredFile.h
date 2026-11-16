#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
/// Owns a bounded private workspace. Use on one serial worker queue.
@interface WQMStructuredFile : NSObject
@property (atomic) BOOL cancelled;
@property (nonatomic, copy, readonly) NSString *workspace;
@property (nonatomic, strong, readonly, nullable) id propertyList;
@property (nonatomic, copy, readonly) NSArray<NSDictionary *> *tables;
- (nullable instancetype)initWithPath:(NSString *)path error:(NSError * _Nullable * _Nullable)error;
- (nullable NSArray<NSDictionary *> *)rowsForTable:(NSString *)table offset:(NSUInteger)offset error:(NSError * _Nullable * _Nullable)error;
- (nullable NSURL *)exportTable:(NSString *)table error:(NSError * _Nullable * _Nullable)error;
@end
NS_ASSUME_NONNULL_END
