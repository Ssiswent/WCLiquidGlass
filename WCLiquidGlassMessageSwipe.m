#import "WCLiquidGlassMessageSwipe.h"

#import <CydiaSubstrate.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "WCLiquidGlassCrashLogger.h"
#import "WCLiquidGlassMenu.h"
#import "WCLiquidGlassPreferences.h"

static const void *WCLiquidGlassMessageSwipeGestureKey = &WCLiquidGlassMessageSwipeGestureKey;
static const void *WCLiquidGlassMessageSwipeFeedbackKey = &WCLiquidGlassMessageSwipeFeedbackKey;
static const void *WCLiquidGlassMessageSwipeFeedbackTriggeredKey = &WCLiquidGlassMessageSwipeFeedbackTriggeredKey;
static const void *WCLiquidGlassMessageSwipeMenuAnchorKey = &WCLiquidGlassMessageSwipeMenuAnchorKey;
static void (*WCLiquidGlassOriginalCommonMessageCellDidMoveToWindow)(id, SEL) = NULL;
static BOOL (*WCLiquidGlassOriginalGestureRecognizerShouldBegin)(id, SEL, UIGestureRecognizer *) = NULL;
static BOOL WCLiquidGlassMessageSwipeHooksInstalled = NO;
static BOOL WCLiquidGlassMessageSwipeHookRetryScheduled = NO;
static NSUInteger WCLiquidGlassMessageSwipeHookAttempts = 0;
static NSHashTable<UIView *> *WCLiquidGlassMessageSwipeCells;

static void WCLiquidGlassMessageSwipeRecord(NSString *event) {
    [WCLiquidGlassCrashLogger.sharedLogger recordEvent:[@"MessageSwipe " stringByAppendingString:event]];
}

static void WCLiquidGlassMessageSwipeRecordThrottled(NSString *key, NSString *event) {
    static NSMutableDictionary<NSString *, NSDate *> *lastRecordDates;
    if (!lastRecordDates) {
        lastRecordDates = [NSMutableDictionary dictionary];
    }
    NSDate *lastDate = lastRecordDates[key];
    if (lastDate && -lastDate.timeIntervalSinceNow < 1.5) {
        return;
    }
    lastRecordDates[key] = NSDate.date;
    WCLiquidGlassMessageSwipeRecord(event);
}

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

static id WCLiquidGlassMessageSwipeService(Class serviceClass) {
    Class serviceCenterClass = NSClassFromString(@"MMServiceCenter");
    SEL defaultCenterSelector = NSSelectorFromString(@"defaultCenter");
    SEL getServiceSelector = NSSelectorFromString(@"getService:");
    if (!serviceClass || ![serviceCenterClass respondsToSelector:defaultCenterSelector]) {
        return nil;
    }
    id serviceCenter = ((id (*)(id, SEL))objc_msgSend)(serviceCenterClass, defaultCenterSelector);
    return [serviceCenter respondsToSelector:getServiceSelector]
        ? ((id (*)(id, SEL, Class))objc_msgSend)(serviceCenter, getServiceSelector, serviceClass)
        : nil;
}

static BOOL WCLiquidGlassMessageSwipeRepeat(id messageWrap) {
    @try {
        id contactManager = WCLiquidGlassMessageSwipeService(NSClassFromString(@"CContactMgr"));
        id selfContact = [contactManager respondsToSelector:NSSelectorFromString(@"getSelfContact")]
            ? ((id (*)(id, SEL))objc_msgSend)(contactManager, NSSelectorFromString(@"getSelfContact"))
            : nil;
        NSString *selfUserName = WCLiquidGlassMessageSwipeValue(selfContact, @"m_nsUsrName")
            ?: WCLiquidGlassMessageSwipeValue(selfContact, @"m_nsUserName")
            ?: WCLiquidGlassMessageSwipeValue(selfContact, @"userName");
        NSString *fromUserName = WCLiquidGlassMessageSwipeValue(messageWrap, @"m_nsFromUsr");
        NSString *toUserName = WCLiquidGlassMessageSwipeValue(messageWrap, @"m_nsToUsr");
        NSString *targetUserName = [fromUserName isEqualToString:selfUserName] ? toUserName : fromUserName;
        SEL contactSelector = NSSelectorFromString(@"getContactByName:");
        id targetContact = targetUserName.length > 0 && [contactManager respondsToSelector:contactSelector]
            ? ((id (*)(id, SEL, id))objc_msgSend)(contactManager, contactSelector, targetUserName)
            : nil;
        Class logicClass = NSClassFromString(@"ForwardMessageLogicController");
        id logic = targetContact && logicClass ? [logicClass new] : nil;
        if (!logic) {
            return NO;
        }
        if ([logic respondsToSelector:NSSelectorFromString(@"setBShowSendSuccessView:")]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(logic, NSSelectorFromString(@"setBShowSendSuccessView:"), NO);
        }
        if ([logic respondsToSelector:NSSelectorFromString(@"setBHiddenSendSuccessToastView:")]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(logic, NSSelectorFromString(@"setBHiddenSendSuccessToastView:"), YES);
        }
        SEL forwardSelector = NSSelectorFromString(@"ForwardMsg:ToContact:");
        if ([logic respondsToSelector:forwardSelector]) {
            ((void (*)(id, SEL, id, id))objc_msgSend)(logic, forwardSelector, messageWrap, targetContact);
            return YES;
        }
        forwardSelector = NSSelectorFromString(@"ForwardMsg:ToContact:NeedSrcInfo:");
        if ([logic respondsToSelector:forwardSelector]) {
            ((void (*)(id, SEL, id, id, BOOL))objc_msgSend)(logic,
                                                           forwardSelector,
                                                           messageWrap,
                                                           targetContact,
                                                           NO);
            return YES;
        }
    } @catch (__unused NSException *exception) {
    }
    return NO;
}

static UIMenuElementSize WCLiquidGlassMessageSwipeNativeMenuElementSize(void) {
    switch (WCLiquidGlassPreferences.messageSwipeMenuElementSize) {
        case WCLiquidGlassMenuElementSizeSmall:
            return UIMenuElementSizeSmall;
        case WCLiquidGlassMenuElementSizeMedium:
            return UIMenuElementSizeMedium;
        case WCLiquidGlassMenuElementSizeLarge:
            return UIMenuElementSizeLarge;
        default:
            if (@available(iOS 17.0, *)) {
                return UIMenuElementSizeAutomatic;
            }
            return UIMenuElementSizeLarge;
    }
}

static UIMenu *WCLiquidGlassMessageSwipeNativeMenu(UIView *cell, id messageWrap, UIViewController *chatController) {
    __weak UIView *weakCell = cell;
    __weak UIViewController *weakChatController = chatController;
    UIImage *quoteImage = WCLiquidGlassImageNamedFromCandidates(@[@"icons_filled_quote"])
        ?: [UIImage systemImageNamed:@"arrowshape.turn.up.left"];
    UIImage *forwardImage = WCLiquidGlassImageNamedFromCandidates(@[@"share_filled", @"icons_filled_share"])
        ?: [UIImage systemImageNamed:@"arrowshape.turn.up.right"];
    UIImage *repeatImage = WCLiquidGlassImageNamedFromCandidates(@[@"icons_outlined_addoutline", @"icons_filled_add"])
        ?: [UIImage systemImageNamed:@"repeat"];
    UIAction *quoteAction = [UIAction actionWithTitle:@"引用"
                                               image:quoteImage
                                          identifier:nil
                                             handler:^(__unused UIAction *action) {
        UIView *strongCell = weakCell;
        SEL quoteSelector = NSSelectorFromString(@"onShowMsgReplyMenuItem:");
        if ([strongCell respondsToSelector:quoteSelector]) {
            ((void (*)(id, SEL, id))objc_msgSend)(strongCell, quoteSelector, nil);
            return;
        }
        SEL replySelector = NSSelectorFromString(@"onReplyMsg:");
        if ([weakChatController respondsToSelector:replySelector]) {
            ((void (*)(id, SEL, id))objc_msgSend)(weakChatController, replySelector, messageWrap);
        }
    }];
    UIAction *repeatAction = [UIAction actionWithTitle:@"复读"
                                                image:repeatImage
                                           identifier:nil
                                              handler:^(__unused UIAction *action) {
        WCLiquidGlassMessageSwipeRepeat(messageWrap);
    }];
    UIAction *forwardAction = [UIAction actionWithTitle:@"转发"
                                                 image:forwardImage
                                            identifier:nil
                                               handler:^(__unused UIAction *action) {
        UIView *strongCell = weakCell;
        SEL forwardSelector = NSSelectorFromString(@"onForward:");
        if ([strongCell respondsToSelector:forwardSelector]) {
            ((void (*)(id, SEL, id))objc_msgSend)(strongCell, forwardSelector, nil);
        }
    }];
    UIMenu *menu = [UIMenu menuWithTitle:@"" children:@[quoteAction, forwardAction, repeatAction]];
    if (@available(iOS 16.0, *)) {
        menu.preferredElementSize = WCLiquidGlassMessageSwipeNativeMenuElementSize();
    }
    return menu;
}

static void WCLiquidGlassMessageSwipeRemoveMenuAnchor(UIView *view) {
    [objc_getAssociatedObject(view, WCLiquidGlassMessageSwipeMenuAnchorKey) removeFromSuperview];
    objc_setAssociatedObject(view,
                             WCLiquidGlassMessageSwipeMenuAnchorKey,
                             nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static UIContextMenuInteraction *WCLiquidGlassMessageSwipeMenuInteractionInView(UIView *view) {
    for (id<UIInteraction> interaction in view.interactions) {
        if ([interaction isKindOfClass:UIContextMenuInteraction.class]) {
            return (UIContextMenuInteraction *)interaction;
        }
    }
    for (UIView *subview in view.subviews) {
        UIContextMenuInteraction *interaction = WCLiquidGlassMessageSwipeMenuInteractionInView(subview);
        if (interaction) {
            return interaction;
        }
    }
    return nil;
}

static BOOL WCLiquidGlassMessageSwipePresentMenuFromToolbar(UIView *view, UIToolbar *toolbar) {
    UIContextMenuInteraction *interaction = WCLiquidGlassMessageSwipeMenuInteractionInView(toolbar);
    UIView *sourceView = interaction.view;
    if (!interaction || !view.window || !toolbar.window || !sourceView.window ||
        view.window != toolbar.window || toolbar.window != sourceView.window) {
        return NO;
    }
    SEL presentSelector = NSSelectorFromString(@"_presentMenuAtLocation:");
    NSMethodSignature *signature = [interaction respondsToSelector:presentSelector]
        ? [interaction methodSignatureForSelector:presentSelector]
        : nil;
    const char *argumentType = signature.numberOfArguments == 3
        ? [signature getArgumentTypeAtIndex:2]
        : NULL;
    const char *returnType = signature.methodReturnType;
    if (!signature || !argumentType || !returnType || strcmp(argumentType, @encode(CGPoint)) != 0 ||
        returnType[0] != 'v' || signature.methodReturnLength != 0) {
        return NO;
    }
    @try {
        CGPoint location = CGPointMake(CGRectGetMidX(sourceView.bounds), CGRectGetMidY(sourceView.bounds));
        ((void (*)(id, SEL, CGPoint))objc_msgSend)(interaction, presentSelector, location);
    } @catch (__unused NSException *exception) {
        return NO;
    }
    return YES;
}

static void WCLiquidGlassMessageSwipeTriggerActionMenu(UIView *view) {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            id viewModel = WCLiquidGlassMessageSwipeValue(view, @"viewModel");
            id messageWrap = WCLiquidGlassMessageSwipeValue(viewModel, @"messageWrap");
            WCLiquidGlassMessageSwipeRecord([NSString stringWithFormat:@"trigger cell=%@ viewModel=%@ messageWrap=%@",
                                                                       NSStringFromClass(view.class),
                                                                       viewModel ? NSStringFromClass([viewModel class]) : @"nil",
                                                                       messageWrap ? NSStringFromClass([messageWrap class]) : @"nil"]);
            if (messageWrap) {
                WCLiquidGlassMessageSwipeRemoveMenuAnchor(view);
                UIResponder *responder = view;
                UIViewController *chatController = nil;
                while ((responder = responder.nextResponder)) {
                    if ([responder isKindOfClass:UIViewController.class]) {
                        chatController = (UIViewController *)responder;
                        break;
                    }
                }
                UIToolbar *toolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0.0, 0.0, 56.0, 56.0)];
                toolbar.center = CGPointMake(CGRectGetMidX(view.bounds), CGRectGetMidY(view.bounds));
                toolbar.alpha = 0.01;
                toolbar.accessibilityElementsHidden = YES;
                toolbar.items = @[[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis"]
                                                                     menu:WCLiquidGlassMessageSwipeNativeMenu(view, messageWrap, chatController)]];
                [view addSubview:toolbar];
                objc_setAssociatedObject(view,
                                         WCLiquidGlassMessageSwipeMenuAnchorKey,
                                         toolbar,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                [view setNeedsLayout];
                [view layoutIfNeeded];
                [toolbar setNeedsLayout];
                [toolbar layoutIfNeeded];
                if (!WCLiquidGlassMessageSwipePresentMenuFromToolbar(view, toolbar)) {
                    __weak UIView *weakView = view;
                    __weak UIToolbar *weakToolbar = toolbar;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        UIView *strongView = weakView;
                        UIToolbar *strongToolbar = weakToolbar;
                        if (strongView && strongToolbar &&
                            objc_getAssociatedObject(strongView, WCLiquidGlassMessageSwipeMenuAnchorKey) == strongToolbar) {
                            if (WCLiquidGlassMessageSwipePresentMenuFromToolbar(strongView, strongToolbar)) {
                                strongToolbar.userInteractionEnabled = NO;
                            } else {
                                WCLiquidGlassMessageSwipeRemoveMenuAnchor(strongView);
                            }
                        }
                    });
                } else {
                    toolbar.userInteractionEnabled = NO;
                }
                return;
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
            WCLiquidGlassMessageSwipeRecord([NSString stringWithFormat:@"end cell=%@ state=%ld translation=(%.0f,%.0f) velocity=(%.0f,%.0f) threshold=%.0f",
                                                                       NSStringFromClass(view.class),
                                                                       (long)gesture.state,
                                                                       translation.x,
                                                                       translation.y,
                                                                       velocity.x,
                                                                       velocity.y,
                                                                       threshold]);
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

static NSString *WCLiquidGlassMessageSwipeClassChain(Class cls) {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    Class baseClass = NSClassFromString(@"CommonMessageCellView");
    for (Class current = cls; current; current = class_getSuperclass(current)) {
        [names addObject:NSStringFromClass(current)];
        if (current == baseClass || names.count >= 6) {
            break;
        }
    }
    return [names componentsJoinedByString:@">"];
}

static NSString *WCLiquidGlassMessageSwipeGestureSummary(UIGestureRecognizer *recognizer) {
    NSString *delegateName = recognizer.delegate ? NSStringFromClass([(NSObject *)recognizer.delegate class]) : @"nil";
    return [NSString stringWithFormat:@"%@(enabled=%d state=%ld delegate=%@)",
                                      NSStringFromClass(recognizer.class),
                                      recognizer.enabled,
                                      (long)recognizer.state,
                                      delegateName];
}

static NSString *WCLiquidGlassMessageSwipeTouchSummary(UIView *cell, UIView *touchView) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSUInteger depth = 0;
    for (UIView *view = touchView; view && depth < 8; view = view.superview, depth += 1) {
        NSMutableArray<NSString *> *gestures = [NSMutableArray array];
        for (UIGestureRecognizer *recognizer in view.gestureRecognizers) {
            if (recognizer != WCLiquidGlassMessageSwipeGesture(cell)) {
                [gestures addObject:WCLiquidGlassMessageSwipeGestureSummary(recognizer)];
            }
        }
        [parts addObject:[NSString stringWithFormat:@"%@[%@]",
                                                    NSStringFromClass(view.class),
                                                    [gestures componentsJoinedByString:@","]]];
        if (view == cell) {
            break;
        }
    }
    return [parts componentsJoinedByString:@" < "];
}

@interface WCLiquidGlassMessageSwipeGestureDelegate : NSObject <UIGestureRecognizerDelegate>
@end

@implementation WCLiquidGlassMessageSwipeGestureDelegate

+ (instancetype)sharedDelegate {
    static WCLiquidGlassMessageSwipeGestureDelegate *delegate;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        delegate = [self new];
    });
    return delegate;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    UIView *cell = gestureRecognizer.view;
    WCLiquidGlassMessageSwipeRecordThrottled([@"touch." stringByAppendingString:NSStringFromClass(cell.class)],
                                             [NSString stringWithFormat:@"touch cell=%@ chain=%@",
                                                               WCLiquidGlassMessageSwipeClassChain(cell.class),
                                                               WCLiquidGlassMessageSwipeTouchSummary(cell, touch.view)]);
    return YES;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (!WCLiquidGlassPreferences.messageSwipeActionsEnabled) {
        return NO;
    }
    UIView *cell = gestureRecognizer.view;
    CGPoint velocity = [(UIPanGestureRecognizer *)gestureRecognizer velocityInView:cell];
    BOOL eligible = WCLiquidGlassMessageSwipeVelocityEligible(velocity);
    WCLiquidGlassMessageSwipeRecord([NSString stringWithFormat:@"shouldBegin cell=%@ velocity=(%.0f,%.0f) result=%d",
                                                               NSStringFromClass(cell.class),
                                                               velocity.x,
                                                               velocity.y,
                                                               eligible]);
    return eligible;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
    shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return NO;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
    shouldRequireFailureOfGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return [otherGestureRecognizer isKindOfClass:UITapGestureRecognizer.class];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
    shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if ([otherGestureRecognizer isKindOfClass:UITapGestureRecognizer.class]) {
        return NO;
    }
    WCLiquidGlassMessageSwipeRecordThrottled([NSString stringWithFormat:@"competing.%@.%@",
                                                                        NSStringFromClass(gestureRecognizer.view.class),
                                                                        NSStringFromClass(otherGestureRecognizer.class)],
                                             [NSString stringWithFormat:@"competing cell=%@ other=%@ otherView=%@",
                                                               NSStringFromClass(gestureRecognizer.view.class),
                                                               WCLiquidGlassMessageSwipeGestureSummary(otherGestureRecognizer),
                                                               NSStringFromClass(otherGestureRecognizer.view.class)]);
    return NO;
}

@end

static void WCLiquidGlassMessageSwipeSetup(UIView *view);
static void WCLiquidGlassMessageSwipeInstallClassHooks(Class cls);

static void WCLiquidGlassMessageSwipeRecordClassIfNeeded(UIView *view) {
    static NSMutableSet<NSString *> *recordedClasses;
    if (!recordedClasses) {
        recordedClasses = [NSMutableSet set];
    }
    NSString *className = NSStringFromClass(view.class);
    if ([recordedClasses containsObject:className]) {
        return;
    }
    [recordedClasses addObject:className];
    WCLiquidGlassMessageSwipeRecord([NSString stringWithFormat:@"attach class=%@ gestures=%lu",
                                                               WCLiquidGlassMessageSwipeClassChain(view.class),
                                                               (unsigned long)view.gestureRecognizers.count]);
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
        WCLiquidGlassMessageSwipeInstallClassHooks(view.class);
        gesture = [[UIPanGestureRecognizer alloc] initWithTarget:view action:NSSelectorFromString(@"wclg_handleMessageSwipe:")];
        gesture.minimumNumberOfTouches = 1;
        gesture.maximumNumberOfTouches = 1;
        gesture.cancelsTouchesInView = YES;
        gesture.delaysTouchesBegan = NO;
        gesture.delaysTouchesEnded = NO;
        gesture.delegate = WCLiquidGlassMessageSwipeGestureDelegate.sharedDelegate;
        [view addGestureRecognizer:gesture];
        objc_setAssociatedObject(view,
                                 WCLiquidGlassMessageSwipeGestureKey,
                                 gesture,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        WCLiquidGlassMessageSwipeRecordClassIfNeeded(view);
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
        WCLiquidGlassMessageSwipeRemoveMenuAnchor(view);
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
        return YES;
    }
    return WCLiquidGlassOriginalGestureRecognizerShouldBegin
        ? WCLiquidGlassOriginalGestureRecognizerShouldBegin(self, selector, gestureRecognizer)
        : YES;
}

static BOOL WCLiquidGlassMessageSwipeClassDefinesMethod(Class cls, SEL selector) {
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    BOOL found = NO;
    for (unsigned int index = 0; index < count && !found; index++) {
        found = method_getName(methods[index]) == selector;
    }
    free(methods);
    return found;
}

static NSMutableSet<NSString *> *WCLiquidGlassMessageSwipeHookedClasses(void) {
    static NSMutableSet<NSString *> *classes;
    if (!classes) {
        classes = [NSMutableSet set];
    }
    return classes;
}

static NSUInteger WCLiquidGlassMessageSwipeHookClassIfNeeded(Class cls) {
    NSString *className = NSStringFromClass(cls);
    NSMutableSet<NSString *> *hookedClasses = WCLiquidGlassMessageSwipeHookedClasses();
    if ([hookedClasses containsObject:className]) {
        return 0;
    }
    [hookedClasses addObject:className];

    NSUInteger hookCount = 0;
    SEL moveSelector = @selector(didMoveToWindow);
    if (WCLiquidGlassMessageSwipeClassDefinesMethod(cls, moveSelector)) {
        IMP *original = calloc(1, sizeof(IMP));
        IMP replacement = imp_implementationWithBlock(^(UIView *view) {
            if (*original) {
                ((void (*)(id, SEL))*original)(view, moveSelector);
            }
            WCLiquidGlassMessageSwipeSetup(view);
        });
        MSHookMessageEx(cls, moveSelector, replacement, original);
        hookCount += 1;
    }

    SEL beginSelector = @selector(gestureRecognizerShouldBegin:);
    if (WCLiquidGlassMessageSwipeClassDefinesMethod(cls, beginSelector)) {
        IMP *original = calloc(1, sizeof(IMP));
        IMP replacement = imp_implementationWithBlock(^BOOL(UIView *view, UIGestureRecognizer *gestureRecognizer) {
            if (gestureRecognizer == WCLiquidGlassMessageSwipeGesture(view)) {
                return YES;
            }
            return *original
                ? ((BOOL (*)(id, SEL, UIGestureRecognizer *))*original)(view, beginSelector, gestureRecognizer)
                : YES;
        });
        MSHookMessageEx(cls, beginSelector, replacement, original);
        hookCount += 1;
    }
    if (hookCount > 0) {
        WCLiquidGlassMessageSwipeRecord([NSString stringWithFormat:@"hooked class=%@ methods=%lu",
                                                                   WCLiquidGlassMessageSwipeClassChain(cls),
                                                                   (unsigned long)hookCount]);
    }
    return hookCount;
}

static void WCLiquidGlassMessageSwipeInstallClassHooks(Class cls) {
    Class baseClass = NSClassFromString(@"CommonMessageCellView");
    NSMutableArray<Class> *chain = [NSMutableArray array];
    for (Class current = cls; current; current = class_getSuperclass(current)) {
        [chain insertObject:current atIndex:0];
        if (current == baseClass) {
            break;
        }
    }
    for (Class current in chain) {
        WCLiquidGlassMessageSwipeHookClassIfNeeded(current);
    }
}

static void WCLiquidGlassMessageSwipeInstallSubclassHooks(Class baseClass) {
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    const char *imageName = class_getImageName(baseClass);
    unsigned int count = 0;
    const char **classNames = imageName ? objc_copyClassNamesForImage(imageName, &count) : NULL;
    NSUInteger subclassCount = 0;
    NSUInteger hookCount = 0;
    for (unsigned int index = 0; index < count; index++) {
        Class cls = objc_getClass(classNames[index]);
        if (!cls || cls == baseClass) {
            continue;
        }
        BOOL isSubclass = NO;
        for (Class current = class_getSuperclass(cls); current; current = class_getSuperclass(current)) {
            if (current == baseClass) {
                isSubclass = YES;
                break;
            }
        }
        if (!isSubclass) {
            continue;
        }
        subclassCount += 1;
        NSUInteger before = WCLiquidGlassMessageSwipeHookedClasses().count;
        WCLiquidGlassMessageSwipeInstallClassHooks(cls);
        hookCount += WCLiquidGlassMessageSwipeHookedClasses().count - before;
    }
    free(classNames);
    WCLiquidGlassMessageSwipeRecord([NSString stringWithFormat:@"install subclasses=%lu scanned=%u elapsed=%.1fms",
                                                               (unsigned long)subclassCount,
                                                               count,
                                                               (CFAbsoluteTimeGetCurrent() - start) * 1000.0]);
    (void)hookCount;
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
    [WCLiquidGlassMessageSwipeHookedClasses() addObject:NSStringFromClass(cellClass)];
    MSHookMessageEx(cellClass,
                    @selector(didMoveToWindow),
                    (IMP)&WCLiquidGlassMessageSwipeCommonMessageCellDidMoveToWindow,
                    (IMP *)&WCLiquidGlassOriginalCommonMessageCellDidMoveToWindow);
    MSHookMessageEx(cellClass,
                    @selector(gestureRecognizerShouldBegin:),
                    (IMP)&WCLiquidGlassMessageSwipeGestureRecognizerShouldBegin,
                    (IMP *)&WCLiquidGlassOriginalGestureRecognizerShouldBegin);
    WCLiquidGlassMessageSwipeInstallSubclassHooks(cellClass);
    [NSNotificationCenter.defaultCenter addObserverForName:WCLiquidGlassPreferencesDidChangeNotification
                                                    object:nil
                                                     queue:NSOperationQueue.mainQueue
                                                usingBlock:^(__unused NSNotification *notification) {
        WCLiquidGlassMessageSwipeRefresh();
    }];
}
