//
//  WQMFilePreviewViewController.m
//  WQManager
//

#import "WQMFilePreviewViewController.h"
#import <ImageIO/ImageIO.h>
#import "WQMStructuredViewController.h"
#import "WQMFilePreviewModel.h"
#import "WQMLanguageManager.h"
#import "WQMTheme.h"
#import <AVKit/AVKit.h>

static const NSUInteger kWQMPreviewTextBytes = 64 * 1024;
static const NSUInteger kWQMPreviewHexBytes = 4096;

@interface WQMFilePreviewViewController () <UIScrollViewDelegate>

@property (nonatomic, copy) NSString *filePath;
@property (nonatomic, copy) NSString *displayName;

@end

@implementation WQMFilePreviewViewController {
    NSUInteger _previewGeneration;
}

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

    NSString *extension = self.filePath.pathExtension.lowercaseString;
    if ([@[@"plist", @"db", @"sqlite", @"sqlite3"] containsObject:extension]) {
        WQMStructuredViewController *inspector = [[WQMStructuredViewController alloc] initWithPath:self.filePath];
        [self addChildViewController:inspector];
        inspector.view.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:inspector.view];
        [NSLayoutConstraint activateConstraints:@[
            [inspector.view.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
            [inspector.view.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
            [inspector.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
            [inspector.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        ]];
        [inspector didMoveToParentViewController:self];
        self.navigationItem.rightBarButtonItem = nil;
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

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    if (self.isMovingFromParentViewController) _previewGeneration++;
}
- (void)loadHeadWithLimit:(NSUInteger)limit completion:(void (^)(NSData *))completion
{
    NSUInteger generation = ++_previewGeneration;
    NSString *path = self.filePath;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSData *head = [WQMFilePreviewModel headOfFile:path maxBytes:limit];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (self && generation == self->_previewGeneration) completion(head);
        });
    });
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
    NSUInteger generation = ++_previewGeneration;
    NSString *path = self.filePath;
    CGFloat pixels = MIN(4096, MAX(self.view.bounds.size.width, self.view.bounds.size.height) * self.traitCollection.displayScale * 2);
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], (__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImageSourceShouldCache: @NO});
        CGImageRef thumbnail = source ? CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)@{
            (__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
            (__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES,
            (__bridge NSString *)kCGImageSourceShouldCacheImmediately: @YES,
            (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize: @(MAX(1, pixels))}) : NULL;
        UIImage *image = thumbnail ? [UIImage imageWithCGImage:thumbnail] : nil;
        if (thumbnail) CGImageRelease(thumbnail);
        if (source) CFRelease(source);
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (self && generation == self->_previewGeneration) [self displayImage:image];
        });
    });
}
- (void)displayImage:(UIImage *)image
{
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
    imageView.accessibilityIdentifier = @"preview.image";
    imageView.isAccessibilityElement = YES;
    imageView.accessibilityLabel = self.displayName;
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
    NSUInteger generation = ++_previewGeneration;
    NSString *path = self.filePath;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSData *head = [WQMFilePreviewModel headOfFile:path maxBytes:kWQMPreviewTextBytes + 1];
        BOOL truncated = head.length > kWQMPreviewTextBytes;
        NSData *bounded = truncated ? [head subdataWithRange:NSMakeRange(0, kWQMPreviewTextBytes)] : head;
        NSString *pretty = !truncated && [WQMFilePreviewModel isJSONPath:path] ? [WQMFilePreviewModel prettyJSONForData:bounded maxBytes:kWQMPreviewTextBytes] : nil;
        NSString *text = pretty ?: [WQMFilePreviewModel textForData:bounded maxBytes:kWQMPreviewTextBytes truncated:NULL];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (self && generation == self->_previewGeneration) [self displayText:head text:text truncated:truncated];
        });
    });
}
- (void)displayText:(NSData *)head text:(NSString *)text truncated:(BOOL)truncated
{
    if (!head.length) {
        [self showMessage:WQML(@"PREVIEW_EMPTY", @"文件是空的") symbol:@"doc"];
        return;
    }

    UITextView *textView = [self makeTextView];
    textView.text = text ?: @"";
    [self.view addSubview:textView];
    [self pinTextView:textView includeBottom:!truncated];

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
    [self loadHeadWithLimit:kWQMPreviewHexBytes completion:^(NSData *head) { [self displayHex:head]; }];
}
- (void)displayHex:(NSData *)head
{
    if (!head.length) {
        [self showMessage:WQML(@"PREVIEW_EMPTY", @"文件是空的") symbol:@"doc"];
        return;
    }

    UITextView *textView = [self makeTextView];
    textView.text = [WQMFilePreviewModel hexDumpForData:head maxBytes:kWQMPreviewHexBytes];
    [self.view addSubview:textView];
    [self pinTextView:textView includeBottom:NO];

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
    textView.adjustsFontForContentSizeCategory = YES;
    textView.editable = NO;
    textView.selectable = YES;
    textView.backgroundColor = WQMTheme.canvasColor;
    textView.textColor = WQMTheme.textPrimaryColor;
    textView.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody] scaledFontForFont:[UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular]];
    textView.textContainerInset = UIEdgeInsetsMake(16, 16, 16, 16);
    textView.alwaysBounceVertical = YES;
    textView.accessibilityIdentifier = @"preview.text";
    return textView;
}

- (void)pinTextView:(UITextView *)textView includeBottom:(BOOL)includeBottom
{
    [NSLayoutConstraint activateConstraints:@[
        [textView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [textView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [textView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
    if (includeBottom) [textView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor].active = YES;
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
