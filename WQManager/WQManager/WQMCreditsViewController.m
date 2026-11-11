#import "WQMCreditsViewController.h"
#import "WQMLanguageManager.h"
#import "WQMMarkdownRenderer.h"
#import "WQMTheme.h"

@interface WQMCredit : NSObject

@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *project;
@property (nonatomic, copy) NSString *role;
@property (nonatomic, copy) NSString *urlString;
@property (nonatomic, copy) NSString *avatarName;

@end

@implementation WQMCredit
@end

@interface WQMCreditCell : UITableViewCell

@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *projectLabel;
@property (nonatomic, strong) UILabel *roleLabel;

- (void)configureWithCredit:(WQMCredit *)credit;

@end

@implementation WQMCreditCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (!self) return nil;

    self.selectionStyle = UITableViewCellSelectionStyleDefault;
    self.backgroundColor = WQMTheme.surfaceColor;

    _avatarView = [UIImageView new];
    _avatarView.translatesAutoresizingMaskIntoConstraints = NO;
    _avatarView.contentMode = UIViewContentModeScaleAspectFill;
    _avatarView.clipsToBounds = YES;
    _avatarView.layer.cornerRadius = 22;
    _avatarView.layer.cornerCurve = kCACornerCurveContinuous;
    _avatarView.backgroundColor = WQMTheme.raisedSurfaceColor;
    [self.contentView addSubview:_avatarView];

    _nameLabel = [UILabel new];
    _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _nameLabel.textColor = WQMTheme.textPrimaryColor;
    _nameLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    [self.contentView addSubview:_nameLabel];

    _projectLabel = [UILabel new];
    _projectLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _projectLabel.textColor = WQMTheme.textSecondaryColor;
    _projectLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    [self.contentView addSubview:_projectLabel];

    _roleLabel = [UILabel new];
    _roleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _roleLabel.textColor = WQMTheme.textSecondaryColor;
    _roleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    _roleLabel.numberOfLines = 0;
    [self.contentView addSubview:_roleLabel];

    UILayoutGuide *guide = self.contentView.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_avatarView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
        [_avatarView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_avatarView.widthAnchor constraintEqualToConstant:44],
        [_avatarView.heightAnchor constraintEqualToConstant:44],
        [_avatarView.topAnchor constraintGreaterThanOrEqualToAnchor:guide.topAnchor constant:4],
        [_avatarView.bottomAnchor constraintLessThanOrEqualToAnchor:guide.bottomAnchor constant:-4],

        [_nameLabel.topAnchor constraintEqualToAnchor:guide.topAnchor constant:4],
        [_nameLabel.leadingAnchor constraintEqualToAnchor:_avatarView.trailingAnchor constant:12],
        [_nameLabel.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],

        [_projectLabel.topAnchor constraintEqualToAnchor:_nameLabel.bottomAnchor constant:1],
        [_projectLabel.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],
        [_projectLabel.trailingAnchor constraintEqualToAnchor:_nameLabel.trailingAnchor],

        [_roleLabel.topAnchor constraintEqualToAnchor:_projectLabel.bottomAnchor constant:2],
        [_roleLabel.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],
        [_roleLabel.trailingAnchor constraintEqualToAnchor:_nameLabel.trailingAnchor],
        [_roleLabel.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor constant:-4],
    ]];
    return self;
}

- (void)configureWithCredit:(WQMCredit *)credit
{
    self.avatarView.image = [UIImage imageNamed:credit.avatarName];
    self.nameLabel.text = credit.name;
    self.projectLabel.text = credit.project;
    self.roleLabel.text = credit.role;
}

@end

@interface WQMCreditsDocumentViewController : UIViewController

@property (nonatomic, copy) NSString *documentTitle;
@property (nonatomic, copy) NSString *documentText;

@end

@implementation WQMCreditsDocumentViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = self.documentTitle;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor = WQMTheme.canvasColor;

    UITextView *textView = [UITextView new];
    textView.editable = NO;
    textView.selectable = YES;
    textView.backgroundColor = WQMTheme.surfaceColor;
    textView.textColor = WQMTheme.textPrimaryColor;
    textView.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    textView.dataDetectorTypes = UIDataDetectorTypeLink;
    textView.attributedText = [WQMMarkdownRenderer attributedStringFromMarkdown:self.documentText];
    textView.textContainerInset = UIEdgeInsetsMake(18, 16, 22, 16);
    textView.layer.cornerRadius = WQMTheme.mediumRadius;
    textView.layer.cornerCurve = kCACornerCurveContinuous;
    textView.layer.borderWidth = 1;
    textView.layer.borderColor = WQMTheme.separatorColor.CGColor;
    textView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:textView];
    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [textView.topAnchor constraintEqualToAnchor:guide.topAnchor constant:16],
        [textView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:16],
        [textView.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-16],
        [textView.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor constant:-16],
    ]];
}

@end

@interface WQMCreditsViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray<NSArray<WQMCredit *> *> *sections;

@end

@implementation WQMCreditsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = WQML(@"THIRD_PARTY", @"第三方项目致谢");
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor = WQMTheme.canvasColor;

    WQMCredit *wqfiles = [WQMCredit new];
    wqfiles.name = @"kolbicz";
    wqfiles.project = @"WQFiles · GPL-3.0-or-later";
    wqfiles.role = WQML(@"CREDITS_ROLE_WQFILES", @"容器访问、容器枚举、Launch Services 显示名称查询与安全检查");
    wqfiles.urlString = @"https://github.com/kolbicz/WQFiles";
    wqfiles.avatarName = @"AvatarKolbicz";

    WQMCredit *worseQuery = [WQMCredit new];
    worseQuery.name = @"Taj C (forcequit)";
    worseQuery.project = @"worse_query · GPL-3.0-or-later";
    worseQuery.role = WQML(@"CREDITS_ROLE_WORSE_QUERY", @"沙盒扩展技术，WQManager 容器访问层的基础");
    worseQuery.urlString = @"https://github.com/forcequitOS/worse_query";
    worseQuery.avatarName = @"AvatarForcequitOS";

    WQMCredit *kamui = [WQMCredit new];
    kamui.name = @"murk-sus";
    kamui.project = @"KAMUI";
    kamui.role = WQML(@"CREDITS_ROLE_KAMUI", @"使用 fsgetpath 枚举容器的实现参考");
    kamui.urlString = @"https://github.com/murk-sus/kamui-escape";
    kamui.avatarName = @"AvatarMurkSus";

    WQMCredit *gestaltx = [WQMCredit new];
    gestaltx.name = @"huamidev";
    gestaltx.project = @"GestaltX · GPL-3.0";
    gestaltx.role = WQML(@"CREDITS_ROLE_GESTALTX", @"关于页、许可展示与双语文档的参考");
    gestaltx.urlString = @"https://github.com/huamidev/GestaltX";
    gestaltx.avatarName = @"AvatarHuamidev";

    self.sections = @[@[wqfiles, worseQuery], @[kamui, gestaltx]];

    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.backgroundColor = WQMTheme.canvasColor;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.cellLayoutMarginsFollowReadableWidth = YES;
    _tableView.rowHeight = UITableViewAutomaticDimension;
    _tableView.estimatedRowHeight = 84;
    [_tableView registerClass:[WQMCreditCell class] forCellReuseIdentifier:@"credit"];
    [_tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"doc"];
    [self.view addSubview:_tableView];

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:guide.topAnchor],
        [_tableView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor],
    ]];

    UILabel *intro = [UILabel new];
    intro.numberOfLines = 0;
    intro.textColor = WQMTheme.textSecondaryColor;
    intro.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    intro.text = WQML(@"CREDITS_INTRO",
                      @"WQManager 的容器访问层改编自以下开源项目。轻点项目卡片可打开项目主页。");
    CGFloat width = MAX(CGRectGetWidth(self.view.bounds) - 48, 0);
    CGSize fit = [intro sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)];
    intro.frame = CGRectMake(0, 0, width, fit.height + 24);
    intro.textAlignment = NSTextAlignmentCenter;
    _tableView.tableHeaderView = intro;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section < self.sections.count) return (NSInteger)self.sections[(NSUInteger)section].count;
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (section == 0) return WQML(@"CREDITS_GPL_SECTION", @"包含或改编的 GPL 代码");
    if (section == 1) return WQML(@"CREDITS_REFERENCE_SECTION", @"设计与流程参考");
    return WQML(@"CREDITS_DOCS_SECTION", @"完整文本");
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (section != 2) return nil;
    return WQML(@"CREDITS_FOOTER",
                @"各项目保留其版权与许可证。列出名称不代表其为本项目背书，也不代表双方存在隶属关系。Apple、iOS 是 Apple Inc. 的商标。");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section < self.sections.count) {
        WQMCreditCell *cell = [tableView dequeueReusableCellWithIdentifier:@"credit" forIndexPath:indexPath];
        [cell configureWithCredit:self.sections[(NSUInteger)indexPath.section][(NSUInteger)indexPath.row]];
        return cell;
    }
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"doc" forIndexPath:indexPath];
    UIListContentConfiguration *content = cell.defaultContentConfiguration;
    content.text = WQML(@"CREDITS_FULL_TEXT", @"查看完整第三方许可文本");
    content.image = [UIImage systemImageNamed:@"doc.text"];
    content.imageProperties.tintColor = WQMTheme.textPrimaryColor;
    content.textProperties.color = WQMTheme.textPrimaryColor;
    cell.contentConfiguration = content;
    cell.backgroundColor = WQMTheme.surfaceColor;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section < self.sections.count) {
        WQMCredit *credit = self.sections[(NSUInteger)indexPath.section][(NSUInteger)indexPath.row];
        NSURL *url = [NSURL URLWithString:credit.urlString];
        if (url) [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
        return;
    }

    BOOL english = [[WQMLanguageManager sharedManager].languageCode isEqualToString:[WQMLanguageManager english]];
    NSString *resource = @"THIRD_PARTY_NOTICES";
    if (!english) resource = [resource stringByAppendingString:@"_zh-Hans"];
    NSString *path = [NSBundle.mainBundle pathForResource:resource ofType:@"md"];
    NSString *text = path ? [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] : nil;
    if (!text.length) text = WQML(@"DOC_NOT_FOUND", @"文档资源未找到。");

    WQMCreditsDocumentViewController *controller = [WQMCreditsDocumentViewController new];
    controller.documentTitle = WQML(@"THIRD_PARTY", @"第三方项目致谢");
    controller.documentText = text;
    [self.navigationController pushViewController:controller animated:YES];
}

@end
