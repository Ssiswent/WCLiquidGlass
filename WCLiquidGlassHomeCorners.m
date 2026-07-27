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
static const void *WCLiquidGlassHomeCornerTableStateKey = &WCLiquidGlassHomeCornerTableStateKey;
static const void *WCLiquidGlassHomeCornerFinalApplyPendingKey = &WCLiquidGlassHomeCornerFinalApplyPendingKey;
static void (*WCLiquidGlassOriginalHomeCornerCellLayoutSubviews)(UITableViewCell *, SEL) = NULL;
static void (*WCLiquidGlassOriginalHomeCornerCellSetBackgroundColor)(UIView *, SEL, UIColor *) = NULL;
static void (*WCLiquidGlassUIViewSetBackgroundColor)(UIView *, SEL, UIColor *) = NULL;
static BOOL WCLiquidGlassHomeCornersHooksInstalled = NO;
static BOOL WCLiquidGlassHomeCornerCellHookRetryScheduled = NO;
static NSUInteger WCLiquidGlassHomeCornerCellHookInstallAttempts = 0;
static __thread BOOL WCLiquidGlassHomeCornerCellLayoutApplying = NO;
static __thread BOOL WCLiquidGlassHomeCornerBackgroundColorApplying = NO;
static NSUInteger WCLiquidGlassHomeCornersConfigurationEpoch = 1;

typedef NS_ENUM(NSInteger, WCLiquidGlassHomeCornerTableRole) {
    WCLiquidGlassHomeCornerTableRoleNone = 0,
    WCLiquidGlassHomeCornerTableRoleHome,
    WCLiquidGlassHomeCornerTableRoleOtherTab
};

static UITableView *WCLiquidGlassHomeCornersTableForCell(UITableViewCell *cell);

@interface WCLiquidGlassHomeCornerCellState : NSObject
@property(nonatomic, assign) CGRect baseFrame;
@property(nonatomic, assign) CGRect appliedFrame;
@property(nonatomic, assign) BOOL hasAppliedFrame;
@property(nonatomic, strong, nullable) UIView *originalBackgroundView;
@property(nonatomic, strong, nullable) UIColor *originalBackgroundColor;
@property(nonatomic, strong, nullable) UIColor *originalContentBackgroundColor;
@property(nonatomic, assign) CGAffineTransform originalContentTransform;
@property(nonatomic, assign) CGFloat originalCornerRadius;
@property(nonatomic, assign) CACornerMask originalMaskedCorners;
@property(nonatomic, assign) BOOL originalMasksToBounds;
@property(nonatomic, strong, nullable) UIColor *appliedBackgroundColor;
@property(nonatomic, assign) NSUInteger appliedConfigurationEpoch;
@property(nonatomic, strong, nullable) UIVisualEffectView *glassOverlay;
@property(nonatomic, assign) NSInteger appliedGlassState;
@property(nonatomic, assign) BOOL captured;
@end

@implementation WCLiquidGlassHomeCornerCellState
@end

@interface WCLiquidGlassHomeCornerTableState : NSObject
@property(nonatomic, assign) UITableViewCellSeparatorStyle originalSeparatorStyle;
@property(nonatomic, strong, nullable) UIColor *originalSeparatorColor;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, id> *groupStates;
@property(nonatomic, assign) BOOL captured;
@end

@implementation WCLiquidGlassHomeCornerTableState
@end

@interface WCLiquidGlassHomeCornerGroupState : NSObject
@property(nonatomic, strong) UIVisualEffectView *glassView;
@property(nonatomic, weak, nullable) UIView *hostView;
@property(nonatomic, assign) NSInteger appliedGlassState;
@end

@implementation WCLiquidGlassHomeCornerGroupState
@end

static WCLiquidGlassHomeCornerTableState *WCLiquidGlassHomeCornerStateForTable(UITableView *tableView) {
    WCLiquidGlassHomeCornerTableState *state = objc_getAssociatedObject(tableView, WCLiquidGlassHomeCornerTableStateKey);
    if (!state) {
        state = [[WCLiquidGlassHomeCornerTableState alloc] init];
        state.originalSeparatorStyle = tableView.separatorStyle;
        state.originalSeparatorColor = tableView.separatorColor;
        state.groupStates = [[NSMutableDictionary alloc] init];
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
    if (tableView.separatorColor != UIColor.clearColor) {
        tableView.separatorColor = UIColor.clearColor;
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
        state.originalContentTransform = cell.contentView.transform;
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
    cell.contentView.transform = state.originalContentTransform;
    cell.layer.cornerRadius = state.originalCornerRadius;
    cell.layer.maskedCorners = state.originalMaskedCorners;
    cell.layer.masksToBounds = state.originalMasksToBounds;
    state.hasAppliedFrame = NO;
    state.appliedBackgroundColor = nil;
    state.appliedConfigurationEpoch = 0;
    [state.glassOverlay removeFromSuperview];
    state.appliedGlassState = NSIntegerMin;
}

static UIColor *WCLiquidGlassHomeCornerLiquidColor(void) {
    WCLiquidGlassGlassAppearance appearance = WCLiquidGlassPreferences.glassAppearance;
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        BOOL dark = traits.userInterfaceStyle == UIUserInterfaceStyleDark;
        switch (appearance) {
            case WCLiquidGlassGlassAppearanceTinted:
                return dark
                    ? [UIColor colorWithRed:0.62 green:0.74 blue:0.98 alpha:0.28]
                    : [UIColor colorWithRed:0.89 green:0.94 blue:1.00 alpha:0.24];
            case WCLiquidGlassGlassAppearanceBalanced:
                return dark
                    ? [UIColor colorWithWhite:1.0 alpha:0.20]
                    : [UIColor colorWithWhite:1.0 alpha:0.18];
            case WCLiquidGlassGlassAppearanceClear:
            default:
                return dark
                    ? [UIColor colorWithWhite:1.0 alpha:0.12]
                    : [UIColor colorWithWhite:1.0 alpha:0.10];
        }
    }];
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

static WCLiquidGlassHomeCornerGroupState *WCLiquidGlassHomeCornerGroupStateForSection(UITableView *tableView,
                                                                                       NSInteger section) {
    WCLiquidGlassHomeCornerTableState *tableState = WCLiquidGlassHomeCornerStateForTable(tableView);
    NSNumber *key = @(section);
    WCLiquidGlassHomeCornerGroupState *state = tableState.groupStates[key];
    if (!state) {
        state = [[WCLiquidGlassHomeCornerGroupState alloc] init];
        state.glassView = [[UIVisualEffectView alloc] initWithEffect:nil];
        state.glassView.userInteractionEnabled = NO;
        state.glassView.autoresizingMask = UIViewAutoresizingNone;
        state.glassView.layer.cornerCurve = kCACornerCurveContinuous;
        state.glassView.clipsToBounds = YES;
        state.appliedGlassState = NSIntegerMin;
        tableState.groupStates[key] = state;
    }
    return state;
}

static void WCLiquidGlassHomeCornerRemoveGroupOverlays(UITableView *tableView) {
    WCLiquidGlassHomeCornerTableState *tableState = objc_getAssociatedObject(tableView, WCLiquidGlassHomeCornerTableStateKey);
    for (WCLiquidGlassHomeCornerGroupState *state in tableState.groupStates.allValues) {
        [state.glassView removeFromSuperview];
        state.hostView = nil;
        state.appliedGlassState = NSIntegerMin;
    }
}

static void WCLiquidGlassHomeCornerUpdateGroupGlass(UITableView *tableView,
                                                     UITableViewCell *cell,
                                                     NSIndexPath *indexPath,
                                                     CGFloat inset,
                                                     CGFloat cornerRadius) {
    NSInteger rows = [tableView numberOfRowsInSection:indexPath.section];
    if (rows <= 0) {
        return;
    }
    UIView *hostView = cell.superview;
    if (!hostView) {
        return;
    }
    NSIndexPath *firstIndexPath = [NSIndexPath indexPathForRow:0 inSection:indexPath.section];
    NSIndexPath *lastIndexPath = [NSIndexPath indexPathForRow:rows - 1 inSection:indexPath.section];
    CGRect firstRect = [tableView rectForRowAtIndexPath:firstIndexPath];
    CGRect lastRect = [tableView rectForRowAtIndexPath:lastIndexPath];
    CGRect fullGroupRect = CGRectUnion(firstRect, lastRect);
    fullGroupRect.origin.x = inset;
    fullGroupRect.size.width = MAX(0.0, CGRectGetWidth(tableView.bounds) - inset * 2.0);
    CGRect coverageRect = CGRectIntersection(fullGroupRect,
                                              CGRectInset(tableView.bounds, 0.0, -180.0));
    if (CGRectIsNull(coverageRect) || CGRectIsEmpty(coverageRect)) {
        return;
    }
    CGRect groupRect = CGRectIntegral([tableView convertRect:coverageRect toView:hostView]);
    WCLiquidGlassHomeCornerGroupState *state = WCLiquidGlassHomeCornerGroupStateForSection(tableView, indexPath.section);
    UIVisualEffectView *glassView = state.glassView;
    NSUInteger firstCellIndex = NSNotFound;
    for (NSUInteger index = 0; index < hostView.subviews.count; index += 1) {
        if ([hostView.subviews[index] isKindOfClass:UITableViewCell.class]) {
            firstCellIndex = index;
            break;
        }
    }
    if (firstCellIndex == NSNotFound) {
        return;
    }
    NSUInteger glassIndex = [hostView.subviews indexOfObject:glassView];
    if (state.hostView != hostView || glassView.superview != hostView) {
        [glassView removeFromSuperview];
        [hostView insertSubview:glassView atIndex:firstCellIndex];
        state.hostView = hostView;
    } else if (glassIndex >= firstCellIndex) {
        [hostView insertSubview:glassView atIndex:firstCellIndex];
    }
    if (!CGRectEqualToRect(glassView.frame, groupRect)) {
        glassView.frame = groupRect;
    }
    if (glassView.layer.cornerRadius != cornerRadius) {
        glassView.layer.cornerRadius = cornerRadius;
    }
    CACornerMask corners = 0;
    if (CGRectGetMinY(coverageRect) <= CGRectGetMinY(fullGroupRect) + 0.5) {
        corners |= kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    }
    if (CGRectGetMaxY(coverageRect) >= CGRectGetMaxY(fullGroupRect) - 0.5) {
        corners |= kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    }
    if (glassView.layer.maskedCorners != corners) {
        glassView.layer.maskedCorners = corners;
    }
    NSInteger glassState = WCLiquidGlassPreferences.glassAppearance * 10 + tableView.traitCollection.userInterfaceStyle;
    if (state.appliedGlassState != glassState) {
        glassView.effect = WCLiquidGlassCurrentGlassEffect();
        state.appliedGlassState = glassState;
    }
    glassView.hidden = NO;
}

static void WCLiquidGlassHomeCornerUpdateGlassOverlay(UITableViewCell *cell,
                                                       WCLiquidGlassHomeCornerCellState *state,
                                                       CGFloat cornerRadius,
                                                       CACornerMask corners) {
    UIVisualEffectView *overlay = state.glassOverlay;
    if (!overlay) {
        overlay = [[UIVisualEffectView alloc] initWithEffect:nil];
        overlay.userInteractionEnabled = NO;
        overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        overlay.layer.cornerCurve = kCACornerCurveContinuous;
        state.glassOverlay = overlay;
        state.appliedGlassState = NSIntegerMin;
    }
    if (overlay.superview != cell.contentView) {
        [overlay removeFromSuperview];
        [cell.contentView insertSubview:overlay atIndex:0];
    }
    if (!CGRectEqualToRect(overlay.frame, cell.contentView.bounds)) {
        overlay.frame = cell.contentView.bounds;
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
    BOOL home = role == WCLiquidGlassHomeCornerTableRoleHome;
    CGFloat inset = home ? WCLiquidGlassPreferences.homeCornerInset : WCLiquidGlassPreferences.homeCornerInset;
    CGFloat radius = home ? WCLiquidGlassPreferences.homeCornerRadius : WCLiquidGlassPreferences.homeOtherTabsCornerRadius;
    BOOL separate = home && WCLiquidGlassPreferences.homeSeparateCardsEnabled;
    BOOL continuousHomeCard = home && !separate;
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
    if (continuousHomeCard && WCLiquidGlassPreferences.homeLiquidBackgroundEnabled) {
        corners = 0;
    }
    CGFloat targetCornerRadius = corners ? radius : 0.0;
    if (cell.layer.cornerRadius != targetCornerRadius) {
        cell.layer.cornerRadius = targetCornerRadius;
    }
    if (cell.layer.cornerCurve != kCACornerCurveContinuous) {
        cell.layer.cornerCurve = kCACornerCurveContinuous;
    }
    if (cell.layer.maskedCorners != corners) {
        cell.layer.maskedCorners = corners;
    }
    if (cell.layer.masksToBounds != (corners != 0)) {
        cell.layer.masksToBounds = corners != 0;
    }
    if (WCLiquidGlassPreferences.homeLiquidBackgroundEnabled) {
        if (cell.backgroundView) {
            cell.backgroundView = nil;
        }
        if (cell.contentView.backgroundColor != UIColor.clearColor) {
            cell.contentView.backgroundColor = UIColor.clearColor;
        }
        WCLiquidGlassHomeCornerHideNativeSeparators(cell);
        if (continuousHomeCard) {
            cell.backgroundColor = UIColor.clearColor;
            state.appliedBackgroundColor = UIColor.clearColor;
            state.appliedConfigurationEpoch = WCLiquidGlassHomeCornersConfigurationEpoch;
            if (!CGAffineTransformEqualToTransform(cell.contentView.transform, state.originalContentTransform)) {
                cell.contentView.transform = state.originalContentTransform;
            }
            [state.glassOverlay removeFromSuperview];
            state.appliedGlassState = NSIntegerMin;
            WCLiquidGlassHomeCornerUpdateGroupGlass(tableView, cell, indexPath, inset, radius);
        } else {
            WCLiquidGlassHomeCornerRemoveGroupOverlays(tableView);
            if (cell.backgroundColor != state.appliedBackgroundColor ||
                state.appliedConfigurationEpoch != WCLiquidGlassHomeCornersConfigurationEpoch) {
                UIColor *liquidColor = WCLiquidGlassHomeCornerLiquidColor();
                cell.backgroundColor = liquidColor;
                state.appliedBackgroundColor = liquidColor;
                state.appliedConfigurationEpoch = WCLiquidGlassHomeCornersConfigurationEpoch;
            }
            CGAffineTransform contentTransform = state.originalContentTransform;
            if (separate && gap > 0.0) {
                contentTransform = CGAffineTransformTranslate(contentTransform, 0.0, -gap * 0.5);
            }
            if (!CGAffineTransformEqualToTransform(cell.contentView.transform, contentTransform)) {
                cell.contentView.transform = contentTransform;
            }
            WCLiquidGlassHomeCornerUpdateGlassOverlay(cell, state, targetCornerRadius, corners);
        }
    } else {
        WCLiquidGlassHomeCornerRemoveGroupOverlays(tableView);
        cell.backgroundView = state.originalBackgroundView;
        cell.backgroundColor = state.originalBackgroundColor;
        cell.contentView.backgroundColor = state.originalContentBackgroundColor;
        state.appliedBackgroundColor = nil;
        state.appliedConfigurationEpoch = 0;
        [state.glassOverlay removeFromSuperview];
        state.appliedGlassState = NSIntegerMin;
    }
}

static void WCLiquidGlassHomeCornerScheduleFinalApply(UITableView *tableView,
                                                       UITableViewCell *cell) {
    if ([objc_getAssociatedObject(cell, WCLiquidGlassHomeCornerFinalApplyPendingKey) boolValue]) {
        return;
    }
    objc_setAssociatedObject(cell,
                             WCLiquidGlassHomeCornerFinalApplyPendingKey,
                             @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UITableView *weakTableView = tableView;
    __weak UITableViewCell *weakCell = cell;
    dispatch_async(dispatch_get_main_queue(), ^{
        UITableView *strongTableView = weakTableView;
        UITableViewCell *strongCell = weakCell;
        if (!strongCell) {
            return;
        }
        objc_setAssociatedObject(strongCell,
                                 WCLiquidGlassHomeCornerFinalApplyPendingKey,
                                 @NO,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!strongTableView || ![strongTableView indexPathForCell:strongCell]) {
            return;
        }
        WCLiquidGlassHomeCornerTableRole role = WCLiquidGlassHomeCornerRoleForTable(strongTableView);
        if (role != WCLiquidGlassHomeCornerTableRoleNone) {
            WCLiquidGlassHomeCornerApplyCell(strongTableView, strongCell, role);
        }
    });
}

static void WCLiquidGlassHomeCornerCellSetBackgroundColor(UIView *self,
                                                           SEL selector,
                                                           UIColor *color) {
    if (WCLiquidGlassOriginalHomeCornerCellSetBackgroundColor) {
        WCLiquidGlassOriginalHomeCornerCellSetBackgroundColor(self, selector, color);
    }
    if (WCLiquidGlassHomeCornerBackgroundColorApplying ||
        ![self isKindOfClass:UITableViewCell.class]) {
        return;
    }
    UITableViewCell *cell = (UITableViewCell *)self;
    UITableView *tableView = WCLiquidGlassHomeCornersTableForCell(cell);
    WCLiquidGlassHomeCornerTableRole role = WCLiquidGlassHomeCornerRoleForTable(tableView);
    if (role == WCLiquidGlassHomeCornerTableRoleNone ||
        !WCLiquidGlassPreferences.homeLiquidBackgroundEnabled) {
        return;
    }
    BOOL continuousHomeCard = role == WCLiquidGlassHomeCornerTableRoleHome &&
        !WCLiquidGlassPreferences.homeSeparateCardsEnabled;
    UIColor *targetColor = continuousHomeCard
        ? UIColor.clearColor
        : WCLiquidGlassHomeCornerLiquidColor();
    WCLiquidGlassHomeCornerBackgroundColorApplying = YES;
    if (WCLiquidGlassUIViewSetBackgroundColor) {
        WCLiquidGlassUIViewSetBackgroundColor(self, selector, targetColor);
    } else if (WCLiquidGlassOriginalHomeCornerCellSetBackgroundColor) {
        WCLiquidGlassOriginalHomeCornerCellSetBackgroundColor(self, selector, targetColor);
    }
    WCLiquidGlassHomeCornerBackgroundColorApplying = NO;
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
            WCLiquidGlassHomeCornerScheduleFinalApply(tableView, cell);
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
    WCLiquidGlassHomeCornerScheduleFinalApply(tableView, self);
    WCLiquidGlassHomeCornerCellLayoutApplying = NO;
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
    if (WCLiquidGlassOriginalHomeCornerCellLayoutSubviews &&
        WCLiquidGlassOriginalHomeCornerCellSetBackgroundColor) {
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
    if (!WCLiquidGlassOriginalHomeCornerCellLayoutSubviews) {
        MSHookMessageEx(cellClass,
                        @selector(layoutSubviews),
                        (IMP)&WCLiquidGlassHomeCornerCellLayoutSubviews,
                        (IMP *)&WCLiquidGlassOriginalHomeCornerCellLayoutSubviews);
    }
    Method backgroundColorMethod = class_getInstanceMethod(cellClass, @selector(setBackgroundColor:));
    if (backgroundColorMethod && !WCLiquidGlassOriginalHomeCornerCellSetBackgroundColor) {
        MSHookMessageEx(cellClass,
                        @selector(setBackgroundColor:),
                        (IMP)&WCLiquidGlassHomeCornerCellSetBackgroundColor,
                        (IMP *)&WCLiquidGlassOriginalHomeCornerCellSetBackgroundColor);
        Method viewBackgroundColorMethod = class_getInstanceMethod(UIView.class, @selector(setBackgroundColor:));
        WCLiquidGlassUIViewSetBackgroundColor = viewBackgroundColorMethod
            ? (void (*)(UIView *, SEL, UIColor *))method_getImplementation(viewBackgroundColorMethod)
            : NULL;
    }
}

void WCLiquidGlassInstallHomeCornersHooks(void) {
    if (WCLiquidGlassHomeCornersHooksInstalled) {
        WCLiquidGlassInstallHomeCornerCellLayoutHook();
        return;
    }
    WCLiquidGlassHomeCornersHooksInstalled = YES;
    WCLiquidGlassInstallHomeCornerCellLayoutHook();
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
    [report appendFormat:@"Home Corners Preferences\nenabled=%@ liquidBackground=%@ inset=%.1f homeRadius=%.1f separateCards=%@ gap=%.1f pinnedGap=%@ syncOtherTabs=%@ otherTabsRadius=%.1f glassAppearance=%ld\n",
     WCLiquidGlassPreferences.homeCornersEnabled ? @"YES" : @"NO",
     WCLiquidGlassPreferences.homeLiquidBackgroundEnabled ? @"YES" : @"NO",
     WCLiquidGlassPreferences.homeCornerInset,
     WCLiquidGlassPreferences.homeCornerRadius,
     WCLiquidGlassPreferences.homeSeparateCardsEnabled ? @"YES" : @"NO",
     WCLiquidGlassPreferences.homeCardGap,
     WCLiquidGlassPreferences.homePinnedCardGapEnabled ? @"YES" : @"NO",
     WCLiquidGlassPreferences.homeCornersSyncOtherTabsEnabled ? @"YES" : @"NO",
     WCLiquidGlassPreferences.homeOtherTabsCornerRadius,
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
    WCLiquidGlassHomeCornersControlTagHomeRadius,
    WCLiquidGlassHomeCornersControlTagOtherTabsRadius
};

static NSString *WCLiquidGlassHomeCornersDisplayValue(CGFloat value) {
    return [NSString stringWithFormat:@"%.0f pt", value];
}

@implementation WCLiquidGlassHomeCornersController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"首页圆角";
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
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 7 : 2;
}

- (void)tableView:(UITableView *)tableView
  willDisplayCell:(UITableViewCell *)cell
forRowAtIndexPath:(NSIndexPath *)indexPath {
    WCLiquidGlassStyleSettingsCardCell(cell, indexPath, tableView);
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
    return WCLiquidGlassSettingsFooterHeight(text, section == 0 ? 68.0 : 56.0);
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
