#import "WCLiquidGlassWCGlassLongPress.h"

#import <CydiaSubstrate.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <math.h>

#import "WCLiquidGlassMenu.h"
#import "WCLiquidGlassPreferences.h"

static const void *WCLiquidGlassWCGlassLongPressStateKey =
    &WCLiquidGlassWCGlassLongPressStateKey;
static void (*WCLiquidGlassOriginalVisualEffectDidMoveToWindow)(UIVisualEffectView *, SEL) = NULL;
static void (*WCLiquidGlassOriginalVisualEffectSetEffect)(UIVisualEffectView *, SEL, UIVisualEffect *) = NULL;
static void (*WCLiquidGlassOriginalApplicationSendEvent)(UIApplication *, SEL, UIEvent *) = NULL;
static void (*WCLiquidGlassOriginalWindowSetHidden)(UIWindow *, SEL, BOOL) = NULL;
static BOOL WCLiquidGlassWCGlassLongPressHooksInstalled = NO;
static __weak UIWindow *WCLiquidGlassWCGlassLongPressTouchWindow = nil;
static CGPoint WCLiquidGlassWCGlassLongPressTouchPoint;
static CFTimeInterval WCLiquidGlassWCGlassLongPressTouchTime = 0.0;

@interface WCLiquidGlassWCGlassLongPressState : NSObject
@property(nonatomic, weak) UIWindow *menuWindow;
@property(nonatomic, weak) UIView *hostView;
@property(nonatomic, strong) UIVisualEffectView *glassContainer;
@property(nonatomic, strong) UIVisualEffectView *morphGlassView;
@property(nonatomic) CGRect sourceFrame;
@property(nonatomic) CGRect targetFrame;
@property(nonatomic) BOOL dismissing;
@end

@implementation WCLiquidGlassWCGlassLongPressState
@end

static SEL WCLiquidGlassWCGlassLongPressMarker(void) {
    return sel_registerName("WCLGApplyLongPressMenuGlass:");
}

static BOOL WCLiquidGlassIsWCGlassLongPressView(UIVisualEffectView *view) {
    return view && objc_getAssociatedObject(view, WCLiquidGlassWCGlassLongPressMarker()) != nil;
}

static UIView *WCLiquidGlassWCGlassLongPressMenuContentView(UIView *hostView) {
    for (UIView *view = hostView.superview; view; view = view.superview) {
        if ([NSStringFromClass(view.class) isEqualToString:@"MMMenuContentView"]) {
            return view;
        }
        if ([view isKindOfClass:UIWindow.class]) {
            break;
        }
    }
    return nil;
}

static CGRect WCLiquidGlassWCGlassLongPressSourceFrame(UIView *menuContentView) {
    CGPoint sourcePoint;
    CFTimeInterval age = CACurrentMediaTime() - WCLiquidGlassWCGlassLongPressTouchTime;
    if (WCLiquidGlassWCGlassLongPressTouchWindow &&
        age >= 0.0 &&
        age <= 2.0 &&
        isfinite(WCLiquidGlassWCGlassLongPressTouchPoint.x) &&
        isfinite(WCLiquidGlassWCGlassLongPressTouchPoint.y)) {
        CGPoint screenPoint =
            [WCLiquidGlassWCGlassLongPressTouchWindow
                convertPoint:WCLiquidGlassWCGlassLongPressTouchPoint
                   toWindow:nil];
        CGPoint menuWindowPoint =
            [menuContentView.window convertPoint:screenPoint fromWindow:nil];
        sourcePoint = [menuContentView convertPoint:menuWindowPoint
                                          fromView:menuContentView.window];
    } else {
        sourcePoint = CGPointMake(CGRectGetMidX(menuContentView.bounds),
                                  CGRectGetMidY(menuContentView.bounds));
    }
    return CGRectMake(sourcePoint.x - 22.0,
                      sourcePoint.y - 22.0,
                      44.0,
                      44.0);
}

static void WCLiquidGlassWCGlassLongPressHideWCGlassViews(UIView *view,
                                                          NSUInteger depth) {
    if (!view || depth > 12) {
        return;
    }
    if ([view isKindOfClass:UIVisualEffectView.class] &&
        WCLiquidGlassIsWCGlassLongPressView((UIVisualEffectView *)view)) {
        view.hidden = YES;
        view.alpha = 0.0;
    }
    for (UIView *subview in view.subviews) {
        WCLiquidGlassWCGlassLongPressHideWCGlassViews(subview, depth + 1);
    }
}

static void WCLiquidGlassWCGlassLongPressApplyTransparentHost(UIView *hostView) {
    hostView.opaque = NO;
    hostView.backgroundColor = UIColor.clearColor;
    hostView.layer.backgroundColor = UIColor.clearColor.CGColor;
    hostView.layer.cornerRadius = 25.0;
    WCLiquidGlassWCGlassLongPressHideWCGlassViews(hostView, 0);
}

static void WCLiquidGlassWCGlassLongPressFinishAppearance(
    WCLiquidGlassWCGlassLongPressState *state) {
    if (!state.hostView.window || state.dismissing) {
        return;
    }
    state.hostView.alpha = 1.0;
    state.morphGlassView.frame = state.targetFrame;
    state.morphGlassView.layer.cornerRadius = 25.0;
}

static void WCLiquidGlassWCGlassLongPressTakeOver(UIVisualEffectView *wcGlassView) {
    UIView *hostView = wcGlassView.superview;
    UIView *menuContentView = WCLiquidGlassWCGlassLongPressMenuContentView(hostView);
    UIWindow *menuWindow = hostView.window;
    if (!hostView ||
        !menuContentView ||
        ![NSStringFromClass(menuWindow.class) isEqualToString:@"MMMenuWindow"] ||
        CGRectIsEmpty(hostView.bounds)) {
        return;
    }

    WCLiquidGlassWCGlassLongPressState *existingState =
        objc_getAssociatedObject(menuWindow, WCLiquidGlassWCGlassLongPressStateKey);
    if (existingState && existingState.hostView == hostView) {
        existingState.morphGlassView.effect = WCLiquidGlassCurrentGlassEffect();
        WCLiquidGlassWCGlassLongPressApplyTransparentHost(hostView);
        return;
    }

    WCLiquidGlassWCGlassLongPressState *state =
        [[WCLiquidGlassWCGlassLongPressState alloc] init];
    state.menuWindow = menuWindow;
    state.hostView = hostView;
    state.sourceFrame = WCLiquidGlassWCGlassLongPressSourceFrame(menuContentView);
    state.targetFrame = [menuContentView convertRect:hostView.bounds
                                            fromView:hostView];

    UIVisualEffectView *glassContainer =
        [[UIVisualEffectView alloc]
            initWithEffect:WCLiquidGlassCurrentGlassContainerEffect()];
    glassContainer.frame = menuContentView.bounds;
    glassContainer.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    glassContainer.userInteractionEnabled = NO;
    glassContainer.opaque = NO;
    glassContainer.backgroundColor = UIColor.clearColor;
    glassContainer.contentView.backgroundColor = UIColor.clearColor;

    UIVisualEffectView *morphGlassView =
        [[UIVisualEffectView alloc] initWithEffect:WCLiquidGlassCurrentGlassEffect()];
    morphGlassView.frame = state.sourceFrame;
    morphGlassView.userInteractionEnabled = NO;
    morphGlassView.opaque = NO;
    morphGlassView.backgroundColor = UIColor.clearColor;
    morphGlassView.contentView.backgroundColor = UIColor.clearColor;
    morphGlassView.clipsToBounds = YES;
    morphGlassView.layer.cornerRadius = 22.0;
    [glassContainer.contentView addSubview:morphGlassView];
    [menuContentView insertSubview:glassContainer atIndex:0];

    state.glassContainer = glassContainer;
    state.morphGlassView = morphGlassView;
    objc_setAssociatedObject(menuWindow,
                             WCLiquidGlassWCGlassLongPressStateKey,
                             state,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    WCLiquidGlassWCGlassLongPressApplyTransparentHost(hostView);
    hostView.alpha = UIAccessibilityIsReduceMotionEnabled() ? 1.0 : 0.0;

    if (UIAccessibilityIsReduceMotionEnabled()) {
        WCLiquidGlassWCGlassLongPressFinishAppearance(state);
        return;
    }

    UIViewPropertyAnimator *animator =
        [[UIViewPropertyAnimator alloc] initWithDuration:0.48
                                           dampingRatio:0.82
                                             animations:^{
        morphGlassView.frame = state.targetFrame;
        morphGlassView.layer.cornerRadius = 25.0;
        hostView.alpha = 1.0;
    }];
    [animator addCompletion:^(__unused UIViewAnimatingPosition position) {
        WCLiquidGlassWCGlassLongPressFinishAppearance(state);
    }];
    [animator startAnimation];
}

static void WCLiquidGlassWCGlassLongPressScheduleTakeOver(
    UIVisualEffectView *wcGlassView) {
    if (!wcGlassView.window || !WCLiquidGlassIsWCGlassLongPressView(wcGlassView)) {
        return;
    }
    __weak UIVisualEffectView *weakView = wcGlassView;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIVisualEffectView *strongView = weakView;
        if (strongView.window && WCLiquidGlassIsWCGlassLongPressView(strongView)) {
            WCLiquidGlassWCGlassLongPressTakeOver(strongView);
        }
    });
}

static void WCLiquidGlassWCGlassLongPressDidMoveToWindow(UIVisualEffectView *self,
                                                         SEL selector) {
    if (WCLiquidGlassOriginalVisualEffectDidMoveToWindow) {
        WCLiquidGlassOriginalVisualEffectDidMoveToWindow(self, selector);
    }
    if (self.window && WCLiquidGlassIsWCGlassLongPressView(self)) {
        self.hidden = YES;
        self.alpha = 0.0;
        WCLiquidGlassWCGlassLongPressScheduleTakeOver(self);
    }
}

static void WCLiquidGlassWCGlassLongPressSetEffect(UIVisualEffectView *self,
                                                   SEL selector,
                                                   UIVisualEffect *effect) {
    if (WCLiquidGlassIsWCGlassLongPressView(self)) {
        self.hidden = YES;
        self.alpha = 0.0;
        WCLiquidGlassWCGlassLongPressScheduleTakeOver(self);
        return;
    }
    if (WCLiquidGlassOriginalVisualEffectSetEffect) {
        WCLiquidGlassOriginalVisualEffectSetEffect(self, selector, effect);
    }
}

static void WCLiquidGlassWCGlassLongPressSendEvent(UIApplication *self,
                                                   SEL selector,
                                                   UIEvent *event) {
    if (event.type == UIEventTypeTouches) {
        for (UITouch *touch in event.allTouches) {
            UIWindow *window = touch.window;
            if ((touch.phase == UITouchPhaseBegan ||
                 touch.phase == UITouchPhaseMoved ||
                 touch.phase == UITouchPhaseStationary) &&
                window &&
                ![NSStringFromClass(window.class) isEqualToString:@"MMMenuWindow"]) {
                WCLiquidGlassWCGlassLongPressTouchWindow = window;
                WCLiquidGlassWCGlassLongPressTouchPoint = [touch locationInView:window];
                WCLiquidGlassWCGlassLongPressTouchTime = CACurrentMediaTime();
            }
        }
    }
    if (WCLiquidGlassOriginalApplicationSendEvent) {
        WCLiquidGlassOriginalApplicationSendEvent(self, selector, event);
    }
}

static void WCLiquidGlassWCGlassLongPressCompleteDismissal(
    WCLiquidGlassWCGlassLongPressState *state) {
    UIWindow *menuWindow = state.menuWindow;
    if (!menuWindow) {
        return;
    }
    objc_setAssociatedObject(menuWindow,
                             WCLiquidGlassWCGlassLongPressStateKey,
                             nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [state.glassContainer removeFromSuperview];
    if (WCLiquidGlassOriginalWindowSetHidden) {
        WCLiquidGlassOriginalWindowSetHidden(menuWindow,
                                             @selector(setHidden:),
                                             YES);
    }
}

static void WCLiquidGlassWCGlassLongPressDismiss(
    WCLiquidGlassWCGlassLongPressState *state) {
    if (state.dismissing) {
        return;
    }
    state.dismissing = YES;
    if (UIAccessibilityIsReduceMotionEnabled() ||
        !state.hostView.window ||
        !state.morphGlassView.window) {
        WCLiquidGlassWCGlassLongPressCompleteDismissal(state);
        return;
    }

    UIViewPropertyAnimator *animator =
        [[UIViewPropertyAnimator alloc] initWithDuration:0.34
                                           dampingRatio:1.0
                                             animations:^{
        state.hostView.alpha = 0.0;
        state.morphGlassView.frame = state.sourceFrame;
        state.morphGlassView.layer.cornerRadius = 22.0;
    }];
    [animator addCompletion:^(__unused UIViewAnimatingPosition position) {
        WCLiquidGlassWCGlassLongPressCompleteDismissal(state);
    }];
    [animator startAnimation];
}

static void WCLiquidGlassWCGlassLongPressWindowSetHidden(UIWindow *self,
                                                         SEL selector,
                                                         BOOL hidden) {
    WCLiquidGlassWCGlassLongPressState *state =
        objc_getAssociatedObject(self, WCLiquidGlassWCGlassLongPressStateKey);
    if (hidden && state) {
        WCLiquidGlassWCGlassLongPressDismiss(state);
        return;
    }
    if (WCLiquidGlassOriginalWindowSetHidden) {
        WCLiquidGlassOriginalWindowSetHidden(self, selector, hidden);
    }
}

static void WCLiquidGlassRefreshVisibleWCGlassLongPressViews(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) {
            continue;
        }
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            WCLiquidGlassWCGlassLongPressState *state =
                objc_getAssociatedObject(window, WCLiquidGlassWCGlassLongPressStateKey);
            if (state) {
                state.morphGlassView.effect = WCLiquidGlassCurrentGlassEffect();
                WCLiquidGlassWCGlassLongPressApplyTransparentHost(state.hostView);
            }
        }
    }
}

void WCLiquidGlassInstallWCGlassLongPressHooks(void) {
    if (WCLiquidGlassWCGlassLongPressHooksInstalled) {
        return;
    }
    WCLiquidGlassWCGlassLongPressHooksInstalled = YES;
    MSHookMessageEx(UIVisualEffectView.class,
                    @selector(didMoveToWindow),
                    (IMP)&WCLiquidGlassWCGlassLongPressDidMoveToWindow,
                    (IMP *)&WCLiquidGlassOriginalVisualEffectDidMoveToWindow);
    MSHookMessageEx(UIVisualEffectView.class,
                    @selector(setEffect:),
                    (IMP)&WCLiquidGlassWCGlassLongPressSetEffect,
                    (IMP *)&WCLiquidGlassOriginalVisualEffectSetEffect);
    MSHookMessageEx(UIApplication.class,
                    @selector(sendEvent:),
                    (IMP)&WCLiquidGlassWCGlassLongPressSendEvent,
                    (IMP *)&WCLiquidGlassOriginalApplicationSendEvent);
    MSHookMessageEx(UIWindow.class,
                    @selector(setHidden:),
                    (IMP)&WCLiquidGlassWCGlassLongPressWindowSetHidden,
                    (IMP *)&WCLiquidGlassOriginalWindowSetHidden);
    [NSNotificationCenter.defaultCenter addObserverForName:WCLiquidGlassPreferencesDidChangeNotification
                                                    object:nil
                                                     queue:NSOperationQueue.mainQueue
                                                usingBlock:^(__unused NSNotification *notification) {
        WCLiquidGlassRefreshVisibleWCGlassLongPressViews();
    }];
}
