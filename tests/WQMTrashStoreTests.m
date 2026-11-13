//
//  WQMTrashStoreTests.m
//  WQManager tests
//
//  The Space Lens bin must list what it holds, put items back where they came
//  from, and never invent a destination it does not know.
//

#import <Foundation/Foundation.h>
#import "WQMTrashStore.h"

static NSUInteger WQMFailures = 0;

static void WQMAssert(BOOL condition, NSString *message)
{
    if (condition) return;
    WQMFailures += 1;
    fprintf(stderr, "FAIL: %s\n", message.UTF8String);
}

static NSString *WQMMakeTempRoot(void)
{
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"WQTrashTests-%@", NSUUID.UUID.UUIDString]];
    [NSFileManager.defaultManager createDirectoryAtPath:root
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:NULL];
    return root;
}

static NSString *WQMWriteFile(NSString *directory, NSString *name, NSUInteger bytes)
{
    [NSFileManager.defaultManager createDirectoryAtPath:directory
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:NULL];
    NSString *path = [directory stringByAppendingPathComponent:name];
    NSMutableData *data = [NSMutableData dataWithLength:bytes];
    [data writeToFile:path atomically:YES];
    return path;
}

int main(void)
{
    @autoreleasepool {
        NSString *scratch = WQMMakeTempRoot();
        setenv("WQM_TRASH_ROOT", [scratch stringByAppendingPathComponent:@"Trash"].UTF8String, 1);

        NSString *container = [scratch stringByAppendingPathComponent:@"Container"];
        NSString *level = [container stringByAppendingPathComponent:@"Documents/WeChat Files"];
        WQMWriteFile(level, @"chat.db", 4096);

        NSString *session = [WQMTrashStore createSessionForLevel:level];
        WQMAssert(session.length > 0, @"session path");
        WQMAssert([[NSFileManager defaultManager] fileExistsAtPath:session], @"session directory exists");

        // Move one file and one folder into the bin and record them.
        NSString *movedFile = [session stringByAppendingPathComponent:@"chat.db"];
        WQMAssert([[NSFileManager defaultManager] moveItemAtPath:[level stringByAppendingPathComponent:@"chat.db"]
                                                         toPath:movedFile
                                                          error:NULL], @"move file into bin");
        NSString *movedFolder = [session stringByAppendingPathComponent:@"video"];
        [NSFileManager.defaultManager createDirectoryAtPath:[movedFolder stringByAppendingPathComponent:@"clips"]
                                withIntermediateDirectories:YES attributes:nil error:NULL];
        [[NSMutableData dataWithLength:2048] writeToFile:[movedFolder stringByAppendingPathComponent:@"clips/a.mp4"]
                                       atomically:YES];

        [WQMTrashStore recordSession:session
                              source:level
                               items:@[@{@"Name": @"chat.db", @"Bytes": @4096, @"Directory": @NO},
                                       @{@"Name": @"video", @"Bytes": @2048, @"Directory": @YES}]];

        NSArray<WQMTrashSession *> *sessions = [WQMTrashStore sessions];
        WQMAssert(sessions.count == 1, @"one session listed");
        WQMTrashSession *listed = sessions.firstObject;
        WQMAssert(listed.items.count == 2, @"two items listed");
        WQMAssert(listed.totalBytes == 6144, @"total bytes add up");
        WQMAssert([listed.sourcePath isEqualToString:level], @"source path remembered");
        WQMAssert([listed.items.firstObject.name isEqualToString:@"chat.db"], @"manifest order kept");
        WQMAssert(listed.items.lastObject.directory, @"directory flag kept");

        WQMTrashItem *file = listed.items.firstObject;
        WQMAssert([file.originalPath isEqualToString:[level stringByAppendingPathComponent:@"chat.db"]],
                  @"original path reconstructed");

        NSError *error = nil;
        WQMAssert([WQMTrashStore restoreItem:file error:&error], @"restore succeeds");
        WQMAssert([[NSFileManager defaultManager] fileExistsAtPath:file.originalPath], @"file back home");
        WQMAssert(![[NSFileManager defaultManager] fileExistsAtPath:file.path], @"file left the bin");

        // Restoring onto an existing file must fail instead of overwriting.
        NSError *conflict = nil;
        WQMAssert(![WQMTrashStore restoreItem:file error:&conflict], @"restore refuses to overwrite");
        WQMAssert(conflict != nil, @"conflict error reported");

        // Sessions without a manifest still list, but cannot be restored.
        NSString *legacy = [scratch stringByAppendingPathComponent:@"Trash/legacy-session"];
        WQMWriteFile(legacy, @"orphan.bin", 1024);
        BOOL sawLegacy = NO;
        for (WQMTrashSession *candidate in [WQMTrashStore sessions]) {
            if ([candidate.name isEqualToString:@"legacy-session"]) {
                sawLegacy = YES;
                WQMAssert(candidate.items.count == 1, @"legacy session lists its content");
                WQMAssert(candidate.items.firstObject.originalPath == nil, @"legacy item has no destination");
            }
        }
        WQMAssert(sawLegacy, @"legacy session is listed");

        WQMTrashItem *remaining = listed.items.lastObject;
        [WQMTrashStore removeItem:remaining];
        WQMAssert(![[NSFileManager defaultManager] fileExistsAtPath:remaining.path], @"item removed from bin");

        WQMAssert(WQMTrashStore.totalBytes == 1024, @"legacy bytes still counted");
        [WQMTrashStore emptyAll];
        WQMAssert([WQMTrashStore sessions].count == 0, @"bin emptied");
        WQMAssert([WQMTrashStore totalBytes] == 0, @"no bytes left");

        [[NSFileManager defaultManager] removeItemAtPath:scratch error:NULL];
    }
    if (WQMFailures == 0) {
        fprintf(stdout, "WQM trash tests passed\n");
        return 0;
    }
    fprintf(stderr, "%lu trash checks failed\n", (unsigned long)WQMFailures);
    return 1;
}
