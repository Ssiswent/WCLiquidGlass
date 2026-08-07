#import "WCLiquidGlassUnreadMessageTip.h"

#import <CydiaSubstrate.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "WCLiquidGlassMenu.h"
#import "WCLiquidGlassPreferences.h"

static const void *WCLiquidGlassUnreadMessageTipStateKey = &WCLiquidGlassUnreadMessageTipStateKey;
static const void *WCLiquidGlassUnreadMessageTipOriginalLayoutKey = &WCLiquidGlassUnreadMessageTipOriginalLayoutKey;
static const void *WCLiquidGlassUnreadMessageTipHookedKey = &WCLiquidGlassUnreadMessageTipHookedKey;
static BOOL WCLiquidGlassUnreadMessageTipRetryScheduled = NO;
static NSUInteger WCLiquidGlassUnreadMessageTipInstallAttempts = 0;

@interface WCLiquidGlassUnreadMessageTipBackgroundState : NSObject
@property(nonatomic, weak) UIView *view;
@property(nonatomic, strong) UIColor *backgroundColor;
@property(nonatomic, strong) UIImage *image;
@property(nonatomic, strong) UIVisualEffect *effect;
@property(nonatomic, strong) NSDictionary<NSNumber *, id> *buttonImages;
@property(nonatomic, assign) BOOL capturesImage;
@property(nonatomic, assign) BOOL capturesEffect;
@property(nonatomic, assign) BOOL capturesButtonImages;
@end

@implementation WCLiquidGlassUnreadMessageTipBackgroundState
@end

@interface WCLiquidGlassUnreadMessageTipState : NSObject
@property(nonatomic, weak) UIView *surface;
@property(nonatomic, strong) UIVisualEffectView *glassView;
@property(nonatomic, strong) NSMutableArray<WCLiquidGlassUnreadMessageTipBackgroundState *> *backgrounds;
@property(nonatomic, assign) NSInteger effectState;
@end

@implementation WCLiquidGlassUnreadMessageTipState

- (instancetype)init {
    self = [super init];
    if (self) {
        _backgrounds = [NSMutableArray array];
        _effectState = NSIntegerMin;
    }
    return self;
}

@end

static NSHashTable<UIView *> *WCLiquidGlassUnreadMessageTipVisibleViews(void) {
    static NSHashTable<UIView *> *views;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        views = [NSHashTable weakObjectsHashTable];
    });
    return views;
}

static id WCLiquidGlassUnreadMessageTipValueForSelector(UIView *view, SEL selector) {
    if (![view respondsToSelector:selector]) {
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)(view, selector);
}

static UIView *WCLiquidGlassUnreadMessageTipSurface(UIView *view) {
    UIView *fallback = nil;
    for (NSString *name in @[@"bgButton", @"backgroundView", @"backgroundImageView", @"backgroundEffectView"]) {
        id candidate = WCLiquidGlassUnreadMessageTipValueForSelector(view, NSSelectorFromString(name));
        UIView *candidateView = [candidate isKindOfClass:UIView.class] ? candidate : nil;
        if (candidateView && !candidateView.hidden && !CGRectIsEmpty(candidateView.bounds)) {
            fallback = fallback ?: candidateView;
            if ([name isEqualToString:@"bgButton"] || [candidateView isKindOfClass:UIButton.class]) {
                return candidateView;
            }
        }
    }
    return [view isKindOfClass:UIButton.class] ? view : fallback;
}

static NSArray<UIView *> *WCLiquidGlassUnreadMessageTipBackgroundViews(UIView *view,
                                                                        UIView *surface) {
    NSMutableArray<UIView *> *views = [NSMutableArray array];
    for (NSString *name in @[@"bgButton", @"backgroundView", @"backgroundImageView", @"backgroundEffectView"]) {
        id candidate = WCLiquidGlassUnreadMessageTipValueForSelector(view, NSSelectorFromString(name));
        if ([candidate isKindOfClass:UIView.class] && candidate != view && ![views containsObject:candidate]) {
            [views addObject:candidate];
        }
    }
    if (surface && ![views containsObject:surface]) {
        [views addObject:surface];
    }
    if (surface) {
        CGRect surfaceBounds = surface.bounds;
        for (UIView *subview in surface.subviews) {
            if (![subview isKindOfClass:UIImageView.class] || [views containsObject:subview]) continue;
            CGRect frame = subview.frame;
            BOOL fillsSurface = fabs(CGRectGetWidth(frame) - CGRectGetWidth(surfaceBounds)) < 0.5 &&
                                 fabs(CGRectGetHeight(frame) - CGRectGetHeight(surfaceBounds)) < 0.5;
            if (fillsSurface) [views addObject:subview];
        }
    }
    return views.copy;
}

static WCLiquidGlassUnreadMessageTipBackgroundState *WCLiquidGlassUnreadMessageTipStateForBackground(
    WCLiquidGlassUnreadMessageTipState *state,
    UIView *view) {
    for (WCLiquidGlassUnreadMessageTipBackgroundState *backgroundState in state.backgrounds) {
        if (backgroundState.view == view) {
            return backgroundState;
        }
    }
    WCLiquidGlassUnreadMessageTipBackgroundState *backgroundState =
        [[WCLiquidGlassUnreadMessageTipBackgroundState alloc] init];
    backgroundState.view = view;
    backgroundState.backgroundColor = view.backgroundColor;
    if ([view isKindOfClass:UIImageView.class]) {
        backgroundState.capturesImage = YES;
        backgroundState.image = ((UIImageView *)view).image;
    }
    if ([view isKindOfClass:UIVisualEffectView.class]) {
        backgroundState.capturesEffect = YES;
        backgroundState.effect = ((UIVisualEffectView *)view).effect;
    }
    if ([view isKindOfClass:UIButton.class]) {
        UIButton *button = (UIButton *)view;
        backgroundState.capturesButtonImages = YES;
        backgroundState.buttonImages = @{
            @(UIControlStateNormal): [button backgroundImageForState:UIControlStateNormal] ?: (id)[NSNull null],
            @(UIControlStateHighlighted): [button backgroundImageForState:UIControlStateHighlighted] ?: (id)[NSNull null],
            @(UIControlStateSelected): [button backgroundImageForState:UIControlStateSelected] ?: (id)[NSNull null],
            @(UIControlStateDisabled): [button backgroundImageForState:UIControlStateDisabled] ?: (id)[NSNull null]
        };
    }
    [state.backgrounds addObject:backgroundState];
    return backgroundState;
}

static void WCLiquidGlassUnreadMessageTipSuppressBackground(
    WCLiquidGlassUnreadMessageTipBackgroundState *backgroundState) {
    UIView *view = backgroundState.view;
    if (!view) {
        return;
    }
    view.backgroundColor = UIColor.clearColor;
    if (backgroundState.capturesImage && [view isKindOfClass:UIImageView.class]) {
        ((UIImageView *)view).image = nil;
    }
    if (backgroundState.capturesEffect && [view isKindOfClass:UIVisualEffectView.class]) {
        ((UIVisualEffectView *)view).effect = nil;
    }
    if (backgroundState.capturesButtonImages && [view isKindOfClass:UIButton.class]) {
        UIButton *button = (UIButton *)view;
        for (NSNumber *stateValue in backgroundState.buttonImages) {
            [button setBackgroundImage:nil forState:(UIControlState)stateValue.unsignedIntegerValue];
        }
    }
}

static void WCLiquidGlassUnreadMessageTipRestoreBackground(
    WCLiquidGlassUnreadMessageTipBackgroundState *backgroundState) {
    UIView *view = backgroundState.view;
    if (!view) {
        return;
    }
    view.backgroundColor = backgroundState.backgroundColor;
    if (backgroundState.capturesImage && [view isKindOfClass:UIImageView.class]) {
        ((UIImageView *)view).image = backgroundState.image;
    }
    if (backgroundState.capturesEffect && [view isKindOfClass:UIVisualEffectView.class]) {
        ((UIVisualEffectView *)view).effect = backgroundState.effect;
    }
    if (backgroundState.capturesButtonImages && [view isKindOfClass:UIButton.class]) {
        UIButton *button = (UIButton *)view;
        for (NSNumber *stateValue in backgroundState.buttonImages) {
            UIImage *image = backgroundState.buttonImages[stateValue];
            [button setBackgroundImage:[image isKindOfClass:UIImage.class] ? image : nil
                              forState:(UIControlState)stateValue.unsignedIntegerValue];
        }
    }
}

static void WCLiquidGlassUnreadMessageTipRestore(UIView *view,
                                                  WCLiquidGlassUnreadMessageTipState *state) {
    for (WCLiquidGlassUnreadMessageTipBackgroundState *backgroundState in state.backgrounds) {
        WCLiquidGlassUnreadMessageTipRestoreBackground(backgroundState);
    }
    [state.glassView removeFromSuperview];
    [state.backgrounds removeAllObjects];
    state.surface = nil;
    state.effectState = NSIntegerMin;
    objc_setAssociatedObject(view, WCLiquidGlassUnreadMessageTipStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void WCLiquidGlassUnreadMessageTipUpdate(UIView *view) {
    WCLiquidGlassUnreadMessageTipState *state =
        objc_getAssociatedObject(view, WCLiquidGlassUnreadMessageTipStateKey);
    if (!WCLiquidGlassPreferences.unreadMessageTipGlassEnabled) {
        if (state) {
            WCLiquidGlassUnreadMessageTipRestore(view, state);
        }
        return;
    }

    UIView *surface = WCLiquidGlassUnreadMessageTipSurface(view);
    if (!surface || CGRectIsEmpty(surface.bounds)) {
        return;
    }
    if (!state) {
        state = [[WCLiquidGlassUnreadMessageTipState alloc] init];
        objc_setAssociatedObject(view, WCLiquidGlassUnreadMessageTipStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    state.surface = surface;
    for (UIView *backgroundView in WCLiquidGlassUnreadMessageTipBackgroundViews(view, surface)) {
        WCLiquidGlassUnreadMessageTipSuppressBackground(
            WCLiquidGlassUnreadMessageTipStateForBackground(state, backgroundView));
    }
    if (!state.glassView) {
        state.glassView = [[UIVisualEffectView alloc] initWithEffect:
            WCLiquidGlassGlassEffectForAppearance(WCLiquidGlassPreferences.glassAppearance)];
        state.glassView.userInteractionEnabled = NO;
        state.glassView.clipsToBounds = YES;
        state.glassView.layer.cornerCurve = kCACornerCurveContinuous;
    }
    if (state.glassView.superview != surface) {
        [state.glassView removeFromSuperview];
        [surface insertSubview:state.glassView atIndex:0];
    }
    CGRect glassBounds = surface.bounds;
    glassBounds.size.width += 16.0;
    state.glassView.frame = glassBounds;
    CGFloat radius = surface.layer.cornerRadius;
    if (radius <= 0.0) {
        radius = MIN(CGRectGetWidth(surface.bounds), CGRectGetHeight(surface.bounds)) * 0.5;
    }
    state.glassView.layer.cornerRadius = radius;
    state.glassView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMinXMaxYCorner;
    NSInteger effectState = WCLiquidGlassPreferences.glassAppearance * 10 +
        surface.traitCollection.userInterfaceStyle;
    if (state.effectState != effectState) {
        state.glassView.effect = WCLiquidGlassGlassEffectForAppearance(WCLiquidGlassPreferences.glassAppearance);
        state.effectState = effectState;
    }
    state.glassView.hidden = NO;
    [WCLiquidGlassUnreadMessageTipVisibleViews() addObject:view];
}

static IMP WCLiquidGlassUnreadMessageTipOriginalLayoutForClass(Class viewClass) {
    for (Class currentClass = viewClass; currentClass; currentClass = class_getSuperclass(currentClass)) {
        NSValue *value = objc_getAssociatedObject((id)currentClass, WCLiquidGlassUnreadMessageTipOriginalLayoutKey);
        if (value) {
            return value.pointerValue;
        }
    }
    return NULL;
}

static void WCLiquidGlassUnreadMessageTipLayoutSubviews(UIView *self, SEL selector) {
    IMP original = WCLiquidGlassUnreadMessageTipOriginalLayoutForClass(self.class);
    if (original) {
        ((void (*)(UIView *, SEL))original)(self, selector);
    }
    WCLiquidGlassUnreadMessageTipUpdate(self);
}

static void WCLiquidGlassUnreadMessageTipRefresh(void) {
    for (UIView *view in WCLiquidGlassUnreadMessageTipVisibleViews().allObjects) {
        WCLiquidGlassUnreadMessageTipUpdate(view);
    }
}

static void WCLiquidGlassUnreadMessageTipHookClass(Class viewClass) {
    if (!viewClass || objc_getAssociatedObject((id)viewClass, WCLiquidGlassUnreadMessageTipHookedKey)) {
        return;
    }
    Method layoutMethod = class_getInstanceMethod(viewClass, @selector(layoutSubviews));
    if (!layoutMethod) {
        return;
    }
    IMP original = NULL;
    MSHookMessageEx(viewClass,
                    @selector(layoutSubviews),
                    (IMP)&WCLiquidGlassUnreadMessageTipLayoutSubviews,
                    &original);
    if (!original) {
        return;
    }
    objc_setAssociatedObject((id)viewClass,
                             WCLiquidGlassUnreadMessageTipOriginalLayoutKey,
                             [NSValue valueWithPointer:original],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject((id)viewClass,
                             WCLiquidGlassUnreadMessageTipHookedKey,
                             @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void WCLiquidGlassInstallUnreadMessageTipHooks(void) {
    NSArray<NSString *> *classNames = @[
        @"MMEdgeTipsView"
    ];
    BOOL installed = NO;
    for (NSString *className in classNames) {
        Class viewClass = NSClassFromString(className);
        if (!viewClass) {
            continue;
        }
        WCLiquidGlassUnreadMessageTipHookClass(viewClass);
        installed = installed || objc_getAssociatedObject((id)viewClass, WCLiquidGlassUnreadMessageTipHookedKey) != nil;
    }
    if (!installed && !WCLiquidGlassUnreadMessageTipRetryScheduled &&
        WCLiquidGlassUnreadMessageTipInstallAttempts < 20) {
        WCLiquidGlassUnreadMessageTipRetryScheduled = YES;
        WCLiquidGlassUnreadMessageTipInstallAttempts += 1;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            WCLiquidGlassUnreadMessageTipRetryScheduled = NO;
            WCLiquidGlassInstallUnreadMessageTipHooks();
        });
    }
    static dispatch_once_t observerToken;
    dispatch_once(&observerToken, ^{
        [NSNotificationCenter.defaultCenter addObserverForName:WCLiquidGlassPreferencesDidChangeNotification
                                                        object:nil
                                                         queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(__unused NSNotification *notification) {
            WCLiquidGlassUnreadMessageTipRefresh();
        }];
    });
}
