#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import "WQMPreferences.h"

NS_ASSUME_NONNULL_BEGIN

/// Immutable description of how much work a long operation may do between
/// deliberate rests. A zero pause means no pacing at all.
@interface WQMLoadPlan : NSObject

@property (nonatomic, readonly) WQMLoadProfile profile;
@property (nonatomic, readonly) qos_class_t qos;
@property (nonatomic, readonly) unsigned long long batchBytes;
@property (nonatomic, readonly) NSUInteger batchFiles;
@property (nonatomic, readonly) NSTimeInterval batchPause;
@property (nonatomic, readonly) BOOL reduceVerificationPasses;

- (instancetype)initWithProfile:(WQMLoadProfile)profile
                            qos:(qos_class_t)qos
                     batchBytes:(unsigned long long)batchBytes
                     batchFiles:(NSUInteger)batchFiles
                     batchPause:(NSTimeInterval)batchPause
        reduceVerificationPasses:(BOOL)reduceVerificationPasses NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

/// Tracks work done by a backup or restore and rests according to the load
/// profile. Automatic mode samples the thermal state at most every few
/// seconds, tightens as soon as the device gets hot, and relaxes only after a
/// sustained cool period so it cannot flap.
@interface WQMLoadController : NSObject

@property (nonatomic, readonly) WQMLoadPlan *plan;

/// Injectable clock, sleep and thermal source keep the pacing logic testable.
- (instancetype)initWithPlan:(WQMLoadPlan *)plan
                       clock:(NSTimeInterval (^)(void))clock
                       sleep:(void (^)(NSTimeInterval seconds))sleep
                     thermal:(NSProcessInfoThermalState (^)(void))thermal NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/// Uses the profile stored in preferences.
+ (instancetype)controllerForCurrentPreferences;

+ (WQMLoadPlan *)planForProfile:(WQMLoadProfile)profile;

/// Account read bytes and filesystem entries. Both are cheap no-ops for the
/// standard profile.
- (void)consumeBytes:(unsigned long long)bytes;
- (void)consumeEntry;

/// YES when the caller may replace repeated full-content verification with
/// metadata comparisons for this run. Only low-load (always) and automatic
/// (while the device is hot) opt in.
- (BOOL)reduceVerificationPasses;

@end

NS_ASSUME_NONNULL_END
