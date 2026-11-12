#import "WQMLoadController.h"

typedef NS_ENUM(NSInteger, WQMLoadTier) {
    WQMLoadTierStandard = 0,
    WQMLoadTierConstrained = 1,
    WQMLoadTierPaused = 2,
};

static const NSTimeInterval kWQMThermalSampleInterval = 5.0;
static const NSTimeInterval kWQMThermalRelaxDelay = 30.0;
static const NSTimeInterval kWQMThermalPauseSlice = 2.0;

@implementation WQMLoadPlan

- (instancetype)initWithProfile:(WQMLoadProfile)profile
                            qos:(qos_class_t)qos
                     batchBytes:(unsigned long long)batchBytes
                     batchFiles:(NSUInteger)batchFiles
                     batchPause:(NSTimeInterval)batchPause
        reduceVerificationPasses:(BOOL)reduceVerificationPasses
{
    self = [super init];
    if (!self) return nil;
    _profile = profile;
    _qos = qos;
    _batchBytes = batchBytes;
    _batchFiles = batchFiles;
    _batchPause = batchPause;
    _reduceVerificationPasses = reduceVerificationPasses;
    return self;
}

@end

@implementation WQMLoadController {
    NSTimeInterval (^_clock)(void);
    void (^_sleep)(NSTimeInterval);
    NSProcessInfoThermalState (^_thermal)(void);
    unsigned long long _pendingBytes;
    NSUInteger _pendingEntries;
    NSTimeInterval _lastSample;
    NSTimeInterval _coolSince;
    BOOL _sampledOnce;
    WQMLoadTier _tier;
}

+ (WQMLoadPlan *)planForProfile:(WQMLoadProfile)profile
{
    switch (profile) {
        case WQMLoadProfileLowLoad:
            // UTILITY QoS plus a short rest every few megabytes keeps the SoC
            // below the point where the system starts thermally throttling.
            return [[WQMLoadPlan alloc] initWithProfile:WQMLoadProfileLowLoad
                                                   qos:QOS_CLASS_UTILITY
                                            batchBytes:4ull * 1024 * 1024
                                            batchFiles:256
                                            batchPause:0.08
                               reduceVerificationPasses:YES];
        case WQMLoadProfileAutomatic:
            return [[WQMLoadPlan alloc] initWithProfile:WQMLoadProfileAutomatic
                                                   qos:QOS_CLASS_USER_INITIATED
                                            batchBytes:2ull * 1024 * 1024
                                            batchFiles:128
                                            batchPause:0.15
                               reduceVerificationPasses:YES];
        case WQMLoadProfileStandard:
        default:
            return [[WQMLoadPlan alloc] initWithProfile:WQMLoadProfileStandard
                                                   qos:QOS_CLASS_USER_INITIATED
                                            batchBytes:0
                                            batchFiles:0
                                            batchPause:0
                               reduceVerificationPasses:NO];
    }
}

+ (instancetype)controllerForCurrentPreferences
{
    WQMLoadProfile profile = WQMLoadProfileCurrent();
    WQMLoadPlan *plan = [self planForProfile:profile];
    return [[self alloc] initWithPlan:plan
                                clock:^NSTimeInterval { return NSDate.date.timeIntervalSinceReferenceDate; }
                                sleep:^(NSTimeInterval seconds) {
        if (seconds > 0) [NSThread sleepForTimeInterval:seconds];
    } thermal:^NSProcessInfoThermalState {
        return NSProcessInfo.processInfo.thermalState;
    }];
}

- (instancetype)initWithPlan:(WQMLoadPlan *)plan
                       clock:(NSTimeInterval (^)(void))clock
                       sleep:(void (^)(NSTimeInterval seconds))sleep
                     thermal:(NSProcessInfoThermalState (^)(void))thermal
{
    self = [super init];
    if (!self) return nil;
    _plan = plan;
    _clock = [clock copy];
    _sleep = [sleep copy];
    _thermal = [thermal copy];
    _tier = plan.profile == WQMLoadProfileLowLoad ? WQMLoadTierConstrained : WQMLoadTierStandard;
    return self;
}

- (WQMLoadTier)tierForThermalState:(NSProcessInfoThermalState)state
{
    switch (state) {
        case NSProcessInfoThermalStateCritical:
            return WQMLoadTierPaused;
        case NSProcessInfoThermalStateSerious:
            return WQMLoadTierConstrained;
        case NSProcessInfoThermalStateFair:
        case NSProcessInfoThermalStateNominal:
        default:
            return WQMLoadTierStandard;
    }
}

- (void)updateAutomaticTierIfNeeded
{
    if (self.plan.profile != WQMLoadProfileAutomatic) return;
    NSTimeInterval now = _clock();
    if (!_sampledOnce) {
        _sampledOnce = YES;
        _lastSample = now;
        _tier = [self tierForThermalState:_thermal()];
        if (self.plan.reduceVerificationPasses &&
            (NSProcessInfo.processInfo.lowPowerModeEnabled || _tier == WQMLoadTierConstrained)) {
            _tier = WQMLoadTierConstrained;
        }
        return;
    }
    if (now - _lastSample < kWQMThermalSampleInterval) return;
    _lastSample = now;
    WQMLoadTier observed = [self tierForThermalState:_thermal()];
    if (observed == WQMLoadTierPaused) {
        _tier = WQMLoadTierPaused;
        _coolSince = 0;
        return;
    }
    if (_tier == WQMLoadTierPaused) {
        // Leave the indefinite pause only once the sample is no longer critical.
        _tier = WQMLoadTierConstrained;
        _coolSince = now;
        return;
    }
    if (observed > _tier) {
        _tier = observed;
        _coolSince = 0;
        return;
    }
    if (observed < _tier) {
        if (_coolSince == 0) {
            _coolSince = now;
            return;
        }
        if (now - _coolSince >= kWQMThermalRelaxDelay) {
            _tier = observed;
            _coolSince = 0;
        }
        return;
    }
    _coolSince = 0;
}

- (void)waitUntilCool
{
    while ([self tierForThermalState:_thermal()] == WQMLoadTierPaused) {
        _sleep(kWQMThermalPauseSlice);
    }
    _tier = WQMLoadTierConstrained;
    _coolSince = _clock();
    _pendingBytes = 0;
    _pendingEntries = 0;
}

- (NSTimeInterval)currentPause
{
    if (self.plan.profile == WQMLoadProfileLowLoad) return self.plan.batchPause;
    return _tier == WQMLoadTierStandard ? 0 : self.plan.batchPause;
}

- (void)accountBytes:(unsigned long long)bytes entries:(NSUInteger)entries
{
    if (self.plan.profile == WQMLoadProfileStandard) return;
    [self updateAutomaticTierIfNeeded];
    if (_tier == WQMLoadTierPaused) [self waitUntilCool];
    NSTimeInterval pause = [self currentPause];
    if (pause <= 0) return;
    _pendingBytes += bytes;
    _pendingEntries += entries;
    BOOL bytesReady = self.plan.batchBytes && _pendingBytes >= self.plan.batchBytes;
    BOOL filesReady = self.plan.batchFiles && _pendingEntries >= self.plan.batchFiles;
    if (!bytesReady && !filesReady) return;
    _pendingBytes = 0;
    _pendingEntries = 0;
    _sleep(pause);
}

- (void)consumeBytes:(unsigned long long)bytes
{
    [self accountBytes:bytes entries:0];
}

- (void)consumeEntry
{
    [self accountBytes:0 entries:1];
}

- (BOOL)reduceVerificationPasses
{
    if (!self.plan.reduceVerificationPasses) return NO;
    if (self.plan.profile == WQMLoadProfileLowLoad) return YES;
    [self updateAutomaticTierIfNeeded];
    return _tier != WQMLoadTierStandard;
}

@end
