#import "WCLiquidGlassChatBottomMenu.h"

#import <CydiaSubstrate.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "WCLiquidGlassMenu.h"
#import "WCLiquidGlassPreferences.h"

/*
 * ThemePro's attachment-material path is a layout hook, not a replacement
 * for WeChat's attachment controller.  Keep the same boundary here: the
 * native panel still owns its buttons, actions, sizing and presentation; we
 * only replace the panel's covering background layer with one glass view.
 */

static const void *WCLiquidGlassChatBottomMenuStateKey = &WCLiquidGlassChatBottomMenuStateKey;
static void (*WCLiquidGlassOriginalInputToolContainerLayoutSubviews)(UIView *, SEL) = NULL;
static void (*WCLiquidGlassOriginalSelectAttachmentLayoutSubviews)(UIView *, SEL) = NULL;
static void (*WCLiquidGlassOriginalInputToolViewBarLayoutSubviews)(UIView *, SEL) = NULL;
static BOOL WCLiquidGlassInputToolContainerHookInstalled = NO;
static BOOL WCLiquidGlassSelectAttachmentHookInstalled = NO;
static BOOL WCLiquidGlassInputToolViewBarHookInstalled = NO;
static BOOL WCLiquidGlassChatBottomMenuObserverInstalled = NO;
static BOOL WCLiquidGlassChatBottomMenuHookRetryScheduled = NO;
static NSUInteger WCLiquidGlassChatBottomMenuHookInstallAttempts = 0;

@interface WCLiquidGlassChatBottomMenuBackgroundState : NSObject

@property(nonatomic, weak) UIView *view;
@property(nonatomic, strong, nullable) UIColor *backgroundColor;
@property(nonatomic, strong, nullable) UIImage *image;
@property(nonatomic, strong, nullable) UIVisualEffect *effect;
@property(nonatomic, assign) BOOL capturesImage;
@property(nonatomic, assign) BOOL capturesEffect;

@end

@implementation WCLiquidGlassChatBottomMenuBackgroundState
@end

@interface WCLiquidGlassChatBottomMenuState : NSObject

@property(nonatomic, strong) UIVisualEffectView *glassView;
@property(nonatomic, strong) NSMutableArray<WCLiquidGlassChatBottomMenuBackgroundState *> *nativeBackgrounds;
@property(nonatomic, strong, nullable) UIColor *originalBackgroundColor;
@property(nonatomic, assign) BOOL capturedOriginalBackgroundColor;
@property(nonatomic, assign) NSInteger effectState;

@end

@implementation WCLiquidGlassChatBottomMenuState

- (instancetype)init {
    self = [super init];
    if (self) {
        _nativeBackgrounds = [NSMutableArray array];
        _effectState = NSIntegerMin;
    }
    return self;
}

@end

static NSHashTable<UIView *> *WCLiquidGlassVisibleChatBottomMenuViews(void) {
    static NSHashTable<UIView *> *views;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        views = [NSHashTable weakObjectsHashTable];
    });
    return views;
}

static BOOL WCLiquidGlassChatBottomMenuClassNameContains(id object, NSString *token) {
    if (!object || token.length == 0) {
        return NO;
    }
    return [NSStringFromClass([object class]).lowercaseString containsString:token.lowercaseString];
}

static BOOL WCLiquidGlassChatBottomMenuIsCandidate(UIView *view) {
    return WCLiquidGlassChatBottomMenuClassNameContains(view, @"inputtoolcontainerview") ||
        WCLiquidGlassChatBottomMenuClassNameContains(view, @"selectattachmentview") ||
        WCLiquidGlassChatBottomMenuClassNameContains(view, @"inputtoolviewbar") ||
        WCLiquidGlassChatBottomMenuClassNameContains(view, @"mminputtoolview");
}

static BOOL WCLiquidGlassChatBottomMenuHasVisibleSelectDescendant(UIView *view,
                                                                  NSUInteger depth) {
    if (!view || depth > 8) {
        return NO;
    }
    for (UIView *subview in view.subviews) {
        if (WCLiquidGlassChatBottomMenuClassNameContains(subview, @"selectattachmentview") &&
            !subview.hidden && subview.alpha > 0.01 && !CGRectIsEmpty(subview.bounds)) {
            return YES;
        }
        if (WCLiquidGlassChatBottomMenuHasVisibleSelectDescendant(subview, depth + 1)) {
            return YES;
        }
    }
    return NO;
}

static BOOL WCLiquidGlassChatBottomMenuHasVisibleAttachmentDescendant(UIView *view,
                                                                       NSUInteger depth) {
    if (!view || depth > 10) {
        return NO;
    }
    for (UIView *subview in view.subviews) {
        if ((WCLiquidGlassChatBottomMenuClassNameContains(subview, @"inputtoolcontainerview") ||
             WCLiquidGlassChatBottomMenuClassNameContains(subview, @"selectattachmentview") ||
             WCLiquidGlassChatBottomMenuClassNameContains(subview, @"inputtoolviewbar")) &&
            !subview.hidden && subview.alpha > 0.01 && !CGRectIsEmpty(subview.bounds)) {
            return YES;
        }
        if (WCLiquidGlassChatBottomMenuHasVisibleAttachmentDescendant(subview, depth + 1)) {
            return YES;
        }
    }
    return NO;
}

static BOOL WCLiquidGlassChatBottomMenuIsLikelyVisibleInputToolPanel(UIView *view) {
    if (!view || view.hidden || view.alpha <= 0.01 || CGRectIsEmpty(view.bounds)) {
        return NO;
    }
    if (WCLiquidGlassChatBottomMenuHasVisibleAttachmentDescendant(view, 0)) {
        return YES;
    }
    // Some WeChat builds put the attachment buttons directly in MMInputToolView
    // and do not expose either of the two panel classes above.  The attachment
    // panel is substantially taller than the normal input toolbar and contains
    // multiple controls; use that shape only as a fallback host.
    if (!WCLiquidGlassChatBottomMenuClassNameContains(view, @"mminputtoolview") ||
        CGRectGetHeight(view.bounds) < 120.0) {
        return NO;
    }
    NSUInteger visibleControls = 0;
    for (UIView *subview in view.subviews) {
        if (!subview.hidden && subview.alpha > 0.01 && [subview isKindOfClass:UIControl.class]) {
            visibleControls += 1;
        }
    }
    return visibleControls >= 2;
}

static BOOL WCLiquidGlassChatBottomMenuShouldUseHost(UIView *view) {
    if (!WCLiquidGlassChatBottomMenuIsCandidate(view)) {
        return NO;
    }
    if (WCLiquidGlassChatBottomMenuClassNameContains(view, @"mminputtoolview")) {
        if (!WCLiquidGlassChatBottomMenuIsLikelyVisibleInputToolPanel(view)) {
            return NO;
        }
        if (WCLiquidGlassChatBottomMenuHasVisibleAttachmentDescendant(view, 0)) {
            // A nested attachment host will get the single glass layer.  The
            // outer input toolbar must not receive a second full-size layer.
            return NO;
        }
    }
    if (WCLiquidGlassChatBottomMenuClassNameContains(view, @"inputtoolcontainerview") &&
        WCLiquidGlassChatBottomMenuHasVisibleSelectDescendant(view, 0)) {
        // SelectAttachmentView owns the visible panel when it is present.  A
        // single glass layer avoids stacking two translucent materials.
        return NO;
    }
    return YES;
}

static Ivar WCLiquidGlassChatBottomMenuFindIvar(Class viewClass, const char *name) {
    for (Class currentClass = viewClass; currentClass; currentClass = class_getSuperclass(currentClass)) {
        Ivar ivar = class_getInstanceVariable(currentClass, name);
        if (ivar) {
            return ivar;
        }
    }
    return NULL;
}

static UIView *WCLiquidGlassChatBottomMenuObjectIvar(UIView *view, const char *name) {
    Ivar ivar = WCLiquidGlassChatBottomMenuFindIvar(view.class, name);
    if (!ivar || ivar_getTypeEncoding(ivar)[0] != '@') {
        return nil;
    }
    id object = object_getIvar(view, ivar);
    return [object isKindOfClass:UIView.class] ? object : nil;
}

static UIView *WCLiquidGlassChatBottomMenuViewProperty(UIView *view, SEL selector) {
    if (![view respondsToSelector:selector]) {
        return nil;
    }
    id object = ((id (*)(id, SEL))objc_msgSend)(view, selector);
    return [object isKindOfClass:UIView.class] ? object : nil;
}

static BOOL WCLiquidGlassChatBottomMenuViewCoversHost(UIView *candidate, UIView *host) {
    if (!candidate || candidate == host || !candidate.superview ||
        CGRectIsEmpty(candidate.bounds) || CGRectIsEmpty(host.bounds)) {
        return NO;
    }
    CGRect frameInHost = [candidate convertRect:candidate.bounds toView:host];
    CGRect intersection = CGRectIntersection(frameInHost, host.bounds);
    if (CGRectIsNull(intersection) || CGRectIsEmpty(intersection)) {
        return NO;
    }
    CGFloat hostArea = CGRectGetWidth(host.bounds) * CGRectGetHeight(host.bounds);
    CGFloat coveredArea = CGRectGetWidth(intersection) * CGRectGetHeight(intersection);
    return hostArea > 0.0 && coveredArea / hostArea >= 0.80;
}

static void WCLiquidGlassChatBottomMenuAppendBackgroundView(NSMutableArray<UIView *> *views,
                                                             UIView *candidate,
                                                             UIView *host) {
    if (!candidate || candidate == host || !WCLiquidGlassChatBottomMenuViewCoversHost(candidate, host) ||
        [views containsObject:candidate]) {
        return;
    }
    [views addObject:candidate];
}

static BOOL WCLiquidGlassChatBottomMenuLooksLikeBackgroundView(UIView *view) {
    return [view isKindOfClass:UIVisualEffectView.class] ||
        [view isKindOfClass:UIImageView.class] ||
        WCLiquidGlassChatBottomMenuClassNameContains(view, @"background") ||
        WCLiquidGlassChatBottomMenuClassNameContains(view, @"effect") ||
        WCLiquidGlassChatBottomMenuClassNameContains(view, @"backdrop") ||
        WCLiquidGlassChatBottomMenuClassNameContains(view, @"material") ||
        WCLiquidGlassChatBottomMenuClassNameContains(view, @"visual") ||
        WCLiquidGlassChatBottomMenuClassNameContains(view, @"inputtoolviewbar");
}

static void WCLiquidGlassChatBottomMenuCollectCoveringViews(UIView *container,
                                                             UIView *host,
                                                             UIView *glassView,
                                                             NSUInteger depth,
                                                             NSMutableArray<UIView *> *views) {
    if (!container || depth > 8) {
        return;
    }
    for (UIView *subview in container.subviews) {
        if (subview == glassView || subview.hidden || subview.alpha <= 0.01) {
            continue;
        }
        if (WCLiquidGlassChatBottomMenuLooksLikeBackgroundView(subview) &&
            WCLiquidGlassChatBottomMenuViewCoversHost(subview, host)) {
            WCLiquidGlassChatBottomMenuAppendBackgroundView(views, subview, host);
        }
        WCLiquidGlassChatBottomMenuCollectCoveringViews(subview,
                                                        host,
                                                        glassView,
                                                        depth + 1,
                                                        views);
    }
}

static NSArray<UIView *> *WCLiquidGlassChatBottomMenuNativeBackgroundViews(
    UIView *host,
    UIView *glassView) {
    NSMutableArray<UIView *> *views = [NSMutableArray array];
    const char *ivarNames[] = {
        "m_backgroundView",
        "_backgroundView",
        "backgroundView",
        "m_bgImageView",
        "_bgImageView",
        "effectSubview",
        "_effectSubview",
        "topBackgroundView",
        "_topBackgroundView"
    };
    for (NSUInteger index = 0; index < sizeof(ivarNames) / sizeof(ivarNames[0]); index += 1) {
        UIView *candidate = WCLiquidGlassChatBottomMenuObjectIvar(host, ivarNames[index]);
        if (candidate != glassView) {
            WCLiquidGlassChatBottomMenuAppendBackgroundView(views, candidate, host);
        }
    }

    SEL propertySelectors[] = {
        NSSelectorFromString(@"backgroundView"),
        NSSelectorFromString(@"effectSubview"),
        NSSelectorFromString(@"topBackgroundView")
    };
    for (NSUInteger index = 0; index < sizeof(propertySelectors) / sizeof(propertySelectors[0]); index += 1) {
        UIView *candidate = WCLiquidGlassChatBottomMenuViewProperty(host, propertySelectors[index]);
        if (candidate != glassView) {
            WCLiquidGlassChatBottomMenuAppendBackgroundView(views, candidate, host);
        }
    }

    WCLiquidGlassChatBottomMenuCollectCoveringViews(host, host, glassView, 0, views);
    return views.copy;
}

static WCLiquidGlassChatBottomMenuBackgroundState *WCLiquidGlassChatBottomMenuStateForBackground(
    WCLiquidGlassChatBottomMenuState *state,
    UIView *view) {
    for (WCLiquidGlassChatBottomMenuBackgroundState *backgroundState in state.nativeBackgrounds) {
        if (backgroundState.view == view) {
            return backgroundState;
        }
    }
    WCLiquidGlassChatBottomMenuBackgroundState *backgroundState =
        [[WCLiquidGlassChatBottomMenuBackgroundState alloc] init];
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

static void WCLiquidGlassChatBottomMenuRestore(UIView *view,
                                                WCLiquidGlassChatBottomMenuState *state) {
    if (!state) {
        return;
    }
    if (state.capturedOriginalBackgroundColor) {
        view.backgroundColor = state.originalBackgroundColor;
    }
    for (WCLiquidGlassChatBottomMenuBackgroundState *backgroundState in state.nativeBackgrounds) {
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
    state.capturedOriginalBackgroundColor = NO;
    state.originalBackgroundColor = nil;
    state.effectState = NSIntegerMin;
    [state.nativeBackgrounds removeAllObjects];
}

static void WCLiquidGlassChatBottomMenuUpdate(UIView *view) {
    WCLiquidGlassChatBottomMenuState *state =
        objc_getAssociatedObject(view, WCLiquidGlassChatBottomMenuStateKey);
    if (!WCLiquidGlassPreferences.chatBottomMenuGlassEnabled ||
        !WCLiquidGlassChatBottomMenuShouldUseHost(view) ||
        !view.window || view.hidden || view.alpha <= 0.01 || CGRectIsEmpty(view.bounds)) {
        WCLiquidGlassChatBottomMenuRestore(view, state);
        return;
    }

    if (!state) {
        state = [[WCLiquidGlassChatBottomMenuState alloc] init];
        objc_setAssociatedObject(view,
                                 WCLiquidGlassChatBottomMenuStateKey,
                                 state,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!state.capturedOriginalBackgroundColor) {
        state.capturedOriginalBackgroundColor = YES;
        state.originalBackgroundColor = view.backgroundColor;
    }
    if (!state.glassView) {
        state.glassView = [[UIVisualEffectView alloc] initWithEffect:nil];
        state.glassView.userInteractionEnabled = NO;
        state.glassView.clipsToBounds = YES;
        state.glassView.layer.cornerCurve = kCACornerCurveContinuous;
        state.glassView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    }
    if (state.glassView.superview != view) {
        [state.glassView removeFromSuperview];
        [view insertSubview:state.glassView atIndex:0];
    }

    view.backgroundColor = UIColor.clearColor;
    for (UIView *backgroundView in WCLiquidGlassChatBottomMenuNativeBackgroundViews(view,
                                                                                       state.glassView)) {
        WCLiquidGlassChatBottomMenuStateForBackground(state, backgroundView);
        backgroundView.backgroundColor = UIColor.clearColor;
        if ([backgroundView isKindOfClass:UIImageView.class]) {
            ((UIImageView *)backgroundView).image = nil;
        }
        if ([backgroundView isKindOfClass:UIVisualEffectView.class]) {
            ((UIVisualEffectView *)backgroundView).effect = nil;
        }
    }

    state.glassView.frame = view.bounds;
    CGFloat height = CGRectGetHeight(view.bounds);
    CGFloat cornerRadius = view.layer.cornerRadius > 0.0
        ? view.layer.cornerRadius
        : MIN(28.0, MAX(0.0, height * 0.5));
    state.glassView.layer.cornerRadius = cornerRadius;
    state.glassView.layer.maskedCorners = view.layer.maskedCorners ?:
        (kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner |
         kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner);

    NSInteger effectState = WCLiquidGlassPreferences.glassAppearance * 10 +
        view.traitCollection.userInterfaceStyle;
    if (state.effectState != effectState) {
        state.glassView.effect = WCLiquidGlassCurrentGlassEffect();
        state.effectState = effectState;
    }
    state.glassView.hidden = NO;
}

static void WCLiquidGlassChatBottomMenuLayoutInputToolContainer(UIView *self, SEL selector) {
    if (WCLiquidGlassOriginalInputToolContainerLayoutSubviews) {
        WCLiquidGlassOriginalInputToolContainerLayoutSubviews(self, selector);
    }
    [WCLiquidGlassVisibleChatBottomMenuViews() addObject:self];
    WCLiquidGlassChatBottomMenuUpdate(self);
}

static void WCLiquidGlassChatBottomMenuLayoutSelectAttachment(UIView *self, SEL selector) {
    if (WCLiquidGlassOriginalSelectAttachmentLayoutSubviews) {
        WCLiquidGlassOriginalSelectAttachmentLayoutSubviews(self, selector);
    }
    [WCLiquidGlassVisibleChatBottomMenuViews() addObject:self];
    WCLiquidGlassChatBottomMenuUpdate(self);
}

static void WCLiquidGlassChatBottomMenuLayoutInputToolViewBar(UIView *self, SEL selector) {
    if (WCLiquidGlassOriginalInputToolViewBarLayoutSubviews) {
        WCLiquidGlassOriginalInputToolViewBarLayoutSubviews(self, selector);
    }
    [WCLiquidGlassVisibleChatBottomMenuViews() addObject:self];
    WCLiquidGlassChatBottomMenuUpdate(self);
}

static void WCLiquidGlassRefreshChatBottomMenuViews(void) {
    for (UIView *view in WCLiquidGlassVisibleChatBottomMenuViews().allObjects) {
        if (view.window) {
            WCLiquidGlassChatBottomMenuUpdate(view);
        } else {
            WCLiquidGlassChatBottomMenuState *state =
                objc_getAssociatedObject(view, WCLiquidGlassChatBottomMenuStateKey);
            WCLiquidGlassChatBottomMenuRestore(view, state);
        }
    }
}

static void WCLiquidGlassChatBottomMenuRefreshVisibleHierarchy(UIView *view,
                                                               NSUInteger depth) {
    if (!view || depth > 32) {
        return;
    }
    if (WCLiquidGlassChatBottomMenuIsCandidate(view)) {
        [WCLiquidGlassVisibleChatBottomMenuViews() addObject:view];
        WCLiquidGlassChatBottomMenuUpdate(view);
    }
    for (UIView *subview in view.subviews) {
        WCLiquidGlassChatBottomMenuRefreshVisibleHierarchy(subview, depth + 1);
    }
}

void WCLiquidGlassRefreshChatBottomMenuHierarchy(UIView *rootView) {
    if (!rootView) {
        return;
    }
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            WCLiquidGlassRefreshChatBottomMenuHierarchy(rootView);
        });
        return;
    }
    if (WCLiquidGlassInputToolContainerHookInstalled &&
        WCLiquidGlassSelectAttachmentHookInstalled &&
        WCLiquidGlassInputToolViewBarHookInstalled) {
        return;
    }
    if (CGRectGetHeight(rootView.bounds) < 120.0 &&
        !WCLiquidGlassChatBottomMenuHasVisibleAttachmentDescendant(rootView, 0)) {
        return;
    }
    WCLiquidGlassChatBottomMenuRefreshVisibleHierarchy(rootView, 0);
}

static void WCLiquidGlassRefreshVisibleChatBottomMenuViews(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) {
            continue;
        }
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            WCLiquidGlassChatBottomMenuRefreshVisibleHierarchy(window, 0);
        }
    }
}

static void WCLiquidGlassScheduleChatBottomMenuHookRetry(void) {
    if (WCLiquidGlassChatBottomMenuHookRetryScheduled ||
        WCLiquidGlassChatBottomMenuHookInstallAttempts >= 10) {
        return;
    }
    WCLiquidGlassChatBottomMenuHookRetryScheduled = YES;
    WCLiquidGlassChatBottomMenuHookInstallAttempts += 1;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        WCLiquidGlassChatBottomMenuHookRetryScheduled = NO;
        WCLiquidGlassInstallChatBottomMenuHooks();
    });
}

void WCLiquidGlassInstallChatBottomMenuHooks(void) {
    BOOL didInstallHook = NO;
    Class inputToolContainerClass = NSClassFromString(@"InputToolContainerView");
    if (!WCLiquidGlassInputToolContainerHookInstalled && inputToolContainerClass) {
        Method layoutMethod = class_getInstanceMethod(inputToolContainerClass,
                                                       @selector(layoutSubviews));
        if (layoutMethod) {
            MSHookMessageEx(inputToolContainerClass,
                            @selector(layoutSubviews),
                            (IMP)&WCLiquidGlassChatBottomMenuLayoutInputToolContainer,
                            (IMP *)&WCLiquidGlassOriginalInputToolContainerLayoutSubviews);
            WCLiquidGlassInputToolContainerHookInstalled =
                WCLiquidGlassOriginalInputToolContainerLayoutSubviews != NULL;
            didInstallHook = WCLiquidGlassInputToolContainerHookInstalled;
        }
    }

    Class selectAttachmentClass = NSClassFromString(@"SelectAttachmentView");
    if (!WCLiquidGlassSelectAttachmentHookInstalled && selectAttachmentClass) {
        Method layoutMethod = class_getInstanceMethod(selectAttachmentClass,
                                                       @selector(layoutSubviews));
        if (layoutMethod) {
            MSHookMessageEx(selectAttachmentClass,
                            @selector(layoutSubviews),
                            (IMP)&WCLiquidGlassChatBottomMenuLayoutSelectAttachment,
                            (IMP *)&WCLiquidGlassOriginalSelectAttachmentLayoutSubviews);
            WCLiquidGlassSelectAttachmentHookInstalled =
                WCLiquidGlassOriginalSelectAttachmentLayoutSubviews != NULL;
            didInstallHook = WCLiquidGlassSelectAttachmentHookInstalled || didInstallHook;
        }
    }

    Class inputToolViewBarClass = NSClassFromString(@"InputToolViewBar");
    if (!WCLiquidGlassInputToolViewBarHookInstalled && inputToolViewBarClass) {
        Method layoutMethod = class_getInstanceMethod(inputToolViewBarClass,
                                                       @selector(layoutSubviews));
        if (layoutMethod) {
            MSHookMessageEx(inputToolViewBarClass,
                            @selector(layoutSubviews),
                            (IMP)&WCLiquidGlassChatBottomMenuLayoutInputToolViewBar,
                            (IMP *)&WCLiquidGlassOriginalInputToolViewBarLayoutSubviews);
            WCLiquidGlassInputToolViewBarHookInstalled =
                WCLiquidGlassOriginalInputToolViewBarLayoutSubviews != NULL;
            didInstallHook = WCLiquidGlassInputToolViewBarHookInstalled || didInstallHook;
        }
    }

    if (!WCLiquidGlassInputToolContainerHookInstalled &&
        !WCLiquidGlassSelectAttachmentHookInstalled &&
        !WCLiquidGlassInputToolViewBarHookInstalled) {
        WCLiquidGlassScheduleChatBottomMenuHookRetry();
        return;
    }
    if (!WCLiquidGlassChatBottomMenuObserverInstalled) {
        WCLiquidGlassChatBottomMenuObserverInstalled = YES;
        [NSNotificationCenter.defaultCenter addObserverForName:WCLiquidGlassPreferencesDidChangeNotification
                                                          object:nil
                                                           queue:NSOperationQueue.mainQueue
                                                      usingBlock:^(__unused NSNotification *notification) {
            WCLiquidGlassRefreshChatBottomMenuViews();
        }];
    }
    if (didInstallHook) {
        WCLiquidGlassRefreshVisibleChatBottomMenuViews();
    }
}
