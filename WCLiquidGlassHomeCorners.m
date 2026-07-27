#import "WCLiquidGlassHomeCorners.h"

#import <CydiaSubstrate.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "WCLiquidGlassMenu.h"
#import "WCLiquidGlassPreferences.h"

static const void *WCLiquidGlassHomeCornerStateKey = &WCLiquidGlassHomeCornerStateKey;
static const void *WCLiquidGlassHomeCornerTableStyledKey = &WCLiquidGlassHomeCornerTableStyledKey;
static const void *WCLiquidGlassHomeCornerTableRoleKey = &WCLiquidGlassHomeCornerTableRoleKey;
static const void *WCLiquidGlassHomeCornerTableRoleEpochKey = &WCLiquidGlassHomeCornerTableRoleEpochKey;
static const void *WCLiquidGlassHomeCornerTableStateKey = &WCLiquidGlassHomeCornerTableStateKey;
static const void *WCLiquidGlassHomeCornerSubviewStateKey = &WCLiquidGlassHomeCornerSubviewStateKey;
static void (*WCLiquidGlassOriginalHomeCornersTableLayoutSubviews)(UITableView *, SEL) = NULL;
static BOOL WCLiquidGlassHomeCornersHooksInstalled = NO;
static BOOL WCLiquidGlassHomeCornersHookRetryScheduled = NO;
static NSUInteger WCLiquidGlassHomeCornersHookInstallAttempts = 0;
static NSUInteger WCLiquidGlassHomeCornersConfigurationEpoch = 1;

typedef NS_ENUM(NSInteger, WCLiquidGlassHomeCornerTableRole) {
    WCLiquidGlassHomeCornerTableRoleNone = 0,
    WCLiquidGlassHomeCornerTableRoleHome,
    WCLiquidGlassHomeCornerTableRoleOtherTab
};

@interface WCLiquidGlassHomeCornerBackgroundView : UIView
@property(nonatomic, strong) UIVisualEffectView *effectView;
@property(nonatomic, assign) NSInteger visualState;
- (void)wc_updateAppearance;
@end

@implementation WCLiquidGlassHomeCornerBackgroundView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _effectView = [[UIVisualEffectView alloc] initWithEffect:nil];
        _effectView.frame = self.bounds;
        _effectView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _effectView.userInteractionEnabled = NO;
        _visualState = NSIntegerMin;
        [self addSubview:_effectView];
    }
    return self;
}

- (void)wc_updateAppearance {
    BOOL liquid = WCLiquidGlassPreferences.homeLiquidBackgroundEnabled;
    NSInteger state = liquid
        ? WCLiquidGlassPreferences.glassAppearance * 10 + self.traitCollection.userInterfaceStyle
        : -1;
    if (self.visualState == state) {
        return;
    }
    self.visualState = state;
    self.effectView.hidden = !liquid;
    self.effectView.effect = liquid ? WCLiquidGlassCurrentGlassEffect() : nil;
    self.backgroundColor = UIColor.clearColor;
}

@end

@interface WCLiquidGlassHomeCornerCellState : NSObject
@property(nonatomic, assign) CGRect baseFrame;
@property(nonatomic, assign) CGRect appliedFrame;
@property(nonatomic, assign) BOOL hasAppliedFrame;
@property(nonatomic, strong, nullable) UIView *originalBackgroundView;
@property(nonatomic, strong, nullable) UIColor *originalBackgroundColor;
@property(nonatomic, strong, nullable) UIColor *originalContentBackgroundColor;
@property(nonatomic, assign) CGFloat originalCornerRadius;
@property(nonatomic, assign) CACornerMask originalMaskedCorners;
@property(nonatomic, assign) BOOL originalMasksToBounds;
@property(nonatomic, strong, nullable) WCLiquidGlassHomeCornerBackgroundView *cardBackground;
@property(nonatomic, assign) BOOL captured;
@end

@implementation WCLiquidGlassHomeCornerCellState
@end

@interface WCLiquidGlassHomeCornerTableState : NSObject
@property(nonatomic, assign) UITableViewCellSeparatorStyle originalSeparatorStyle;
@property(nonatomic, assign) BOOL captured;
@end

@implementation WCLiquidGlassHomeCornerTableState
@end

@interface WCLiquidGlassHomeCornerSubviewState : NSObject
@property(nonatomic, strong, nullable) UIColor *originalBackgroundColor;
@property(nonatomic, assign) BOOL originalHidden;
@property(nonatomic, assign) BOOL captured;
@end

@implementation WCLiquidGlassHomeCornerSubviewState
@end

static WCLiquidGlassHomeCornerTableState *WCLiquidGlassHomeCornerStateForTable(UITableView *tableView) {
    WCLiquidGlassHomeCornerTableState *state = objc_getAssociatedObject(tableView, WCLiquidGlassHomeCornerTableStateKey);
    if (!state) {
        state = [[WCLiquidGlassHomeCornerTableState alloc] init];
        state.originalSeparatorStyle = tableView.separatorStyle;
        state.captured = YES;
        objc_setAssociatedObject(tableView,
                                 WCLiquidGlassHomeCornerTableStateKey,
                                 state,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return state;
}

static void WCLiquidGlassHomeCornerApplyTableStyle(UITableView *tableView) {
    WCLiquidGlassHomeCornerStateForTable(tableView);
    if (tableView.separatorStyle != UITableViewCellSeparatorStyleNone) {
        tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    }
}

static void WCLiquidGlassHomeCornerRestoreTableStyle(UITableView *tableView) {
    WCLiquidGlassHomeCornerTableState *state = objc_getAssociatedObject(tableView, WCLiquidGlassHomeCornerTableStateKey);
    if (state && state.captured) {
        tableView.separatorStyle = state.originalSeparatorStyle;
    }
}

static BOOL WCLiquidGlassHomeCornerColorIsOpaqueWhite(UIColor *color, UITraitCollection *traits) {
    if (!color) {
        return NO;
    }
    UIColor *resolvedColor = [color resolvedColorWithTraitCollection:traits];
    CGFloat white = 0.0;
    CGFloat alpha = 0.0;
    if ([resolvedColor getWhite:&white alpha:&alpha]) {
        return white > 0.86 && alpha > 0.68;
    }
    CGFloat red = 0.0;
    CGFloat green = 0.0;
    CGFloat blue = 0.0;
    return [resolvedColor getRed:&red green:&green blue:&blue alpha:&alpha] &&
        red > 0.86 && green > 0.86 && blue > 0.86 && alpha > 0.68;
}

static BOOL WCLiquidGlassHomeCornerShouldPreserveSubview(UIView *view) {
    return [view isKindOfClass:UILabel.class] ||
        [view isKindOfClass:UIImageView.class] ||
        [view isKindOfClass:UIControl.class] ||
        [view isKindOfClass:UIVisualEffectView.class];
}

static WCLiquidGlassHomeCornerSubviewState *WCLiquidGlassHomeCornerStateForSubview(UIView *view) {
    WCLiquidGlassHomeCornerSubviewState *state = objc_getAssociatedObject(view, WCLiquidGlassHomeCornerSubviewStateKey);
    if (!state) {
        state = [[WCLiquidGlassHomeCornerSubviewState alloc] init];
        state.originalBackgroundColor = view.backgroundColor;
        state.originalHidden = view.hidden;
        state.captured = YES;
        objc_setAssociatedObject(view,
                                 WCLiquidGlassHomeCornerSubviewStateKey,
                                 state,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return state;
}

static void WCLiquidGlassHomeCornerPrepareContent(UIView *view, NSUInteger depth) {
    if (!view || depth > 8) {
        return;
    }
    if (!WCLiquidGlassHomeCornerShouldPreserveSubview(view) &&
        WCLiquidGlassHomeCornerColorIsOpaqueWhite(view.backgroundColor, view.traitCollection)) {
        WCLiquidGlassHomeCornerStateForSubview(view);
        view.backgroundColor = UIColor.clearColor;
    }
    CGRect bounds = view.bounds;
    if (depth > 0 &&
        CGRectGetHeight(bounds) <= 1.5 &&
        CGRectGetWidth(bounds) >= CGRectGetWidth(view.superview.bounds) * 0.72) {
        WCLiquidGlassHomeCornerStateForSubview(view);
        view.hidden = YES;
    }
    for (UIView *subview in view.subviews) {
        WCLiquidGlassHomeCornerPrepareContent(subview, depth + 1);
    }
}

static void WCLiquidGlassHomeCornerRestoreContent(UIView *view, NSUInteger depth) {
    if (!view || depth > 8) {
        return;
    }
    WCLiquidGlassHomeCornerSubviewState *state = objc_getAssociatedObject(view, WCLiquidGlassHomeCornerSubviewStateKey);
    if (state && state.captured) {
        view.backgroundColor = state.originalBackgroundColor;
        view.hidden = state.originalHidden;
    }
    for (UIView *subview in view.subviews) {
        WCLiquidGlassHomeCornerRestoreContent(subview, depth + 1);
    }
}

static BOOL WCLiquidGlassHomeCornerNameContains(NSString *name, NSArray<NSString *> *tokens) {
    NSString *lowercaseName = name.lowercaseString;
    for (NSString *token in tokens) {
        if ([lowercaseName containsString:token]) {
            return YES;
        }
    }
    return NO;
}

static WCLiquidGlassHomeCornerTableRole WCLiquidGlassHomeCornerUncachedRoleForTable(UITableView *tableView) {
    if (!WCLiquidGlassPreferences.homeCornersEnabled) {
        return WCLiquidGlassHomeCornerTableRoleNone;
    }
    Class homeTableClass = NSClassFromString(@"MainFrameTableView");
    if (homeTableClass && [tableView isKindOfClass:homeTableClass]) {
        return WCLiquidGlassHomeCornerTableRoleHome;
    }
    if (!WCLiquidGlassPreferences.homeCornersSyncOtherTabsEnabled) {
        return WCLiquidGlassHomeCornerTableRoleNone;
    }
    BOOL belongsToMainFrame = NO;
    BOOL otherTabController = NO;
    for (UIResponder *responder = tableView.nextResponder;
         responder;
         responder = responder.nextResponder) {
        NSString *name = NSStringFromClass(responder.class);
        if ([name isEqualToString:@"NewMainFrameViewController"]) {
            belongsToMainFrame = YES;
        }
        if (WCLiquidGlassHomeCornerNameContains(name, @[@"findfriend", @"contact", @"more"])) {
            otherTabController = YES;
        }
    }
    return belongsToMainFrame && otherTabController
        ? WCLiquidGlassHomeCornerTableRoleOtherTab
        : WCLiquidGlassHomeCornerTableRoleNone;
}

static WCLiquidGlassHomeCornerTableRole WCLiquidGlassHomeCornerRoleForTable(UITableView *tableView) {
    NSNumber *cachedEpoch = objc_getAssociatedObject(tableView, WCLiquidGlassHomeCornerTableRoleEpochKey);
    if (cachedEpoch.unsignedIntegerValue == WCLiquidGlassHomeCornersConfigurationEpoch) {
        return [objc_getAssociatedObject(tableView, WCLiquidGlassHomeCornerTableRoleKey) integerValue];
    }
    WCLiquidGlassHomeCornerTableRole role = WCLiquidGlassHomeCornerUncachedRoleForTable(tableView);
    objc_setAssociatedObject(tableView,
                             WCLiquidGlassHomeCornerTableRoleKey,
                             @(role),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(tableView,
                             WCLiquidGlassHomeCornerTableRoleEpochKey,
                             @(WCLiquidGlassHomeCornersConfigurationEpoch),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return role;
}

static WCLiquidGlassHomeCornerCellState *WCLiquidGlassHomeCornerStateForCell(UITableViewCell *cell) {
    WCLiquidGlassHomeCornerCellState *state = objc_getAssociatedObject(cell, WCLiquidGlassHomeCornerStateKey);
    if (!state) {
        state = [[WCLiquidGlassHomeCornerCellState alloc] init];
        objc_setAssociatedObject(cell,
                                 WCLiquidGlassHomeCornerStateKey,
                                 state,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!state.captured) {
        state.originalBackgroundView = cell.backgroundView;
        state.originalBackgroundColor = cell.backgroundColor;
        state.originalContentBackgroundColor = cell.contentView.backgroundColor;
        state.originalCornerRadius = cell.layer.cornerRadius;
        state.originalMaskedCorners = cell.layer.maskedCorners;
        state.originalMasksToBounds = cell.layer.masksToBounds;
        state.captured = YES;
    }
    return state;
}

static void WCLiquidGlassHomeCornerRestoreCell(UITableViewCell *cell) {
    WCLiquidGlassHomeCornerCellState *state = objc_getAssociatedObject(cell, WCLiquidGlassHomeCornerStateKey);
    if (!state || !state.captured) {
        return;
    }
    if (state.hasAppliedFrame && CGRectEqualToRect(cell.frame, state.appliedFrame)) {
        cell.frame = state.baseFrame;
    }
    cell.backgroundView = state.originalBackgroundView;
    cell.backgroundColor = state.originalBackgroundColor;
    cell.contentView.backgroundColor = state.originalContentBackgroundColor;
    [state.cardBackground removeFromSuperview];
    WCLiquidGlassHomeCornerRestoreContent(cell, 0);
    cell.layer.cornerRadius = state.originalCornerRadius;
    cell.layer.maskedCorners = state.originalMaskedCorners;
    cell.layer.masksToBounds = state.originalMasksToBounds;
    state.hasAppliedFrame = NO;
}

static CGRect WCLiquidGlassHomeCornerBaseFrame(UITableViewCell *cell,
                                               WCLiquidGlassHomeCornerCellState *state) {
    CGRect currentFrame = cell.frame;
    if (state.hasAppliedFrame && CGRectEqualToRect(currentFrame, state.appliedFrame)) {
        return state.baseFrame;
    }
    return currentFrame;
}

static void WCLiquidGlassHomeCornerApplyCell(UITableView *tableView,
                                             UITableViewCell *cell,
                                             WCLiquidGlassHomeCornerTableRole role) {
    NSIndexPath *indexPath = [tableView indexPathForCell:cell];
    if (!indexPath) {
        return;
    }
    WCLiquidGlassHomeCornerCellState *state = WCLiquidGlassHomeCornerStateForCell(cell);
    CGRect baseFrame = WCLiquidGlassHomeCornerBaseFrame(cell, state);
    BOOL home = role == WCLiquidGlassHomeCornerTableRoleHome;
    CGFloat inset = home ? WCLiquidGlassPreferences.homeCornerInset : WCLiquidGlassPreferences.homeCornerInset;
    CGFloat radius = home ? WCLiquidGlassPreferences.homeCornerRadius : WCLiquidGlassPreferences.homeOtherTabsCornerRadius;
    BOOL separate = home && WCLiquidGlassPreferences.homeSeparateCardsEnabled;
    CGFloat gap = separate ? WCLiquidGlassPreferences.homeCardGap : 0.0;
    CGRect targetFrame = baseFrame;
    targetFrame.origin.x = inset;
    targetFrame.size.width = MAX(0.0, CGRectGetWidth(tableView.bounds) - inset * 2.0);
    if (gap > 0.0) {
        CGFloat halfGap = gap * 0.5;
        targetFrame.origin.y += halfGap;
        targetFrame.size.height = MAX(1.0, targetFrame.size.height - gap);
    }
    targetFrame = CGRectIntegral(targetFrame);
    if (!CGRectEqualToRect(cell.frame, targetFrame)) {
        cell.frame = targetFrame;
    }
    state.baseFrame = baseFrame;
    state.appliedFrame = targetFrame;
    state.hasAppliedFrame = YES;

    NSInteger rows = [tableView numberOfRowsInSection:indexPath.section];
    BOOL first = indexPath.row == 0;
    BOOL last = indexPath.row == rows - 1;
    CACornerMask corners = 0;
    if (separate || rows <= 1) {
        corners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner |
            kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    } else if (first) {
        corners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    } else if (last) {
        corners = kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    }
    cell.layer.cornerRadius = corners ? radius : 0.0;
    cell.layer.cornerCurve = kCACornerCurveContinuous;
    cell.layer.maskedCorners = corners;
    cell.layer.masksToBounds = corners != 0;
    if (WCLiquidGlassPreferences.homeLiquidBackgroundEnabled) {
        cell.backgroundView = state.originalBackgroundView;
        cell.backgroundColor = UIColor.clearColor;
        cell.contentView.backgroundColor = UIColor.clearColor;
        WCLiquidGlassHomeCornerPrepareContent(cell, 0);
        if (!state.cardBackground) {
            state.cardBackground = [[WCLiquidGlassHomeCornerBackgroundView alloc] initWithFrame:CGRectZero];
            state.cardBackground.userInteractionEnabled = NO;
        }
        [state.cardBackground wc_updateAppearance];
        state.cardBackground.frame = cell.contentView.bounds;
        state.cardBackground.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        if (state.cardBackground.superview != cell.contentView) {
            [state.cardBackground removeFromSuperview];
            [cell.contentView insertSubview:state.cardBackground atIndex:0];
        }
    } else {
        [state.cardBackground removeFromSuperview];
        cell.backgroundView = state.originalBackgroundView;
        cell.backgroundColor = state.originalBackgroundColor;
        cell.contentView.backgroundColor = state.originalContentBackgroundColor;
        WCLiquidGlassHomeCornerRestoreContent(cell, 0);
    }
}

static void WCLiquidGlassHomeCornersUpdateTable(UITableView *tableView) {
    WCLiquidGlassHomeCornerTableRole role = WCLiquidGlassHomeCornerRoleForTable(tableView);
    BOOL wasStyled = [objc_getAssociatedObject(tableView, WCLiquidGlassHomeCornerTableStyledKey) boolValue];
    if (role == WCLiquidGlassHomeCornerTableRoleNone && !wasStyled) {
        return;
    }
    if (role != WCLiquidGlassHomeCornerTableRoleNone) {
        WCLiquidGlassHomeCornerApplyTableStyle(tableView);
        objc_setAssociatedObject(tableView,
                                 WCLiquidGlassHomeCornerTableStyledKey,
                                 @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    for (UITableViewCell *cell in tableView.visibleCells) {
        if (role == WCLiquidGlassHomeCornerTableRoleNone) {
            WCLiquidGlassHomeCornerRestoreCell(cell);
        } else {
            WCLiquidGlassHomeCornerApplyCell(tableView, cell, role);
        }
    }
    if (role == WCLiquidGlassHomeCornerTableRoleNone) {
        WCLiquidGlassHomeCornerRestoreTableStyle(tableView);
        objc_setAssociatedObject(tableView,
                                 WCLiquidGlassHomeCornerTableStyledKey,
                                 @NO,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void WCLiquidGlassHomeCornersTableLayoutSubviews(UITableView *self, SEL selector) {
    if (WCLiquidGlassOriginalHomeCornersTableLayoutSubviews) {
        WCLiquidGlassOriginalHomeCornersTableLayoutSubviews(self, selector);
    }
    WCLiquidGlassHomeCornersUpdateTable(self);
}

static void WCLiquidGlassHomeCornersRefreshTablesInView(UIView *view, NSUInteger depth) {
    if (!view || depth > 24) {
        return;
    }
    if ([view isKindOfClass:UITableView.class]) {
        WCLiquidGlassHomeCornersUpdateTable((UITableView *)view);
    }
    for (UIView *subview in view.subviews) {
        WCLiquidGlassHomeCornersRefreshTablesInView(subview, depth + 1);
    }
}

static void WCLiquidGlassHomeCornersRefreshVisibleTables(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) {
            continue;
        }
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            WCLiquidGlassHomeCornersRefreshTablesInView(window, 0);
        }
    }
}

void WCLiquidGlassInstallHomeCornersHooks(void) {
    if (WCLiquidGlassHomeCornersHooksInstalled) {
        return;
    }
    Method layoutMethod = class_getInstanceMethod(UITableView.class, @selector(layoutSubviews));
    if (!layoutMethod) {
        if (!WCLiquidGlassHomeCornersHookRetryScheduled && WCLiquidGlassHomeCornersHookInstallAttempts < 10) {
            WCLiquidGlassHomeCornersHookRetryScheduled = YES;
            WCLiquidGlassHomeCornersHookInstallAttempts += 1;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                WCLiquidGlassHomeCornersHookRetryScheduled = NO;
                WCLiquidGlassInstallHomeCornersHooks();
            });
        }
        return;
    }
    MSHookMessageEx(UITableView.class,
                    @selector(layoutSubviews),
                    (IMP)&WCLiquidGlassHomeCornersTableLayoutSubviews,
                    (IMP *)&WCLiquidGlassOriginalHomeCornersTableLayoutSubviews);
    WCLiquidGlassHomeCornersHooksInstalled = WCLiquidGlassOriginalHomeCornersTableLayoutSubviews != NULL;
    if (WCLiquidGlassHomeCornersHooksInstalled) {
        [NSNotificationCenter.defaultCenter addObserverForName:WCLiquidGlassPreferencesDidChangeNotification
                                                          object:nil
                                                           queue:NSOperationQueue.mainQueue
                                                      usingBlock:^(__unused NSNotification *notification) {
            WCLiquidGlassHomeCornersConfigurationEpoch += 1;
            WCLiquidGlassHomeCornersRefreshVisibleTables();
        }];
    }
}

typedef NS_ENUM(NSInteger, WCLiquidGlassHomeCornersControlTag) {
    WCLiquidGlassHomeCornersControlTagInset = 1,
    WCLiquidGlassHomeCornersControlTagHomeRadius,
    WCLiquidGlassHomeCornersControlTagOtherTabsRadius
};

static NSString *WCLiquidGlassHomeCornersDisplayValue(CGFloat value) {
    return [NSString stringWithFormat:@"%.0f pt", value];
}

static UIFont *WCLiquidGlassHomeCornersFont(CGFloat size, UIFontWeight weight) {
    NSString *fontName = weight >= UIFontWeightSemibold ? @"PingFangSC-Semibold" : @"PingFangSC-Regular";
    UIFont *font = [UIFont fontWithName:fontName size:size] ?: [UIFont systemFontOfSize:size weight:weight];
    return [[UIFontMetrics metricsForTextStyle:size >= 16.0 ? UIFontTextStyleBody : UIFontTextStyleFootnote] scaledFontForFont:font];
}

static UIColor *WCLiquidGlassHomeCornersCardColor(void) {
    WCLiquidGlassGlassAppearance appearance = WCLiquidGlassPreferences.glassAppearance;
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        BOOL dark = traits.userInterfaceStyle == UIUserInterfaceStyleDark;
        if (appearance == WCLiquidGlassGlassAppearanceClear) {
            return dark ? [UIColor colorWithWhite:1.0 alpha:0.10] : [UIColor colorWithWhite:1.0 alpha:0.68];
        }
        if (appearance == WCLiquidGlassGlassAppearanceTinted) {
            return dark ? [UIColor colorWithRed:0.72 green:0.82 blue:1.0 alpha:0.20]
                        : [UIColor colorWithRed:0.95 green:0.97 blue:1.0 alpha:0.92];
        }
        return dark ? [UIColor colorWithWhite:0.14 alpha:0.94] : [UIColor colorWithWhite:1.0 alpha:0.84];
    }];
}

@interface WCLiquidGlassHomeCornersBackdropView : UIView
@property(nonatomic, strong) CAGradientLayer *gradientLayer;
@end

@implementation WCLiquidGlassHomeCornersBackdropView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _gradientLayer = [CAGradientLayer layer];
        _gradientLayer.startPoint = CGPointMake(0.0, 0.0);
        _gradientLayer.endPoint = CGPointMake(1.0, 1.0);
        [self.layer insertSublayer:_gradientLayer atIndex:0];
        [self wc_updateColors];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.gradientLayer.frame = self.bounds;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self wc_updateColors];
    }
}

- (void)wc_updateColors {
    BOOL dark = self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    self.gradientLayer.colors = @[
        (id)(dark ? [UIColor colorWithRed:0.06 green:0.10 blue:0.16 alpha:1.0] : [UIColor colorWithRed:0.90 green:0.96 blue:1.0 alpha:1.0]).CGColor,
        (id)(dark ? [UIColor colorWithRed:0.12 green:0.08 blue:0.18 alpha:1.0] : [UIColor colorWithRed:0.97 green:0.92 blue:1.0 alpha:1.0]).CGColor,
        (id)(dark ? [UIColor colorWithRed:0.05 green:0.13 blue:0.15 alpha:1.0] : [UIColor colorWithRed:0.91 green:0.98 blue:0.96 alpha:1.0]).CGColor
    ];
}

@end

static void WCLiquidGlassHomeCornersStyleCardCell(UITableViewCell *cell,
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
    cell.backgroundColor = WCLiquidGlassHomeCornersCardColor();
    cell.contentView.backgroundColor = UIColor.clearColor;
    cell.layer.cornerRadius = (first || last) ? 24.0 : 0.0;
    cell.layer.cornerCurve = kCACornerCurveContinuous;
    cell.layer.maskedCorners = corners;
    cell.layer.masksToBounds = YES;
}

@implementation WCLiquidGlassHomeCornersController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"首页圆角";
    self.view.backgroundColor = UIColor.clearColor;
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.backgroundView = [[WCLiquidGlassHomeCornersBackdropView alloc] initWithFrame:CGRectZero];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 64.0;
    self.tableView.separatorColor = [UIColor.separatorColor colorWithAlphaComponent:0.30];
    self.tableView.tableHeaderView = [self wc_makeHeaderView];
    [WCLiquidGlassPreferences registerDefaults];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(wc_preferencesChanged:)
                                               name:WCLiquidGlassPreferencesDidChangeNotification
                                             object:nil];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIView *header = self.tableView.tableHeaderView;
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    if (header && fabs(CGRectGetWidth(header.frame) - width) > 0.5) {
        header.frame = CGRectMake(0.0, 0.0, width, 154.0);
        self.tableView.tableHeaderView = header;
    }
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        self.tableView.tableHeaderView = [self wc_makeHeaderView];
        [self.tableView reloadData];
    }
}

- (UIView *)wc_makeHeaderView {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 320.0, 154.0)];
    UIVisualEffectView *card = [[UIVisualEffectView alloc] initWithEffect:WCLiquidGlassCurrentGlassEffect()];
    card.frame = CGRectMake(20.0, 14.0, 280.0, 126.0);
    card.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    card.layer.cornerRadius = 28.0;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.clipsToBounds = YES;

    UIView *iconBackground = [[UIView alloc] initWithFrame:CGRectMake(20.0, 33.0, 56.0, 56.0)];
    iconBackground.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:1.0 alpha:0.16]
            : [UIColor colorWithWhite:1.0 alpha:0.58];
    }];
    iconBackground.layer.cornerRadius = 18.0;
    iconBackground.layer.cornerCurve = kCACornerCurveContinuous;
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"rectangle.inset.filled"]];
    icon.frame = CGRectInset(iconBackground.bounds, 14.0, 14.0);
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.tintColor = UIColor.labelColor;
    [iconBackground addSubview:icon];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(92.0, 30.0, 168.0, 28.0)];
    title.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    title.text = @"首页圆角";
    title.font = WCLiquidGlassHomeCornersFont(22.0, UIFontWeightSemibold);
    title.adjustsFontForContentSizeCategory = YES;
    title.textColor = UIColor.labelColor;
    UILabel *detail = [[UILabel alloc] initWithFrame:CGRectMake(92.0, 62.0, 168.0, 42.0)];
    detail.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    detail.text = @"以圆润的液态卡片呈现主页会话";
    detail.font = WCLiquidGlassHomeCornersFont(14.0, UIFontWeightRegular);
    detail.adjustsFontForContentSizeCategory = YES;
    detail.textColor = UIColor.secondaryLabelColor;
    detail.numberOfLines = 2;
    [header addSubview:card];
    [card.contentView addSubview:iconBackground];
    [card.contentView addSubview:title];
    [card.contentView addSubview:detail];
    return header;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 7 : 2;
}

- (void)tableView:(UITableView *)tableView
  willDisplayCell:(UITableViewCell *)cell
forRowAtIndexPath:(NSIndexPath *)indexPath {
    WCLiquidGlassHomeCornersStyleCardCell(cell, indexPath, tableView);
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"卡片化主页列表" : @"同步到发现/通讯录/我";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return @"会话行两侧缩进并呈现圆角卡片。开启“液态背景”后，背景会跟随插件“液态效果”设置。";
    }
    return @"同步后，发现、通讯录和我页面会使用相同的卡片背景与左右缩进；圆角可单独调整。";
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20.0, 4.0, 300.0, 24.0)];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    label.text = [self tableView:tableView titleForHeaderInSection:section];
    label.font = WCLiquidGlassHomeCornersFont(13.0, UIFontWeightSemibold);
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = UIColor.secondaryLabelColor;
    return label;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 32.0;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20.0, 3.0, CGRectGetWidth(tableView.bounds) - 40.0, 58.0)];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    label.text = [self tableView:tableView titleForFooterInSection:section];
    label.font = WCLiquidGlassHomeCornersFont(13.0, UIFontWeightRegular);
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = UIColor.secondaryLabelColor;
    label.numberOfLines = 0;
    return label;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return section == 0 ? 66.0 : 52.0;
}

- (UITableViewCell *)wc_cellWithTitle:(NSString *)title
                                detail:(nullable NSString *)detail
                               enabled:(BOOL)enabled
                            identifier:(NSString *)identifier {
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    }
    cell.textLabel.text = title;
    cell.textLabel.font = WCLiquidGlassHomeCornersFont(17.0, UIFontWeightRegular);
    cell.textLabel.adjustsFontForContentSizeCategory = YES;
    cell.detailTextLabel.text = detail;
    cell.detailTextLabel.font = WCLiquidGlassHomeCornersFont(13.0, UIFontWeightRegular);
    cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
    cell.textLabel.textColor = enabled ? UIColor.labelColor : UIColor.tertiaryLabelColor;
    cell.detailTextLabel.textColor = enabled ? UIColor.secondaryLabelColor : UIColor.tertiaryLabelColor;
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = enabled ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    cell.userInteractionEnabled = enabled;
    return cell;
}

- (UITableViewCell *)wc_switchCellWithTitle:(NSString *)title
                                      detail:(nullable NSString *)detail
                                         on:(BOOL)on
                                     enabled:(BOOL)enabled
                                     action:(SEL)action {
    UITableViewCell *cell = [self wc_cellWithTitle:title detail:detail enabled:enabled identifier:@"WCLiquidGlassHomeCornersSwitchCell"];
    UISwitch *toggle = [[UISwitch alloc] init];
    toggle.on = on;
    toggle.enabled = enabled;
    [toggle addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = toggle;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (UITableViewCell *)wc_sliderCellWithTitle:(NSString *)title
                                       value:(CGFloat)value
                                     minimum:(CGFloat)minimum
                                     maximum:(CGFloat)maximum
                                         tag:(WCLiquidGlassHomeCornersControlTag)tag
                                     enabled:(BOOL)enabled {
    UITableViewCell *cell = [self wc_cellWithTitle:title
                                             detail:WCLiquidGlassHomeCornersDisplayValue(value)
                                            enabled:enabled
                                         identifier:@"WCLiquidGlassHomeCornersSliderCell"];
    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(0.0, 0.0, 152.0, 31.0)];
    slider.minimumValue = minimum;
    slider.maximumValue = maximum;
    slider.value = value;
    slider.tag = tag;
    slider.enabled = enabled;
    [slider addTarget:self action:@selector(wc_sliderChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = slider;
    cell.accessibilityHint = enabled ? @"点按滑块外的区域可直接输入数值" : nil;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    BOOL active = WCLiquidGlassPreferences.homeCornersEnabled;
    if (indexPath.section == 0) {
        switch (indexPath.row) {
            case 0:
                return [self wc_switchCellWithTitle:@"卡片化主页列表"
                                               detail:@"会话行两侧缩进并加圆角卡片"
                                                  on:active
                                              enabled:YES
                                              action:@selector(wc_homeCornersChanged:)];
            case 1:
                return [self wc_sliderCellWithTitle:@"左右缩进"
                                               value:WCLiquidGlassPreferences.homeCornerInset
                                             minimum:0.0
                                             maximum:32.0
                                                 tag:WCLiquidGlassHomeCornersControlTagInset
                                             enabled:active];
            case 2:
                return [self wc_sliderCellWithTitle:@"主页圆角"
                                               value:WCLiquidGlassPreferences.homeCornerRadius
                                             minimum:0.0
                                             maximum:52.0
                                                 tag:WCLiquidGlassHomeCornersControlTagHomeRadius
                                             enabled:active];
            case 3:
                return [self wc_switchCellWithTitle:@"每条独立圆角卡片"
                                               detail:@"每条会话独立成圆角卡片，可设置会话间距"
                                                  on:WCLiquidGlassPreferences.homeSeparateCardsEnabled
                                              enabled:active
                                              action:@selector(wc_separateCardsChanged:)];
            case 4: {
                UITableViewCell *cell = [self wc_cellWithTitle:@"会话间距"
                                                         detail:WCLiquidGlassHomeCornersDisplayValue(WCLiquidGlassPreferences.homeCardGap)
                                                        enabled:active
                                                     identifier:@"WCLiquidGlassHomeCornersValueCell"];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                return cell;
            }
            case 5:
                return [self wc_switchCellWithTitle:@"置顶会话间隙"
                                               detail:@"置顶与普通会话之间保留卡片间距；关闭则连续显示"
                                                  on:WCLiquidGlassPreferences.homePinnedCardGapEnabled
                                              enabled:active && WCLiquidGlassPreferences.homeSeparateCardsEnabled
                                              action:@selector(wc_pinnedGapChanged:)];
            case 6:
                return [self wc_switchCellWithTitle:@"液态背景"
                                               detail:@"卡片背景跟随“液态效果”"
                                                  on:WCLiquidGlassPreferences.homeLiquidBackgroundEnabled
                                              enabled:active
                                              action:@selector(wc_liquidBackgroundChanged:)];
            default:
                break;
        }
    }
    if (indexPath.row == 0) {
        return [self wc_switchCellWithTitle:@"同步到发现/通讯录/我"
                                       detail:@"这三页也套用卡片样式（圆角可在下方单独调整）"
                                          on:WCLiquidGlassPreferences.homeCornersSyncOtherTabsEnabled
                                      enabled:active
                                      action:@selector(wc_syncOtherTabsChanged:)];
    }
    return [self wc_sliderCellWithTitle:@"发现/通讯录/我 圆角"
                                   value:WCLiquidGlassPreferences.homeOtherTabsCornerRadius
                                 minimum:0.0
                                 maximum:52.0
                                     tag:WCLiquidGlassHomeCornersControlTagOtherTabsRadius
                                 enabled:active && WCLiquidGlassPreferences.homeCornersSyncOtherTabsEnabled];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0 && indexPath.row == 1) {
        [self wc_presentValueInputWithTitle:@"左右缩进" value:WCLiquidGlassPreferences.homeCornerInset minimum:0.0 maximum:32.0 setter:^(CGFloat value) {
            [WCLiquidGlassPreferences setHomeCornerInset:value];
        }];
    } else if (indexPath.section == 0 && indexPath.row == 2) {
        [self wc_presentValueInputWithTitle:@"主页圆角" value:WCLiquidGlassPreferences.homeCornerRadius minimum:0.0 maximum:52.0 setter:^(CGFloat value) {
            [WCLiquidGlassPreferences setHomeCornerRadius:value];
        }];
    } else if (indexPath.section == 0 && indexPath.row == 4) {
        [self wc_presentValueInputWithTitle:@"会话间距" value:WCLiquidGlassPreferences.homeCardGap minimum:0.0 maximum:24.0 setter:^(CGFloat value) {
            [WCLiquidGlassPreferences setHomeCardGap:value];
        }];
    } else if (indexPath.section == 1 && indexPath.row == 1) {
        [self wc_presentValueInputWithTitle:@"发现/通讯录/我 圆角" value:WCLiquidGlassPreferences.homeOtherTabsCornerRadius minimum:0.0 maximum:52.0 setter:^(CGFloat value) {
            [WCLiquidGlassPreferences setHomeOtherTabsCornerRadius:value];
        }];
    }
}

- (void)wc_homeCornersChanged:(UISwitch *)sender {
    [WCLiquidGlassPreferences setHomeCornersEnabled:sender.isOn];
}

- (void)wc_separateCardsChanged:(UISwitch *)sender {
    [WCLiquidGlassPreferences setHomeSeparateCardsEnabled:sender.isOn];
}

- (void)wc_pinnedGapChanged:(UISwitch *)sender {
    [WCLiquidGlassPreferences setHomePinnedCardGapEnabled:sender.isOn];
}

- (void)wc_liquidBackgroundChanged:(UISwitch *)sender {
    [WCLiquidGlassPreferences setHomeLiquidBackgroundEnabled:sender.isOn];
}

- (void)wc_syncOtherTabsChanged:(UISwitch *)sender {
    [WCLiquidGlassPreferences setHomeCornersSyncOtherTabsEnabled:sender.isOn];
}

- (void)wc_sliderChanged:(UISlider *)slider {
    CGFloat value = round(slider.value);
    [slider setValue:value animated:NO];
    switch (slider.tag) {
        case WCLiquidGlassHomeCornersControlTagInset:
            [WCLiquidGlassPreferences setHomeCornerInset:value];
            break;
        case WCLiquidGlassHomeCornersControlTagHomeRadius:
            [WCLiquidGlassPreferences setHomeCornerRadius:value];
            break;
        case WCLiquidGlassHomeCornersControlTagOtherTabsRadius:
            [WCLiquidGlassPreferences setHomeOtherTabsCornerRadius:value];
            break;
    }
}

- (void)wc_presentValueInputWithTitle:(NSString *)title
                                 value:(CGFloat)value
                               minimum:(CGFloat)minimum
                               maximum:(CGFloat)maximum
                                setter:(void (^)(CGFloat value))setter {
    NSString *message = [NSString stringWithFormat:@"输入 %.0f–%.0f 之间的 pt 数值", minimum, maximum];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.keyboardType = UIKeyboardTypeDecimalPad;
        textField.text = [NSString stringWithFormat:@"%.0f", value];
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        CGFloat enteredValue = alert.textFields.firstObject.text.doubleValue;
        setter(MIN(maximum, MAX(minimum, enteredValue)));
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)wc_preferencesChanged:(NSNotification *)notification {
    [self.tableView reloadData];
}

@end
