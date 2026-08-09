#import "WCLiquidGlassMessageSwipe.h"

#import <CydiaSubstrate.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "WCLiquidGlassPreferences.h"

static const void *WCLiquidGlassMessageSwipeGestureKey = &WCLiquidGlassMessageSwipeGestureKey;
static const void *WCLiquidGlassMessageSwipeFeedbackKey = &WCLiquidGlassMessageSwipeFeedbackKey;
static const void *WCLiquidGlassMessageSwipeFeedbackTriggeredKey = &WCLiquidGlassMessageSwipeFeedbackTriggeredKey;
static const void *WCLiquidGlassMessageSwipeMenuDelegateKey = &WCLiquidGlassMessageSwipeMenuDelegateKey;
static const void *WCLiquidGlassMessageSwipeMenuInteractionKey = &WCLiquidGlassMessageSwipeMenuInteractionKey;
static const void *WCLiquidGlassMessageSwipeMenuAnchorKey = &WCLiquidGlassMessageSwipeMenuAnchorKey;
static void (*WCLiquidGlassOriginalCommonMessageCellDidMoveToWindow)(id, SEL) = NULL;
static BOOL (*WCLiquidGlassOriginalGestureRecognizerShouldBegin)(id, SEL, UIGestureRecognizer *) = NULL;
static BOOL (*WCLiquidGlassOriginalShouldRecognizeSimultaneously)(id, SEL, UIGestureRecognizer *, UIGestureRecognizer *) = NULL;
static BOOL (*WCLiquidGlassOriginalShouldRequireFailure)(id, SEL, UIGestureRecognizer *, UIGestureRecognizer *) = NULL;
static BOOL WCLiquidGlassMessageSwipeHooksInstalled = NO;
static BOOL WCLiquidGlassMessageSwipeHookRetryScheduled = NO;
static NSUInteger WCLiquidGlassMessageSwipeHookAttempts = 0;
static NSHashTable<UIView *> *WCLiquidGlassMessageSwipeCells;

static UIPanGestureRecognizer *WCLiquidGlassMessageSwipeGesture(UIView *view) {
    return objc_getAssociatedObject(view, WCLiquidGlassMessageSwipeGestureKey);
}

static UIImpactFeedbackGenerator *WCLiquidGlassMessageSwipeFeedback(UIView *view) {
    return objc_getAssociatedObject(view, WCLiquidGlassMessageSwipeFeedbackKey);
}

static BOOL WCLiquidGlassMessageSwipeFeedbackTriggered(UIView *view) {
    return [objc_getAssociatedObject(view, WCLiquidGlassMessageSwipeFeedbackTriggeredKey) boolValue];
}

static void WCLiquidGlassSetMessageSwipeFeedbackTriggered(UIView *view, BOOL triggered) {
    objc_setAssociatedObject(view,
                             WCLiquidGlassMessageSwipeFeedbackTriggeredKey,
                             @(triggered),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static NSArray<UIView *> *WCLiquidGlassMessageSwipeRelatedViews(UIView *view) {
    return view ? @[view] : @[];
}

static CGFloat WCLiquidGlassMessageSwipeThreshold(UIView *view) {
    return MAX(CGRectGetWidth(view.bounds) * 0.18, 44.0);
}

static BOOL WCLiquidGlassMessageSwipeShouldIgnore(CGPoint translation) {
    return translation.x > 0.0 && fabs(translation.y) <= fabs(translation.x) * 0.7;
}

static BOOL WCLiquidGlassMessageSwipeVelocityEligible(CGPoint velocity) {
    return velocity.x < 0.0 && fabs(velocity.x) >= fabs(velocity.y) * 1.3;
}

static CGFloat WCLiquidGlassMessageSwipeClampedTranslation(CGFloat translation, CGFloat threshold) {
    return MIN(MAX(-translation, 0.0), threshold);
}

static BOOL WCLiquidGlassMessageSwipeShouldTrigger(CGPoint translation,
                                                   CGPoint velocity,
                                                   CGFloat threshold) {
    return translation.x <= -threshold || velocity.x <= -600.0;
}

static void WCLiquidGlassMessageSwipeApplyTransform(CGAffineTransform transform,
                                                    NSArray<UIView *> *views) {
    for (UIView *view in views) {
        view.transform = transform;
    }
}

static void WCLiquidGlassMessageSwipeResetViews(NSArray<UIView *> *views, BOOL animated) {
    if (views.count == 0) {
        return;
    }
    void (^reset)(void) = ^{
        WCLiquidGlassMessageSwipeApplyTransform(CGAffineTransformIdentity, views);
    };
    if (animated) {
        [UIView animateWithDuration:0.25
                              delay:0.0
             usingSpringWithDamping:0.78
              initialSpringVelocity:0.0
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                         animations:reset
                         completion:nil];
    } else {
        reset();
    }
}

static void WCLiquidGlassMessageSwipeTriggerFeedback(UIView *view) {
    if (WCLiquidGlassMessageSwipeFeedbackTriggered(view)) {
        return;
    }
    [WCLiquidGlassMessageSwipeFeedback(view) impactOccurred];
    WCLiquidGlassSetMessageSwipeFeedbackTriggered(view, YES);
}

static id WCLiquidGlassMessageSwipeValue(id object, NSString *key) {
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static void WCLiquidGlassMessageSwipeTriggerActionMenu(UIView *view) {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            id viewModel = WCLiquidGlassMessageSwipeValue(view, @"viewModel");
            id messageWrap = WCLiquidGlassMessageSwipeValue(viewModel, @"messageWrap");
            Class delegateClass = NSClassFromString(@"WCLGMessageSwipeMenuDelegate");
            SEL presentSelector = NSSelectorFromString(@"_presentMenuAtLocation:");
            if (messageWrap && delegateClass) {
                UIContextMenuInteraction *oldInteraction = objc_getAssociatedObject(view, WCLiquidGlassMessageSwipeMenuInteractionKey);
                if (oldInteraction) {
                    [view removeInteraction:oldInteraction];
                }
                [objc_getAssociatedObject(view, WCLiquidGlassMessageSwipeMenuAnchorKey) removeFromSuperview];

                id delegate = [delegateClass new];
                [delegate setValue:view forKey:@"cell"];
                [delegate setValue:messageWrap forKey:@"frozenWrap"];

                UIResponder *responder = view;
                while ((responder = responder.nextResponder)) {
                    if ([responder isKindOfClass:UIViewController.class]) {
                        [delegate setValue:responder forKey:@"chatController"];
                        break;
                    }
                }

                UIView *anchor = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 1.0, 1.0)];
                anchor.center = CGPointMake(CGRectGetMidX(view.bounds), CGRectGetMidY(view.bounds));
                anchor.backgroundColor = UIColor.clearColor;
                anchor.userInteractionEnabled = NO;
                anchor.accessibilityElementsHidden = YES;
                [view addSubview:anchor];
                [delegate setValue:anchor forKey:@"previewAnchor"];

                UIContextMenuInteraction *interaction = [[UIContextMenuInteraction alloc] initWithDelegate:delegate];
                [view addInteraction:interaction];
                objc_setAssociatedObject(view, WCLiquidGlassMessageSwipeMenuDelegateKey, delegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                objc_setAssociatedObject(view, WCLiquidGlassMessageSwipeMenuInteractionKey, interaction, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                objc_setAssociatedObject(view, WCLiquidGlassMessageSwipeMenuAnchorKey, anchor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

                NSMethodSignature *signature = [interaction methodSignatureForSelector:presentSelector];
                if ([interaction respondsToSelector:presentSelector] &&
                    signature.numberOfArguments == 3 &&
                    strcmp([signature getArgumentTypeAtIndex:2], @encode(CGPoint)) == 0) {
                    ((void (*)(id, SEL, CGPoint))objc_msgSend)(interaction,
                                                               presentSelector,
                                                               CGPointMake(CGRectGetMidX(view.bounds), CGRectGetMidY(view.bounds)));
                    return;
                }
            }
            SEL quoteSelector = NSSelectorFromString(@"onShowMsgReplyMenuItem:");
            if ([view respondsToSelector:quoteSelector]) {
                ((void (*)(id, SEL, id))objc_msgSend)(view, quoteSelector, nil);
            }
        } @catch (__unused NSException *exception) {
        }
    });
}

static void WCLiquidGlassMessageSwipeReset(UIView *view, BOOL animated) {
    WCLiquidGlassMessageSwipeResetViews(WCLiquidGlassMessageSwipeRelatedViews(view), animated);
    WCLiquidGlassSetMessageSwipeFeedbackTriggered(view, NO);
}

static void WCLiquidGlassMessageSwipeHandle(id self, SEL selector, UIPanGestureRecognizer *gesture) {
    (void)selector;
    UIView *view = self;
    if (!WCLiquidGlassPreferences.messageSwipeActionsEnabled) {
        WCLiquidGlassMessageSwipeReset(view, YES);
        return;
    }

    NSArray<UIView *> *views = WCLiquidGlassMessageSwipeRelatedViews(view);
    CGPoint translation = [gesture translationInView:view];
    CGPoint velocity = [gesture velocityInView:view];
    if (WCLiquidGlassMessageSwipeShouldIgnore(translation)) {
        WCLiquidGlassMessageSwipeApplyTransform(CGAffineTransformIdentity, views);
        if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
            WCLiquidGlassMessageSwipeReset(view, YES);
        }
        return;
    }

    CGFloat threshold = WCLiquidGlassMessageSwipeThreshold(view);
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan:
            [WCLiquidGlassMessageSwipeFeedback(view) prepare];
            WCLiquidGlassSetMessageSwipeFeedbackTriggered(view, NO);
            break;
        case UIGestureRecognizerStateChanged: {
            CGFloat distance = WCLiquidGlassMessageSwipeClampedTranslation(translation.x, threshold);
            WCLiquidGlassMessageSwipeApplyTransform(CGAffineTransformMakeTranslation(-distance, 0.0), views);
            if (!WCLiquidGlassMessageSwipeFeedbackTriggered(view) && translation.x <= -threshold) {
                WCLiquidGlassMessageSwipeTriggerFeedback(view);
            }
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
            if (WCLiquidGlassMessageSwipeShouldTrigger(translation, velocity, threshold)) {
                WCLiquidGlassMessageSwipeTriggerFeedback(view);
                WCLiquidGlassMessageSwipeTriggerActionMenu(view);
            }
            WCLiquidGlassMessageSwipeReset(view, YES);
            break;
        case UIGestureRecognizerStateFailed:
            WCLiquidGlassMessageSwipeReset(view, NO);
            break;
        default:
            break;
    }
}

static void WCLiquidGlassMessageSwipeSetup(UIView *view) {
    [WCLiquidGlassMessageSwipeCells addObject:view];
    UIPanGestureRecognizer *gesture = WCLiquidGlassMessageSwipeGesture(view);
    if (!WCLiquidGlassPreferences.messageSwipeActionsEnabled) {
        gesture.enabled = NO;
        WCLiquidGlassMessageSwipeReset(view, NO);
        return;
    }
    if (!gesture) {
        gesture = [[UIPanGestureRecognizer alloc] initWithTarget:view action:NSSelectorFromString(@"wclg_handleMessageSwipe:")];
        gesture.minimumNumberOfTouches = 1;
        gesture.maximumNumberOfTouches = 1;
        gesture.cancelsTouchesInView = YES;
        gesture.delaysTouchesBegan = NO;
        gesture.delaysTouchesEnded = NO;
        gesture.delegate = (id<UIGestureRecognizerDelegate>)view;
        [view addGestureRecognizer:gesture];
        objc_setAssociatedObject(view,
                                 WCLiquidGlassMessageSwipeGestureKey,
                                 gesture,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    gesture.enabled = YES;
    if (!WCLiquidGlassMessageSwipeFeedback(view)) {
        UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        objc_setAssociatedObject(view,
                                 WCLiquidGlassMessageSwipeFeedbackKey,
                                 feedback,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!view.window) {
        WCLiquidGlassMessageSwipeReset(view, NO);
    }
}

static void WCLiquidGlassMessageSwipeCommonMessageCellDidMoveToWindow(id self, SEL selector) {
    if (WCLiquidGlassOriginalCommonMessageCellDidMoveToWindow) {
        WCLiquidGlassOriginalCommonMessageCellDidMoveToWindow(self, selector);
    }
    WCLiquidGlassMessageSwipeSetup(self);
}

static BOOL WCLiquidGlassMessageSwipeGestureRecognizerShouldBegin(id self,
                                                                  SEL selector,
                                                                  UIGestureRecognizer *gestureRecognizer) {
    if (gestureRecognizer == WCLiquidGlassMessageSwipeGesture(self)) {
        if (!WCLiquidGlassPreferences.messageSwipeActionsEnabled) {
            return NO;
        }
        CGPoint velocity = [(UIPanGestureRecognizer *)gestureRecognizer velocityInView:self];
        return WCLiquidGlassMessageSwipeVelocityEligible(velocity);
    }
    return WCLiquidGlassOriginalGestureRecognizerShouldBegin
        ? WCLiquidGlassOriginalGestureRecognizerShouldBegin(self, selector, gestureRecognizer)
        : YES;
}

static BOOL WCLiquidGlassMessageSwipeShouldRecognizeSimultaneously(id self,
                                                                   SEL selector,
                                                                   UIGestureRecognizer *gestureRecognizer,
                                                                   UIGestureRecognizer *otherGestureRecognizer) {
    if (gestureRecognizer == WCLiquidGlassMessageSwipeGesture(self)) {
        return NO;
    }
    return WCLiquidGlassOriginalShouldRecognizeSimultaneously
        ? WCLiquidGlassOriginalShouldRecognizeSimultaneously(self,
                                                              selector,
                                                              gestureRecognizer,
                                                              otherGestureRecognizer)
        : NO;
}

static BOOL WCLiquidGlassMessageSwipeShouldRequireFailure(id self,
                                                          SEL selector,
                                                          UIGestureRecognizer *gestureRecognizer,
                                                          UIGestureRecognizer *otherGestureRecognizer) {
    if (gestureRecognizer == WCLiquidGlassMessageSwipeGesture(self) &&
        [otherGestureRecognizer isKindOfClass:UITapGestureRecognizer.class]) {
        return YES;
    }
    return WCLiquidGlassOriginalShouldRequireFailure
        ? WCLiquidGlassOriginalShouldRequireFailure(self,
                                                     selector,
                                                     gestureRecognizer,
                                                     otherGestureRecognizer)
        : NO;
}

static void WCLiquidGlassMessageSwipeRefresh(void) {
    for (UIView *view in WCLiquidGlassMessageSwipeCells.allObjects) {
        WCLiquidGlassMessageSwipeSetup(view);
    }
}

void WCLiquidGlassInstallMessageSwipeHooks(void) {
    if (WCLiquidGlassMessageSwipeHooksInstalled) {
        return;
    }
    Class cellClass = NSClassFromString(@"CommonMessageCellView");
    if (!cellClass || !class_getInstanceMethod(cellClass, @selector(didMoveToWindow))) {
        if (!WCLiquidGlassMessageSwipeHookRetryScheduled && WCLiquidGlassMessageSwipeHookAttempts < 5) {
            WCLiquidGlassMessageSwipeHookRetryScheduled = YES;
            WCLiquidGlassMessageSwipeHookAttempts += 1;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                WCLiquidGlassMessageSwipeHookRetryScheduled = NO;
                WCLiquidGlassInstallMessageSwipeHooks();
            });
        }
        return;
    }

    WCLiquidGlassMessageSwipeHooksInstalled = YES;
    WCLiquidGlassMessageSwipeCells = [NSHashTable weakObjectsHashTable];
    class_addMethod(cellClass,
                    NSSelectorFromString(@"wclg_handleMessageSwipe:"),
                    (IMP)&WCLiquidGlassMessageSwipeHandle,
                    "v@:@");
    MSHookMessageEx(cellClass,
                    @selector(didMoveToWindow),
                    (IMP)&WCLiquidGlassMessageSwipeCommonMessageCellDidMoveToWindow,
                    (IMP *)&WCLiquidGlassOriginalCommonMessageCellDidMoveToWindow);
    MSHookMessageEx(cellClass,
                    @selector(gestureRecognizerShouldBegin:),
                    (IMP)&WCLiquidGlassMessageSwipeGestureRecognizerShouldBegin,
                    (IMP *)&WCLiquidGlassOriginalGestureRecognizerShouldBegin);
    MSHookMessageEx(cellClass,
                    @selector(gestureRecognizer:shouldRecognizeSimultaneouslyWithGestureRecognizer:),
                    (IMP)&WCLiquidGlassMessageSwipeShouldRecognizeSimultaneously,
                    (IMP *)&WCLiquidGlassOriginalShouldRecognizeSimultaneously);
    MSHookMessageEx(cellClass,
                    @selector(gestureRecognizer:shouldRequireFailureOfGestureRecognizer:),
                    (IMP)&WCLiquidGlassMessageSwipeShouldRequireFailure,
                    (IMP *)&WCLiquidGlassOriginalShouldRequireFailure);
    [NSNotificationCenter.defaultCenter addObserverForName:WCLiquidGlassPreferencesDidChangeNotification
                                                    object:nil
                                                     queue:NSOperationQueue.mainQueue
                                                usingBlock:^(__unused NSNotification *notification) {
        WCLiquidGlassMessageSwipeRefresh();
    }];
}
