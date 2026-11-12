#import <Foundation/Foundation.h>
#import "WQAppsSupport.h"

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
        NSFileManager *fm = NSFileManager.defaultManager;
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:
                          [@"wqm-digest-" stringByAppendingString:NSUUID.UUID.UUIDString]];
        NSString *sub = [root stringByAppendingPathComponent:@"sub"];
        NSString *empty = [root stringByAppendingPathComponent:@"empty"];
        WQMAssert([fm createDirectoryAtPath:sub withIntermediateDirectories:YES attributes:nil error:nil],
                  @"fixture directory should be created");
        WQMAssert([fm createDirectoryAtPath:empty withIntermediateDirectories:NO attributes:nil error:nil],
                  @"empty directory should be created");

        NSData *alpha = [@"alpha" dataUsingEncoding:NSUTF8StringEncoding];
        NSData *beta = [@"beta-beta" dataUsingEncoding:NSUTF8StringEncoding];
        NSData *han = [@"中文内容" dataUsingEncoding:NSUTF8StringEncoding];
        NSString *fileA = [root stringByAppendingPathComponent:@"a.txt"];
        NSString *fileB = [sub stringByAppendingPathComponent:@"b.txt"];
        NSString *fileC = [root stringByAppendingPathComponent:@"中文.txt"];
        [alpha writeToFile:fileA atomically:YES];
        [beta writeToFile:fileB atomically:YES];
        [han writeToFile:fileC atomically:YES];
        chmod(fileA.fileSystemRepresentation, 0640);
        WQMAssert([fm createSymbolicLinkAtPath:[root stringByAppendingPathComponent:@"link"]
                                   withDestinationPath:@"a.txt" error:nil],
                  @"fixture symlink should be created");

        NSString *error = nil;
        BOOL exists = NO;
        NSString *legacyIdentity = WQAppsSupportTreeSignature(root, YES, &exists, &error);
        WQMAssert(legacyIdentity.length > 0 && exists, error ?: @"legacy identity should succeed");
        NSString *legacyShape = WQAppsSupportTreeSignature(root, NO, &exists, &error);
        WQMAssert(legacyShape.length > 0 && exists, error ?: @"legacy shape should succeed");

        NSString *identity = nil;
        NSString *shape = nil;
        unsigned long long total = 0;
        error = nil;
        exists = NO;
        BOOL merged = WQAppsSupportTreeDigests(root, &exists, &identity, &shape, &total, &error);
        WQMAssert(merged && exists, error ?: @"merged digests should succeed");
        WQMAssert([identity isEqualToString:legacyIdentity],
                  @"merged identity must match the legacy identity digest");
        WQMAssert([shape isEqualToString:legacyShape],
                  @"merged shape must match the legacy shape digest");
        unsigned long long expected = (unsigned long long)(alpha.length + beta.length + han.length);
        WQMAssert(total == expected, @"merged byte count must match the regular-file bytes");

        NSString *missing = [root stringByAppendingPathComponent:@"missing"];
        exists = YES;
        NSString *missingIdentity = nil;
        NSString *missingShape = nil;
        unsigned long long missingTotal = 99;
        WQMAssert(WQAppsSupportTreeDigests(missing, &exists, &missingIdentity, &missingShape,
                                           &missingTotal, NULL),
                  @"a missing tree is reported, not treated as an error");
        WQMAssert(!exists, @"a missing tree should report exists=NO");
        WQMAssert([missingIdentity isEqualToString:@"<missing>"] &&
                  [missingShape isEqualToString:@"<missing>"],
                  @"a missing tree should yield placeholder digests");
        WQMAssert(missingTotal == 0, @"a missing tree should have no bytes");

        exists = NO;
        error = nil;
        WQMAssert(WQAppsSupportTreeDigests(fileA, &exists, NULL, NULL, NULL, &error) == NO,
                  @"a regular file is not a tree");
        WQMAssert(error.length > 0, @"a non-directory root should set an error");

        NSString *fingerprintPath = [root stringByAppendingPathComponent:@"fingerprint.txt"];
        [@"one" writeToFile:fingerprintPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSString *first = WQAppsSupportFileFingerprint(fingerprintPath);
        WQMAssert(first.length > 0, @"a file fingerprint should be produced");
        WQMAssert([first isEqualToString:WQAppsSupportFileFingerprint(fingerprintPath)],
                  @"a file fingerprint should be stable while the file is unchanged");
        [@"two" writeToFile:fingerprintPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSString *second = WQAppsSupportFileFingerprint(fingerprintPath);
        WQMAssert(second.length > 0 && ![first isEqualToString:second],
                  @"rewriting a file must change its fingerprint");
        WQMAssert(WQAppsSupportFileFingerprint(missing) == nil,
                  @"a missing file has no fingerprint");

        [fm removeItemAtPath:root error:nil];
    }

    if (gFailures) {
        fprintf(stderr, "%lu support digest test(s) failed\n", (unsigned long)gFailures);
        return 1;
    }
    printf("WQM support digest tests passed\n");
    return 0;
}
