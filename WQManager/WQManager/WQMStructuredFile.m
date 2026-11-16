#import "WQMStructuredFile.h"
#import "WQAccessSafety.h"
#import "WQMLanguageManager.h"
#import <sqlite3.h>

static const unsigned long long kWQMDatabaseLimit = 512ULL * 1024 * 1024;
static const NSUInteger kWQMPageSize = 100;
static NSError *WQMInspectError(NSInteger code)
{
    return [NSError errorWithDomain:@"WQMStructuredFile" code:code userInfo:@{NSLocalizedDescriptionKey:
        WQML(@"INSPECT_READ_ERROR", @"读取失败：文件可能损坏、正在变化或超过查看上限。请关闭来源 App 后重试。查看仅使用工作副本。") }];
}
static NSString *WQMQuoteIdentifier(NSString *value) { return [NSString stringWithFormat:@"\"%@\"", [value stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""]]; }
static BOOL WQMStableStat(const struct stat *a, const struct stat *b)
{
    return WQSameObject(a, b) && a->st_size == b->st_size &&
        a->st_mtimespec.tv_sec == b->st_mtimespec.tv_sec && a->st_mtimespec.tv_nsec == b->st_mtimespec.tv_nsec &&
        a->st_ctimespec.tv_sec == b->st_ctimespec.tv_sec && a->st_ctimespec.tv_nsec == b->st_ctimespec.tv_nsec;
}
static BOOL WQMCopySnapshotFile(int parent, NSString *name, NSString *destination, struct stat *before, BOOL *present, unsigned long long *budget)
{
    if (fstatat(parent, name.fileSystemRepresentation, before, AT_SYMLINK_NOFOLLOW) != 0) { *present = NO; return errno == ENOENT; }
    *present = YES;
    if (!S_ISREG(before->st_mode) || before->st_size < 0 || (unsigned long long)before->st_size > *budget) return NO;
    int input = WQOpenRegularAt(parent, name.fileSystemRepresentation, O_RDONLY, 0);
    if (input < 0) return NO;
    int output = open(destination.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
    BOOL ok = output >= 0;
    struct stat opened, after;
    if (fstat(input, &opened) != 0 || !WQMStableStat(before, &opened)) ok = NO;
    unsigned long long bytes = 0;
    uint8_t buffer[64 * 1024];
    while (ok) {
        ssize_t count = read(input, buffer, sizeof(buffer));
        if (count < 0 && errno == EINTR) continue;
        if (count < 0) { ok = NO; break; }
        if (!count) break;
        bytes += count;
        if (bytes > (unsigned long long)before->st_size || bytes > *budget) { ok = NO; break; }
        ssize_t offset = 0;
        while (offset < count) {
            ssize_t written = write(output, buffer + offset, count - offset);
            if (written < 0 && errno == EINTR) continue;
            if (written <= 0) { ok = NO; break; }
            offset += written;
        }
    }
    if (fstat(input, &after) != 0 || !WQMStableStat(before, &after) || bytes != (unsigned long long)before->st_size) ok = NO;
    close(input); if (output >= 0) close(output);
    if (ok) *budget -= bytes;
    return ok;
}
static NSString *WQMColumnText(sqlite3_stmt *statement, int column)
{
    int type = sqlite3_column_type(statement, column);
    if (type == SQLITE_NULL) return @"NULL";
    if (type == SQLITE_BLOB) return [NSString stringWithFormat:@"<BLOB: %d bytes>", sqlite3_column_bytes(statement, column)];
    const unsigned char *value = sqlite3_column_text(statement, column);
    int count = sqlite3_column_bytes(statement, column);
    NSData *data = [NSData dataWithBytes:value ?: (const unsigned char *)"" length:MIN(count, 4096)];
    NSString *text;
    for (NSUInteger tail = 0; tail <= (count > 4096 ? 3 : 0) && tail <= data.length; tail++) {
        text = [[NSString alloc] initWithBytes:data.bytes length:data.length - tail encoding:NSUTF8StringEncoding];
        if (text) break;
    }
    return [(text ?: @"<text>") stringByAppendingString:count > 4096 ? @"…" : @""];
}
static int WQMInspectProgress(void *context);
@implementation WQMStructuredFile {
    sqlite3 *_database;
    CFAbsoluteTime _deadline;
}
- (instancetype)initWithPath:(NSString *)path error:(NSError **)error
{
    if (!(self = [super init])) return nil;
    _tables = @[];
    _workspace = [NSTemporaryDirectory() stringByAppendingPathComponent:[@"WQMInspect-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    BOOL ok = [NSFileManager.defaultManager createDirectoryAtPath:_workspace withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:nil];
    int parent = WQOpenDirectoryNoLinks(path.stringByDeletingLastPathComponent);
    BOOL plist = [path.pathExtension.lowercaseString isEqual:@"plist"];
    unsigned long long budget = plist ? 8ULL * 1024 * 1024 : kWQMDatabaseLimit;
    NSArray *names = plist ? @[path.lastPathComponent] : @[path.lastPathComponent, [path.lastPathComponent stringByAppendingString:@"-wal"], [path.lastPathComponent stringByAppendingString:@"-journal"]];
    struct stat before[3] = {0}; BOOL present[3] = {NO};
    if (parent < 0) ok = NO;
    for (NSUInteger index = 0; ok && index < names.count; index++) {
        NSString *name = names[index];
        NSString *target = [_workspace stringByAppendingPathComponent:index == 0 ? @"content" : index == 1 ? @"content-wal" : @"content-journal"];
        ok = WQMCopySnapshotFile(parent, name, target, &before[index], &present[index], &budget);
        if (index == 0 && !present[index]) ok = NO;
        // A rollback journal needs a writable source recovery; never infer consistency.
        if (index == 2 && present[index] && before[index].st_size > 0) ok = NO;
    }
    for (NSUInteger index = 0; ok && index < names.count; index++) {
        struct stat after;
        int status = fstatat(parent, [names[index] fileSystemRepresentation], &after, AT_SYMLINK_NOFOLLOW);
        ok = present[index] ? status == 0 && WQMStableStat(&before[index], &after) : status != 0 && errno == ENOENT;
    }
    if (parent >= 0) close(parent);
    NSString *content = [_workspace stringByAppendingPathComponent:@"content"];
    if (ok && plist) {
        NSData *data = [NSData dataWithContentsOfFile:content options:0 error:nil];
        _propertyList = data ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:nil] : nil;
        ok = _propertyList != nil;
    } else if (ok) {
        // SQLite opens only the private copy, including copied WAL. It may rebuild
        // SHM/checkpoint here; source paths are never passed to SQLite.
        ok = sqlite3_open_v2(content.fileSystemRepresentation, &_database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX, NULL) == SQLITE_OK;
        if (ok) {
            _deadline = CFAbsoluteTimeGetCurrent() + 3;
            sqlite3_progress_handler(_database, 1000, WQMInspectProgress, (__bridge void *)self);
            sqlite3_busy_timeout(_database, 1000);
            sqlite3_limit(_database, SQLITE_LIMIT_LENGTH, 1024 * 1024);
            sqlite3_limit(_database, SQLITE_LIMIT_COLUMN, 128);
            sqlite3_limit(_database, SQLITE_LIMIT_SQL_LENGTH, 64 * 1024);
            sqlite3_db_config(_database, SQLITE_DBCONFIG_DEFENSIVE, 1, NULL);
            sqlite3_db_config(_database, SQLITE_DBCONFIG_TRUSTED_SCHEMA, 0, NULL);
            sqlite3_exec(_database, "PRAGMA query_only=ON; PRAGMA trusted_schema=OFF;", NULL, NULL, NULL);
            sqlite3_stmt *statement = NULL;
            ok = sqlite3_prepare_v2(_database, "SELECT name, sql FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name LIMIT 1001", -1, &statement, NULL) == SQLITE_OK;
            NSMutableArray *tables = [NSMutableArray new]; int status = SQLITE_DONE;
            if (ok) while ((status = sqlite3_step(statement)) == SQLITE_ROW) {
                NSString *name = WQMColumnText(statement, 0), *sql = WQMColumnText(statement, 1);
                // Virtual tables can invoke modules; expose only ordinary tables.
                if ([sql.uppercaseString containsString:@"VIRTUAL TABLE"]) continue;
                [tables addObject:@{@"Name":name, @"SQL":sql}];
                if (tables.count > 1000) { ok = NO; break; }
            }
            if (status != SQLITE_DONE) ok = NO;
            sqlite3_finalize(statement); _tables = tables;
        }
    }
    if (!ok) { if (error) *error = WQMInspectError(1); return nil; }
    return self;
}
- (BOOL)shouldInterrupt { return self.cancelled || CFAbsoluteTimeGetCurrent() > _deadline; }
- (void)dealloc
{
    if (_database) sqlite3_close(_database);
    if (_workspace) [NSFileManager.defaultManager removeItemAtPath:_workspace error:nil];
}
- (sqlite3_stmt *)statementForTable:(NSString *)table offset:(NSUInteger)offset limit:(NSUInteger)limit
{
    _deadline = CFAbsoluteTimeGetCurrent() + 3;
    BOOL known = NO;
    for (NSDictionary *entry in _tables) if ([entry[@"Name"] isEqual:table]) known = YES;
    if (!known || self.cancelled || offset > 10000000) return NULL;
    NSString *sql = [NSString stringWithFormat:@"SELECT * FROM %@ LIMIT %lu OFFSET %lu", WQMQuoteIdentifier(table), (unsigned long)limit, (unsigned long)offset];
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(_database, sql.UTF8String, -1, &statement, NULL) != SQLITE_OK) return NULL;
    return statement;
}
- (NSArray<NSDictionary *> *)rowsForTable:(NSString *)table offset:(NSUInteger)offset error:(NSError **)error
{
    sqlite3_stmt *statement = [self statementForTable:table offset:offset limit:kWQMPageSize];
    if (!statement) { if (error) *error = WQMInspectError(2); return nil; }
    NSMutableArray *rows = [NSMutableArray new]; int status = SQLITE_DONE; NSUInteger totalBytes = 0;
    while (!self.cancelled && (status = sqlite3_step(statement)) == SQLITE_ROW) {
        NSMutableArray *values = [NSMutableArray new], *columns = [NSMutableArray new];
        for (int index = 0; index < sqlite3_column_count(statement); index++) {
            [columns addObject:[NSString stringWithUTF8String:sqlite3_column_name(statement, index)] ?: @"?"];
            NSString *value = WQMColumnText(statement, index);
            totalBytes += [value lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
            if (totalBytes > 2 * 1024 * 1024) { sqlite3_finalize(statement); if (error) *error = WQMInspectError(3); return nil; }
            [values addObject:value];
        }
        [rows addObject:@{@"Columns":columns, @"Values":values}];
    }
    BOOL ok = !self.cancelled && status == SQLITE_DONE;
    sqlite3_finalize(statement);
    if (!ok) { if (error) *error = WQMInspectError(3); return nil; }
    return rows;
}
- (NSURL *)exportTable:(NSString *)table error:(NSError **)error
{
    sqlite3_stmt *statement = [self statementForTable:table offset:0 limit:10001];
    _deadline = CFAbsoluteTimeGetCurrent() + 10;
    NSString *path = [_workspace stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"csv"]];
    NSFileHandle *handle;
    BOOL ok = statement != NULL;
    if (ok) { [NSFileManager.defaultManager createFileAtPath:path contents:nil attributes:nil]; handle = [NSFileHandle fileHandleForWritingAtPath:path]; ok = handle != nil; }
    NSUInteger bytes = 0, rows = 0;
    // Export follows the same display bounds: BLOB summaries, text <=4KB.
    int status = SQLITE_DONE;
    @try {
        BOOL header = YES;
        while (ok && !self.cancelled) {
            if (!header) { status = sqlite3_step(statement); if (status != SQLITE_ROW) break; if (++rows > 10000) { ok = NO; break; } }
            @autoreleasepool {
                NSMutableArray *fields = [NSMutableArray new];
                for (int index = 0; index < sqlite3_column_count(statement); index++) {
                    NSString *value = header ? [NSString stringWithUTF8String:sqlite3_column_name(statement, index)] : WQMColumnText(statement, index);
                    // Keep CSV text inert when opened by spreadsheet applications.
                    if (value.length && [@"=+-@\t\r" rangeOfString:[value substringToIndex:1]].location != NSNotFound) value = [@"'" stringByAppendingString:value];
                    [fields addObject:[NSString stringWithFormat:@"\"%@\"", [value stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""]]];
                }
                NSData *data = [[[fields componentsJoinedByString:@","] stringByAppendingString:@"\r\n"] dataUsingEncoding:NSUTF8StringEncoding];
                bytes += data.length; if (bytes > 16 * 1024 * 1024) { ok = NO; break; }
                [handle writeData:data]; header = NO;
            }
        }
    } @catch (__unused NSException *exception) { ok = NO; }
    [handle closeFile]; sqlite3_finalize(statement);
    ok = ok && !self.cancelled && status == SQLITE_DONE;
    if (!ok) { [NSFileManager.defaultManager removeItemAtPath:path error:nil]; if (error) *error = WQMInspectError(4); return nil; }
    return [NSURL fileURLWithPath:path];
}
@end

static int WQMInspectProgress(void *context) { return [(__bridge WQMStructuredFile *)context shouldInterrupt] ? 1 : 0; }
