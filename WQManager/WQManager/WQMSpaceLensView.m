//
//  WQMSpaceLensView.m
//  WQManager
//

#import "WQMSpaceLensView.h"
#import "WQMTheme.h"
#import "WQMLanguageManager.h"

static const CGFloat kWQMSpaceLensFillRatio = 0.62;

@interface WQMSpaceLensBubble : UIControl

@property (nonatomic, strong) CAGradientLayer *baseLayer;
@property (nonatomic, strong) CAGradientLayer *veilLayer;
@property (nonatomic, strong) CAGradientLayer *sheenLayer;
@property (nonatomic, strong) CAGradientLayer *innerGlowLayer;
@property (nonatomic, strong) CAGradientLayer *bloomLayer;
@property (nonatomic, strong) CAShapeLayer *bloomMask;
@property (nonatomic, strong) CAGradientLayer *bottomGlowLayer;
@property (nonatomic, strong) CALayer *grainLayer;
@property (nonatomic, strong) CAShapeLayer *rimLayer;
@property (nonatomic, strong) CAShapeLayer *highlightLayer;
@property (nonatomic, strong) CAGradientLayer *filmLayer;
@property (nonatomic, strong) CAShapeLayer *filmMask;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, copy) NSString *fileName;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *sizeLabel;
@property (nonatomic) BOOL directory;
@property (nonatomic) BOOL aggregate;
@property (nonatomic, strong) UIColor *appliedTint;
@property (nonatomic, copy, nullable) UIMenu *(^menuProvider)(void);

- (void)applyRadius:(CGFloat)radius;
@end

@implementation WQMSpaceLensBubble

/// A very fine noise plate. It kills gradient banding and gives the fill a
/// printed, matte quality instead of a flat plastic one.
static UIImage *WQMBubbleGrainImage(void)
{
    static UIImage *image;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        CGSize size = CGSizeMake(256, 256);
        UIGraphicsImageRendererFormat *format = UIGraphicsImageRendererFormat.defaultFormat;
        format.opaque = NO;
        format.scale = 1.0;
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size
                                                                                  format:format];
        image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
            for (NSInteger i = 0; i < 14000; i++) {
                CGFloat x = (CGFloat)arc4random_uniform(256);
                CGFloat y = (CGFloat)arc4random_uniform(256);
                CGFloat alpha = 0.03 + (CGFloat)arc4random_uniform(1000) / 1000.0 * 0.06;
                BOOL light = (i % 3) != 0;
                UIColor *color = light ? [UIColor colorWithWhite:1.0 alpha:alpha]
                                       : [UIColor colorWithWhite:0.0 alpha:alpha * 0.8];
                [color setFill];
                UIRectFillUsingBlendMode(CGRectMake(x, y, 1, 1), kCGBlendModeNormal);
            }
        }];
    });
    return image;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = UIColor.clearColor;

        _baseLayer = [CAGradientLayer layer];
        _baseLayer.type = kCAGradientLayerRadial;
        _baseLayer.startPoint = CGPointMake(0.32, 0.24);
        _baseLayer.endPoint = CGPointMake(1.05, 1.05);
        _baseLayer.locations = @[@0.0, @0.55, @1.0];
        [self.layer addSublayer:_baseLayer];

        _innerGlowLayer = [CAGradientLayer layer];
        _innerGlowLayer.type = kCAGradientLayerRadial;
        _innerGlowLayer.startPoint = CGPointMake(0.5, 0.5);
        _innerGlowLayer.endPoint = CGPointMake(1.0, 1.0);
        _innerGlowLayer.locations = @[@0.0, @0.78, @1.0];
        [self.layer addSublayer:_innerGlowLayer];

        _bloomLayer = [CAGradientLayer layer];
        _bloomLayer.type = kCAGradientLayerRadial;
        _bloomLayer.startPoint = CGPointMake(0.5, 0.5);
        _bloomLayer.endPoint = CGPointMake(1.0, 1.0);
        _bloomLayer.locations = @[@0.0, @0.70, @0.92, @1.0];
        // The radial fill is a square, so the bloom has to stay inside the circle.
        _bloomMask = [CAShapeLayer layer];
        _bloomMask.fillColor = UIColor.whiteColor.CGColor;
        _bloomLayer.mask = _bloomMask;
        [self.layer addSublayer:_bloomLayer];

        _bottomGlowLayer = [CAGradientLayer layer];
        _bottomGlowLayer.startPoint = CGPointMake(0.5, 0.0);
        _bottomGlowLayer.endPoint = CGPointMake(0.5, 1.0);
        _bottomGlowLayer.locations = @[@0.62, @0.86, @1.0];
        [self.layer addSublayer:_bottomGlowLayer];

        _veilLayer = [CAGradientLayer layer];
        _veilLayer.startPoint = CGPointMake(0.5, 0.0);
        _veilLayer.endPoint = CGPointMake(0.5, 1.0);
        _veilLayer.locations = @[@0.42, @0.82, @1.0];
        [self.layer addSublayer:_veilLayer];

        _grainLayer = [CALayer layer];
        _grainLayer.contents = (__bridge id)WQMBubbleGrainImage().CGImage;
        _grainLayer.contentsGravity = kCAGravityResize;
        _grainLayer.opacity = 0.0f;
        _grainLayer.masksToBounds = YES;
        [self.layer addSublayer:_grainLayer];

        _sheenLayer = [CAGradientLayer layer];
        _sheenLayer.type = kCAGradientLayerRadial;
        _sheenLayer.startPoint = CGPointMake(0.34, 0.24);
        _sheenLayer.endPoint = CGPointMake(0.62, 0.60);
        _sheenLayer.colors = @[(__bridge id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor,
                               (__bridge id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor,
                               (__bridge id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor];
        _sheenLayer.locations = @[@0.0, @0.22, @1.0];
        [self.layer addSublayer:_sheenLayer];

        _rimLayer = [CAShapeLayer layer];
        _rimLayer.fillColor = UIColor.clearColor.CGColor;
        _rimLayer.lineWidth = 1.0;
        [self.layer addSublayer:_rimLayer];

        _highlightLayer = [CAShapeLayer layer];
        _highlightLayer.fillColor = UIColor.clearColor.CGColor;
        _highlightLayer.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.70].CGColor;
        _highlightLayer.lineWidth = 1.4;
        _highlightLayer.lineCap = kCALineCapRound;
        [self.layer addSublayer:_highlightLayer];

        UIContextMenuInteraction *menu = [[UIContextMenuInteraction alloc] initWithDelegate:self];
        [self addInteraction:menu];

        _iconView = [UIImageView new];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.layer.shadowColor = UIColor.blackColor.CGColor;
        _iconView.layer.shadowOpacity = 0.20f;
        _iconView.layer.shadowRadius = 4.0;
        _iconView.layer.shadowOffset = CGSizeMake(0, 3);
        [self addSubview:_iconView];

        _nameLabel = [UILabel new];
        _nameLabel.textAlignment = NSTextAlignmentCenter;
        _nameLabel.numberOfLines = 2;
        _nameLabel.adjustsFontSizeToFitWidth = YES;
        _nameLabel.minimumScaleFactor = 0.72;
        _nameLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        _nameLabel.layer.shadowColor = UIColor.blackColor.CGColor;
        _nameLabel.layer.shadowOpacity = 0.28f;
        _nameLabel.layer.shadowRadius = 3.0;
        _nameLabel.layer.shadowOffset = CGSizeMake(0, 1);

        _sizeLabel = [UILabel new];
        _sizeLabel.textAlignment = NSTextAlignmentCenter;
        _sizeLabel.adjustsFontSizeToFitWidth = YES;
        _sizeLabel.minimumScaleFactor = 0.7;
        _sizeLabel.layer.shadowColor = UIColor.blackColor.CGColor;
        _sizeLabel.layer.shadowOpacity = 0.24f;
        _sizeLabel.layer.shadowRadius = 2.0;
        _sizeLabel.layer.shadowOffset = CGSizeMake(0, 1);

        [self addSubview:_nameLabel];
        [self addSubview:_sizeLabel];

        UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc]
            initWithTarget:self action:@selector(pressed:)];
        press.minimumPressDuration = 0.01;
        press.cancelsTouchesInView = NO;
        [self addGestureRecognizer:press];

        self.layer.shadowColor = UIColor.blackColor.CGColor;
        self.layer.shadowOpacity = 0.24f;
        self.layer.shadowRadius = 14.0;
        self.layer.shadowOffset = CGSizeMake(0, 8);
    }
    return self;
}

- (void)layoutSubviews
{
    [super layoutSubviews];

    CGFloat diameter = CGRectGetWidth(self.bounds);
    CGFloat radius = diameter / 2;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _baseLayer.frame = self.bounds;
    _baseLayer.cornerRadius = radius;
    _innerGlowLayer.frame = self.bounds;
    _innerGlowLayer.cornerRadius = radius;
    _bloomLayer.frame = self.bounds;
    _bloomMask.frame = self.bounds;
    _bloomMask.path = [UIBezierPath bezierPathWithOvalInRect:self.bounds].CGPath;
    _bottomGlowLayer.frame = self.bounds;
    _bottomGlowLayer.cornerRadius = radius;
    _veilLayer.frame = self.bounds;
    _veilLayer.cornerRadius = radius;
    _sheenLayer.frame = self.bounds;
    _sheenLayer.cornerRadius = radius;
    _grainLayer.frame = self.bounds;
    _grainLayer.cornerRadius = radius;
    _rimLayer.frame = self.bounds;
    _rimLayer.path = [UIBezierPath bezierPathWithOvalInRect:CGRectInset(self.bounds, 0.6, 0.6)].CGPath;
    _highlightLayer.frame = self.bounds;
    CGFloat arcRadius = MAX(radius - 1.4, 1.0);
    _highlightLayer.path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(radius, radius)
                                                          radius:arcRadius
                                                      startAngle:M_PI * 1.08
                                                        endAngle:M_PI * 1.62
                                                       clockwise:YES].CGPath;
    [CATransaction commit];

    BOOL showText = diameter >= 44;
    BOOL showIcon = diameter >= 64;
    BOOL showSize = diameter >= 84 && _sizeLabel.text.length > 0;

    _nameLabel.hidden = !showText;
    _sizeLabel.hidden = !showSize;
    _iconView.hidden = !showIcon;

    CGFloat inset = MAX(diameter * 0.10, 3.0);
    CGFloat iconSide = diameter * 0.30;
    CGFloat iconTop = diameter * 0.195;
    _iconView.frame = CGRectMake((diameter - iconSide) / 2, iconTop, iconSide, iconSide);

    CGFloat nameTop;
    CGFloat nameHeight;
    if (showIcon) {
        nameTop = CGRectGetMaxY(_iconView.frame) + diameter * 0.035;
        nameHeight = diameter * 0.16;
    } else {
        nameHeight = diameter * (showSize ? 0.20 : 0.30);
        nameTop = (diameter - nameHeight) / 2 - (showSize ? diameter * 0.07 : 0);
    }
    _nameLabel.frame = CGRectMake(inset, nameTop, diameter - inset * 2, nameHeight);
    if (showSize) {
        _sizeLabel.frame = CGRectMake(inset, CGRectGetMaxY(_nameLabel.frame) + diameter * 0.010,
                                      diameter - inset * 2, diameter * 0.15);
    }
}

#pragma mark - Icon

- (void)applyIconForRadius:(CGFloat)radius
{
    if (_directory && !_aggregate) {
        _iconView.image = [WQMSpaceLensIcon folderImageWithSize:radius * 0.62];
        _iconView.tintColor = nil;
        return;
    }
    CGFloat pointSize = MAX(radius * 0.60, 8);
    UIImageConfiguration *configuration = [UIImageSymbolConfiguration
        configurationWithPointSize:pointSize weight:UIImageSymbolWeightMedium];
    UIImage *image = [UIImage systemImageNamed:[WQMSpaceLensIcon symbolNameForName:_fileName
                                                                        directory:_directory
                                                                        aggregate:_aggregate]
                             withConfiguration:configuration];
    _iconView.image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    _iconView.tintColor = [WQMSpaceLensIcon tintForName:_fileName
                                             directory:_directory
                                             aggregate:_aggregate];
}

#pragma mark - Appearance

- (void)applyTint:(UIColor *)tint
{
    CGFloat hue = 0, saturation = 0, brightness = 0, alpha = 0;
    if (![tint getHue:&hue saturation:&saturation brightness:&brightness alpha:&alpha]) return;
    self.appliedTint = tint;
    BOOL light = self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleLight;

    // Dark: a hairline of light with almost no fill. Light: a grey wash plus a
    // grey halo, because a white ring on paper has nothing to contrast with.
    UIColor *crown, *core, *depth, *edge;
    if (light) {
        crown = [UIColor colorWithWhite:0.60 alpha:0.14];
        core = [UIColor colorWithWhite:0.52 alpha:0.08];
        depth = [UIColor colorWithWhite:0.46 alpha:0.04];
        edge = [UIColor colorWithWhite:0.44 alpha:0.90];
    } else {
        crown = [UIColor colorWithHue:hue saturation:MIN(saturation * 0.50, 0.58)
                           brightness:1.0 alpha:0.02];
        core = [UIColor colorWithHue:hue saturation:MIN(saturation * 0.66, 0.76)
                          brightness:0.96 alpha:0.03];
        depth = [UIColor colorWithHue:hue saturation:MIN(saturation * 0.78, 0.90)
                           brightness:0.88 alpha:0.0];
        edge = [UIColor colorWithHue:hue saturation:MIN(saturation * 0.80, 0.92)
                          brightness:1.0 alpha:0.85];
    }

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _baseLayer.colors = @[(__bridge id)crown.CGColor,
                          (__bridge id)core.CGColor,
                          (__bridge id)depth.CGColor];
    _innerGlowLayer.colors = @[(__bridge id)[UIColor colorWithWhite:0.0 alpha:0.0].CGColor,
                               (__bridge id)[UIColor colorWithWhite:0.0 alpha:0.0].CGColor,
                               (__bridge id)[UIColor colorWithWhite:0.0 alpha:0.0].CGColor];
    _bottomGlowLayer.colors = @[(__bridge id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor,
                                (__bridge id)[UIColor colorWithWhite:1.0 alpha:(light ? 0.06 : 0.02)].CGColor,
                                (__bridge id)[UIColor colorWithWhite:1.0 alpha:(light ? 0.10 : 0.05)].CGColor];
    _veilLayer.colors = @[(__bridge id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor,
                          (__bridge id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor,
                          (__bridge id)[UIColor colorWithWhite:0.0 alpha:0.0].CGColor];
    _bloomLayer.colors = @[(__bridge id)[edge colorWithAlphaComponent:0.0].CGColor,
                           (__bridge id)[edge colorWithAlphaComponent:0.0].CGColor,
                           (__bridge id)[edge colorWithAlphaComponent:(light ? 0.16 : 0.08)].CGColor,
                           (__bridge id)[edge colorWithAlphaComponent:(light ? 0.34 : 0.24)].CGColor];
    _rimLayer.strokeColor = edge.CGColor;
    _rimLayer.lineWidth = 1.3;
    _rimLayer.shadowColor = edge.CGColor;
    _rimLayer.shadowOpacity = 1.0f;
    _rimLayer.shadowRadius = light ? 10.0 : 9.0;
    _rimLayer.shadowOffset = CGSizeZero;
    [CATransaction commit];

    self.layer.shadowColor = light
        ? [UIColor colorWithWhite:0.42 alpha:1.0].CGColor
        : edge.CGColor;
    self.layer.shadowOpacity = light ? 0.28f : (_directory ? 0.32f : 0.24f);
    self.layer.shadowRadius = light ? 18.0 : 22.0;
    self.layer.shadowOffset = CGSizeZero;
}

- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction
                                  configurationForMenuAtLocation:(CGPoint)location
{
    if (!self.menuProvider) return nil;
    __weak typeof(self) weakSelf = self;
    return [UIContextMenuConfiguration
            configurationWithIdentifier:nil
                        previewProvider:nil
                         actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggestedActions) {
        return weakSelf.menuProvider();
    }];
}

- (void)applyRadius:(CGFloat)radius
{
    CGRect frame = self.frame;
    frame.size = CGSizeMake(radius * 2, radius * 2);
    self.frame = frame;
    CGFloat diameter = radius * 2;
    self.layer.cornerRadius = radius;
    self.nameLabel.font = [UIFont systemFontOfSize:MIN(MAX(diameter * 0.078, 10.5), 16.0)
                                           weight:UIFontWeightSemibold];
    [self applyLabelStyle];
    self.sizeLabel.font = [UIFont monospacedSystemFontOfSize:MIN(MAX(diameter * 0.048, 8.5), 11.0)
                                                     weight:UIFontWeightMedium];

    [self applyIconForRadius:radius];
    [self setNeedsLayout];
}

- (void)applyLabelStyle
{
    BOOL light = self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleLight;
    self.nameLabel.textColor = light ? WQMTheme.textPrimaryColor
                                     : [UIColor colorWithWhite:1.0 alpha:0.96];
    self.sizeLabel.textColor = light ? WQMTheme.textSecondaryColor
                                     : [UIColor colorWithWhite:1.0 alpha:0.74];
    self.nameLabel.layer.shadowOpacity = light ? 0.0f : 0.28f;
    self.sizeLabel.layer.shadowOpacity = light ? 0.0f : 0.24f;
    self.iconView.layer.shadowOpacity = light ? 0.10f : 0.20f;
    self.highlightLayer.strokeColor = [UIColor colorWithWhite:light ? 0.0 : 1.0
                                                        alpha:light ? 0.06 : 0.70].CGColor;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection
{
    [super traitCollectionDidChange:previousTraitCollection];
    if (!previousTraitCollection) return;
    if (previousTraitCollection.userInterfaceStyle == self.traitCollection.userInterfaceStyle) return;
    [self applyLabelStyle];
    if (self.appliedTint) [self applyTint:self.appliedTint];
}

- (void)pressed:(UILongPressGestureRecognizer *)gesture
{
    BOOL inBounds = gesture.state == UIGestureRecognizerStateBegan ||
                    gesture.state == UIGestureRecognizerStateChanged;
    if (WQMTheme.shouldReduceMotion) return;
    if (inBounds) {
        [UIView animateWithDuration:0.14 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            self.transform = CGAffineTransformMakeScale(0.95, 0.95);
        } completion:nil];
    } else {
        [UIView animateWithDuration:0.32 delay:0 usingSpringWithDamping:0.55 initialSpringVelocity:0.4
                            options:UIViewAnimationOptionCurveEaseOut animations:^{
            self.transform = CGAffineTransformIdentity;
        } completion:nil];
    }
}

- (void)setHighlighted:(BOOL)highlighted
{
    [super setHighlighted:highlighted];
    if (WQMTheme.shouldReduceMotion) return;
    [UIView animateWithDuration:0.18 animations:^{
        self.alpha = highlighted ? 0.86 : 1.0;
    }];
}

@end


@implementation WQMSpaceLensIcon

+ (NSString *)symbolNameForName:(NSString *)name directory:(BOOL)directory aggregate:(BOOL)aggregate
{
    if (aggregate) return @"ellipsis";
    if (directory) return @"folder.fill";
    NSString *extension = name.pathExtension.lowercaseString;
    if ([@[@"db", @"sqlite", @"sqlite3", @"realm"] containsObject:extension]) {
        return @"cylinder.split.1x2.fill";
    }
    if ([@[@"mp4", @"mov", @"m4v", @"avi", @"mkv"] containsObject:extension]) {
        return @"film.fill";
    }
    if ([@[@"jpg", @"jpeg", @"png", @"heic", @"gif", @"webp"] containsObject:extension]) {
        return @"photo.fill";
    }
    if ([@[@"mp3", @"m4a", @"wav", @"aac"] containsObject:extension]) {
        return @"waveform";
    }
    if ([@[@"zip", @"tar", @"gz", @"rar", @"7z", @"wqbackup"] containsObject:extension]) {
        return @"archivebox.fill";
    }
    if ([@[@"app", @"appex"] containsObject:extension]) {
        return @"square.stack.3d.up.fill";
    }
    return @"doc.text.fill";
}

+ (UIColor *)tintForName:(NSString *)name directory:(BOOL)directory aggregate:(BOOL)aggregate
{
    if (aggregate) return [UIColor colorWithWhite:0.72 alpha:1.0];
    if (directory) return [UIColor colorWithRed:0.16 green:0.62 blue:1.00 alpha:1.0];
    NSString *extension = name.pathExtension.lowercaseString;
    if ([@[@"db", @"sqlite", @"sqlite3", @"realm"] containsObject:extension]) {
        return [UIColor colorWithRed:1.00 green:0.62 blue:0.26 alpha:1.0];
    }
    if ([@[@"mp4", @"mov", @"m4v", @"avi", @"mkv"] containsObject:extension]) {
        return [UIColor colorWithRed:1.00 green:0.47 blue:0.62 alpha:1.0];
    }
    if ([@[@"jpg", @"jpeg", @"png", @"heic", @"gif", @"webp"] containsObject:extension]) {
        return [UIColor colorWithRed:0.36 green:0.84 blue:0.55 alpha:1.0];
    }
    if ([@[@"mp3", @"m4a", @"wav", @"aac"] containsObject:extension]) {
        return [UIColor colorWithRed:0.55 green:0.75 blue:1.00 alpha:1.0];
    }
    if ([@[@"zip", @"tar", @"gz", @"rar", @"7z", @"wqbackup"] containsObject:extension]) {
        return [UIColor colorWithRed:0.95 green:0.78 blue:0.40 alpha:1.0];
    }
    if ([@[@"app", @"appex"] containsObject:extension]) {
        return [UIColor colorWithRed:0.62 green:0.72 blue:1.00 alpha:1.0];
    }
    return [UIColor colorWithWhite:0.96 alpha:0.95];
}

+ (nullable UIImage *)folderImageWithSize:(CGFloat)size
{
    if (size < 1) return nil;
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSCache new]; });
    NSString *key = [NSString stringWithFormat:@"folder-%.1f", size];
    UIImage *cached = [cache objectForKey:key];
    if (cached) return cached;

    CGFloat scale = size / 1024.0;
    CGFloat canvas = size;
    UIGraphicsImageRendererFormat *format = UIGraphicsImageRendererFormat.defaultFormat;
    format.opaque = NO;
    format.scale = UIScreen.mainScreen.scale;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc]
        initWithSize:CGSizeMake(canvas, canvas) format:format];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGContextRef ctx = context.CGContext;
        CGContextScaleCTM(ctx, scale, scale);
        CGContextSetLineJoin(ctx, kCGLineJoinRound);
        CGContextSetLineCap(ctx, kCGLineCapRound);

        // Back board with the tab, straight from the reference SVG.
        CGPoint board[] = {
            CGPointMake(170.2, 246.4), CGPointMake(512.3, 246.4), CGPointMake(601.4, 168.6),
            CGPointMake(856.3, 168.6), CGPointMake(894.0, 810.7), CGPointMake(213.0, 854.7),
            CGPointMake(169.0, 290.4),
        };
        CGContextSetFillColorWithColor(ctx, [UIColor colorWithRed:0.412 green:0.294 blue:0.294 alpha:1.0].CGColor);
        CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithRed:0.412 green:0.294 blue:0.294 alpha:1.0].CGColor);
        CGContextSetLineWidth(ctx, 26);
        CGContextAddLines(ctx, board, 7);
        CGContextClosePath(ctx);
        CGContextDrawPath(ctx, kCGPathFillStroke);

        // Dark sheet behind the papers.
        CGPoint dark[] = {
            CGPointMake(870.8, 671.8), CGPointMake(242.2, 707.0),
            CGPointMake(221.1, 319.0), CGPointMake(855.7, 283.8),
        };
        CGContextSetFillColorWithColor(ctx, [UIColor colorWithRed:0.349 green:0.247 blue:0.247 alpha:1.0].CGColor);
        CGContextAddLines(ctx, dark, 4);
        CGContextClosePath(ctx);
        CGContextFillPath(ctx);

        // Papers.
        CGPoint paper1[] = {
            CGPointMake(840.7, 673.7), CGPointMake(218.1, 725.0),
            CGPointMake(196.2, 341.6), CGPointMake(819.6, 285.7),
        };
        CGContextSetFillColorWithColor(ctx, UIColor.whiteColor.CGColor);
        CGContextAddLines(ctx, paper1, 4);
        CGContextClosePath(ctx);
        CGContextFillPath(ctx);

        CGPoint paper2[] = {
            CGPointMake(807.9, 715.1), CGPointMake(178.6, 750.0),
            CGPointMake(156.4, 393.7), CGPointMake(786.1, 345.6),
        };
        CGContextSetFillColorWithColor(ctx, [UIColor colorWithRed:0.949 green:0.949 blue:0.945 alpha:1.0].CGColor);
        CGContextAddLines(ctx, paper2, 4);
        CGContextClosePath(ctx);
        CGContextFillPath(ctx);

        CGPoint paper3[] = {
            CGPointMake(796.0, 713.5), CGPointMake(177.0, 749.8),
            CGPointMake(154.9, 343.5), CGPointMake(773.7, 303.4),
        };
        CGContextSetFillColorWithColor(ctx, UIColor.whiteColor.CGColor);
        CGContextAddLines(ctx, paper3, 4);
        CGContextClosePath(ctx);
        CGContextFillPath(ctx);

        // Blue front panel.
        CGPoint front[] = {
            CGPointMake(895.2, 425.1), CGPointMake(509.1, 425.1), CGPointMake(420.0, 353.7),
            CGPointMake(125.1, 353.7), CGPointMake(86.2, 389.7), CGPointMake(126.2, 818.9),
            CGPointMake(170.2, 854.7), CGPointMake(855.2, 854.7), CGPointMake(899.2, 818.9),
            CGPointMake(939.2, 460.9),
        };
        CGContextSetFillColorWithColor(ctx, [UIColor colorWithRed:0.0 green:0.710 blue:0.988 alpha:1.0].CGColor);
        CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithRed:0.0 green:0.710 blue:0.988 alpha:1.0].CGColor);
        CGContextSetLineWidth(ctx, 34);
        CGContextAddLines(ctx, front, 10);
        CGContextClosePath(ctx);
        CGContextDrawPath(ctx, kCGPathFillStroke);
    }];
    [cache setObject:image forKey:key];
    return image;
}

@end

@implementation WQMSpaceLensView {
    NSMutableArray<WQMSpaceLensBubble *> *_bubbles;
    UIView *_scanOverlay;
    UIActivityIndicatorView *_spinner;
    UILabel *_scanLabel;
    UIButton *_cancelButton;
    NSArray<WQMBubbleLayoutItem *> *_visibleItems;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        _bubbles = [NSMutableArray new];
        self.backgroundColor = UIColor.clearColor;
        self.isAccessibilityElement = NO;
    }
    return self;
}

- (void)setItems:(NSArray<WQMBubbleLayoutItem *> *)items
{
    [self setItems:items animated:YES];
}

- (void)setItems:(NSArray<WQMBubbleLayoutItem *> *)items animated:(BOOL)animated
{
    _items = [items copy] ?: @[];
    [self rebuildBubblesAnimated:animated];
}

- (UIEdgeInsets)contentInsets
{
    return UIEdgeInsetsMake(14, 16, 14, 16);
}

- (void)rebuildBubblesAnimated:(BOOL)animated
{
    for (WQMSpaceLensBubble *bubble in _bubbles) {
        [bubble removeFromSuperview];
    }
    [_bubbles removeAllObjects];

    NSMutableArray<WQMBubbleLayoutItem *> *visible = [NSMutableArray new];
    for (WQMBubbleLayoutItem *item in _items) {
        if (item.bytes == 0) continue;
        [visible addObject:item];
        WQMSpaceLensBubble *bubble = [WQMSpaceLensBubble new];
        bubble.directory = [item.identifier hasPrefix:@"dir:"];
        bubble.aggregate = [item.identifier isEqualToString:@"other"];
        [bubble applyTint:[self tintForIndex:_bubbles.count count:_items.count]];
        bubble.nameLabel.text = [self titleForItem:item];
        bubble.fileName = [[self titleForItem:item] copy];
        __weak typeof(self) weakSelf = self;
        bubble.menuProvider = ^UIMenu * _Nullable {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf || !strongSelf.contextMenuProvider) return nil;
            return strongSelf.contextMenuProvider(item);
        };
        bubble.sizeLabel.text = WQMFormatBytes(item.bytes);
        bubble.accessibilityLabel = [NSString stringWithFormat:@"%@, %@",
            bubble.nameLabel.text ?: @"", WQMFormatBytes(item.bytes)];
        bubble.tag = (NSInteger)_bubbles.count;
        [bubble addTarget:self action:@selector(bubbleTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:bubble];
        [_bubbles addObject:bubble];
    }
    _visibleItems = visible;
    [self layoutBubbles];

    if (animated && !WQMTheme.shouldReduceMotion) {
        NSTimeInterval delay = 0;
        for (WQMSpaceLensBubble *bubble in _bubbles) {
            bubble.alpha = 0;
            bubble.transform = CGAffineTransformMakeScale(0.72, 0.72);
            [UIView animateWithDuration:0.55 delay:delay usingSpringWithDamping:0.74
                  initialSpringVelocity:0.3 options:UIViewAnimationOptionCurveEaseOut animations:^{
                bubble.alpha = 1;
                bubble.transform = CGAffineTransformIdentity;
            } completion:nil];
            delay += 0.035;
        }
    }
}

- (UIColor *)tintForIndex:(NSUInteger)index count:(NSUInteger)count
{
    // Violet to turquoise, with the lightness stepping down along the ramp so
    // neighbours differ in value as well as in hue. Saturations stay under 1 so
    // the result reads as dyed paper rather than neon.
    // One colour for the whole map: area already encodes size, and a single
    // tint keeps the glowing rings quiet instead of turning into a rainbow.
    (void)index;
    (void)count;
    return [self neutralTint];
}

/// Dark mode draws the rings in white; light mode uses a soft grey so the
/// circles stay visible on the paper canvas without shouting.
- (UIColor *)neutralTint
{
    BOOL light = self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleLight;
    return light ? [UIColor colorWithWhite:0.55 alpha:1.0] : [UIColor colorWithWhite:1.0 alpha:1.0];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection
{
    [super traitCollectionDidChange:previousTraitCollection];
    if (!previousTraitCollection) return;
    if (previousTraitCollection.userInterfaceStyle == self.traitCollection.userInterfaceStyle) return;
    UIColor *tint = [self neutralTint];
    for (WQMSpaceLensBubble *bubble in _bubbles) {
        [bubble applyTint:tint];
    }
}

- (NSString *)titleForItem:(WQMBubbleLayoutItem *)item
{
    if ([item.identifier isEqualToString:@"other"]) {
        return WQML(@"LENS_OTHER", @"其他");
    }
    NSString *name = item.identifier;
    if ([name hasPrefix:@"dir:"]) {
        name = [name substringFromIndex:4];
    } else if ([name hasPrefix:@"file:"]) {
        name = [name substringFromIndex:5];
    }
    return name.length ? name : WQML(@"LENS_UNKNOWN", @"未命名");
}

- (void)layoutBubbles
{
    if (_bubbles.count == 0) return;
    UIEdgeInsets insets = [self contentInsets];
    CGSize size = CGSizeMake(MAX(CGRectGetWidth(self.bounds) - insets.left - insets.right, 1),
                             MAX(CGRectGetHeight(self.bounds) - insets.top - insets.bottom, 1));
    NSArray<WQMBubblePlacement *> *placements = [WQMBubbleLayout placementsForItems:_visibleItems
                                                                             inSize:size
                                                                          fillRatio:kWQMSpaceLensFillRatio];
    NSUInteger count = MIN(placements.count, _bubbles.count);
    for (NSUInteger i = 0; i < count; i++) {
        WQMBubblePlacement *placement = placements[i];
        WQMSpaceLensBubble *bubble = _bubbles[i];
        [bubble applyRadius:placement.radius];
        bubble.center = CGPointMake(placement.center.x + insets.left, placement.center.y + insets.top);
    }
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    [self layoutBubbles];
    [self layoutScanOverlay];
}

- (void)bubbleTapped:(WQMSpaceLensBubble *)sender
{
    NSInteger index = sender.tag;
    if (index < 0 || index >= (NSInteger)_visibleItems.count) return;
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [feedback impactOccurred];
    if (self.selectionHandler) self.selectionHandler(_visibleItems[(NSUInteger)index]);
}

#pragma mark - Scanning overlay

- (void)setScanning:(BOOL)scanning text:(NSString *)text
{
    if (!scanning) {
        [self cancelScanning];
        return;
    }
    if (!_scanOverlay) {
        _scanOverlay = [UIView new];
        _scanOverlay.backgroundColor = [WQMTheme.canvasColor colorWithAlphaComponent:0.82];
        _scanOverlay.layer.cornerRadius = WQMTheme.largeRadius;
        _scanOverlay.layer.cornerCurve = kCACornerCurveContinuous;
        _scanOverlay.userInteractionEnabled = YES;

        _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        _spinner.color = WQMTheme.textSecondaryColor;
        _scanLabel = [UILabel new];
        _scanLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        _scanLabel.textColor = WQMTheme.textSecondaryColor;
        _scanLabel.textAlignment = NSTextAlignmentCenter;
        _scanLabel.numberOfLines = 2;
        _cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_cancelButton setTitle:WQML(@"CANCEL", @"取消") forState:UIControlStateNormal];
        _cancelButton.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        _cancelButton.tintColor = WQMTheme.textSecondaryColor;
        [_cancelButton addTarget:self action:@selector(cancelTapped:) forControlEvents:UIControlEventTouchUpInside];

        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_spinner, _scanLabel, _cancelButton]];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.alignment = UIStackViewAlignmentCenter;
        stack.spacing = 8;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [_scanOverlay addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.centerXAnchor constraintEqualToAnchor:_scanOverlay.centerXAnchor],
            [stack.centerYAnchor constraintEqualToAnchor:_scanOverlay.centerYAnchor],
        ]];
        [self addSubview:_scanOverlay];
    }
    _scanOverlay.hidden = NO;
    _scanLabel.text = text;
    [_spinner startAnimating];
    [self layoutScanOverlay];
}

- (void)cancelScanning
{
    _scanOverlay.hidden = YES;
    [_spinner stopAnimating];
}

- (void)cancelTapped:(UIButton *)sender
{
    if (self.cancelHandler) self.cancelHandler();
}

- (void)layoutScanOverlay
{
    if (!_scanOverlay) return;
    UIEdgeInsets insets = [self contentInsets];
    _scanOverlay.frame = CGRectInset(self.bounds, insets.left, insets.top);
}

@end
