#import "WCLiquidGlassFloatingTabBar.h"

#import "WCLiquidGlassCrashLogger.h"
#import "WCLiquidGlassMenu.h"
#import "WCLiquidGlassPreferences.h"
#import "WCLiquidGlassWCGlassSearchTabBar.h"

#import <CydiaSubstrate.h>
#import <math.h>
#import <objc/message.h>
#import <objc/runtime.h>

static const CGFloat WCLiquidGlassFloatingTabBarCollapsedHeight = 90.0;
static const CGFloat WCLiquidGlassFloatingTabBarSheetChromeHeight = 120.0;
static const CGFloat WCLiquidGlassFloatingTabBarMinimumExpandedHeight = 240.0;
static NSString * const WCLiquidGlassFloatingTabBarCollapsedDetent = @"collapsed";
static NSString * const WCLiquidGlassFloatingTabBarExpandedDetent = @"expanded";

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
@class WCLiquidGlassFloatingTabBarSheetViewController;

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
    id value = WCLiquidGlassFloatingTabBarObjectValue(tabController, @selector(viewControllers));
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

static void WCLiquidGlassFloatingTabBarHideNativeSubviews(UITabBar *tabBar) {
    if (tabBar) {
        [WCLiquidGlassFloatingTabBarController.sharedController wc_hideNativeSubviews:tabBar];
    }
}

static void WCLiquidGlassFloatingTabBarRestoreNativeSubviews(UITabBar *tabBar) {
    [WCLiquidGlassFloatingTabBarController.sharedController wc_restoreNativeSubviews:tabBar];
}

@interface WCLiquidGlassFloatingPassthroughView : UIView
@end

@implementation WCLiquidGlassFloatingPassthroughView

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    return nil;
}

@end

@interface WCLiquidGlassFloatingTabBarWindow : UIWindow
@property(nonatomic, weak) UIViewController *sheetViewController;
@end

@implementation WCLiquidGlassFloatingTabBarWindow

- (BOOL)canBecomeKeyWindow {
    return NO;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *sheetView = self.sheetViewController.viewIfLoaded;
    if (!sheetView || sheetView.window != self || sheetView.hidden) {
        return nil;
    }
    CGPoint local = [self convertPoint:point toView:sheetView];
    if (![sheetView pointInside:local withEvent:event]) {
        return nil;
    }
    return [sheetView hitTest:local withEvent:event];
}

@end

@interface WCLiquidGlassFloatingTabBarTileCell : UICollectionViewCell
@property(nonatomic, copy) NSString *actionIdentifier;
- (void)configureWithItem:(NSDictionary<NSString *, id> *)item;
- (void)refreshEffect;
@end

@implementation WCLiquidGlassFloatingTabBarTileCell {
    UIVisualEffectView *_effectView;
    UIImageView *_imageView;
    UILabel *_label;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) {
        return nil;
    }
    self.contentView.backgroundColor = UIColor.clearColor;
    _effectView = [[UIVisualEffectView alloc]
        initWithEffect:WCLiquidGlassGlassEffectForAppearance(WCLiquidGlassGlassAppearanceTinted)];
    _effectView.userInteractionEnabled = NO;
    _effectView.layer.cornerRadius = 18.0;
    _effectView.clipsToBounds = YES;
    _effectView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _effectView.frame = self.contentView.bounds;
    [self.contentView addSubview:_effectView];
    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectZero];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 8.0;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    _imageView = [[UIImageView alloc] initWithFrame:CGRectZero];
    _imageView.contentMode = UIViewContentModeScaleAspectFit;
    _imageView.translatesAutoresizingMaskIntoConstraints = NO;
    [_imageView.widthAnchor constraintEqualToConstant:28.0].active = YES;
    [_imageView.heightAnchor constraintEqualToConstant:28.0].active = YES;
    _label = [UILabel new];
    _label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    _label.textColor = UIColor.labelColor;
    _label.textAlignment = NSTextAlignmentCenter;
    _label.numberOfLines = 1;
    [_label setContentCompressionResistancePriority:UILayoutPriorityDefaultLow
                                            forAxis:UILayoutConstraintAxisHorizontal];
    [stack addArrangedSubview:_imageView];
    [stack addArrangedSubview:_label];
    [_effectView.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:_effectView.contentView.leadingAnchor constant:8.0],
        [stack.trailingAnchor constraintLessThanOrEqualToAnchor:_effectView.contentView.trailingAnchor constant:-8.0],
        [stack.centerXAnchor constraintEqualToAnchor:_effectView.contentView.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:_effectView.contentView.centerYAnchor]
    ]];
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.actionIdentifier = nil;
    _imageView.image = nil;
    _label.text = nil;
    self.alpha = 1.0;
}

- (void)configureWithItem:(NSDictionary<NSString *, id> *)item {
    self.actionIdentifier = item[@"action"];
    _imageView.image = WCLiquidGlassImageForAction(self.actionIdentifier, 56.0);
    if (_imageView.image.renderingMode == UIImageRenderingModeAlwaysTemplate) {
        _imageView.tintColor = [UIColor colorWithRed:0.027 green:0.757 blue:0.376 alpha:1.0];
    }
    _label.text = WCLiquidGlassActionTitle(self.actionIdentifier);
}

- (void)refreshEffect {
    _effectView.effect = WCLiquidGlassGlassEffectForAppearance(WCLiquidGlassGlassAppearanceTinted);
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = highlighted ? 0.6 : 1.0;
}

@end

@class WCLiquidGlassFloatingTabBarSheetView;

@interface WCLiquidGlassFloatingNativeTabBar : UITabBar
@property(nonatomic, weak) WCLiquidGlassFloatingTabBarSheetView *sheetView;
@end

static BOOL WCLiquidGlassFloatingTabBarShouldObserve(UITabBar *tabBar) {
    return tabBar == WCLiquidGlassFloatingTabBarTrackedTabBar ||
        (!WCLiquidGlassFloatingTabBarTrackedTabBar &&
         ![tabBar isKindOfClass:WCLiquidGlassFloatingNativeTabBar.class]);
}

@interface WCLiquidGlassFloatingTabBarSheetView : UIView
@property(nonatomic, strong) UICollectionView *collectionView;
@property(nonatomic, strong) UILabel *emptyLabel;
@property(nonatomic, strong) WCLiquidGlassFloatingNativeTabBar *tabBar;
@property(nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *actionItems;
@property(nonatomic, assign) BOOL appInactive;
@property(nonatomic, assign) BOOL expanded;
@property(nonatomic, assign) CGFloat visibilityProgress;
@property(nonatomic, assign) CGFloat detentProgress;
@property(nonatomic, assign) CGFloat positionProgress;
- (void)refreshEffects;
- (void)wc_applyTabBarBackgroundOpacity;
@end

@interface WCLiquidGlassFloatingTabBarSheetViewController : UIViewController
    <UICollectionViewDataSource, UICollectionViewDelegate, UITabBarDelegate, UISheetPresentationControllerDelegate>
@property(nonatomic, weak) WCLiquidGlassFloatingTabBarController *controller;
@property(nonatomic, strong) WCLiquidGlassFloatingTabBarSheetView *sheetView;
@property(nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *actionItems;
@property(nonatomic, copy) NSArray<NSString *> *actionIdentifiers;
@property(nonatomic, assign) CGFloat measuredGridHeight;
@property(nonatomic, assign) BOOL expanded;
- (instancetype)initWithController:(WCLiquidGlassFloatingTabBarController *)controller;
- (void)wc_updateForTabController:(id)tabController tabBar:(UITabBar *)tabBar;
- (void)wc_collapseAnimated:(BOOL)animated;
@end

@implementation WCLiquidGlassFloatingNativeTabBar

- (void)layoutSubviews {
    [super layoutSubviews];
    [self.sheetView wc_applyTabBarBackgroundOpacity];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self.sheetView wc_applyTabBarBackgroundOpacity];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.sheetView wc_applyTabBarBackgroundOpacity];
    });
}

@end

@implementation WCLiquidGlassFloatingTabBarSheetView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) {
        return nil;
    }
    self.backgroundColor = UIColor.clearColor;
    UICollectionViewCompositionalLayout *layout =
        [[UICollectionViewCompositionalLayout alloc] initWithSectionProvider:^NSCollectionLayoutSection *(NSInteger sectionIndex,
                                                                                                            id<NSCollectionLayoutEnvironment> environment) {
        (void)sectionIndex;
        (void)environment;
        NSCollectionLayoutSize *itemSize =
            [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0 / 3.0]
                                              heightDimension:[NSCollectionLayoutDimension absoluteDimension:78.0]];
        NSCollectionLayoutItem *item = [NSCollectionLayoutItem itemWithLayoutSize:itemSize];
        NSCollectionLayoutSize *groupSize =
            [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                              heightDimension:[NSCollectionLayoutDimension absoluteDimension:78.0]];
        NSCollectionLayoutGroup *group =
            [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:groupSize
                                                   repeatingSubitem:item
                                                               count:3];
        group.interItemSpacing = [NSCollectionLayoutSpacing fixedSpacing:12.0];
        NSCollectionLayoutSection *section = [NSCollectionLayoutSection sectionWithGroup:group];
        section.interGroupSpacing = 12.0;
        section.contentInsets = NSDirectionalEdgeInsetsMake(20.0, 20.0, 102.0, 20.0);
        return section;
    }];
    _collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    _collectionView.backgroundColor = UIColor.clearColor;
    _collectionView.alwaysBounceVertical = YES;
    _collectionView.showsVerticalScrollIndicator = NO;
    _collectionView.delaysContentTouches = NO;
    [_collectionView registerClass:WCLiquidGlassFloatingTabBarTileCell.class
        forCellWithReuseIdentifier:@"WCLiquidGlassFloatingTabBarTileCell"];
    [self addSubview:_collectionView];
    _emptyLabel = [UILabel new];
    _emptyLabel.text = @"请先在“按钮与动作”中启用动作";
    _emptyLabel.textColor = UIColor.secondaryLabelColor;
    _emptyLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    _emptyLabel.textAlignment = NSTextAlignmentCenter;
    _emptyLabel.numberOfLines = 0;
    _emptyLabel.hidden = YES;
    [self addSubview:_emptyLabel];
    _tabBar = [WCLiquidGlassFloatingNativeTabBar new];
    _tabBar.translucent = YES;
    _tabBar.backgroundImage = [UIImage new];
    _tabBar.shadowImage = [UIImage new];
    _tabBar.backgroundColor = UIColor.clearColor;
    _tabBar.tintColor = [UIColor colorWithRed:0.027 green:0.757 blue:0.376 alpha:1.0];
    _tabBar.sheetView = self;
    UITabBarAppearance *appearance = [UITabBarAppearance new];
    [appearance configureWithTransparentBackground];
    appearance.backgroundEffect = nil;
    appearance.backgroundColor = UIColor.clearColor;
    appearance.shadowColor = UIColor.clearColor;
    _tabBar.standardAppearance = appearance;
    _tabBar.scrollEdgeAppearance = appearance;
    [self addSubview:_tabBar];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat height = CGRectGetHeight(self.bounds);
    self.visibilityProgress =
        WCLiquidGlassFloatingTabBarClamp((height - 125.0) / 100.0, 0.0, 1.0);
    self.detentProgress =
        WCLiquidGlassFloatingTabBarClamp((height - 90.0) / 294.0, 0.0, 1.0);
    self.positionProgress =
        WCLiquidGlassFloatingTabBarClamp((height - 384.0) / 428.0, 0.0, 1.0);
    self.collectionView.frame = self.bounds;
    self.collectionView.alpha = self.visibilityProgress;
    self.emptyLabel.frame = self.bounds;
    self.emptyLabel.alpha = self.visibilityProgress;
    self.emptyLabel.hidden = self.actionItems.count > 0;
    CGFloat offset = 3.0 + 9.0 * self.detentProgress - 11.0 * self.positionProgress;
    self.tabBar.frame = CGRectMake(0.0, height - 90.0 + offset, width, 90.0);
    [self wc_applyTabBarBackgroundOpacity];
}

- (void)refreshEffects {
    for (UICollectionViewCell *cell in self.collectionView.visibleCells) {
        if ([cell isKindOfClass:WCLiquidGlassFloatingTabBarTileCell.class]) {
            [(WCLiquidGlassFloatingTabBarTileCell *)cell refreshEffect];
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
    if (!self.expanded && self.visibilityProgress <= 0.0) {
        opacity = 0.0;
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self wc_applyOpacity:opacity toLayer:self.tabBar.layer platterSize:platter.bounds.size];
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

@end

@implementation WCLiquidGlassFloatingTabBarSheetViewController

- (instancetype)initWithController:(WCLiquidGlassFloatingTabBarController *)controller {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _controller = controller;
        _actionItems = @[];
        _actionIdentifiers = @[];
        _measuredGridHeight = 0.0;
    }
    return self;
}

- (void)loadView {
    self.sheetView = [WCLiquidGlassFloatingTabBarSheetView new];
    self.sheetView.collectionView.dataSource = self;
    self.sheetView.collectionView.delegate = self;
    self.sheetView.tabBar.delegate = self;
    self.view = self.sheetView;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat measured = self.sheetView.collectionView.collectionViewLayout.collectionViewContentSize.height;
    if (measured <= 0.0) {
        NSUInteger rows = (self.actionItems.count + 2U) / 3U;
        measured = rows == 0 ? 24.0 : rows * 78.0 + (rows - 1U) * 12.0 + 24.0;
    }
    if (fabs(self.measuredGridHeight - measured) <= 0.01) {
        return;
    }
    self.measuredGridHeight = measured;
    if (@available(iOS 16.0, *)) {
        UISheetPresentationController *sheet = self.sheetPresentationController;
        if (sheet) {
            [sheet animateChanges:^{
                [sheet invalidateDetents];
            }];
        }
    }
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self.sheetView.collectionView reloadData];
        [self.sheetView refreshEffects];
    }
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.actionItems.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                  cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    WCLiquidGlassFloatingTabBarTileCell *cell =
        [collectionView dequeueReusableCellWithReuseIdentifier:@"WCLiquidGlassFloatingTabBarTileCell"
                                                  forIndexPath:indexPath];
    [cell configureWithItem:self.actionItems[indexPath.item]];
    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [collectionView deselectItemAtIndexPath:indexPath animated:NO];
    if ((NSUInteger)indexPath.item >= self.actionItems.count) {
        return;
    }
    NSString *identifier = self.actionItems[indexPath.item][@"action"];
    [self wc_collapseAnimated:YES];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        WCLiquidGlassPerformActionIdentifier(identifier);
    });
}

- (void)wc_rebuildActionItemsIfNeeded {
    NSArray<NSDictionary<NSString *, id> *> *items = WCLiquidGlassFloatingTabBarActionItems();
    NSArray<NSString *> *identifiers = [items valueForKey:@"action"] ?: @[];
    if ([identifiers isEqualToArray:self.actionIdentifiers]) {
        return;
    }
    CGFloat oldHeight = self.measuredGridHeight;
    self.actionItems = items;
    self.actionIdentifiers = identifiers;
    self.sheetView.actionItems = items;
    [self.sheetView.collectionView reloadData];
    [self.sheetView.collectionView layoutIfNeeded];
    CGFloat measured = self.sheetView.collectionView.collectionViewLayout.collectionViewContentSize.height;
    if (measured <= 0.0) {
        NSUInteger rows = (items.count + 2U) / 3U;
        measured = rows == 0 ? 24.0 : rows * 78.0 + (rows - 1U) * 12.0 + 24.0;
    }
    self.measuredGridHeight = measured;
    if (@available(iOS 16.0, *)) {
        UISheetPresentationController *sheet = self.sheetPresentationController;
        if (sheet && fabs(oldHeight - measured) > 0.01) {
            [sheet animateChanges:^{
                [sheet invalidateDetents];
            }];
        }
    }
    [self.sheetView setNeedsLayout];
}

- (void)wc_updateForTabController:(id)tabController tabBar:(UITabBar *)tabBar {
    if (!tabBar) {
        return;
    }
    NSArray *viewControllers = WCLiquidGlassFloatingTabBarViewControllers(tabController);
    NSUInteger count = MIN(4U, viewControllers.count);
    NSMutableArray<UITabBarItem *> *items = [NSMutableArray arrayWithCapacity:count];
    NSArray<NSString *> *symbols = @[@"message.fill", @"person.2.fill", @"safari.fill", @"person.fill"];
    for (NSUInteger index = 0; index < count; index++) {
        UIViewController *viewController =
            [viewControllers[index] isKindOfClass:UIViewController.class] ? viewControllers[index] : nil;
        UIImage *image = WCLiquidGlassNativeTabImage(tabController, index);
        if (!image) {
            image = [UIImage systemImageNamed:symbols[index]];
        }
        UITabBarItem *item = [[UITabBarItem alloc] initWithTitle:nil image:image selectedImage:image];
        item.tag = index;
        @try {
            item.badgeValue = viewController.tabBarItem.badgeValue;
        } @catch (__unused NSException *exception) {
        }
        [items addObject:item];
    }
    BOOL itemsChanged = self.sheetView.tabBar.items.count != items.count;
    for (NSUInteger index = 0; !itemsChanged && index < items.count; index++) {
        UITabBarItem *oldItem = self.sheetView.tabBar.items[index];
        UITabBarItem *newItem = items[index];
        itemsChanged = ![oldItem.image isEqual:newItem.image] ||
            ![oldItem.selectedImage isEqual:newItem.selectedImage] ||
            ![oldItem.badgeValue isEqualToString:newItem.badgeValue];
    }
    if (itemsChanged) {
        self.sheetView.tabBar.items = items;
    }
    NSInteger selectedIndex = WCLiquidGlassCurrentTabIndex(tabController);
    if (selectedIndex >= 0 && selectedIndex < (NSInteger)self.sheetView.tabBar.items.count &&
        self.sheetView.tabBar.selectedItem != self.sheetView.tabBar.items[selectedIndex]) {
        [UIView performWithoutAnimation:^{
            self.sheetView.tabBar.selectedItem = self.sheetView.tabBar.items[selectedIndex];
        }];
    }
    [self wc_rebuildActionItemsIfNeeded];
}

- (void)wc_collapseAnimated:(BOOL)animated {
    self.expanded = NO;
    self.sheetView.expanded = NO;
    UISheetPresentationController *sheet = self.sheetPresentationController;
    if (!sheet) {
        [self.sheetView setNeedsLayout];
        return;
    }
    if (@available(iOS 16.0, *)) {
        if (animated) {
            [sheet animateChanges:^{
                sheet.selectedDetentIdentifier = WCLiquidGlassFloatingTabBarCollapsedDetent;
            }];
        } else {
            [UIView performWithoutAnimation:^{
                sheet.selectedDetentIdentifier = WCLiquidGlassFloatingTabBarCollapsedDetent;
            }];
        }
    } else {
        sheet.selectedDetentIdentifier = UISheetPresentationControllerDetentIdentifierMedium;
    }
    [self.sheetView setNeedsLayout];
}

- (void)sheetPresentationControllerDidChangeSelectedDetentIdentifier:(UISheetPresentationController *)sheetPresentationController {
    BOOL expanded = ![sheetPresentationController.selectedDetentIdentifier
        isEqualToString:WCLiquidGlassFloatingTabBarCollapsedDetent];
    if (expanded != self.expanded) {
        self.expanded = expanded;
        self.sheetView.expanded = expanded;
        UIImpactFeedbackGenerator *generator =
            [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [generator prepare];
        [generator impactOccurred];
    }
    [self.sheetView setNeedsLayout];
}

- (void)tabBar:(UITabBar *)tabBar didSelectItem:(UITabBarItem *)item {
    id tabController = WCLiquidGlassCurrentTabController();
    NSInteger index = item.tag;
    NSInteger current = WCLiquidGlassCurrentTabIndex(tabController);
    if (index == current) {
        return;
    }
    if (!WCLiquidGlassCanSelectTab(tabController, index)) {
        self.sheetView.tabBar.selectedItem = self.sheetView.tabBar.items[current];
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
        self.sheetView.tabBar.selectedItem = self.sheetView.tabBar.items[current];
    }
    [self.controller setNeedsUpdate];
}

@end

@interface WCLiquidGlassFloatingTabBarController ()
@property(nonatomic, strong) WCLiquidGlassFloatingTabBarWindow *window;
@property(nonatomic, strong) WCLiquidGlassFloatingTabBarSheetViewController *sheetViewController;
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
    [center addObserver:self selector:@selector(wc_preferencesChanged:)
                   name:WCLiquidGlassPreferencesDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(wc_applicationDidBecomeActive:)
                   name:UIApplicationDidBecomeActiveNotification object:nil];
    [center addObserver:self selector:@selector(wc_applicationWillResignActive:)
                   name:UIApplicationWillResignActiveNotification object:nil];
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
    [self.sheetViewController.sheetView refreshEffects];
    [self setNeedsUpdate];
}

- (void)wc_applicationDidBecomeActive:(NSNotification *)notification {
    self.appInactive = NO;
    self.sheetViewController.sheetView.appInactive = NO;
    [self.sheetViewController.sheetView wc_applyTabBarBackgroundOpacity];
    [self setNeedsUpdate];
}

- (void)wc_applicationWillResignActive:(NSNotification *)notification {
    self.appInactive = YES;
    self.sheetViewController.sheetView.appInactive = YES;
    [self.sheetViewController wc_collapseAnimated:NO];
    [self.sheetViewController.sheetView wc_applyTabBarBackgroundOpacity];
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

- (void)wc_configureSheet:(WCLiquidGlassFloatingTabBarSheetViewController *)sheetViewController {
    @try {
        sheetViewController.modalPresentationStyle = UIModalPresentationPageSheet;
        sheetViewController.modalInPresentation = YES;
    } @catch (__unused NSException *exception) {
        return;
    }
    UISheetPresentationController *sheet = sheetViewController.sheetPresentationController;
    if (!sheet) {
        return;
    }
    sheet.delegate = sheetViewController;
    sheet.prefersGrabberVisible = YES;
    sheet.prefersScrollingExpandsWhenScrolledToEdge = YES;
    sheet.prefersEdgeAttachedInCompactHeight = YES;
    sheet.largestUndimmedDetentIdentifier = WCLiquidGlassFloatingTabBarExpandedDetent;
    if (@available(iOS 16.0, *)) {
        __weak WCLiquidGlassFloatingTabBarSheetViewController *weakSheetViewController = sheetViewController;
        UISheetPresentationControllerDetent *collapsed =
            [UISheetPresentationControllerDetent customDetentWithIdentifier:WCLiquidGlassFloatingTabBarCollapsedDetent
                                                                      resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> context) {
            (void)context;
            return WCLiquidGlassFloatingTabBarCollapsedHeight;
        }];
        UISheetPresentationControllerDetent *expanded =
            [UISheetPresentationControllerDetent customDetentWithIdentifier:WCLiquidGlassFloatingTabBarExpandedDetent
                                                                      resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> context) {
            CGFloat maximum = MAX(WCLiquidGlassFloatingTabBarMinimumExpandedHeight,
                                  context.maximumDetentValue * 0.85);
            CGFloat measured = weakSheetViewController.measuredGridHeight;
            return MIN(MAX(measured + WCLiquidGlassFloatingTabBarSheetChromeHeight,
                           WCLiquidGlassFloatingTabBarMinimumExpandedHeight), maximum);
        }];
        sheet.detents = @[collapsed, expanded];
        sheet.selectedDetentIdentifier = WCLiquidGlassFloatingTabBarCollapsedDetent;
    } else {
        sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent];
        sheet.selectedDetentIdentifier = UISheetPresentationControllerDetentIdentifierMedium;
    }
}

- (void)wc_ensureWindowForTabBar:(UITabBar *)tabBar {
    UIWindowScene *scene = tabBar.window.windowScene;
    if (!scene) {
        return;
    }
    if (self.window.windowScene != scene) {
        self.window.hidden = YES;
        self.window = nil;
        self.sheetViewController = nil;
    }
    if (!self.window) {
        self.window = [[WCLiquidGlassFloatingTabBarWindow alloc] initWithWindowScene:scene];
        self.window.windowLevel = UIWindowLevelNormal + 1.0;
        self.window.backgroundColor = UIColor.clearColor;
        UIViewController *rootViewController = [UIViewController new];
        rootViewController.view = [WCLiquidGlassFloatingPassthroughView new];
        rootViewController.view.backgroundColor = UIColor.clearColor;
        self.window.rootViewController = rootViewController;
    }
    self.window.frame = scene.coordinateSpace.bounds;
    self.window.hidden = NO;
    UIViewController *rootViewController = self.window.rootViewController;
    if (!rootViewController.presentedViewController) {
        self.sheetViewController = [[WCLiquidGlassFloatingTabBarSheetViewController alloc]
            initWithController:self];
        [self wc_configureSheet:self.sheetViewController];
        self.window.sheetViewController = self.sheetViewController;
        [rootViewController presentViewController:self.sheetViewController animated:NO completion:nil];
    } else if (!self.window.sheetViewController) {
        self.window.sheetViewController = rootViewController.presentedViewController;
    }
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
    if (!enabled) {
        WCLiquidGlassFloatingTabBarRestoreNativeSubviews(WCLiquidGlassFloatingTabBarTrackedTabBar);
        WCLiquidGlassFloatingTabBarTrackedTabBar = nil;
        [self.sheetViewController wc_collapseAnimated:NO];
        self.window.hidden = YES;
        [self.window.rootViewController dismissViewControllerAnimated:NO completion:nil];
        self.sheetViewController = nil;
        self.window = nil;
        return;
    }
    if (!tabBar || blocked) {
        WCLiquidGlassFloatingTabBarRestoreNativeSubviews(WCLiquidGlassFloatingTabBarTrackedTabBar);
        WCLiquidGlassFloatingTabBarTrackedTabBar = nil;
        [self.sheetViewController wc_collapseAnimated:NO];
        self.window.hidden = YES;
        return;
    }
    [self wc_ensureWindowForTabBar:tabBar];
    if (!self.sheetViewController) {
        return;
    }
    if (WCLiquidGlassFloatingTabBarTrackedTabBar != tabBar) {
        WCLiquidGlassFloatingTabBarRestoreNativeSubviews(WCLiquidGlassFloatingTabBarTrackedTabBar);
        WCLiquidGlassFloatingTabBarTrackedTabBar = tabBar;
        [WCLiquidGlassCrashLogger.sharedLogger recordEvent:@"FloatingTabBar attached to native tab bar"];
    }
    self.sheetViewController.sheetView.appInactive = self.appInactive;
    WCLiquidGlassFloatingTabBarHideNativeSubviews(tabBar);
    [self.sheetViewController wc_updateForTabController:tabController tabBar:tabBar];
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
        [self.sheetViewController wc_collapseAnimated:NO];
    }
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
        [WCLiquidGlassFloatingTabBarController.sharedController start];
        return;
    }
    Method viewDidAppearMethod = class_getInstanceMethod(UIViewController.class, @selector(viewDidAppear:));
    Method viewDidDisappearMethod = class_getInstanceMethod(UIViewController.class, @selector(viewDidDisappear:));
    Method selectedIndexMethod = class_getInstanceMethod(UITabBarController.class, @selector(setSelectedIndex:));
    Method selectedControllerMethod =
        class_getInstanceMethod(UITabBarController.class, @selector(setSelectedViewController:));
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
    MSHookMessageEx(UIViewController.class, @selector(viewDidAppear:),
                    (IMP)&WCLiquidGlassFloatingTabBarViewDidAppear,
                    (IMP *)&WCLiquidGlassFloatingTabBarOriginalViewDidAppear);
    MSHookMessageEx(UIViewController.class, @selector(viewDidDisappear:),
                    (IMP)&WCLiquidGlassFloatingTabBarViewDidDisappear,
                    (IMP *)&WCLiquidGlassFloatingTabBarOriginalViewDidDisappear);
    MSHookMessageEx(UITabBarController.class, @selector(setSelectedIndex:),
                    (IMP)&WCLiquidGlassFloatingTabBarSetSelectedIndex,
                    (IMP *)&WCLiquidGlassFloatingTabBarOriginalSetSelectedIndex);
    MSHookMessageEx(UITabBarController.class, @selector(setSelectedViewController:),
                    (IMP)&WCLiquidGlassFloatingTabBarSetSelectedViewController,
                    (IMP *)&WCLiquidGlassFloatingTabBarOriginalSetSelectedViewController);
    MSHookMessageEx(UITabBar.class, @selector(layoutSubviews),
                    (IMP)&WCLiquidGlassFloatingTabBarLayoutSubviews,
                    (IMP *)&WCLiquidGlassFloatingTabBarOriginalLayoutSubviews);
    MSHookMessageEx(UITabBar.class, @selector(setHidden:),
                    (IMP)&WCLiquidGlassFloatingTabBarSetHidden,
                    (IMP *)&WCLiquidGlassFloatingTabBarOriginalSetHidden);
    MSHookMessageEx(UITabBar.class, @selector(setFrame:),
                    (IMP)&WCLiquidGlassFloatingTabBarSetFrame,
                    (IMP *)&WCLiquidGlassFloatingTabBarOriginalSetFrame);
    MSHookMessageEx(UITabBar.class, @selector(didMoveToWindow),
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
