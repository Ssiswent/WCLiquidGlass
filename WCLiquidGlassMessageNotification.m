#import "WCLiquidGlassMessageNotification.h"

#import <CydiaSubstrate.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "WCLiquidGlassMenu.h"
#import "WCLiquidGlassPreferences.h"

static const void *WCLiquidGlassMessageNotificationStateKey = &WCLiquidGlassMessageNotificationStateKey;
static void (*WCLiquidGlassOriginalMessageNotificationLayoutSubviews)(UIView *, SEL) = NULL;
static BOOL WCLiquidGlassMessageNotificationHooksInstalled = NO;
static BOOL WCLiquidGlassMessageNotificationHookRetryScheduled = NO;
static NSUInteger WCLiquidGlassMessageNotificationHookInstallAttempts = 0;
static Class WCLiquidGlassMessageNotificationViewClass = Nil;

static id WCLiquidGlassMessageNotificationObjectValue(id target, SEL selector) {
    if (!target || !selector || ![target respondsToSelector:selector]) {
        return nil;
    }
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(target, selector);
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

@interface WCLiquidGlassMessageNotificationBackgroundState : NSObject
@property(nonatomic, weak) UIView *view;
@property(nonatomic, strong, nullable) UIColor *backgroundColor;
@property(nonatomic, strong, nullable) UIImage *image;
@property(nonatomic, strong, nullable) UIVisualEffect *effect;
@property(nonatomic, assign) BOOL capturesImage;
@property(nonatomic, assign) BOOL capturesEffect;
@end

@implementation WCLiquidGlassMessageNotificationBackgroundState
@end

@interface WCLiquidGlassMessageNotificationState : NSObject
@property(nonatomic, strong) UIVisualEffectView *glassView;
@property(nonatomic, strong) NSMutableArray<WCLiquidGlassMessageNotificationBackgroundState *> *nativeBackgrounds;
@property(nonatomic, strong, nullable) UIColor *originalBackgroundColor;
@property(nonatomic, assign) BOOL capturedOriginalBackgroundColor;
@property(nonatomic, assign) BOOL originalClipsToBounds;
@property(nonatomic, assign) BOOL capturedOriginalClipsToBounds;
@property(nonatomic, assign) NSInteger effectState;
@end

@implementation WCLiquidGlassMessageNotificationState

- (instancetype)init {
    self = [super init];
    if (self) {
        _nativeBackgrounds = [NSMutableArray array];
        _effectState = NSIntegerMin;
    }
    return self;
}

@end

static NSHashTable<UIView *> *WCLiquidGlassVisibleMessageNotificationViews(void) {
    static NSHashTable<UIView *> *views;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        views = [NSHashTable weakObjectsHashTable];
    });
    return views;
}

static Ivar WCLiquidGlassMessageNotificationFindIvar(Class viewClass, const char *name) {
    for (Class currentClass = viewClass; currentClass; currentClass = class_getSuperclass(currentClass)) {
        Ivar ivar = class_getInstanceVariable(currentClass, name);
        if (ivar) {
            return ivar;
        }
    }
    return NULL;
}

static void WCLiquidGlassMessageNotificationAppendBackgroundValue(
    id value,
    NSMutableArray<UIView *> *backgroundViews,
    UIView *owner) {
    if ([value isKindOfClass:UIView.class] && value != owner &&
        ![backgroundViews containsObject:value]) {
        [backgroundViews addObject:value];
    }
}

static WCLiquidGlassMessageNotificationBackgroundState *WCLiquidGlassMessageNotificationBackgroundStateForView(
    WCLiquidGlassMessageNotificationState *state,
    UIView *view) {
    for (WCLiquidGlassMessageNotificationBackgroundState *backgroundState in state.nativeBackgrounds) {
        if (backgroundState.view == view) {
            return backgroundState;
        }
    }
    WCLiquidGlassMessageNotificationBackgroundState *backgroundState =
        [[WCLiquidGlassMessageNotificationBackgroundState alloc] init];
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
    [state.nativeBackgrounds addObject:backgroundState];
    return backgroundState;
}

static BOOL WCLiquidGlassMessageNotificationViewCoversBanner(UIView *candidate, UIView *bannerView) {
    if (!candidate.superview || CGRectIsEmpty(candidate.bounds) || CGRectIsEmpty(bannerView.bounds)) {
        return NO;
    }
    CGRect frameInBanner = [candidate convertRect:candidate.bounds toView:bannerView];
    CGRect intersection = CGRectIntersection(frameInBanner, bannerView.bounds);
    if (CGRectIsNull(intersection) || CGRectIsEmpty(intersection)) {
        return NO;
    }
    CGFloat bannerArea = CGRectGetWidth(bannerView.bounds) * CGRectGetHeight(bannerView.bounds);
    CGFloat coveredArea = CGRectGetWidth(intersection) * CGRectGetHeight(intersection);
    return bannerArea > 0.0 && coveredArea / bannerArea >= 0.82;
}

static void WCLiquidGlassMessageNotificationCollectCoveringViews(
    UIView *container,
    UIView *bannerView,
    UIView *glassView,
    NSUInteger depth,
    NSMutableArray<UIView *> *backgroundViews) {
    if (depth > 6) {
        return;
    }
    for (UIView *subview in container.subviews) {
        if (subview == glassView) {
            continue;
        }
        if (WCLiquidGlassMessageNotificationViewCoversBanner(subview, bannerView) &&
            ![backgroundViews containsObject:subview]) {
            [backgroundViews addObject:subview];
        }
        WCLiquidGlassMessageNotificationCollectCoveringViews(subview,
                                                              bannerView,
                                                              glassView,
                                                              depth + 1,
                                                              backgroundViews);
    }
}

static NSArray<UIView *> *WCLiquidGlassMessageNotificationNativeBackgroundViews(
    UIView *view,
    UIView *glassView) {
    NSMutableArray<UIView *> *backgroundViews = [NSMutableArray array];
    const char *ivarNames[] = {
        "m_backgroundView",
        "_backgroundView",
        "m_bgImageView",
        "_bgImageView",
        "m_bgButton",
        "_bgButton",
        "m_backgroundImageView",
        "_backgroundImageView",
        "m_backgroundEffectView",
        "_backgroundEffectView"
    };
    for (NSUInteger index = 0; index < sizeof(ivarNames) / sizeof(ivarNames[0]); index += 1) {
        Ivar ivar = WCLiquidGlassMessageNotificationFindIvar(view.class, ivarNames[index]);
        id candidate = ivar ? object_getIvar(view, ivar) : nil;
        if ([candidate isKindOfClass:UIView.class] &&
            candidate != view &&
            ![backgroundViews containsObject:candidate]) {
            [backgroundViews addObject:candidate];
        }
    }
    const char *selectorNames[] = {
        "bgButton",
        "backgroundImageView",
        "backgroundView",
        "backgroundEffectView"
    };
    for (NSUInteger index = 0; index < sizeof(selectorNames) / sizeof(selectorNames[0]); index += 1) {
        id candidate = WCLiquidGlassMessageNotificationObjectValue(
            view,
            sel_registerName(selectorNames[index]));
        WCLiquidGlassMessageNotificationAppendBackgroundValue(candidate, backgroundViews, view);
    }
    WCLiquidGlassMessageNotificationCollectCoveringViews(view,
                                                          view,
                                                          glassView,
                                                          0,
                                                          backgroundViews);
    return backgroundViews.copy;
}

static void WCLiquidGlassMessageNotificationSuppressNativeBackground(
    UIView *view,
    WCLiquidGlassMessageNotificationState *state) {
    if (!state.capturedOriginalBackgroundColor) {
        state.capturedOriginalBackgroundColor = YES;
        state.originalBackgroundColor = view.backgroundColor;
    }
    if (!state.capturedOriginalClipsToBounds) {
        state.capturedOriginalClipsToBounds = YES;
        state.originalClipsToBounds = view.clipsToBounds;
    }
    view.backgroundColor = UIColor.clearColor;
    view.clipsToBounds = NO;

    for (UIView *backgroundView in WCLiquidGlassMessageNotificationNativeBackgroundViews(view,
                                                                                           state.glassView)) {
        WCLiquidGlassMessageNotificationBackgroundStateForView(state, backgroundView);
        backgroundView.backgroundColor = UIColor.clearColor;
        if ([backgroundView isKindOfClass:UIImageView.class]) {
            ((UIImageView *)backgroundView).image = nil;
        }
        if ([backgroundView isKindOfClass:UIVisualEffectView.class]) {
            ((UIVisualEffectView *)backgroundView).effect = nil;
        }
    }
}

static void WCLiquidGlassMessageNotificationRestoreNativeBackground(
    UIView *view,
    WCLiquidGlassMessageNotificationState *state) {
    if (state.capturedOriginalBackgroundColor) {
        view.backgroundColor = state.originalBackgroundColor;
    }
    if (state.capturedOriginalClipsToBounds) {
        view.clipsToBounds = state.originalClipsToBounds;
    }
    for (WCLiquidGlassMessageNotificationBackgroundState *backgroundState in state.nativeBackgrounds) {
        UIView *backgroundView = backgroundState.view;
        if (!backgroundView) {
            continue;
        }
        backgroundView.backgroundColor = backgroundState.backgroundColor;
        if (backgroundState.capturesImage && [backgroundView isKindOfClass:UIImageView.class]) {
            ((UIImageView *)backgroundView).image = backgroundState.image;
        }
        if (backgroundState.capturesEffect && [backgroundView isKindOfClass:UIVisualEffectView.class]) {
            ((UIVisualEffectView *)backgroundView).effect = backgroundState.effect;
        }
    }
    [state.glassView removeFromSuperview];
    [state.nativeBackgrounds removeAllObjects];
    state.capturedOriginalBackgroundColor = NO;
    state.originalBackgroundColor = nil;
    state.capturedOriginalClipsToBounds = NO;
}

static void WCLiquidGlassUpdateMessageNotificationGlass(UIView *view) {
    WCLiquidGlassMessageNotificationState *state =
        objc_getAssociatedObject(view, WCLiquidGlassMessageNotificationStateKey);
    if (!WCLiquidGlassPreferences.messageNotificationGlassEnabled) {
        if (state) {
            WCLiquidGlassMessageNotificationRestoreNativeBackground(view, state);
            objc_setAssociatedObject(view,
                                     WCLiquidGlassMessageNotificationStateKey,
                                     nil,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return;
    }

    if (!state) {
        state = [[WCLiquidGlassMessageNotificationState alloc] init];
        objc_setAssociatedObject(view,
                                 WCLiquidGlassMessageNotificationStateKey,
                                 state,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!state.glassView) {
        state.glassView = [[UIVisualEffectView alloc] initWithEffect:
            WCLiquidGlassGlassEffectForAppearance(WCLiquidGlassPreferences.messageNotificationGlassAppearance)];
        state.glassView.userInteractionEnabled = NO;
        state.glassView.clipsToBounds = YES;
        state.glassView.layer.cornerCurve = kCACornerCurveContinuous;
    }
    if (state.glassView.superview != view) {
        [state.glassView removeFromSuperview];
        [view insertSubview:state.glassView atIndex:0];
    }

    NSArray<UIView *> *nativeBackgroundViews =
        WCLiquidGlassMessageNotificationNativeBackgroundViews(view, state.glassView);
    WCLiquidGlassMessageNotificationSuppressNativeBackground(view, state);

    CGRect frame = CGRectIntegral(CGRectInset(view.bounds,
                                               -WCLiquidGlassPreferences.messageNotificationPadding,
                                               -WCLiquidGlassPreferences.messageNotificationPadding));
    if (!CGRectEqualToRect(state.glassView.frame, frame)) {
        state.glassView.frame = frame;
    }
    if (state.glassView.layer.cornerRadius != WCLiquidGlassPreferences.messageNotificationCornerRadius) {
        state.glassView.layer.cornerRadius = WCLiquidGlassPreferences.messageNotificationCornerRadius;
    }
    CACornerMask maskedCorners = view.layer.maskedCorners;
    if (maskedCorners == 0) {
        for (UIView *backgroundView in nativeBackgroundViews) {
            if (backgroundView.layer.maskedCorners != 0) {
                maskedCorners = backgroundView.layer.maskedCorners;
                break;
            }
        }
    }
    if (maskedCorners == 0) {
        maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner |
            kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    }
    state.glassView.layer.maskedCorners = maskedCorners;

    NSInteger effectState = WCLiquidGlassPreferences.messageNotificationGlassAppearance * 10 +
        view.traitCollection.userInterfaceStyle;
    if (state.effectState != effectState) {
        state.glassView.effect = WCLiquidGlassGlassEffectForAppearance(
            WCLiquidGlassPreferences.messageNotificationGlassAppearance);
        state.effectState = effectState;
    }
    state.glassView.hidden = NO;
}

static void WCLiquidGlassMessageNotificationLayoutSubviews(UIView *self, SEL selector) {
    if (WCLiquidGlassOriginalMessageNotificationLayoutSubviews) {
        WCLiquidGlassOriginalMessageNotificationLayoutSubviews(self, selector);
    }
    [WCLiquidGlassVisibleMessageNotificationViews() addObject:self];
    WCLiquidGlassUpdateMessageNotificationGlass(self);
}

static void WCLiquidGlassRefreshMessageNotificationGlass(void) {
    for (UIView *view in WCLiquidGlassVisibleMessageNotificationViews().allObjects) {
        WCLiquidGlassUpdateMessageNotificationGlass(view);
    }
}

void WCLiquidGlassInstallMessageNotificationHooks(void) {
    if (WCLiquidGlassMessageNotificationHooksInstalled) {
        return;
    }
    WCLiquidGlassMessageNotificationViewClass = NSClassFromString(@"QuickReplyMsgNotifyView");
    Method layoutMethod = class_getInstanceMethod(WCLiquidGlassMessageNotificationViewClass,
                                                   @selector(layoutSubviews));
    if (!WCLiquidGlassMessageNotificationViewClass || !layoutMethod) {
        if (!WCLiquidGlassMessageNotificationHookRetryScheduled &&
            WCLiquidGlassMessageNotificationHookInstallAttempts < 10) {
            WCLiquidGlassMessageNotificationHookRetryScheduled = YES;
            WCLiquidGlassMessageNotificationHookInstallAttempts += 1;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                WCLiquidGlassMessageNotificationHookRetryScheduled = NO;
                WCLiquidGlassInstallMessageNotificationHooks();
            });
        }
        return;
    }
    MSHookMessageEx(WCLiquidGlassMessageNotificationViewClass,
                    @selector(layoutSubviews),
                    (IMP)&WCLiquidGlassMessageNotificationLayoutSubviews,
                    (IMP *)&WCLiquidGlassOriginalMessageNotificationLayoutSubviews);
    WCLiquidGlassMessageNotificationHooksInstalled =
        WCLiquidGlassOriginalMessageNotificationLayoutSubviews != NULL;
    if (WCLiquidGlassMessageNotificationHooksInstalled) {
        [NSNotificationCenter.defaultCenter addObserverForName:WCLiquidGlassPreferencesDidChangeNotification
                                                        object:nil
                                                         queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(__unused NSNotification *notification) {
            WCLiquidGlassRefreshMessageNotificationGlass();
        }];
    }
}
