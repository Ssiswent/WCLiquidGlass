#import "WCLiquidGlassWCGlassLongPress.h"

#import <CydiaSubstrate.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "WCLiquidGlassLongPressDiagnostics.h"
#import "WCLiquidGlassMenu.h"
#import "WCLiquidGlassPreferences.h"

static const void *WCLiquidGlassWCGlassLongPressAnimatedKey =
    &WCLiquidGlassWCGlassLongPressAnimatedKey;
static void (*WCLiquidGlassOriginalVisualEffectDidMoveToWindow)(UIVisualEffectView *, SEL) = NULL;
static void (*WCLiquidGlassOriginalVisualEffectSetEffect)(UIVisualEffectView *, SEL, UIVisualEffect *) = NULL;
static BOOL WCLiquidGlassWCGlassLongPressHooksInstalled = NO;

static SEL WCLiquidGlassWCGlassLongPressMarker(void) {
    return sel_registerName("WCLGApplyLongPressMenuGlass:");
}

static BOOL WCLiquidGlassIsWCGlassLongPressView(UIVisualEffectView *view) {
    return view && objc_getAssociatedObject(view, WCLiquidGlassWCGlassLongPressMarker()) != nil;
}

static void WCLiquidGlassMakeWCGlassLongPressViewTransparent(UIVisualEffectView *view) {
    view.opaque = NO;
    view.backgroundColor = UIColor.clearColor;
    view.contentView.backgroundColor = UIColor.clearColor;
    view.layer.backgroundColor = UIColor.clearColor.CGColor;
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

static CGSize WCLiquidGlassWCGlassLongPressAnimatedSize(CGSize finalSize,
                                                        CGFloat diameter,
                                                        CGFloat widthProgress,
                                                        CGFloat heightProgress) {
    return CGSizeMake(diameter + (finalSize.width - diameter) * widthProgress,
                      diameter + (finalSize.height - diameter) * heightProgress);
}

static CGPoint WCLiquidGlassWCGlassLongPressPosition(CGRect finalFrame,
                                                      CGSize size,
                                                      BOOL growsFromRight,
                                                      BOOL growsFromBottom) {
    CGFloat x = growsFromRight
        ? CGRectGetMaxX(finalFrame) - size.width * 0.5
        : CGRectGetMinX(finalFrame) + size.width * 0.5;
    CGFloat y = growsFromBottom
        ? CGRectGetMaxY(finalFrame) - size.height * 0.5
        : CGRectGetMinY(finalFrame) + size.height * 0.5;
    return CGPointMake(x, y);
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

static void WCLiquidGlassAnimateWCGlassLongPressAppearance(UIVisualEffectView *view) {
    if (!view.window ||
        UIAccessibilityIsReduceMotionEnabled() ||
        MIN(CGRectGetWidth(view.bounds), CGRectGetHeight(view.bounds)) < 24.0 ||
        MAX(CGRectGetWidth(view.bounds), CGRectGetHeight(view.bounds)) < 56.0) {
        return;
    }
    CALayer *layer = view.layer;
    CGRect finalBounds = layer.bounds;
    CGRect finalFrame = view.frame;
    CGPoint finalPosition = layer.position;
    CGSize finalSize = finalBounds.size;
    CGFloat diameter = MIN(44.0, MIN(finalSize.width, finalSize.height));
    CGPoint centerInWindow = [view convertPoint:CGPointMake(CGRectGetMidX(view.bounds),
                                                            CGRectGetMidY(view.bounds))
                                         toView:view.window];
    BOOL growsFromRight = centerInWindow.x >= CGRectGetMidX(view.window.bounds);
    BOOL growsFromBottom = centerInWindow.y >= CGRectGetMidY(view.window.bounds);
    NSArray<NSNumber *> *widthProgress = @[@0.0, @0.34, @0.76, @1.02, @0.995, @1.0];
    NSArray<NSNumber *> *heightProgress = @[@0.0, @0.12, @0.48, @0.94, @1.012, @1.0];
    NSArray<NSNumber *> *keyTimes = @[@0.0, @0.16, @0.42, @0.68, @0.84, @1.0];
    NSMutableArray<NSValue *> *boundsValues = [NSMutableArray arrayWithCapacity:keyTimes.count];
    NSMutableArray<NSValue *> *positionValues = [NSMutableArray arrayWithCapacity:keyTimes.count];
    NSMutableArray<NSNumber *> *cornerValues = [NSMutableArray arrayWithCapacity:keyTimes.count];
    for (NSUInteger index = 0; index < keyTimes.count; index += 1) {
        CGSize size = WCLiquidGlassWCGlassLongPressAnimatedSize(finalSize,
                                                                diameter,
                                                                widthProgress[index].doubleValue,
                                                                heightProgress[index].doubleValue);
        CGRect bounds = CGRectMake(finalBounds.origin.x,
                                   finalBounds.origin.y,
                                   size.width,
                                   size.height);
        CGPoint position = WCLiquidGlassWCGlassLongPressPosition(finalFrame,
                                                                 size,
                                                                 growsFromRight,
                                                                 growsFromBottom);
        CGFloat progress = MAX(widthProgress[index].doubleValue,
                               heightProgress[index].doubleValue);
        CGFloat cornerRadius = diameter * 0.5 +
            (layer.cornerRadius - diameter * 0.5) * MIN(1.0, progress);
        [boundsValues addObject:[NSValue valueWithCGRect:bounds]];
        [positionValues addObject:[NSValue valueWithCGPoint:position]];
        [cornerValues addObject:@(MAX(0.0, cornerRadius))];
    }
    positionValues[positionValues.count - 1] = [NSValue valueWithCGPoint:finalPosition];
    boundsValues[boundsValues.count - 1] = [NSValue valueWithCGRect:finalBounds];
    cornerValues[cornerValues.count - 1] = @(layer.cornerRadius);

    CAKeyframeAnimation *boundsAnimation = [CAKeyframeAnimation animationWithKeyPath:@"bounds"];
    boundsAnimation.values = boundsValues;
    boundsAnimation.keyTimes = keyTimes;
    CAKeyframeAnimation *positionAnimation = [CAKeyframeAnimation animationWithKeyPath:@"position"];
    positionAnimation.values = positionValues;
    positionAnimation.keyTimes = keyTimes;
    CAKeyframeAnimation *cornerAnimation = [CAKeyframeAnimation animationWithKeyPath:@"cornerRadius"];
    cornerAnimation.values = cornerValues;
    cornerAnimation.keyTimes = keyTimes;
    CAKeyframeAnimation *opacityAnimation = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    opacityAnimation.values = @[@0.48, @0.76, @0.94, @1.0];
    opacityAnimation.keyTimes = @[@0.0, @0.22, @0.56, @1.0];

    NSArray<CAMediaTimingFunction *> *timingFunctions = @[
        [CAMediaTimingFunction functionWithControlPoints:0.20 :0.82 :0.32 :1.0],
        [CAMediaTimingFunction functionWithControlPoints:0.18 :0.86 :0.28 :1.0],
        [CAMediaTimingFunction functionWithControlPoints:0.22 :0.76 :0.34 :1.0],
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut],
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut]
    ];
    boundsAnimation.timingFunctions = timingFunctions;
    positionAnimation.timingFunctions = timingFunctions;
    cornerAnimation.timingFunctions = timingFunctions;
    opacityAnimation.timingFunctions = @[
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut],
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut],
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut]
    ];

    CFTimeInterval beginTime = CACurrentMediaTime();
    CFTimeInterval duration = 0.42;
    CAAnimationGroup *group = [CAAnimationGroup animation];
    group.animations = @[boundsAnimation, positionAnimation, cornerAnimation, opacityAnimation];
    group.duration = duration;
    group.beginTime = beginTime;
    group.fillMode = kCAFillModeBackwards;
    group.removedOnCompletion = YES;
    [layer addAnimation:group forKey:@"WCLiquidGlass.WCGlassLongPress.GlassExpansion"];
    WCLiquidGlassAnimateWCGlassLongPressContent(view, beginTime + 0.035, duration - 0.035);
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
    UIVisualEffect *resolvedEffect = isWCGlassLongPressView ? WCLiquidGlassCurrentGlassEffect() : effect;
    if (WCLiquidGlassOriginalVisualEffectSetEffect) {
        WCLiquidGlassOriginalVisualEffectSetEffect(self, selector, resolvedEffect);
    }
    if (isWCGlassLongPressView) {
        WCLiquidGlassMakeWCGlassLongPressViewTransparent(self);
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
    WCLiquidGlassInstallLongPressMenuDiagnostics();
    [NSNotificationCenter.defaultCenter addObserverForName:WCLiquidGlassPreferencesDidChangeNotification
                                                    object:nil
                                                     queue:NSOperationQueue.mainQueue
                                                usingBlock:^(__unused NSNotification *notification) {
        WCLiquidGlassRefreshVisibleWCGlassLongPressViews();
    }];
}
