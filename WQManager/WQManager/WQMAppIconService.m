//
//  WQMAppIconService.m
//  WQManager
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//
//  The bundle-icon fallback is compatible with the approach documented by
//  WQFiles. Scheduling, cancellation, disk caching, placeholders, and UI
//  ownership are WQManager-specific.
//

#import "WQMAppIconService.h"
#import "WQAccess.h"
#import "WQLaunchServices.h"
#import "WQMTheme.h"

#import <dlfcn.h>
#import <math.h>
#import <objc/message.h>
#import <stdint.h>
#import <stdlib.h>
#import <sys/stat.h>

NSNotificationName const WQMAppIconDidResolveNotification = @"WQMAppIconDidResolveNotification";
NSString *const WQMAppIconBundleIdentifierKey = @"bundleIdentifier";

static const NSTimeInterval WQMAppIconDiskCacheAge = 7 * 24 * 60 * 60;

static BOOL WQMAppIconLooksUsable(UIImage *image);
static BOOL WQMAppIconLooksLikeKnownPlaceholder(UIImage *image);
static UIImage *WQMIconServicesIcon(NSString *bundleIdentifier);
static NSString *WQMAppIconDigestOfImage(UIImage *image);
static BOOL WQMAppIconIsKnownGenericPlaceholderImage(UIImage *image);

#if DEBUG
static BOOL WQMAppIconDebugSourceDisabled(NSString *key)
{
    return [NSProcessInfo.processInfo.environment[key] boolValue];
}
static BOOL WQMAppIconDebugLoggingEnabled(void)
{
    return [NSProcessInfo.processInfo.environment[@"WQM_ICON_DEBUG"] boolValue];
}
#endif

@interface UIImage (WQMPrivateIcon)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier
                                               format:(int)format
                                                scale:(CGFloat)scale;
@end

static NSCache<NSString *, UIImage *> *WQMAppIconMemoryCache(void)
{
    static NSCache *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSCache new];
        cache.countLimit = 256;
    });
    return cache;
}

static NSOperationQueue *WQMAppIconWorkQueue(void)
{
    static NSOperationQueue *queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = [NSOperationQueue new];
        queue.name = @"com.mumu.wqmanager.app-icons";
        queue.maxConcurrentOperationCount = 2;
        queue.qualityOfService = NSQualityOfServiceUserInitiated;
    });
    return queue;
}

static NSMutableSet<NSString *> *WQMAppIconPendingIdentifiers(void)
{
    static NSMutableSet *identifiers;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ identifiers = [NSMutableSet new]; });
    return identifiers;
}

static NSUInteger WQMAppIconGeneration;
static CGFloat WQMAppIconRenderScale = 2.0;

static CGFloat WQMAppIconCurrentScreenScale(void)
{
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class]) {
            return ((UIWindowScene *)scene).screen.scale;
        }
    }
    return 3.0;
}

static NSCache<NSString *, UIImage *> *WQMAppIconFallbackCache(void)
{
    static NSCache *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSCache new];
        cache.countLimit = 128;
    });
    return cache;
}

static NSURL *WQMAppIconDiskDirectory(void)
{
    static NSURL *directory;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSFileManager *fileManager = NSFileManager.defaultManager;
        NSURL *cacheRoot = [[fileManager URLsForDirectory:NSCachesDirectory
                                                 inDomains:NSUserDomainMask] firstObject];
        NSURL *managerDirectory = [cacheRoot URLByAppendingPathComponent:@"WQManager"
                                                              isDirectory:YES];
        NSURL *legacyDirectory = [managerDirectory URLByAppendingPathComponent:@"AppIcons-v4"
                                                                   isDirectory:YES];
        [fileManager removeItemAtURL:legacyDirectory error:nil];
        NSURL *previousDirectory = [managerDirectory URLByAppendingPathComponent:@"AppIcons-v5"
                                                                     isDirectory:YES];
        [fileManager removeItemAtURL:previousDirectory error:nil];
        directory = [managerDirectory URLByAppendingPathComponent:@"AppIcons-v6"
                                                      isDirectory:YES];
        [fileManager createDirectoryAtURL:directory
              withIntermediateDirectories:YES
                               attributes:nil
                                    error:nil];
    });
    return directory;
}

static NSURL *WQMAppIconDiskURL(NSString *bundleIdentifier)
{
    NSCharacterSet *unsafe = [[NSCharacterSet characterSetWithCharactersInString:
                               @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-"]
                              invertedSet];
    NSString *safe = [[bundleIdentifier componentsSeparatedByCharactersInSet:unsafe]
                      componentsJoinedByString:@"_"];
    if (!safe.length) return nil;
    return [WQMAppIconDiskDirectory() URLByAppendingPathComponent:
            [safe stringByAppendingPathExtension:@"png"]];
}

static UIImage *WQMAppIconDiskImage(NSString *bundleIdentifier)
{
    NSURL *url = WQMAppIconDiskURL(bundleIdentifier);
    if (!url) return nil;
    NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:url.path error:nil];
    NSDate *modified = attributes[NSFileModificationDate];
    if (!modified || -[modified timeIntervalSinceNow] > WQMAppIconDiskCacheAge) {
        [NSFileManager.defaultManager removeItemAtURL:url error:nil];
        return nil;
    }
    UIImage *image = [UIImage imageWithContentsOfFile:url.path];
    if (!WQMAppIconLooksUsable(image) ||
        WQMAppIconLooksLikeKnownPlaceholder(image) ||
        WQMAppIconIsKnownGenericPlaceholderImage(image)) {
        [NSFileManager.defaultManager removeItemAtURL:url error:nil];
        return nil;
    }
    return image;
}

static void WQMAppIconStoreDiskImage(UIImage *image, NSString *bundleIdentifier)
{
    NSURL *url = WQMAppIconDiskURL(bundleIdentifier);
    NSData *data = url ? UIImagePNGRepresentation(image) : nil;
    if (data) [data writeToURL:url options:NSDataWritingAtomic error:nil];
}

static BOOL WQMAppIconLooksUsable(UIImage *image)
{
    if (!image.CGImage || image.size.width < 24 || image.size.height < 24) return NO;
    CGFloat ratio = image.size.width / MAX(image.size.height, 1);
    if (ratio < 0.85 || ratio > 1.18) return NO;

    enum { sampleSide = 16 };
    uint8_t pixels[sampleSide * sampleSide * 4] = {0};
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, sampleSide, sampleSide, 8, sampleSide * 4,
                                                  colorSpace,
                                                  (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(colorSpace);
    if (!context) return YES;
    CGContextDrawImage(context, CGRectMake(0, 0, sampleSide, sampleSide), image.CGImage);
    CGContextRelease(context);
    NSUInteger minLuma = NSUIntegerMax, maxLuma = 0;
    for (NSUInteger index = 0; index < sampleSide * sampleSide; index++) {
        const uint8_t *rgba = pixels + index * 4;
        NSUInteger luma = (NSUInteger)rgba[0] * 3 + (NSUInteger)rgba[1] * 6 + (NSUInteger)rgba[2];
        minLuma = MIN(minLuma, luma);
        maxLuma = MAX(maxLuma, luma);
    }
    return maxLuma - minLuma > 24;
}

static UIImage *WQMSystemIconForFormat(NSString *bundleIdentifier, int format)
{
    if (!bundleIdentifier.length ||
        ![UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)]) {
        return nil;
    }
    return [UIImage _applicationIconImageForBundleIdentifier:bundleIdentifier
                                                       format:format
                                                        scale:WQMAppIconRenderScale];
}

static NSData *WQMAppIconFingerprint(UIImage *image)
{
    if (!image.CGImage) return nil;
    enum { side = 12 };
    uint8_t pixels[side * side * 4] = {0};
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, side, side, 8, side * 4,
                                                  colorSpace,
                                                  (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(colorSpace);
    if (!context) return nil;
    CGContextDrawImage(context, CGRectMake(0, 0, side, side), image.CGImage);
    CGContextRelease(context);
    return [NSData dataWithBytes:pixels length:sizeof(pixels)];
}

static BOOL WQMAppIconFingerprintLooksLikePlaceholder(UIImage *image, NSData *placeholderFingerprint)
{
    NSData *fingerprint = WQMAppIconFingerprint(image);
    if (!placeholderFingerprint || fingerprint.length != placeholderFingerprint.length) return NO;
    const uint8_t *left = fingerprint.bytes;
    const uint8_t *right = placeholderFingerprint.bytes;
    unsigned long difference = 0;
    for (NSUInteger index = 0; index < fingerprint.length; index++) {
        difference += (unsigned long)labs((long)left[index] - (long)right[index]);
    }
    return difference / fingerprint.length < 8;
}

static NSArray<NSData *> *WQMAppIconPlaceholderFingerprints(void)
{
    static NSArray<NSData *> *fingerprints;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableArray<NSData *> *items = [NSMutableArray new];
        NSArray<NSString *> *probeIdentifiers = @[
            @"com.mumu.wqmanager.nonexistent-app",
            @"cz.kolbi.wqfiles.no-such-app",
        ];
        for (NSString *probe in probeIdentifiers) {
            for (NSNumber *format in @[@10, @8, @2, @0, @1]) {
                NSData *fingerprint =
                    WQMAppIconFingerprint(WQMSystemIconForFormat(probe, format.intValue));
                if (!fingerprint) continue;
                BOOL duplicate = NO;
                for (NSData *known in items) {
                    if ([known isEqualToData:fingerprint]) {
                        duplicate = YES;
                        break;
                    }
                }
                if (!duplicate) [items addObject:fingerprint];
            }
        }
        fingerprints = [items copy];
    });
    return fingerprints;
}

static BOOL WQMAppIconLooksLikeKnownPlaceholder(UIImage *image)
{
    if (!image) return NO;
    for (NSData *fingerprint in WQMAppIconPlaceholderFingerprints()) {
        if (WQMAppIconFingerprintLooksLikePlaceholder(image, fingerprint)) return YES;
    }
    return NO;
}

#pragma mark - Generic placeholder detection

// iOS 26's iconservicesagent answers disallowed clients with the same gray
// placeholder bitmap for every third-party app.  That bitmap passes the usual
// "looks usable" heuristics, so it is detected by identity instead: a mostly
// gray image whose 16x16 digest collides with another bundle identifier (or
// with the system's own placeholder probe) is not an app icon.

static NSString *WQMAppIconDigestOfImage(UIImage *image)
{
    CGImageRef cgImage = image.CGImage;
    if (!cgImage) return nil;
    enum { side = 16 };
    uint8_t pixels[side * side * 4] = {0};
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, side, side, 8, side * 4,
                                                  colorSpace,
                                                  (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(colorSpace);
    if (!context) return nil;
    CGContextDrawImage(context, CGRectMake(0, 0, side, side), cgImage);
    CGContextRelease(context);
    uint64_t hash = 1469598103934665603ULL;
    for (NSUInteger index = 0; index < sizeof(pixels); index++) {
        hash ^= (uint64_t)pixels[index];
        hash *= 1099511628211ULL;
    }
    return [NSString stringWithFormat:@"%016llx", (unsigned long long)hash];
}

static BOOL WQMAppIconImageIsMostlyGray(UIImage *image)
{
    CGImageRef cgImage = image.CGImage;
    if (!cgImage) return NO;
    enum { side = 16 };
    uint8_t pixels[side * side * 4] = {0};
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, side, side, 8, side * 4,
                                                  colorSpace,
                                                  (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(colorSpace);
    if (!context) return NO;
    CGContextDrawImage(context, CGRectMake(0, 0, side, side), cgImage);
    CGContextRelease(context);
    NSUInteger colorful = 0;
    for (NSUInteger index = 0; index < side * side; index++) {
        const uint8_t *rgba = pixels + index * 4;
        NSUInteger maximum = MAX(rgba[0], MAX(rgba[1], rgba[2]));
        NSUInteger minimum = MIN(rgba[0], MIN(rgba[1], rgba[2]));
        if (maximum - minimum > 16) colorful++;
    }
    return colorful <= (side * side) / 64;
}

static NSMutableSet<NSString *> *WQMAppIconGenericPlaceholderDigests(void)
{
    static NSMutableSet *digests;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray *stored = [NSUserDefaults.standardUserDefaults
                           arrayForKey:@"WQMAppIconGenericPlaceholderDigests"];
        digests = [NSMutableSet setWithArray:stored ?: @[]];
    });
    return digests;
}

static void WQMAppIconPersistGenericPlaceholderDigests(void)
{
    NSArray<NSString *> *items = WQMAppIconGenericPlaceholderDigests().allObjects;
    if (items.count > 16) items = [items subarrayWithRange:NSMakeRange(0, 16)];
    [NSUserDefaults.standardUserDefaults setObject:items
                                           forKey:@"WQMAppIconGenericPlaceholderDigests"];
}

static NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *WQMAppIconDigestOwners(void)
{
    static NSMutableDictionary *owners;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ owners = [NSMutableDictionary new]; });
    return owners;
}

static NSString *WQMAppIconSystemPlaceholderDigest(void)
{
    static NSString *digest;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        UIImage *probe = WQMIconServicesIcon(@"com.mumu.wqmanager.placeholder-probe");
        if (probe) digest = WQMAppIconDigestOfImage(probe);
    });
    return digest;
}

static BOOL WQMAppIconIsKnownGenericPlaceholderImage(UIImage *image)
{
    NSString *digest = WQMAppIconDigestOfImage(image);
    if (!digest) return NO;
    @synchronized (WQMAppIconGenericPlaceholderDigests()) {
        if ([WQMAppIconGenericPlaceholderDigests() containsObject:digest]) return YES;
    }
    NSString *systemDigest = WQMAppIconSystemPlaceholderDigest();
    return systemDigest != nil && [systemDigest isEqualToString:digest] &&
           WQMAppIconImageIsMostlyGray(image);
}

static BOOL WQMAppIconIsGenericPlaceholder(UIImage *image,
                                           NSString *bundleIdentifier,
                                           NSString **digestOut,
                                           NSArray<NSString *> **conflictsOut)
{
    NSString *digest = WQMAppIconDigestOfImage(image);
    if (!digest || !WQMAppIconImageIsMostlyGray(image)) return NO;
    NSString *systemDigest = WQMAppIconSystemPlaceholderDigest();
    BOOL matchesSystem = systemDigest != nil && [systemDigest isEqualToString:digest];
    NSMutableArray<NSString *> *conflicts = [NSMutableArray array];
    BOOL known = matchesSystem;
    @synchronized (WQMAppIconDigestOwners()) {
        if ([WQMAppIconGenericPlaceholderDigests() containsObject:digest]) {
            known = YES;
        } else {
            NSMutableSet *owners = WQMAppIconDigestOwners()[digest];
            if (!owners) {
                owners = [NSMutableSet set];
                WQMAppIconDigestOwners()[digest] = owners;
            }
            for (NSString *other in owners) {
                if (![other isEqualToString:bundleIdentifier]) [conflicts addObject:other];
            }
            if (conflicts.count) {
                [WQMAppIconGenericPlaceholderDigests() addObject:digest];
                WQMAppIconPersistGenericPlaceholderDigests();
            }
            [owners addObject:bundleIdentifier];
        }
    }
    if (!known && !conflicts.count) return NO;
    if (digestOut) *digestOut = digest;
    if (conflictsOut) *conflictsOut = conflicts;
    return YES;
}

static void WQMAppIconForgetCachedIcon(NSString *bundleIdentifier)
{
    if (!bundleIdentifier.length) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [WQMAppIconMemoryCache() removeObjectForKey:bundleIdentifier];
        NSURL *url = WQMAppIconDiskURL(bundleIdentifier);
        if (url) [NSFileManager.defaultManager removeItemAtURL:url error:nil];
        [NSNotificationCenter.defaultCenter
            postNotificationName:WQMAppIconDidResolveNotification
                          object:nil
                        userInfo:@{WQMAppIconBundleIdentifierKey: bundleIdentifier}];
    });
}

static UIImage *WQMRealSystemIcon(NSString *bundleIdentifier)
{
#if DEBUG
    if (WQMAppIconDebugSourceDisabled(@"WQM_UI_DISABLE_DIRECT_ICON")) return nil;
#endif
    for (NSNumber *format in @[@10, @8, @2, @0, @1]) {
        UIImage *image = WQMSystemIconForFormat(bundleIdentifier, format.intValue);
        if (WQMAppIconLooksUsable(image) &&
            !WQMAppIconLooksLikeKnownPlaceholder(image)) {
            return image;
        }
    }
    return nil;
}

typedef CFTypeRef (*WQMSPCopyIconValueFn)(CFStringRef displayIdentifier);

static WQMSPCopyIconValueFn WQMSPIconDataFunction(void)
{
    static WQMSPCopyIconValueFn function;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *handle = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices",
                              RTLD_LAZY | RTLD_LOCAL);
        if (handle) function = (WQMSPCopyIconValueFn)dlsym(handle,
            "SBSCopyIconImagePNGDataForDisplayIdentifier");
    });
    return function;
}

static WQMSPCopyIconValueFn WQMSPIconPathFunction(void)
{
    static WQMSPCopyIconValueFn function;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *handle = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices",
                              RTLD_LAZY | RTLD_LOCAL);
        if (handle) function = (WQMSPCopyIconValueFn)dlsym(handle,
            "SBSCopyIconImagePathForDisplayIdentifier");
    });
    return function;
}

static WQMSPCopyIconValueFn WQMSPBundlePathFunction(void)
{
    static WQMSPCopyIconValueFn function;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *handle = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices",
                              RTLD_LAZY | RTLD_LOCAL);
        if (handle) function = (WQMSPCopyIconValueFn)dlsym(handle,
            "SBSCopyBundlePathForDisplayIdentifier");
    });
    return function;
}

static id WQMApplicationProxyForIdentifier(NSString *bundleIdentifier)
{
    if (!bundleIdentifier.length) return nil;
    static Class proxyClass;
    static Class workspaceClass;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dlopen("/System/Library/Frameworks/CoreServices.framework/CoreServices",
               RTLD_LAZY | RTLD_LOCAL);
        dlopen("/System/Library/Frameworks/MobileCoreServices.framework/MobileCoreServices",
               RTLD_LAZY | RTLD_LOCAL);
        proxyClass = NSClassFromString(@"LSApplicationProxy");
        workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    });
    id proxy = nil;
    @try {
        if ([proxyClass respondsToSelector:NSSelectorFromString(@"applicationProxyForIdentifier:")]) {
            proxy = ((id (*)(id, SEL, id))objc_msgSend)(
                proxyClass,
                NSSelectorFromString(@"applicationProxyForIdentifier:"),
                bundleIdentifier);
        }
        if (!proxy) {
            id workspace = [workspaceClass respondsToSelector:NSSelectorFromString(@"defaultWorkspace")]
                ? ((id (*)(id, SEL))objc_msgSend)(workspaceClass,
                                                  NSSelectorFromString(@"defaultWorkspace"))
                : nil;
            if ([workspace respondsToSelector:NSSelectorFromString(@"applicationProxyForIdentifier:")]) {
                proxy = ((id (*)(id, SEL, id))objc_msgSend)(
                    workspace,
                    NSSelectorFromString(@"applicationProxyForIdentifier:"),
                    bundleIdentifier);
            }
        }
    } @catch (NSException *__unused exception) {
        return nil;
    }
#if DEBUG
    if (WQMAppIconDebugLoggingEnabled()) {
        NSLog(@"WQM icon proxy %@ -> %@", bundleIdentifier, proxy);
    }
#endif
    return proxy;
}

static NSString *WQMApplicationProxyBundlePathWithProxy(id proxy)
{
    if (!proxy) return nil;
    @try {
        NSURL *bundleURL = [proxy respondsToSelector:@selector(valueForKey:)]
            ? [proxy valueForKey:@"bundleURL"] : nil;
        return [bundleURL isKindOfClass:NSURL.class] ? bundleURL.path : nil;
    } @catch (NSException *__unused exception) {
        return nil;
    }
}

static NSString *WQMApplicationProxyBundlePath(NSString *bundleIdentifier)
{
    return WQMApplicationProxyBundlePathWithProxy(
        WQMApplicationProxyForIdentifier(bundleIdentifier));
}

static BOOL WQMApplicationProxyIsSystemApp(id proxy)
{
    if (!proxy) return NO;
    for (NSString *selectorName in @[@"isSystemApplication", @"systemApplication"]) {
        SEL selector = NSSelectorFromString(selectorName);
        if (![proxy respondsToSelector:selector]) continue;
        @try {
            return ((BOOL (*)(id, SEL))objc_msgSend)(proxy, selector);
        } @catch (NSException *__unused exception) {
            return NO;
        }
    }
    return NO;
}

static BOOL WQMAppBundleIsThirdParty(id proxy, NSString *bundlePath)
{
    if (proxy) return !WQMApplicationProxyIsSystemApp(proxy);
    if (!bundlePath.length) return NO;
    return [bundlePath hasPrefix:@"/private/var/containers/Bundle/Application/"] ||
        [bundlePath hasPrefix:@"/var/containers/Bundle/Application/"];
}

static id WQMApplicationProxyIconData(id proxy, NSString *selectorName,
                                      int variant, BOOL withOptions)
{
    if (!proxy) return nil;
    SEL selector = NSSelectorFromString(selectorName);
    if (![proxy respondsToSelector:selector]) return nil;
    @try {
        NSMethodSignature *signature = [proxy methodSignatureForSelector:selector];
        NSUInteger expectedArguments = withOptions ? 4 : 3;
        if (!signature || signature.numberOfArguments < expectedArguments ||
            signature.methodReturnType[0] != '@') {
            return nil;
        }
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        invocation.target = proxy;
        invocation.selector = selector;
        [invocation setArgument:&variant atIndex:2];
        if (withOptions) {
            unsigned long long options = 0;
            [invocation setArgument:&options atIndex:3];
        }
        [invocation invoke];
        __unsafe_unretained id result = nil;
        [invocation getReturnValue:&result];
        id strongResult = result;
        return strongResult;
    } @catch (NSException *__unused exception) {
        return nil;
    }
}

static NSString *WQMCoreUIPlatformIOS(void)
{
    static NSString *platform;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *handle = dlopen("/System/Library/PrivateFrameworks/CoreUI.framework/CoreUI",
                              RTLD_LAZY | RTLD_LOCAL);
        void *symbol = handle ? dlsym(handle, "kCUIPlatformiOS") : NULL;
        if (symbol) {
            void *value = *(void **)symbol;
            if (value) platform = (__bridge NSString *)value;
        }
        if (!platform.length) platform = @"ios";
    });
    return platform;
}

static UIImage *WQMLayeredIconImageFromData(NSData *data)
{
    if (data.length < 16) return nil;
    NSData *magic = [NSData dataWithBytes:"BOMStore" length:8];
    NSRange magicRange = [data rangeOfData:magic
                                  options:0
                                    range:NSMakeRange(0, data.length)];
    if (magicRange.location == NSNotFound ||
        magicRange.location + magicRange.length >= data.length) {
        return nil;
    }

    static Class catalogClass;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dlopen("/System/Library/PrivateFrameworks/CoreUI.framework/CoreUI",
               RTLD_LAZY | RTLD_LOCAL);
        catalogClass = NSClassFromString(@"CUICatalog");
    });
    if (!catalogClass) return nil;

    @try {
        NSError *error = nil;
        id catalog = ((id (*)(id, SEL, const void *, NSUInteger, NSError **))objc_msgSend)(
            ((id (*)(id, SEL))objc_msgSend)(catalogClass, @selector(alloc)),
            NSSelectorFromString(@"initWithBytes:length:error:"),
            (const uint8_t *)data.bytes + magicRange.location,
            data.length - magicRange.location,
            &error);
        if (!catalog) return nil;

        id stack = ((id (*)(id, SEL))objc_msgSend)(
            catalog, NSSelectorFromString(@"defaultIconLayerStack"));
        SEL imageSelector = NSSelectorFromString(
            @"_IS_imageWithSize:scale:platform:appearance:appearanceVariant:tintColor:isLegacy:background:");
        if (!stack || ![stack respondsToSelector:imageSelector]) return nil;

        NSMethodSignature *signature = [stack methodSignatureForSelector:imageSelector];
        if (!signature || signature.numberOfArguments < 10 ||
            signature.methodReturnType[0] != '@') {
            return nil;
        }
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        invocation.target = stack;
        invocation.selector = imageSelector;
        double desiredSize[2] = { 80, 80 };
        long long scale = (long long)llround(WQMAppIconRenderScale);
        unsigned long long platform = (unsigned long long)(uintptr_t)
            (__bridge void *)WQMCoreUIPlatformIOS();
        long long appearance = 0;
        long long appearanceVariant = 0;
        id tintColor = nil;
        BOOL legacy = NO;
        unsigned long long background = 0;
        [invocation setArgument:&desiredSize atIndex:2];
        [invocation setArgument:&scale atIndex:3];
        [invocation setArgument:&platform atIndex:4];
        [invocation setArgument:&appearance atIndex:5];
        [invocation setArgument:&appearanceVariant atIndex:6];
        [invocation setArgument:&tintColor atIndex:7];
        [invocation setArgument:&legacy atIndex:8];
        [invocation setArgument:&background atIndex:9];
        [invocation invoke];

        __unsafe_unretained id rendered = nil;
        [invocation getReturnValue:&rendered];
        id strongRendered = rendered;
        if (![strongRendered respondsToSelector:@selector(CGImage)]) return nil;
        CGImageRef imageRef = ((CGImageRef (*)(id, SEL))objc_msgSend)(
            strongRendered, @selector(CGImage));
        return imageRef
            ? [UIImage imageWithCGImage:imageRef
                                  scale:WQMAppIconRenderScale
                            orientation:UIImageOrientationUp]
            : nil;
    } @catch (NSException *__unused exception) {
        return nil;
    }
}

static UIImage *WQMApplicationProxyIconImage(id proxy, NSString *selectorName,
                                             int format, BOOL withScale)
{
    if (!proxy) return nil;
    SEL selector = NSSelectorFromString(selectorName);
    if (![proxy respondsToSelector:selector]) return nil;
    @try {
        NSMethodSignature *signature = [proxy methodSignatureForSelector:selector];
        NSUInteger expectedArguments = withScale ? 4 : 3;
        if (!signature || signature.numberOfArguments < expectedArguments ||
            signature.methodReturnType[0] != '@') {
            return nil;
        }
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        invocation.target = proxy;
        invocation.selector = selector;
        [invocation setArgument:&format atIndex:2];
        if (withScale) {
            CGFloat scale = WQMAppIconRenderScale;
            [invocation setArgument:&scale atIndex:3];
        }
        [invocation invoke];
        __unsafe_unretained id result = nil;
        [invocation getReturnValue:&result];
        id strongResult = result;
        return [strongResult isKindOfClass:UIImage.class] ? strongResult : nil;
    } @catch (NSException *__unused exception) {
        return nil;
    }
}

static UIImage *WQMApplicationProxyIcon(id proxy)
{
#if DEBUG
    if (WQMAppIconDebugSourceDisabled(@"WQM_UI_DISABLE_PROXY_ICON")) return nil;
#endif
    if (!proxy) return nil;
    NSArray<NSString *> *dataSelectors = @[
        @"primaryIconDataForVariant:withOptions:",
        @"iconDataForVariant:withOptions:",
        @"primaryIconDataForVariant:",
        @"iconDataForVariant:",
    ];
    for (NSNumber *variant in @[@10, @2, @0, @1, @8]) {
        for (NSString *selectorName in dataSelectors) {
            BOOL withOptions = [selectorName containsString:@"withOptions:"];
            id value = WQMApplicationProxyIconData(proxy, selectorName, variant.intValue, withOptions);
            NSData *data = [value isKindOfClass:NSData.class] ? value : nil;
            UIImage *image = data.length
                ? ([UIImage imageWithData:data] ?: WQMLayeredIconImageFromData(data))
                : nil;
            BOOL usable = WQMAppIconLooksUsable(image);
            BOOL placeholder = usable && WQMAppIconLooksLikeKnownPlaceholder(image);
#if DEBUG
            if (WQMAppIconDebugLoggingEnabled()) {
                NSLog(@"WQM icon proxy selector %@ variant %@ data %lu usable %d placeholder %d",
                      selectorName, variant, (unsigned long)data.length, usable, placeholder);
            }
#endif
            if (usable && !placeholder) {
                return image;
            }
        }
    }

    SEL allSizesSelector = NSSelectorFromString(@"iconsOfAllSizes");
    if ([proxy respondsToSelector:allSizesSelector]) {
        @try {
            id icons = ((id (*)(id, SEL))objc_msgSend)(proxy, allSizesSelector);
            NSArray *values = [icons isKindOfClass:NSDictionary.class]
                ? [(NSDictionary *)icons allValues] : nil;
            values = [values sortedArrayUsingComparator:^NSComparisonResult(id left, id right) {
                NSUInteger leftLength = [left isKindOfClass:NSData.class]
                    ? [(NSData *)left length] : 0;
                NSUInteger rightLength = [right isKindOfClass:NSData.class]
                    ? [(NSData *)right length] : 0;
                return leftLength > rightLength ? NSOrderedAscending
                    : (leftLength < rightLength ? NSOrderedDescending : NSOrderedSame);
            }];
            for (id value in values) {
                NSData *data = [value isKindOfClass:NSData.class] ? value : nil;
                UIImage *image = data.length
                    ? ([UIImage imageWithData:data] ?: WQMLayeredIconImageFromData(data))
                    : nil;
                if (WQMAppIconLooksUsable(image) &&
                    !WQMAppIconLooksLikeKnownPlaceholder(image)) {
                    return image;
                }
            }
        } @catch (NSException *__unused exception) {
        }
    }

    for (NSNumber *format in @[@10, @8, @2, @0, @1]) {
        UIImage *image = WQMApplicationProxyIconImage(
            proxy, @"applicationIconImageForFormat:scale:", format.intValue, YES);
        if (WQMAppIconLooksUsable(image) &&
            !WQMAppIconLooksLikeKnownPlaceholder(image)) {
            return image;
        }
        image = WQMApplicationProxyIconImage(
            proxy, @"applicationIconImageForFormat:", format.intValue, NO);
        if (WQMAppIconLooksUsable(image) &&
            !WQMAppIconLooksLikeKnownPlaceholder(image)) {
            return image;
        }
    }
    return nil;
}

static NSString *WQMAppBundlePath(NSString *bundleIdentifier)
{
    NSString *path = WQMApplicationProxyBundlePath(bundleIdentifier);
    if (!path.length) path = wq_bundle_path_for_id(bundleIdentifier);
    if (path.length) return path;
    WQMSPCopyIconValueFn function = WQMSPBundlePathFunction();
    if (!function) return nil;
    NSString *springBoardPath =
        (__bridge_transfer NSString *)function((__bridge CFStringRef)bundleIdentifier);
    return [springBoardPath isKindOfClass:NSString.class] ? springBoardPath : nil;
}

static UIImage *WQMSpringBoardIcon(NSString *bundleIdentifier)
{
#if DEBUG
    if (WQMAppIconDebugSourceDisabled(@"WQM_UI_DISABLE_SPRINGBOARD_ICON")) return nil;
#endif
    if (!bundleIdentifier.length) return nil;
    CFStringRef identifier = (__bridge CFStringRef)bundleIdentifier;
    WQMSPCopyIconValueFn dataFunction = WQMSPIconDataFunction();
    if (dataFunction) {
        NSData *data = (__bridge_transfer NSData *)dataFunction(identifier);
        UIImage *image = [data isKindOfClass:NSData.class] ? [UIImage imageWithData:data] : nil;
        if (WQMAppIconLooksUsable(image)) return image;
    }
    WQMSPCopyIconValueFn pathFunction = WQMSPIconPathFunction();
    if (pathFunction) {
        NSString *path = (__bridge_transfer NSString *)pathFunction(identifier);
        UIImage *image = [path isKindOfClass:NSString.class]
            ? [UIImage imageWithContentsOfFile:path] : nil;
        if (WQMAppIconLooksUsable(image)) return image;
    }
    return nil;
}

static UIImage *WQMIconServicesIcon(NSString *bundleIdentifier)
{
#if DEBUG
    if (WQMAppIconDebugSourceDisabled(@"WQM_UI_DISABLE_ICONSERVICES_ICON")) return nil;
#endif
    if (!bundleIdentifier.length) return nil;
    static Class bundleIconClass;
    static Class descriptorClass;
    static Class requestClass;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dlopen("/System/Library/PrivateFrameworks/IconServices.framework/IconServices",
               RTLD_LAZY | RTLD_LOCAL);
        bundleIconClass = NSClassFromString(@"ISBundleIcon");
        descriptorClass = NSClassFromString(@"ISImageDescriptor");
        requestClass = NSClassFromString(@"ISGenerationRequest");
    });
    NSString *bundlePath = WQMAppBundlePath(bundleIdentifier);
    if (!bundlePath.length || !bundleIconClass || !descriptorClass || !requestClass) return nil;

    @try {
        id descriptor = ((id (*)(id, SEL, id))objc_msgSend)(
            descriptorClass,
            NSSelectorFromString(@"imageDescriptorNamed:"),
            @"com.apple.IconServices.ImageDescriptor.HomeScreen");
        [descriptor setValue:@3.0 forKey:@"scale"];
        [descriptor setValue:@YES forKey:@"ignoreCache"];
        id icon = ((id (*)(id, SEL, id))objc_msgSend)(
            ((id (*)(id, SEL))objc_msgSend)(bundleIconClass, @selector(alloc)),
            NSSelectorFromString(@"initWithBundleURL:"),
            [NSURL fileURLWithPath:bundlePath isDirectory:YES]);
        id request = ((id (*)(id, SEL))objc_msgSend)(requestClass, @selector(new));
        ((void (*)(id, SEL, id))objc_msgSend)(
            request, NSSelectorFromString(@"setIcon:"), icon);
        ((void (*)(id, SEL, id))objc_msgSend)(
            request, NSSelectorFromString(@"setImageDescriptor:"), descriptor);
        id generated = ((id (*)(id, SEL, void *))objc_msgSend)(
            request, NSSelectorFromString(@"generateImageReturningRecordIdentifiers:"), NULL);
        if ([generated respondsToSelector:@selector(CGImage)]) {
            CGImageRef cgImage = ((CGImageRef (*)(id, SEL))objc_msgSend)(
                generated, @selector(CGImage));
            UIImage *image = cgImage ? [UIImage imageWithCGImage:cgImage] : nil;
            if (WQMAppIconLooksUsable(image)) return image;
        }
    } @catch (NSException *__unused exception) {
        return nil;
    }
    return nil;
}

static UIImage *WQMCUICatalogIcon(NSString *bundlePath)
{
#if DEBUG
    if (WQMAppIconDebugSourceDisabled(@"WQM_UI_DISABLE_CUICATALOG_ICON")) return nil;
#endif
    NSString *catalogPath = [bundlePath stringByAppendingPathComponent:@"Assets.car"];
    if (![NSFileManager.defaultManager fileExistsAtPath:catalogPath]) return nil;
    dlopen("/System/Library/PrivateFrameworks/CoreUI.framework/CoreUI",
           RTLD_LAZY | RTLD_LOCAL);
    Class catalogClass = NSClassFromString(@"CUICatalog");
    if (!catalogClass) return nil;

    @try {
        NSError *error = nil;
        id catalog = ((id (*)(id, SEL, id, NSError **))objc_msgSend)(
            ((id (*)(id, SEL))objc_msgSend)(catalogClass, @selector(alloc)),
            NSSelectorFromString(@"initWithURL:error:"),
            [NSURL fileURLWithPath:catalogPath],
            &error);
        if (!catalog) return nil;

        NSMutableOrderedSet<NSString *> *names = [NSMutableOrderedSet new];
        NSString *plistPath = [bundlePath stringByAppendingPathComponent:@"Info.plist"];
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:plistPath];
        for (NSString *key in @[@"CFBundleIcons", @"CFBundleIcons~ipad"]) {
            NSDictionary *primary = [info[key] isKindOfClass:NSDictionary.class]
                ? info[key][@"CFBundlePrimaryIcon"] : nil;
            if (![primary isKindOfClass:NSDictionary.class]) continue;
            if ([primary[@"CFBundleIconName"] isKindOfClass:NSString.class]) {
                [names addObject:primary[@"CFBundleIconName"]];
            }
            for (id file in [primary[@"CFBundleIconFiles"] isKindOfClass:NSArray.class]
                     ? [primary[@"CFBundleIconFiles"] reverseObjectEnumerator] : @[]) {
                if ([file isKindOfClass:NSString.class]) {
                    [names addObject:[file stringByDeletingPathExtension]];
                }
            }
        }
        [names addObjectsFromArray:@[@"AppIcon", @"AppIcon60x60", @"AppIcon76x76"]];

        NSArray<NSString *> *allNames = ((id (*)(id, SEL))objc_msgSend)(
            catalog, NSSelectorFromString(@"allImageNames"));
        if ([allNames isKindOfClass:NSArray.class]) {
            NSArray<NSString *> *iconNames = [allNames filteredArrayUsingPredicate:
                [NSPredicate predicateWithBlock:^BOOL(NSString *name, NSDictionary *__unused bindings) {
                    return [name localizedCaseInsensitiveContainsString:@"appicon"];
                }]];
            [names addObjectsFromArray:iconNames];
        }

        for (NSString *name in names) {
            for (NSNumber *scale in @[@3, @2, @1]) {
                for (NSNumber *idiom in @[@0, @1]) {
                    id namedImage = ((id (*)(id, SEL, id, CGFloat, NSInteger))objc_msgSend)(
                        catalog,
                        NSSelectorFromString(@"imageWithName:scaleFactor:deviceIdiom:"),
                        name,
                        scale.doubleValue,
                        idiom.integerValue);
                    if (!namedImage) continue;
                    CGImageRef cgImage = ((CGImageRef (*)(id, SEL))objc_msgSend)(
                        namedImage, NSSelectorFromString(@"image"));
                    UIImage *image = cgImage ? [UIImage imageWithCGImage:cgImage] : nil;
                    if (WQMAppIconLooksUsable(image)) return image;
                    cgImage = ((CGImageRef (*)(id, SEL))objc_msgSend)(
                        namedImage, NSSelectorFromString(@"croppedImage"));
                    image = cgImage ? [UIImage imageWithCGImage:cgImage] : nil;
                    if (WQMAppIconLooksUsable(image)) return image;
                }
            }
        }
    } @catch (NSException *__unused exception) {
        return nil;
    }
    return nil;
}

static UIImage *WQMBundleIcon(NSString *bundleIdentifier)
{
#if DEBUG
    if (WQMAppIconDebugSourceDisabled(@"WQM_UI_DISABLE_BUNDLE_ICON")) return nil;
#endif
    NSString *bundlePath = WQMAppBundlePath(bundleIdentifier);
    if (!bundlePath.length) return nil;

    NSString *plistPath = [bundlePath stringByAppendingPathComponent:@"Info.plist"];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:plistPath];
    if (![info isKindOfClass:NSDictionary.class] && wq_grant(bundlePath)) {
        info = [NSDictionary dictionaryWithContentsOfFile:plistPath];
    }
    if (![info isKindOfClass:NSDictionary.class]) return nil;

    NSMutableOrderedSet<NSString *> *names = [NSMutableOrderedSet new];
    for (NSString *key in @[@"CFBundleIcons", @"CFBundleIcons~ipad"]) {
        NSDictionary *primary = [info[key] isKindOfClass:NSDictionary.class]
            ? info[key][@"CFBundlePrimaryIcon"] : nil;
        if (![primary isKindOfClass:NSDictionary.class]) continue;
        if ([primary[@"CFBundleIconName"] isKindOfClass:NSString.class]) {
            [names addObject:primary[@"CFBundleIconName"]];
        }
        NSArray *iconFiles = [primary[@"CFBundleIconFiles"] isKindOfClass:NSArray.class]
            ? primary[@"CFBundleIconFiles"] : @[];
        for (id file in iconFiles.reverseObjectEnumerator) {
            if ([file isKindOfClass:NSString.class]) [names addObject:file];
        }
    }
    if ([info[@"CFBundleIconFile"] isKindOfClass:NSString.class]) {
        [names addObject:info[@"CFBundleIconFile"]];
    }
    [names addObjectsFromArray:@[@"AppIcon60x60", @"AppIcon"]];

    for (NSString *name in names) {
        NSString *base = name.stringByDeletingPathExtension;
        if (!base.length) continue;
        for (NSString *suffix in @[@"@3x.png", @"@2x.png", @"@2x~ipad.png", @"~ipad.png", @".png"]) {
            UIImage *image = [UIImage imageWithContentsOfFile:
                              [bundlePath stringByAppendingPathComponent:
                               [base stringByAppendingString:suffix]]];
            if (WQMAppIconLooksUsable(image)) return image;
        }
    }
    return nil;
}

static UIImage *WQMRoundIcon(UIImage *source)
{
    const CGFloat side = 80;
    UIGraphicsImageRenderer *renderer =
        [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *__unused context) {
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, side, side)
                                        cornerRadius:side * 0.225] addClip];
        [source drawInRect:CGRectMake(0, 0, side, side)];
    }];
}

static UIImage *WQMFallbackIcon(NSString *bundleIdentifier, NSString *displayName)
{
    NSString *key = [NSString stringWithFormat:@"%@|%@", bundleIdentifier ?: @"", displayName ?: @""];
    UIImage *cached = [WQMAppIconFallbackCache() objectForKey:key];
    if (cached) return cached;

    NSString *title = displayName.length ? displayName : bundleIdentifier;
    NSString *initial = title.length ? [title substringToIndex:1].uppercaseString : @"?";
    const CGFloat side = 80;
    UIGraphicsImageRenderer *renderer =
        [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)];
    UIImage *tile = [renderer imageWithActions:^(UIGraphicsImageRendererContext *__unused context) {
        [[WQMTheme.surfaceColor colorWithAlphaComponent:0.82] setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, side, side)
                                        cornerRadius:side * 0.225] fill];
        NSDictionary *attributes = @{
            NSFontAttributeName: [UIFont systemFontOfSize:32 weight:UIFontWeightSemibold],
            NSForegroundColorAttributeName: WQMTheme.textSecondaryColor,
        };
        CGSize size = [initial sizeWithAttributes:attributes];
        [initial drawAtPoint:CGPointMake((side - size.width) / 2,
                                         (side - size.height) / 2)
              withAttributes:attributes];
    }];
    [WQMAppIconFallbackCache() setObject:tile forKey:key];
    return tile;
}

#pragma mark - Icon diagnostics (temporary)
// Temporary instrumentation for the iOS 26 third-party icon investigation.
// Logs to Documents/icon-diag-<timestamp>.log (visible through Files because
// UIFileSharingEnabled is on) and to NSLog. Set WQM_ICON_DIAG=0 to silence and
// WQM_ICON_DIAG_DUMP=1 to export up to three raw icon records.

static BOOL WQMAppIconDiagnosticsWanted(void)
{
    static BOOL wanted;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *value = NSProcessInfo.processInfo.environment[@"WQM_ICON_DIAG"];
        wanted = value.length ? value.boolValue : YES;
    });
    return wanted;
}

static NSURL *WQMAppIconDiagnosticsLogURL(void)
{
    static NSURL *url;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSURL *documents = [NSFileManager.defaultManager
            URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
        NSDateFormatter *formatter = [NSDateFormatter new];
        formatter.dateFormat = @"yyyyMMdd-HHmmss";
        NSString *name = [NSString stringWithFormat:@"icon-diag-%@.log",
                          [formatter stringFromDate:NSDate.date]];
        url = [documents URLByAppendingPathComponent:name];
    });
    return url;
}

static void WQMAppIconDiag(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void WQMAppIconDiag(NSString *format, ...)
{
    if (!WQMAppIconDiagnosticsWanted()) return;
    va_list arguments;
    va_start(arguments, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);
    NSLog(@"[WQM icon] %@", line);

    NSURL *url = WQMAppIconDiagnosticsLogURL();
    @synchronized (url) {
        NSData *data = [[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
        if (![NSFileManager.defaultManager fileExistsAtPath:url.path]) {
            [data writeToURL:url atomically:YES];
            return;
        }
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingToURL:url error:nil];
        if (!handle) return;
        @try {
            [handle seekToEndOfFile];
            [handle writeData:data];
        } @catch (NSException *__unused exception) {
        }
        [handle closeFile];
    }
}

static NSString *WQMAppIconDiagHex(NSData *data, NSUInteger limit)
{
    NSUInteger count = MIN(data.length, limit);
    const uint8_t *bytes = data.bytes;
    NSMutableString *text = [NSMutableString stringWithCapacity:count * 2];
    for (NSUInteger index = 0; index < count; index++) {
        [text appendFormat:@"%02x", bytes[index]];
    }
    return text;
}

static NSString *WQMAppIconDiagDescribeData(NSData *data)
{
    if (!data.length) return @"none";
    const uint8_t *bytes = data.bytes;
    NSMutableString *text = [NSMutableString stringWithFormat:@"len=%lu",
                             (unsigned long)data.length];
    uint32_t version = 0, pixels = 0, bom = 0, flags = 0;
    if (data.length >= 16) {
        memcpy(&version, bytes, 4);
        memcpy(&pixels, bytes + 4, 4);
        memcpy(&bom, bytes + 8, 4);
        memcpy(&flags, bytes + 12, 4);
        [text appendFormat:@" v=%u pix=%u bom=%u flags=%u", version, pixels, bom, flags];
    }
    if (data.length >= 40) {
        float width = 0, height = 0, insetA = 0, insetB = 0, canvasW = 0, canvasH = 0;
        memcpy(&width, bytes + 16, 4);
        memcpy(&height, bytes + 20, 4);
        memcpy(&insetA, bytes + 24, 4);
        memcpy(&insetB, bytes + 28, 4);
        memcpy(&canvasW, bytes + 32, 4);
        memcpy(&canvasH, bytes + 36, 4);
        double area = (double)width * (double)height;
        double bytesPerPixel = area > 0 ? (double)pixels / area : 0;
        [text appendFormat:@" size=%.0fx%.0f bpp=%.1f", width, height, bytesPerPixel];
    }
    NSUInteger bomOffset = 48 + (NSUInteger)pixels;
    if (bom && bomOffset + 8 <= data.length &&
        memcmp(bytes + bomOffset, "BOMStore", 8) == 0) {
        [text appendFormat:@" bomAt=%lu", (unsigned long)bomOffset];
    }
    [text appendFormat:@" head=%@", WQMAppIconDiagHex(data, 16)];
    return text;
}

static NSString *WQMAppIconDiagDescribeImage(UIImage *image)
{
    if (!image) return @"none";
    NSString *usable = WQMAppIconLooksUsable(image) ? @"usable" : @"rejected";
    NSString *placeholder = WQMAppIconLooksLikeKnownPlaceholder(image) ? @"placeholder" : @"-";
    return [NSString stringWithFormat:@"%.0fx%.0f %@ %@", image.size.width,
            image.size.height, usable, placeholder];
}

static void WQMAppIconDiagDump(NSString *bundleIdentifier, NSData *data)
{
    if (data.length < 1024 * 1024) return;
    if (![NSProcessInfo.processInfo.environment[@"WQM_ICON_DIAG_DUMP"] boolValue]) return;
    static NSUInteger dumps;
    if (dumps >= 3) return;
    dumps++;
    NSURL *documents = [NSFileManager.defaultManager
        URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    NSString *name = [NSString stringWithFormat:@"icon-dump-%@.bin", bundleIdentifier];
    [data writeToURL:[documents URLByAppendingPathComponent:name] atomically:NO];
    WQMAppIconDiag(@"dump id=%@ bytes=%lu", bundleIdentifier, (unsigned long)data.length);
}

// Probes a directory or file the same way the icon code would use it: worse_query
// grant first, then read. Kept read-only and exception-safe.
static NSString *WQMAppIconDiagProbePath(NSString *path, NSString *label)
{
    if (!path.length) return [NSString stringWithFormat:@"%@ path=-", label];
    struct stat info = {0};
    BOOL exists = lstat(path.fileSystemRepresentation, &info) == 0;
    BOOL granted = exists ? wq_grant(path) : NO;
    NSError *error = nil;
    NSArray<NSString *> *entries = granted
        ? [NSFileManager.defaultManager contentsOfDirectoryAtPath:path error:&error] : nil;
    NSMutableString *text = [NSMutableString stringWithFormat:@"%@ exists=%d grant=%d",
                             label, exists, granted];
    if (entries) {
        [text appendFormat:@" entries=%lu", (unsigned long)entries.count];
        NSArray<NSString *> *sorted = [entries sortedArrayUsingSelector:@selector(compare:)];
        if (sorted.count) {
            NSUInteger head = MIN((NSUInteger)4, sorted.count);
            [text appendFormat:@" first=%@", [[sorted subarrayWithRange:NSMakeRange(0, head)]
                componentsJoinedByString:@","]];
        }
    } else if (error) {
        [text appendFormat:@" err=%@", error.localizedDescription];
    }
    return text;
}

static void WQMAppIconDiagProbeBundle(NSString *bundleIdentifier, NSString *bundlePath)
{
    if (!bundleIdentifier.length || !bundlePath.length) return;
    NSString *infoPath = [bundlePath stringByAppendingPathComponent:@"Info.plist"];
    NSString *assetsPath = [bundlePath stringByAppendingPathComponent:@"Assets.car"];
    NSData *infoData = [NSData dataWithContentsOfFile:infoPath options:0 error:nil];
    NSData *assetsData = [NSData dataWithContentsOfFile:assetsPath options:0 error:nil];
    NSArray<NSString *> *entries = [NSFileManager.defaultManager
        contentsOfDirectoryAtPath:bundlePath error:nil];
    NSMutableArray<NSString *> *iconFiles = [NSMutableArray array];
    for (NSString *name in entries) {
        NSString *lower = name.lowercaseString;
        if ([lower hasPrefix:@"appicon"] || [lower hasSuffix:@".car"]) {
            [iconFiles addObject:name];
        }
    }
    WQMAppIconDiag(@"id=%@ bundleRead info=%lu assets=%lu entries=%lu icons=%@",
                   bundleIdentifier, (unsigned long)infoData.length,
                   (unsigned long)assetsData.length, (unsigned long)entries.count,
                   iconFiles.count ? [iconFiles componentsJoinedByString:@","] : @"-");
}

// The on-disk IconServices cache is the only remaining source once LaunchServices
// refuses to map its database. Probe readability and keep one record for offline
// decoding (the raw record is small enough to share).
static void WQMAppIconDiagProbeCache(void)
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray<NSString *> *paths = @[
            @"/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.lsd.iconscache",
            @"/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.lsd.iconscache/Library/Caches/com.apple.IconsCache",
            @"/private/var/mobile/Library/Caches/com.apple.IconsCache",
            @"/private/var/mobile/Library/Caches/com.apple.springboard",
            @"/private/var/mobile/Library/Caches/com.apple.springboard/IconCache",
        ];
        for (NSString *path in paths) {
            WQMAppIconDiag(@"cache %@", WQMAppIconDiagProbePath(path, @"dir"));
        }
        NSString *store = @"/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.lsd.iconscache/Library/Caches/com.apple.IconsCache";
        (void)wq_grant(store);
        NSArray<NSString *> *stores = [NSFileManager.defaultManager
            contentsOfDirectoryAtPath:store error:nil];
        NSString *storeContents = nil;
        for (NSString *name in [stores sortedArrayUsingSelector:@selector(compare:)]) {
            BOOL directory = NO;
            NSString *candidate = [store stringByAppendingPathComponent:name];
            if ([NSFileManager.defaultManager fileExistsAtPath:candidate isDirectory:&directory] &&
                directory) {
                storeContents = candidate;
                break;
            }
        }
        WQMAppIconDiag(@"cache store=%@ entries=%lu",
                       storeContents.lastPathComponent ?: @"-", (unsigned long)stores.count);
        NSArray<NSString *> *entries = storeContents
            ? [NSFileManager.defaultManager contentsOfDirectoryAtPath:storeContents error:nil]
            : nil;
        if (!entries.count) {
            WQMAppIconDiag(@"cache store unreadable entries=0");
            return;
        }
        WQMAppIconDiag(@"cache store entries=%lu first=%@", (unsigned long)entries.count,
                       [[entries sortedArrayUsingSelector:@selector(compare:)]
                           subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)4, entries.count))]);
        NSString *sample = nil;
        for (NSString *name in entries) {
            if ([name hasSuffix:@".isdata"]) { sample = name; break; }
        }
        if (!sample) { WQMAppIconDiag(@"cache no isdata"); return; }
        NSString *path = [storeContents stringByAppendingPathComponent:sample];
        NSData *data = [NSData dataWithContentsOfFile:path options:0 error:nil];
        WQMAppIconDiag(@"cache sample=%@ %@", sample, WQMAppIconDiagDescribeData(data));
        if (data.length && data.length <= 4 * 1024 * 1024) {
            NSURL *documents = [NSFileManager.defaultManager
                URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
            NSString *out = [documents.path stringByAppendingPathComponent:@"icon-cache-sample.isdata"];
            [data writeToFile:out atomically:NO];
            WQMAppIconDiag(@"cache sample saved %@ bytes=%lu", out, (unsigned long)data.length);
        }
    });
}

static void WQMAppIconDiagSaveImage(NSString *bundleIdentifier, UIImage *image)
{
    if (!image || !WQMAppIconDiagnosticsWanted()) return;
    static NSMutableSet<NSString *> *saved;
    static NSUInteger count;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ saved = [NSMutableSet new]; });
    @synchronized (saved) {
        if ([saved containsObject:bundleIdentifier] || count >= 6) return;
        [saved addObject:bundleIdentifier];
        count++;
    }
    NSData *png = UIImagePNGRepresentation(image);
    if (!png.length) return;
    NSURL *documents = [NSFileManager.defaultManager
        URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    NSString *name = [NSString stringWithFormat:@"icon-result-%@.png", bundleIdentifier];
    NSString *path = [documents.path stringByAppendingPathComponent:name];
    [png writeToFile:path atomically:NO];
    WQMAppIconDiag(@"id=%@ resultPng=%@ bytes=%lu", bundleIdentifier, name,
                   (unsigned long)png.length);
}

static void WQMAppIconDiagnose(NSString *bundleIdentifier)
{
    if (!WQMAppIconDiagnosticsWanted() || !bundleIdentifier.length) return;
    static NSMutableSet<NSString *> *seen;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        seen = [NSMutableSet new];
        WQMAppIconDiag(@"env os=%@ app=%@", NSProcessInfo.processInfo.operatingSystemVersionString,
                       NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"] ?: @"?");
        WQMAppIconDiagProbeCache();
    });
    @synchronized (seen) {
        if ([seen containsObject:bundleIdentifier]) return;
        if (seen.count >= 12 &&
            ![NSProcessInfo.processInfo.environment[@"WQM_ICON_DIAG_ALL"] boolValue]) {
            if (seen.count == 12) {
                WQMAppIconDiag(@"diag limit reached; set WQM_ICON_DIAG_ALL=1 for every app");
            }
            [seen addObject:bundleIdentifier];
            return;
        }
        [seen addObject:bundleIdentifier];
    }

    id proxy = WQMApplicationProxyForIdentifier(bundleIdentifier);
    NSString *bundlePath = WQMApplicationProxyBundlePathWithProxy(proxy);
    if (!bundlePath.length) bundlePath = WQMAppBundlePath(bundleIdentifier);
    BOOL granted = bundlePath.length ? wq_grant(bundlePath) : NO;
    WQMAppIconDiag(@"id=%@ proxy=%d isSystem=%d thirdParty=%d grant=%d path=%@",
                   bundleIdentifier, proxy != nil, WQMApplicationProxyIsSystemApp(proxy),
                   WQMAppBundleIsThirdParty(proxy, bundlePath), granted, bundlePath ?: @"-");
    WQMAppIconDiagProbeBundle(bundleIdentifier, bundlePath);

    NSArray<NSString *> *selectors = @[
        @"primaryIconDataForVariant:withOptions:",
        @"iconDataForVariant:withOptions:",
    ];
    for (NSNumber *variant in @[@10, @8, @2, @0]) {
        for (NSString *selector in selectors) {
            id value = WQMApplicationProxyIconData(proxy, selector, variant.intValue, YES);
            NSData *data = [value isKindOfClass:NSData.class] ? value : nil;
            UIImage *direct = data.length ? [UIImage imageWithData:data] : nil;
            UIImage *layered = (data.length && !direct) ? WQMLayeredIconImageFromData(data) : nil;
            WQMAppIconDiag(@"id=%@ sel=%@ var=%@ %@ ui=%@ layered=%@",
                           bundleIdentifier, selector, variant,
                           WQMAppIconDiagDescribeData(data),
                           WQMAppIconDiagDescribeImage(direct),
                           WQMAppIconDiagDescribeImage(layered));
            WQMAppIconDiagDump(bundleIdentifier, data);
        }
    }

    SEL allSizesSelector = NSSelectorFromString(@"iconsOfAllSizes");
    if ([proxy respondsToSelector:allSizesSelector]) {
        @try {
            id icons = ((id (*)(id, SEL))objc_msgSend)(proxy, allSizesSelector);
            NSDictionary *entries = [icons isKindOfClass:NSDictionary.class] ? icons : nil;
            NSUInteger largest = 0, images = 0;
            for (id value in entries.allValues) {
                if ([value isKindOfClass:NSData.class]) {
                    largest = MAX(largest, [(NSData *)value length]);
                } else if ([value isKindOfClass:UIImage.class]) {
                    images++;
                }
            }
            WQMAppIconDiag(@"id=%@ allSizes entries=%lu largest=%lu images=%lu",
                           bundleIdentifier, (unsigned long)entries.count,
                           (unsigned long)largest, (unsigned long)images);
        } @catch (NSException *__unused exception) {
        }
    }

    for (NSNumber *format in @[@10, @8, @2, @0, @1]) {
        UIImage *scaled = WQMApplicationProxyIconImage(
            proxy, @"applicationIconImageForFormat:scale:", format.intValue, YES);
        UIImage *plain = WQMApplicationProxyIconImage(
            proxy, @"applicationIconImageForFormat:", format.intValue, NO);
        WQMAppIconDiag(@"id=%@ fmt=%@ scaled=%@ plain=%@", bundleIdentifier, format,
                       WQMAppIconDiagDescribeImage(scaled),
                       WQMAppIconDiagDescribeImage(plain));
    }

    WQMAppIconDiag(@"id=%@ sources iconservices=%@ springboard=%@ bundle=%@ direct=%@ catalog=%@",
                   bundleIdentifier,
                   WQMAppIconDiagDescribeImage(WQMIconServicesIcon(bundleIdentifier)),
                   WQMAppIconDiagDescribeImage(WQMSpringBoardIcon(bundleIdentifier)),
                   WQMAppIconDiagDescribeImage(WQMBundleIcon(bundleIdentifier)),
                   WQMAppIconDiagDescribeImage(WQMRealSystemIcon(bundleIdentifier)),
                   WQMAppIconDiagDescribeImage(bundlePath.length
                       ? WQMCUICatalogIcon(bundlePath) : nil));
}

static UIImage *WQMResolveIcon(NSString *bundleIdentifier)
{
    WQMAppIconDiagnose(bundleIdentifier);
    id proxy = WQMApplicationProxyForIdentifier(bundleIdentifier);
    NSString *bundlePath = WQMApplicationProxyBundlePathWithProxy(proxy);
    if (!bundlePath.length) bundlePath = WQMAppBundlePath(bundleIdentifier);
    if (bundlePath.length) (void)wq_grant(bundlePath);
    BOOL thirdParty = WQMAppBundleIsThirdParty(proxy, bundlePath);
    UIImage *raw = WQMApplicationProxyIcon(proxy);
    if (!raw && !thirdParty) raw = WQMRealSystemIcon(bundleIdentifier);
    if (!raw) raw = WQMIconServicesIcon(bundleIdentifier);
    if (!raw) raw = WQMSpringBoardIcon(bundleIdentifier);
    if (!raw && bundlePath.length) raw = WQMCUICatalogIcon(bundlePath);
    if (!raw) raw = WQMBundleIcon(bundleIdentifier);
    NSArray<NSString *> *parts = [bundleIdentifier componentsSeparatedByString:@"."];
    for (NSInteger count = (NSInteger)parts.count - 1; !raw && count >= 3; count--) {
        NSString *parent = [[parts subarrayWithRange:NSMakeRange(0, (NSUInteger)count)]
                            componentsJoinedByString:@"."];
        id parentProxy = WQMApplicationProxyForIdentifier(parent);
        NSString *parentPath = WQMApplicationProxyBundlePathWithProxy(parentProxy);
        if (!parentPath.length) parentPath = WQMAppBundlePath(parent);
        if (parentPath.length) (void)wq_grant(parentPath);
        BOOL parentThirdParty = WQMAppBundleIsThirdParty(parentProxy, parentPath);
        raw = WQMApplicationProxyIcon(parentProxy);
        if (!raw && !parentThirdParty) raw = WQMRealSystemIcon(parent);
        if (!raw) raw = WQMIconServicesIcon(parent);
        if (!raw) raw = WQMSpringBoardIcon(parent);
        if (!raw && parentPath.length) raw = WQMCUICatalogIcon(parentPath);
        if (!raw) raw = WQMBundleIcon(parent);
    }
    NSString *placeholderDigest = nil;
    NSArray<NSString *> *placeholderConflicts = nil;
    if (WQMAppIconIsGenericPlaceholder(raw, bundleIdentifier,
                                       &placeholderDigest, &placeholderConflicts)) {
        WQMAppIconDiag(@"id=%@ placeholder=generic digest=%@ conflicts=%@",
                       bundleIdentifier, placeholderDigest, placeholderConflicts);
        for (NSString *other in placeholderConflicts) WQMAppIconForgetCachedIcon(other);
        WQMAppIconForgetCachedIcon(bundleIdentifier);
        raw = nil;
    }
    WQMAppIconDiagSaveImage(bundleIdentifier, raw);
    WQMAppIconDiag(@"id=%@ result=%@ raw=%@", bundleIdentifier, raw ? @"image" : @"nil",
                   WQMAppIconDiagDescribeImage(raw));
    return raw ? WQMRoundIcon(raw) : nil;
}

#pragma mark - Remote icons

// When the local icon services are blocked (unjailbroken devices without the
// iconservices entitlement), fall back to the public App Store artwork lookup.
// Only App Store apps resolve; sideloaded bundles simply keep the letter tile.

static BOOL WQMAppIconRemoteEnabled(void)
{
    NSString *environment = NSProcessInfo.processInfo.environment[@"WQM_ICON_REMOTE"];
    if (environment.length && !environment.boolValue) return NO;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults objectForKey:@"WQMAppIconRemoteEnabled"]) {
        return [defaults boolForKey:@"WQMAppIconRemoteEnabled"];
    }
    return YES;
}

static NSMutableSet<NSString *> *WQMAppIconRemotePending(void)
{
    static NSMutableSet *pending;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ pending = [NSMutableSet new]; });
    return pending;
}

static NSMutableSet<NSString *> *WQMAppIconFallbackIdentifiers(void)
{
    static NSMutableSet *identifiers;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ identifiers = [NSMutableSet new]; });
    return identifiers;
}

static NSMutableDictionary<NSString *, NSNumber *> *WQMAppIconRemoteMisses(void)
{
    static NSMutableDictionary *misses;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSDictionary *stored = [NSUserDefaults.standardUserDefaults
                                dictionaryForKey:@"WQMAppIconRemoteMisses"];
        misses = [NSMutableDictionary dictionaryWithDictionary:stored ?: @{}];
    });
    return misses;
}

static void WQMAppIconPersistRemoteMisses(void)
{
    NSDictionary *snapshot;
    @synchronized (WQMAppIconRemoteMisses()) {
        snapshot = [WQMAppIconRemoteMisses() copy];
    }
    [NSUserDefaults.standardUserDefaults setObject:snapshot
                                           forKey:@"WQMAppIconRemoteMisses"];
}

static BOOL WQMAppIconRemoteRecentlyMissed(NSString *bundleIdentifier)
{
    NSNumber *timestamp;
    @synchronized (WQMAppIconRemoteMisses()) {
        timestamp = WQMAppIconRemoteMisses()[bundleIdentifier];
    }
    if (timestamp == nil) return NO;
    return [NSDate date].timeIntervalSince1970 - timestamp.doubleValue < 24 * 60 * 60;
}

static void WQMAppIconRecordRemoteMiss(NSString *bundleIdentifier)
{
    @synchronized (WQMAppIconRemoteMisses()) {
        WQMAppIconRemoteMisses()[bundleIdentifier] =
            @([NSDate date].timeIntervalSince1970);
    }
    WQMAppIconPersistRemoteMisses();
}

static void WQMAppIconClearRemoteMiss(NSString *bundleIdentifier)
{
    @synchronized (WQMAppIconRemoteMisses()) {
        [WQMAppIconRemoteMisses() removeObjectForKey:bundleIdentifier];
    }
    WQMAppIconPersistRemoteMisses();
}

static NSURLSession *WQMAppIconRemoteSession(void)
{
    static NSURLSession *session;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSURLSessionConfiguration *configuration =
            [NSURLSessionConfiguration ephemeralSessionConfiguration];
        configuration.timeoutIntervalForRequest = 10;
        configuration.timeoutIntervalForResource = 20;
        configuration.HTTPAdditionalHeaders = @{@"User-Agent": @"WQManager/0.1"};
        session = [NSURLSession sessionWithConfiguration:configuration];
    });
    return session;
}

static void WQMAppIconApplyRemoteImage(UIImage *image, NSString *bundleIdentifier)
{
    if (!WQMAppIconLooksUsable(image) ||
        WQMAppIconLooksLikeKnownPlaceholder(image) ||
        WQMAppIconIsKnownGenericPlaceholderImage(image)) return;
    UIImage *rounded = WQMRoundIcon(image);
    WQMAppIconStoreDiskImage(rounded, bundleIdentifier);
    @synchronized (WQMAppIconFallbackIdentifiers()) {
        [WQMAppIconFallbackIdentifiers() removeObject:bundleIdentifier];
    }
    [WQMAppIconMemoryCache() setObject:rounded forKey:bundleIdentifier];
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter
            postNotificationName:WQMAppIconDidResolveNotification
                          object:nil
                        userInfo:@{WQMAppIconBundleIdentifierKey: bundleIdentifier}];
    });
}

static void WQMAppIconDownloadRemoteImage(NSString *artwork, NSString *bundleIdentifier)
{
    NSURLSessionDataTask *download =
        [WQMAppIconRemoteSession() dataTaskWithURL:[NSURL URLWithString:artwork]
                                completionHandler:^(NSData *imageData, NSURLResponse *response,
                                                    NSError *error) {
        UIImage *image = imageData.length ? [UIImage imageWithData:imageData] : nil;
        if (image) {
            WQMAppIconClearRemoteMiss(bundleIdentifier);
            WQMAppIconApplyRemoteImage(image, bundleIdentifier);
        }
        WQMAppIconDiag(@"id=%@ remote=%@ size=%@", bundleIdentifier,
                       image ? @"image" : @"nil", NSStringFromCGSize(image.size));
        @synchronized (WQMAppIconRemotePending()) {
            [WQMAppIconRemotePending() removeObject:bundleIdentifier];
        }
    }];
    [download resume];
}

static void WQMAppIconLookupArtwork(NSString *bundleIdentifier, NSString *country,
                                    void (^completion)(NSString *artwork, BOOL definitive))
{
    NSURLComponents *components =
        [NSURLComponents componentsWithString:@"https://itunes.apple.com/lookup"];
    NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray arrayWithObjects:
        [NSURLQueryItem queryItemWithName:@"bundleId" value:bundleIdentifier],
        [NSURLQueryItem queryItemWithName:@"limit" value:@"1"], nil];
    if (country.length) {
        [items addObject:[NSURLQueryItem queryItemWithName:@"country" value:country]];
    }
    components.queryItems = items;
    NSURLSessionDataTask *lookup =
        [WQMAppIconRemoteSession() dataTaskWithURL:components.URL
                                completionHandler:^(NSData *data, NSURLResponse *response,
                                                    NSError *error) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class]
            ? ((NSHTTPURLResponse *)response).statusCode : 0;
        BOOL definitive = NO;
        NSString *artwork = nil;
        if (data.length) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([json isKindOfClass:NSDictionary.class]) {
                definitive = status == 200;
                NSArray *results = json[@"results"];
                if ([results isKindOfClass:NSArray.class] && results.count) {
                    NSDictionary *item = results.firstObject;
                    if ([item isKindOfClass:NSDictionary.class]) {
                        for (NSString *key in @[@"artworkUrl512", @"artworkUrl100", @"artworkUrl60"]) {
                            NSString *value = item[key];
                            if ([value isKindOfClass:NSString.class] && value.length) {
                                artwork = value;
                                break;
                            }
                        }
                    }
                }
            }
        }
        completion(artwork, definitive);
    }];
    [lookup resume];
}

static void WQMAppIconFinishRemote(NSString *bundleIdentifier)
{
    @synchronized (WQMAppIconRemotePending()) {
        [WQMAppIconRemotePending() removeObject:bundleIdentifier];
    }
}

static void WQMAppIconRunRemoteLookup(NSString *bundleIdentifier, NSString *country,
                                      NSInteger attempt)
{
    WQMAppIconLookupArtwork(bundleIdentifier, country, ^(NSString *artwork, BOOL definitive) {
        if (artwork.length) {
            WQMAppIconDownloadRemoteImage(artwork, bundleIdentifier);
            return;
        }
        if (!definitive && attempt < 1) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                           dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                WQMAppIconRunRemoteLookup(bundleIdentifier, country, attempt + 1);
            });
            return;
        }
        if (country.length == 0) {
            WQMAppIconRunRemoteLookup(bundleIdentifier, @"cn", 0);
            return;
        }
        if (definitive) {
            WQMAppIconRecordRemoteMiss(bundleIdentifier);
            WQMAppIconDiag(@"id=%@ remote=miss", bundleIdentifier);
        } else {
            WQMAppIconDiag(@"id=%@ remote=error", bundleIdentifier);
        }
        WQMAppIconFinishRemote(bundleIdentifier);
    });
}

static void WQMAppIconFetchRemoteIcon(NSString *bundleIdentifier)
{
    if (!bundleIdentifier.length || !WQMAppIconRemoteEnabled()) return;
    if (WQMAppIconRemoteRecentlyMissed(bundleIdentifier)) return;
    @synchronized (WQMAppIconRemotePending()) {
        if ([WQMAppIconRemotePending() containsObject:bundleIdentifier]) return;
        [WQMAppIconRemotePending() addObject:bundleIdentifier];
    }
    static NSTimeInterval lastStart;
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    NSTimeInterval delay = 0;
    @synchronized (WQMAppIconService.class) {
        delay = MAX(0, 0.25 - (now - lastStart));
        lastStart = now + delay;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        WQMAppIconRunRemoteLookup(bundleIdentifier, nil, 0);
    });
}

@implementation WQMAppIconService

+ (UIImage *)iconForBundleIdentifier:(NSString *)bundleIdentifier displayName:(NSString *)displayName
{
    if (!bundleIdentifier.length) return WQMFallbackIcon(@"", displayName);
    UIImage *cached = [WQMAppIconMemoryCache() objectForKey:bundleIdentifier];
    return cached ?: WQMFallbackIcon(bundleIdentifier, displayName);
}

+ (void)requestIconForBundleIdentifier:(NSString *)bundleIdentifier displayName:(NSString *)displayName
{
    if (!bundleIdentifier.length) return;
    UIImage *cached = [WQMAppIconMemoryCache() objectForKey:bundleIdentifier];
    if (cached) {
        BOOL fallback = NO;
        @synchronized (WQMAppIconFallbackIdentifiers()) {
            fallback = [WQMAppIconFallbackIdentifiers() containsObject:bundleIdentifier];
        }
        if (fallback) {
            [WQMAppIconWorkQueue() addOperationWithBlock:^{
                UIImage *disk = WQMAppIconDiskImage(bundleIdentifier);
                if (disk) {
                    @synchronized (WQMAppIconFallbackIdentifiers()) {
                        [WQMAppIconFallbackIdentifiers() removeObject:bundleIdentifier];
                    }
                    [WQMAppIconMemoryCache() setObject:disk forKey:bundleIdentifier];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [NSNotificationCenter.defaultCenter
                            postNotificationName:WQMAppIconDidResolveNotification
                                          object:nil
                                        userInfo:@{WQMAppIconBundleIdentifierKey: bundleIdentifier}];
                    });
                } else if (!WQMAppIconRemoteRecentlyMissed(bundleIdentifier)) {
                    WQMAppIconFetchRemoteIcon(bundleIdentifier);
                }
            }];
        }
        return;
    }
    if (NSThread.isMainThread) WQMAppIconRenderScale = WQMAppIconCurrentScreenScale();
    NSUInteger generation;
    @synchronized (WQMAppIconPendingIdentifiers()) {
        if ([WQMAppIconPendingIdentifiers() containsObject:bundleIdentifier]) return;
        [WQMAppIconPendingIdentifiers() addObject:bundleIdentifier];
        generation = WQMAppIconGeneration;
    }
    [WQMAppIconWorkQueue() addOperationWithBlock:^{
        NSUInteger currentGeneration;
        @synchronized (WQMAppIconPendingIdentifiers()) {
            currentGeneration = WQMAppIconGeneration;
        }
        if (generation != currentGeneration) return;

        UIImage *diskIcon = WQMAppIconDiskImage(bundleIdentifier);
        UIImage *resolved = diskIcon ?: WQMResolveIcon(bundleIdentifier);
        if (generation != currentGeneration) return;
        if (!resolved) WQMAppIconFetchRemoteIcon(bundleIdentifier);
        BOOL actualIcon = resolved != nil;
        UIImage *icon = resolved ?: WQMFallbackIcon(bundleIdentifier, displayName);
        if (actualIcon) {
            WQMAppIconStoreDiskImage(icon, bundleIdentifier);
            @synchronized (WQMAppIconFallbackIdentifiers()) {
                [WQMAppIconFallbackIdentifiers() removeObject:bundleIdentifier];
            }
            [WQMAppIconMemoryCache() setObject:icon forKey:bundleIdentifier];
        } else {
            @synchronized (WQMAppIconFallbackIdentifiers()) {
                [WQMAppIconFallbackIdentifiers() addObject:bundleIdentifier];
            }
            // A remote image may have landed while we were resolving; do not
            // replace a real icon with the letter fallback.
            if (![WQMAppIconMemoryCache() objectForKey:bundleIdentifier]) {
                [WQMAppIconMemoryCache() setObject:icon forKey:bundleIdentifier];
            }
        }
        @synchronized (WQMAppIconPendingIdentifiers()) {
            [WQMAppIconPendingIdentifiers() removeObject:bundleIdentifier];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter postNotificationName:WQMAppIconDidResolveNotification
                                                              object:nil
                                                            userInfo:@{WQMAppIconBundleIdentifierKey:
                                                                           bundleIdentifier}];
        });
    }];
}

+ (void)cancelPendingRequests
{
    @synchronized (WQMAppIconPendingIdentifiers()) {
        WQMAppIconGeneration++;
        [WQMAppIconPendingIdentifiers() removeAllObjects];
    }
    [WQMAppIconWorkQueue() cancelAllOperations];
}

+ (void)clearCache
{
    [self cancelPendingRequests];
    [WQMAppIconMemoryCache() removeAllObjects];
    [WQMAppIconFallbackCache() removeAllObjects];
    NSArray<NSURL *> *items = [NSFileManager.defaultManager
        contentsOfDirectoryAtURL:WQMAppIconDiskDirectory()
      includingPropertiesForKeys:nil
                         options:NSDirectoryEnumerationSkipsHiddenFiles
                           error:nil] ?: @[];
    for (NSURL *url in items) {
        [NSFileManager.defaultManager removeItemAtURL:url error:nil];
    }
}

@end
