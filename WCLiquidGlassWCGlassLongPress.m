#import "WCLiquidGlassWCGlassLongPress.h"

#import <CydiaSubstrate.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "WCLiquidGlassMenu.h"
#import "WCLiquidGlassPreferences.h"

static const void *WCLiquidGlassWCGlassLongPressAnimatedKey =
    &WCLiquidGlassWCGlassLongPressAnimatedKey;
static const void *WCLiquidGlassWCGlassLongPressContentKey =
    &WCLiquidGlassWCGlassLongPressContentKey;
static const void *WCLiquidGlassWCGlassLongPressHostKey =
    &WCLiquidGlassWCGlassLongPressHostKey;
static const void *WCLiquidGlassWCGlassLongPressMaskKey =
    &WCLiquidGlassWCGlassLongPressMaskKey;
static const void *WCLiquidGlassWCGlassLongPressSourcePointKey =
    &WCLiquidGlassWCGlassLongPressSourcePointKey;
static const void *WCLiquidGlassWCGlassLongPressDismissalKey =
    &WCLiquidGlassWCGlassLongPressDismissalKey;
static void (*WCLiquidGlassOriginalVisualEffectDidMoveToWindow)(UIVisualEffectView *, SEL) = NULL;
static void (*WCLiquidGlassOriginalVisualEffectLayoutSubviews)(UIVisualEffectView *, SEL) = NULL;
static void (*WCLiquidGlassOriginalVisualEffectSetEffect)(UIVisualEffectView *, SEL, UIVisualEffect *) = NULL;
static void (*WCLiquidGlassOriginalApplicationSendEvent)(UIApplication *, SEL, UIEvent *) = NULL;
static void (*WCLiquidGlassOriginalViewRemoveFromSuperview)(UIView *, SEL) = NULL;
static void (*WCLiquidGlassOriginalViewSetBackgroundColor)(UIView *, SEL, UIColor *) = NULL;
static void (*WCLiquidGlassOriginalViewSetOverrideUserInterfaceStyle)(UIView *, SEL, UIUserInterfaceStyle) = NULL;
static void (*WCLiquidGlassOriginalButtonSetHighlighted)(UIButton *, SEL, BOOL) = NULL;
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

static BOOL WCLiquidGlassIsWCGlassLongPressHost(UIView *view) {
    return view && [objc_getAssociatedObject(view, WCLiquidGlassWCGlassLongPressHostKey) boolValue];
}

static BOOL WCLiquidGlassWCGlassLongPressHostMatches(UIVisualEffectView *glassView) {
    UIView *hostView = glassView.superview;
    return hostView &&
        ![hostView isKindOfClass:UIWindow.class] &&
        CGRectGetWidth(hostView.bounds) <= 520.0 &&
        CGRectGetHeight(hostView.bounds) <= 760.0 &&
        fabs(CGRectGetWidth(hostView.bounds) - CGRectGetWidth(glassView.bounds)) <= 4.0 &&
        fabs(CGRectGetHeight(hostView.bounds) - CGRectGetHeight(glassView.bounds)) <= 4.0;
}

static UIVisualEffectView *WCLiquidGlassWCGlassLongPressGlassInHost(UIView *hostView) {
    for (UIView *subview in hostView.subviews) {
        if ([subview isKindOfClass:UIVisualEffectView.class] &&
            WCLiquidGlassIsWCGlassLongPressView((UIVisualEffectView *)subview)) {
            return (UIVisualEffectView *)subview;
        }
    }
    return nil;
}

static void WCLiquidGlassRemoveWCGlassLongPressButtonShadows(UIView *view, BOOL insideButton) {
    BOOL isButton = [view isKindOfClass:UIButton.class];
    BOOL shouldClearShadow = insideButton || isButton;
    if (shouldClearShadow) {
        view.layer.shadowOpacity = 0.0;
        view.layer.shadowRadius = 0.0;
        view.layer.shadowOffset = CGSizeZero;
        view.layer.shadowColor = UIColor.clearColor.CGColor;
    }
    if (isButton) {
        UIButton *button = (UIButton *)view;
        SEL adjustsSelector = sel_registerName("setAdjustsImageWhenHighlighted:");
        SEL touchSelector = sel_registerName("setShowsTouchWhenHighlighted:");
        if ([button respondsToSelector:adjustsSelector]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(button, adjustsSelector, NO);
        }
        if ([button respondsToSelector:touchSelector]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(button, touchSelector, NO);
        }
    }
    for (UIView *subview in view.subviews) {
        WCLiquidGlassRemoveWCGlassLongPressButtonShadows(subview, shouldClearShadow);
    }
}

static void WCLiquidGlassMakeWCGlassLongPressViewTransparent(UIVisualEffectView *view) {
    if (!view) {
        return;
    }
    UIView *contentView = view.contentView;
    objc_setAssociatedObject(contentView,
                             WCLiquidGlassWCGlassLongPressContentKey,
                             @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    view.opaque = NO;
    view.backgroundColor = UIColor.clearColor;
    contentView.backgroundColor = UIColor.clearColor;
    view.layer.backgroundColor = UIColor.clearColor.CGColor;
    view.overrideUserInterfaceStyle = UIUserInterfaceStyleUnspecified;
    contentView.overrideUserInterfaceStyle = UIUserInterfaceStyleUnspecified;
    if (WCLiquidGlassWCGlassLongPressHostMatches(view)) {
        UIView *hostView = view.superview;
        objc_setAssociatedObject(hostView,
                                 WCLiquidGlassWCGlassLongPressHostKey,
                                 @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        hostView.opaque = NO;
        hostView.backgroundColor = UIColor.clearColor;
        hostView.layer.backgroundColor = UIColor.clearColor.CGColor;
    }
}

static void WCLiquidGlassPrepareWCGlassLongPressButtons(UIVisualEffectView *view) {
    if (WCLiquidGlassWCGlassLongPressHostMatches(view)) {
        WCLiquidGlassRemoveWCGlassLongPressButtonShadows(view.superview, NO);
    }
}

static void WCLiquidGlassApplyWCGlassLongPressMaterial(UIVisualEffectView *view) {
    if (!WCLiquidGlassIsWCGlassLongPressView(view)) {
        return;
    }
    UIVisualEffect *effect = WCLiquidGlassCurrentGlassEffect();
    if (WCLiquidGlassOriginalVisualEffectSetEffect) {
        WCLiquidGlassOriginalVisualEffectSetEffect(view, @selector(setEffect:), effect);
    } else {
        view.effect = effect;
    }
    WCLiquidGlassMakeWCGlassLongPressViewTransparent(view);
}

static CGPoint WCLiquidGlassWCGlassLongPressSourcePointInWindow(UIVisualEffectView *view) {
    UIWindow *window = view.window;
    CFTimeInterval age = CACurrentMediaTime() - WCLiquidGlassWCGlassLongPressTouchTime;
    if (window &&
        WCLiquidGlassWCGlassLongPressTouchWindow == window &&
        age >= 0.0 &&
        age <= 2.0 &&
        isfinite(WCLiquidGlassWCGlassLongPressTouchPoint.x) &&
        isfinite(WCLiquidGlassWCGlassLongPressTouchPoint.y)) {
        return WCLiquidGlassWCGlassLongPressTouchPoint;
    }
    CGRect frameInWindow = [view convertRect:view.bounds toView:window];
    CGFloat fallbackY = CGRectGetMidY(frameInWindow) <= CGRectGetMidY(window.bounds)
        ? CGRectGetMaxY(frameInWindow)
        : CGRectGetMinY(frameInWindow);
    return CGPointMake(CGRectGetMidX(frameInWindow), fallbackY);
}

static CGPoint WCLiquidGlassWCGlassLongPressClampedSourcePoint(UIView *view,
                                                               CGPoint sourcePointInWindow,
                                                               CGFloat diameter) {
    CGPoint point = [view convertPoint:sourcePointInWindow fromView:view.window];
    CGRect bounds = view.bounds;
    CGFloat radius = diameter * 0.5;
    CGFloat minX = CGRectGetMinX(bounds) + radius;
    CGFloat maxX = CGRectGetMaxX(bounds) - radius;
    CGFloat minY = CGRectGetMinY(bounds) + radius;
    CGFloat maxY = CGRectGetMaxY(bounds) - radius;
    point.x = MIN(MAX(point.x, minX), MAX(minX, maxX));
    point.y = MIN(MAX(point.y, minY), MAX(minY, maxY));
    return point;
}

static CGRect WCLiquidGlassWCGlassLongPressMorphRect(CGRect finalBounds,
                                                     CGPoint sourcePoint,
                                                     CGFloat diameter,
                                                     CGFloat widthProgress,
                                                     CGFloat heightProgress) {
    CGRect initialRect = CGRectMake(sourcePoint.x - diameter * 0.5,
                                    sourcePoint.y - diameter * 0.5,
                                    diameter,
                                    diameter);
    CGFloat minX = CGRectGetMinX(initialRect) +
        (CGRectGetMinX(finalBounds) - CGRectGetMinX(initialRect)) * widthProgress;
    CGFloat maxX = CGRectGetMaxX(initialRect) +
        (CGRectGetMaxX(finalBounds) - CGRectGetMaxX(initialRect)) * widthProgress;
    CGFloat minY = CGRectGetMinY(initialRect) +
        (CGRectGetMinY(finalBounds) - CGRectGetMinY(initialRect)) * heightProgress;
    CGFloat maxY = CGRectGetMaxY(initialRect) +
        (CGRectGetMaxY(finalBounds) - CGRectGetMaxY(initialRect)) * heightProgress;
    return CGRectMake(minX, minY, MAX(1.0, maxX - minX), MAX(1.0, maxY - minY));
}

static NSArray *WCLiquidGlassWCGlassLongPressMorphPaths(UIView *view,
                                                        CGPoint sourcePointInWindow,
                                                        BOOL reversed) {
    CGRect finalBounds = view.bounds;
    CGFloat diameter = MIN(44.0, MIN(CGRectGetWidth(finalBounds), CGRectGetHeight(finalBounds)));
    CGPoint sourcePoint = WCLiquidGlassWCGlassLongPressClampedSourcePoint(view,
                                                                         sourcePointInWindow,
                                                                         diameter);
    CGFloat finalRadius = view.layer.cornerRadius;
    if (finalRadius <= 0.0) {
        finalRadius = MIN(25.0, MIN(CGRectGetWidth(finalBounds), CGRectGetHeight(finalBounds)) * 0.5);
    }
    NSArray<NSNumber *> *widthProgress = @[@0.0, @0.18, @0.58, @0.91, @1.015, @1.0];
    NSArray<NSNumber *> *heightProgress = @[@0.0, @0.04, @0.22, @0.68, @1.01, @1.0];
    NSMutableArray *paths = [NSMutableArray arrayWithCapacity:widthProgress.count];
    for (NSUInteger index = 0; index < widthProgress.count; index += 1) {
        CGFloat widthValue = widthProgress[index].doubleValue;
        CGFloat heightValue = heightProgress[index].doubleValue;
        CGRect rect = WCLiquidGlassWCGlassLongPressMorphRect(finalBounds,
                                                             sourcePoint,
                                                             diameter,
                                                             widthValue,
                                                             heightValue);
        CGFloat progress = MIN(1.0, MAX(widthValue, heightValue));
        CGFloat radius = diameter * 0.5 + (finalRadius - diameter * 0.5) * progress;
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:rect
                                                        cornerRadius:MAX(0.0, radius)];
        [paths addObject:(__bridge id)path.CGPath];
    }
    return reversed ? [[paths reverseObjectEnumerator] allObjects] : paths;
}

static UIView *WCLiquidGlassWCGlassLongPressMorphView(UIVisualEffectView *glassView) {
    UIView *hostView = glassView.superview;
    if (WCLiquidGlassWCGlassLongPressHostMatches(glassView) && !hostView.layer.mask) {
        return hostView;
    }
    return glassView;
}

static void WCLiquidGlassAnimateWCGlassLongPressContent(UIVisualEffectView *glassView,
                                                        CFTimeInterval beginTime,
                                                        CFTimeInterval duration) {
    if (!WCLiquidGlassWCGlassLongPressHostMatches(glassView)) {
        return;
    }
    UIView *hostView = glassView.superview;
    for (UIView *subview in hostView.subviews) {
        if (subview == glassView || subview.hidden || subview.alpha <= 0.01) {
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

static void WCLiquidGlassAnimateWCGlassLongPressMask(UIView *view,
                                                     UIVisualEffectView *glassView,
                                                     CGPoint sourcePointInWindow,
                                                     BOOL reversed,
                                                     CFTimeInterval duration) {
    NSArray *paths = WCLiquidGlassWCGlassLongPressMorphPaths(view,
                                                             sourcePointInWindow,
                                                             reversed);
    CAShapeLayer *maskLayer = [CAShapeLayer layer];
    maskLayer.frame = view.bounds;
    maskLayer.fillColor = UIColor.blackColor.CGColor;
    maskLayer.path = (__bridge CGPathRef)paths.lastObject;
    view.layer.mask = maskLayer;
    objc_setAssociatedObject(view,
                             WCLiquidGlassWCGlassLongPressMaskKey,
                             maskLayer,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    CAKeyframeAnimation *pathAnimation = [CAKeyframeAnimation animationWithKeyPath:@"path"];
    pathAnimation.values = paths;
    pathAnimation.keyTimes = @[@0.0, @0.12, @0.34, @0.64, @0.84, @1.0];
    pathAnimation.timingFunctions = @[
        [CAMediaTimingFunction functionWithControlPoints:0.16 :0.72 :0.22 :1.0],
        [CAMediaTimingFunction functionWithControlPoints:0.18 :0.88 :0.24 :1.0],
        [CAMediaTimingFunction functionWithControlPoints:0.20 :0.84 :0.28 :1.0],
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut],
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut]
    ];
    pathAnimation.duration = duration;
    pathAnimation.removedOnCompletion = YES;
    [maskLayer addAnimation:pathAnimation
                     forKey:@"WCLiquidGlass.WCGlassLongPress.ShapeMorph"];

    if (!reversed) {
        __weak UIView *weakView = view;
        __weak UIVisualEffectView *weakGlassView = glassView;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            UIView *strongView = weakView;
            if (strongView &&
                objc_getAssociatedObject(strongView, WCLiquidGlassWCGlassLongPressMaskKey) == maskLayer) {
                strongView.layer.mask = nil;
                objc_setAssociatedObject(strongView,
                                         WCLiquidGlassWCGlassLongPressMaskKey,
                                         nil,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                WCLiquidGlassMakeWCGlassLongPressViewTransparent(weakGlassView);
            }
        });
    }
}

static void WCLiquidGlassAnimateWCGlassLongPressAppearance(UIVisualEffectView *view) {
    if (!view.window ||
        UIAccessibilityIsReduceMotionEnabled() ||
        MIN(CGRectGetWidth(view.bounds), CGRectGetHeight(view.bounds)) < 24.0 ||
        MAX(CGRectGetWidth(view.bounds), CGRectGetHeight(view.bounds)) < 56.0) {
        return;
    }
    CGPoint sourcePointInWindow = WCLiquidGlassWCGlassLongPressSourcePointInWindow(view);
    objc_setAssociatedObject(view,
                             WCLiquidGlassWCGlassLongPressSourcePointKey,
                             [NSValue valueWithCGPoint:sourcePointInWindow],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIView *morphView = WCLiquidGlassWCGlassLongPressMorphView(view);
    CFTimeInterval duration = 0.38;
    WCLiquidGlassAnimateWCGlassLongPressMask(morphView,
                                            view,
                                            sourcePointInWindow,
                                            NO,
                                            duration);
    WCLiquidGlassAnimateWCGlassLongPressContent(view,
                                                CACurrentMediaTime() + 0.025,
                                                duration - 0.025);
}

static void WCLiquidGlassAnimateWCGlassLongPressDismissal(UIView *hostView,
                                                          UIVisualEffectView *glassView) {
    if (!hostView.window ||
        UIAccessibilityIsReduceMotionEnabled() ||
        [objc_getAssociatedObject(hostView, WCLiquidGlassWCGlassLongPressDismissalKey) boolValue]) {
        return;
    }
    NSValue *sourceValue = objc_getAssociatedObject(glassView,
                                                     WCLiquidGlassWCGlassLongPressSourcePointKey);
    if (!sourceValue) {
        return;
    }
    UIView *snapshot = [hostView snapshotViewAfterScreenUpdates:NO];
    if (!snapshot) {
        return;
    }
    objc_setAssociatedObject(hostView,
                             WCLiquidGlassWCGlassLongPressDismissalKey,
                             @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIWindow *window = hostView.window;
    snapshot.userInteractionEnabled = NO;
    snapshot.frame = [hostView convertRect:hostView.bounds toView:window];
    [window addSubview:snapshot];
    CFTimeInterval duration = 0.30;
    WCLiquidGlassAnimateWCGlassLongPressMask(snapshot,
                                            glassView,
                                            sourceValue.CGPointValue,
                                            YES,
                                            duration);
    CABasicAnimation *opacityAnimation = [CABasicAnimation animationWithKeyPath:@"opacity"];
    opacityAnimation.fromValue = @1.0;
    opacityAnimation.toValue = @0.12;
    opacityAnimation.duration = duration;
    opacityAnimation.timingFunction =
        [CAMediaTimingFunction functionWithControlPoints:0.42 :0.0 :0.72 :0.28];
    snapshot.layer.opacity = 0.0;
    [snapshot.layer addAnimation:opacityAnimation
                          forKey:@"WCLiquidGlass.WCGlassLongPress.ContentDismiss"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [snapshot removeFromSuperview];
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
        WCLiquidGlassPrepareWCGlassLongPressButtons(strongView);
        objc_setAssociatedObject(strongView.superview,
                                 WCLiquidGlassWCGlassLongPressDismissalKey,
                                 nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        WCLiquidGlassAnimateWCGlassLongPressAppearance(strongView);
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

static void WCLiquidGlassWCGlassLongPressLayoutSubviews(UIVisualEffectView *self, SEL selector) {
    if (WCLiquidGlassOriginalVisualEffectLayoutSubviews) {
        WCLiquidGlassOriginalVisualEffectLayoutSubviews(self, selector);
    }
    if (WCLiquidGlassIsWCGlassLongPressView(self)) {
        WCLiquidGlassMakeWCGlassLongPressViewTransparent(self);
    }
}

static void WCLiquidGlassWCGlassLongPressSetEffect(UIVisualEffectView *self,
                                                   SEL selector,
                                                   UIVisualEffect *effect) {
    BOOL isWCGlassLongPressView = WCLiquidGlassIsWCGlassLongPressView(self);
    UIVisualEffect *resolvedEffect = isWCGlassLongPressView ? WCLiquidGlassCurrentGlassEffect() : effect;
    if (WCLiquidGlassOriginalVisualEffectSetEffect) {
        WCLiquidGlassOriginalVisualEffectSetEffect(self, selector, resolvedEffect);
    }
    if (isWCGlassLongPressView) {
        WCLiquidGlassMakeWCGlassLongPressViewTransparent(self);
    }
}

static void WCLiquidGlassWCGlassLongPressSendEvent(UIApplication *self,
                                                   SEL selector,
                                                   UIEvent *event) {
    if (event.type == UIEventTypeTouches) {
        for (UITouch *touch in event.allTouches) {
            if (touch.phase == UITouchPhaseBegan ||
                touch.phase == UITouchPhaseMoved ||
                touch.phase == UITouchPhaseStationary) {
                UIWindow *window = touch.window;
                if (window) {
                    WCLiquidGlassWCGlassLongPressTouchWindow = window;
                    WCLiquidGlassWCGlassLongPressTouchPoint = [touch locationInView:window];
                    WCLiquidGlassWCGlassLongPressTouchTime = CACurrentMediaTime();
                }
            }
        }
    }
    if (WCLiquidGlassOriginalApplicationSendEvent) {
        WCLiquidGlassOriginalApplicationSendEvent(self, selector, event);
    }
}

static void WCLiquidGlassWCGlassLongPressRemoveFromSuperview(UIView *self, SEL selector) {
    UIView *hostView = nil;
    UIVisualEffectView *glassView = nil;
    if (WCLiquidGlassIsWCGlassLongPressHost(self)) {
        hostView = self;
        glassView = WCLiquidGlassWCGlassLongPressGlassInHost(self);
    } else if ([self isKindOfClass:UIVisualEffectView.class] &&
               WCLiquidGlassIsWCGlassLongPressView((UIVisualEffectView *)self)) {
        glassView = (UIVisualEffectView *)self;
        hostView = self.superview;
    }
    if (hostView &&
        glassView &&
        [objc_getAssociatedObject(glassView, WCLiquidGlassWCGlassLongPressAnimatedKey) boolValue]) {
        WCLiquidGlassAnimateWCGlassLongPressDismissal(hostView, glassView);
    }
    if (WCLiquidGlassOriginalViewRemoveFromSuperview) {
        WCLiquidGlassOriginalViewRemoveFromSuperview(self, selector);
    }
}

static void WCLiquidGlassWCGlassLongPressSetBackgroundColor(UIView *self,
                                                            SEL selector,
                                                            UIColor *color) {
    UIColor *resolvedColor =
        [objc_getAssociatedObject(self, WCLiquidGlassWCGlassLongPressContentKey) boolValue]
        ? UIColor.clearColor
        : color;
    if (WCLiquidGlassOriginalViewSetBackgroundColor) {
        WCLiquidGlassOriginalViewSetBackgroundColor(self, selector, resolvedColor);
    }
}

static void WCLiquidGlassWCGlassLongPressSetOverrideUserInterfaceStyle(
    UIView *self,
    SEL selector,
    UIUserInterfaceStyle style) {
    BOOL belongsToLongPressGlass =
        [self isKindOfClass:UIVisualEffectView.class] &&
        WCLiquidGlassIsWCGlassLongPressView((UIVisualEffectView *)self);
    if (belongsToLongPressGlass ||
        [objc_getAssociatedObject(self, WCLiquidGlassWCGlassLongPressContentKey) boolValue]) {
        style = UIUserInterfaceStyleUnspecified;
    }
    if (WCLiquidGlassOriginalViewSetOverrideUserInterfaceStyle) {
        WCLiquidGlassOriginalViewSetOverrideUserInterfaceStyle(self, selector, style);
    }
}

static BOOL WCLiquidGlassButtonBelongsToWCGlassLongPressMenu(UIButton *button) {
    UIView *view = button;
    for (NSUInteger depth = 0; view && depth < 12; depth += 1, view = view.superview) {
        if (WCLiquidGlassIsWCGlassLongPressHost(view)) {
            return YES;
        }
    }
    return NO;
}

static void WCLiquidGlassWCGlassLongPressSetHighlighted(UIButton *self,
                                                        SEL selector,
                                                        BOOL highlighted) {
    BOOL belongsToLongPressMenu = WCLiquidGlassButtonBelongsToWCGlassLongPressMenu(self);
    BOOL resolvedHighlighted = belongsToLongPressMenu ? NO : highlighted;
    if (WCLiquidGlassOriginalButtonSetHighlighted) {
        WCLiquidGlassOriginalButtonSetHighlighted(self, selector, resolvedHighlighted);
    }
    if (belongsToLongPressMenu) {
        WCLiquidGlassRemoveWCGlassLongPressButtonShadows(self, YES);
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
                    @selector(layoutSubviews),
                    (IMP)&WCLiquidGlassWCGlassLongPressLayoutSubviews,
                    (IMP *)&WCLiquidGlassOriginalVisualEffectLayoutSubviews);
    MSHookMessageEx(UIVisualEffectView.class,
                    @selector(setEffect:),
                    (IMP)&WCLiquidGlassWCGlassLongPressSetEffect,
                    (IMP *)&WCLiquidGlassOriginalVisualEffectSetEffect);
    MSHookMessageEx(UIApplication.class,
                    @selector(sendEvent:),
                    (IMP)&WCLiquidGlassWCGlassLongPressSendEvent,
                    (IMP *)&WCLiquidGlassOriginalApplicationSendEvent);
    MSHookMessageEx(UIView.class,
                    @selector(removeFromSuperview),
                    (IMP)&WCLiquidGlassWCGlassLongPressRemoveFromSuperview,
                    (IMP *)&WCLiquidGlassOriginalViewRemoveFromSuperview);
    MSHookMessageEx(UIView.class,
                    @selector(setBackgroundColor:),
                    (IMP)&WCLiquidGlassWCGlassLongPressSetBackgroundColor,
                    (IMP *)&WCLiquidGlassOriginalViewSetBackgroundColor);
    MSHookMessageEx(UIView.class,
                    @selector(setOverrideUserInterfaceStyle:),
                    (IMP)&WCLiquidGlassWCGlassLongPressSetOverrideUserInterfaceStyle,
                    (IMP *)&WCLiquidGlassOriginalViewSetOverrideUserInterfaceStyle);
    MSHookMessageEx(UIButton.class,
                    @selector(setHighlighted:),
                    (IMP)&WCLiquidGlassWCGlassLongPressSetHighlighted,
                    (IMP *)&WCLiquidGlassOriginalButtonSetHighlighted);
    [NSNotificationCenter.defaultCenter addObserverForName:WCLiquidGlassPreferencesDidChangeNotification
                                                    object:nil
                                                     queue:NSOperationQueue.mainQueue
                                                usingBlock:^(__unused NSNotification *notification) {
        WCLiquidGlassRefreshVisibleWCGlassLongPressViews();
    }];
}
