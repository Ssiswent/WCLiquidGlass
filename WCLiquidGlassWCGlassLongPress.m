#import "WCLiquidGlassWCGlassLongPress.h"

#import <CydiaSubstrate.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <math.h>

#import "WCLiquidGlassMenu.h"
#import "WCLiquidGlassPreferences.h"

static const void *WCLiquidGlassWCGlassLongPressAnimatedKey =
    &WCLiquidGlassWCGlassLongPressAnimatedKey;
static const void *WCLiquidGlassWCGlassLongPressReplacementKey =
    &WCLiquidGlassWCGlassLongPressReplacementKey;
static const void *WCLiquidGlassWCGlassLongPressHostKey =
    &WCLiquidGlassWCGlassLongPressHostKey;
static const void *WCLiquidGlassWCGlassLongPressSourcePointKey =
    &WCLiquidGlassWCGlassLongPressSourcePointKey;
static void (*WCLiquidGlassOriginalVisualEffectDidMoveToWindow)(UIVisualEffectView *, SEL) = NULL;
static void (*WCLiquidGlassOriginalVisualEffectSetEffect)(UIVisualEffectView *, SEL, UIVisualEffect *) = NULL;
static void (*WCLiquidGlassOriginalApplicationSendEvent)(UIApplication *, SEL, UIEvent *) = NULL;
static void (*WCLiquidGlassOriginalWindowSetHidden)(UIWindow *, SEL, BOOL) = NULL;
static void (*WCLiquidGlassOriginalMenuItemSetHighlighted)(UIControl *, SEL, BOOL) = NULL;
static BOOL WCLiquidGlassWCGlassLongPressHooksInstalled = NO;
static __weak UIWindow *WCLiquidGlassWCGlassLongPressTouchWindow = nil;
static CGPoint WCLiquidGlassWCGlassLongPressTouchPoint;
static CFTimeInterval WCLiquidGlassWCGlassLongPressTouchTime = 0.0;

static SEL WCLiquidGlassWCGlassLongPressMarker(void) {
    return sel_registerName("WCLGApplyLongPressMenuGlass:");
}

static BOOL WCLiquidGlassIsWCGlassLongPressView(UIVisualEffectView *view) {
    return view && objc_getAssociatedObject(view, WCLiquidGlassWCGlassLongPressMarker()) != nil;
}

static BOOL WCLiquidGlassWCGlassLongPressHostMatches(UIVisualEffectView *view) {
    UIView *hostView = view.superview;
    return hostView &&
        ![hostView isKindOfClass:UIWindow.class] &&
        CGRectGetWidth(hostView.bounds) <= 520.0 &&
        CGRectGetHeight(hostView.bounds) <= 760.0 &&
        fabs(CGRectGetWidth(hostView.bounds) - CGRectGetWidth(view.bounds)) <= 4.0 &&
        fabs(CGRectGetHeight(hostView.bounds) - CGRectGetHeight(view.bounds)) <= 4.0;
}

static void WCLiquidGlassClearWCGlassLongPressButtonShadows(UIView *view,
                                                            BOOL insideMenuItem) {
    BOOL isMenuItem = [NSStringFromClass(view.class) isEqualToString:@"MMMenuItemView"];
    BOOL shouldClear = insideMenuItem || isMenuItem;
    if (shouldClear) {
        view.layer.shadowOpacity = 0.0;
        view.layer.shadowRadius = 0.0;
        view.layer.shadowOffset = CGSizeZero;
        view.layer.shadowColor = UIColor.clearColor.CGColor;
    }
    for (UIView *subview in view.subviews) {
        WCLiquidGlassClearWCGlassLongPressButtonShadows(subview, shouldClear);
    }
}

static UIVisualEffectView *WCLiquidGlassWCGlassLongPressReplacement(UIVisualEffectView *view,
                                                                    BOOL create) {
    UIVisualEffectView *replacement =
        objc_getAssociatedObject(view, WCLiquidGlassWCGlassLongPressReplacementKey);
    UIView *hostView = view.superview;
    if (!replacement && create && WCLiquidGlassWCGlassLongPressHostMatches(view)) {
        replacement = [[UIVisualEffectView alloc] initWithEffect:WCLiquidGlassCurrentGlassEffect()];
        replacement.userInteractionEnabled = NO;
        replacement.opaque = NO;
        replacement.backgroundColor = UIColor.clearColor;
        replacement.contentView.backgroundColor = UIColor.clearColor;
        replacement.frame = view.frame;
        replacement.autoresizingMask =
            UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        replacement.clipsToBounds = YES;
        replacement.layer.cornerRadius = view.layer.cornerRadius;
        NSUInteger index = [hostView.subviews indexOfObjectIdenticalTo:view];
        [hostView insertSubview:replacement atIndex:index == NSNotFound ? 0 : index];
        objc_setAssociatedObject(view,
                                 WCLiquidGlassWCGlassLongPressReplacementKey,
                                 replacement,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(hostView,
                                 WCLiquidGlassWCGlassLongPressHostKey,
                                 view,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return replacement;
}

static void WCLiquidGlassApplyWCGlassLongPressMaterial(UIVisualEffectView *view) {
    if (!WCLiquidGlassIsWCGlassLongPressView(view)) {
        return;
    }
    UIVisualEffectView *replacement =
        WCLiquidGlassWCGlassLongPressReplacement(view, YES);
    if (!replacement) {
        return;
    }
    replacement.frame = view.frame;
    replacement.layer.cornerRadius = view.layer.cornerRadius;
    replacement.effect = WCLiquidGlassCurrentGlassEffect();
    view.hidden = YES;
    view.alpha = 0.0;
    UIView *hostView = view.superview;
    hostView.opaque = NO;
    hostView.backgroundColor = UIColor.clearColor;
    hostView.layer.backgroundColor = UIColor.clearColor.CGColor;
    hostView.clipsToBounds = YES;
    hostView.layer.cornerRadius = 25.0;
    replacement.layer.cornerRadius = 25.0;
    WCLiquidGlassClearWCGlassLongPressButtonShadows(hostView, NO);
}

static CGPoint WCLiquidGlassWCGlassLongPressSourcePointInScreen(UIView *hostView) {
    CFTimeInterval age = CACurrentMediaTime() - WCLiquidGlassWCGlassLongPressTouchTime;
    if (WCLiquidGlassWCGlassLongPressTouchWindow &&
        age >= 0.0 &&
        age <= 2.0 &&
        isfinite(WCLiquidGlassWCGlassLongPressTouchPoint.x) &&
        isfinite(WCLiquidGlassWCGlassLongPressTouchPoint.y)) {
        return [WCLiquidGlassWCGlassLongPressTouchWindow
            convertPoint:WCLiquidGlassWCGlassLongPressTouchPoint
               toWindow:nil];
    }
    CGRect frameInScreen = [hostView.window convertRect:[hostView convertRect:hostView.bounds
                                                                       toView:hostView.window]
                                               toWindow:nil];
    return CGPointMake(CGRectGetMidX(frameInScreen), CGRectGetMidY(frameInScreen));
}

static NSArray *WCLiquidGlassWCGlassLongPressMorphPaths(UIView *view,
                                                        CGPoint sourcePointInScreen,
                                                        BOOL reversed) {
    CGPoint pointInWindow = [view.window convertPoint:sourcePointInScreen fromWindow:nil];
    CGPoint sourcePoint = [view convertPoint:pointInWindow fromView:view.window];
    CGRect finalBounds = view.bounds;
    CGFloat diameter = MIN(44.0, MIN(CGRectGetWidth(finalBounds), CGRectGetHeight(finalBounds)));
    CGRect sourceRect = CGRectMake(sourcePoint.x - diameter * 0.5,
                                   sourcePoint.y - diameter * 0.5,
                                   diameter,
                                   diameter);
    NSArray<NSNumber *> *progress = @[@0.0, @0.10, @0.34, @0.68, @0.92, @1.0];
    NSMutableArray *paths = [NSMutableArray arrayWithCapacity:progress.count];
    CGFloat finalRadius = view.layer.cornerRadius > 0.0 ? view.layer.cornerRadius : 25.0;
    for (NSNumber *value in progress) {
        CGFloat amount = value.doubleValue;
        CGRect rect = CGRectMake(CGRectGetMinX(sourceRect) +
                                     (CGRectGetMinX(finalBounds) - CGRectGetMinX(sourceRect)) * amount,
                                 CGRectGetMinY(sourceRect) +
                                     (CGRectGetMinY(finalBounds) - CGRectGetMinY(sourceRect)) * amount,
                                 CGRectGetWidth(sourceRect) +
                                     (CGRectGetWidth(finalBounds) - CGRectGetWidth(sourceRect)) * amount,
                                 CGRectGetHeight(sourceRect) +
                                     (CGRectGetHeight(finalBounds) - CGRectGetHeight(sourceRect)) * amount);
        CGFloat radius = diameter * 0.5 + (finalRadius - diameter * 0.5) * amount;
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:rect
                                                        cornerRadius:MAX(0.0, radius)];
        [paths addObject:(__bridge id)path.CGPath];
    }
    return reversed ? [[paths reverseObjectEnumerator] allObjects] : paths;
}

static void WCLiquidGlassAnimateWCGlassLongPressContent(UIVisualEffectView *glassView,
                                                        CFTimeInterval beginTime,
                                                        CFTimeInterval duration) {
    UIView *hostView = glassView.superview;
    if (!hostView ||
        [hostView isKindOfClass:UIWindow.class] ||
        CGRectGetWidth(hostView.bounds) > 520.0 ||
        CGRectGetHeight(hostView.bounds) > 760.0 ||
        fabs(CGRectGetWidth(hostView.bounds) - CGRectGetWidth(glassView.bounds)) > 4.0 ||
        fabs(CGRectGetHeight(hostView.bounds) - CGRectGetHeight(glassView.bounds)) > 4.0) {
        return;
    }
    for (UIView *subview in hostView.subviews) {
        if (subview == glassView ||
            subview == WCLiquidGlassWCGlassLongPressReplacement(glassView, NO) ||
            subview.hidden ||
            subview.alpha <= 0.01) {
            continue;
        }
        CAKeyframeAnimation *contentAnimation = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
        contentAnimation.values = @[@0.0, @0.0, @0.72, @1.0];
        contentAnimation.keyTimes = @[@0.0, @0.22, @0.64, @1.0];
        contentAnimation.duration = duration;
        contentAnimation.beginTime = beginTime;
        contentAnimation.fillMode = kCAFillModeBackwards;
        contentAnimation.removedOnCompletion = YES;
        [subview.layer addAnimation:contentAnimation
                            forKey:@"WCLiquidGlass.WCGlassLongPress.ContentReveal"];
    }
}

static void WCLiquidGlassAnimateWCGlassLongPressAppearance(UIVisualEffectView *view) {
    if (!view.window ||
        UIAccessibilityIsReduceMotionEnabled() ||
        MIN(CGRectGetWidth(view.bounds), CGRectGetHeight(view.bounds)) < 24.0 ||
        MAX(CGRectGetWidth(view.bounds), CGRectGetHeight(view.bounds)) < 56.0) {
        return;
    }
    UIView *hostView = view.superview;
    CGPoint sourcePoint = WCLiquidGlassWCGlassLongPressSourcePointInScreen(hostView);
    objc_setAssociatedObject(hostView,
                             WCLiquidGlassWCGlassLongPressSourcePointKey,
                             [NSValue valueWithCGPoint:sourcePoint],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSArray *paths = WCLiquidGlassWCGlassLongPressMorphPaths(hostView, sourcePoint, NO);
    CAShapeLayer *maskLayer = [CAShapeLayer layer];
    maskLayer.frame = hostView.bounds;
    maskLayer.fillColor = UIColor.blackColor.CGColor;
    maskLayer.path = (__bridge CGPathRef)paths.lastObject;
    hostView.layer.mask = maskLayer;
    CAKeyframeAnimation *pathAnimation = [CAKeyframeAnimation animationWithKeyPath:@"path"];
    pathAnimation.values = paths;
    pathAnimation.keyTimes = @[@0.0, @0.10, @0.32, @0.62, @0.84, @1.0];
    pathAnimation.timingFunctions = @[
        [CAMediaTimingFunction functionWithControlPoints:0.16 :0.70 :0.22 :1.0],
        [CAMediaTimingFunction functionWithControlPoints:0.16 :0.86 :0.24 :1.0],
        [CAMediaTimingFunction functionWithControlPoints:0.20 :0.82 :0.28 :1.0],
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut],
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut]
    ];
    CFTimeInterval beginTime = CACurrentMediaTime();
    CFTimeInterval duration = 0.40;
    pathAnimation.duration = duration;
    pathAnimation.beginTime = beginTime;
    pathAnimation.fillMode = kCAFillModeBackwards;
    pathAnimation.removedOnCompletion = YES;
    [maskLayer addAnimation:pathAnimation
                     forKey:@"WCLiquidGlass.WCGlassLongPress.HostMorph"];
    WCLiquidGlassAnimateWCGlassLongPressContent(view, beginTime + 0.035, duration - 0.035);
    __weak UIView *weakHostView = hostView;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        UIView *strongHostView = weakHostView;
        if (strongHostView.layer.mask == maskLayer) {
            strongHostView.layer.mask = nil;
        }
    });
}

static void WCLiquidGlassScheduleWCGlassLongPressAppearance(UIVisualEffectView *view) {
    if (!view.window || !WCLiquidGlassIsWCGlassLongPressView(view)) {
        return;
    }
    if ([objc_getAssociatedObject(view, WCLiquidGlassWCGlassLongPressAnimatedKey) boolValue]) {
        return;
    }
    objc_setAssociatedObject(view,
                             WCLiquidGlassWCGlassLongPressAnimatedKey,
                             @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UIVisualEffectView *weakView = view;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIVisualEffectView *strongView = weakView;
        if (!strongView.window || !WCLiquidGlassIsWCGlassLongPressView(strongView)) {
            return;
        }
        WCLiquidGlassApplyWCGlassLongPressMaterial(strongView);
        WCLiquidGlassAnimateWCGlassLongPressAppearance(strongView);
        __weak UIView *weakHostView = strongView.superview;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.55 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            UIView *hostView = weakHostView;
            if (hostView.window) {
                WCLiquidGlassClearWCGlassLongPressButtonShadows(hostView, NO);
            }
        });
    });
}

static void WCLiquidGlassWCGlassLongPressDidMoveToWindow(UIVisualEffectView *self, SEL selector) {
    if (WCLiquidGlassOriginalVisualEffectDidMoveToWindow) {
        WCLiquidGlassOriginalVisualEffectDidMoveToWindow(self, selector);
    }
    if (!self.window) {
        objc_setAssociatedObject(self,
                                 WCLiquidGlassWCGlassLongPressAnimatedKey,
                                 nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    if (WCLiquidGlassIsWCGlassLongPressView(self)) {
        WCLiquidGlassApplyWCGlassLongPressMaterial(self);
        WCLiquidGlassScheduleWCGlassLongPressAppearance(self);
    }
}

static void WCLiquidGlassWCGlassLongPressSetEffect(UIVisualEffectView *self,
                                                   SEL selector,
                                                   UIVisualEffect *effect) {
    BOOL isWCGlassLongPressView = WCLiquidGlassIsWCGlassLongPressView(self);
    if (isWCGlassLongPressView) {
        WCLiquidGlassApplyWCGlassLongPressMaterial(self);
        if (!WCLiquidGlassWCGlassLongPressReplacement(self, NO) &&
            WCLiquidGlassOriginalVisualEffectSetEffect) {
            WCLiquidGlassOriginalVisualEffectSetEffect(self, selector, effect);
        }
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

static UIView *WCLiquidGlassWCGlassLongPressHostInView(UIView *view,
                                                       NSUInteger depth) {
    if (!view || depth > 24) {
        return nil;
    }
    if (objc_getAssociatedObject(view, WCLiquidGlassWCGlassLongPressHostKey)) {
        return view;
    }
    for (UIView *subview in view.subviews) {
        UIView *hostView =
            WCLiquidGlassWCGlassLongPressHostInView(subview, depth + 1);
        if (hostView) {
            return hostView;
        }
    }
    return nil;
}

static UIWindow *WCLiquidGlassWCGlassLongPressDismissalWindow(UIWindow *menuWindow) {
    UIWindowScene *scene = menuWindow.windowScene;
    UIWindow *sourceWindow = WCLiquidGlassWCGlassLongPressTouchWindow;
    if (sourceWindow &&
        sourceWindow.windowScene == scene &&
        !sourceWindow.hidden &&
        sourceWindow.alpha > 0.01) {
        return sourceWindow;
    }
    for (UIWindow *window in [scene.windows reverseObjectEnumerator]) {
        if (window != menuWindow &&
            !window.hidden &&
            window.alpha > 0.01 &&
            ![NSStringFromClass(window.class) isEqualToString:@"MMMenuWindow"]) {
            return window;
        }
    }
    return nil;
}

static void WCLiquidGlassAnimateWCGlassLongPressDismissal(UIWindow *menuWindow) {
    UIView *hostView = WCLiquidGlassWCGlassLongPressHostInView(menuWindow, 0);
    NSValue *sourceValue =
        objc_getAssociatedObject(hostView, WCLiquidGlassWCGlassLongPressSourcePointKey);
    UIWindow *targetWindow =
        WCLiquidGlassWCGlassLongPressDismissalWindow(menuWindow);
    if (!hostView ||
        !sourceValue ||
        !targetWindow ||
        UIAccessibilityIsReduceMotionEnabled()) {
        return;
    }
    UIView *snapshot = [hostView snapshotViewAfterScreenUpdates:NO];
    if (!snapshot) {
        return;
    }
    CGRect frameInScreen = [menuWindow convertRect:[hostView convertRect:hostView.bounds
                                                                   toView:menuWindow]
                                          toWindow:nil];
    snapshot.frame = [targetWindow convertRect:frameInScreen fromWindow:nil];
    snapshot.userInteractionEnabled = NO;
    [targetWindow addSubview:snapshot];

    NSArray *paths =
        WCLiquidGlassWCGlassLongPressMorphPaths(snapshot,
                                                sourceValue.CGPointValue,
                                                YES);
    CAShapeLayer *maskLayer = [CAShapeLayer layer];
    maskLayer.frame = snapshot.bounds;
    maskLayer.fillColor = UIColor.blackColor.CGColor;
    maskLayer.path = (__bridge CGPathRef)paths.lastObject;
    snapshot.layer.mask = maskLayer;
    CAKeyframeAnimation *pathAnimation = [CAKeyframeAnimation animationWithKeyPath:@"path"];
    pathAnimation.values = paths;
    pathAnimation.keyTimes = @[@0.0, @0.16, @0.38, @0.68, @0.90, @1.0];
    pathAnimation.duration = 0.26;
    pathAnimation.timingFunction =
        [CAMediaTimingFunction functionWithControlPoints:0.34 :0.0 :0.76 :0.22];
    [maskLayer addAnimation:pathAnimation
                     forKey:@"WCLiquidGlass.WCGlassLongPress.HostDismiss"];
    CABasicAnimation *opacityAnimation = [CABasicAnimation animationWithKeyPath:@"opacity"];
    opacityAnimation.fromValue = @1.0;
    opacityAnimation.toValue = @0.0;
    opacityAnimation.duration = 0.26;
    opacityAnimation.timingFunction =
        [CAMediaTimingFunction functionWithControlPoints:0.40 :0.0 :0.72 :0.24];
    snapshot.layer.opacity = 0.0;
    [snapshot.layer addAnimation:opacityAnimation
                          forKey:@"WCLiquidGlass.WCGlassLongPress.DismissOpacity"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.26 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [snapshot removeFromSuperview];
    });
}

static void WCLiquidGlassWCGlassLongPressWindowSetHidden(UIWindow *self,
                                                         SEL selector,
                                                         BOOL hidden) {
    if (hidden &&
        [NSStringFromClass(self.class) isEqualToString:@"MMMenuWindow"]) {
        WCLiquidGlassAnimateWCGlassLongPressDismissal(self);
    }
    if (WCLiquidGlassOriginalWindowSetHidden) {
        WCLiquidGlassOriginalWindowSetHidden(self, selector, hidden);
    }
}

static BOOL WCLiquidGlassWCGlassLongPressViewBelongsToHost(UIView *view) {
    for (NSUInteger depth = 0; view && depth < 12; depth += 1, view = view.superview) {
        if (objc_getAssociatedObject(view, WCLiquidGlassWCGlassLongPressHostKey)) {
            return YES;
        }
    }
    return NO;
}

static void WCLiquidGlassWCGlassLongPressMenuItemSetHighlighted(UIControl *self,
                                                                SEL selector,
                                                                BOOL highlighted) {
    if (WCLiquidGlassOriginalMenuItemSetHighlighted) {
        WCLiquidGlassOriginalMenuItemSetHighlighted(self, selector, highlighted);
    }
    if (WCLiquidGlassWCGlassLongPressViewBelongsToHost(self)) {
        WCLiquidGlassClearWCGlassLongPressButtonShadows(self, YES);
    }
}

static void WCLiquidGlassRefreshWCGlassLongPressViewsInView(UIView *view, NSUInteger depth) {
    if (!view || depth > 48) {
        return;
    }
    if ([view isKindOfClass:UIVisualEffectView.class] &&
        WCLiquidGlassIsWCGlassLongPressView((UIVisualEffectView *)view)) {
        WCLiquidGlassApplyWCGlassLongPressMaterial((UIVisualEffectView *)view);
    }
    for (UIView *subview in view.subviews) {
        WCLiquidGlassRefreshWCGlassLongPressViewsInView(subview, depth + 1);
    }
}

static void WCLiquidGlassRefreshVisibleWCGlassLongPressViews(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) {
            continue;
        }
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            WCLiquidGlassRefreshWCGlassLongPressViewsInView(window, 0);
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
    Class menuItemClass = NSClassFromString(@"MMMenuItemView");
    if (menuItemClass) {
        MSHookMessageEx(menuItemClass,
                        @selector(setHighlighted:),
                        (IMP)&WCLiquidGlassWCGlassLongPressMenuItemSetHighlighted,
                        (IMP *)&WCLiquidGlassOriginalMenuItemSetHighlighted);
    }
    [NSNotificationCenter.defaultCenter addObserverForName:WCLiquidGlassPreferencesDidChangeNotification
                                                    object:nil
                                                     queue:NSOperationQueue.mainQueue
                                                usingBlock:^(__unused NSNotification *notification) {
        WCLiquidGlassRefreshVisibleWCGlassLongPressViews();
    }];
}
