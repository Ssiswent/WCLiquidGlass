#import "WCLiquidGlassHomeCorners.h"

#import <CydiaSubstrate.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "WCLiquidGlassMenu.h"
#import "WCLiquidGlassCrashLogger.h"
#import "WCLiquidGlassPreferences.h"

static const void *WCLiquidGlassHomeCornerStateKey = &WCLiquidGlassHomeCornerStateKey;
static const void *WCLiquidGlassHomeCornerTableStyledKey = &WCLiquidGlassHomeCornerTableStyledKey;
static const void *WCLiquidGlassHomeCornerTableRoleKey = &WCLiquidGlassHomeCornerTableRoleKey;
static const void *WCLiquidGlassHomeCornerTableRoleEpochKey = &WCLiquidGlassHomeCornerTableRoleEpochKey;
static const void *WCLiquidGlassHomeCornerTableRoleRetryScheduledKey = &WCLiquidGlassHomeCornerTableRoleRetryScheduledKey;
static const void *WCLiquidGlassHomeCornerTableRoleRetryCountKey = &WCLiquidGlassHomeCornerTableRoleRetryCountKey;
static const void *WCLiquidGlassHomeCornerTableStateKey = &WCLiquidGlassHomeCornerTableStateKey;
static const void *WCLiquidGlassHomeCornerContentSubviewStateKey = &WCLiquidGlassHomeCornerContentSubviewStateKey;
static const void *WCLiquidGlassHomeCornerNativeHeightEpochKey = &WCLiquidGlassHomeCornerNativeHeightEpochKey;
static const void *WCLiquidGlassHomeCornerContactsAvatarKey = &WCLiquidGlassHomeCornerContactsAvatarKey;
static void (*WCLiquidGlassOriginalHomeCornerCellLayoutSubviews)(UITableViewCell *, SEL) = NULL;
static void (*WCLiquidGlassOriginalStandardTabCellLayoutSubviews)(UITableViewCell *, SEL) = NULL;
static void (*WCLiquidGlassOriginalContactsCellLayoutSubviews)(UITableViewCell *, SEL) = NULL;
static void (*WCLiquidGlassOriginalContactsAvatarLayoutSubviews)(UIView *, SEL) = NULL;
static void (*WCLiquidGlassOriginalHomeCornerCellSetBackgroundColor)(UITableViewCell *, SEL, UIColor *) = NULL;
static void (*WCLiquidGlassOriginalHomeCornerTableLayoutSubviews)(UITableView *, SEL) = NULL;
static CGFloat (*WCLiquidGlassOriginalHomeHeightForRow)(id, SEL, UITableView *, NSIndexPath *) = NULL;
static CGFloat (*WCLiquidGlassOriginalContactsHeightForHeader)(id, SEL, UITableView *, NSInteger) = NULL;
static BOOL WCLiquidGlassHomeCornersHooksInstalled = NO;
static BOOL WCLiquidGlassHomeCornerCellHookRetryScheduled = NO;
static NSUInteger WCLiquidGlassHomeCornerCellHookInstallAttempts = 0;
static BOOL WCLiquidGlassHomeCornerContactsCellHookRetryScheduled = NO;
static NSUInteger WCLiquidGlassHomeCornerContactsCellHookInstallAttempts = 0;
static BOOL WCLiquidGlassHomeCornerContactsAvatarHookRetryScheduled = NO;
static NSUInteger WCLiquidGlassHomeCornerContactsAvatarHookInstallAttempts = 0;
static __thread BOOL WCLiquidGlassHomeCornerCellLayoutApplying = NO;
static __thread BOOL WCLiquidGlassHomeCornerTableLayoutApplying = NO;
static NSUInteger WCLiquidGlassHomeCornersConfigurationEpoch = 1;

typedef NS_ENUM(NSInteger, WCLiquidGlassHomeCornerTableRole) {
    WCLiquidGlassHomeCornerTableRoleNone = 0,
    WCLiquidGlassHomeCornerTableRoleHome,
    WCLiquidGlassHomeCornerTableRoleOtherTab,
    WCLiquidGlassHomeCornerTableRoleFindFriend,
    WCLiquidGlassHomeCornerTableRoleMore
};

@interface WCLiquidGlassHomeCornerCellState : NSObject
@property(nonatomic, assign) CGRect baseFrame;
@property(nonatomic, assign) CGRect appliedFrame;
@property(nonatomic, assign) BOOL hasAppliedFrame;
@property(nonatomic, strong, nullable) UIView *originalBackgroundView;
@property(nonatomic, strong, nullable) UIColor *originalBackgroundColor;
@property(nonatomic, strong, nullable) UIColor *originalContentBackgroundColor;
@property(nonatomic, assign) CGRect baseContentFrame;
@property(nonatomic, assign) CGRect appliedContentFrame;
@property(nonatomic, assign) BOOL hasAppliedContentFrame;
@property(nonatomic, assign) CGRect baseInnerContentFrame;
@property(nonatomic, assign) CGRect appliedInnerContentFrame;
@property(nonatomic, assign) BOOL hasAppliedInnerContentFrame;
@property(nonatomic, assign) UITableViewCellSelectionStyle originalSelectionStyle;
@property(nonatomic, strong, nullable) UIView *originalSelectedBackgroundView;
@property(nonatomic, assign) CGFloat originalCornerRadius;
@property(nonatomic, assign) CACornerMask originalMaskedCorners;
@property(nonatomic, assign) BOOL originalMasksToBounds;
@property(nonatomic, strong, nullable) UIColor *appliedBackgroundColor;
@property(nonatomic, assign) NSUInteger appliedConfigurationEpoch;
@property(nonatomic, strong, nullable) UIVisualEffectView *glassOverlay;
@property(nonatomic, assign) NSInteger appliedGlassState;
@property(nonatomic, assign) NSInteger appliedGlassTintState;
@property(nonatomic, assign) BOOL captured;
@end

@implementation WCLiquidGlassHomeCornerCellState
@end

@interface WCLiquidGlassHomeCornerContentSubviewState : NSObject
@property(nonatomic, assign) CGRect baseFrame;
@property(nonatomic, assign) CGRect appliedFrame;
@property(nonatomic, assign) BOOL hasAppliedFrame;
@end

@implementation WCLiquidGlassHomeCornerContentSubviewState
@end

@interface WCLiquidGlassHomeCornerSectionState : NSObject
@property(nonatomic, strong) UIVisualEffectView *glassView;
@property(nonatomic, assign) NSInteger appliedGlassState;
@end

@implementation WCLiquidGlassHomeCornerSectionState
@end

@interface WCLiquidGlassHomeCornerTableState : NSObject
@property(nonatomic, assign) UITableViewCellSeparatorStyle originalSeparatorStyle;
@property(nonatomic, strong, nullable) UIColor *originalSeparatorColor;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, WCLiquidGlassHomeCornerSectionState *> *sectionStates;
@property(nonatomic, assign) BOOL captured;
@end

@implementation WCLiquidGlassHomeCornerTableState
@end

static void WCLiquidGlassHomeCornersUpdateTable(UITableView *tableView);
static void WCLiquidGlassInstallHomeCornerStandardTabCellLayoutHook(void);
static CGRect WCLiquidGlassHomeCornerTargetFrame(UITableView *tableView,
                                                  NSIndexPath *indexPath,
                                                  WCLiquidGlassHomeCornerTableRole role,
                                                  CGRect baseFrame);
static NSRange WCLiquidGlassHomeCornerVisualSectionRange(
    UITableView *tableView,
    NSInteger section,
    WCLiquidGlassHomeCornerTableRole role);

static WCLiquidGlassHomeCornerTableState *WCLiquidGlassHomeCornerStateForTable(UITableView *tableView) {
    WCLiquidGlassHomeCornerTableState *state = objc_getAssociatedObject(tableView, WCLiquidGlassHomeCornerTableStateKey);
    if (!state) {
        state = [[WCLiquidGlassHomeCornerTableState alloc] init];
        state.originalSeparatorStyle = tableView.separatorStyle;
        state.originalSeparatorColor = tableView.separatorColor;
        state.sectionStates = [NSMutableDictionary dictionary];
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
    BOOL needsSeparatorRefresh = NO;
    if (tableView.separatorStyle != UITableViewCellSeparatorStyleNone) {
        tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
        needsSeparatorRefresh = YES;
    }
    if (tableView.separatorColor != UIColor.clearColor) {
        tableView.separatorColor = UIColor.clearColor;
        needsSeparatorRefresh = YES;
    }
    if (!needsSeparatorRefresh) {
        return;
    }
    for (UIView *subview in tableView.subviews) {
        NSString *className = NSStringFromClass(subview.class).lowercaseString;
        if ([className containsString:@"separator"] && !subview.hidden) {
            subview.hidden = YES;
        }
    }
}

static void WCLiquidGlassHomeCornerRestoreTableStyle(UITableView *tableView) {
    WCLiquidGlassHomeCornerTableState *state = objc_getAssociatedObject(tableView, WCLiquidGlassHomeCornerTableStateKey);
    if (state && state.captured) {
        tableView.separatorStyle = state.originalSeparatorStyle;
        tableView.separatorColor = state.originalSeparatorColor;
        for (WCLiquidGlassHomeCornerSectionState *sectionState in state.sectionStates.allValues) {
            [sectionState.glassView removeFromSuperview];
        }
        [state.sectionStates removeAllObjects];
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

static BOOL WCLiquidGlassHomeCornerControllerOwnsTable(UIViewController *controller,
                                                       UITableView *tableView,
                                                       NSArray<NSString *> *tokens,
                                                       NSUInteger depth) {
    if (!controller || depth > 12) {
        return NO;
    }
    NSString *name = NSStringFromClass(controller.class);
    if (controller.isViewLoaded &&
        WCLiquidGlassHomeCornerNameContains(name, tokens) &&
        [tableView isDescendantOfView:controller.view]) {
        return YES;
    }
    if (WCLiquidGlassHomeCornerControllerOwnsTable(controller.presentedViewController, tableView, tokens, depth + 1)) {
        return YES;
    }
    for (UIViewController *child in controller.childViewControllers) {
        if (WCLiquidGlassHomeCornerControllerOwnsTable(child, tableView, tokens, depth + 1)) {
            return YES;
        }
    }
    return NO;
}

static BOOL WCLiquidGlassHomeCornerTableBelongsToControllers(UITableView *tableView,
                                                             NSArray<NSString *> *tokens) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) {
            continue;
        }
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (WCLiquidGlassHomeCornerControllerOwnsTable(window.rootViewController, tableView, tokens, 0)) {
                return YES;
            }
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
    if (WCLiquidGlassHomeCornerTableBelongsToControllers(tableView, @[@"findfriendentryviewcontroller"])) {
        return WCLiquidGlassHomeCornerTableRoleFindFriend;
    }
    if (WCLiquidGlassHomeCornerTableBelongsToControllers(tableView, @[@"moreviewcontroller"])) {
        return WCLiquidGlassHomeCornerTableRoleMore;
    }
    return WCLiquidGlassHomeCornerTableBelongsToControllers(tableView, @[@"contactsviewcontroller"])
        ? WCLiquidGlassHomeCornerTableRoleOtherTab
        : WCLiquidGlassHomeCornerTableRoleNone;
}

static void WCLiquidGlassHomeCornerScheduleRoleRetry(UITableView *tableView) {
    if ([objc_getAssociatedObject(tableView, WCLiquidGlassHomeCornerTableRoleRetryScheduledKey) boolValue]) {
        return;
    }
    NSUInteger retryCount = [objc_getAssociatedObject(tableView, WCLiquidGlassHomeCornerTableRoleRetryCountKey) unsignedIntegerValue];
    if (retryCount >= 3) {
        return;
    }
    objc_setAssociatedObject(tableView,
                             WCLiquidGlassHomeCornerTableRoleRetryScheduledKey,
                             @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(tableView,
                             WCLiquidGlassHomeCornerTableRoleRetryCountKey,
                             @(retryCount + 1),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        objc_setAssociatedObject(tableView,
                                 WCLiquidGlassHomeCornerTableRoleRetryScheduledKey,
                                 @NO,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(tableView,
                                 WCLiquidGlassHomeCornerTableRoleEpochKey,
                                 nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        WCLiquidGlassHomeCornersUpdateTable(tableView);
        [tableView setNeedsLayout];
    });
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
    if (role == WCLiquidGlassHomeCornerTableRoleNone && WCLiquidGlassPreferences.homeCornersEnabled) {
        WCLiquidGlassHomeCornerScheduleRoleRetry(tableView);
    } else if (role != WCLiquidGlassHomeCornerTableRoleNone) {
        objc_setAssociatedObject(tableView,
                                 WCLiquidGlassHomeCornerTableRoleRetryCountKey,
                                 @0,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
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
        state.originalSelectionStyle = cell.selectionStyle;
        state.originalSelectedBackgroundView = cell.selectedBackgroundView;
        state.originalCornerRadius = cell.layer.cornerRadius;
        state.originalMaskedCorners = cell.layer.maskedCorners;
        state.originalMasksToBounds = cell.layer.masksToBounds;
        state.captured = YES;
    }
    return state;
}

static WCLiquidGlassHomeCornerContentSubviewState *WCLiquidGlassHomeCornerStateForContentSubview(
    UIView *subview) {
    WCLiquidGlassHomeCornerContentSubviewState *state =
        objc_getAssociatedObject(subview, WCLiquidGlassHomeCornerContentSubviewStateKey);
    if (!state) {
        state = [[WCLiquidGlassHomeCornerContentSubviewState alloc] init];
        objc_setAssociatedObject(subview,
                                 WCLiquidGlassHomeCornerContentSubviewStateKey,
                                 state,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return state;
}

static CGRect WCLiquidGlassHomeCornerTargetStandardTabContentSubviewFrame(
    UIView *contentView,
    CGRect baseFrame) {
    CGFloat midpoint = CGRectGetMidX(contentView.bounds);
    CGRect targetFrame = baseFrame;
    if (CGRectGetMaxX(baseFrame) <= midpoint) {
        targetFrame.origin.x += 16.0;
    } else if (CGRectGetMinX(baseFrame) >= midpoint) {
        targetFrame.origin.x -= 16.0;
    }
    return CGRectIntegral(targetFrame);
}

static BOOL WCLiquidGlassHomeCornerApplyStandardTabContentInset(
    UITableViewCell *cell,
    WCLiquidGlassHomeCornerCellState *cellState) {
    BOOL changed = NO;
    UIView *contentView = cell.contentView;
    CGFloat contentWidth = CGRectGetWidth(contentView.bounds);
    for (UIView *subview in contentView.subviews) {
        if (subview == cellState.glassOverlay || subview.hidden ||
            CGRectIsEmpty(subview.frame) ||
            CGRectGetWidth(subview.frame) >= contentWidth - 1.0) {
            continue;
        }
        NSString *className = NSStringFromClass(subview.class).lowercaseString;
        if ([className containsString:@"separator"]) {
            continue;
        }
        WCLiquidGlassHomeCornerContentSubviewState *state =
            WCLiquidGlassHomeCornerStateForContentSubview(subview);
        CGRect baseFrame = subview.frame;
        if (state.hasAppliedFrame && CGRectEqualToRect(baseFrame, state.appliedFrame)) {
            baseFrame = state.baseFrame;
        }
        CGRect targetFrame = WCLiquidGlassHomeCornerTargetStandardTabContentSubviewFrame(
            contentView,
            baseFrame);
        state.baseFrame = baseFrame;
        state.appliedFrame = targetFrame;
        state.hasAppliedFrame = YES;
        if (!CGRectEqualToRect(subview.frame, targetFrame)) {
            subview.frame = targetFrame;
            changed = YES;
        }
    }
    return changed;
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
    if (state.hasAppliedContentFrame &&
        CGRectEqualToRect(cell.contentView.frame, state.appliedContentFrame)) {
        cell.contentView.frame = state.baseContentFrame;
    }
    UIView *innerContentView = cell.contentView.subviews.firstObject;
    if (state.hasAppliedInnerContentFrame &&
        CGRectEqualToRect(innerContentView.frame, state.appliedInnerContentFrame)) {
        innerContentView.frame = state.baseInnerContentFrame;
    }
    cell.selectionStyle = state.originalSelectionStyle;
    cell.selectedBackgroundView = state.originalSelectedBackgroundView;
    cell.layer.cornerRadius = state.originalCornerRadius;
    cell.layer.maskedCorners = state.originalMaskedCorners;
    cell.layer.masksToBounds = state.originalMasksToBounds;
    state.hasAppliedFrame = NO;
    state.hasAppliedContentFrame = NO;
    state.hasAppliedInnerContentFrame = NO;
    state.appliedBackgroundColor = nil;
    state.appliedConfigurationEpoch = 0;
    [state.glassOverlay removeFromSuperview];
    state.glassOverlay = nil;
    state.appliedGlassState = NSIntegerMin;
    state.appliedGlassTintState = NSIntegerMin;
}

static void WCLiquidGlassHomeCornerHideNativeSeparators(UITableViewCell *cell) {
    NSArray<UIView *> *containers = @[cell, cell.contentView];
    for (UIView *container in containers) {
        for (UIView *subview in container.subviews) {
            NSString *className = NSStringFromClass(subview.class).lowercaseString;
            if ([className containsString:@"separator"] && !subview.hidden) {
                subview.hidden = YES;
            }
        }
    }
}

static BOOL WCLiquidGlassHomeCornerHasVisibleBackground(UIView *view) {
    UIColor *backgroundColor = view.backgroundColor;
    if (!backgroundColor) {
        return NO;
    }
    UIColor *resolvedColor = [backgroundColor resolvedColorWithTraitCollection:view.traitCollection];
    return CGColorGetAlpha(resolvedColor.CGColor) > 0.001;
}

static BOOL WCLiquidGlassHomeCornerIsNativeContentContainer(UIView *view,
                                                            WCLiquidGlassHomeCornerCellState *state) {
    if (view == state.glassOverlay || [view isKindOfClass:UIImageView.class] ||
        [view isKindOfClass:UILabel.class]) {
        return NO;
    }
    return YES;
}

static BOOL WCLiquidGlassHomeCornerHasOpaqueNativeContentBackground(UITableViewCell *cell,
                                                                     WCLiquidGlassHomeCornerCellState *state) {
    for (UIView *subview in cell.contentView.subviews) {
        if (WCLiquidGlassHomeCornerIsNativeContentContainer(subview, state) &&
            WCLiquidGlassHomeCornerHasVisibleBackground(subview)) {
            return YES;
        }
    }
    return NO;
}

static void WCLiquidGlassHomeCornerClearNativeContentBackgrounds(UITableViewCell *cell,
                                                                  WCLiquidGlassHomeCornerCellState *state) {
    for (UIView *subview in cell.contentView.subviews) {
        if (WCLiquidGlassHomeCornerIsNativeContentContainer(subview, state) &&
            WCLiquidGlassHomeCornerHasVisibleBackground(subview)) {
            subview.backgroundColor = UIColor.clearColor;
        }
    }
}

static void WCLiquidGlassHomeCornerUpdateGlassOverlay(UITableViewCell *cell,
                                                       WCLiquidGlassHomeCornerCellState *state,
                                                       CGRect overlayFrame,
                                                       CGFloat cornerRadius,
                                                       CACornerMask corners) {
    overlayFrame = CGRectIntegral(overlayFrame);
    UIVisualEffectView *overlay = state.glassOverlay;
    if (!overlay) {
        overlay = [[UIVisualEffectView alloc] initWithEffect:nil];
        overlay.userInteractionEnabled = NO;
        overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        overlay.layer.cornerCurve = kCACornerCurveContinuous;
        state.glassOverlay = overlay;
        state.appliedGlassState = NSIntegerMin;
        state.appliedGlassTintState = NSIntegerMin;
    }
    if (overlay.superview != cell.contentView ||
        cell.contentView.subviews.firstObject != overlay) {
        [overlay removeFromSuperview];
        [cell.contentView insertSubview:overlay atIndex:0];
    }
    if (!CGRectEqualToRect(overlay.frame, overlayFrame)) {
        overlay.frame = overlayFrame;
    }
    if (overlay.layer.cornerRadius != cornerRadius) {
        overlay.layer.cornerRadius = cornerRadius;
    }
    if (overlay.layer.maskedCorners != corners) {
        overlay.layer.maskedCorners = corners;
    }
    if (!overlay.clipsToBounds) {
        overlay.clipsToBounds = YES;
    }
    NSInteger glassState = WCLiquidGlassPreferences.glassAppearance * 10 + cell.traitCollection.userInterfaceStyle;
    if (state.appliedGlassState != glassState) {
        overlay.effect = WCLiquidGlassCurrentGlassEffect();
        state.appliedGlassState = glassState;
    }
    if (state.appliedGlassTintState != glassState) {
        overlay.contentView.backgroundColor = UIColor.clearColor;
        state.appliedGlassTintState = glassState;
    }
    overlay.hidden = NO;
}

static CGRect WCLiquidGlassHomeCornerBaseFrame(UITableViewCell *cell,
                                               WCLiquidGlassHomeCornerCellState *state) {
    CGRect currentFrame = cell.frame;
    if (state.hasAppliedFrame && CGRectEqualToRect(currentFrame, state.appliedFrame)) {
        return state.baseFrame;
    }
    return currentFrame;
}

static CGFloat WCLiquidGlassHomeCornerOriginalHeightForController(id controller,
                                                                   SEL selector,
                                                                   UITableView *tableView,
                                                                   NSIndexPath *indexPath) {
    Class homeClass = NSClassFromString(@"NewMainFrameViewController");
    CGFloat (*original)(id, SEL, UITableView *, NSIndexPath *) = NULL;
    if (homeClass && [controller isKindOfClass:homeClass]) {
        original = WCLiquidGlassOriginalHomeHeightForRow;
    }
    return original ? original(controller, selector, tableView, indexPath) : tableView.rowHeight;
}

static CGFloat WCLiquidGlassHomeCornerRadiusForCell(WCLiquidGlassHomeCornerTableRole role,
                                                     NSIndexPath *indexPath) {
    if (role == WCLiquidGlassHomeCornerTableRoleHome) {
        return indexPath.section == 0 ? 24.0 : WCLiquidGlassPreferences.homeCornerRadius;
    }
    return 26.0;
}

static BOOL WCLiquidGlassHomeCornerUsesIndependentCard(WCLiquidGlassHomeCornerTableRole role,
                                                        NSIndexPath *indexPath) {
    if (role != WCLiquidGlassHomeCornerTableRoleHome) {
        return NO;
    }
    return indexPath.section == 0 || WCLiquidGlassPreferences.homeSeparateCardsEnabled;
}

static CGFloat WCLiquidGlassHomeCornerGapForCell(WCLiquidGlassHomeCornerTableRole role,
                                                 NSIndexPath *indexPath) {
    return role == WCLiquidGlassHomeCornerTableRoleHome &&
        indexPath.section != 0 &&
        WCLiquidGlassPreferences.homeSeparateCardsEnabled
        ? WCLiquidGlassPreferences.homeCardGap
        : 0.0;
}

static CGFloat WCLiquidGlassHomeCornerHeightForRow(id self,
                                                    SEL selector,
                                                    UITableView *tableView,
                                                    NSIndexPath *indexPath) {
    CGFloat nativeHeight = WCLiquidGlassHomeCornerOriginalHeightForController(self,
                                                                                selector,
                                                                                tableView,
                                                                                indexPath);
    WCLiquidGlassHomeCornerTableRole role = WCLiquidGlassHomeCornerRoleForTable(tableView);
    if (!WCLiquidGlassPreferences.homeCornersEnabled || nativeHeight <= 0.0 ||
        role == WCLiquidGlassHomeCornerTableRoleNone) {
        return nativeHeight;
    }
    return nativeHeight + MAX(0.0, WCLiquidGlassHomeCornerGapForCell(role, indexPath));
}

static void WCLiquidGlassHomeCornerInstallHeightHookForClass(Class controllerClass,
                                                              CGFloat (**original)(id, SEL, UITableView *, NSIndexPath *)) {
    SEL selector = @selector(tableView:heightForRowAtIndexPath:);
    if (!controllerClass || *original || !class_getInstanceMethod(controllerClass, selector)) {
        return;
    }
    MSHookMessageEx(controllerClass,
                    selector,
                    (IMP)&WCLiquidGlassHomeCornerHeightForRow,
                    (IMP *)original);
}

static CGFloat WCLiquidGlassHomeCornerHeightForContactsHeader(id self,
                                                               SEL selector,
                                                               UITableView *tableView,
                                                               NSInteger section) {
    CGFloat nativeHeight = WCLiquidGlassOriginalContactsHeightForHeader
        ? WCLiquidGlassOriginalContactsHeightForHeader(self, selector, tableView, section)
        : tableView.sectionHeaderHeight;
    if (!WCLiquidGlassPreferences.homeCornersEnabled || nativeHeight < 0.0) {
        return nativeHeight;
    }
    BOOL beginsVisualGroup = section == 0 || nativeHeight > 1.0;
    return beginsVisualGroup ? nativeHeight + 8.0 : nativeHeight;
}

static void WCLiquidGlassHomeCornerInstallContactsHeaderHeightHook(void) {
    Class contactsClass = NSClassFromString(@"ContactsViewController");
    SEL selector = @selector(tableView:heightForHeaderInSection:);
    if (!contactsClass || WCLiquidGlassOriginalContactsHeightForHeader ||
        !class_getInstanceMethod(contactsClass, selector)) {
        return;
    }
    MSHookMessageEx(contactsClass,
                    selector,
                    (IMP)&WCLiquidGlassHomeCornerHeightForContactsHeader,
                    (IMP *)&WCLiquidGlassOriginalContactsHeightForHeader);
}

static void WCLiquidGlassHomeCornerInstallNativeHeightHooks(void) {
    WCLiquidGlassHomeCornerInstallHeightHookForClass(NSClassFromString(@"NewMainFrameViewController"),
                                                     &WCLiquidGlassOriginalHomeHeightForRow);
    WCLiquidGlassHomeCornerInstallContactsHeaderHeightHook();
}

static void WCLiquidGlassHomeCornerRequestNativeHeightUpdate(UITableView *tableView) {
    NSNumber *epoch = objc_getAssociatedObject(tableView, WCLiquidGlassHomeCornerNativeHeightEpochKey);
    if (epoch.unsignedIntegerValue == WCLiquidGlassHomeCornersConfigurationEpoch) {
        return;
    }
    objc_setAssociatedObject(tableView,
                             WCLiquidGlassHomeCornerNativeHeightEpochKey,
                             @(WCLiquidGlassHomeCornersConfigurationEpoch),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (WCLiquidGlassHomeCornerRoleForTable(tableView) != WCLiquidGlassHomeCornerTableRoleNone) {
            [tableView reloadData];
        }
    });
}

static CGRect WCLiquidGlassHomeCornerTargetFrame(UITableView *tableView,
                                                  NSIndexPath *indexPath,
                                                  WCLiquidGlassHomeCornerTableRole role,
                                                  CGRect baseFrame) {
    CGFloat inset = WCLiquidGlassPreferences.homeCornerInset;
    CGFloat gap = WCLiquidGlassHomeCornerGapForCell(role, indexPath);
    CGRect targetFrame = baseFrame;
    CGFloat tableWidth = CGRectGetWidth(tableView.bounds);
    if (role == WCLiquidGlassHomeCornerTableRoleHome && indexPath.section == 0 &&
        CGRectGetWidth(tableView.window.bounds) > 0.0) {
        tableWidth = CGRectGetWidth(tableView.window.bounds);
    }
    targetFrame.origin.x = inset;
    targetFrame.size.width = MAX(0.0, tableWidth - inset * 2.0);
    if (gap > 0.0) {
        targetFrame.origin.y += gap * 0.5;
        targetFrame.size.height = MAX(0.0, targetFrame.size.height - gap);
    }
    return CGRectIntegral(targetFrame);
}

static void WCLiquidGlassHomeCornerApplyCell(UITableView *tableView,
                                             UITableViewCell *cell,
                                             WCLiquidGlassHomeCornerTableRole role) {
    NSIndexPath *indexPath = [tableView indexPathForCell:cell];
    if (!indexPath) {
        return;
    }
    WCLiquidGlassHomeCornerApplyTableStyle(tableView);
    WCLiquidGlassHomeCornerCellState *state = WCLiquidGlassHomeCornerStateForCell(cell);
    CGRect baseFrame = WCLiquidGlassHomeCornerBaseFrame(cell, state);
    BOOL preservesNativeGeometry = role != WCLiquidGlassHomeCornerTableRoleHome;
    if (preservesNativeGeometry && state.hasAppliedFrame &&
        CGRectEqualToRect(cell.frame, state.appliedFrame)) {
        cell.frame = state.baseFrame;
        baseFrame = cell.frame;
    }
    CGFloat radius = WCLiquidGlassHomeCornerRadiusForCell(role, indexPath);
    BOOL separate = WCLiquidGlassHomeCornerUsesIndependentCard(role, indexPath);
    CGRect targetFrame = preservesNativeGeometry
        ? baseFrame
        : WCLiquidGlassHomeCornerTargetFrame(tableView, indexPath, role, baseFrame);
    BOOL needsFrameUpdate = !preservesNativeGeometry && !CGRectEqualToRect(cell.frame, targetFrame);
    state.baseFrame = baseFrame;
    state.appliedFrame = targetFrame;
    state.hasAppliedFrame = !preservesNativeGeometry;

    CACornerMask corners = separate
        ? kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner |
            kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner
        : 0;
    CGFloat visualCornerRadius = corners ? radius : 0.0;
    CACornerMask cellCorners = preservesNativeGeometry ? 0 : corners;
    CGFloat targetCornerRadius = cellCorners ? radius : 0.0;
    NSInteger glassState = WCLiquidGlassPreferences.glassAppearance * 10 + cell.traitCollection.userInterfaceStyle;
    NSInteger tintState = glassState;
    BOOL isLiquidBackground = WCLiquidGlassPreferences.homeLiquidBackgroundEnabled;
    BOOL usesCellGlass = isLiquidBackground && separate;
    BOOL suppressesSelectionEffect = role == WCLiquidGlassHomeCornerTableRoleFindFriend;
    CGRect overlayFrame = cell.contentView.bounds;
    UIColor *targetBackgroundColor = UIColor.clearColor;
    BOOL needsCornerUpdate = cell.layer.cornerRadius != targetCornerRadius ||
        cell.layer.cornerCurve != kCACornerCurveContinuous ||
        cell.layer.maskedCorners != cellCorners ||
        cell.layer.masksToBounds != (cellCorners != 0);
    BOOL needsLiquidUpdate = isLiquidBackground &&
        (cell.backgroundView != nil ||
         cell.backgroundColor != targetBackgroundColor ||
         state.appliedConfigurationEpoch != WCLiquidGlassHomeCornersConfigurationEpoch ||
         cell.contentView.backgroundColor != UIColor.clearColor ||
         WCLiquidGlassHomeCornerHasOpaqueNativeContentBackground(cell, state) ||
         (usesCellGlass
            ? !state.glassOverlay ||
                state.glassOverlay.superview != cell.contentView ||
                cell.contentView.subviews.firstObject != state.glassOverlay ||
                !CGRectEqualToRect(state.glassOverlay.frame, CGRectIntegral(overlayFrame)) ||
                state.glassOverlay.layer.cornerRadius != visualCornerRadius ||
                state.glassOverlay.layer.maskedCorners != corners ||
                !state.glassOverlay.clipsToBounds ||
                state.appliedGlassState != glassState ||
                state.appliedGlassTintState != tintState
            : state.glassOverlay.superview != nil));
    BOOL needsSelectionUpdate = suppressesSelectionEffect
        ? cell.selectionStyle != UITableViewCellSelectionStyleNone || cell.selectedBackgroundView != nil
        : cell.selectionStyle != state.originalSelectionStyle ||
            cell.selectedBackgroundView != state.originalSelectedBackgroundView;
    CGRect baseContentFrame = cell.contentView.frame;
    if (state.hasAppliedContentFrame &&
        CGRectEqualToRect(baseContentFrame, state.appliedContentFrame)) {
        baseContentFrame = state.baseContentFrame;
    }
    CGRect targetContentFrame = baseContentFrame;
    BOOL insetsStandardTabContent =
        role == WCLiquidGlassHomeCornerTableRoleFindFriend ||
        role == WCLiquidGlassHomeCornerTableRoleMore;
    NSRange visualSectionRange = WCLiquidGlassHomeCornerVisualSectionRange(tableView,
                                                                          indexPath.section,
                                                                          role);
    BOOL insetsFirstContactsSection =
        role == WCLiquidGlassHomeCornerTableRoleOtherTab &&
        visualSectionRange.location == 0;
    if (role == WCLiquidGlassHomeCornerTableRoleOtherTab &&
        !insetsFirstContactsSection) {
        targetContentFrame.origin.x += 16.0;
        targetContentFrame.size.width = MAX(0.0, targetContentFrame.size.width - 24.0);
    }
    BOOL needsContentFrameUpdate = !CGRectEqualToRect(cell.contentView.frame,
                                                      targetContentFrame);
    state.baseContentFrame = baseContentFrame;
    state.appliedContentFrame = targetContentFrame;
    state.hasAppliedContentFrame = role == WCLiquidGlassHomeCornerTableRoleOtherTab;
    UIView *innerContentView = cell.contentView.subviews.firstObject;
    CGRect baseInnerContentFrame = innerContentView.frame;
    if (state.hasAppliedInnerContentFrame &&
        CGRectEqualToRect(baseInnerContentFrame, state.appliedInnerContentFrame)) {
        baseInnerContentFrame = state.baseInnerContentFrame;
    }
    CGRect targetInnerContentFrame = baseInnerContentFrame;
    if (insetsFirstContactsSection) {
        targetInnerContentFrame.origin.x += 16.0;
        targetInnerContentFrame.size.width =
            MAX(0.0, targetInnerContentFrame.size.width - 24.0);
    }
    BOOL needsInnerContentFrameUpdate = innerContentView &&
        !CGRectEqualToRect(innerContentView.frame, targetInnerContentFrame);
    state.baseInnerContentFrame = baseInnerContentFrame;
    state.appliedInnerContentFrame = targetInnerContentFrame;
    state.hasAppliedInnerContentFrame = insetsFirstContactsSection;
    BOOL needsStandardTabContentInset = insetsStandardTabContent;
    BOOL needsRestore = !isLiquidBackground &&
        (state.glassOverlay || state.appliedConfigurationEpoch != 0);
    if (!needsFrameUpdate && !needsCornerUpdate && !needsLiquidUpdate && !needsSelectionUpdate &&
        !needsContentFrameUpdate && !needsInnerContentFrameUpdate && !needsStandardTabContentInset &&
        !needsRestore) {
        return;
    }
    if (suppressesSelectionEffect) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
    }
    if (needsFrameUpdate) {
        cell.frame = targetFrame;
    }
    if (needsContentFrameUpdate) {
        cell.contentView.frame = targetContentFrame;
    }
    if (needsInnerContentFrameUpdate) {
        innerContentView.frame = targetInnerContentFrame;
    }
    if (cell.layer.cornerRadius != targetCornerRadius) {
        cell.layer.cornerRadius = targetCornerRadius;
    }
    if (cell.layer.cornerCurve != kCACornerCurveContinuous) {
        cell.layer.cornerCurve = kCACornerCurveContinuous;
    }
    if (cell.layer.maskedCorners != cellCorners) {
        cell.layer.maskedCorners = cellCorners;
    }
    if (cell.layer.masksToBounds != (cellCorners != 0)) {
        cell.layer.masksToBounds = cellCorners != 0;
    }
    if (suppressesSelectionEffect) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.selectedBackgroundView = nil;
    } else {
        cell.selectionStyle = state.originalSelectionStyle;
        cell.selectedBackgroundView = state.originalSelectedBackgroundView;
    }
    if (isLiquidBackground) {
        if (cell.backgroundView) {
            cell.backgroundView = nil;
        }
        if (cell.backgroundColor != targetBackgroundColor ||
            state.appliedConfigurationEpoch != WCLiquidGlassHomeCornersConfigurationEpoch) {
            cell.backgroundColor = targetBackgroundColor;
            state.appliedBackgroundColor = targetBackgroundColor;
            state.appliedConfigurationEpoch = WCLiquidGlassHomeCornersConfigurationEpoch;
        }
        if (cell.contentView.backgroundColor != UIColor.clearColor) {
            cell.contentView.backgroundColor = UIColor.clearColor;
        }
        WCLiquidGlassHomeCornerClearNativeContentBackgrounds(cell, state);
        WCLiquidGlassHomeCornerHideNativeSeparators(cell);
        if (usesCellGlass) {
            WCLiquidGlassHomeCornerUpdateGlassOverlay(cell,
                                                      state,
                                                      overlayFrame,
                                                      visualCornerRadius,
                                                      corners);
        } else {
            [state.glassOverlay removeFromSuperview];
            state.glassOverlay = nil;
            state.appliedGlassState = NSIntegerMin;
            state.appliedGlassTintState = NSIntegerMin;
        }
    } else {
        cell.backgroundView = state.originalBackgroundView;
        cell.backgroundColor = state.originalBackgroundColor;
        cell.contentView.backgroundColor = state.originalContentBackgroundColor;
        state.appliedBackgroundColor = nil;
        state.appliedConfigurationEpoch = 0;
        [state.glassOverlay removeFromSuperview];
        state.glassOverlay = nil;
        state.appliedGlassState = NSIntegerMin;
        state.appliedGlassTintState = NSIntegerMin;
    }
    if (insetsStandardTabContent) {
        WCLiquidGlassHomeCornerApplyStandardTabContentInset(cell, state);
    }
    if (suppressesSelectionEffect) {
        [CATransaction commit];
    }
}

static UIView *WCLiquidGlassHomeCornerFirstCellSubview(UITableView *tableView) {
    for (UIView *subview in tableView.subviews) {
        if ([subview isKindOfClass:UITableViewCell.class]) {
            return subview;
        }
    }
    return nil;
}

static CGRect WCLiquidGlassHomeCornerRawSectionFrame(UITableView *tableView,
                                                      NSInteger section) {
    NSInteger rowCount = [tableView numberOfRowsInSection:section];
    if (rowCount <= 0) {
        return CGRectNull;
    }
    CGRect firstRow = [tableView rectForRowAtIndexPath:[NSIndexPath indexPathForRow:0
                                                                         inSection:section]];
    CGRect lastRow = [tableView rectForRowAtIndexPath:[NSIndexPath indexPathForRow:rowCount - 1
                                                                        inSection:section]];
    return CGRectUnion(firstRow, lastRow);
}

static BOOL WCLiquidGlassHomeCornerSectionsAreContiguous(UITableView *tableView,
                                                          NSInteger firstSection,
                                                          NSInteger secondSection) {
    CGRect firstFrame = WCLiquidGlassHomeCornerRawSectionFrame(tableView, firstSection);
    CGRect secondFrame = WCLiquidGlassHomeCornerRawSectionFrame(tableView, secondSection);
    if (CGRectIsNull(firstFrame) || CGRectIsNull(secondFrame)) {
        return NO;
    }
    CGFloat gap = CGRectGetMinY(secondFrame) - CGRectGetMaxY(firstFrame);
    return gap >= -1.0 && gap <= 1.0;
}

static NSRange WCLiquidGlassHomeCornerVisualSectionRange(
    UITableView *tableView,
    NSInteger section,
    WCLiquidGlassHomeCornerTableRole role) {
    if (role != WCLiquidGlassHomeCornerTableRoleOtherTab) {
        return NSMakeRange(section, 1);
    }
    NSInteger sectionCount = tableView.numberOfSections;
    NSInteger firstSection = section;
    NSInteger lastSection = section;
    while (firstSection > 0 &&
           WCLiquidGlassHomeCornerSectionsAreContiguous(tableView,
                                                        firstSection - 1,
                                                        firstSection)) {
        firstSection -= 1;
    }
    while (lastSection + 1 < sectionCount &&
           WCLiquidGlassHomeCornerSectionsAreContiguous(tableView,
                                                        lastSection,
                                                        lastSection + 1)) {
        lastSection += 1;
    }
    return NSMakeRange(firstSection, lastSection - firstSection + 1);
}

static CGRect WCLiquidGlassHomeCornerSectionFrame(UITableView *tableView,
                                                   NSInteger section,
                                                   WCLiquidGlassHomeCornerTableRole role) {
    NSRange sectionRange = WCLiquidGlassHomeCornerVisualSectionRange(tableView,
                                                                    section,
                                                                    role);
    CGRect firstSectionFrame = WCLiquidGlassHomeCornerRawSectionFrame(tableView,
                                                                      sectionRange.location);
    CGRect lastSectionFrame = WCLiquidGlassHomeCornerRawSectionFrame(
        tableView,
        NSMaxRange(sectionRange) - 1);
    if (CGRectIsNull(firstSectionFrame) || CGRectIsNull(lastSectionFrame)) {
        return CGRectNull;
    }
    CGRect sectionFrame = CGRectUnion(firstSectionFrame, lastSectionFrame);
    if (role == WCLiquidGlassHomeCornerTableRoleOtherTab) {
        sectionFrame.origin.x = 16.0;
        sectionFrame.size.width = MAX(0.0, CGRectGetWidth(tableView.bounds) - 40.0);
        sectionFrame = CGRectInset(sectionFrame, 0.0, -8.0);
    } else {
        CGFloat inset = WCLiquidGlassPreferences.homeCornerInset;
        sectionFrame.origin.x = inset;
        sectionFrame.size.width = MAX(0.0, CGRectGetWidth(tableView.bounds) - inset * 2.0);
    }
    return CGRectIntegral(sectionFrame);
}

static WCLiquidGlassHomeCornerSectionState *WCLiquidGlassHomeCornerStateForSection(
    WCLiquidGlassHomeCornerTableState *tableState,
    NSInteger section) {
    NSNumber *key = @(section);
    WCLiquidGlassHomeCornerSectionState *sectionState = tableState.sectionStates[key];
    if (!sectionState) {
        sectionState = [[WCLiquidGlassHomeCornerSectionState alloc] init];
        sectionState.glassView = [[UIVisualEffectView alloc] initWithEffect:nil];
        sectionState.glassView.userInteractionEnabled = NO;
        sectionState.glassView.layer.cornerCurve = kCACornerCurveContinuous;
        sectionState.glassView.clipsToBounds = YES;
        sectionState.appliedGlassState = NSIntegerMin;
        tableState.sectionStates[key] = sectionState;
    }
    return sectionState;
}

static void WCLiquidGlassHomeCornerUpdateSectionGlassViews(
    UITableView *tableView,
    WCLiquidGlassHomeCornerTableRole role) {
    WCLiquidGlassHomeCornerTableState *tableState = WCLiquidGlassHomeCornerStateForTable(tableView);
    NSMutableIndexSet *activeSections = [NSMutableIndexSet indexSet];
    if (WCLiquidGlassPreferences.homeLiquidBackgroundEnabled) {
        for (UITableViewCell *cell in tableView.visibleCells) {
            NSIndexPath *indexPath = [tableView indexPathForCell:cell];
            if (indexPath && !WCLiquidGlassHomeCornerUsesIndependentCard(role, indexPath)) {
                NSRange sectionRange = WCLiquidGlassHomeCornerVisualSectionRange(tableView,
                                                                                indexPath.section,
                                                                                role);
                [activeSections addIndex:sectionRange.location];
            }
        }
    }

    for (NSNumber *key in tableState.sectionStates.allKeys.copy) {
        if (![activeSections containsIndex:key.unsignedIntegerValue]) {
            WCLiquidGlassHomeCornerSectionState *sectionState = tableState.sectionStates[key];
            [sectionState.glassView removeFromSuperview];
            [tableState.sectionStates removeObjectForKey:key];
        }
    }
    if (activeSections.count == 0) {
        return;
    }

    UIView *firstCellSubview = WCLiquidGlassHomeCornerFirstCellSubview(tableView);
    if (!firstCellSubview) {
        return;
    }
    [activeSections enumerateIndexesUsingBlock:^(NSUInteger section, __unused BOOL *stop) {
        CGRect sectionFrame = WCLiquidGlassHomeCornerSectionFrame(tableView, section, role);
        if (CGRectIsNull(sectionFrame) || CGRectIsEmpty(sectionFrame)) {
            return;
        }
        WCLiquidGlassHomeCornerSectionState *sectionState =
            WCLiquidGlassHomeCornerStateForSection(tableState, section);
        UIVisualEffectView *glassView = sectionState.glassView;
        if (glassView.superview != tableView) {
            [glassView removeFromSuperview];
        }
        [tableView insertSubview:glassView belowSubview:firstCellSubview];
        if (!CGRectEqualToRect(glassView.frame, sectionFrame)) {
            glassView.frame = sectionFrame;
        }
        NSIndexPath *firstIndexPath = [NSIndexPath indexPathForRow:0 inSection:section];
        CGFloat radius = WCLiquidGlassHomeCornerRadiusForCell(role, firstIndexPath);
        if (glassView.layer.cornerRadius != radius) {
            glassView.layer.cornerRadius = radius;
        }
        glassView.layer.maskedCorners =
            kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner |
            kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
        NSInteger glassState =
            WCLiquidGlassPreferences.glassAppearance * 10 +
            tableView.traitCollection.userInterfaceStyle;
        if (sectionState.appliedGlassState != glassState) {
            glassView.effect = WCLiquidGlassCurrentGlassEffect();
            glassView.contentView.backgroundColor = UIColor.clearColor;
            sectionState.appliedGlassState = glassState;
        }
        glassView.hidden = NO;
    }];
}

static void WCLiquidGlassHomeCornersUpdateTable(UITableView *tableView) {
    WCLiquidGlassHomeCornerTableRole role = WCLiquidGlassHomeCornerRoleForTable(tableView);
    BOOL wasStyled = [objc_getAssociatedObject(tableView, WCLiquidGlassHomeCornerTableStyledKey) boolValue];
    if (role == WCLiquidGlassHomeCornerTableRoleNone && !wasStyled) {
        return;
    }
    if (role != WCLiquidGlassHomeCornerTableRoleNone) {
        WCLiquidGlassHomeCornerInstallNativeHeightHooks();
        if (role == WCLiquidGlassHomeCornerTableRoleFindFriend ||
            role == WCLiquidGlassHomeCornerTableRoleMore) {
            WCLiquidGlassInstallHomeCornerStandardTabCellLayoutHook();
        }
        WCLiquidGlassHomeCornerApplyTableStyle(tableView);
        objc_setAssociatedObject(tableView,
                                 WCLiquidGlassHomeCornerTableStyledKey,
                                 @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (role == WCLiquidGlassHomeCornerTableRoleHome ||
            role == WCLiquidGlassHomeCornerTableRoleOtherTab) {
            WCLiquidGlassHomeCornerRequestNativeHeightUpdate(tableView);
        }
    }
    for (UITableViewCell *cell in tableView.visibleCells) {
        if (role == WCLiquidGlassHomeCornerTableRoleNone) {
            WCLiquidGlassHomeCornerRestoreCell(cell);
        } else {
            WCLiquidGlassHomeCornerApplyCell(tableView, cell, role);
        }
    }
    if (role != WCLiquidGlassHomeCornerTableRoleNone) {
        WCLiquidGlassHomeCornerUpdateSectionGlassViews(tableView, role);
    }
    if (role == WCLiquidGlassHomeCornerTableRoleNone) {
        WCLiquidGlassHomeCornerRestoreTableStyle(tableView);
        objc_setAssociatedObject(tableView,
                                 WCLiquidGlassHomeCornerTableStyledKey,
                                 @NO,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static UITableView *WCLiquidGlassHomeCornersTableForCell(UITableViewCell *cell) {
    for (UIView *view = cell.superview; view; view = view.superview) {
        if ([view isKindOfClass:UITableView.class]) {
            return (UITableView *)view;
        }
    }
    return nil;
}

static void WCLiquidGlassHomeCornerCellLayoutSubviews(UITableViewCell *self, SEL selector) {
    if (WCLiquidGlassOriginalHomeCornerCellLayoutSubviews) {
        WCLiquidGlassOriginalHomeCornerCellLayoutSubviews(self, selector);
    }
    if (WCLiquidGlassHomeCornerCellLayoutApplying) {
        return;
    }
    UITableView *tableView = WCLiquidGlassHomeCornersTableForCell(self);
    WCLiquidGlassHomeCornerTableRole role = WCLiquidGlassHomeCornerRoleForTable(tableView);
    if (role == WCLiquidGlassHomeCornerTableRoleNone) {
        return;
    }
    WCLiquidGlassHomeCornerCellLayoutApplying = YES;
    WCLiquidGlassHomeCornerApplyCell(tableView, self, role);
    WCLiquidGlassHomeCornerCellLayoutApplying = NO;
}

static void WCLiquidGlassHomeCornerStandardTabCellLayoutSubviews(UITableViewCell *self,
                                                                  SEL selector) {
    if (WCLiquidGlassOriginalStandardTabCellLayoutSubviews) {
        WCLiquidGlassOriginalStandardTabCellLayoutSubviews(self, selector);
    }
    if (WCLiquidGlassHomeCornerCellLayoutApplying) {
        return;
    }
    UITableView *tableView = WCLiquidGlassHomeCornersTableForCell(self);
    WCLiquidGlassHomeCornerTableRole role = WCLiquidGlassHomeCornerRoleForTable(tableView);
    if (role != WCLiquidGlassHomeCornerTableRoleFindFriend &&
        role != WCLiquidGlassHomeCornerTableRoleMore) {
        return;
    }
    WCLiquidGlassHomeCornerCellLayoutApplying = YES;
    WCLiquidGlassHomeCornerApplyCell(tableView, self, role);
    WCLiquidGlassHomeCornerCellLayoutApplying = NO;
}

static void WCLiquidGlassHomeCornerPreserveContactsAvatarCorners(UIView *view) {
    NSString *className = NSStringFromClass(view.class);
    if ([className isEqualToString:@"MMHeadImageView"]) {
        objc_setAssociatedObject(view,
                                 WCLiquidGlassHomeCornerContactsAvatarKey,
                                 @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        CGFloat radius = MIN(CGRectGetWidth(view.bounds), CGRectGetHeight(view.bounds)) * 0.5;
        if (radius > 0.0 &&
            (view.layer.cornerRadius != radius ||
             !view.layer.masksToBounds ||
             !view.clipsToBounds)) {
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            view.layer.cornerRadius = radius;
            view.layer.masksToBounds = YES;
            view.clipsToBounds = YES;
            [CATransaction commit];
        }
        return;
    }
    for (UIView *subview in view.subviews) {
        WCLiquidGlassHomeCornerPreserveContactsAvatarCorners(subview);
    }
}

static void WCLiquidGlassHomeCornerContactsAvatarLayoutSubviews(UIView *self, SEL selector) {
    if (WCLiquidGlassOriginalContactsAvatarLayoutSubviews) {
        WCLiquidGlassOriginalContactsAvatarLayoutSubviews(self, selector);
    }
    if (![objc_getAssociatedObject(self, WCLiquidGlassHomeCornerContactsAvatarKey) boolValue] ||
        !WCLiquidGlassPreferences.homeCornersEnabled) {
        return;
    }
    WCLiquidGlassHomeCornerPreserveContactsAvatarCorners(self);
}

static void WCLiquidGlassHomeCornerContactsCellLayoutSubviews(UITableViewCell *self,
                                                               SEL selector) {
    if (WCLiquidGlassOriginalContactsCellLayoutSubviews) {
        WCLiquidGlassOriginalContactsCellLayoutSubviews(self, selector);
    }
    if (WCLiquidGlassHomeCornerCellLayoutApplying) {
        return;
    }
    UITableView *tableView = WCLiquidGlassHomeCornersTableForCell(self);
    WCLiquidGlassHomeCornerTableRole role = WCLiquidGlassHomeCornerRoleForTable(tableView);
    NSIndexPath *indexPath = [tableView indexPathForCell:self];
    if (role != WCLiquidGlassHomeCornerTableRoleOtherTab || !indexPath) {
        return;
    }
    NSRange visualSectionRange = WCLiquidGlassHomeCornerVisualSectionRange(tableView,
                                                                          indexPath.section,
                                                                          role);
    if (visualSectionRange.location == 0) {
        WCLiquidGlassHomeCornerCellLayoutApplying = YES;
        WCLiquidGlassHomeCornerApplyCell(tableView, self, role);
        WCLiquidGlassHomeCornerCellLayoutApplying = NO;
    }
    WCLiquidGlassHomeCornerPreserveContactsAvatarCorners(self.contentView);
}

static void WCLiquidGlassHomeCornerCellSetBackgroundColor(UITableViewCell *self,
                                                           SEL selector,
                                                           UIColor *color) {
    UIColor *targetColor = WCLiquidGlassPreferences.homeCornersEnabled &&
        WCLiquidGlassPreferences.homeLiquidBackgroundEnabled
        ? UIColor.clearColor
        : color;
    WCLiquidGlassOriginalHomeCornerCellSetBackgroundColor(self, selector, targetColor);
}

static void WCLiquidGlassHomeCornerTableLayoutSubviews(UITableView *self, SEL selector) {
    if (WCLiquidGlassOriginalHomeCornerTableLayoutSubviews) {
        WCLiquidGlassOriginalHomeCornerTableLayoutSubviews(self, selector);
    }
    if (WCLiquidGlassHomeCornerTableLayoutApplying) {
        return;
    }
    WCLiquidGlassHomeCornerTableRole role = WCLiquidGlassHomeCornerRoleForTable(self);
    if (role == WCLiquidGlassHomeCornerTableRoleNone) {
        return;
    }
    WCLiquidGlassHomeCornerTableLayoutApplying = YES;
    WCLiquidGlassHomeCornersUpdateTable(self);
    WCLiquidGlassHomeCornerTableLayoutApplying = NO;
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

static void WCLiquidGlassInstallHomeCornerCellLayoutHook(void) {
    if (WCLiquidGlassOriginalHomeCornerCellLayoutSubviews) {
        return;
    }
    Class cellClass = NSClassFromString(@"NewMainFrameCell");
    Method layoutMethod = cellClass ? class_getInstanceMethod(cellClass, @selector(layoutSubviews)) : NULL;
    if (!layoutMethod) {
        if (!WCLiquidGlassHomeCornerCellHookRetryScheduled &&
            WCLiquidGlassHomeCornerCellHookInstallAttempts < 10) {
            WCLiquidGlassHomeCornerCellHookRetryScheduled = YES;
            WCLiquidGlassHomeCornerCellHookInstallAttempts += 1;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                WCLiquidGlassHomeCornerCellHookRetryScheduled = NO;
                WCLiquidGlassInstallHomeCornerCellLayoutHook();
            });
        }
        return;
    }
    MSHookMessageEx(cellClass,
                    @selector(layoutSubviews),
                    (IMP)&WCLiquidGlassHomeCornerCellLayoutSubviews,
                    (IMP *)&WCLiquidGlassOriginalHomeCornerCellLayoutSubviews);
    if (!WCLiquidGlassOriginalHomeCornerCellSetBackgroundColor) {
        MSHookMessageEx(cellClass,
                        @selector(setBackgroundColor:),
                        (IMP)&WCLiquidGlassHomeCornerCellSetBackgroundColor,
                        (IMP *)&WCLiquidGlassOriginalHomeCornerCellSetBackgroundColor);
    }
}

static void WCLiquidGlassInstallHomeCornerStandardTabCellLayoutHook(void) {
    if (WCLiquidGlassOriginalStandardTabCellLayoutSubviews) {
        return;
    }
    Class cellClass = NSClassFromString(@"MMTableViewCell");
    Method layoutMethod = cellClass
        ? class_getInstanceMethod(cellClass, @selector(layoutSubviews))
        : NULL;
    if (!layoutMethod) {
        return;
    }
    MSHookMessageEx(cellClass,
                    @selector(layoutSubviews),
                    (IMP)&WCLiquidGlassHomeCornerStandardTabCellLayoutSubviews,
                    (IMP *)&WCLiquidGlassOriginalStandardTabCellLayoutSubviews);
}

static void WCLiquidGlassInstallHomeCornerContactsCellLayoutHook(void) {
    if (WCLiquidGlassOriginalContactsCellLayoutSubviews) {
        return;
    }
    Class cellClass = NSClassFromString(@"NewContactsItemCell");
    Method layoutMethod = cellClass ? class_getInstanceMethod(cellClass, @selector(layoutSubviews)) : NULL;
    if (!layoutMethod) {
        if (!WCLiquidGlassHomeCornerContactsCellHookRetryScheduled &&
            WCLiquidGlassHomeCornerContactsCellHookInstallAttempts < 10) {
            WCLiquidGlassHomeCornerContactsCellHookRetryScheduled = YES;
            WCLiquidGlassHomeCornerContactsCellHookInstallAttempts += 1;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                WCLiquidGlassHomeCornerContactsCellHookRetryScheduled = NO;
                WCLiquidGlassInstallHomeCornerContactsCellLayoutHook();
            });
        }
        return;
    }
    MSHookMessageEx(cellClass,
                    @selector(layoutSubviews),
                    (IMP)&WCLiquidGlassHomeCornerContactsCellLayoutSubviews,
                    (IMP *)&WCLiquidGlassOriginalContactsCellLayoutSubviews);
}

static void WCLiquidGlassInstallHomeCornerContactsAvatarLayoutHook(void) {
    if (WCLiquidGlassOriginalContactsAvatarLayoutSubviews) {
        return;
    }
    Class avatarClass = NSClassFromString(@"MMHeadImageView");
    Method layoutMethod = avatarClass
        ? class_getInstanceMethod(avatarClass, @selector(layoutSubviews))
        : NULL;
    if (!layoutMethod) {
        if (!WCLiquidGlassHomeCornerContactsAvatarHookRetryScheduled &&
            WCLiquidGlassHomeCornerContactsAvatarHookInstallAttempts < 10) {
            WCLiquidGlassHomeCornerContactsAvatarHookRetryScheduled = YES;
            WCLiquidGlassHomeCornerContactsAvatarHookInstallAttempts += 1;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                WCLiquidGlassHomeCornerContactsAvatarHookRetryScheduled = NO;
                WCLiquidGlassInstallHomeCornerContactsAvatarLayoutHook();
            });
        }
        return;
    }
    MSHookMessageEx(avatarClass,
                    @selector(layoutSubviews),
                    (IMP)&WCLiquidGlassHomeCornerContactsAvatarLayoutSubviews,
                    (IMP *)&WCLiquidGlassOriginalContactsAvatarLayoutSubviews);
}

static void WCLiquidGlassInstallHomeCornerTableLayoutHook(void) {
    if (WCLiquidGlassOriginalHomeCornerTableLayoutSubviews) {
        return;
    }
    MSHookMessageEx(UITableView.class,
                    @selector(layoutSubviews),
                    (IMP)&WCLiquidGlassHomeCornerTableLayoutSubviews,
                    (IMP *)&WCLiquidGlassOriginalHomeCornerTableLayoutSubviews);
}

void WCLiquidGlassInstallHomeCornersHooks(void) {
    if (WCLiquidGlassHomeCornersHooksInstalled) {
        WCLiquidGlassInstallHomeCornerCellLayoutHook();
        WCLiquidGlassInstallHomeCornerContactsCellLayoutHook();
        WCLiquidGlassInstallHomeCornerContactsAvatarLayoutHook();
        WCLiquidGlassInstallHomeCornerTableLayoutHook();
        return;
    }
    WCLiquidGlassHomeCornersHooksInstalled = YES;
    WCLiquidGlassHomeCornerInstallNativeHeightHooks();
    WCLiquidGlassInstallHomeCornerCellLayoutHook();
    WCLiquidGlassInstallHomeCornerContactsCellLayoutHook();
    WCLiquidGlassInstallHomeCornerContactsAvatarLayoutHook();
    WCLiquidGlassInstallHomeCornerTableLayoutHook();
    [NSNotificationCenter.defaultCenter addObserverForName:WCLiquidGlassPreferencesDidChangeNotification
                                                      object:nil
                                                       queue:NSOperationQueue.mainQueue
                                                  usingBlock:^(__unused NSNotification *notification) {
        WCLiquidGlassHomeCornersConfigurationEpoch += 1;
        WCLiquidGlassHomeCornersRefreshVisibleTables();
    }];
}

static NSString *WCLiquidGlassHomeCornersDiagnosticRect(CGRect rect) {
    return [NSString stringWithFormat:@"{x=%.1f y=%.1f w=%.1f h=%.1f}",
            rect.origin.x, rect.origin.y, rect.size.width, rect.size.height];
}

static NSString *WCLiquidGlassHomeCornersDiagnosticColor(UIColor *color,
                                                           UITraitCollection *traits) {
    if (!color) {
        return @"nil";
    }
    UIColor *resolved = [color resolvedColorWithTraitCollection:traits ?: UITraitCollection.currentTraitCollection];
    CGFloat red = 0.0;
    CGFloat green = 0.0;
    CGFloat blue = 0.0;
    CGFloat alpha = 0.0;
    if ([resolved getRed:&red green:&green blue:&blue alpha:&alpha]) {
        return [NSString stringWithFormat:@"rgba(%.3f, %.3f, %.3f, %.3f)", red, green, blue, alpha];
    }
    CGFloat white = 0.0;
    if ([resolved getWhite:&white alpha:&alpha]) {
        return [NSString stringWithFormat:@"white(%.3f, %.3f)", white, alpha];
    }
    return NSStringFromClass(resolved.class);
}

static void WCLiquidGlassHomeCornersAppendViewTree(NSMutableString *report,
                                                    UIView *view,
                                                    NSUInteger depth,
                                                    NSUInteger *viewCount) {
    if (!view || depth > 7 || *viewCount >= 420) {
        return;
    }
    *viewCount += 1;
    NSString *indent = [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0];
    [report appendFormat:@"%@%@ frame=%@ bounds=%@ alpha=%.2f hidden=%@ bg=%@ corner=%.1f masks=%@ clips=%@ subviews=%lu\n",
     indent,
     NSStringFromClass(view.class),
     WCLiquidGlassHomeCornersDiagnosticRect(view.frame),
     WCLiquidGlassHomeCornersDiagnosticRect(view.bounds),
     view.alpha,
     view.hidden ? @"YES" : @"NO",
     WCLiquidGlassHomeCornersDiagnosticColor(view.backgroundColor, view.traitCollection),
     view.layer.cornerRadius,
     view.layer.masksToBounds ? @"YES" : @"NO",
     view.clipsToBounds ? @"YES" : @"NO",
     (unsigned long)view.subviews.count];
    for (UIView *subview in view.subviews) {
        WCLiquidGlassHomeCornersAppendViewTree(report, subview, depth + 1, viewCount);
    }
}

static void WCLiquidGlassHomeCornersCollectTables(UIView *view,
                                                   NSMutableArray<UITableView *> *tables,
                                                   NSMutableSet<NSValue *> *seen,
                                                   NSUInteger depth) {
    if (!view || depth > 24) {
        return;
    }
    if ([view isKindOfClass:UITableView.class]) {
        NSValue *identity = [NSValue valueWithNonretainedObject:view];
        if (![seen containsObject:identity]) {
            [seen addObject:identity];
            [tables addObject:(UITableView *)view];
        }
    }
    for (UIView *subview in view.subviews) {
        WCLiquidGlassHomeCornersCollectTables(subview, tables, seen, depth + 1);
    }
}

static void WCLiquidGlassHomeCornersAppendControllerTree(NSMutableString *report,
                                                          UIViewController *controller,
                                                          NSUInteger depth,
                                                          NSMutableSet<NSValue *> *seen) {
    if (!controller || depth > 16) {
        return;
    }
    NSValue *identity = [NSValue valueWithNonretainedObject:controller];
    if ([seen containsObject:identity]) {
        return;
    }
    [seen addObject:identity];
    NSString *indent = [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0];
    [report appendFormat:@"%@%@ viewLoaded=%@ viewFrame=%@ children=%lu presented=%@\n",
     indent,
     NSStringFromClass(controller.class),
     controller.isViewLoaded ? @"YES" : @"NO",
     controller.isViewLoaded ? WCLiquidGlassHomeCornersDiagnosticRect(controller.view.frame) : @"n/a",
     (unsigned long)controller.childViewControllers.count,
     controller.presentedViewController ? NSStringFromClass(controller.presentedViewController.class) : @"nil"];
    if (controller.presentedViewController) {
        WCLiquidGlassHomeCornersAppendControllerTree(report, controller.presentedViewController, depth + 1, seen);
    }
    for (UIViewController *child in controller.childViewControllers) {
        WCLiquidGlassHomeCornersAppendControllerTree(report, child, depth + 1, seen);
    }
}

static void WCLiquidGlassHomeCornersAppendTableDiagnostics(NSMutableString *report,
                                                           UITableView *tableView,
                                                           NSUInteger index) {
    Class mainFrameTableClass = NSClassFromString(@"MainFrameTableView");
    BOOL mainFrameTable = mainFrameTableClass && [tableView isKindOfClass:mainFrameTableClass];
    [report appendFormat:@"\nTable %lu%@\nclass=%@ frame=%@ bounds=%@ contentSize={w=%.1f h=%.1f} contentOffset={x=%.1f y=%.1f} adjustedInset={t=%.1f l=%.1f b=%.1f r=%.1f} separatorStyle=%ld separatorColor=%@ visibleCells=%lu sections=%ld\n",
     (unsigned long)index,
     mainFrameTable ? @" [MainFrameTableView]" : @"",
     NSStringFromClass(tableView.class),
     WCLiquidGlassHomeCornersDiagnosticRect(tableView.frame),
     WCLiquidGlassHomeCornersDiagnosticRect(tableView.bounds),
     tableView.contentSize.width,
     tableView.contentSize.height,
     tableView.contentOffset.x,
     tableView.contentOffset.y,
     tableView.adjustedContentInset.top,
     tableView.adjustedContentInset.left,
     tableView.adjustedContentInset.bottom,
     tableView.adjustedContentInset.right,
     (long)tableView.separatorStyle,
     WCLiquidGlassHomeCornersDiagnosticColor(tableView.separatorColor, tableView.traitCollection),
     (unsigned long)tableView.visibleCells.count,
     (long)tableView.numberOfSections];
    NSUInteger directSubviewLimit = MIN((NSUInteger)32, tableView.subviews.count);
    for (NSUInteger subviewIndex = 0; subviewIndex < directSubviewLimit; subviewIndex += 1) {
        UIView *subview = tableView.subviews[subviewIndex];
        [report appendFormat:@"  TableSubview %lu class=%@ frame=%@ hidden=%@ alpha=%.2f\n",
         (unsigned long)subviewIndex,
         NSStringFromClass(subview.class),
         WCLiquidGlassHomeCornersDiagnosticRect(subview.frame),
         subview.hidden ? @"YES" : @"NO",
         subview.alpha];
    }
    NSUInteger cellLimit = MIN((NSUInteger)24, tableView.visibleCells.count);
    for (NSUInteger cellIndex = 0; cellIndex < cellLimit; cellIndex += 1) {
        UITableViewCell *cell = tableView.visibleCells[cellIndex];
        NSIndexPath *indexPath = [tableView indexPathForCell:cell];
        [report appendFormat:@"  Cell %lu indexPath=%@ class=%@ frame=%@ bg=%@ contentBg=%@ backgroundView=%@ corner=%.1f masks=%@\n",
         (unsigned long)cellIndex,
         indexPath ?: @"nil",
         NSStringFromClass(cell.class),
         WCLiquidGlassHomeCornersDiagnosticRect(cell.frame),
         WCLiquidGlassHomeCornersDiagnosticColor(cell.backgroundColor, cell.traitCollection),
         WCLiquidGlassHomeCornersDiagnosticColor(cell.contentView.backgroundColor, cell.traitCollection),
         cell.backgroundView ? NSStringFromClass(cell.backgroundView.class) : @"nil",
         cell.layer.cornerRadius,
         cell.layer.masksToBounds ? @"YES" : @"NO"];
        NSUInteger viewCount = 0;
        WCLiquidGlassHomeCornersAppendViewTree(report, cell, 2, &viewCount);
    }
}

static void WCLiquidGlassHomeCornersCaptureCurrentPageHierarchyDiagnosticsOnMainThread(void) {
    NSMutableString *report = [NSMutableString string];
    [report appendString:@"Privacy: this report intentionally excludes visible text, message content, contact names, and accessibility labels.\n\n"];
    [report appendFormat:@"Home Corners Preferences\nenabled=%@ liquidBackground=%@ inset=%.1f homeRadius=%.1f homeGap=%.1f otherTabsRadius=26.0 otherTabsGap=8.0 glassAppearance=%ld\n",
     WCLiquidGlassPreferences.homeCornersEnabled ? @"YES" : @"NO",
     WCLiquidGlassPreferences.homeLiquidBackgroundEnabled ? @"YES" : @"NO",
     WCLiquidGlassPreferences.homeCornerInset,
     WCLiquidGlassPreferences.homeCornerRadius,
     WCLiquidGlassPreferences.homeCardGap,
     (long)WCLiquidGlassPreferences.glassAppearance];

    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) {
            continue;
        }
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        if (windowScene.activationState == UISceneActivationStateUnattached) {
            continue;
        }
        for (UIWindow *window in windowScene.windows) {
            if (!window.hidden && window.alpha > 0.01) {
                [windows addObject:window];
            }
        }
    }
    [windows sortUsingComparator:^NSComparisonResult(UIWindow *first, UIWindow *second) {
        if (first.isKeyWindow == second.isKeyWindow) {
            return NSOrderedSame;
        }
        return first.isKeyWindow ? NSOrderedAscending : NSOrderedDescending;
    }];
    [report appendFormat:@"\nVisible Windows: %lu\n", (unsigned long)windows.count];
    NSMutableArray<UITableView *> *tables = [NSMutableArray array];
    NSMutableSet<NSValue *> *seenTables = [NSMutableSet set];
    for (NSUInteger index = 0; index < windows.count; index += 1) {
        UIWindow *window = windows[index];
        [report appendFormat:@"Window %lu key=%@ class=%@ level=%.1f frame=%@ root=%@\n",
         (unsigned long)index,
         window.isKeyWindow ? @"YES" : @"NO",
         NSStringFromClass(window.class),
         window.windowLevel,
         WCLiquidGlassHomeCornersDiagnosticRect(window.frame),
         window.rootViewController ? NSStringFromClass(window.rootViewController.class) : @"nil"];
        WCLiquidGlassHomeCornersCollectTables(window, tables, seenTables, 0);
    }

    [report appendString:@"\nController Hierarchy\n"];
    NSMutableSet<NSValue *> *seenControllers = [NSMutableSet set];
    for (UIWindow *window in windows) {
        WCLiquidGlassHomeCornersAppendControllerTree(report, window.rootViewController, 0, seenControllers);
    }
    [report appendFormat:@"\nDiscovered Tables: %lu\n", (unsigned long)tables.count];
    for (NSUInteger index = 0; index < tables.count; index += 1) {
        WCLiquidGlassHomeCornersAppendTableDiagnostics(report, tables[index], index);
    }
    [report appendString:@"\nKey Window View Hierarchy\n"];
    if (windows.firstObject) {
        NSUInteger viewCount = 0;
        WCLiquidGlassHomeCornersAppendViewTree(report, windows.firstObject, 0, &viewCount);
    } else {
        [report appendString:@"No visible window found.\n"];
    }

    NSURL *URL = [WCLiquidGlassCrashLogger.sharedLogger writeDiagnosticReportWithTitle:@"Current Page Hierarchy"
                                                                                content:report];
    if (URL) {
        UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [feedback prepare];
        [feedback impactOccurred];
    }
}

void WCLiquidGlassCaptureCurrentPageHierarchyDiagnostics(void) {
    if (NSThread.isMainThread) {
        WCLiquidGlassHomeCornersCaptureCurrentPageHierarchyDiagnosticsOnMainThread();
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        WCLiquidGlassHomeCornersCaptureCurrentPageHierarchyDiagnosticsOnMainThread();
    });
}

typedef NS_ENUM(NSInteger, WCLiquidGlassHomeCornersControlTag) {
    WCLiquidGlassHomeCornersControlTagInset = 1,
    WCLiquidGlassHomeCornersControlTagHomeRadius
};

static NSString *WCLiquidGlassHomeCornersDisplayValue(CGFloat value) {
    return [NSString stringWithFormat:@"%.0f pt", value];
}

@implementation WCLiquidGlassHomeCornersController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"首页圆角与液态";
    WCLiquidGlassConfigureSettingsTableBackground(self);
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 64.0;
    self.tableView.separatorColor = [UIColor.separatorColor colorWithAlphaComponent:0.30];
    [WCLiquidGlassPreferences registerDefaults];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(wc_preferencesChanged:)
                                               name:WCLiquidGlassPreferencesDidChangeNotification
                                             object:nil];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 6;
}

- (void)tableView:(UITableView *)tableView
  willDisplayCell:(UITableViewCell *)cell
forRowAtIndexPath:(NSIndexPath *)indexPath {
    WCLiquidGlassStyleSettingsCardCell(cell, indexPath, tableView);
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @"主页会话样式";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"主页可切换独立卡片与微信原生连续分区；独立卡片可调缩进、圆角和间距。发现、通讯录和我保持连续分区，使用固定圆角和液态材质。";
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    return WCLiquidGlassSettingsSectionHeader([self tableView:tableView titleForHeaderInSection:section]);
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return WCLiquidGlassSettingsSectionHeaderHeight();
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    return WCLiquidGlassSettingsFooter([self tableView:tableView titleForFooterInSection:section]);
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    NSString *text = [self tableView:tableView titleForFooterInSection:section];
    return WCLiquidGlassSettingsFooterHeight(text, 68.0);
}

- (UITableViewCell *)wc_cellWithTitle:(NSString *)title
                                detail:(nullable NSString *)detail
                               enabled:(BOOL)enabled
                            identifier:(NSString *)identifier {
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    }
    WCLiquidGlassConfigureSettingsCell(cell, title, detail, nil, enabled ? UIColor.labelColor : UIColor.tertiaryLabelColor);
    cell.contentView.alpha = enabled ? 1.0 : 0.45;
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
    BOOL separate = WCLiquidGlassPreferences.homeSeparateCardsEnabled;
    if (indexPath.section == 0) {
        switch (indexPath.row) {
            case 0:
                return [self wc_switchCellWithTitle:@"启用首页圆角与液态"
                                               detail:@"主页及微信分区的圆角和液态材质"
                                                  on:active
                                              enabled:YES
                                              action:@selector(wc_homeCornersChanged:)];
            case 1:
                return [self wc_sliderCellWithTitle:@"主页左右缩进"
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
                return [self wc_switchCellWithTitle:@"主页使用独立卡片"
                                               detail:@"关闭后合并为微信原生连续分区"
                                                  on:separate
                                              enabled:active
                                              action:@selector(wc_separateCardsChanged:)];
            case 4: {
                UITableViewCell *cell = [self wc_cellWithTitle:@"独立卡片间距"
                                                         detail:WCLiquidGlassHomeCornersDisplayValue(WCLiquidGlassPreferences.homeCardGap)
                                                        enabled:active && separate
                                                     identifier:@"WCLiquidGlassHomeCornersValueCell"];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                return cell;
            }
            case 5:
                return [self wc_switchCellWithTitle:@"启用液态背景"
                                               detail:@"卡片与分区使用“液态效果”材质"
                                                  on:WCLiquidGlassPreferences.homeLiquidBackgroundEnabled
                                              enabled:active
                                              action:@selector(wc_liquidBackgroundChanged:)];
            default:
                break;
        }
    }
    return [self wc_cellWithTitle:@"" detail:nil enabled:NO identifier:@"WCLiquidGlassHomeCornersUnusedCell"];
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
        [self wc_presentValueInputWithTitle:@"独立卡片间距" value:WCLiquidGlassPreferences.homeCardGap minimum:0.0 maximum:24.0 setter:^(CGFloat value) {
            [WCLiquidGlassPreferences setHomeCardGap:value];
        }];
    }
}

- (void)wc_homeCornersChanged:(UISwitch *)sender {
    [WCLiquidGlassPreferences setHomeCornersEnabled:sender.isOn];
}

- (void)wc_separateCardsChanged:(UISwitch *)sender {
    [WCLiquidGlassPreferences setHomeSeparateCardsEnabled:sender.isOn];
}

- (void)wc_liquidBackgroundChanged:(UISwitch *)sender {
    [WCLiquidGlassPreferences setHomeLiquidBackgroundEnabled:sender.isOn];
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
