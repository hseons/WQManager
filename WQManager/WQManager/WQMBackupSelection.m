#import "WQMBackupSelection.h"
#import <sys/stat.h>

@implementation WQMBackupSelection

+ (BOOL)isAllowedPath:(id)path
{
    if (![path isKindOfClass:NSString.class] || ![path length] || [path lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 1024) return NO;
    if ([path hasPrefix:@"/"] || [path containsString:@"\\"] ||
        [path rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) return NO;
    NSArray *components = [path componentsSeparatedByString:@"/"];
    if (![@[@"Documents", @"Library", @"tmp"] containsObject:components.firstObject]) return NO;
    for (NSString *component in components) {
        if (!component.length || [component isEqualToString:@"."] || [component isEqualToString:@".."]) return NO;
    }
    return components.count <= 32;
}

+ (NSArray<NSString *> *)canonicalPaths:(NSArray *)paths
{
    if (![paths isKindOfClass:NSArray.class] || !paths.count || paths.count > 128) return nil;
    for (id path in paths) if (![self isAllowedPath:path]) return nil;
    NSArray *sorted = [[NSSet setWithArray:paths].allObjects sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray *result = [NSMutableArray new];
    for (NSString *path in sorted) {
        BOOL covered = NO;
        for (NSString *parent in result) {
            if ([path hasPrefix:[parent stringByAppendingString:@"/"]]) { covered = YES; break; }
        }
        if (!covered) [result addObject:path];
    }
    // Distinct names must also stay distinct on case-insensitive volumes.
    NSMutableSet *folded = [NSMutableSet new];
    for (NSString *path in result) {
        NSString *key = path.precomposedStringWithCanonicalMapping.lowercaseString;
        if ([folded containsObject:key]) return nil;
        for (NSString *existing in folded) {
            if ([key hasPrefix:[existing stringByAppendingString:@"/"]] || [existing hasPrefix:[key stringByAppendingString:@"/"]]) return nil;
        }
        [folded addObject:key];
    }
    return result;
}

+ (BOOL)validatePayloadAtPath:(NSString *)root parts:(NSArray<NSString *> *)parts
{
    struct stat st;
    if (lstat(root.fileSystemRepresentation, &st) != 0 || !S_ISDIR(st.st_mode)) return NO;
    NSMutableSet *ancestors = [NSMutableSet set];
    for (NSString *part in parts) {
        NSString *ancestor = part;
        while (ancestor.length) { [ancestors addObject:ancestor]; ancestor = ancestor.stringByDeletingLastPathComponent; }
    }
    NSFileManager *fm = NSFileManager.defaultManager;
    NSMutableArray *pending = [NSMutableArray arrayWithObject:@""];
    while (pending.count) {
        NSString *relative = pending.lastObject;
        [pending removeLastObject];
        NSArray *children = [fm contentsOfDirectoryAtPath:[root stringByAppendingPathComponent:relative] error:nil];
        if (!children) return NO;
        for (NSString *name in children) {
            NSString *child = relative.length ? [relative stringByAppendingPathComponent:name] : name;
            if ([child isEqualToString:@"manifest.plist"]) {
                if (lstat([root stringByAppendingPathComponent:child].fileSystemRepresentation, &st) != 0 || !S_ISREG(st.st_mode)) return NO;
                continue;
            }
            if (![ancestors containsObject:child] || lstat([root stringByAppendingPathComponent:child].fileSystemRepresentation, &st) != 0 || !S_ISDIR(st.st_mode)) return NO;
            if (![parts containsObject:child]) [pending addObject:child];
        }
    }
    for (NSString *part in parts) {
        if (lstat([root stringByAppendingPathComponent:part].fileSystemRepresentation, &st) != 0 || !S_ISDIR(st.st_mode)) return NO;
    }
    return YES;
}
@end
