#import <Foundation/Foundation.h>
#import "WQMLoadController.h"

static NSUInteger gFailures = 0;

static void WQMAssert(BOOL condition, NSString *message)
{
    if (condition) return;
    gFailures++;
    fprintf(stderr, "FAIL: %s\n", message.UTF8String);
}

int main(void)
{
    @autoreleasepool {
        // Standard: everything is a no-op.
        {
            WQMLoadPlan *plan = [WQMLoadController planForProfile:WQMLoadProfileStandard];
            __block NSUInteger sleeps = 0;
            WQMLoadController *load = [[WQMLoadController alloc]
                initWithPlan:plan
                       clock:^NSTimeInterval { return 0; }
                       sleep:^(NSTimeInterval seconds) { (void)seconds; sleeps++; }
                     thermal:^NSProcessInfoThermalState { return NSProcessInfoThermalStateNominal; }];
            [load consumeBytes:64ull * 1024 * 1024];
            for (NSUInteger i = 0; i < 10000; i++) [load consumeEntry];
            WQMAssert(sleeps == 0, @"standard profile must never sleep");
            WQMAssert(!load.reduceVerificationPasses, @"standard profile keeps every verification pass");
            WQMAssert(plan.qos == QOS_CLASS_USER_INITIATED, @"standard runs at user-initiated QoS");
        }

        // Low load: fixed duty cycle, verification reduction, utility QoS.
        {
            WQMLoadPlan *plan = [WQMLoadController planForProfile:WQMLoadProfileLowLoad];
            __block NSUInteger sleeps = 0;
            __block NSTimeInterval slept = 0;
            WQMLoadController *load = [[WQMLoadController alloc]
                initWithPlan:plan
                       clock:^NSTimeInterval { return 0; }
                       sleep:^(NSTimeInterval seconds) { sleeps++; slept += seconds; }
                     thermal:^NSProcessInfoThermalState { return NSProcessInfoThermalStateNominal; }];
            WQMAssert(load.reduceVerificationPasses, @"low-load may reuse verification results");
            WQMAssert(plan.qos == QOS_CLASS_UTILITY, @"low-load runs at utility QoS");
            [load consumeBytes:plan.batchBytes];
            WQMAssert(sleeps == 1, @"one batch of bytes must produce one rest");
            WQMAssert(fabs(slept - plan.batchPause) < 0.0001, @"rest length must match the plan");
            NSTimeInterval before = slept;
            for (NSUInteger i = 0; i < plan.batchFiles; i++) [load consumeEntry];
            WQMAssert(sleeps == 2, @"one batch of entries must also produce a rest");
            WQMAssert(slept - before > 0, @"entry rest must add time");
        }

        // Automatic, cool: no pacing but the plan allows thermal escalation.
        {
            __block NSTimeInterval now = 0;
            __block NSUInteger sleeps = 0;
            __block NSProcessInfoThermalState thermal = NSProcessInfoThermalStateNominal;
            WQMLoadController *load = [[WQMLoadController alloc]
                initWithPlan:[WQMLoadController planForProfile:WQMLoadProfileAutomatic]
                       clock:^NSTimeInterval { return now; }
                       sleep:^(NSTimeInterval seconds) { sleeps++; now += seconds; }
                     thermal:^NSProcessInfoThermalState { return thermal; }];
            WQMAssert(!load.reduceVerificationPasses, @"cool automatic run keeps full verification");
            [load consumeBytes:64ull * 1024 * 1024];
            WQMAssert(sleeps == 0, @"cool automatic run must not rest");

            // Heat up: the next sample switches to constrained pacing.
            thermal = NSProcessInfoThermalStateSerious;
            now += 6.0;
            [load consumeBytes:1024];
            WQMAssert(load.reduceVerificationPasses, @"hot automatic run may reuse verification");
            [load consumeBytes:2ull * 1024 * 1024];
            WQMAssert(sleeps == 1, @"hot automatic run must rest once per batch");

            // Cool down: no immediate relaxation, only after the hysteresis delay.
            thermal = NSProcessInfoThermalStateNominal;
            now += 6.0;
            [load consumeBytes:1024];
            WQMAssert(load.reduceVerificationPasses, @"automatic run must not relax immediately");
            now += 31.0;
            [load consumeBytes:1024];
            WQMAssert(!load.reduceVerificationPasses, @"automatic run relaxes after a cool period");
            [load consumeBytes:64ull * 1024 * 1024];
            WQMAssert(sleeps == 1, @"relaxed automatic run must stop resting");
        }

        // Automatic, critical: wait in slices until the device cools.
        {
            __block NSTimeInterval now = 0;
            __block NSUInteger sleeps = 0;
            __block NSUInteger criticalSamples = 3;
            WQMLoadController *load = [[WQMLoadController alloc]
                initWithPlan:[WQMLoadController planForProfile:WQMLoadProfileAutomatic]
                       clock:^NSTimeInterval { return now; }
                       sleep:^(NSTimeInterval seconds) { sleeps++; now += seconds; }
                     thermal:^NSProcessInfoThermalState {
                if (criticalSamples > 0) { criticalSamples--; return NSProcessInfoThermalStateCritical; }
                return NSProcessInfoThermalStateNominal;
            }];
            [load consumeBytes:1024];
            // Two critical observations, each followed by a two-second slice.
            WQMAssert(sleeps == 2, @"critical state must pause in slices until it clears");
        }
    }
    if (gFailures) {
        fprintf(stderr, "%lu load-controller test(s) failed\n", (unsigned long)gFailures);
        return 1;
    }
    printf("WQMLoadControllerTests: all checks passed\n");
    return 0;
}
