#import "WCLiquidGlassMessageSwipe.h"

#import <CydiaSubstrate.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "WCLiquidGlassPreferences.h"

static const void *WCLiquidGlassMessageSwipeControllerKey =
    &WCLiquidGlassMessageSwipeControllerKey;
static void (*WCLiquidGlassOriginalCommonMessageCellDidMoveToWindow)(id, SEL) = NULL;
static BOOL WCLiquidGlassMessageSwipeHooksInstalled = NO;
static BOOL WCLiquidGlassMessageSwipeHookRetryScheduled = NO;
static NSUInteger WCLiquidGlassMessageSwipeHookAttempts = 0;

@class WCLiquidGlassMessageSwipeController;
static NSHashTable<WCLiquidGlassMessageSwipeController *> *WCLiquidGlassMessageSwipeControllers;

static Class WCLiquidGlassMessageSwipeUtilities(void) {
    return NSClassFromString(@"WCHookSwipeUtilities");
}

static UITableViewCell *WCLiquidGlassMessageSwipeEnclosingTableCell(UIView *view) {
    for (UIView *candidate = view; candidate; candidate = candidate.superview) {
        if ([candidate isKindOfClass:UITableViewCell.class]) {
            return (UITableViewCell *)candidate;
        }
    }
    return nil;
}

static NSArray<UIView *> *WCLiquidGlassMessageSwipeRelatedViews(UIView *cell) {
    Class utilities = WCLiquidGlassMessageSwipeUtilities();
    SEL selector = NSSelectorFromString(@"relatedMessageViewsForCommonView:");
    if ([utilities respondsToSelector:selector]) {
        @try {
            NSArray *views = ((id (*)(id, SEL, id))objc_msgSend)(utilities, selector, cell);
            if ([views isKindOfClass:NSArray.class] && views.count > 0) {
                return views;
            }
        } @catch (__unused NSException *exception) {
        }
    }
    UITableViewCell *tableCell = WCLiquidGlassMessageSwipeEnclosingTableCell(cell);
    return tableCell.contentView.subviews.count > 0 ? tableCell.contentView.subviews : (cell ? @[cell] : @[]);
}

static CGFloat WCLiquidGlassMessageSwipeThreshold(UIView *cell) {
    Class utilities = WCLiquidGlassMessageSwipeUtilities();
    SEL selector = NSSelectorFromString(@"thresholdForView:");
    if ([utilities respondsToSelector:selector]) {
        return ((CGFloat (*)(id, SEL, id))objc_msgSend)(utilities, selector, cell);
    }
    return MAX(CGRectGetWidth(cell.bounds) * 0.18, 44.0);
}

static BOOL WCLiquidGlassMessageSwipeShouldIgnore(CGPoint translation) {
    Class utilities = WCLiquidGlassMessageSwipeUtilities();
    SEL selector = NSSelectorFromString(@"shouldIgnoreTranslation:");
    if ([utilities respondsToSelector:selector]) {
        return ((BOOL (*)(id, SEL, CGPoint))objc_msgSend)(utilities, selector, translation);
    }
    return translation.x > 0.0 && fabs(translation.y) <= fabs(translation.x) * 0.7;
}

static BOOL WCLiquidGlassMessageSwipeVelocityEligible(CGPoint velocity) {
    Class utilities = WCLiquidGlassMessageSwipeUtilities();
    SEL selector = NSSelectorFromString(@"isVelocityEligible:");
    if ([utilities respondsToSelector:selector]) {
        return ((BOOL (*)(id, SEL, CGPoint))objc_msgSend)(utilities, selector, velocity);
    }
    return velocity.x < 0.0 && fabs(velocity.x) >= fabs(velocity.y) * 1.3;
}

static CGFloat WCLiquidGlassMessageSwipeClampedTranslation(CGFloat translation, CGFloat threshold) {
    Class utilities = WCLiquidGlassMessageSwipeUtilities();
    SEL selector = NSSelectorFromString(@"clampedTranslation:threshold:");
    if ([utilities respondsToSelector:selector]) {
        return ((CGFloat (*)(id, SEL, CGFloat, CGFloat))objc_msgSend)(utilities,
                                                                     selector,
                                                                     translation,
                                                                     threshold);
    }
    return MIN(MAX(-translation, 0.0), threshold);
}

static BOOL WCLiquidGlassMessageSwipeShouldTrigger(CGPoint translation,
                                                   CGPoint velocity,
                                                   CGFloat threshold) {
    Class utilities = WCLiquidGlassMessageSwipeUtilities();
    SEL selector = NSSelectorFromString(@"shouldTriggerWithTranslation:velocity:threshold:");
    if ([utilities respondsToSelector:selector]) {
        return ((BOOL (*)(id, SEL, CGPoint, CGPoint, CGFloat))objc_msgSend)(utilities,
                                                                           selector,
                                                                           translation,
                                                                           velocity,
                                                                           threshold);
    }
    return translation.x <= -threshold || velocity.x <= -600.0;
}

static void WCLiquidGlassMessageSwipeApplyTransform(CGAffineTransform transform,
                                                    NSArray<UIView *> *views) {
    Class utilities = WCLiquidGlassMessageSwipeUtilities();
    SEL selector = NSSelectorFromString(@"applyTransform:toViews:");
    if ([utilities respondsToSelector:selector]) {
        ((void (*)(id, SEL, CGAffineTransform, id))objc_msgSend)(utilities, selector, transform, views);
        return;
    }
    for (UIView *view in views) {
        view.transform = transform;
    }
}

static void WCLiquidGlassMessageSwipeResetViews(NSArray<UIView *> *views, BOOL animated) {
    Class utilities = WCLiquidGlassMessageSwipeUtilities();
    SEL selector = NSSelectorFromString(@"animateResetForViews:animated:");
    if ([utilities respondsToSelector:selector]) {
        ((void (*)(id, SEL, id, BOOL))objc_msgSend)(utilities, selector, views, animated);
        return;
    }
    void (^reset)(void) = ^{
        for (UIView *view in views) {
            view.transform = CGAffineTransformIdentity;
        }
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

@interface WCLiquidGlassMessageSwipeController : NSObject <UIGestureRecognizerDelegate>
@property(nonatomic, weak) UIView *cell;
@property(nonatomic, strong) UIPanGestureRecognizer *panGesture;
@property(nonatomic, strong) UIImpactFeedbackGenerator *feedbackGenerator;
@property(nonatomic) BOOL feedbackTriggered;
@property(nonatomic, weak) UIGestureRecognizer *wcHookGesture;
@property(nonatomic) BOOL wcHookGestureEnabled;
@property(nonatomic) BOOL wcHookGestureWasDisabled;
@end

@implementation WCLiquidGlassMessageSwipeController

- (instancetype)initWithCell:(UIView *)cell {
    self = [super init];
    if (self) {
        _cell = cell;
        _panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(wc_handlePan:)];
        _panGesture.minimumNumberOfTouches = 1;
        _panGesture.maximumNumberOfTouches = 1;
        _panGesture.cancelsTouchesInView = YES;
        _panGesture.delaysTouchesBegan = NO;
        _panGesture.delaysTouchesEnded = NO;
        _panGesture.delegate = self;
        [cell addGestureRecognizer:_panGesture];
        _feedbackGenerator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    }
    return self;
}

- (void)wc_restoreWCCHookGesture {
    if (self.wcHookGestureWasDisabled && self.wcHookGesture) {
        self.wcHookGesture.enabled = self.wcHookGestureEnabled;
    }
    self.wcHookGesture = nil;
    self.wcHookGestureWasDisabled = NO;
}

- (void)wc_updateWCCHookGesture {
    UIView *cell = self.cell;
    SEL selector = NSSelectorFromString(@"wchook_swipeGesture");
    if (!WCLiquidGlassPreferences.messageSwipeActionsEnabled || !cell || ![cell respondsToSelector:selector]) {
        [self wc_restoreWCCHookGesture];
        return;
    }
    UIGestureRecognizer *gesture = nil;
    @try {
        gesture = ((id (*)(id, SEL))objc_msgSend)(cell, selector);
    } @catch (__unused NSException *exception) {
    }
    if (![gesture isKindOfClass:UIGestureRecognizer.class]) {
        [self wc_restoreWCCHookGesture];
        return;
    }
    if (gesture != self.wcHookGesture) {
        [self wc_restoreWCCHookGesture];
        self.wcHookGesture = gesture;
        self.wcHookGestureEnabled = gesture.enabled;
        self.wcHookGestureWasDisabled = YES;
    }
    gesture.enabled = NO;
}

- (void)wc_refresh {
    BOOL enabled = WCLiquidGlassPreferences.messageSwipeActionsEnabled && self.cell.window != nil;
    self.panGesture.enabled = enabled;
    if (enabled) {
        [self wc_updateWCCHookGesture];
    } else {
        WCLiquidGlassMessageSwipeResetViews(WCLiquidGlassMessageSwipeRelatedViews(self.cell), NO);
        self.feedbackTriggered = NO;
        [self wc_restoreWCCHookGesture];
    }
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer != self.panGesture || !WCLiquidGlassPreferences.messageSwipeActionsEnabled) {
        return NO;
    }
    return WCLiquidGlassMessageSwipeVelocityEligible([(UIPanGestureRecognizer *)gestureRecognizer velocityInView:self.cell]);
}

- (BOOL)gestureRecognizer:(__unused UIGestureRecognizer *)gestureRecognizer
shouldRecognizeSimultaneouslyWithGestureRecognizer:(__unused UIGestureRecognizer *)otherGestureRecognizer {
    return NO;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
shouldRequireFailureOfGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return gestureRecognizer == self.panGesture && [otherGestureRecognizer isKindOfClass:UITapGestureRecognizer.class];
}

- (void)wc_triggerFeedback {
    if (self.feedbackTriggered) {
        return;
    }
    [self.feedbackGenerator impactOccurred];
    self.feedbackTriggered = YES;
}

- (void)wc_triggerQuoteReply {
    UIView *cell = self.cell;
    SEL selector = NSSelectorFromString(@"onShowMsgReplyMenuItem:");
    if (![cell respondsToSelector:selector]) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            ((void (*)(id, SEL, id))objc_msgSend)(cell, selector, nil);
        } @catch (__unused NSException *exception) {
        }
    });
}

- (void)wc_handlePan:(UIPanGestureRecognizer *)pan {
    NSArray<UIView *> *views = WCLiquidGlassMessageSwipeRelatedViews(self.cell);
    CGPoint translation = [pan translationInView:self.cell];
    CGPoint velocity = [pan velocityInView:self.cell];
    if (WCLiquidGlassMessageSwipeShouldIgnore(translation)) {
        WCLiquidGlassMessageSwipeApplyTransform(CGAffineTransformIdentity, views);
        if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
            WCLiquidGlassMessageSwipeResetViews(views, YES);
        }
        return;
    }
    CGFloat threshold = WCLiquidGlassMessageSwipeThreshold(self.cell);
    if (pan.state == UIGestureRecognizerStateBegan) {
        [self.feedbackGenerator prepare];
        self.feedbackTriggered = NO;
        return;
    }
    if (pan.state == UIGestureRecognizerStateChanged) {
        CGFloat distance = WCLiquidGlassMessageSwipeClampedTranslation(translation.x, threshold);
        WCLiquidGlassMessageSwipeApplyTransform(CGAffineTransformMakeTranslation(-distance, 0.0), views);
        if (!self.feedbackTriggered && translation.x <= -threshold) {
            [self wc_triggerFeedback];
        }
        return;
    }
    if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        if (WCLiquidGlassMessageSwipeShouldTrigger(translation, velocity, threshold)) {
            [self wc_triggerFeedback];
            [self wc_triggerQuoteReply];
        }
        WCLiquidGlassMessageSwipeResetViews(views, YES);
        return;
    }
    if (pan.state == UIGestureRecognizerStateFailed) {
        WCLiquidGlassMessageSwipeResetViews(views, NO);
        self.feedbackTriggered = NO;
    }
}

@end

static void WCLiquidGlassMessageSwipeConfigureCell(UIView *cell) {
    WCLiquidGlassMessageSwipeController *controller =
        objc_getAssociatedObject(cell, WCLiquidGlassMessageSwipeControllerKey);
    if (!controller) {
        controller = [[WCLiquidGlassMessageSwipeController alloc] initWithCell:cell];
        objc_setAssociatedObject(cell,
                                 WCLiquidGlassMessageSwipeControllerKey,
                                 controller,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [WCLiquidGlassMessageSwipeControllers addObject:controller];
    }
    [controller wc_refresh];
}

static void WCLiquidGlassMessageSwipeCommonMessageCellDidMoveToWindow(id self, SEL selector) {
    if (WCLiquidGlassOriginalCommonMessageCellDidMoveToWindow) {
        WCLiquidGlassOriginalCommonMessageCellDidMoveToWindow(self, selector);
    }
    WCLiquidGlassMessageSwipeConfigureCell(self);
    __weak UIView *cell = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (cell) {
            WCLiquidGlassMessageSwipeConfigureCell(cell);
        }
    });
}

static void WCLiquidGlassMessageSwipeRefresh(void) {
    for (WCLiquidGlassMessageSwipeController *controller in WCLiquidGlassMessageSwipeControllers.allObjects) {
        [controller wc_refresh];
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
    WCLiquidGlassMessageSwipeControllers = [NSHashTable weakObjectsHashTable];
    MSHookMessageEx(cellClass,
                    @selector(didMoveToWindow),
                    (IMP)&WCLiquidGlassMessageSwipeCommonMessageCellDidMoveToWindow,
                    (IMP *)&WCLiquidGlassOriginalCommonMessageCellDidMoveToWindow);
    [NSNotificationCenter.defaultCenter addObserverForName:WCLiquidGlassPreferencesDidChangeNotification
                                                    object:nil
                                                     queue:NSOperationQueue.mainQueue
                                                usingBlock:^(__unused NSNotification *notification) {
        WCLiquidGlassMessageSwipeRefresh();
    }];
}
