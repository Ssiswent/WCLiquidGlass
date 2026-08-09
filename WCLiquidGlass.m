#import "WCLiquidGlass.h"
#import "WCLiquidGlassCrashLogger.h"
#import "WCLiquidGlassHomeCorners.h"
#import "WCLiquidGlassMessageNotificationSettings.h"
#import "WCLiquidGlassMenu.h"
#import "WCLiquidGlassPreferences.h"

static const NSUInteger WCLiquidGlassMaximumButtonCount = 16;

#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <math.h>

#ifndef WCLIQUIDGLASS_VERSION
#define WCLIQUIDGLASS_VERSION "Unknown"
#endif

static UIColor *WCLiquidGlassBackdropTopColor(UITraitCollection *traits) {
    return traits.userInterfaceStyle == UIUserInterfaceStyleDark
        ? [UIColor colorWithRed:0.12 green:0.07 blue:0.04 alpha:1.0]
        : [UIColor colorWithRed:1.0 green:0.94 blue:0.84 alpha:1.0];
}

static UIColor *WCLiquidGlassBackdropBaseColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return WCLiquidGlassBackdropTopColor(traits);
    }];
}

@interface WCLiquidGlassBackdropView : UIView
@end

@implementation WCLiquidGlassBackdropView

+ (Class)layerClass {
    return CAGradientLayer.class;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self wc_updateColors];
    }
    return self;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self wc_updateColors];
    }
}

- (void)wc_updateColors {
    BOOL dark = self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    CAGradientLayer *gradient = (CAGradientLayer *)self.layer;
    gradient.colors = dark
        ? @[(id)WCLiquidGlassBackdropTopColor(self.traitCollection).CGColor,
            (id)[UIColor colorWithRed:0.025 green:0.025 blue:0.04 alpha:1.0].CGColor]
        : @[(id)WCLiquidGlassBackdropTopColor(self.traitCollection).CGColor,
            (id)[UIColor colorWithRed:0.94 green:0.95 blue:1.0 alpha:1.0].CGColor];
    gradient.startPoint = CGPointMake(0.0, 0.0);
    gradient.endPoint = CGPointMake(1.0, 1.0);
}

@end

static UIVisualEffect *WCLiquidGlassGlassEffect(WCLiquidGlassGlassAppearance appearance);

static UIVisualEffect *WCLiquidGlassSettingsEffect(void) {
    return WCLiquidGlassGlassEffect(WCLiquidGlassGlassAppearanceBalanced);
}

static UIVisualEffect *WCLiquidGlassGlassEffect(WCLiquidGlassGlassAppearance appearance) {
    Class glassClass = NSClassFromString(@"UIGlassEffect");
    SEL factorySelector = NSSelectorFromString(@"effectWithStyle:");
    if (glassClass && [glassClass respondsToSelector:factorySelector]) {
        UIVisualEffect *effect = ((id (*)(id, SEL, NSInteger))objc_msgSend)(glassClass,
                                                                           factorySelector,
                                                                           appearance == WCLiquidGlassGlassAppearanceClear ? 1 : 0);
        if (appearance == WCLiquidGlassGlassAppearanceTinted) {
            SEL tintColorSelector = NSSelectorFromString(@"setTintColor:");
            if ([effect respondsToSelector:tintColorSelector]) {
                UIColor *tintColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
                    return traits.userInterfaceStyle == UIUserInterfaceStyleDark
                        ? [UIColor colorWithWhite:1.0 alpha:0.23]
                        : [UIColor colorWithWhite:1.0 alpha:0.16];
                }];
                ((void (*)(id, SEL, id))objc_msgSend)(effect, tintColorSelector, tintColor);
            }
        }
        if (effect) {
            return effect;
        }
    }
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
}

static UIFont *WCLiquidGlassFont(CGFloat size, UIFontWeight weight);

static UIFontTextStyle WCLiquidGlassTextStyleForSize(CGFloat size) {
    if (size >= 20.0) {
        return UIFontTextStyleTitle2;
    }
    if (size >= 16.0) {
        return UIFontTextStyleBody;
    }
    if (size >= 14.0) {
        return UIFontTextStyleSubheadline;
    }
    if (size >= 12.0) {
        return UIFontTextStyleFootnote;
    }
    return UIFontTextStyleCaption2;
}

static BOOL WCLiquidGlassHasDifferentContentSizeCategory(UITraitCollection *current,
                                                          UITraitCollection *previous) {
    return ![current.preferredContentSizeCategory isEqualToString:previous.preferredContentSizeCategory];
}

static CGFloat WCLiquidGlassSectionHeaderHeight(void) {
    return MAX(38.0, ceil(WCLiquidGlassFont(13.0, UIFontWeightSemibold).lineHeight + 8.0));
}

static CGFloat WCLiquidGlassFooterHeight(NSString *text, CGFloat minimumHeight) {
    UIFont *font = WCLiquidGlassFont(13.0, UIFontWeightRegular);
    CGFloat width = MAX(1.0, UIScreen.mainScreen.bounds.size.width - 40.0);
    CGRect textBounds = [text boundingRectWithSize:CGSizeMake(width, CGFLOAT_MAX)
                                           options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                        attributes:@{NSFontAttributeName: font}
                                           context:nil];
    return MAX(minimumHeight, ceil(textBounds.size.height + 6.0));
}

static CGFloat WCLiquidGlassHeaderHeight(void) {
    CGFloat textHeight = WCLiquidGlassFont(22.0, UIFontWeightSemibold).lineHeight + 4.0 +
        WCLiquidGlassFont(14.0, UIFontWeightRegular).lineHeight * 2.0 + 10.0 +
        MAX(24.0, WCLiquidGlassFont(11.5, UIFontWeightSemibold).lineHeight + 8.0);
    return MAX(164.0, ceil(50.0 + textHeight));
}

static void WCLiquidGlassConfigureTableBackground(UITableViewController *controller) {
    UIColor *backgroundColor = WCLiquidGlassBackdropBaseColor();
    controller.view.backgroundColor = backgroundColor;
    controller.tableView.backgroundColor = backgroundColor;
    controller.tableView.backgroundView = [[WCLiquidGlassBackdropView alloc] init];
}

static UIColor *WCLiquidGlassSettingsCardColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        BOOL dark = traits.userInterfaceStyle == UIUserInterfaceStyleDark;
        return dark ? [UIColor colorWithWhite:0.14 alpha:0.94]
                    : [UIColor colorWithWhite:1.0 alpha:0.84];
    }];
}

static void WCLiquidGlassStyleCardCell(UITableViewCell *cell,
                                       NSIndexPath *indexPath,
                                       UITableView *tableView) {
    NSInteger rowCount = [tableView.dataSource tableView:tableView numberOfRowsInSection:indexPath.section];
    BOOL first = indexPath.row == 0;
    BOOL last = indexPath.row == rowCount - 1;
    CACornerMask corners = 0;
    if (first) {
        corners |= kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    }
    if (last) {
        corners |= kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    }
    cell.backgroundConfiguration = nil;
    cell.backgroundColor = WCLiquidGlassSettingsCardColor();
    cell.contentView.backgroundColor = UIColor.clearColor;
    cell.layer.cornerRadius = (first || last) ? 24.0 : 0.0;
    cell.layer.cornerCurve = kCACornerCurveContinuous;
    cell.layer.maskedCorners = corners;
    cell.layer.masksToBounds = YES;
}

static UIFont *WCLiquidGlassFont(CGFloat size, UIFontWeight weight) {
    NSString *fontName = weight >= UIFontWeightSemibold ? @"PingFangSC-Semibold" : @"PingFangSC-Regular";
    UIFont *font = [UIFont fontWithName:fontName size:size] ?: [UIFont systemFontOfSize:size weight:weight];
    return [[UIFontMetrics metricsForTextStyle:WCLiquidGlassTextStyleForSize(size)] scaledFontForFont:font];
}

static UILabel *WCLiquidGlassSectionLabel(NSString *text, UIColor *color) {
    UIFont *font = WCLiquidGlassFont(13.0, UIFontWeightSemibold);
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20.0, 4.0, 300.0,
                                                                ceil(font.lineHeight + 4.0))];
    label.text = text;
    label.font = font;
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = color;
    return label;
}

static UILabel *WCLiquidGlassFooterLabel(NSString *text) {
    UIFont *font = WCLiquidGlassFont(13.0, UIFontWeightRegular);
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20.0, 2.0, UIScreen.mainScreen.bounds.size.width - 40.0,
                                                                WCLiquidGlassFooterHeight(text, 48.0) - 4.0)];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    label.text = text;
    label.font = font;
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = UIColor.secondaryLabelColor;
    label.numberOfLines = 0;
    return label;
}

static void WCLiquidGlassConfigureCell(UITableViewCell *cell,
                                       NSString *title,
                                       NSString *secondaryText,
                                       UIImage *image,
                                       UIColor *titleColor) {
    UIListContentConfiguration *content = [UIListContentConfiguration valueCellConfiguration];
    content.text = title;
    content.secondaryText = secondaryText;
    content.image = image;
    content.textProperties.font = WCLiquidGlassFont(17.0, UIFontWeightRegular);
    content.textProperties.adjustsFontForContentSizeCategory = YES;
    content.textProperties.color = titleColor ?: UIColor.labelColor;
    content.secondaryTextProperties.font = WCLiquidGlassFont(15.0, UIFontWeightRegular);
    content.secondaryTextProperties.adjustsFontForContentSizeCategory = YES;
    content.secondaryTextProperties.color = UIColor.secondaryLabelColor;
    content.imageProperties.maximumSize = CGSizeMake(28.0, 28.0);
    content.imageProperties.reservedLayoutSize = CGSizeMake(28.0, 28.0);
    content.imageProperties.tintColor = UIColor.labelColor;
    content.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(10.0, 16.0, 10.0, 12.0);
    cell.contentConfiguration = content;
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
}

void WCLiquidGlassConfigureSettingsTableBackground(UITableViewController *controller) {
    WCLiquidGlassConfigureTableBackground(controller);
}

void WCLiquidGlassStyleSettingsCardCell(UITableViewCell *cell,
                                        NSIndexPath *indexPath,
                                        UITableView *tableView) {
    WCLiquidGlassStyleCardCell(cell, indexPath, tableView);
}

UIView *WCLiquidGlassSettingsSectionHeader(NSString *text) {
    return WCLiquidGlassSectionLabel(text, UIColor.secondaryLabelColor);
}

CGFloat WCLiquidGlassSettingsSectionHeaderHeight(void) {
    return WCLiquidGlassSectionHeaderHeight();
}

UIView *WCLiquidGlassSettingsFooter(NSString *text) {
    return WCLiquidGlassFooterLabel(text);
}

CGFloat WCLiquidGlassSettingsFooterHeight(NSString *text, CGFloat minimumHeight) {
    return WCLiquidGlassFooterHeight(text, minimumHeight);
}

void WCLiquidGlassConfigureSettingsCell(UITableViewCell *cell,
                                        NSString *title,
                                        NSString *secondaryText,
                                        UIImage * _Nullable image,
                                        UIColor *titleColor) {
    WCLiquidGlassConfigureCell(cell, title, secondaryText, image, titleColor);
}

static NSString *WCLiquidGlassGlassAppearanceTitle(WCLiquidGlassGlassAppearance appearance) {
    switch (appearance) {
        case WCLiquidGlassGlassAppearanceBalanced:
            return @"平衡";
        case WCLiquidGlassGlassAppearanceTinted:
            return @"色调";
        default:
            return @"通透";
    }
}

@interface WCLiquidGlassGlassPreviewView : UIView

@property(nonatomic, strong) UIView *menuPreview;

- (void)setAppearance:(WCLiquidGlassGlassAppearance)appearance;

@end


@implementation WCLiquidGlassGlassPreviewView

- (instancetype)init {
    self = [super initWithFrame:CGRectZero];
    if (!self) {
        return nil;
    }

    self.layer.cornerRadius = 28.0;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.clipsToBounds = YES;
    self.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithRed:0.07 green:0.10 blue:0.14 alpha:1.0]
            : [UIColor colorWithRed:0.74 green:0.88 blue:0.97 alpha:1.0];
    }];

    UIView *sky = [[UIView alloc] init];
    sky.translatesAutoresizingMaskIntoConstraints = NO;
    sky.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithRed:0.12 green:0.22 blue:0.31 alpha:0.92]
            : [UIColor colorWithRed:0.44 green:0.75 blue:0.96 alpha:0.88];
    }];

    UIView *building = [[UIView alloc] init];
    building.translatesAutoresizingMaskIntoConstraints = NO;
    building.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithRed:0.37 green:0.43 blue:0.49 alpha:0.86]
            : [UIColor colorWithRed:0.94 green:0.90 blue:0.80 alpha:0.94];
    }];
    building.layer.cornerRadius = 22.0;
    building.layer.cornerCurve = kCACornerCurveContinuous;
    building.transform = CGAffineTransformMakeRotation(-0.08);

    UIView *foliage = [[UIView alloc] init];
    foliage.translatesAutoresizingMaskIntoConstraints = NO;
    foliage.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithRed:0.10 green:0.26 blue:0.18 alpha:0.94]
            : [UIColor colorWithRed:0.19 green:0.47 blue:0.31 alpha:0.86];
    }];
    foliage.layer.cornerRadius = 80.0;
    foliage.layer.cornerCurve = kCACornerCurveContinuous;

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"液态，呈现更多内容";
    title.font = WCLiquidGlassFont(22.0, UIFontWeightSemibold);
    title.adjustsFontForContentSizeCategory = YES;
    title.textColor = UIColor.whiteColor;

    UILabel *subtitle = [[UILabel alloc] init];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.text = @"层次、色彩与光线会自然透过控件。";
    subtitle.font = WCLiquidGlassFont(14.0, UIFontWeightRegular);
    subtitle.adjustsFontForContentSizeCategory = YES;
    subtitle.numberOfLines = 2;
    subtitle.textColor = [UIColor.whiteColor colorWithAlphaComponent:0.86];

    _menuPreview = WCLiquidGlassCreateStaticMenuPreview();
    _menuPreview.translatesAutoresizingMaskIntoConstraints = NO;

    [self addSubview:sky];
    [self addSubview:building];
    [self addSubview:foliage];
    [self addSubview:title];
    [self addSubview:subtitle];
    [self addSubview:_menuPreview];
    [NSLayoutConstraint activateConstraints:@[
        [sky.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [sky.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [sky.topAnchor constraintEqualToAnchor:self.topAnchor],
        [sky.heightAnchor constraintEqualToAnchor:self.heightAnchor multiplier:0.58],
        [building.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:24.0],
        [building.topAnchor constraintEqualToAnchor:self.topAnchor constant:24.0],
        [building.widthAnchor constraintEqualToAnchor:self.widthAnchor multiplier:0.62],
        [building.heightAnchor constraintEqualToAnchor:self.heightAnchor multiplier:0.48],
        [foliage.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:-42.0],
        [foliage.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:54.0],
        [foliage.widthAnchor constraintEqualToAnchor:self.widthAnchor multiplier:0.70],
        [foliage.heightAnchor constraintEqualToAnchor:self.heightAnchor multiplier:0.40],
        [title.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:22.0],
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-22.0],
        [title.topAnchor constraintEqualToAnchor:self.topAnchor constant:26.0],
        [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [subtitle.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-22.0],
        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:5.0],
        [_menuPreview.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_menuPreview.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_menuPreview.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_menuPreview.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]
    ]];
    return self;
}

- (void)setAppearance:(WCLiquidGlassGlassAppearance)appearance {
    (void)appearance;
    WCLiquidGlassRefreshStaticMenuPreview(self.menuPreview);
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self setAppearance:WCLiquidGlassPreferences.glassAppearance];
    }
}

@end

@interface WCLiquidGlassGlassEndpointIcon : UIView

@property(nonatomic, assign) BOOL filled;
@property(nonatomic, strong) CAShapeLayer *rectangleLayer;
@property(nonatomic, strong) CAShapeLayer *ellipseLayer;

- (instancetype)initWithFilled:(BOOL)filled;

@end


@implementation WCLiquidGlassGlassEndpointIcon

- (instancetype)initWithFilled:(BOOL)filled {
    self = [super initWithFrame:CGRectZero];
    if (!self) {
        return nil;
    }
    _filled = filled;
    self.opaque = NO;
    _rectangleLayer = [CAShapeLayer layer];
    _ellipseLayer = [CAShapeLayer layer];
    [self.layer addSublayer:_rectangleLayer];
    [self.layer addSublayer:_ellipseLayer];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    UIColor *color = UIColor.secondaryLabelColor;
    CGRect rectangle = CGRectMake(1.5, 2.0, CGRectGetWidth(self.bounds) - 11.0, CGRectGetHeight(self.bounds) - 10.0);
    CGRect ellipse = CGRectMake(CGRectGetWidth(self.bounds) - 20.0,
                                CGRectGetHeight(self.bounds) - 17.0,
                                18.5,
                                14.5);
    self.rectangleLayer.path = [UIBezierPath bezierPathWithRoundedRect:rectangle cornerRadius:4.5].CGPath;
    self.ellipseLayer.path = [UIBezierPath bezierPathWithOvalInRect:ellipse].CGPath;
    if (self.filled) {
        self.rectangleLayer.fillColor = [color colorWithAlphaComponent:0.82].CGColor;
        self.rectangleLayer.strokeColor = UIColor.clearColor.CGColor;
        self.ellipseLayer.fillColor = color.CGColor;
        self.ellipseLayer.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.86].CGColor;
        self.ellipseLayer.lineWidth = 2.4;
    } else {
        self.rectangleLayer.fillColor = UIColor.clearColor.CGColor;
        self.rectangleLayer.strokeColor = color.CGColor;
        self.rectangleLayer.lineWidth = 2.4;
        self.ellipseLayer.fillColor = UIColor.clearColor.CGColor;
        self.ellipseLayer.strokeColor = color.CGColor;
        self.ellipseLayer.lineWidth = 2.4;
    }
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self setNeedsLayout];
    }
}

@end

@interface WCLiquidGlassGlassAppearanceControl : UIView

@property(nonatomic, strong) UISlider *slider;
@property(nonatomic, copy) NSArray<UIButton *> *stageButtons;
@property(nonatomic, copy) NSArray<NSLayoutConstraint *> *stageCenterConstraints;
@property(nonatomic, copy) NSArray<UIView *> *markers;
@property(nonatomic, strong) UISelectionFeedbackGenerator *selectionFeedbackGenerator;
@property(nonatomic, copy) void (^appearanceChanged)(WCLiquidGlassGlassAppearance appearance);

- (void)setAppearance:(WCLiquidGlassGlassAppearance)appearance animated:(BOOL)animated;

@end


@implementation WCLiquidGlassGlassAppearanceControl

- (instancetype)init {
    self = [super initWithFrame:CGRectZero];
    if (!self) {
        return nil;
    }

    self.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:1.0 alpha:0.10]
            : [UIColor colorWithWhite:1.0 alpha:0.76];
    }];
    self.layer.cornerRadius = 28.0;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    _selectionFeedbackGenerator = [[UISelectionFeedbackGenerator alloc] init];
    [_selectionFeedbackGenerator prepare];

    WCLiquidGlassGlassEndpointIcon *clearIcon = [[WCLiquidGlassGlassEndpointIcon alloc] initWithFilled:NO];
    clearIcon.translatesAutoresizingMaskIntoConstraints = NO;

    WCLiquidGlassGlassEndpointIcon *tintedIcon = [[WCLiquidGlassGlassEndpointIcon alloc] initWithFilled:YES];
    tintedIcon.translatesAutoresizingMaskIntoConstraints = NO;

    _slider = [[UISlider alloc] init];
    _slider.translatesAutoresizingMaskIntoConstraints = NO;
    _slider.minimumValue = WCLiquidGlassGlassAppearanceClear;
    _slider.maximumValue = WCLiquidGlassGlassAppearanceTinted;
    _slider.continuous = YES;
    SEL sliderStyleSelector = NSSelectorFromString(@"setSliderStyle:");
    if ([_slider respondsToSelector:sliderStyleSelector]) {
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(_slider, sliderStyleSelector, 0);
    }
    _slider.accessibilityLabel = @"液态效果";
    _slider.accessibilityHint = @"向左更通透，向右增加色调和可读性";
    [_slider addTarget:self action:@selector(wc_sliderChanged:) forControlEvents:UIControlEventValueChanged];
    UITapGestureRecognizer *sliderTap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                                 action:@selector(wc_sliderTapped:)];
    sliderTap.cancelsTouchesInView = NO;
    [_slider addGestureRecognizer:sliderTap];
    [self addSubview:_slider];

    NSArray<NSString *> *titles = @[@"透明", @"平衡", @"色调"];
    NSMutableArray<UIButton *> *stageButtons = [NSMutableArray arrayWithCapacity:titles.count];
    NSMutableArray<NSLayoutConstraint *> *stageCenterConstraints = [NSMutableArray arrayWithCapacity:titles.count];
    NSMutableArray<UIView *> *markers = [NSMutableArray arrayWithCapacity:titles.count];
    for (NSInteger index = WCLiquidGlassGlassAppearanceClear;
         index <= WCLiquidGlassGlassAppearanceTinted;
         index += 1) {
        UIButton *stageButton = [UIButton buttonWithType:UIButtonTypeCustom];
        stageButton.translatesAutoresizingMaskIntoConstraints = NO;
        stageButton.tag = index;
        stageButton.accessibilityLabel = titles[(NSUInteger)index];
        stageButton.accessibilityHint = @"切换到此液态效果";
        [stageButton addTarget:self action:@selector(wc_stageTapped:) forControlEvents:UIControlEventTouchUpInside];

        UIView *marker = [[UIView alloc] init];
        marker.translatesAutoresizingMaskIntoConstraints = NO;
        marker.layer.cornerRadius = 2.0;

        UILabel *label = [[UILabel alloc] init];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        label.text = titles[(NSUInteger)index];
        label.font = WCLiquidGlassFont(12.0, UIFontWeightMedium);
        label.adjustsFontForContentSizeCategory = YES;
        label.textColor = UIColor.secondaryLabelColor;
        label.textAlignment = NSTextAlignmentCenter;
        label.userInteractionEnabled = NO;

        [stageButton addSubview:marker];
        [stageButton addSubview:label];
        [self addSubview:stageButton];
        [NSLayoutConstraint activateConstraints:@[
            [marker.widthAnchor constraintEqualToConstant:4.0],
            [marker.heightAnchor constraintEqualToConstant:4.0],
            [marker.centerXAnchor constraintEqualToAnchor:stageButton.centerXAnchor],
            [marker.topAnchor constraintEqualToAnchor:stageButton.topAnchor],
            [label.leadingAnchor constraintEqualToAnchor:stageButton.leadingAnchor],
            [label.trailingAnchor constraintEqualToAnchor:stageButton.trailingAnchor],
            [label.topAnchor constraintEqualToAnchor:marker.bottomAnchor constant:8.0],
            [label.bottomAnchor constraintEqualToAnchor:stageButton.bottomAnchor]
        ]];
        NSLayoutConstraint *centerConstraint = [stageButton.centerXAnchor constraintEqualToAnchor:_slider.leadingAnchor];
        [stageCenterConstraints addObject:centerConstraint];
        [stageButtons addObject:stageButton];
        [markers addObject:marker];
        [NSLayoutConstraint activateConstraints:@[
            [stageButton.widthAnchor constraintEqualToConstant:72.0],
            [stageButton.topAnchor constraintEqualToAnchor:_slider.bottomAnchor constant:7.0],
            centerConstraint
        ]];
    }
    _stageButtons = stageButtons.copy;
    _stageCenterConstraints = stageCenterConstraints.copy;
    _markers = markers.copy;

    [self addSubview:clearIcon];
    [self addSubview:tintedIcon];
    [NSLayoutConstraint activateConstraints:@[
        [clearIcon.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:22.0],
        [clearIcon.widthAnchor constraintEqualToConstant:34.0],
        [clearIcon.heightAnchor constraintEqualToConstant:28.0],
        [clearIcon.centerYAnchor constraintEqualToAnchor:_slider.centerYAnchor],
        [_slider.leadingAnchor constraintEqualToAnchor:clearIcon.trailingAnchor constant:15.0],
        [_slider.trailingAnchor constraintEqualToAnchor:tintedIcon.leadingAnchor constant:-15.0],
        [_slider.topAnchor constraintEqualToAnchor:self.topAnchor constant:23.0],
        [tintedIcon.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-22.0],
        [tintedIcon.widthAnchor constraintEqualToConstant:34.0],
        [tintedIcon.heightAnchor constraintEqualToConstant:28.0],
        [tintedIcon.centerYAnchor constraintEqualToAnchor:_slider.centerYAnchor],
        [self.bottomAnchor constraintEqualToAnchor:_slider.bottomAnchor constant:49.0]
    ]];
    [self setAppearance:WCLiquidGlassPreferences.glassAppearance animated:NO];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect sliderBounds = self.slider.bounds;
    CGRect trackRect = [self.slider trackRectForBounds:sliderBounds];
    [self.stageCenterConstraints enumerateObjectsUsingBlock:^(NSLayoutConstraint *constraint, NSUInteger index, BOOL *stop) {
        (void)stop;
        constraint.constant = [self wc_thumbCenterXForAppearance:(WCLiquidGlassGlassAppearance)index
                                                        trackRect:trackRect];
    }];
}

- (CGFloat)wc_thumbCenterXForAppearance:(WCLiquidGlassGlassAppearance)appearance
                               trackRect:(CGRect)trackRect {
    CGRect thumbRect = [self.slider thumbRectForBounds:self.slider.bounds
                                              trackRect:trackRect
                                                  value:appearance];
    return CGRectGetMidX(thumbRect);
}

- (void)wc_sliderChanged:(UISlider *)slider {
    WCLiquidGlassGlassAppearance appearance = (WCLiquidGlassGlassAppearance)lroundf(slider.value);
    [self wc_selectAppearance:appearance animated:YES];
}

- (void)wc_sliderTapped:(UITapGestureRecognizer *)gestureRecognizer {
    CGPoint location = [gestureRecognizer locationInView:self.slider];
    CGRect sliderBounds = self.slider.bounds;
    CGRect trackRect = [self.slider trackRectForBounds:sliderBounds];
    WCLiquidGlassGlassAppearance closestAppearance = WCLiquidGlassGlassAppearanceClear;
    CGFloat closestDistance = CGFLOAT_MAX;
    for (NSInteger index = WCLiquidGlassGlassAppearanceClear;
         index <= WCLiquidGlassGlassAppearanceTinted;
         index += 1) {
        CGFloat distance = fabs(location.x - [self wc_thumbCenterXForAppearance:(WCLiquidGlassGlassAppearance)index
                                                                        trackRect:trackRect]);
        if (distance < closestDistance) {
            closestDistance = distance;
            closestAppearance = (WCLiquidGlassGlassAppearance)index;
        }
    }
    [self wc_selectAppearance:closestAppearance animated:YES];
}

- (void)wc_stageTapped:(UIButton *)stageButton {
    [self wc_selectAppearance:(WCLiquidGlassGlassAppearance)stageButton.tag animated:YES];
}

- (void)wc_selectAppearance:(WCLiquidGlassGlassAppearance)appearance animated:(BOOL)animated {
    [self setAppearance:appearance animated:animated];
    if (WCLiquidGlassPreferences.glassAppearance == appearance) {
        return;
    }
    [self.selectionFeedbackGenerator selectionChanged];
    [self.selectionFeedbackGenerator prepare];
    if (self.appearanceChanged) {
        self.appearanceChanged(appearance);
    }
}

- (void)setAppearance:(WCLiquidGlassGlassAppearance)appearance animated:(BOOL)animated {
    [self.slider setValue:appearance animated:animated];
    self.slider.accessibilityValue = WCLiquidGlassGlassAppearanceTitle(appearance);
    [self.markers enumerateObjectsUsingBlock:^(UIView *marker, NSUInteger index, BOOL *stop) {
        (void)stop;
        marker.backgroundColor = index == (NSUInteger)appearance
            ? UIColor.labelColor
            : [UIColor.secondaryLabelColor colorWithAlphaComponent:0.38];
    }];
    [self.stageButtons enumerateObjectsUsingBlock:^(UIButton *stageButton, NSUInteger index, BOOL *stop) {
        (void)stop;
        stageButton.accessibilityTraits = index == (NSUInteger)appearance
            ? UIAccessibilityTraitButton | UIAccessibilityTraitSelected
            : UIAccessibilityTraitButton;
    }];
}

@end

@interface WCLiquidGlassGlassAppearanceController : UIViewController

@property(nonatomic, strong) WCLiquidGlassGlassPreviewView *previewView;
@property(nonatomic, strong) WCLiquidGlassGlassAppearanceControl *appearanceControl;
@property(nonatomic, strong) UILabel *detailLabel;

@end


@implementation WCLiquidGlassGlassAppearanceController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"液态效果";
    self.view.backgroundColor = WCLiquidGlassBackdropBaseColor();

    WCLiquidGlassBackdropView *backdrop = [[WCLiquidGlassBackdropView alloc] init];
    backdrop.translatesAutoresizingMaskIntoConstraints = NO;
    UIScrollView *scrollView = [[UIScrollView alloc] init];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.alwaysBounceVertical = YES;
    UIView *contentView = [[UIView alloc] init];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *intro = [[UILabel alloc] init];
    intro.translatesAutoresizingMaskIntoConstraints = NO;
    intro.text = @"调节悬浮入口与环形菜单的液态层次";
    intro.font = WCLiquidGlassFont(16.0, UIFontWeightRegular);
    intro.adjustsFontForContentSizeCategory = YES;
    intro.numberOfLines = 0;
    intro.textColor = UIColor.secondaryLabelColor;

    _previewView = [[WCLiquidGlassGlassPreviewView alloc] init];
    _previewView.translatesAutoresizingMaskIntoConstraints = NO;

    _appearanceControl = [[WCLiquidGlassGlassAppearanceControl alloc] init];
    _appearanceControl.translatesAutoresizingMaskIntoConstraints = NO;
    _appearanceControl.appearanceChanged = ^(WCLiquidGlassGlassAppearance appearance) {
        [WCLiquidGlassPreferences setGlassAppearance:appearance];
    };

    _detailLabel = [[UILabel alloc] init];
    _detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _detailLabel.font = WCLiquidGlassFont(14.0, UIFontWeightRegular);
    _detailLabel.adjustsFontForContentSizeCategory = YES;
    _detailLabel.numberOfLines = 0;
    _detailLabel.textColor = UIColor.secondaryLabelColor;

    [self.view addSubview:backdrop];
    [self.view addSubview:scrollView];
    [scrollView addSubview:contentView];
    [contentView addSubview:intro];
    [contentView addSubview:_previewView];
    [contentView addSubview:_appearanceControl];
    [contentView addSubview:_detailLabel];
    [NSLayoutConstraint activateConstraints:@[
        [backdrop.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [backdrop.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [backdrop.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [backdrop.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [contentView.leadingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.leadingAnchor],
        [contentView.trailingAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.trailingAnchor],
        [contentView.topAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.topAnchor],
        [contentView.bottomAnchor constraintEqualToAnchor:scrollView.contentLayoutGuide.bottomAnchor],
        [contentView.widthAnchor constraintEqualToAnchor:scrollView.frameLayoutGuide.widthAnchor],
        [intro.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:24.0],
        [intro.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-24.0],
        [intro.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:18.0],
        [_previewView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20.0],
        [_previewView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20.0],
        [_previewView.topAnchor constraintEqualToAnchor:intro.bottomAnchor constant:18.0],
        [_previewView.heightAnchor constraintEqualToConstant:270.0],
        [_appearanceControl.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20.0],
        [_appearanceControl.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20.0],
        [_appearanceControl.topAnchor constraintEqualToAnchor:_previewView.bottomAnchor constant:28.0],
        [_detailLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:28.0],
        [_detailLabel.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-28.0],
        [_detailLabel.topAnchor constraintEqualToAnchor:_appearanceControl.bottomAnchor constant:16.0],
        [_detailLabel.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:-32.0]
    ]];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(wc_preferencesChanged:)
                                               name:WCLiquidGlassPreferencesDidChangeNotification
                                             object:nil];
    [self wc_updateAppearance];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection] ||
        WCLiquidGlassHasDifferentContentSizeCategory(self.traitCollection, previousTraitCollection)) {
        [self wc_updateAppearance];
    }
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)wc_preferencesChanged:(NSNotification *)notification {
    [self wc_updateAppearance];
}

- (void)wc_updateAppearance {
    WCLiquidGlassGlassAppearance appearance = WCLiquidGlassPreferences.glassAppearance;
    [self.previewView setAppearance:appearance];
    [self.appearanceControl setAppearance:appearance animated:NO];
    self.detailLabel.text = @"“透明”更通透，“色调”可增加不透明度，提升内容和控制项对比度。";
}

@end

@interface WCLiquidGlassButtonEditorController : UITableViewController

@property(nonatomic, strong) NSMutableArray<NSMutableDictionary<NSString *, id> *> *items;
@property(nonatomic, copy) NSArray<NSString *> *availableNavigationActions;
@property(nonatomic, copy) NSArray<NSString *> *availableChatActions;

@end


@implementation WCLiquidGlassButtonEditorController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"按钮与动作";
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 66.0;
    WCLiquidGlassConfigureTableBackground(self);
    self.tableView.separatorColor = [UIColor.separatorColor colorWithAlphaComponent:0.30];
    self.tableView.allowsSelectionDuringEditing = YES;
    self.navigationItem.rightBarButtonItem = self.editButtonItem;
    [self wc_reloadItems];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection] ||
        WCLiquidGlassHasDifferentContentSizeCategory(self.traitCollection, previousTraitCollection)) {
        [self.tableView reloadData];
    }
}

- (void)tableView:(UITableView *)tableView
  willDisplayCell:(UITableViewCell *)cell
forRowAtIndexPath:(NSIndexPath *)indexPath {
    WCLiquidGlassStyleCardCell(cell, indexPath, tableView);
}

- (void)wc_reloadItems {
    NSMutableArray *items = [NSMutableArray array];
    for (NSDictionary<NSString *, id> *item in WCLiquidGlassPreferences.buttonItems) {
        [items addObject:item.mutableCopy];
    }
    self.items = items;
    [self wc_rebuildAvailableActions];
    [self.tableView reloadData];
}

- (void)wc_saveItems {
    [WCLiquidGlassPreferences setButtonItems:self.items.copy];
}

- (NSSet<NSString *> *)wc_currentActionIdentifiers {
    NSMutableSet<NSString *> *actionIdentifiers = [NSMutableSet set];
    [self.items enumerateObjectsUsingBlock:^(NSDictionary<NSString *, id> *item, __unused NSUInteger index, __unused BOOL *stop) {
        if ([item[@"action"] isKindOfClass:NSString.class]) {
            [actionIdentifiers addObject:item[@"action"]];
        }
    }];
    return actionIdentifiers.copy;
}

- (void)wc_rebuildAvailableActions {
    NSSet<NSString *> *currentActions = [self wc_currentActionIdentifiers];
    NSArray<NSString *> *navigationActions = @[
        WCLiquidGlassActionSettings, WCLiquidGlassActionWCGlassSettings,
        WCLiquidGlassActionChats, WCLiquidGlassActionContacts,
        WCLiquidGlassActionDiscover, WCLiquidGlassActionMe,
        WCLiquidGlassActionPageHierarchyDiagnostics,
        WCLiquidGlassActionPlugins,
        WCLiquidGlassActionMoments, WCLiquidGlassActionChannels
    ];
    NSArray<NSString *> *chatActions = @[
        WCLiquidGlassActionDoutuAssistant, WCLiquidGlassActionSearchRecords,
        WCLiquidGlassActionAlbum, WCLiquidGlassActionCamera, WCLiquidGlassActionVideoCall,
        WCLiquidGlassActionRedPacket, WCLiquidGlassActionFiles, WCLiquidGlassActionTransfer,
        WCLiquidGlassActionLocation, WCLiquidGlassActionFavorites, WCLiquidGlassActionTranslate,
        WCLiquidGlassActionScan, WCLiquidGlassActionPayment, WCLiquidGlassActionContactCard,
        WCLiquidGlassActionVoiceInput, WCLiquidGlassActionNewLine,
        WCLiquidGlassActionMention, WCLiquidGlassActionFullInput
    ];
    NSPredicate *availablePredicate = [NSPredicate predicateWithBlock:^BOOL(NSString *actionIdentifier,
                                                                           __unused NSDictionary *bindings) {
        return ![currentActions containsObject:actionIdentifier];
    }];
    self.availableNavigationActions = [navigationActions filteredArrayUsingPredicate:availablePredicate];
    self.availableChatActions = [chatActions filteredArrayUsingPredicate:availablePredicate];
}

- (NSArray<NSString *> *)wc_availableActionsForSection:(NSInteger)section {
    return section == 1 ? self.availableNavigationActions : self.availableChatActions;
}

- (NSInteger)wc_availableSectionForAction:(NSString *)actionIdentifier {
    NSArray<NSString *> *navigationActions = @[
        WCLiquidGlassActionSettings, WCLiquidGlassActionWCGlassSettings,
        WCLiquidGlassActionChats, WCLiquidGlassActionContacts,
        WCLiquidGlassActionDiscover, WCLiquidGlassActionMe,
        WCLiquidGlassActionPageHierarchyDiagnostics,
        WCLiquidGlassActionPlugins,
        WCLiquidGlassActionMoments, WCLiquidGlassActionChannels
    ];
    return [navigationActions containsObject:actionIdentifier] ? 1 : 2;
}

- (void)wc_reloadAvailableSectionsWithoutAnimation {
    [UIView performWithoutAnimation:^{
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1, 2)]
                      withRowAnimation:UITableViewRowAnimationNone];
    }];
}

- (void)wc_confirmRestoreButtons {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"恢复默认按钮？"
                                                                   message:@"按钮顺序和已添加动作会恢复，其他设置不受影响。"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"恢复"
                                             style:UIAlertActionStyleDestructive
                                           handler:^(__unused UIAlertAction *action) {
        [WCLiquidGlassPreferences restoreDefaultButtonItems];
        [self wc_reloadItems];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 4;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) {
        return self.items.count;
    }
    if (section == 1 || section == 2) {
        return [self wc_availableActionsForSection:section].count;
    }
    return 1;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSArray<NSString *> *titles = @[@"已添加", @"导航与入口", @"聊天工具", @"管理"];
    return WCLiquidGlassSectionLabel(titles[section], UIColor.secondaryLabelColor);
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return WCLiquidGlassSectionHeaderHeight();
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return WCLiquidGlassFooterLabel(@"最多可添加 16 个动作；环形菜单会按当前页面自动隐藏不可用的动作。点按右上角“编辑”后，可删除按钮或按住右侧把手调整顺序。");
    }
    if (section == 2) {
        return WCLiquidGlassFooterLabel(@"编辑时轻点加号即可添加；已添加的动作不会重复显示。");
    }
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return WCLiquidGlassFooterHeight(@"最多可添加 16 个动作；环形菜单会按当前页面自动隐藏不可用的动作。点按右上角“编辑”后，可删除按钮或按住右侧把手调整顺序。", 54.0);
    }
    if (section == 2) {
        return WCLiquidGlassFooterHeight(@"编辑时轻点加号即可添加；已添加的动作不会重复显示。", 54.0);
    }
    return CGFLOAT_MIN;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return self.editing && indexPath.section == 0;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        return self.editing;
    }
    return self.editing && (indexPath.section == 1 || indexPath.section == 2)
        && self.items.count < WCLiquidGlassMaximumButtonCount;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.editing && indexPath.section == 0) {
        return UITableViewCellEditingStyleDelete;
    }
    if (self.editing && (indexPath.section == 1 || indexPath.section == 2)
        && self.items.count < WCLiquidGlassMaximumButtonCount) {
        return UITableViewCellEditingStyleInsert;
    }
    return UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    return self.editing && indexPath.section < 3;
}

- (void)tableView:(UITableView *)tableView
commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
 forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete && indexPath.section == 0) {
        NSString *actionIdentifier = self.items[indexPath.row][@"action"];
        BOOL wasAtMaximum = self.items.count == WCLiquidGlassMaximumButtonCount;
        [self.items removeObjectAtIndex:indexPath.row];
        [self wc_rebuildAvailableActions];
        [self wc_saveItems];
        NSInteger destinationSection = [self wc_availableSectionForAction:actionIdentifier];
        NSUInteger destinationRow = [[self wc_availableActionsForSection:destinationSection] indexOfObject:actionIdentifier];
        [tableView performBatchUpdates:^{
            [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
            if (destinationRow != NSNotFound) {
                NSIndexPath *destination = [NSIndexPath indexPathForRow:destinationRow inSection:destinationSection];
                [tableView insertRowsAtIndexPaths:@[destination] withRowAnimation:UITableViewRowAnimationAutomatic];
            }
        } completion:^(__unused BOOL finished) {
            if (wasAtMaximum) {
                [self wc_reloadAvailableSectionsWithoutAnimation];
            }
        }];
        return;
    }
    if (editingStyle != UITableViewCellEditingStyleInsert
        || (indexPath.section != 1 && indexPath.section != 2)
        || self.items.count >= WCLiquidGlassMaximumButtonCount) {
        return;
    }
    NSString *actionIdentifier = [self wc_availableActionsForSection:indexPath.section][indexPath.row];
    NSUInteger destinationRow = self.items.count;
    [self.items addObject:[@{
        @"slot": [NSString stringWithFormat:@"slot.%@", NSUUID.UUID.UUIDString],
        @"action": actionIdentifier
    } mutableCopy]];
    [self wc_rebuildAvailableActions];
    [self wc_saveItems];
    BOOL reachedMaximum = self.items.count == WCLiquidGlassMaximumButtonCount;
    [tableView performBatchUpdates:^{
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
        NSIndexPath *destination = [NSIndexPath indexPathForRow:destinationRow inSection:0];
        [tableView insertRowsAtIndexPaths:@[destination] withRowAnimation:UITableViewRowAnimationAutomatic];
    } completion:^(__unused BOOL finished) {
        if (reachedMaximum) {
            [self wc_reloadAvailableSectionsWithoutAnimation];
        }
    }];
}

- (void)tableView:(UITableView *)tableView
 moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath
        toIndexPath:(NSIndexPath *)destinationIndexPath {
    NSMutableDictionary *item = self.items[sourceIndexPath.row];
    [self.items removeObjectAtIndex:sourceIndexPath.row];
    [self.items insertObject:item atIndex:destinationIndexPath.row];
    [self wc_saveItems];
}

- (NSIndexPath *)tableView:(UITableView *)tableView
targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)sourceIndexPath
       toProposedIndexPath:(NSIndexPath *)proposedDestinationIndexPath {
    if (proposedDestinationIndexPath.section == 0) {
        return proposedDestinationIndexPath;
    }
    return [NSIndexPath indexPathForRow:self.items.count - 1 inSection:0];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"WCLiquidGlassButtonEditorCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
    }

    if (indexPath.section == 3) {
        WCLiquidGlassConfigureCell(cell,
                                   @"恢复默认按钮",
                                   @"恢复为最初的按钮与顺序",
                                   WCLiquidGlassSettingsIconImage(WCLiquidGlassSettingsIconKindRestore, 32.0),
                                   UIColor.systemRedColor);
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.showsReorderControl = NO;
        cell.contentView.alpha = 1.0;
        return cell;
    }

    NSString *actionIdentifier = indexPath.section == 0
        ? self.items[indexPath.row][@"action"]
        : [self wc_availableActionsForSection:indexPath.section][indexPath.row];
    WCLiquidGlassConfigureCell(cell,
                               WCLiquidGlassActionTitle(actionIdentifier),
                               nil,
                               WCLiquidGlassImageForAction(actionIdentifier, 60.0),
                               UIColor.labelColor);
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.showsReorderControl = indexPath.section == 0;
    cell.contentView.alpha = (indexPath.section > 0
                              && self.items.count >= WCLiquidGlassMaximumButtonCount) ? 0.45 : 1.0;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 3) {
        [self wc_confirmRestoreButtons];
    }
}

@end

@interface WCLiquidGlassCrashLogsController : UITableViewController

@property(nonatomic, copy) NSArray<NSURL *> *logURLs;

@end


@implementation WCLiquidGlassCrashLogsController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"崩溃日志";
    WCLiquidGlassConfigureTableBackground(self);
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 76.0;
    self.tableView.separatorColor = [UIColor.separatorColor colorWithAlphaComponent:0.30];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"清空"
                                                                               style:UIBarButtonItemStylePlain
                                                                              target:self
                                                                              action:@selector(wc_confirmDeleteAll)];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(wc_logsChanged:)
                                               name:WCLiquidGlassCrashLogsDidChangeNotification
                                             object:nil];
    [self wc_reloadLogs];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection] ||
        WCLiquidGlassHasDifferentContentSizeCategory(self.traitCollection, previousTraitCollection)) {
        [self.tableView reloadData];
    }
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.logURLs.count;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    return WCLiquidGlassSectionLabel(@"最近日志", UIColor.secondaryLabelColor);
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return WCLiquidGlassSectionHeaderHeight();
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    return WCLiquidGlassFooterLabel(@"最多保留 20 份。点击日志可调用 iOS 系统分享；内容包含崩溃堆栈、系统与已加载插件信息，不记录聊天文字。");
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return WCLiquidGlassFooterHeight(@"最多保留 20 份。点击日志可调用 iOS 系统分享；内容包含崩溃堆栈、系统与已加载插件信息，不记录聊天文字。", 72.0);
}

- (void)tableView:(UITableView *)tableView
  willDisplayCell:(UITableViewCell *)cell
forRowAtIndexPath:(NSIndexPath *)indexPath {
    WCLiquidGlassStyleCardCell(cell, indexPath, tableView);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"WCLiquidGlassCrashLogCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    }
    NSURL *URL = self.logURLs[indexPath.row];
    NSNumber *fileSize = nil;
    NSDate *modifiedAt = nil;
    [URL getResourceValue:&fileSize forKey:NSURLFileSizeKey error:nil];
    [URL getResourceValue:&modifiedAt forKey:NSURLContentModificationDateKey error:nil];
    BOOL fullReport = [URL.pathExtension.lowercaseString isEqualToString:@"crash"];
    NSString *title = fullReport ? @"完整崩溃报告" : @"Objective-C 异常报告";
    NSString *detail = [NSString stringWithFormat:@"%@ · %@",
                        modifiedAt ? [NSDateFormatter localizedStringFromDate:modifiedAt
                                                                    dateStyle:NSDateFormatterShortStyle
                                                                    timeStyle:NSDateFormatterMediumStyle] : @"未知时间",
                        [NSByteCountFormatter stringFromByteCount:fileSize.longLongValue
                                                      countStyle:NSByteCountFormatterCountStyleFile]];
    WCLiquidGlassConfigureCell(cell, title, detail,
                               WCLiquidGlassSettingsIconImage(WCLiquidGlassSettingsIconKindCrashLogs, 32.0), UIColor.labelColor);
    cell.accessibilityHint = URL.lastPathComponent;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSURL *URL = self.logURLs[indexPath.row];
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[URL]
                                                                        applicationActivities:nil];
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    share.popoverPresentationController.sourceView = cell;
    share.popoverPresentationController.sourceRect = cell.bounds;
    [self presentViewController:share animated:YES completion:nil];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (void)tableView:(UITableView *)tableView
commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
 forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) {
        return;
    }
    [[WCLiquidGlassCrashLogger sharedLogger] deleteLogAtURL:self.logURLs[indexPath.row] error:nil];
}

- (void)wc_reloadLogs {
    self.logURLs = WCLiquidGlassCrashLogger.sharedLogger.crashLogURLs;
    self.navigationItem.rightBarButtonItem.enabled = self.logURLs.count > 0;
    if (self.logURLs.count == 0) {
        UILabel *empty = [[UILabel alloc] init];
        empty.text = @"暂无崩溃日志\n发生可捕获的异常后会自动出现在这里";
        empty.numberOfLines = 0;
        empty.textAlignment = NSTextAlignmentCenter;
        empty.textColor = UIColor.secondaryLabelColor;
        empty.font = WCLiquidGlassFont(15.0, UIFontWeightRegular);
        empty.adjustsFontForContentSizeCategory = YES;
        self.tableView.backgroundView = empty;
    } else {
        self.tableView.backgroundView = [[WCLiquidGlassBackdropView alloc] init];
    }
    [self.tableView reloadData];
}

- (void)wc_logsChanged:(NSNotification *)notification {
    [self wc_reloadLogs];
}

- (void)wc_confirmDeleteAll {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"清空全部日志？"
                                                                   message:@"删除后无法恢复。"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"清空"
                                             style:UIAlertActionStyleDestructive
                                           handler:^(__unused UIAlertAction *action) {
        [WCLiquidGlassCrashLogger.sharedLogger deleteAllLogs];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end


@interface WCLiquidGlass ()

@property(nonatomic, strong) UISwitch *enabledSwitch;
@property(nonatomic, strong) UISwitch *chatTimeGlassSwitch;
@property(nonatomic, strong) UISwitch *contactsIndexGlassSwitch;
@property(nonatomic, strong) UISwitch *wcGlassLongPressMenuSwitch;
@property(nonatomic, strong) UISwitch *unreadMessageTipGlassSwitch;
@property(nonatomic, strong) UISwitch *messageSwipeActionsSwitch;
@property(nonatomic, strong) UISwitch *fullCrashReportsSwitch;
@property(nonatomic, strong) UISwitch *materialFileProtectionSwitch;

@end


@implementation WCLiquidGlass

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"WCLiquidGlass";
    WCLiquidGlassConfigureTableBackground(self);
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 66.0;
    self.tableView.separatorColor = [UIColor.separatorColor colorWithAlphaComponent:0.30];
    self.tableView.tableHeaderView = [self wc_makeHeaderView];
    [WCLiquidGlassPreferences registerDefaults];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(wc_preferencesChanged:)
                                           name:WCLiquidGlassPreferencesDidChangeNotification
                                           object:nil];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection] ||
        WCLiquidGlassHasDifferentContentSizeCategory(self.traitCollection, previousTraitCollection)) {
        self.tableView.tableHeaderView = [self wc_makeHeaderView];
        [self.tableView reloadData];
    }
}

- (void)tableView:(UITableView *)tableView
  willDisplayCell:(UITableViewCell *)cell
forRowAtIndexPath:(NSIndexPath *)indexPath {
    WCLiquidGlassStyleCardCell(cell, indexPath, tableView);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIView *header = self.tableView.tableHeaderView;
    if (!header) {
        return;
    }
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    if (fabs(CGRectGetWidth(header.frame) - width) > 0.5) {
        header.frame = CGRectMake(0.0, 0.0, width, WCLiquidGlassHeaderHeight());
        self.tableView.tableHeaderView = header;
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (UIView *)wc_makeHeaderView {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 320.0, WCLiquidGlassHeaderHeight())];
    UIVisualEffectView *card = [[UIVisualEffectView alloc] initWithEffect:WCLiquidGlassSettingsEffect()];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.layer.cornerRadius = 28.0;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.clipsToBounds = YES;

    UIImageView *brandIcon = [[UIImageView alloc] initWithImage:WCLiquidGlassBrandIconImage(58.0, YES)];
    brandIcon.translatesAutoresizingMaskIntoConstraints = NO;
    brandIcon.contentMode = UIViewContentModeScaleAspectFit;

    UIView *brandDetails = [[UIView alloc] init];
    brandDetails.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"WCLiquidGlass";
    title.font = WCLiquidGlassFont(22.0, UIFontWeightSemibold);
    title.adjustsFontForContentSizeCategory = YES;
    title.textColor = UIColor.labelColor;

    UILabel *subtitle = [[UILabel alloc] init];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.text = @"为微信打造的模块化交互增强";
    subtitle.textColor = UIColor.secondaryLabelColor;
    subtitle.font = WCLiquidGlassFont(14.0, UIFontWeightRegular);
    subtitle.adjustsFontForContentSizeCategory = YES;
    subtitle.numberOfLines = 2;

    UIView *versionBadge = [[UIView alloc] init];
    versionBadge.translatesAutoresizingMaskIntoConstraints = NO;
    versionBadge.backgroundColor = UIColor.secondarySystemFillColor;
    versionBadge.layer.cornerRadius = 12.0;
    versionBadge.layer.cornerCurve = kCACornerCurveContinuous;
    versionBadge.layer.borderWidth = 0.5;
    versionBadge.layer.borderColor = [UIColor.separatorColor colorWithAlphaComponent:0.34].CGColor;

    UILabel *version = [[UILabel alloc] init];
    version.translatesAutoresizingMaskIntoConstraints = NO;
    NSString *displayVersion = [NSString stringWithUTF8String:WCLIQUIDGLASS_VERSION];
    displayVersion = [[displayVersion stringByReplacingOccurrencesOfString:@"~" withString:@" "] uppercaseString];
    version.text = [NSString stringWithFormat:@"Version %@", displayVersion];
    version.font = WCLiquidGlassFont(11.5, UIFontWeightSemibold);
    version.adjustsFontForContentSizeCategory = YES;
    version.textColor = UIColor.secondaryLabelColor;
    version.textAlignment = NSTextAlignmentCenter;

    [header addSubview:card];
    [card.contentView addSubview:brandIcon];
    [card.contentView addSubview:brandDetails];
    [brandDetails addSubview:title];
    [brandDetails addSubview:subtitle];
    [brandDetails addSubview:versionBadge];
    [versionBadge addSubview:version];
    [NSLayoutConstraint activateConstraints:@[
        [card.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20.0],
        [card.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20.0],
        [card.topAnchor constraintEqualToAnchor:header.topAnchor constant:14.0],
        [card.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-12.0],
        [brandIcon.leadingAnchor constraintEqualToAnchor:card.contentView.leadingAnchor constant:22.0],
        [brandIcon.centerYAnchor constraintEqualToAnchor:card.contentView.centerYAnchor],
        [brandIcon.widthAnchor constraintEqualToConstant:58.0],
        [brandIcon.heightAnchor constraintEqualToConstant:58.0],
        [brandDetails.leadingAnchor constraintEqualToAnchor:brandIcon.trailingAnchor constant:15.0],
        [brandDetails.trailingAnchor constraintEqualToAnchor:card.contentView.trailingAnchor constant:-20.0],
        [brandDetails.centerYAnchor constraintEqualToAnchor:card.contentView.centerYAnchor],
        [title.leadingAnchor constraintEqualToAnchor:brandDetails.leadingAnchor],
        [title.topAnchor constraintEqualToAnchor:brandDetails.topAnchor],
        [title.trailingAnchor constraintEqualToAnchor:brandDetails.trailingAnchor],
        [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:4.0],
        [subtitle.trailingAnchor constraintEqualToAnchor:brandDetails.trailingAnchor],
        [versionBadge.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [versionBadge.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:10.0],
        [versionBadge.heightAnchor constraintEqualToConstant:MAX(24.0, ceil(version.font.lineHeight + 8.0))],
        [versionBadge.bottomAnchor constraintEqualToAnchor:brandDetails.bottomAnchor],
        [version.leadingAnchor constraintEqualToAnchor:versionBadge.leadingAnchor constant:10.0],
        [version.trailingAnchor constraintEqualToAnchor:versionBadge.trailingAnchor constant:-10.0],
        [version.centerYAnchor constraintEqualToAnchor:versionBadge.centerYAnchor]
    ]];
    return header;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 5;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) {
        return 7;
    }
    if (section == 1) {
        return 9;
    }
    if (section == 2) {
        return 2;
    }
    return section == 3 ? 2 : 1;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSArray<NSString *> *titles = @[@"菜单", @"内容", @"保护与兼容", @"诊断", @"维护"];
    return WCLiquidGlassSectionLabel(titles[section], UIColor.secondaryLabelColor);
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return WCLiquidGlassSectionHeaderHeight();
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return WCLiquidGlassFooterLabel(@"入口可在微信任意页面呼出，可选择环形菜单或系统液态面板；闲置时自动吸附并半隐藏到屏幕边缘。空间不足时自动使用所选紧凑布局。");
    }
    if (section == 1) {
        return WCLiquidGlassFooterLabel(@"在“按钮与动作”页面点按编辑，即可添加、删除或拖动调整按钮顺序。聊天时间条、通讯录 A–Z 索引、消息通知与未读消息提示跟随本插件材质设置；首页圆角与液态可分别管理各自的圆角、间距与材质。");
    }
    if (section == 2) {
        return WCLiquidGlassFooterLabel(@"WCGlass iOS 27 兼容修复用于处理带键盘返回时的闪退；素材文件保护会阻止微信磁盘扫描删除未知素材，并保持 ThemePro 的删除与移动拦截规则。开关切换后立即生效。");
    }
    if (section == 3) {
        return WCLiquidGlassFooterLabel(@"基础诊断始终开启且不记录聊天内容；日志可在“崩溃日志”中分享。");
    }
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return WCLiquidGlassFooterHeight(@"入口可在微信任意页面呼出，可选择环形菜单或系统液态面板；闲置时自动吸附并半隐藏到屏幕边缘。空间不足时自动使用所选紧凑布局。", 88.0);
    }
    if (section == 1) {
        return WCLiquidGlassFooterHeight(@"在“按钮与动作”页面点按编辑，即可添加、删除或拖动调整按钮顺序。聊天时间条、通讯录 A–Z 索引、消息通知与未读消息提示跟随本插件材质设置；首页圆角与液态可分别管理各自的圆角、间距与材质。", 104.0);
    }
    if (section == 2) {
        return WCLiquidGlassFooterHeight(@"WCGlass iOS 27 兼容修复用于处理带键盘返回时的闪退；素材文件保护会阻止微信磁盘扫描删除未知素材，并保持 ThemePro 的删除与移动拦截规则。开关切换后立即生效。", 88.0);
    }
    return section == 3
        ? WCLiquidGlassFooterHeight(@"基础诊断始终开启且不记录聊天内容；日志可在“崩溃日志”中分享。", 64.0)
        : CGFLOAT_MIN;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"WCLiquidGlassSettingsCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
    }

    if (indexPath.section == 0 && indexPath.row == 0) {
        WCLiquidGlassConfigureCell(cell, @"启用全局菜单", nil,
                                   WCLiquidGlassSettingsIconImage(WCLiquidGlassSettingsIconKindMenu, 32.0), UIColor.labelColor);
        self.enabledSwitch = [[UISwitch alloc] init];
        self.enabledSwitch.on = WCLiquidGlassPreferences.enabled;
        [self.enabledSwitch addTarget:self action:@selector(wc_enabledChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = self.enabledSwitch;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (indexPath.section == 0 && indexPath.row == 1) {
        WCLiquidGlassConfigureCell(cell, @"按钮大小", [self wc_sizeModeTitle],
                                   WCLiquidGlassSettingsIconImage(WCLiquidGlassSettingsIconKindSize, 32.0), UIColor.labelColor);
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 0 && indexPath.row == 2) {
        WCLiquidGlassConfigureCell(cell, @"紧凑布局", [self wc_compactLayoutStyleTitle],
                                   WCLiquidGlassSettingsIconImage(WCLiquidGlassSettingsIconKindCompactLayout, 32.0), UIColor.labelColor);
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 0 && indexPath.row == 3) {
        WCLiquidGlassConfigureCell(cell, @"菜单样式", [self wc_menuStyleTitle],
                                   WCLiquidGlassSettingsIconImage(WCLiquidGlassSettingsIconKindMenu, 32.0), UIColor.labelColor);
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 0 && indexPath.row == 4) {
        WCLiquidGlassConfigureCell(cell, @"面板菜单大小", [self wc_menuElementSizeTitle],
                                   WCLiquidGlassSettingsIconImage(WCLiquidGlassSettingsIconKindSize, 32.0), UIColor.labelColor);
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 0 && indexPath.row == 5) {
        WCLiquidGlassConfigureCell(cell, @"悬浮按钮轨迹", [self wc_floatingMenuStrategyTitle],
                                   WCLiquidGlassSettingsIconImage(WCLiquidGlassSettingsIconKindMenu, 32.0), UIColor.labelColor);
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 0) {
        WCLiquidGlassConfigureCell(cell, @"液态效果", [self wc_glassAppearanceTitle],
                                   WCLiquidGlassSettingsIconImage(WCLiquidGlassSettingsIconKindGlassAppearance, 32.0), UIColor.labelColor);
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 1 && indexPath.row == 0) {
        NSString *count = [NSString stringWithFormat:@"%lu 个槽位", (unsigned long)WCLiquidGlassPreferences.buttonItems.count];
        WCLiquidGlassConfigureCell(cell, @"按钮与动作", count,
                                   WCLiquidGlassSettingsIconImage(WCLiquidGlassSettingsIconKindActions, 32.0), UIColor.labelColor);
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 1 && indexPath.row == 1) {
        WCLiquidGlassConfigureCell(cell, @"聊天时间条液态", nil,
                                   WCLiquidGlassSettingsIconImage(WCLiquidGlassSettingsIconKindGlassAppearance, 32.0), UIColor.labelColor);
        self.chatTimeGlassSwitch = [[UISwitch alloc] init];
        self.chatTimeGlassSwitch.on = WCLiquidGlassPreferences.chatTimeGlassEnabled;
        [self.chatTimeGlassSwitch addTarget:self action:@selector(wc_chatTimeGlassChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = self.chatTimeGlassSwitch;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (indexPath.section == 1 && indexPath.row == 2) {
        WCLiquidGlassConfigureCell(cell, @"长按菜单液态", nil,
                                   WCLiquidGlassSettingsIconImage(WCLiquidGlassSettingsIconKindGlassAppearance, 32.0), UIColor.labelColor);
        self.wcGlassLongPressMenuSwitch = [[UISwitch alloc] init];
        self.wcGlassLongPressMenuSwitch.on = WCLiquidGlassPreferences.wcGlassLongPressMenuEnabled;
        [self.wcGlassLongPressMenuSwitch addTarget:self action:@selector(wc_wcGlassLongPressMenuChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = self.wcGlassLongPressMenuSwitch;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (indexPath.section == 1 && indexPath.row == 3) {
        WCLiquidGlassConfigureCell(cell, @"通讯录索引液态", nil,
                                   WCLiquidGlassSettingsIconImage(WCLiquidGlassSettingsIconKindGlassAppearance, 32.0), UIColor.labelColor);
        self.contactsIndexGlassSwitch = [[UISwitch alloc] init];
        self.contactsIndexGlassSwitch.on = WCLiquidGlassPreferences.contactsIndexGlassEnabled;
        [self.contactsIndexGlassSwitch addTarget:self action:@selector(wc_contactsIndexGlassChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = self.contactsIndexGlassSwitch;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (indexPath.section == 1 && indexPath.row == 4) {
        WCLiquidGlassConfigureCell(cell, @"未读消息提示液态", nil,
                                   WCLiquidGlassSettingsIconImage(WCLiquidGlassSettingsIconKindGlassAppearance, 32.0), UIColor.labelColor);
        self.unreadMessageTipGlassSwitch = [[UISwitch alloc] init];
        self.unreadMessageTipGlassSwitch.on = WCLiquidGlassPreferences.unreadMessageTipGlassEnabled;
        [self.unreadMessageTipGlassSwitch addTarget:self action:@selector(wc_unreadMessageTipGlassChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = self.unreadMessageTipGlassSwitch;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (indexPath.section == 1 && indexPath.row == 5) {
        WCLiquidGlassConfigureCell(cell, @"左滑引用/复读消息", @"整行左滑，选择引用或复读",
                                   WCLiquidGlassSettingsIconImage(WCLiquidGlassSettingsIconKindActions, 32.0), UIColor.labelColor);
        self.messageSwipeActionsSwitch = [[UISwitch alloc] init];
        self.messageSwipeActionsSwitch.on = WCLiquidGlassPreferences.messageSwipeActionsEnabled;
        [self.messageSwipeActionsSwitch addTarget:self action:@selector(wc_messageSwipeActionsChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = self.messageSwipeActionsSwitch;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (indexPath.section == 1 && indexPath.row == 6) {
        WCLiquidGlassConfigureCell(cell, @"左滑菜单大小", [self wc_messageSwipeMenuElementSizeTitle],
                                   WCLiquidGlassSettingsIconImage(WCLiquidGlassSettingsIconKindSize, 32.0), UIColor.labelColor);
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 1 && indexPath.row == 7) {
        WCLiquidGlassConfigureCell(cell, @"通知圆角与液态", nil,
                                   WCLiquidGlassSettingsIconImage(WCLiquidGlassSettingsIconKindGlassAppearance, 32.0), UIColor.labelColor);
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 1) {
        WCLiquidGlassConfigureCell(cell, @"首页圆角与液态", nil,
                                   WCLiquidGlassSettingsIconImage(WCLiquidGlassSettingsIconKindGlassAppearance, 32.0), UIColor.labelColor);
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 2 && indexPath.row == 0) {
        WCLiquidGlassConfigureCell(cell, @"WCGlass iOS 27 兼容修复", @"修复带键盘返回时的闪退",
                                   WCLiquidGlassSettingsIconImage(WCLiquidGlassSettingsIconKindCompatibility, 32.0), UIColor.labelColor);
        UISwitch *wcGlassCompatibilitySwitch = [[UISwitch alloc] init];
        wcGlassCompatibilitySwitch.on = WCLiquidGlassPreferences.wcGlassIOS27CompatibilityEnabled;
        [wcGlassCompatibilitySwitch addTarget:self action:@selector(wc_wcGlassCompatibilityChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = wcGlassCompatibilitySwitch;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (indexPath.section == 2) {
        WCLiquidGlassConfigureCell(cell, @"素材文件保护", @"保护未知素材，阻止删除与移动清理",
                                   WCLiquidGlassSettingsIconImage(WCLiquidGlassSettingsIconKindCompatibility, 32.0), UIColor.labelColor);
        self.materialFileProtectionSwitch = [[UISwitch alloc] init];
        self.materialFileProtectionSwitch.on = WCLiquidGlassPreferences.materialFileProtectionEnabled;
        [self.materialFileProtectionSwitch addTarget:self action:@selector(wc_materialFileProtectionChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = self.materialFileProtectionSwitch;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (indexPath.section == 3 && indexPath.row == 0) {
        WCLiquidGlassConfigureCell(cell, @"完整崩溃采集", @"重启微信后生效",
                                   WCLiquidGlassSettingsIconImage(WCLiquidGlassSettingsIconKindCrashCapture, 32.0), UIColor.labelColor);
        self.fullCrashReportsSwitch = [[UISwitch alloc] init];
        self.fullCrashReportsSwitch.on = WCLiquidGlassPreferences.fullCrashReportsEnabled;
        [self.fullCrashReportsSwitch addTarget:self action:@selector(wc_fullCrashReportsChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = self.fullCrashReportsSwitch;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (indexPath.section == 3 && indexPath.row == 1) {
        NSUInteger count = WCLiquidGlassCrashLogger.sharedLogger.crashLogURLs.count;
        NSString *detail = count > 0 ? [NSString stringWithFormat:@"%lu 份", (unsigned long)count] : @"暂无日志";
        WCLiquidGlassConfigureCell(cell, @"崩溃日志", detail,
                                   WCLiquidGlassSettingsIconImage(WCLiquidGlassSettingsIconKindCrashLogs, 32.0), UIColor.labelColor);
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        WCLiquidGlassConfigureCell(cell, @"恢复默认设置", nil,
                                   WCLiquidGlassSettingsIconImage(WCLiquidGlassSettingsIconKindRestore, 32.0), UIColor.systemRedColor);
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0 && indexPath.row == 1) {
        [self wc_presentSizePickerFromView:[tableView cellForRowAtIndexPath:indexPath]];
    } else if (indexPath.section == 0 && indexPath.row == 2) {
        [self wc_presentCompactLayoutPickerFromView:[tableView cellForRowAtIndexPath:indexPath]];
    } else if (indexPath.section == 0 && indexPath.row == 3) {
        [self wc_presentMenuStylePickerFromView:[tableView cellForRowAtIndexPath:indexPath]];
    } else if (indexPath.section == 0 && indexPath.row == 4) {
        [self wc_presentMenuElementSizePickerFromView:[tableView cellForRowAtIndexPath:indexPath]];
    } else if (indexPath.section == 0 && indexPath.row == 5) {
        [self wc_presentFloatingMenuStrategyPickerFromView:[tableView cellForRowAtIndexPath:indexPath]];
    } else if (indexPath.section == 0 && indexPath.row == 6) {
        [self.navigationController pushViewController:[[WCLiquidGlassGlassAppearanceController alloc] init] animated:YES];
    } else if (indexPath.section == 1 && indexPath.row == 0) {
        [self.navigationController pushViewController:[[WCLiquidGlassButtonEditorController alloc] init] animated:YES];
    } else if (indexPath.section == 1 && indexPath.row == 6) {
        [self wc_presentMessageSwipeMenuElementSizePickerFromView:[tableView cellForRowAtIndexPath:indexPath]];
    } else if (indexPath.section == 1 && indexPath.row == 7) {
        [self.navigationController pushViewController:[[WCLiquidGlassMessageNotificationSettingsController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
    } else if (indexPath.section == 1 && indexPath.row == 8) {
        [self.navigationController pushViewController:[[WCLiquidGlassHomeCornersController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES];
    } else if (indexPath.section == 3 && indexPath.row == 1) {
        [self.navigationController pushViewController:[[WCLiquidGlassCrashLogsController alloc] init] animated:YES];
    } else if (indexPath.section == 4) {
        [self wc_confirmRestore];
    }
}

- (void)wc_enabledChanged:(UISwitch *)sender {
    [WCLiquidGlassPreferences setEnabled:sender.isOn];
}

- (void)wc_chatTimeGlassChanged:(UISwitch *)sender {
    [WCLiquidGlassPreferences setChatTimeGlassEnabled:sender.isOn];
}

- (void)wc_contactsIndexGlassChanged:(UISwitch *)sender {
    [WCLiquidGlassPreferences setContactsIndexGlassEnabled:sender.isOn];
}

- (void)wc_wcGlassLongPressMenuChanged:(UISwitch *)sender {
    [WCLiquidGlassPreferences setWCGlassLongPressMenuEnabled:sender.isOn];
}

- (void)wc_unreadMessageTipGlassChanged:(UISwitch *)sender {
    [WCLiquidGlassPreferences setUnreadMessageTipGlassEnabled:sender.isOn];
}

- (void)wc_messageSwipeActionsChanged:(UISwitch *)sender {
    [WCLiquidGlassPreferences setMessageSwipeActionsEnabled:sender.isOn];
}

- (void)wc_fullCrashReportsChanged:(UISwitch *)sender {
    [WCLiquidGlassPreferences setFullCrashReportsEnabled:sender.isOn];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"重启微信后生效"
                                                                   message:sender.isOn
                                                                        ? @"完整崩溃采集会在下次启动微信时启用。它能提供更完整的原生崩溃信息，但可能与其他崩溃采集插件竞争异常处理权。"
                                                                        : @"完整崩溃采集会在下次启动微信时关闭；基础 Objective-C 异常诊断仍会保留。"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)wc_wcGlassCompatibilityChanged:(UISwitch *)sender {
    [WCLiquidGlassPreferences setWCGlassIOS27CompatibilityEnabled:sender.isOn];
}

- (void)wc_materialFileProtectionChanged:(UISwitch *)sender {
    [WCLiquidGlassPreferences setMaterialFileProtectionEnabled:sender.isOn];
}

- (NSString *)wc_sizeModeTitle {
    switch (WCLiquidGlassPreferences.sizeMode) {
        case 0:
            return @"紧凑 · 53pt";
        case 2:
            return @"大 · 66pt";
        default:
            return @"标准 · 60pt";
    }
}

- (NSString *)wc_compactLayoutStyleTitle {
    switch (WCLiquidGlassPreferences.compactLayoutStyle) {
        case WCLiquidGlassCompactLayoutStyleSCurve:
            return @"流动 S 弧";
        case WCLiquidGlassCompactLayoutStyleWideFan:
            return @"宽扇形";
        case WCLiquidGlassCompactLayoutStylePetalCluster:
            return @"花瓣环簇";
        default:
            return @"双层月牙";
    }
}

- (NSString *)wc_glassAppearanceTitle {
    return WCLiquidGlassGlassAppearanceTitle(WCLiquidGlassPreferences.glassAppearance);
}

- (NSString *)wc_menuStyleTitle {
    return WCLiquidGlassPreferences.menuStyle == WCLiquidGlassMenuStyleLiquidPanel
        ? @"液态面板"
        : @"环形菜单";
}

- (NSString *)wc_menuElementSizeTitle {
    switch (WCLiquidGlassPreferences.menuElementSize) {
        case WCLiquidGlassMenuElementSizeSmall:
            return @"Small";
        case WCLiquidGlassMenuElementSizeMedium:
            return @"Medium";
        case WCLiquidGlassMenuElementSizeLarge:
            return @"Large";
        default:
            return @"Automatic";
    }
}

- (NSString *)wc_messageSwipeMenuElementSizeTitle {
    switch (WCLiquidGlassPreferences.messageSwipeMenuElementSize) {
        case WCLiquidGlassMenuElementSizeSmall:
            return @"Small";
        case WCLiquidGlassMenuElementSizeMedium:
            return @"Medium";
        case WCLiquidGlassMenuElementSizeLarge:
            return @"Large";
        default:
            return @"Automatic";
    }
}

- (NSString *)wc_floatingMenuStrategyTitle {
    return WCLiquidGlassPreferences.floatingMenuStrategy == WCLiquidGlassFloatingMenuStrategyPreflightSpring
        ? @"点击时先自动归位"
        : @"隐藏位置直接打开菜单";
}

- (void)wc_presentSizePickerFromView:(UIView *)sourceView {
    UIAlertController *picker = [UIAlertController alertControllerWithTitle:@"按钮大小"
                                                                     message:nil
                                                              preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray<NSString *> *titles = @[@"紧凑 · 53pt", @"标准 · 60pt", @"大 · 66pt"];
    [titles enumerateObjectsUsingBlock:^(NSString *title, NSUInteger index, __unused BOOL *stop) {
        UIAlertAction *action = [UIAlertAction actionWithTitle:title
                                                        style:UIAlertActionStyleDefault
                                                      handler:^(__unused UIAlertAction *selectedAction) {
            [WCLiquidGlassPreferences setSizeMode:index];
        }];
        [picker addAction:action];
    }];
    [picker addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    picker.popoverPresentationController.sourceView = sourceView;
    picker.popoverPresentationController.sourceRect = sourceView.bounds;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)wc_presentCompactLayoutPickerFromView:(UIView *)sourceView {
    UIAlertController *picker = [UIAlertController alertControllerWithTitle:@"紧凑布局"
                                                                     message:@"菜单空间不足时自动采用；所有样式都会保留胶黏动画所需的按钮间距。"
                                                              preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray<NSString *> *titles = @[@"双层月牙", @"流动 S 弧", @"宽扇形", @"花瓣环簇"];
    [titles enumerateObjectsUsingBlock:^(NSString *title, NSUInteger index, __unused BOOL *stop) {
        UIAlertAction *action = [UIAlertAction actionWithTitle:title
                                                        style:UIAlertActionStyleDefault
                                                      handler:^(__unused UIAlertAction *selectedAction) {
            [WCLiquidGlassPreferences setCompactLayoutStyle:(WCLiquidGlassCompactLayoutStyle)index];
        }];
        [picker addAction:action];
    }];
    [picker addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    picker.popoverPresentationController.sourceView = sourceView;
    picker.popoverPresentationController.sourceRect = sourceView.bounds;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)wc_presentMenuStylePickerFromView:(UIView *)sourceView {
    UIAlertController *picker = [UIAlertController alertControllerWithTitle:@"菜单样式"
                                                                     message:@"环形菜单仅显示图标；液态面板使用系统 Liquid Glass 菜单。"
                                                              preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray<NSString *> *titles = @[@"环形菜单", @"液态面板"];
    [titles enumerateObjectsUsingBlock:^(NSString *title, NSUInteger index, __unused BOOL *stop) {
        [picker addAction:[UIAlertAction actionWithTitle:title
                                                    style:UIAlertActionStyleDefault
                                                  handler:^(__unused UIAlertAction *action) {
            [WCLiquidGlassPreferences setMenuStyle:(WCLiquidGlassMenuStyle)index];
        }]];
    }];
    [picker addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    picker.popoverPresentationController.sourceView = sourceView;
    picker.popoverPresentationController.sourceRect = sourceView.bounds;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)wc_presentMenuElementSizePickerFromView:(UIView *)sourceView {
    UIAlertController *picker = [UIAlertController alertControllerWithTitle:@"面板菜单大小"
                                                                     message:@"仅影响液态面板样式的原生菜单。"
                                                              preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray<NSString *> *titles = @[@"Small", @"Medium", @"Large", @"Automatic"];
    [titles enumerateObjectsUsingBlock:^(NSString *title, NSUInteger index, __unused BOOL *stop) {
        [picker addAction:[UIAlertAction actionWithTitle:title
                                                    style:UIAlertActionStyleDefault
                                                  handler:^(__unused UIAlertAction *action) {
            [WCLiquidGlassPreferences setMenuElementSize:(WCLiquidGlassMenuElementSize)index];
        }]];
    }];
    [picker addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    picker.popoverPresentationController.sourceView = sourceView;
    picker.popoverPresentationController.sourceRect = sourceView.bounds;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)wc_presentMessageSwipeMenuElementSizePickerFromView:(UIView *)sourceView {
    UIAlertController *picker = [UIAlertController alertControllerWithTitle:@"左滑菜单大小"
                                                                     message:@"仅影响左滑“引用 / 复读”的原生液态面板。"
                                                              preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray<NSString *> *titles = @[@"Small", @"Medium", @"Large", @"Automatic"];
    [titles enumerateObjectsUsingBlock:^(NSString *title, NSUInteger index, __unused BOOL *stop) {
        [picker addAction:[UIAlertAction actionWithTitle:title
                                                    style:UIAlertActionStyleDefault
                                                  handler:^(__unused UIAlertAction *action) {
            [WCLiquidGlassPreferences setMessageSwipeMenuElementSize:(WCLiquidGlassMenuElementSize)index];
        }]];
    }];
    [picker addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    picker.popoverPresentationController.sourceView = sourceView;
    picker.popoverPresentationController.sourceRect = sourceView.bounds;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)wc_presentFloatingMenuStrategyPickerFromView:(UIView *)sourceView {
    UIAlertController *picker = [UIAlertController alertControllerWithTitle:@"悬浮按钮轨迹"
                                                                     message:@"仅影响液态面板的悬浮按钮隐藏、归位与菜单命中方式。"
                                                              preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray<NSString *> *titles = @[@"隐藏位置直接打开菜单", @"点击时先自动归位"];
    [titles enumerateObjectsUsingBlock:^(NSString *title, NSUInteger index, __unused BOOL *stop) {
        [picker addAction:[UIAlertAction actionWithTitle:title
                                                    style:UIAlertActionStyleDefault
                                                  handler:^(__unused UIAlertAction *action) {
            [WCLiquidGlassPreferences setFloatingMenuStrategy:(WCLiquidGlassFloatingMenuStrategy)index];
        }]];
    }];
    [picker addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    picker.popoverPresentationController.sourceView = sourceView;
    picker.popoverPresentationController.sourceRect = sourceView.bounds;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)wc_confirmRestore {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"恢复默认设置？"
                                                                   message:@"开关、菜单样式与大小、按钮大小、紧凑布局、入口位置、按钮动作、素材保护、兼容性和诊断选项都会恢复。"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"恢复"
                                             style:UIAlertActionStyleDestructive
                                           handler:^(__unused UIAlertAction *action) {
        [WCLiquidGlassPreferences restoreDefaults];
        [self.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)wc_preferencesChanged:(NSNotification *)notification {
    self.tableView.tableHeaderView = [self wc_makeHeaderView];
    [self.tableView reloadData];
}

@end
