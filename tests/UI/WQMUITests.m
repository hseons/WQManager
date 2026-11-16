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
@end
