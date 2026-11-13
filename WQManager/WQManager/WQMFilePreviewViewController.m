//
//  WQMFilePreviewViewController.m
//  WQManager
//

#import "WQMFilePreviewViewController.h"
#import "WQMFilePreviewModel.h"
#import "WQMLanguageManager.h"
#import "WQMTheme.h"
#import <AVKit/AVKit.h>

static const NSUInteger kWQMPreviewTextBytes = 2 * 1024 * 1024;
static const NSUInteger kWQMPreviewHexBytes = 4096;

@interface WQMFilePreviewViewController () <UIScrollViewDelegate>

@property (nonatomic, copy) NSString *filePath;
@property (nonatomic, copy) NSString *displayName;

@end

@implementation WQMFilePreviewViewController

- (instancetype)initWithFilePath:(NSString *)path name:(NSString *)name
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _filePath = [path copy];
        _displayName = name.length ? [name copy] : path.lastPathComponent;
        self.title = _displayName;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = WQMTheme.canvasColor;

    UIBarButtonItem *share = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"square.and.arrow.up"]
                                                             style:UIBarButtonItemStylePlain
                                                            target:self
                                                            action:@selector(share:)];
    share.accessibilityLabel = WQML(@"LENS_SHARE", @"分享");
    self.navigationItem.rightBarButtonItem = share;

    if (![[NSFileManager defaultManager] isReadableFileAtPath:self.filePath]) {
        [self showMessage:WQML(@"PREVIEW_UNREADABLE", @"无法读取这个文件") symbol:@"exclamationmark.triangle"];
        return;
    }

    WQMFilePreviewKind kind = [WQMFilePreviewModel kindForPath:self.filePath];
    switch (kind) {
        case WQMFilePreviewKindImage:
            [self loadImage];
            break;
        case WQMFilePreviewKindVideo:
        case WQMFilePreviewKindAudio:
            [self loadMedia];
            break;
        case WQMFilePreviewKindText:
            [self loadText];
            break;
        case WQMFilePreviewKindUnknown:
        default:
            [self loadHex];
            break;
    }
}

#pragma mark - Sharing

- (void)share:(__unused UIBarButtonItem *)sender
{
    UIActivityViewController *share = [[UIActivityViewController alloc]
                                       initWithActivityItems:@[[NSURL fileURLWithPath:self.filePath]]
                                       applicationActivities:nil];
    share.popoverPresentationController.barButtonItem = sender;
    [self presentViewController:share animated:YES completion:nil];
}

#pragma mark - Image

- (void)loadImage
{
    UIImage *image = [UIImage imageWithContentsOfFile:self.filePath];
    if (!image) {
        [self showMessage:WQML(@"PREVIEW_UNREADABLE", @"无法读取这个文件") symbol:@"photo"];
        return;
    }

    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.delegate = self;
    scroll.minimumZoomScale = 1.0;
    scroll.maximumZoomScale = 6.0;
    scroll.showsHorizontalScrollIndicator = NO;
    scroll.showsVerticalScrollIndicator = NO;

    UIImageView *imageView = [[UIImageView alloc] initWithImage:image];
    imageView.translatesAutoresizingMaskIntoConstraints = NO;
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    imageView.userInteractionEnabled = YES;

    [scroll addSubview:imageView];
    [self.view addSubview:scroll];

    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                               action:@selector(zoomTapped:)];
    doubleTap.numberOfTapsRequired = 2;
    [imageView addGestureRecognizer:doubleTap];

    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [imageView.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [imageView.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [imageView.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [imageView.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [imageView.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor],
        [imageView.heightAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.heightAnchor],
    ]];
}

- (void)zoomTapped:(UITapGestureRecognizer *)gesture
{
    UIScrollView *scroll = (UIScrollView *)gesture.view.superview;
    if (![scroll isKindOfClass:UIScrollView.class]) return;
    if (scroll.zoomScale > 1.05) {
        [scroll setZoomScale:1.0 animated:YES];
    } else {
        CGPoint point = [gesture locationInView:gesture.view];
        [scroll zoomToRect:CGRectMake(point.x - 40, point.y - 40, 80, 80) animated:YES];
    }
}

- (UIView *)viewForZoomingInScrollView:(__unused UIScrollView *)scrollView
{
    return scrollView.subviews.firstObject;
}

#pragma mark - Text

- (void)loadText
{
    NSData *head = [WQMFilePreviewModel headOfFile:self.filePath maxBytes:kWQMPreviewTextBytes];
    if (!head.length) {
        [self showMessage:WQML(@"PREVIEW_EMPTY", @"文件是空的") symbol:@"doc"];
        return;
    }

    BOOL truncated = NO;
    NSString *text = nil;
    if ([WQMFilePreviewModel isJSONPath:self.filePath]) {
        text = [WQMFilePreviewModel prettyJSONForData:head maxBytes:kWQMPreviewTextBytes];
    }
    if (!text.length) {
        text = [WQMFilePreviewModel textForData:head maxBytes:kWQMPreviewTextBytes truncated:&truncated];
    }

    UITextView *textView = [self makeTextView];
    textView.text = text ?: @"";
    [self.view addSubview:textView];
    [self pinTextView:textView];

    if (truncated) {
        UILabel *footer = [self makeFooter];
        footer.text = [NSString stringWithFormat:WQML(@"PREVIEW_TRUNCATED", @"只显示前 %@，完整内容请分享查看"),
                       WQMFormatBytes(kWQMPreviewTextBytes)];
        [self.view addSubview:footer];
        [NSLayoutConstraint activateConstraints:@[
            [footer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
            [footer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
            [footer.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-10],
            [textView.bottomAnchor constraintEqualToAnchor:footer.topAnchor constant:-6],
        ]];
    }
}

#pragma mark - Hex

- (void)loadHex
{
    NSData *head = [WQMFilePreviewModel headOfFile:self.filePath maxBytes:kWQMPreviewHexBytes];
    if (!head.length) {
        [self showMessage:WQML(@"PREVIEW_EMPTY", @"文件是空的") symbol:@"doc"];
        return;
    }

    UITextView *textView = [self makeTextView];
    textView.text = [WQMFilePreviewModel hexDumpForData:head maxBytes:kWQMPreviewHexBytes];
    [self.view addSubview:textView];
    [self pinTextView:textView];

    UILabel *footer = [self makeFooter];
    footer.text = WQML(@"PREVIEW_HEX_NOTE", @"二进制文件，只显示开头 4 KB");
    [self.view addSubview:footer];
    [NSLayoutConstraint activateConstraints:@[
        [footer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [footer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [footer.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-10],
        [textView.bottomAnchor constraintEqualToAnchor:footer.topAnchor constant:-6],
    ]];
}

#pragma mark - Media

- (void)loadMedia
{
    AVPlayerViewController *player = [AVPlayerViewController new];
    player.player = [AVPlayer playerWithURL:[NSURL fileURLWithPath:self.filePath]];
    [self addChildViewController:player];
    player.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:player.view];
    [NSLayoutConstraint activateConstraints:@[
        [player.view.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [player.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [player.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [player.view.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
    ]];
    [player didMoveToParentViewController:self];
    [player.player play];
}

#pragma mark - Helpers

- (UITextView *)makeTextView
{
    UITextView *textView = [UITextView new];
    textView.translatesAutoresizingMaskIntoConstraints = NO;
    textView.editable = NO;
    textView.selectable = YES;
    textView.backgroundColor = WQMTheme.canvasColor;
    textView.textColor = WQMTheme.textPrimaryColor;
    textView.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    textView.textContainerInset = UIEdgeInsetsMake(16, 16, 16, 16);
    textView.alwaysBounceVertical = YES;
    textView.accessibilityIdentifier = @"preview.text";
    return textView;
}

- (void)pinTextView:(UITextView *)textView
{
    [NSLayoutConstraint activateConstraints:@[
        [textView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [textView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [textView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [textView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
    ]];
}

- (UILabel *)makeFooter
{
    UILabel *footer = [UILabel new];
    footer.translatesAutoresizingMaskIntoConstraints = NO;
    footer.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
    footer.textColor = WQMTheme.textSecondaryColor;
    footer.textAlignment = NSTextAlignmentCenter;
    footer.numberOfLines = 2;
    return footer;
}

- (void)showMessage:(NSString *)message symbol:(NSString *)symbol
{
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = WQMTheme.textSecondaryColor;
    icon.contentMode = UIViewContentModeScaleAspectFit;

    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = message;
    label.textColor = WQMTheme.textSecondaryColor;
    label.font = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;

    [self.view addSubview:icon];
    [self.view addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [icon.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [icon.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-24],
        [icon.widthAnchor constraintEqualToConstant:36],
        [icon.heightAnchor constraintEqualToConstant:36],
        [label.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:12],
        [label.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:32],
        [label.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-32],
    ]];
}

@end
