#import <XCTest/XCTest.h>
@interface WQMUITests : XCTestCase
@end
@implementation WQMUITests
- (XCUIApplication *)launchFeature:(NSString *)feature language:(NSString *)language
{
    self.continueAfterFailure = NO;
    XCUIApplication *app = [[XCUIApplication alloc] initWithBundleIdentifier:@"mumu.pduola.WQManager"];
    app.launchEnvironment = @{@"WQM_UI_FIXTURES":@"1", @"WQM_UI_FEATURE":feature,
        @"WQM_UI_APPEARANCE":[language isEqual:@"en"] ? @"dark" : @"light", @"WQM_ICON_REMOTE":@"0"};
    app.launchArguments = @[@"-WQMAcceptedDisclaimerVersion", @"2026-11-10-v1", @"-WQManagerLanguage", language];
    [app launch]; return app;
}
- (void)attachScreenshot:(XCUIApplication *)app name:(NSString *)name
{
    XCTAttachment *attachment = [XCTAttachment attachmentWithScreenshot:app.screenshot]; attachment.name = name; attachment.lifetime = XCTAttachmentLifetimeKeepAlways; [self addAttachment:attachment];
}
- (void)testSQLiteCopyPagingAndExport
{
    XCUIApplication *app = [self launchFeature:@"sqlite" language:@"zh-Hans"];
    XCUIElement *open = app.staticTexts[@"制作只读工作副本"];
    XCTAssertTrue([open waitForExistenceWithTimeout:15]); [open tap];
    [app.alerts.buttons[@"继续"] tap];
    XCUIElement *table = app.staticTexts[@"messages"];
    XCTAssertTrue([table waitForExistenceWithTimeout:15]); [table tap];
    XCTAssertTrue([app.staticTexts[@"第 1 行"] waitForExistenceWithTimeout:10]);
    [self attachScreenshot:app name:@"sqlite-first-page-zh"];
    [app.staticTexts[@"下一页"] tap];
    XCTAssertTrue([app.staticTexts[@"第 101 行"] waitForExistenceWithTimeout:10]);
    [app.staticTexts[@"上一页"] tap];
    XCTAssertTrue([app.staticTexts[@"第 1 行"] waitForExistenceWithTimeout:10]);
    [app.staticTexts[@"导出此表 CSV"] tap];
    XCTAssertTrue([app.otherElements[@"ActivityListView"] waitForExistenceWithTimeout:10]);
    [self attachScreenshot:app name:@"sqlite-export-sheet-zh"];
    [app terminate];
}
- (void)testBinaryPlistTreeInEnglish
{
    XCUIApplication *app = [self launchFeature:@"plist" language:@"en"];
    XCUIElement *open = app.staticTexts[@"Make read-only working copy"];
    XCTAssertTrue([open waitForExistenceWithTimeout:15]); [open tap]; [app.alerts.buttons[@"Continue"] tap];
    XCUIElement *nested = app.staticTexts[@"nested"];
    XCTAssertTrue([nested waitForExistenceWithTimeout:10]); [nested tap];
    XCTAssertTrue([app.staticTexts[@"theme"] waitForExistenceWithTimeout:10]);
    [self attachScreenshot:app name:@"plist-tree-en-dark"];
    [app terminate];
}
- (void)testLargeImagePreview
{
    XCUIApplication *app = [self launchFeature:@"image" language:@"en"];
    XCTAssertTrue([app.images[@"preview.image"] waitForExistenceWithTimeout:15]);
    [self attachScreenshot:app name:@"large-image-preview"];
    [app terminate];
}
- (void)testTruncatedTextLayout
{
    XCUIApplication *app = [self launchFeature:@"text" language:@"zh-Hans"];
    XCTAssertTrue([app.textViews[@"preview.text"] waitForExistenceWithTimeout:15]);
    XCUIElement *footer = [app.staticTexts matchingPredicate:[NSPredicate predicateWithFormat:@"label CONTAINS %@", @"只显示前"]].firstMatch;
    XCTAssertTrue([footer waitForExistenceWithTimeout:10]);
    XCTAssertLessThanOrEqual(app.textViews[@"preview.text"].frame.origin.y + app.textViews[@"preview.text"].frame.size.height, footer.frame.origin.y + 1);
    [self attachScreenshot:app name:@"truncated-text-layout"];
    [app terminate];
}
- (void)testFileSearchAndDirectDiagnostics
{
    XCUIApplication *app = [self launchFeature:@"files" language:@"en"];
    XCTAssertTrue([app.tables[@"files.table"] waitForExistenceWithTimeout:15]);
    XCUIElement *search = app.searchFields.firstMatch;
    [search tap]; [search typeText:@"inspection.sqlite"];
    XCTAssertTrue([app.staticTexts[@"inspection.sqlite"] waitForExistenceWithTimeout:10]);
    [app terminate];
    app = [self launchFeature:@"diagnostics" language:@"en"];
    XCTAssertTrue([app.staticTexts[@"Access capabilities"] waitForExistenceWithTimeout:15]);
    [self attachScreenshot:app name:@"direct-app-diagnostics"];
    [app terminate];
}
- (void)testAppActionPanelExpandsMoreTools
{
    XCUIApplication *app = [[XCUIApplication alloc] initWithBundleIdentifier:@"mumu.pduola.WQManager"];
    app.launchEnvironment = @{@"WQM_UI_FIXTURES":@"1", @"WQM_UI_ACTION_PANEL":@"1",
        @"WQM_UI_APPEARANCE":@"light", @"WQM_ICON_REMOTE":@"0"};
    app.launchArguments = @[@"-WQMAcceptedDisclaimerVersion", @"2026-11-10-v1", @"-WQManagerLanguage", @"zh-Hans"];
    [app launch];

    XCUIElement *more = app.buttons[@"app.action.more"];
    XCTAssertTrue([more waitForExistenceWithTimeout:15]);
    XCTNSPredicateExpectation *hittable = [[XCTNSPredicateExpectation alloc] initWithPredicate:
        [NSPredicate predicateWithFormat:@"hittable == YES"] object:more];
    XCTAssertEqual([XCTWaiter waitForExpectations:@[hittable] timeout:15], XCTWaiterResultCompleted);
    [self attachScreenshot:app name:@"app-actions-more-button-zh"];

    XCUIElement *custom = app.buttons[@"app.action.customBackup"];
    XCTAssertFalse(custom.hittable);
    [more tap];

    XCTNSPredicateExpectation *expanded = [[XCTNSPredicateExpectation alloc] initWithPredicate:
        [NSPredicate predicateWithFormat:@"hittable == YES"] object:custom];
    XCTAssertEqual([XCTWaiter waitForExpectations:@[expanded] timeout:10], XCTWaiterResultCompleted);
    [self attachScreenshot:app name:@"app-actions-more-tools-zh"];
    [app terminate];
}
- (void)testExportCenterFiltersAndSelection
{
    XCUIApplication *app = [self launchFeature:@"export" language:@"zh-Hans"];
    XCTAssertTrue([app.tables[@"export.table"] waitForExistenceWithTimeout:15]);
    XCUIElement *categories = app.segmentedControls[@"export.categories"];
    XCTAssertTrue([categories waitForExistenceWithTimeout:10]);
    [categories.buttons[@"图片"] tap];
    XCUIElement *file = app.cells[@"export.file.0"];
    XCTAssertTrue([file waitForExistenceWithTimeout:10]);
    [file tap];
    XCTAssertTrue(app.buttons[@"export.action"].enabled);
    XCUIElement *selection = [[app.staticTexts matchingPredicate:
        [NSPredicate predicateWithFormat:@"label CONTAINS %@", @"已选 1 项"]] firstMatch];
    XCTAssertTrue(selection.exists);
    [self attachScreenshot:app name:@"export-center-images-zh"];
    [app.buttons[@"export.action"] tap];
    XCUIElement *share = app.buttons[@"分享…"];
    if (!share.exists) {
        share = [[app.buttons matchingPredicate:[NSPredicate predicateWithFormat:@"label BEGINSWITH %@", @"分享"]] firstMatch];
    }
    XCTAssertTrue([share waitForExistenceWithTimeout:15]);
    [self attachScreenshot:app name:@"export-center-choice-zh"];
    [share tap];
    XCTAssertTrue([app.otherElements[@"ActivityListView"] waitForExistenceWithTimeout:15]);
    [app terminate];
}
- (void)testGlobalFileSearch
{
    XCUIApplication *app = [self launchFeature:@"search" language:@"zh-Hans"];
    XCTAssertTrue([app.tables[@"global-search.table"] waitForExistenceWithTimeout:15]);
    XCUIElement *search = app.searchFields[@"global-search.field"];
    if (!search.exists) search = app.textFields[@"global-search.field"];
    XCTAssertTrue([search waitForExistenceWithTimeout:10]);
    [search tap];
    [search typeText:@"duplicate\n"];
    XCUIElement *file = app.cells[@"global-search.file.0"];
    XCTAssertTrue([file waitForExistenceWithTimeout:15]);
    [self attachScreenshot:app name:@"global-file-search-zh"];
    [file tap];
    XCTAssertTrue([app.buttons[@"预览"] waitForExistenceWithTimeout:5]);
    XCUIElement *close = app.buttons[@"关闭"];
    if (!close.exists) close = app.buttons[@"取消"];
    XCTAssertTrue([close waitForExistenceWithTimeout:5]);
    [close tap];
    [app terminate];
}

- (void)testLargeDuplicateAuditVerification
{
    XCUIApplication *app = [self launchFeature:@"audit" language:@"zh-Hans"];
    XCTAssertTrue([app.tables[@"file-audit.table"] waitForExistenceWithTimeout:15]);
    [self attachScreenshot:app name:@"file-audit-large-zh"];
    XCUIElement *modes = app.segmentedControls[@"file-audit.modes"];
    XCTAssertTrue([modes waitForExistenceWithTimeout:10]);
    [modes.buttons[@"重复文件"] tap];
    [self attachScreenshot:app name:@"file-audit-duplicates-zh"];
    XCUIElement *group = app.cells[@"audit.duplicate.0"];
    XCTAssertTrue([group waitForExistenceWithTimeout:10]);
    [group tap];
    XCTAssertTrue([app.tables[@"duplicate.table"] waitForExistenceWithTimeout:15]);
    XCUIElement *duplicate = app.cells[@"duplicate.file.0.0"];
    XCTAssertTrue([duplicate waitForExistenceWithTimeout:15]);
    [duplicate tap];
    XCTAssertTrue(app.buttons[@"duplicate.trash"].enabled);
    [self attachScreenshot:app name:@"duplicate-verification-zh"];
    [app.buttons[@"duplicate.trash"] tap];
    XCTAssertTrue([app.alerts.buttons[@"取消"] waitForExistenceWithTimeout:5]);
    [app.alerts.buttons[@"取消"] tap];
    [app terminate];
}

@end
