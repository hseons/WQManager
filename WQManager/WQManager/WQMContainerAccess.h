#import "WQMAppModel.h"
#import "WQAccess.h"
#import "WQAccessSafety.h"

/// Used by the read-only directory tools. The returned descriptor is owned by
/// the caller. Cached UI paths never substitute for a current identity check.
static inline int WQMOpenAppContainer(WQMAppModel *app)
{
    if (!app.accessAvailable || !app.identityKnown || !app.bundleIdentifier.length) return -1;
    BOOL fixture = NO;
#if DEBUG
    fixture = [NSProcessInfo.processInfo.environment[@"WQM_UI_FIXTURES"] boolValue] &&
        [app.bundleIdentifier isEqual:@"com.tencent.xin"] &&
        [app.containerPath isEqual:[NSTemporaryDirectory() stringByAppendingPathComponent:@"WQMContainerFixture"]];
#endif
    if (!fixture && !wq_grant(app.containerPath)) return -1;
    int fd = WQOpenDirectoryNoLinks(app.containerPath);
    struct stat st;
    if (fd < 0) return -1;
    if (fstat(fd, &st) != 0 || st.st_dev != app.containerDevice || st.st_ino != app.containerInode ||
        (!fixture && ![wq_container_label(app.containerPath) isEqual:app.bundleIdentifier])) {
        close(fd); return -1;
    }
    return fd;
}
