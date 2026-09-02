#import "WCLiquidGlassFloatingTabBar.h"

#import "WCLiquidGlassCrashLogger.h"
#import "WCLiquidGlassMenu.h"
#import "WCLiquidGlassPreferences.h"
#import "WCLiquidGlassWCGlassSearchTabBar.h"

#import <CydiaSubstrate.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <stdlib.h>

static const CGFloat WCLiquidGlassFloatingTabBarCollapsedHeight = 90.0;
static const CGFloat WCLiquidGlassFloatingTabBarSheetChromeHeight = 120.0;
static const CGFloat WCLiquidGlassFloatingTabBarMinimumExpandedHeight = 240.0;

static __weak UITabBar *WCLiquidGlassFloatingTabBarTrackedTabBar;
static BOOL WCLiquidGlassFloatingTabBarHooksInstalled;
static BOOL WCLiquidGlassFloatingTabBarRetryScheduled;
static NSUInteger WCLiquidGlassFloatingTabBarInstallAttempts;

static void (*WCLiquidGlassFloatingTabBarOriginalViewDidAppear)(UIViewController *, SEL, BOOL);
static void (*WCLiquidGlassFloatingTabBarOriginalViewDidDisappear)(UIViewController *, SEL, BOOL);
static void (*WCLiquidGlassFloatingTabBarOriginalSetSelectedIndex)(UITabBarController *, SEL, NSInteger);
static void (*WCLiquidGlassFloatingTabBarOriginalSetSelectedViewController)(UITabBarController *, SEL, UIViewController *);
static void (*WCLiquidGlassFloatingTabBarOriginalLayoutSubviews)(UITabBar *, SEL);
static void (*WCLiquidGlassFloatingTabBarOriginalSetHidden)(UITabBar *, SEL, BOOL);
static void (*WCLiquidGlassFloatingTabBarOriginalSetFrame)(UITabBar *, SEL, CGRect);
static void (*WCLiquidGlassFloatingTabBarOriginalDidMoveToWindow)(UITabBar *, SEL);

@class WCLiquidGlassFloatingNativeTabBar;

@interface WCLiquidGlassFloatingTabBarController ()
- (void)wc_hideNativeSubviews:(UITabBar *)tabBar;
- (void)wc_restoreNativeSubviews:(UITabBar *)tabBar;
@end

static id WCLiquidGlassFloatingTabBarObjectValue(id target, SEL selector) {
    if (!target || !selector || ![target respondsToSelector:selector]) {
        return nil;
    }
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(target, selector);
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static NSArray *WCLiquidGlassFloatingTabBarViewControllers(id tabController) {
    id value = WCLiquidGlassFloatingTabBarObjectValue(tabController,
                                                       @selector(viewControllers));
    return [value isKindOfClass:NSArray.class] ? value : nil;
}

static UITabBar *WCLiquidGlassFloatingTabBarForController(id tabController) {
    if ([tabController isKindOfClass:UITabBarController.class]) {
        return ((UITabBarController *)tabController).tabBar;
    }
    id tabBar = WCLiquidGlassFloatingTabBarObjectValue(tabController, @selector(tabBar));
    return [tabBar isKindOfClass:UITabBar.class] ? tabBar : nil;
}

static CGFloat WCLiquidGlassFloatingTabBarClamp(CGFloat value, CGFloat minimum, CGFloat maximum) {
    return MIN(maximum, MAX(minimum, value));
}

static BOOL WCLiquidGlassFloatingTabBarShouldObserve(UITabBar *tabBar);

static void WCLiquidGlassFloatingTabBarHideNativeSubviews(UITabBar *tabBar) {
    if (!tabBar) {
        return;
    }
    WCLiquidGlassFloatingTabBarController *controller =
        WCLiquidGlassFloatingTabBarController.sharedController;
    [controller wc_hideNativeSubviews:tabBar];
}

static void WCLiquidGlassFloatingTabBarRestoreNativeSubviews(UITabBar *tabBar) {
    WCLiquidGlassFloatingTabBarController *controller =
        WCLiquidGlassFloatingTabBarController.sharedController;
    [controller wc_restoreNativeSubviews:tabBar];
}

@interface WCLiquidGlassFloatingTabBarWindow : UIWindow
@property(nonatomic, weak) UIView *hostView;
@end

@implementation WCLiquidGlassFloatingTabBarWindow

- (BOOL)canBecomeKeyWindow {
    return NO;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    if (hitView == self || hitView == self.rootViewController.view || hitView == self.hostView) {
        return nil;
    }
    return hitView;
}

@end

@interface WCLiquidGlassFloatingTabBarTile : UIControl
@property(nonatomic, copy) NSString *actionIdentifier;
@end

@implementation WCLiquidGlassFloatingTabBarTile

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = highlighted ? 0.6 : 1.0;
}

@end

@class WCLiquidGlassFloatingTabBarHostView;

@interface WCLiquidGlassFloatingNativeTabBar : UITabBar
@property(nonatomic, weak) WCLiquidGlassFloatingTabBarHostView *host;
- (void)wc_fixLabelsInView:(UIView *)view;
@end

static BOOL WCLiquidGlassFloatingTabBarShouldObserve(UITabBar *tabBar) {
    return tabBar == WCLiquidGlassFloatingTabBarTrackedTabBar ||
        (!WCLiquidGlassFloatingTabBarTrackedTabBar &&
         ![tabBar isKindOfClass:WCLiquidGlassFloatingNativeTabBar.class]);
}

@interface WCLiquidGlassFloatingTabBarHostView : UIView <UITabBarDelegate,
                                                          UIGestureRecognizerDelegate>
@property(nonatomic, weak) WCLiquidGlassFloatingTabBarController *controller;
@property(nonatomic, strong) UIControl *dismissControl;
@property(nonatomic, strong) UIView *sheetView;
@property(nonatomic, strong) UIVisualEffectView *backgroundView;
@property(nonatomic, strong) UIView *separatorView;
@property(nonatomic, strong) UIView *grabberView;
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UIScrollView *scrollView;
@property(nonatomic, strong) UIStackView *gridStack;
@property(nonatomic, strong) UILabel *emptyLabel;
@property(nonatomic, strong) WCLiquidGlassFloatingNativeTabBar *tabBar;
@property(nonatomic, strong) UIPanGestureRecognizer *panGestureRecognizer;
@property(nonatomic, copy) NSArray<NSString *> *actionIdentifiers;
@property(nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *actionItems;
@property(nonatomic, assign) CGFloat sheetHeight;
@property(nonatomic, assign) CGFloat expandedHeight;
@property(nonatomic, assign) CGFloat startHeight;
@property(nonatomic, assign) CGFloat visibilityProgress;
@property(nonatomic, assign) CGFloat detentProgress;
@property(nonatomic, assign) CGFloat positionProgress;
@property(nonatomic, assign) BOOL appInactive;
@property(nonatomic, assign) BOOL expanded;
- (instancetype)initWithController:(WCLiquidGlassFloatingTabBarController *)controller;
- (void)wc_updateForTabController:(id)tabController tabBar:(UITabBar *)tabBar;
- (void)wc_collapseImmediately;
- (void)wc_collapseAnimated;
- (void)wc_applyTabBarBackgroundOpacity;
@end

@implementation WCLiquidGlassFloatingNativeTabBar

- (void)layoutSubviews {
    [super layoutSubviews];
    [self.host wc_applyTabBarBackgroundOpacity];
    [self wc_fixLabelsInView:self];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self.host wc_applyTabBarBackgroundOpacity];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.host wc_applyTabBarBackgroundOpacity];
    });
}

- (void)wc_fixLabelsInView:(UIView *)view {
    for (UIView *subview in view.subviews) {
        NSString *className = NSStringFromClass(subview.class);
        if ([subview isKindOfClass:UILabel.class] && [className containsString:@"Label"]) {
            subview.hidden = NO;
            if (CGRectGetHeight(subview.frame) == 0.0) {
                CGRect frame = subview.frame;
                frame.origin.y = 37.0;
                frame.size.height = 16.0;
                subview.frame = frame;
            }
        }
        [self wc_fixLabelsInView:subview];
    }
}

@end

@implementation WCLiquidGlassFloatingTabBarHostView

- (instancetype)initWithController:(WCLiquidGlassFloatingTabBarController *)controller {
    self = [super initWithFrame:CGRectZero];
    if (!self) {
        return nil;
    }
    _controller = controller;
    _sheetHeight = WCLiquidGlassFloatingTabBarCollapsedHeight;
    _expandedHeight = WCLiquidGlassFloatingTabBarMinimumExpandedHeight;
    _actionIdentifiers = @[];
    _actionItems = @[];
    self.backgroundColor = UIColor.clearColor;

    _dismissControl = [UIControl new];
    _dismissControl.hidden = YES;
    [_dismissControl addTarget:self
                        action:@selector(wc_dismissTapped:)
              forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_dismissControl];

    _sheetView = [UIView new];
    _sheetView.clipsToBounds = NO;
    _sheetView.backgroundColor = UIColor.clearColor;
    [self addSubview:_sheetView];

    _backgroundView = [[UIVisualEffectView alloc] initWithEffect:WCLiquidGlassCurrentGlassEffect()];
    _backgroundView.clipsToBounds = YES;
    _backgroundView.backgroundColor = UIColor.clearColor;
    [_sheetView addSubview:_backgroundView];

    _separatorView = [UIView new];
    _separatorView.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:1.0 alpha:0.18]
            : [UIColor colorWithWhite:0.0 alpha:0.12];
    }];
    _separatorView.hidden = NSClassFromString(@"UIGlassEffect") != Nil;
    [_backgroundView addSubview:_separatorView];

    _grabberView = [UIView new];
    _grabberView.backgroundColor = UIColor.tertiaryLabelColor;
    _grabberView.layer.cornerRadius = 2.5;
    [_sheetView addSubview:_grabberView];

    _titleLabel = [UILabel new];
    _titleLabel.text = @"快捷动作";
    _titleLabel.font = [UIFont systemFontOfSize:22.0 weight:UIFontWeightBold];
    _titleLabel.textColor = UIColor.labelColor;
    [_sheetView addSubview:_titleLabel];

    _scrollView = [UIScrollView new];
    _scrollView.showsVerticalScrollIndicator = NO;
    _scrollView.alwaysBounceVertical = NO;
    _scrollView.backgroundColor = UIColor.clearColor;
    [_sheetView addSubview:_scrollView];

    _gridStack = [[UIStackView alloc] initWithFrame:CGRectZero];
    _gridStack.axis = UILayoutConstraintAxisVertical;
    _gridStack.spacing = 12.0;
    _gridStack.distribution = UIStackViewDistributionFillEqually;
    [_scrollView addSubview:_gridStack];

    _emptyLabel = [UILabel new];
    _emptyLabel.text = @"请先在“按钮与动作”中启用动作";
    _emptyLabel.textColor = UIColor.secondaryLabelColor;
    _emptyLabel.textAlignment = NSTextAlignmentCenter;
    _emptyLabel.numberOfLines = 0;
    [_scrollView addSubview:_emptyLabel];

    _tabBar = [WCLiquidGlassFloatingNativeTabBar new];
    _tabBar.host = self;
    _tabBar.delegate = self;
    _tabBar.translucent = YES;
    _tabBar.backgroundImage = [UIImage new];
    _tabBar.shadowImage = [UIImage new];
    _tabBar.backgroundColor = UIColor.clearColor;
    _tabBar.tintColor = [UIColor colorWithRed:0.027 green:0.757 blue:0.376 alpha:1.0];
    if (@available(iOS 13.0, *)) {
        UITabBarAppearance *appearance = [UITabBarAppearance new];
        [appearance configureWithTransparentBackground];
        appearance.backgroundColor = UIColor.clearColor;
        appearance.backgroundEffect = nil;
        appearance.shadowColor = UIColor.clearColor;
        _tabBar.standardAppearance = appearance;
        _tabBar.scrollEdgeAppearance = appearance;
    }
    [_sheetView addSubview:_tabBar];

    UITapGestureRecognizer *grabberTap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(wc_grabberTapped:)];
    grabberTap.cancelsTouchesInView = NO;
    [_sheetView addGestureRecognizer:grabberTap];
    _panGestureRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                      action:@selector(wc_pan:)];
    _panGestureRecognizer.delegate = self;
    [_sheetView addGestureRecognizer:_panGestureRecognizer];
    return self;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self wc_refreshEffects];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat height = CGRectGetHeight(self.bounds);
    CGFloat sheetHeight = WCLiquidGlassFloatingTabBarClamp(self.sheetHeight,
                                                            WCLiquidGlassFloatingTabBarCollapsedHeight - 24.0,
                                                            MAX(WCLiquidGlassFloatingTabBarCollapsedHeight,
                                                                self.expandedHeight + 24.0));
    self.visibilityProgress = WCLiquidGlassFloatingTabBarClamp((sheetHeight - 125.0) / 100.0, 0.0, 1.0);
    self.detentProgress = WCLiquidGlassFloatingTabBarClamp((sheetHeight - 90.0) / 294.0, 0.0, 1.0);
    self.positionProgress = WCLiquidGlassFloatingTabBarClamp((sheetHeight - 384.0) / 428.0, 0.0, 1.0);

    self.dismissControl.frame = self.bounds;
    self.dismissControl.hidden = !self.expanded;
    self.dismissControl.enabled = self.expanded;
    self.sheetView.frame = CGRectMake(0.0, height - sheetHeight, width, sheetHeight + 100.0);
    self.backgroundView.frame = self.sheetView.bounds;
    CGFloat cornerRadius = [self wc_screenCornerRadius];
    self.backgroundView.layer.cornerRadius = cornerRadius;
    self.backgroundView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    self.separatorView.frame = CGRectMake(0.0, 0.0, width, 1.0);
    self.grabberView.frame = CGRectMake((width - 36.0) / 2.0, 5.0, 36.0, 5.0);
    self.titleLabel.frame = CGRectMake(20.0, 24.0, MAX(0.0, width - 40.0), 28.0);
    self.titleLabel.alpha = self.visibilityProgress;
    CGFloat scrollHeight = MAX(0.0, sheetHeight - 150.0);
    self.scrollView.frame = CGRectMake(0.0, 60.0, width, scrollHeight);
    CGFloat gridWidth = MAX(0.0, width - 40.0);
    CGFloat gridHeight = [self.gridStack systemLayoutSizeFittingSize:CGSizeMake(gridWidth,
                                                                                UILayoutFittingCompressedSize.height)].height;
    self.gridStack.frame = CGRectMake(20.0, 12.0, gridWidth, gridHeight);
    self.scrollView.contentSize = CGSizeMake(width, gridHeight + 24.0);
    self.emptyLabel.frame = CGRectMake(20.0, 12.0, gridWidth, MAX(44.0, scrollHeight - 24.0));
    self.emptyLabel.hidden = self.actionItems.count > 0;
    self.gridStack.hidden = self.actionItems.count == 0;
    self.gridStack.alpha = self.visibilityProgress;
    self.emptyLabel.alpha = self.visibilityProgress;
    CGFloat offset = 3.0 + 9.0 * self.detentProgress - 11.0 * self.positionProgress;
    self.tabBar.frame = CGRectMake(0.0, sheetHeight - 90.0 + offset, width, 90.0);
    self.tabBar.alpha = 1.0;
    [self wc_applyTabBarBackgroundOpacity];
}

- (CGFloat)wc_screenCornerRadius {
    CGFloat radius = 38.0;
    @try {
        radius = [UIScreen.mainScreen valueForKey:@"_displayCornerRadius"] ?
            [[UIScreen.mainScreen valueForKey:@"_displayCornerRadius"] doubleValue] : radius;
    } @catch (__unused NSException *exception) {
    }
    return radius > 0.0 ? radius : 12.0;
}

- (void)wc_refreshEffects {
    self.backgroundView.effect = WCLiquidGlassCurrentGlassEffect();
    for (UIView *view in self.gridStack.arrangedSubviews) {
        if ([view isKindOfClass:WCLiquidGlassFloatingTabBarTile.class]) {
            UIVisualEffectView *effectView = (UIVisualEffectView *)view.subviews.firstObject;
            if ([effectView isKindOfClass:UIVisualEffectView.class]) {
                effectView.effect = WCLiquidGlassGlassEffectForAppearance(WCLiquidGlassGlassAppearanceTinted);
            }
        }
    }
}

- (void)wc_applyTabBarBackgroundOpacity {
    if (self.tabBar.bounds.size.width <= 0.0) {
        return;
    }
    UIView *platter = nil;
    for (UIView *subview in self.tabBar.subviews) {
        if (CGRectGetWidth(subview.bounds) > CGRectGetWidth(self.tabBar.bounds) * 0.8 &&
            CGRectGetHeight(subview.bounds) > 50.0 &&
            CGRectGetHeight(subview.bounds) < CGRectGetHeight(self.tabBar.bounds)) {
            platter = subview;
            break;
        }
    }
    if (!platter) {
        return;
    }
    CGFloat opacity = self.appInactive ? 0.0 : self.visibilityProgress;
    if (!self.expanded && self.sheetHeight <= WCLiquidGlassFloatingTabBarCollapsedHeight + 0.5) {
        opacity = 0.0;
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self wc_applyOpacity:opacity
                  toLayer:self.tabBar.layer
               platterSize:platter.bounds.size];
    [CATransaction commit];
}

- (void)wc_applyOpacity:(CGFloat)opacity
                toLayer:(CALayer *)layer
             platterSize:(CGSize)size {
    NSString *name = NSStringFromClass(layer.class);
    if ([layer.name isEqualToString:@"MaterialProvider"]) {
        layer.opacity = 1.0;
        layer.hidden = self.appInactive && opacity == 0.0;
    }
    BOOL fullSize = layer.bounds.size.width > size.width * 0.8 &&
        layer.bounds.size.height > size.height * 0.8;
    if (fullSize && ([name containsString:@"Backdrop"] ||
                     [name containsString:@"SDF"] ||
                     [name containsString:@"Portal"])) {
        layer.opacity = (float)WCLiquidGlassFloatingTabBarClamp(opacity, 0.0, 1.0);
    }
    for (CALayer *sublayer in layer.sublayers.copy) {
        [self wc_applyOpacity:opacity toLayer:sublayer platterSize:size];
    }
}

- (void)wc_rebuildActionTilesIfNeeded {
    NSArray<NSDictionary<NSString *, id> *> *items = WCLiquidGlassFloatingTabBarActionItems();
    NSArray<NSString *> *identifiers = [items valueForKey:@"action"];
    if ([identifiers isEqualToArray:self.actionIdentifiers]) {
        return;
    }
    self.actionItems = items;
    self.actionIdentifiers = identifiers ?: @[];
    for (UIView *view in self.gridStack.arrangedSubviews) {
        [self.gridStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    for (NSUInteger index = 0; index < items.count; index += 3) {
        UIStackView *row = [[UIStackView alloc] initWithFrame:CGRectZero];
        row.axis = UILayoutConstraintAxisHorizontal;
        row.spacing = 12.0;
        row.distribution = UIStackViewDistributionFillEqually;
        for (NSUInteger column = 0; column < 3; column++) {
            NSUInteger itemIndex = index + column;
            if (itemIndex >= items.count) {
                UIView *spacer = [UIView new];
                spacer.backgroundColor = UIColor.clearColor;
                [row addArrangedSubview:spacer];
                continue;
            }
            NSDictionary<NSString *, id> *item = items[itemIndex];
            NSString *identifier = item[@"action"];
            WCLiquidGlassFloatingTabBarTile *tile = [WCLiquidGlassFloatingTabBarTile new];
            tile.actionIdentifier = identifier;
            tile.backgroundColor = UIColor.clearColor;
            tile.layer.cornerRadius = 18.0;
            tile.clipsToBounds = YES;
            UIVisualEffectView *effectView =
                [[UIVisualEffectView alloc] initWithEffect:WCLiquidGlassGlassEffectForAppearance(WCLiquidGlassGlassAppearanceTinted)];
            effectView.frame = tile.bounds;
            effectView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            effectView.layer.cornerRadius = 18.0;
            effectView.clipsToBounds = YES;
            [tile addSubview:effectView];
            UIStackView *content = [[UIStackView alloc] initWithFrame:CGRectZero];
            content.axis = UILayoutConstraintAxisVertical;
            content.spacing = 8.0;
            content.alignment = UIStackViewAlignmentCenter;
            content.translatesAutoresizingMaskIntoConstraints = NO;
            UIImageView *imageView = [[UIImageView alloc] initWithImage:WCLiquidGlassImageForAction(identifier, 56.0)];
            imageView.contentMode = UIViewContentModeScaleAspectFit;
            UIImage *image = imageView.image;
            if (image.renderingMode == UIImageRenderingModeAlwaysTemplate) {
                imageView.tintColor = UIColor.labelColor;
            }
            imageView.translatesAutoresizingMaskIntoConstraints = NO;
            [imageView.widthAnchor constraintEqualToConstant:28.0].active = YES;
            [imageView.heightAnchor constraintEqualToConstant:28.0].active = YES;
            UILabel *label = [UILabel new];
            label.text = WCLiquidGlassActionTitle(identifier);
            label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
            label.textColor = UIColor.labelColor;
            label.textAlignment = NSTextAlignmentCenter;
            label.numberOfLines = 1;
            [content addArrangedSubview:imageView];
            [content addArrangedSubview:label];
            [effectView.contentView addSubview:content];
            [NSLayoutConstraint activateConstraints:@[
                [content.leadingAnchor constraintGreaterThanOrEqualToAnchor:effectView.contentView.leadingAnchor constant:8.0],
                [content.trailingAnchor constraintLessThanOrEqualToAnchor:effectView.contentView.trailingAnchor constant:-8.0],
                [content.centerXAnchor constraintEqualToAnchor:effectView.contentView.centerXAnchor],
                [content.centerYAnchor constraintEqualToAnchor:effectView.contentView.centerYAnchor],
                [tile.heightAnchor constraintGreaterThanOrEqualToConstant:78.0]
            ]];
            [tile addTarget:self action:@selector(wc_tileTapped:) forControlEvents:UIControlEventTouchUpInside];
            [row addArrangedSubview:tile];
        }
        [self.gridStack addArrangedSubview:row];
    }
    [self setNeedsLayout];
}

- (void)wc_updateForTabController:(id)tabController tabBar:(UITabBar *)tabBar {
    if (!tabBar) {
        return;
    }
    NSArray *viewControllers = WCLiquidGlassFloatingTabBarViewControllers(tabController);
    NSUInteger count = MIN(4U, viewControllers.count);
    NSMutableArray<UITabBarItem *> *items = [NSMutableArray arrayWithCapacity:count];
    NSArray<NSString *> *defaults = @[@"微信", @"通讯录", @"发现", @"我"];
    NSArray<NSString *> *symbols = @[@"message.fill", @"person.2.fill", @"safari.fill", @"person.fill"];
    for (NSUInteger index = 0; index < count; index++) {
        UIViewController *viewController = [viewControllers[index] isKindOfClass:UIViewController.class]
            ? viewControllers[index] : nil;
        NSString *title = nil;
        @try {
            title = viewController.tabBarItem.title;
        } @catch (__unused NSException *exception) {
        }
        if (title.length == 0) {
            title = viewController.title;
        }
        if (title.length == 0) {
            title = defaults[index];
        }
        UIImage *image = WCLiquidGlassNativeTabImage(tabController, index);
        if (!image) {
            image = [UIImage systemImageNamed:symbols[index]];
        }
        UITabBarItem *item = [[UITabBarItem alloc] initWithTitle:title
                                                           image:image
                                                     selectedImage:image];
        item.tag = index;
        @try {
            item.badgeValue = viewController.tabBarItem.badgeValue;
        } @catch (__unused NSException *exception) {
        }
        [items addObject:item];
    }
    BOOL itemsChanged = self.tabBar.items.count != items.count;
    for (NSUInteger index = 0; !itemsChanged && index < items.count; index++) {
        UITabBarItem *oldItem = self.tabBar.items[index];
        UITabBarItem *newItem = items[index];
        itemsChanged = ![oldItem.title isEqualToString:newItem.title] ||
            ![oldItem.image isEqual:newItem.image] ||
            ![oldItem.selectedImage isEqual:newItem.selectedImage] ||
            ![oldItem.badgeValue isEqualToString:newItem.badgeValue];
    }
    if (itemsChanged) {
        self.tabBar.items = items;
    } else {
        for (NSUInteger index = 0; index < items.count; index++) {
            UITabBarItem *oldItem = self.tabBar.items[index];
            UITabBarItem *newItem = items[index];
            if (![oldItem.image isEqual:newItem.image] ||
                ![oldItem.title isEqualToString:newItem.title] ||
                ![oldItem.badgeValue isEqualToString:newItem.badgeValue]) {
                oldItem.title = newItem.title;
                oldItem.image = newItem.image;
                oldItem.selectedImage = newItem.selectedImage;
                oldItem.badgeValue = newItem.badgeValue;
            }
        }
    }
    NSInteger selectedIndex = WCLiquidGlassCurrentTabIndex(tabController);
    if (selectedIndex >= 0 && selectedIndex < (NSInteger)self.tabBar.items.count &&
        self.tabBar.selectedItem != self.tabBar.items[selectedIndex]) {
        [UIView performWithoutAnimation:^{
            self.tabBar.selectedItem = self.tabBar.items[selectedIndex];
        }];
    }
    [self wc_rebuildActionTilesIfNeeded];
    CGFloat gridHeight = [self.gridStack systemLayoutSizeFittingSize:CGSizeMake(MAX(1.0, CGRectGetWidth(self.bounds) - 40.0),
                                                                                 UILayoutFittingCompressedSize.height)].height + 24.0;
    CGFloat maximumHeight = MAX(WCLiquidGlassFloatingTabBarMinimumExpandedHeight,
                                CGRectGetHeight(self.bounds) * 0.85);
    self.expandedHeight = MIN(MAX(gridHeight + WCLiquidGlassFloatingTabBarSheetChromeHeight,
                                  WCLiquidGlassFloatingTabBarMinimumExpandedHeight),
                              maximumHeight);
    [self setNeedsLayout];
}

- (void)wc_setExpanded:(BOOL)expanded {
    self.expanded = expanded;
    self.dismissControl.hidden = !expanded;
    self.dismissControl.enabled = expanded;
}

- (void)setSheetHeight:(CGFloat)height {
    _sheetHeight = height;
    self.visibilityProgress = WCLiquidGlassFloatingTabBarClamp((height - 125.0) / 100.0, 0.0, 1.0);
    self.detentProgress = WCLiquidGlassFloatingTabBarClamp((height - 90.0) / 294.0, 0.0, 1.0);
    self.positionProgress = WCLiquidGlassFloatingTabBarClamp((height - 384.0) / 428.0, 0.0, 1.0);
    [self setNeedsLayout];
    [self layoutIfNeeded];
    [self wc_applyTabBarBackgroundOpacity];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self wc_applyTabBarBackgroundOpacity];
    });
}

- (void)wc_collapseImmediately {
    [self wc_setExpanded:NO];
    [self setSheetHeight:WCLiquidGlassFloatingTabBarCollapsedHeight];
}

- (void)wc_animateToHeight:(CGFloat)height {
    CGFloat target = height <= WCLiquidGlassFloatingTabBarCollapsedHeight + 0.5
        ? WCLiquidGlassFloatingTabBarCollapsedHeight : self.expandedHeight;
    BOOL changedDetent = (target > WCLiquidGlassFloatingTabBarCollapsedHeight) != self.expanded;
    [self wc_setExpanded:target > WCLiquidGlassFloatingTabBarCollapsedHeight];
    if (changedDetent) {
        UIImpactFeedbackGenerator *generator =
            [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [generator prepare];
        [generator impactOccurred];
    }
    [UIView animateWithDuration:0.45
                          delay:0.0
         usingSpringWithDamping:0.86
          initialSpringVelocity:0.0
                        options:UIViewAnimationOptionAllowUserInteraction |
                                UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        self.sheetHeight = target;
        [self layoutIfNeeded];
    } completion:nil];
}

- (void)wc_collapseAnimated {
    [self wc_animateToHeight:WCLiquidGlassFloatingTabBarCollapsedHeight];
}

- (void)wc_dismissTapped:(UIControl *)sender {
    [self wc_collapseAnimated];
}

- (void)wc_grabberTapped:(UITapGestureRecognizer *)gesture {
    CGPoint point = [gesture locationInView:self.sheetView];
    if (gesture.state == UIGestureRecognizerStateEnded && point.y <= 44.0) {
        [self wc_animateToHeight:self.expanded ? WCLiquidGlassFloatingTabBarCollapsedHeight
                                                : self.expandedHeight];
    }
}

- (void)wc_tileTapped:(WCLiquidGlassFloatingTabBarTile *)tile {
    NSString *identifier = tile.actionIdentifier;
    [self wc_collapseAnimated];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        WCLiquidGlassPerformActionIdentifier(identifier);
    });
}

- (void)wc_pan:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self];
    CGPoint velocity = [gesture velocityInView:self];
    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.startHeight = self.sheetHeight;
    } else if (gesture.state == UIGestureRecognizerStateChanged) {
        CGFloat value = self.startHeight - translation.y;
        CGFloat lower = WCLiquidGlassFloatingTabBarCollapsedHeight - 24.0;
        CGFloat upper = self.expandedHeight + 24.0;
        if (value < lower) {
            value = lower + (value - lower) * 0.3;
        } else if (value > upper) {
            value = upper + (value - upper) * 0.3;
        }
        [self wc_setExpanded:value > WCLiquidGlassFloatingTabBarCollapsedHeight + 1.0];
        [self setSheetHeight:value];
    } else if (gesture.state == UIGestureRecognizerStateEnded ||
               gesture.state == UIGestureRecognizerStateCancelled) {
        CGFloat predicted = self.sheetHeight - velocity.y * 0.15;
        CGFloat target = fabs(predicted - WCLiquidGlassFloatingTabBarCollapsedHeight) <
            fabs(predicted - self.expandedHeight)
            ? WCLiquidGlassFloatingTabBarCollapsedHeight : self.expandedHeight;
        [self wc_animateToHeight:target];
    }
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if ([gestureRecognizer isKindOfClass:UITapGestureRecognizer.class]) {
        return [gestureRecognizer locationInView:self.sheetView].y <= 44.0;
    }
    if (gestureRecognizer != self.panGestureRecognizer) {
        return YES;
    }
    CGPoint translation = [self.panGestureRecognizer translationInView:self.sheetView];
    if (fabs(translation.y) <= fabs(translation.x)) {
        return NO;
    }
    CGPoint point = [gestureRecognizer locationInView:self.sheetView];
    if (CGRectContainsPoint(self.scrollView.frame, point) &&
        self.scrollView.contentSize.height > self.scrollView.bounds.size.height) {
        UIPanGestureRecognizer *pan = (UIPanGestureRecognizer *)gestureRecognizer;
        CGPoint translation = [pan translationInView:self.sheetView];
        if (self.scrollView.contentOffset.y > 0.0 || translation.y < 0.0) {
            return NO;
        }
    }
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
        shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return NO;
}

- (void)tabBar:(UITabBar *)tabBar didSelectItem:(UITabBarItem *)item {
    id tabController = WCLiquidGlassCurrentTabController();
    NSInteger index = item.tag;
    NSInteger current = WCLiquidGlassCurrentTabIndex(tabController);
    if (index == current) {
        return;
    }
    if (!WCLiquidGlassCanSelectTab(tabController, index)) {
        self.tabBar.selectedItem = self.tabBar.items[current];
        return;
    }
    @try {
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(tabController,
                                                     @selector(setSelectedIndex:),
                                                     index);
        UIImpactFeedbackGenerator *generator =
            [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [generator impactOccurred];
    } @catch (__unused NSException *exception) {
        self.tabBar.selectedItem = self.tabBar.items[current];
    }
    [self.controller setNeedsUpdate];
}

@end

@interface WCLiquidGlassFloatingTabBarController ()
@property(nonatomic, strong) WCLiquidGlassFloatingTabBarWindow *window;
@property(nonatomic, strong) WCLiquidGlassFloatingTabBarHostView *hostView;
@property(nonatomic, strong) NSHashTable<UIView *> *hiddenNativeSubviews;
@property(nonatomic, assign) BOOL started;
@property(nonatomic, assign) BOOL updateScheduled;
@property(nonatomic, assign) BOOL appInactive;
@property(nonatomic, assign) BOOL lastBlockedState;
@property(nonatomic, assign) BOOL hasBlockedState;
@end

@implementation WCLiquidGlassFloatingTabBarController

+ (instancetype)sharedController {
    static WCLiquidGlassFloatingTabBarController *controller;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        controller = [self new];
    });
    return controller;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _hiddenNativeSubviews = [NSHashTable weakObjectsHashTable];
    }
    return self;
}

- (void)start {
    if (self.started) {
        return;
    }
    self.started = YES;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self
               selector:@selector(wc_preferencesChanged:)
                   name:WCLiquidGlassPreferencesDidChangeNotification
                 object:nil];
    [center addObserver:self
               selector:@selector(wc_applicationDidBecomeActive:)
                   name:UIApplicationDidBecomeActiveNotification
                 object:nil];
    [center addObserver:self
               selector:@selector(wc_applicationWillResignActive:)
                   name:UIApplicationWillResignActiveNotification
                 object:nil];
    [WCLiquidGlassCrashLogger.sharedLogger recordEvent:@"FloatingTabBar hooks installed"];
    [self setNeedsUpdate];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)setNeedsUpdate {
    if (self.updateScheduled) {
        return;
    }
    self.updateScheduled = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.updateScheduled = NO;
        [self wc_update];
    });
}

- (void)wc_preferencesChanged:(NSNotification *)notification {
    [self.hostView wc_refreshEffects];
    [self setNeedsUpdate];
}

- (void)wc_applicationDidBecomeActive:(NSNotification *)notification {
    self.appInactive = NO;
    self.hostView.appInactive = NO;
    [self.hostView wc_applyTabBarBackgroundOpacity];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.hostView wc_applyTabBarBackgroundOpacity];
    });
    [self setNeedsUpdate];
}

- (void)wc_applicationWillResignActive:(NSNotification *)notification {
    self.appInactive = YES;
    self.hostView.appInactive = YES;
    [self.hostView wc_collapseImmediately];
    [self.hostView wc_applyTabBarBackgroundOpacity];
    self.window.hidden = YES;
}

- (void)wc_hideNativeSubviews:(UITabBar *)tabBar {
    if (!tabBar) {
        return;
    }
    for (UIView *subview in tabBar.subviews.copy) {
        if (!subview.hidden) {
            subview.hidden = YES;
            [self.hiddenNativeSubviews addObject:subview];
        }
    }
}

- (void)wc_restoreNativeSubviews:(UITabBar *)tabBar {
    for (UIView *subview in self.hiddenNativeSubviews.allObjects) {
        if (subview.superview == tabBar) {
            subview.hidden = NO;
        }
    }
    [self.hiddenNativeSubviews removeAllObjects];
}

- (void)wc_ensureWindowForTabBar:(UITabBar *)tabBar {
    UIWindowScene *scene = tabBar.window.windowScene;
    if (!scene) {
        return;
    }
    if (self.window.windowScene != scene) {
        self.window.hidden = YES;
        self.window = nil;
        self.hostView = nil;
    }
    if (!self.window) {
        self.window = [[WCLiquidGlassFloatingTabBarWindow alloc] initWithWindowScene:scene];
        self.window.windowLevel = UIWindowLevelNormal + 1.0;
        self.window.backgroundColor = UIColor.clearColor;
        UIViewController *rootViewController = [UIViewController new];
        self.hostView = [[WCLiquidGlassFloatingTabBarHostView alloc] initWithController:self];
        self.hostView.appInactive = self.appInactive;
        rootViewController.view = self.hostView;
        self.window.rootViewController = rootViewController;
        self.window.hostView = self.hostView;
    }
    self.window.frame = scene.coordinateSpace.bounds;
    self.hostView.frame = self.window.bounds;
}

- (void)wc_update {
    if (!NSThread.isMainThread) {
        [self setNeedsUpdate];
        return;
    }
    BOOL enabled = WCLiquidGlassPreferences.floatingTabBarEnabled;
    id tabController = WCLiquidGlassCurrentTabController();
    UITabBar *tabBar = WCLiquidGlassFloatingTabBarForController(tabController);
    BOOL blocked = tabBar && WCLiquidGlassWCGlassFloatingOverlayIsActiveForTabBar(tabBar);
    if (!self.hasBlockedState || blocked != self.lastBlockedState) {
        if (blocked) {
            [WCLiquidGlassCrashLogger.sharedLogger recordEvent:@"FloatingTabBar blocked by WCGlass"];
        } else if (self.hasBlockedState) {
            [WCLiquidGlassCrashLogger.sharedLogger recordEvent:@"FloatingTabBar WCGlass block ended"];
        }
        self.lastBlockedState = blocked;
        self.hasBlockedState = YES;
    }
    if (!enabled || !tabBar || blocked) {
        WCLiquidGlassFloatingTabBarRestoreNativeSubviews(WCLiquidGlassFloatingTabBarTrackedTabBar);
        WCLiquidGlassFloatingTabBarTrackedTabBar = nil;
        self.hostView.appInactive = self.appInactive;
        [self.hostView wc_collapseImmediately];
        self.window.hidden = YES;
        return;
    }
    [self wc_ensureWindowForTabBar:tabBar];
    if (!self.hostView) {
        return;
    }
    if (WCLiquidGlassFloatingTabBarTrackedTabBar != tabBar) {
        WCLiquidGlassFloatingTabBarRestoreNativeSubviews(WCLiquidGlassFloatingTabBarTrackedTabBar);
        WCLiquidGlassFloatingTabBarTrackedTabBar = tabBar;
        [WCLiquidGlassCrashLogger.sharedLogger recordEvent:@"FloatingTabBar attached to native tab bar"];
    }
    self.hostView.appInactive = self.appInactive;
    WCLiquidGlassFloatingTabBarHideNativeSubviews(tabBar);
    [self.hostView wc_updateForTabController:tabController tabBar:tabBar];
    BOOL hasPresentedController = NO;
    if ([tabController respondsToSelector:@selector(presentedViewController)]) {
        @try {
            hasPresentedController = ((UIViewController *)tabController).presentedViewController != nil;
        } @catch (__unused NSException *exception) {
        }
    }
    BOOL visible = tabBar.window != nil &&
        !tabBar.hidden &&
        tabBar.alpha > 0.01 &&
        CGRectGetMinY(tabBar.frame) < CGRectGetMaxY(tabBar.superview.bounds) - 1.0 &&
        WCLiquidGlassIsAtCurrentTabRoot(tabController) &&
        !hasPresentedController;
    self.window.hidden = !visible || self.appInactive;
    if (!visible || self.appInactive) {
        [self.hostView wc_collapseImmediately];
        return;
    }
    [self.hostView setNeedsLayout];
}

@end

static void WCLiquidGlassFloatingTabBarViewDidAppear(UIViewController *self,
                                                      SEL selector,
                                                      BOOL animated) {
    [WCLiquidGlassFloatingTabBarController.sharedController setNeedsUpdate];
    if (WCLiquidGlassFloatingTabBarOriginalViewDidAppear) {
        WCLiquidGlassFloatingTabBarOriginalViewDidAppear(self, selector, animated);
    }
}

static void WCLiquidGlassFloatingTabBarViewDidDisappear(UIViewController *self,
                                                         SEL selector,
                                                         BOOL animated) {
    [WCLiquidGlassFloatingTabBarController.sharedController setNeedsUpdate];
    if (WCLiquidGlassFloatingTabBarOriginalViewDidDisappear) {
        WCLiquidGlassFloatingTabBarOriginalViewDidDisappear(self, selector, animated);
    }
}

static void WCLiquidGlassFloatingTabBarSetSelectedIndex(UITabBarController *self,
                                                         SEL selector,
                                                         NSInteger index) {
    [WCLiquidGlassFloatingTabBarController.sharedController setNeedsUpdate];
    if (WCLiquidGlassFloatingTabBarOriginalSetSelectedIndex) {
        WCLiquidGlassFloatingTabBarOriginalSetSelectedIndex(self, selector, index);
    }
}

static void WCLiquidGlassFloatingTabBarSetSelectedViewController(UITabBarController *self,
                                                                  SEL selector,
                                                                  UIViewController *controller) {
    [WCLiquidGlassFloatingTabBarController.sharedController setNeedsUpdate];
    if (WCLiquidGlassFloatingTabBarOriginalSetSelectedViewController) {
        WCLiquidGlassFloatingTabBarOriginalSetSelectedViewController(self, selector, controller);
    }
}

static void WCLiquidGlassFloatingTabBarLayoutSubviews(UITabBar *self, SEL selector) {
    if (WCLiquidGlassFloatingTabBarShouldObserve(self)) {
        [WCLiquidGlassFloatingTabBarController.sharedController setNeedsUpdate];
    }
    if (WCLiquidGlassFloatingTabBarOriginalLayoutSubviews) {
        WCLiquidGlassFloatingTabBarOriginalLayoutSubviews(self, selector);
    }
    if (self == WCLiquidGlassFloatingTabBarTrackedTabBar) {
        WCLiquidGlassFloatingTabBarHideNativeSubviews(self);
    }
}

static void WCLiquidGlassFloatingTabBarSetHidden(UITabBar *self, SEL selector, BOOL hidden) {
    if (WCLiquidGlassFloatingTabBarShouldObserve(self)) {
        [WCLiquidGlassFloatingTabBarController.sharedController setNeedsUpdate];
    }
    if (WCLiquidGlassFloatingTabBarOriginalSetHidden) {
        WCLiquidGlassFloatingTabBarOriginalSetHidden(self, selector, hidden);
    }
}

static void WCLiquidGlassFloatingTabBarSetFrame(UITabBar *self, SEL selector, CGRect frame) {
    if (WCLiquidGlassFloatingTabBarShouldObserve(self)) {
        [WCLiquidGlassFloatingTabBarController.sharedController setNeedsUpdate];
    }
    if (WCLiquidGlassFloatingTabBarOriginalSetFrame) {
        WCLiquidGlassFloatingTabBarOriginalSetFrame(self, selector, frame);
    }
}

static void WCLiquidGlassFloatingTabBarDidMoveToWindow(UITabBar *self, SEL selector) {
    if (WCLiquidGlassFloatingTabBarShouldObserve(self)) {
        [WCLiquidGlassFloatingTabBarController.sharedController setNeedsUpdate];
    }
    if (WCLiquidGlassFloatingTabBarOriginalDidMoveToWindow) {
        WCLiquidGlassFloatingTabBarOriginalDidMoveToWindow(self, selector);
    }
    if (self == WCLiquidGlassFloatingTabBarTrackedTabBar) {
        WCLiquidGlassFloatingTabBarHideNativeSubviews(self);
    }
}

void WCLiquidGlassInstallFloatingTabBarHooks(void) {
    if (WCLiquidGlassFloatingTabBarHooksInstalled) {
        [[WCLiquidGlassFloatingTabBarController sharedController] start];
        return;
    }
    Method viewDidAppearMethod = class_getInstanceMethod(UIViewController.class,
                                                         @selector(viewDidAppear:));
    Method viewDidDisappearMethod = class_getInstanceMethod(UIViewController.class,
                                                            @selector(viewDidDisappear:));
    Method selectedIndexMethod = class_getInstanceMethod(UITabBarController.class,
                                                         @selector(setSelectedIndex:));
    Method selectedControllerMethod = class_getInstanceMethod(UITabBarController.class,
                                                               @selector(setSelectedViewController:));
    Method layoutMethod = class_getInstanceMethod(UITabBar.class, @selector(layoutSubviews));
    Method hiddenMethod = class_getInstanceMethod(UITabBar.class, @selector(setHidden:));
    Method frameMethod = class_getInstanceMethod(UITabBar.class, @selector(setFrame:));
    Method movedMethod = class_getInstanceMethod(UITabBar.class, @selector(didMoveToWindow));
    if (!viewDidAppearMethod || !viewDidDisappearMethod || !selectedIndexMethod ||
        !selectedControllerMethod || !layoutMethod || !hiddenMethod || !frameMethod || !movedMethod) {
        if (!WCLiquidGlassFloatingTabBarRetryScheduled &&
            WCLiquidGlassFloatingTabBarInstallAttempts < 20) {
            WCLiquidGlassFloatingTabBarRetryScheduled = YES;
            WCLiquidGlassFloatingTabBarInstallAttempts += 1;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                WCLiquidGlassFloatingTabBarRetryScheduled = NO;
                WCLiquidGlassInstallFloatingTabBarHooks();
            });
        }
        return;
    }
    MSHookMessageEx(UIViewController.class,
                    @selector(viewDidAppear:),
                    (IMP)&WCLiquidGlassFloatingTabBarViewDidAppear,
                    (IMP *)&WCLiquidGlassFloatingTabBarOriginalViewDidAppear);
    MSHookMessageEx(UIViewController.class,
                    @selector(viewDidDisappear:),
                    (IMP)&WCLiquidGlassFloatingTabBarViewDidDisappear,
                    (IMP *)&WCLiquidGlassFloatingTabBarOriginalViewDidDisappear);
    MSHookMessageEx(UITabBarController.class,
                    @selector(setSelectedIndex:),
                    (IMP)&WCLiquidGlassFloatingTabBarSetSelectedIndex,
                    (IMP *)&WCLiquidGlassFloatingTabBarOriginalSetSelectedIndex);
    MSHookMessageEx(UITabBarController.class,
                    @selector(setSelectedViewController:),
                    (IMP)&WCLiquidGlassFloatingTabBarSetSelectedViewController,
                    (IMP *)&WCLiquidGlassFloatingTabBarOriginalSetSelectedViewController);
    MSHookMessageEx(UITabBar.class,
                    @selector(layoutSubviews),
                    (IMP)&WCLiquidGlassFloatingTabBarLayoutSubviews,
                    (IMP *)&WCLiquidGlassFloatingTabBarOriginalLayoutSubviews);
    MSHookMessageEx(UITabBar.class,
                    @selector(setHidden:),
                    (IMP)&WCLiquidGlassFloatingTabBarSetHidden,
                    (IMP *)&WCLiquidGlassFloatingTabBarOriginalSetHidden);
    MSHookMessageEx(UITabBar.class,
                    @selector(setFrame:),
                    (IMP)&WCLiquidGlassFloatingTabBarSetFrame,
                    (IMP *)&WCLiquidGlassFloatingTabBarOriginalSetFrame);
    MSHookMessageEx(UITabBar.class,
                    @selector(didMoveToWindow),
                    (IMP)&WCLiquidGlassFloatingTabBarDidMoveToWindow,
                    (IMP *)&WCLiquidGlassFloatingTabBarOriginalDidMoveToWindow);
    WCLiquidGlassFloatingTabBarHooksInstalled =
        WCLiquidGlassFloatingTabBarOriginalViewDidAppear != NULL &&
        WCLiquidGlassFloatingTabBarOriginalViewDidDisappear != NULL &&
        WCLiquidGlassFloatingTabBarOriginalSetSelectedIndex != NULL &&
        WCLiquidGlassFloatingTabBarOriginalSetSelectedViewController != NULL &&
        WCLiquidGlassFloatingTabBarOriginalLayoutSubviews != NULL &&
        WCLiquidGlassFloatingTabBarOriginalSetHidden != NULL &&
        WCLiquidGlassFloatingTabBarOriginalSetFrame != NULL &&
        WCLiquidGlassFloatingTabBarOriginalDidMoveToWindow != NULL;
    if (WCLiquidGlassFloatingTabBarHooksInstalled) {
        [WCLiquidGlassFloatingTabBarController.sharedController start];
    }
}

BOOL WCLiquidGlassFloatingTabBarIsBlockedByWCGlass(void) {
    id tabController = WCLiquidGlassCurrentTabController();
    UITabBar *tabBar = WCLiquidGlassFloatingTabBarForController(tabController);
    return tabBar && WCLiquidGlassWCGlassFloatingOverlayIsActiveForTabBar(tabBar);
}
