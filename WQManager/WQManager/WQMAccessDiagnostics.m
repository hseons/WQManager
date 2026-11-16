#import "WQMAccessDiagnostics.h"
#import "WQMAppModel.h"
#import "WQAccessSafety.h"
#import "WQMLanguageManager.h"
#import <TargetConditionals.h>
#import <dirent.h>
#import <sys/sysctl.h>

#if TARGET_OS_IOS
typedef struct __SecTask *SecTaskRef;
extern SecTaskRef SecTaskCreateFromSelf(CFAllocatorRef allocator);
extern CFTypeRef SecTaskCopyValueForEntitlement(SecTaskRef task, CFStringRef entitlement, CFErrorRef *error);
#endif

static NSString *WQMAccessReason(NSString *reason)
{
    NSDictionary *text = @{
        @"ok": WQML(@"ACCESS_REASON_OK", @"本次检查通过。"),
        @"no-group": WQML(@"ACCESS_REASON_GROUP", @"签名未保留可用 App Group；请使用保留 App Group 的方式重新签名。"),
        @"api": WQML(@"ACCESS_REASON_API", @"容器查询接口不可用；导出报告时会附带当前系统 build。"),
        @"query": WQML(@"ACCESS_REASON_QUERY", @"容器查询初始化失败；重启工具后重试。"),
        @"prepare": WQML(@"ACCESS_REASON_PREPARE", @"App Group 准备失败或正在使用；结束其他操作后重试。"),
        @"result": WQML(@"ACCESS_REASON_RESULT", @"查询未返回目标容器；刷新 App 索引后重试。"),
        @"token": WQML(@"ACCESS_REASON_TOKEN", @"查询未返回访问 token；可导出报告反馈系统与签名兼容性。"),
        @"consume": WQML(@"ACCESS_REASON_CONSUME", @"系统未接受访问 token；重启工具后重试。"),
        @"recovery": WQML(@"ACCESS_REASON_RECOVERY", @"工具的 App Group 缓存恢复未完成；请保留现有数据并反馈。"),
        @"exception": WQML(@"ACCESS_REASON_EXCEPTION", @"容器查询发生异常；可导出报告反馈。"),
        @"denied": WQML(@"ACCESS_REASON_DENIED", @"系统拒绝访问。解锁设备后重试；仍失败时导出报告，进一步核对系统与签名。"),
        @"permission": WQML(@"ACCESS_REASON_PERMISSION", @"读取权限受限，可能涉及文件权限或数据保护。解锁设备后重试；本次检查未确定具体原因。"),
        @"missing": WQML(@"ACCESS_REASON_MISSING", @"目录当前不存在；若 App 已更新或重装，请刷新索引。"),
        @"changed": WQML(@"ACCESS_REASON_CHANGED", @"容器身份与索引不一致；请刷新 App 索引后再检查。"),
        @"identity": WQML(@"ACCESS_REASON_IDENTITY", @"缺少可验证的容器归属；请刷新索引。本次未继续读取子目录。"),
        @"path": WQML(@"ACCESS_REASON_PATH", @"目标不在已识别的 App 数据容器范围，或路径包含链接。"),
        @"io": WQML(@"ACCESS_REASON_IO", @"读取失败；请结合错误码与系统 build 反馈。"),
        @"no-sample": WQML(@"ACCESS_REASON_SAMPLE", @"有限范围内未找到普通文件；文件内容读取尚未验证。"),
        @"cancelled": WQML(@"ACCESS_REASON_CANCELLED", @"检查已停止；未完成部分尚未验证。"),
    };
    return text[reason] ?: text[@"io"];
}

@implementation WQMAccessCheck
- (NSString *)title
{
    NSDictionary *titles = @{
        @"target": WQML(@"ACCESS_STAGE_TARGET", @"索引中的容器"),
        @"grant": WQML(@"ACCESS_STAGE_GRANT", @"访问 token"),
        @"identity": WQML(@"ACCESS_STAGE_IDENTITY", @"容器身份"),
        @"root-open": WQML(@"ACCESS_STAGE_ROOT_OPEN", @"打开容器目录"),
        @"root-list": WQML(@"ACCESS_STAGE_ROOT_LIST", @"读取容器目录"),
        @"cancelled": WQML(@"ACCESS_STAGE_CANCELLED", @"检查进度"),
    };
    if (titles[self.stage]) return titles[self.stage];
    NSArray *parts = [self.stage componentsSeparatedByString:@"-"];
    NSString *scope = @{@"documents": @"Documents", @"library": @"Library", @"tmp": @"tmp"}[parts.firstObject];
    NSString *action = @{
        @"open": WQML(@"ACCESS_STAGE_OPEN", @"打开目录"),
        @"list": WQML(@"ACCESS_STAGE_LIST", @"读取目录"),
        @"read": WQML(@"ACCESS_STAGE_READ", @"文件读取样本"),
    }[parts.lastObject];
    return [NSString stringWithFormat:@"%@ · %@", scope ?: @"", action ?: @""];
}
- (NSString *)detail
{
    NSString *status = @{
        @"passed": WQML(@"ACCESS_PASSED", @"通过"),
        @"failed": WQML(@"ACCESS_FAILED", @"受限"),
        @"missing": WQML(@"ACCESS_MISSING", @"不存在"),
        @"not-tested": WQML(@"ACCESS_NOT_TESTED", @"未验证"),
    }[self.status] ?: @"";
    NSMutableString *detail = [NSMutableString stringWithFormat:@"%@ · %@", status, WQMAccessReason(self.reason)];
    if ([self.stage hasSuffix:@"-list"] && [self.status isEqual:@"passed"])
        [detail appendFormat:WQML(@"ACCESS_LIST_SAMPLE", @" 读取了 %lu 个条目%@。"),
         (unsigned long)self.sampledEntries, self.sampleLimited ? WQML(@"ACCESS_LIMITED", @"（已达抽样上限）") : @""];
    if ([self.stage hasSuffix:@"-read"] && [self.status isEqual:@"passed"])
        [detail appendString:WQML(@"ACCESS_READ_SAMPLE", @" 仅验证一个普通文件最多 1 字节的读取，不代表全部文件。")];
    if (self.code || self.systemError) [detail appendFormat:@" [code %ld, errno %d]", (long)self.code, self.systemError];
    return detail;
}
@end

@implementation WQMAccessReport
- (NSData *)redactedJSONData
{
    NSMutableDictionary *environment = [NSMutableDictionary new];
    for (NSString *key in @[@"OSVersion", @"OSBuild", @"Hardware", @"AppVersion", @"AppBuild", @"Simulator",
                            @"AppGroupEntitlementCount", @"UsableAppGroup", @"DevelopmentEntitlement",
                            @"EmbeddedProfilePresent", @"ProtectedDataAvailable", @"SyntheticTarget", @"SigningEntitlementsReadable"])
        if (self.environment[key]) environment[key] = self.environment[key];
    NSMutableArray *checks = [NSMutableArray new];
    for (WQMAccessCheck *check in self.checks) {
        [checks addObject:@{@"Stage": check.stage, @"Status": check.status, @"Reason": check.reason,
                           @"Code": @(check.code), @"Errno": @(check.systemError),
                           @"SampledEntries": @(check.sampledEntries), @"SampleLimited": @(check.sampleLimited)}];
    }
    return [NSJSONSerialization dataWithJSONObject:@{
        @"Format": @1, @"Category": @"app-data", @"Environment": environment,
        @"CreatedAt": [NSISO8601DateFormatter.new stringFromDate:self.createdAt],
        @"DurationSeconds": @(self.duration), @"Cancelled": @(self.cancelled), @"Checks": checks,
        @"UntestedCategories": @[@"shared-app-groups", @"extensions", @"system"],
        @"WriteCapability": @"not-tested", @"ReadScope": @"bounded-sample",
    } options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
}
@end

static NSString *WQMAccessErrnoReason(int value)
{
    if (value == ENOENT) return @"missing";
    if (value == EPERM) return @"denied";
    if (value == EACCES) return @"permission";
    if (value == ELOOP || value == ENOTDIR || value == EINVAL) return @"path";
    return @"io";
}

static WQMAccessCheck *WQMAccessAdd(NSMutableArray *checks, NSString *stage, NSString *status, NSString *reason, int err)
{
    WQMAccessCheck *check = [WQMAccessCheck new];
    check.stage = stage; check.status = status; check.reason = reason; check.systemError = err;
    [checks addObject:check];
    return check;
}

// Names and read bytes stay on the stack, never in a report or log. No recursion.
static void WQMAccessSample(int fd, NSString *scope, NSMutableArray *checks, BOOL (^cancelled)(void))
{
    int listing = dup(fd);
    DIR *directory = listing >= 0 ? fdopendir(listing) : NULL;
    if (!directory) {
        int err = errno;
        if (listing >= 0) close(listing);
        WQMAccessAdd(checks, [scope stringByAppendingString:@"-list"], @"failed", WQMAccessErrnoReason(err), err);
        return;
    }
    NSUInteger count = 0;
    int listError = 0, sampleError = 0;
    BOOL sampleAttempted = NO, sampleRead = NO, limited = NO;
    while (!cancelled()) {
        errno = 0;
        struct dirent *entry = readdir(directory);
        if (!entry) { listError = errno; break; }
        if (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, "..")) continue;
        if (count == 64) { limited = YES; break; }
        count++;
        if ([scope isEqual:@"root"] || sampleAttempted) continue;
        struct stat st;
        if (fstatat(fd, entry->d_name, &st, AT_SYMLINK_NOFOLLOW) != 0 || !S_ISREG(st.st_mode)) continue;
        sampleAttempted = YES;
        int file = WQOpenRegularAt(fd, entry->d_name, O_RDONLY, 0);
        if (file < 0) { sampleError = errno; continue; }
        struct stat opened;
        if (fstat(file, &opened) != 0 || !WQSameObject(&st, &opened)) sampleError = ESTALE;
        else {
            unsigned char byte;
            ssize_t bytes;
            do { bytes = read(file, &byte, 1); } while (bytes < 0 && errno == EINTR && !cancelled());
            sampleRead = bytes >= 0;
            if (!sampleRead) sampleError = errno;
        }
        close(file);
    }
    closedir(directory);
    WQMAccessCheck *list = WQMAccessAdd(checks, [scope stringByAppendingString:@"-list"],
        cancelled() ? @"not-tested" : listError ? @"failed" : @"passed",
        cancelled() ? @"cancelled" : listError ? WQMAccessErrnoReason(listError) : @"ok", listError);
    list.sampledEntries = count; list.sampleLimited = limited;
    if (![scope isEqual:@"root"])
        WQMAccessAdd(checks, [scope stringByAppendingString:@"-read"], sampleRead ? @"passed" : sampleAttempted ? @"failed" : @"not-tested",
            sampleRead ? @"ok" : sampleAttempted ? WQMAccessErrnoReason(sampleError) : @"no-sample", sampleError);
}

@implementation WQMAccessDiagnostics {
    NSString *_root;
    WQMAccessGrant _grant;
    WQMAccessLabel _label;
}
- (instancetype)initWithContainerRoot:(NSString *)root grant:(WQMAccessGrant)grant label:(WQMAccessLabel)label
{
    if ((self = [super init])) { _root = [WQCanonicalVarPath(root) copy]; _grant = [grant copy]; _label = [label copy]; }
    return self;
}
- (WQMAccessReport *)probeApp:(WQMAppModel *)app environment:(NSDictionary *)environment cancelled:(BOOL (^)(void))cancelled
{
    WQMAccessReport *report = [WQMAccessReport new];
    report.environment = environment; report.createdAt = NSDate.date;
    NSTimeInterval started = NSProcessInfo.processInfo.systemUptime;
    NSMutableArray *checks = [NSMutableArray new];
    int fd = -1;
    @try {
        if (cancelled()) return report;
        NSString *path = WQCanonicalVarPath(app.containerPath);
        if (![path.stringByDeletingLastPathComponent isEqual:_root] ||
            [path.pathComponents containsObject:@".."] || [path.pathComponents containsObject:@"."]) {
            WQMAccessAdd(checks, @"target", @"failed", @"path", 0); return report;
        }
        WQMAccessAdd(checks, @"target", @"passed", @"ok", 0);
        NSInteger code = 0; int grantError = 0;
        BOOL granted = _grant(path, &code, &grantError);
        NSDictionary *reasons = @{@(-1): @"no-group", @(-2): @"api", @(-3): @"query", @(-4): @"prepare",
            @(-5): @"result", @(-6): @"token", @(-7): @"consume", @(-8): @"recovery", @(-9): @"exception",
            @(-10): @"denied", @(-11): WQMAccessErrnoReason(grantError)};
        WQMAccessCheck *grant = WQMAccessAdd(checks, @"grant", granted ? @"passed" : @"failed",
            granted ? @"ok" : reasons[@(code)] ?: @"io", grantError);
        grant.code = code;
        if (cancelled()) return report;
        // Verify a real descriptor even when the grant was cached or failed.
        fd = WQOpenDirectoryNoLinks(path);
        if (fd < 0) {
            int err = errno;
            WQMAccessAdd(checks, @"root-open", @"failed", WQMAccessErrnoReason(err), err); return report;
        }
        WQMAccessAdd(checks, @"root-open", @"passed", @"ok", 0);
        struct stat st;
        if (fstat(fd, &st) != 0) {
            int err = errno; WQMAccessAdd(checks, @"identity", @"failed", WQMAccessErrnoReason(err), err); return report;
        }
        if (app.identityKnown && (st.st_dev != app.containerDevice || st.st_ino != app.containerInode)) {
            WQMAccessAdd(checks, @"identity", @"failed", @"changed", 0); return report;
        }
        NSString *label = _label(path);
        // Re-open after the pathname-based label lookup; do not trust a replaced root.
        int current = WQOpenDirectoryNoLinks(path);
        struct stat now;
        BOOL same = current >= 0 && fstat(current, &now) == 0 && WQSameObject(&st, &now);
        if (current >= 0) close(current);
        if (!same || (label.length && app.bundleIdentifier.length && ![label isEqual:app.bundleIdentifier])) {
            WQMAccessAdd(checks, @"identity", @"failed", @"changed", 0); return report;
        }
        if (!label.length || !app.bundleIdentifier.length) {
            WQMAccessAdd(checks, @"identity", @"not-tested", @"identity", 0); return report;
        }
        WQMAccessAdd(checks, @"identity", @"passed", @"ok", 0);
        WQMAccessSample(fd, @"root", checks, cancelled);
        for (NSString *scope in @[@"Documents", @"Library", @"tmp"]) {
            if (cancelled()) break;
            NSString *stage = [scope.lowercaseString stringByAppendingString:@"-open"];
            int child = openat(fd, scope.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
            if (child < 0) {
                int err = errno;
                WQMAccessAdd(checks, stage, err == ENOENT ? @"missing" : @"failed", WQMAccessErrnoReason(err), err);
                continue;
            }
            WQMAccessAdd(checks, stage, @"passed", @"ok", 0);
            WQMAccessSample(child, scope.lowercaseString, checks, cancelled);
            close(child);
        }
    } @finally {
        if (fd >= 0) close(fd);
        report.cancelled = cancelled();
        if (report.cancelled) WQMAccessAdd(checks, @"cancelled", @"not-tested", @"cancelled", 0);
        report.checks = checks;
        report.duration = NSProcessInfo.processInfo.systemUptime - started;
    }
    return report;
}
+ (NSDictionary *)environmentWithProtectedDataAvailable:(BOOL)available
{
    NSMutableDictionary *environment = [NSMutableDictionary new];
    for (NSString *key in @[@"kern.osversion", @"hw.machine"]) {
        char value[256] = {0}; size_t length = sizeof(value);
        if (sysctlbyname(key.UTF8String, value, &length, NULL, 0) == 0)
            environment[[key isEqual:@"kern.osversion"] ? @"OSBuild" : @"Hardware"] = [NSString stringWithUTF8String:value] ?: @"unknown";
    }
    NSOperatingSystemVersion os = NSProcessInfo.processInfo.operatingSystemVersion;
    environment[@"OSVersion"] = [NSString stringWithFormat:@"%ld.%ld.%ld", (long)os.majorVersion, (long)os.minorVersion, (long)os.patchVersion];
#if TARGET_OS_SIMULATOR
    // sysctl in Simulator describes the host kernel, not the iOS runtime build.
    NSString *runtimeRoot = NSProcessInfo.processInfo.environment[@"SIMULATOR_ROOT"];
    NSDictionary *runtime = runtimeRoot.length ? [NSDictionary dictionaryWithContentsOfFile:
        [runtimeRoot stringByAppendingPathComponent:@"System/Library/CoreServices/SystemVersion.plist"]] : nil;
    environment[@"OSBuild"] = [runtime[@"ProductBuildVersion"] isKindOfClass:NSString.class]
        ? runtime[@"ProductBuildVersion"] : @"unknown";
    environment[@"Hardware"] = NSProcessInfo.processInfo.environment[@"SIMULATOR_MODEL_IDENTIFIER"] ?: @"simulator";
#endif
    environment[@"AppVersion"] = NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"] ?: @"unknown";
    environment[@"AppBuild"] = NSBundle.mainBundle.infoDictionary[@"CFBundleVersion"] ?: @"unknown";
    environment[@"Simulator"] = @(TARGET_OS_SIMULATOR);
    environment[@"SyntheticTarget"] = @NO;
    environment[@"ProtectedDataAvailable"] = @(available);
    environment[@"EmbeddedProfilePresent"] = @([NSBundle.mainBundle pathForResource:@"embedded" ofType:@"mobileprovision"] != nil);
    NSUInteger groupCount = 0; BOOL usableGroup = NO, development = NO, signingReadable = NO;
#if TARGET_OS_IOS
    SecTaskRef task = SecTaskCreateFromSelf(kCFAllocatorDefault);
    if (task) {
        CFErrorRef error = NULL;
        id groups = CFBridgingRelease(SecTaskCopyValueForEntitlement(task, CFSTR("com.apple.security.application-groups"), &error));
        signingReadable = error == NULL;
        if (error) CFRelease(error);
        if ([groups isKindOfClass:NSArray.class]) {
            for (id group in groups) if ([group isKindOfClass:NSString.class]) {
                groupCount++;
                NSURL *url = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:group];
                if (url) {
                    int fd = WQOpenDirectoryNoLinks(url.path);
                    if (fd >= 0) { usableGroup = YES; close(fd); }
                }
            }
        }
        id debug = CFBridgingRelease(SecTaskCopyValueForEntitlement(task, CFSTR("get-task-allow"), NULL));
        development = [debug isKindOfClass:NSNumber.class] && [debug boolValue];
        CFRelease(task);
    }
#endif
    environment[@"AppGroupEntitlementCount"] = @(groupCount);
    environment[@"SigningEntitlementsReadable"] = @(signingReadable);
    environment[@"UsableAppGroup"] = @(usableGroup);
    environment[@"DevelopmentEntitlement"] = @(development);
    return environment;
}
@end
