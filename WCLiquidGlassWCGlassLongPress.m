#import "WCLiquidGlassWCGlassLongPress.h"

#import <CydiaSubstrate.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "WCLiquidGlassMenu.h"
#import "WCLiquidGlassPreferences.h"

static const void *WCLiquidGlassWCGlassLongPressStateKey =
    &WCLiquidGlassWCGlassLongPressStateKey;
static const void *WCLiquidGlassWCGlassLongPressClosingKey =
    &WCLiquidGlassWCGlassLongPressClosingKey;
static void (*WCLiquidGlassOriginalVisualEffectDidMoveToWindow)(UIVisualEffectView *, SEL) = NULL;
static void (*WCLiquidGlassOriginalVisualEffectSetEffect)(UIVisualEffectView *, SEL, UIVisualEffect *) = NULL;
static BOOL (*WCLiquidGlassOriginalApplicationSendAction)(UIApplication *, SEL, SEL, id, id, UIEvent *) = NULL;
static void (*WCLiquidGlassOriginalWindowSetHidden)(UIWindow *, SEL, BOOL) = NULL;
static void (*WCLiquidGlassOriginalMenuControllerOnTouchAtNoneMenuArea)(id, SEL) = NULL;
static BOOL WCLiquidGlassWCGlassLongPressHooksInstalled = NO;
static BOOL WCLiquidGlassWCGlassLongPressMenuControllerHookInstalled = NO;

@interface WCLiquidGlassWCGlassLongPressState : NSObject
@property(nonatomic, weak) UIWindow *menuWindow;
@property(nonatomic, weak) UIView *hostView;
@property(nonatomic, weak) UIView *menuContentView;
@property(nonatomic, strong) UIVisualEffectView *glassContainer;
@property(nonatomic, strong) UIVisualEffectView *morphGlassView;
@property(nonatomic, strong) UIView *originalMaskView;
@property(nonatomic, strong) UIView *revealMaskView;
@property(nonatomic) CGRect collapsedFrame;
@property(nonatomic) CGRect targetFrame;
@property(nonatomic) CGAffineTransform originalMenuTransform;
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

static void WCLiquidGlassWCGlassLongPressSetMenuContentHidden(UIView *view,
                                                              BOOL hidden,
                                                              NSUInteger depth) {
    if (!view || depth > 12) {
        return;
    }
    if ([NSStringFromClass(view.class) isEqualToString:@"MMMenuContentView"]) {
        view.hidden = hidden;
        return;
    }
    for (UIView *subview in view.subviews) {
        WCLiquidGlassWCGlassLongPressSetMenuContentHidden(subview,
                                                          hidden,
                                                          depth + 1);
    }
}

static CGRect WCLiquidGlassWCGlassLongPressCollapsedFrame(CGRect targetFrame) {
    CGFloat height = MIN(CGRectGetHeight(targetFrame),
                         MAX(76.0, CGRectGetHeight(targetFrame) * 0.62));
    CGFloat width = MIN(CGRectGetWidth(targetFrame),
                        MAX(92.0, height * 1.16));
    return CGRectMake(CGRectGetMidX(targetFrame) - width * 0.5,
                      CGRectGetMidY(targetFrame) - height * 0.5,
                      width,
                      height);
}

static CGRect WCLiquidGlassWCGlassLongPressCenteredFrame(CGRect targetFrame,
                                                          CGFloat widthScale,
                                                          CGFloat heightScale) {
    CGFloat width = CGRectGetWidth(targetFrame) * widthScale;
    CGFloat height = CGRectGetHeight(targetFrame) * heightScale;
    return CGRectMake(CGRectGetMidX(targetFrame) - width * 0.5,
                      CGRectGetMidY(targetFrame) - height * 0.5,
                      width,
                      height);
}

static CGFloat WCLiquidGlassWCGlassLongPressCollapsedCornerRadius(CGRect frame) {
    return CGRectGetHeight(frame) * 0.5;
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
    state.menuContentView.transform = state.originalMenuTransform;
    state.hostView.hidden = NO;
    state.hostView.alpha = 1.0;
    state.morphGlassView.alpha = 1.0;
    state.revealMaskView.frame = state.targetFrame;
    state.revealMaskView.layer.cornerRadius = 25.0;
    state.morphGlassView.frame = state.targetFrame;
    state.morphGlassView.layer.cornerRadius = 25.0;
}

static UIVisualEffectView *WCLiquidGlassWCGlassLongPressGlassView(CGRect frame) {
    UIVisualEffectView *glassView =
        [[UIVisualEffectView alloc] initWithEffect:WCLiquidGlassCurrentGlassEffect()];
    glassView.frame = frame;
    glassView.userInteractionEnabled = NO;
    glassView.opaque = NO;
    glassView.backgroundColor = UIColor.clearColor;
    glassView.contentView.backgroundColor = UIColor.clearColor;
    glassView.clipsToBounds = YES;
    glassView.layer.cornerRadius = 22.0;
    glassView.layer.cornerCurve = kCACornerCurveContinuous;
    return glassView;
}

static void WCLiquidGlassInstallWCGlassLongPressMenuControllerHook(void);

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
    NSNumber *closingTime =
        objc_getAssociatedObject(menuWindow,
                                 WCLiquidGlassWCGlassLongPressClosingKey);
    if (closingTime) {
        if (CACurrentMediaTime() - closingTime.doubleValue < 0.75) {
            menuContentView.hidden = YES;
            return;
        }
        objc_setAssociatedObject(menuWindow,
                                 WCLiquidGlassWCGlassLongPressClosingKey,
                                 nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    WCLiquidGlassWCGlassLongPressState *existingState =
        objc_getAssociatedObject(menuWindow, WCLiquidGlassWCGlassLongPressStateKey);
    if (existingState && existingState.hostView == hostView) {
        if (existingState.dismissing) {
            return;
        }
        existingState.morphGlassView.effect = WCLiquidGlassCurrentGlassEffect();
        menuContentView.hidden = NO;
        hostView.hidden = NO;
        hostView.alpha = 1.0;
        WCLiquidGlassWCGlassLongPressApplyTransparentHost(hostView);
        return;
    }

    WCLiquidGlassWCGlassLongPressState *state =
        [[WCLiquidGlassWCGlassLongPressState alloc] init];
    state.menuWindow = menuWindow;
    state.hostView = hostView;
    state.menuContentView = menuContentView;
    state.originalMenuTransform = menuContentView.transform;
    state.targetFrame = [menuContentView convertRect:hostView.bounds
                                            fromView:hostView];
    state.collapsedFrame =
        WCLiquidGlassWCGlassLongPressCollapsedFrame(state.targetFrame);

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
        WCLiquidGlassWCGlassLongPressGlassView(state.collapsedFrame);
    morphGlassView.layer.cornerRadius =
        WCLiquidGlassWCGlassLongPressCollapsedCornerRadius(state.collapsedFrame);
    [glassContainer.contentView addSubview:morphGlassView];
    [menuContentView insertSubview:glassContainer atIndex:0];

    state.glassContainer = glassContainer;
    state.morphGlassView = morphGlassView;
    state.originalMaskView = menuContentView.maskView;
    UIView *revealMaskView =
        [[UIView alloc] initWithFrame:state.collapsedFrame];
    revealMaskView.userInteractionEnabled = NO;
    revealMaskView.backgroundColor = UIColor.blackColor;
    revealMaskView.layer.cornerRadius =
        WCLiquidGlassWCGlassLongPressCollapsedCornerRadius(state.collapsedFrame);
    revealMaskView.layer.cornerCurve = kCACornerCurveContinuous;
    state.revealMaskView = revealMaskView;
    menuContentView.maskView = revealMaskView;
    objc_setAssociatedObject(menuWindow,
                             WCLiquidGlassWCGlassLongPressStateKey,
                             state,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    WCLiquidGlassWCGlassLongPressApplyTransparentHost(hostView);
    menuContentView.hidden = NO;
    menuContentView.transform = UIAccessibilityIsReduceMotionEnabled()
        ? state.originalMenuTransform
        : CGAffineTransformScale(state.originalMenuTransform, 0.56, 0.66);
    morphGlassView.alpha = UIAccessibilityIsReduceMotionEnabled() ? 1.0 : 0.72;
    hostView.hidden = NO;
    hostView.alpha = 1.0;
    WCLiquidGlassInstallWCGlassLongPressMenuControllerHook();

    if (UIAccessibilityIsReduceMotionEnabled()) {
        WCLiquidGlassWCGlassLongPressFinishAppearance(state);
        return;
    }

    CGRect stretchedFrame =
        WCLiquidGlassWCGlassLongPressCenteredFrame(state.targetFrame, 1.025, 0.975);
    CGRect reboundFrame =
        WCLiquidGlassWCGlassLongPressCenteredFrame(state.targetFrame, 0.985, 1.015);
    [UIView animateWithDuration:0.46
                          delay:0.0
         usingSpringWithDamping:0.54
          initialSpringVelocity:0.38
                        options:UIViewAnimationOptionBeginFromCurrentState |
                                UIViewAnimationOptionAllowUserInteraction |
                                UIViewAnimationOptionCurveEaseOut
                     animations:^{
        menuContentView.transform =
            CGAffineTransformScale(state.originalMenuTransform, 1.035, 0.965);
        revealMaskView.frame = stretchedFrame;
        revealMaskView.layer.cornerRadius = 31.0;
        morphGlassView.frame = stretchedFrame;
        morphGlassView.layer.cornerRadius = 31.0;
        morphGlassView.alpha = 1.0;
    }
                     completion:^(__unused BOOL finished) {
        if (state.dismissing) {
            return;
        }
        [UIView animateWithDuration:0.24
                              delay:0.0
             usingSpringWithDamping:0.60
              initialSpringVelocity:0.22
                            options:UIViewAnimationOptionBeginFromCurrentState |
                                    UIViewAnimationOptionAllowUserInteraction |
                                    UIViewAnimationOptionCurveEaseInOut
                         animations:^{
            menuContentView.transform =
                CGAffineTransformScale(state.originalMenuTransform, 0.982, 1.018);
            revealMaskView.frame = reboundFrame;
            revealMaskView.layer.cornerRadius = 22.0;
            morphGlassView.frame = reboundFrame;
            morphGlassView.layer.cornerRadius = 22.0;
            morphGlassView.alpha = 0.94;
        }
                         completion:^(__unused BOOL reboundFinished) {
            if (state.dismissing) {
                return;
            }
            [UIView animateWithDuration:0.28
                                  delay:0.0
                 usingSpringWithDamping:0.70
                  initialSpringVelocity:0.18
                                options:UIViewAnimationOptionBeginFromCurrentState |
                                        UIViewAnimationOptionAllowUserInteraction |
                                        UIViewAnimationOptionCurveEaseOut
                             animations:^{
                menuContentView.transform = state.originalMenuTransform;
                revealMaskView.frame = state.targetFrame;
                revealMaskView.layer.cornerRadius = 25.0;
                morphGlassView.frame = state.targetFrame;
                morphGlassView.layer.cornerRadius = 25.0;
                morphGlassView.alpha = 1.0;
            }
                             completion:^(__unused BOOL settleFinished) {
                WCLiquidGlassWCGlassLongPressFinishAppearance(state);
            }];
        }];
    }];
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

typedef void (^WCLiquidGlassWCGlassLongPressNativeDismissal)(void);

static void WCLiquidGlassWCGlassLongPressCompleteDismissal(
    WCLiquidGlassWCGlassLongPressState *state,
    WCLiquidGlassWCGlassLongPressNativeDismissal nativeDismissal) {
    UIWindow *menuWindow = state.menuWindow;
    UIView *hostView = state.hostView;
    UIView *menuContentView = state.menuContentView;
    if (menuWindow) {
        objc_setAssociatedObject(menuWindow,
                                 WCLiquidGlassWCGlassLongPressClosingKey,
                                 @(CACurrentMediaTime()),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(menuWindow,
                                 WCLiquidGlassWCGlassLongPressStateKey,
                                 nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    menuContentView.hidden = YES;
    menuContentView.transform = state.originalMenuTransform;
    menuContentView.maskView = state.originalMaskView;
    hostView.alpha = 1.0;
    hostView.hidden = YES;
    [state.glassContainer removeFromSuperview];
    if (nativeDismissal) {
        nativeDismissal();
    }
}

static void WCLiquidGlassWCGlassLongPressDismiss(
    WCLiquidGlassWCGlassLongPressState *state,
    WCLiquidGlassWCGlassLongPressNativeDismissal nativeDismissal) {
    if (state.dismissing) {
        return;
    }
    state.dismissing = YES;
    if (UIAccessibilityIsReduceMotionEnabled() ||
        !state.hostView.window ||
        !state.morphGlassView.window) {
        WCLiquidGlassWCGlassLongPressCompleteDismissal(state, nativeDismissal);
        return;
    }

    CGRect stretchedFrame =
        WCLiquidGlassWCGlassLongPressCenteredFrame(state.targetFrame, 1.018, 0.982);
    CGRect compressedFrame =
        WCLiquidGlassWCGlassLongPressCenteredFrame(state.targetFrame, 0.62, 0.78);
    CGRect terminalFrame =
        WCLiquidGlassWCGlassLongPressCenteredFrame(state.targetFrame, 0.08, 0.10);
    [UIView animateWithDuration:0.15
                          delay:0.0
         usingSpringWithDamping:0.52
          initialSpringVelocity:0.28
                        options:UIViewAnimationOptionBeginFromCurrentState |
                                UIViewAnimationOptionAllowUserInteraction |
                                UIViewAnimationOptionCurveEaseOut
                     animations:^{
        state.menuContentView.transform =
            CGAffineTransformScale(state.originalMenuTransform, 1.018, 0.982);
        state.revealMaskView.frame = stretchedFrame;
        state.revealMaskView.layer.cornerRadius = 22.0;
        state.morphGlassView.frame = stretchedFrame;
        state.morphGlassView.layer.cornerRadius = 22.0;
    }
                     completion:^(__unused BOOL finished) {
        [UIView animateWithDuration:0.34
                              delay:0.0
             usingSpringWithDamping:0.54
              initialSpringVelocity:0.34
                            options:UIViewAnimationOptionBeginFromCurrentState |
                                    UIViewAnimationOptionAllowUserInteraction |
                                    UIViewAnimationOptionCurveEaseInOut
                         animations:^{
            state.menuContentView.transform =
                CGAffineTransformScale(state.originalMenuTransform, 0.57, 0.70);
            state.revealMaskView.frame = compressedFrame;
            state.revealMaskView.layer.cornerRadius =
                WCLiquidGlassWCGlassLongPressCollapsedCornerRadius(compressedFrame);
            state.morphGlassView.frame = compressedFrame;
            state.morphGlassView.layer.cornerRadius =
                WCLiquidGlassWCGlassLongPressCollapsedCornerRadius(compressedFrame);
        }
                         completion:^(__unused BOOL compressedFinished) {
            [UIView animateWithDuration:0.26
                                  delay:0.0
                 usingSpringWithDamping:0.68
                  initialSpringVelocity:0.24
                                options:UIViewAnimationOptionBeginFromCurrentState |
                                        UIViewAnimationOptionAllowUserInteraction |
                                        UIViewAnimationOptionCurveEaseIn
                             animations:^{
                state.menuContentView.transform =
                    CGAffineTransformScale(state.originalMenuTransform, 0.14, 0.18);
                state.revealMaskView.frame = state.collapsedFrame;
                state.revealMaskView.layer.cornerRadius =
                    WCLiquidGlassWCGlassLongPressCollapsedCornerRadius(state.collapsedFrame);
                state.morphGlassView.frame = state.collapsedFrame;
                state.morphGlassView.layer.cornerRadius =
                    WCLiquidGlassWCGlassLongPressCollapsedCornerRadius(state.collapsedFrame);
                state.morphGlassView.alpha = 0.82;
            }
                             completion:^(__unused BOOL collapsedFinished) {
                [UIView animateWithDuration:0.10
                                      delay:0.0
                                    options:UIViewAnimationOptionBeginFromCurrentState |
                                            UIViewAnimationOptionAllowUserInteraction |
                                            UIViewAnimationOptionCurveEaseIn
                                 animations:^{
                    state.menuContentView.transform =
                        CGAffineTransformScale(state.originalMenuTransform, 0.001, 0.001);
                    state.revealMaskView.frame = terminalFrame;
                    state.revealMaskView.layer.cornerRadius =
                        WCLiquidGlassWCGlassLongPressCollapsedCornerRadius(terminalFrame);
                    state.morphGlassView.frame = terminalFrame;
                    state.morphGlassView.layer.cornerRadius =
                        WCLiquidGlassWCGlassLongPressCollapsedCornerRadius(terminalFrame);
                    state.morphGlassView.alpha = 0.0;
                }
                                 completion:^(__unused BOOL terminalFinished) {
                    WCLiquidGlassWCGlassLongPressCompleteDismissal(state,
                                                                   nativeDismissal);
                }];
            }];
        }];
    }];
}

static UIWindow *WCLiquidGlassWCGlassLongPressWindowForObject(id object) {
    if ([object isKindOfClass:UIView.class]) {
        return ((UIView *)object).window;
    }
    if ([object isKindOfClass:UIGestureRecognizer.class]) {
        return ((UIGestureRecognizer *)object).view.window;
    }
    if ([object isKindOfClass:UIViewController.class]) {
        return ((UIViewController *)object).viewIfLoaded.window;
    }
    return nil;
}

static BOOL WCLiquidGlassWCGlassLongPressSendAction(UIApplication *self,
                                                    SEL selector,
                                                    SEL action,
                                                    id target,
                                                    id sender,
                                                    UIEvent *event) {
    if (action == sel_registerName("onItemButtonClick:")) {
        UIWindow *menuWindow =
            WCLiquidGlassWCGlassLongPressWindowForObject(sender) ?:
            WCLiquidGlassWCGlassLongPressWindowForObject(target);
        WCLiquidGlassWCGlassLongPressState *state =
            objc_getAssociatedObject(menuWindow, WCLiquidGlassWCGlassLongPressStateKey);
        if (state) {
            if (!state.dismissing) {
                WCLiquidGlassWCGlassLongPressDismiss(state, ^{
                    if (WCLiquidGlassOriginalApplicationSendAction) {
                        WCLiquidGlassOriginalApplicationSendAction(self,
                                                                   selector,
                                                                   action,
                                                                   target,
                                                                   sender,
                                                                   event);
                    }
                });
            }
            return YES;
        }
    }
    return WCLiquidGlassOriginalApplicationSendAction
        ? WCLiquidGlassOriginalApplicationSendAction(self,
                                                     selector,
                                                     action,
                                                     target,
                                                     sender,
                                                     event)
        : NO;
}

static void WCLiquidGlassWCGlassLongPressMenuControllerOnTouchAtNoneMenuArea(
    id self,
    SEL selector) {
    UIWindow *menuWindow = WCLiquidGlassWCGlassLongPressWindowForObject(self);
    WCLiquidGlassWCGlassLongPressState *state =
        objc_getAssociatedObject(menuWindow, WCLiquidGlassWCGlassLongPressStateKey);
    if (state) {
        if (!state.dismissing) {
            WCLiquidGlassWCGlassLongPressDismiss(state, ^{
                if (WCLiquidGlassOriginalMenuControllerOnTouchAtNoneMenuArea) {
                    WCLiquidGlassOriginalMenuControllerOnTouchAtNoneMenuArea(self, selector);
                }
            });
        }
        return;
    }
    if (WCLiquidGlassOriginalMenuControllerOnTouchAtNoneMenuArea) {
        WCLiquidGlassOriginalMenuControllerOnTouchAtNoneMenuArea(self, selector);
    }
}

static void WCLiquidGlassInstallWCGlassLongPressMenuControllerHook(void) {
    if (WCLiquidGlassWCGlassLongPressMenuControllerHookInstalled) {
        return;
    }
    Class menuControllerClass = NSClassFromString(@"MMMenuController");
    SEL selector = sel_registerName("onTouchAtNoneMenuArea");
    if (!menuControllerClass || !class_getInstanceMethod(menuControllerClass, selector)) {
        return;
    }
    WCLiquidGlassWCGlassLongPressMenuControllerHookInstalled = YES;
    MSHookMessageEx(menuControllerClass,
                    selector,
                    (IMP)&WCLiquidGlassWCGlassLongPressMenuControllerOnTouchAtNoneMenuArea,
                    (IMP *)&WCLiquidGlassOriginalMenuControllerOnTouchAtNoneMenuArea);
}

static void WCLiquidGlassWCGlassLongPressWindowSetHidden(UIWindow *self,
                                                         SEL selector,
                                                         BOOL hidden) {
    if (!hidden &&
        [NSStringFromClass(self.class) isEqualToString:@"MMMenuWindow"]) {
        objc_setAssociatedObject(self,
                                 WCLiquidGlassWCGlassLongPressClosingKey,
                                 nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        WCLiquidGlassWCGlassLongPressSetMenuContentHidden(self, NO, 0);
    }
    WCLiquidGlassWCGlassLongPressState *state =
        objc_getAssociatedObject(self, WCLiquidGlassWCGlassLongPressStateKey);
    if (hidden && state) {
        if (!state.dismissing) {
            WCLiquidGlassWCGlassLongPressDismiss(state, ^{
                if (WCLiquidGlassOriginalWindowSetHidden) {
                    WCLiquidGlassOriginalWindowSetHidden(self, selector, hidden);
                }
            });
        }
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
                    @selector(sendAction:to:from:forEvent:),
                    (IMP)&WCLiquidGlassWCGlassLongPressSendAction,
                    (IMP *)&WCLiquidGlassOriginalApplicationSendAction);
    MSHookMessageEx(UIWindow.class,
                    @selector(setHidden:),
                    (IMP)&WCLiquidGlassWCGlassLongPressWindowSetHidden,
                    (IMP *)&WCLiquidGlassOriginalWindowSetHidden);
    WCLiquidGlassInstallWCGlassLongPressMenuControllerHook();
    [NSNotificationCenter.defaultCenter addObserverForName:WCLiquidGlassPreferencesDidChangeNotification
                                                    object:nil
                                                     queue:NSOperationQueue.mainQueue
                                                usingBlock:^(__unused NSNotification *notification) {
        WCLiquidGlassRefreshVisibleWCGlassLongPressViews();
    }];
}
