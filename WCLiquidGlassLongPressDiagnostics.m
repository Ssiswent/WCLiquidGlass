#import "WCLiquidGlassLongPressDiagnostics.h"

#import <CydiaSubstrate.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "WCLiquidGlassCrashLogger.h"

static const void *WCLiquidGlassLongPressDiagnosticSessionKey =
    &WCLiquidGlassLongPressDiagnosticSessionKey;
static void (*WCLiquidGlassOriginalDiagnosticVisualEffectDidMoveToWindow)(UIVisualEffectView *, SEL) = NULL;
static void (*WCLiquidGlassOriginalDiagnosticApplicationSendEvent)(UIApplication *, SEL, UIEvent *) = NULL;
static BOOL (*WCLiquidGlassOriginalDiagnosticApplicationSendAction)(UIApplication *, SEL, SEL, id, id, UIEvent *) = NULL;
static void (*WCLiquidGlassOriginalDiagnosticViewRemoveFromSuperview)(UIView *, SEL) = NULL;
static BOOL WCLiquidGlassLongPressDiagnosticsInstalled = NO;
static __weak UIView *WCLiquidGlassLongPressLatestTouchView = nil;
static __weak UIWindow *WCLiquidGlassLongPressLatestTouchWindow = nil;
static CGPoint WCLiquidGlassLongPressLatestTouchPoint;
static CFTimeInterval WCLiquidGlassLongPressLatestTouchTime = 0.0;
static NSUInteger WCLiquidGlassLongPressDiagnosticSequence = 0;

@interface WCLiquidGlassLongPressDiagnosticSession : NSObject

@property(nonatomic) NSUInteger sequence;
@property(nonatomic) CFTimeInterval startedAt;
@property(nonatomic) BOOL finalized;
@property(nonatomic) NSUInteger snapshotCount;
@property(nonatomic, weak) UIVisualEffectView *glassView;
@property(nonatomic, weak) UIView *hostView;
@property(nonatomic, strong) NSMutableArray<NSString *> *lines;

@end

@implementation WCLiquidGlassLongPressDiagnosticSession
@end

static SEL WCLiquidGlassLongPressWCGlassMarker(void) {
    return sel_registerName("WCLGApplyLongPressMenuGlass:");
}

static BOOL WCLiquidGlassIsWCGlassLongPressDiagnosticView(UIVisualEffectView *view) {
    return view && objc_getAssociatedObject(view, WCLiquidGlassLongPressWCGlassMarker()) != nil;
}

static NSString *WCLiquidGlassLongPressRectText(CGRect rect) {
    return [NSString stringWithFormat:@"{x=%.1f y=%.1f w=%.1f h=%.1f}",
            rect.origin.x,
            rect.origin.y,
            rect.size.width,
            rect.size.height];
}

static NSString *WCLiquidGlassLongPressClassName(id object) {
    return object ? NSStringFromClass([object class]) : @"nil";
}

static void WCLiquidGlassLongPressAppend(WCLiquidGlassLongPressDiagnosticSession *session,
                                         NSString *line) {
    if (!session || session.finalized || line.length == 0) {
        return;
    }
    CFTimeInterval elapsed = CACurrentMediaTime() - session.startedAt;
    [session.lines addObject:[NSString stringWithFormat:@"+%.3fs  %@", elapsed, line]];
}

static id WCLiquidGlassLongPressSafeValue(id object, NSString *key) {
    if (!object || key.length == 0) {
        return nil;
    }
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static NSString *WCLiquidGlassLongPressActionText(id actionValue) {
    if ([actionValue isKindOfClass:NSString.class]) {
        return actionValue;
    }
    if ([actionValue isKindOfClass:NSValue.class]) {
        @try {
            SEL selector = (SEL)[(NSValue *)actionValue pointerValue];
            if (selector) {
                return NSStringFromSelector(selector);
            }
        } @catch (__unused NSException *exception) {
            return @"unknown";
        }
    }
    return @"unknown";
}

static NSArray *WCLiquidGlassLongPressGestureTargetDescriptions(UIGestureRecognizer *gesture) {
    id entries = WCLiquidGlassLongPressSafeValue(gesture, @"_targets");
    if (![entries conformsToProtocol:@protocol(NSFastEnumeration)]) {
        return @[];
    }
    NSMutableArray<NSString *> *descriptions = [NSMutableArray array];
    for (id entry in entries) {
        id target = WCLiquidGlassLongPressSafeValue(entry, @"target");
        if (!target) {
            target = WCLiquidGlassLongPressSafeValue(entry, @"_target");
        }
        id action = WCLiquidGlassLongPressSafeValue(entry, @"action");
        if (!action) {
            action = WCLiquidGlassLongPressSafeValue(entry, @"_action");
        }
        [descriptions addObject:[NSString stringWithFormat:@"%@::%@",
                                 WCLiquidGlassLongPressClassName(target),
                                 WCLiquidGlassLongPressActionText(action)]];
    }
    return descriptions;
}

static NSString *WCLiquidGlassLongPressGestureDescription(UIGestureRecognizer *gesture) {
    NSMutableString *description = [NSMutableString stringWithFormat:
                                    @"gesture=%@ state=%ld enabled=%@ cancelsTouches=%@ delaysBegan=%@",
                                    WCLiquidGlassLongPressClassName(gesture),
                                    (long)gesture.state,
                                    gesture.enabled ? @"YES" : @"NO",
                                    gesture.cancelsTouchesInView ? @"YES" : @"NO",
                                    gesture.delaysTouchesBegan ? @"YES" : @"NO"];
    if ([gesture isKindOfClass:UILongPressGestureRecognizer.class]) {
        UILongPressGestureRecognizer *longPress = (UILongPressGestureRecognizer *)gesture;
        [description appendFormat:@" minimumDuration=%.3f allowableMovement=%.1f",
                                  longPress.minimumPressDuration,
                                  longPress.allowableMovement];
    }
    NSArray *targets = WCLiquidGlassLongPressGestureTargetDescriptions(gesture);
    if (targets.count > 0) {
        [description appendFormat:@" targets=[%@]", [targets componentsJoinedByString:@", "]];
    }
    return description;
}

static NSString *WCLiquidGlassLongPressImageDescription(UIImage *image) {
    if (!image) {
        return @"none";
    }
    return [NSString stringWithFormat:@"%@ size={%.1f,%.1f} scale=%.1f renderingMode=%ld capInsets={%.1f,%.1f,%.1f,%.1f}",
            WCLiquidGlassLongPressClassName(image),
            image.size.width,
            image.size.height,
            image.scale,
            (long)image.renderingMode,
            image.capInsets.top,
            image.capInsets.left,
            image.capInsets.bottom,
            image.capInsets.right];
}

static NSString *WCLiquidGlassLongPressControlActions(UIControl *control) {
    NSMutableArray<NSString *> *entries = [NSMutableArray array];
    NSArray *targets = [[control.allTargets allObjects]
                        sortedArrayUsingComparator:^NSComparisonResult(id first, id second) {
        return [WCLiquidGlassLongPressClassName(first)
                compare:WCLiquidGlassLongPressClassName(second)];
    }];
    for (id target in targets) {
        UIControlEvents registeredEvents = control.allControlEvents;
        for (NSUInteger bit = 0; bit < sizeof(UIControlEvents) * 8; bit += 1) {
            UIControlEvents event = (UIControlEvents)1 << bit;
            if ((registeredEvents & event) == 0) {
                continue;
            }
            NSArray<NSString *> *actions = [control actionsForTarget:target
                                                    forControlEvent:event] ?: @[];
            for (NSString *action in actions) {
                [entries addObject:[NSString stringWithFormat:@"%@::%@ event=%llu",
                                    WCLiquidGlassLongPressClassName(target),
                                    action,
                                    (unsigned long long)event]];
            }
        }
    }
    return entries.count > 0 ? [entries componentsJoinedByString:@", "] : @"none";
}

static void WCLiquidGlassLongPressAppendViewTree(UIView *view,
                                                 WCLiquidGlassLongPressDiagnosticSession *session,
                                                 NSUInteger depth,
                                                 NSUInteger *nodeCount) {
    if (!view || depth > 14 || *nodeCount >= 240) {
        return;
    }
    *nodeCount += 1;
    NSMutableString *line = [NSMutableString stringWithFormat:
                             @"%@view[%lu] class=%@ frame=%@ bounds=%@ alpha=%.3f hidden=%@ interaction=%@ clips=%@ corner=%.2f subviews=%lu",
                             [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0],
                             (unsigned long)*nodeCount,
                             WCLiquidGlassLongPressClassName(view),
                             WCLiquidGlassLongPressRectText(view.frame),
                             WCLiquidGlassLongPressRectText(view.bounds),
                             view.alpha,
                             view.hidden ? @"YES" : @"NO",
                             view.userInteractionEnabled ? @"YES" : @"NO",
                             view.clipsToBounds ? @"YES" : @"NO",
                             view.layer.cornerRadius,
                             (unsigned long)view.subviews.count];
    if ([view isKindOfClass:UIControl.class]) {
        UIControl *control = (UIControl *)view;
        [line appendFormat:@" controlEvents=%llu actions=[%@]",
                            (unsigned long long)control.allControlEvents,
                            WCLiquidGlassLongPressControlActions(control)];
    }
    if ([view isKindOfClass:UIImageView.class]) {
        [line appendFormat:@" image={%@}",
                            WCLiquidGlassLongPressImageDescription(((UIImageView *)view).image)];
    } else if ([view isKindOfClass:UIButton.class]) {
        UIButton *button = (UIButton *)view;
        [line appendFormat:@" image={%@}",
                            WCLiquidGlassLongPressImageDescription([button imageForState:UIControlStateNormal])];
    }
    WCLiquidGlassLongPressAppend(session, line);
    for (UIGestureRecognizer *gesture in view.gestureRecognizers) {
        WCLiquidGlassLongPressAppend(session,
                                     [NSString stringWithFormat:@"%@  %@",
                                      [@"" stringByPaddingToLength:(depth + 1) * 2
                                                        withString:@" "
                                                   startingAtIndex:0],
                                      WCLiquidGlassLongPressGestureDescription(gesture)]);
    }
    for (UIView *subview in view.subviews) {
        WCLiquidGlassLongPressAppendViewTree(subview, session, depth + 1, nodeCount);
    }
}

static void WCLiquidGlassLongPressAppendResponderChain(
    UIResponder *responder,
    WCLiquidGlassLongPressDiagnosticSession *session,
    NSString *name) {
    WCLiquidGlassLongPressAppend(session, [NSString stringWithFormat:@"%@ responder chain:", name]);
    NSUInteger depth = 0;
    for (UIResponder *current = responder; current && depth < 24; current = current.nextResponder) {
        WCLiquidGlassLongPressAppend(session,
                                     [NSString stringWithFormat:@"  responder[%lu]=%@",
                                      (unsigned long)depth,
                                      WCLiquidGlassLongPressClassName(current)]);
        depth += 1;
    }
}

static void WCLiquidGlassLongPressAppendTouchSource(
    WCLiquidGlassLongPressDiagnosticSession *session) {
    CFTimeInterval age = CACurrentMediaTime() - WCLiquidGlassLongPressLatestTouchTime;
    UIView *touchView = WCLiquidGlassLongPressLatestTouchView;
    UIWindow *touchWindow = WCLiquidGlassLongPressLatestTouchWindow;
    WCLiquidGlassLongPressAppend(session,
                                 [NSString stringWithFormat:
                                  @"touch source age=%.3f window=%@ view=%@ point={%.1f,%.1f}",
                                  age,
                                  WCLiquidGlassLongPressClassName(touchWindow),
                                  WCLiquidGlassLongPressClassName(touchView),
                                  WCLiquidGlassLongPressLatestTouchPoint.x,
                                  WCLiquidGlassLongPressLatestTouchPoint.y]);
    NSUInteger depth = 0;
    for (UIView *view = touchView; view && depth < 18; view = view.superview) {
        WCLiquidGlassLongPressAppend(session,
                                     [NSString stringWithFormat:@"  touchAncestor[%lu] class=%@ frame=%@ gestures=%lu",
                                      (unsigned long)depth,
                                      WCLiquidGlassLongPressClassName(view),
                                      WCLiquidGlassLongPressRectText(view.frame),
                                      (unsigned long)view.gestureRecognizers.count]);
        for (UIGestureRecognizer *gesture in view.gestureRecognizers) {
            WCLiquidGlassLongPressAppend(session,
                                         [NSString stringWithFormat:@"    %@",
                                          WCLiquidGlassLongPressGestureDescription(gesture)]);
        }
        depth += 1;
    }
}

static void WCLiquidGlassLongPressCaptureSnapshot(
    WCLiquidGlassLongPressDiagnosticSession *session,
    NSString *phase) {
    if (!session || session.finalized) {
        return;
    }
    session.snapshotCount += 1;
    WCLiquidGlassLongPressAppend(session,
                                 [NSString stringWithFormat:
                                  @"--- snapshot[%lu] phase=%@ hostWindow=%@ glassWindow=%@ ---",
                                  (unsigned long)session.snapshotCount,
                                  phase,
                                  WCLiquidGlassLongPressClassName(session.hostView.window),
                                  WCLiquidGlassLongPressClassName(session.glassView.window)]);
    WCLiquidGlassLongPressAppendResponderChain(session.hostView,
                                               session,
                                               @"host");
    NSUInteger nodeCount = 0;
    WCLiquidGlassLongPressAppendViewTree(session.hostView, session, 0, &nodeCount);
    WCLiquidGlassLongPressAppend(session,
                                 [NSString stringWithFormat:@"snapshot nodes=%lu",
                                 (unsigned long)nodeCount]);
}

static void WCLiquidGlassLongPressCaptureGeometry(
    WCLiquidGlassLongPressDiagnosticSession *session,
    NSString *phase) {
    if (!session || session.finalized) {
        return;
    }
    UIView *hostView = session.hostView;
    UIVisualEffectView *glassView = session.glassView;
    WCLiquidGlassLongPressAppend(session,
                                 [NSString stringWithFormat:
                                  @"geometry phase=%@ hostFrame=%@ hostBounds=%@ glassFrame=%@ glassBounds=%@",
                                  phase,
                                  WCLiquidGlassLongPressRectText(hostView.frame),
                                  WCLiquidGlassLongPressRectText(hostView.bounds),
                                  WCLiquidGlassLongPressRectText(glassView.frame),
                                  WCLiquidGlassLongPressRectText(glassView.bounds)]);
}

static void WCLiquidGlassLongPressFinalize(
    WCLiquidGlassLongPressDiagnosticSession *session,
    NSString *reason) {
    if (!session || session.finalized) {
        return;
    }
    session.finalized = YES;
    [session.lines addObject:[NSString stringWithFormat:
                              @"+%.3fs  finalized reason=%@",
                              CACurrentMediaTime() - session.startedAt,
                              reason]];
    NSString *privacy =
        @"Privacy: this report records only Objective-C class names, selectors, geometry, "
         "view/control/gesture state and image metadata. It excludes visible text, message "
         "content, menu titles, contact names and accessibility labels.\n\n";
    NSString *content = [privacy stringByAppendingString:
                         [session.lines componentsJoinedByString:@"\n"]];
    [[WCLiquidGlassCrashLogger sharedLogger]
     writeDiagnosticReportWithTitle:[NSString stringWithFormat:
                                     @"Long Press Menu Runtime Survey #%lu",
                                     (unsigned long)session.sequence]
     content:content];
    session.lines = nil;
}

static WCLiquidGlassLongPressDiagnosticSession *WCLiquidGlassLongPressBeginSession(
    UIVisualEffectView *glassView) {
    WCLiquidGlassLongPressDiagnosticSession *existing =
        objc_getAssociatedObject(glassView, WCLiquidGlassLongPressDiagnosticSessionKey);
    if (existing && !existing.finalized) {
        return existing;
    }
    if (WCLiquidGlassLongPressDiagnosticSequence >= 8) {
        return nil;
    }
    WCLiquidGlassLongPressDiagnosticSession *session =
        [[WCLiquidGlassLongPressDiagnosticSession alloc] init];
    session.sequence = ++WCLiquidGlassLongPressDiagnosticSequence;
    session.startedAt = CACurrentMediaTime();
    session.glassView = glassView;
    session.hostView = glassView.superview;
    session.lines = [NSMutableArray array];
    objc_setAssociatedObject(glassView,
                             WCLiquidGlassLongPressDiagnosticSessionKey,
                             session,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (session.hostView) {
        objc_setAssociatedObject(session.hostView,
                                 WCLiquidGlassLongPressDiagnosticSessionKey,
                                 session,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    WCLiquidGlassLongPressAppend(session,
                                 [NSString stringWithFormat:
                                  @"session began glass=%@ host=%@ glassFrame=%@ hostFrame=%@",
                                  WCLiquidGlassLongPressClassName(glassView),
                                  WCLiquidGlassLongPressClassName(session.hostView),
                                  WCLiquidGlassLongPressRectText(glassView.frame),
                                  WCLiquidGlassLongPressRectText(session.hostView.frame)]);
    WCLiquidGlassLongPressAppendTouchSource(session);
    WCLiquidGlassLongPressCaptureSnapshot(session, @"attached");
    __weak WCLiquidGlassLongPressDiagnosticSession *weakSession = session;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.08 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        WCLiquidGlassLongPressCaptureGeometry(weakSession, @"settling-80ms");
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.55 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        WCLiquidGlassLongPressCaptureSnapshot(weakSession, @"settled-550ms");
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        WCLiquidGlassLongPressDiagnosticSession *strongSession = weakSession;
        if (strongSession && !strongSession.finalized) {
            WCLiquidGlassLongPressCaptureSnapshot(strongSession, @"timeout-final");
            WCLiquidGlassLongPressFinalize(strongSession, @"15s timeout");
        }
    });
    return session;
}

static WCLiquidGlassLongPressDiagnosticSession *WCLiquidGlassLongPressSessionForView(
    UIView *view) {
    for (UIView *current = view; current; current = current.superview) {
        WCLiquidGlassLongPressDiagnosticSession *session =
            objc_getAssociatedObject(current, WCLiquidGlassLongPressDiagnosticSessionKey);
        if (session && !session.finalized) {
            return session;
        }
    }
    return nil;
}

static void WCLiquidGlassLongPressDiagnosticVisualEffectDidMoveToWindow(
    UIVisualEffectView *self,
    SEL selector) {
    if (WCLiquidGlassOriginalDiagnosticVisualEffectDidMoveToWindow) {
        WCLiquidGlassOriginalDiagnosticVisualEffectDidMoveToWindow(self, selector);
    }
    if (!WCLiquidGlassIsWCGlassLongPressDiagnosticView(self)) {
        return;
    }
    if (self.window) {
        WCLiquidGlassLongPressDiagnosticSession *session =
            WCLiquidGlassLongPressBeginSession(self);
        WCLiquidGlassLongPressAppend(session, @"glass didMoveToWindow attached");
    } else {
        WCLiquidGlassLongPressDiagnosticSession *session =
            objc_getAssociatedObject(self, WCLiquidGlassLongPressDiagnosticSessionKey);
        WCLiquidGlassLongPressAppend(session, @"glass didMoveToWindow detached");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.20 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            WCLiquidGlassLongPressFinalize(session, @"glass detached");
        });
    }
}

static void WCLiquidGlassLongPressDiagnosticApplicationSendEvent(
    UIApplication *self,
    SEL selector,
    UIEvent *event) {
    if (event.type == UIEventTypeTouches) {
        for (UITouch *touch in event.allTouches) {
            if (touch.phase == UITouchPhaseBegan ||
                touch.phase == UITouchPhaseMoved ||
                touch.phase == UITouchPhaseStationary) {
                WCLiquidGlassLongPressLatestTouchView = touch.view;
                WCLiquidGlassLongPressLatestTouchWindow = touch.window;
                WCLiquidGlassLongPressLatestTouchPoint = [touch locationInView:touch.window];
                WCLiquidGlassLongPressLatestTouchTime = CACurrentMediaTime();
            }
        }
    }
    if (WCLiquidGlassOriginalDiagnosticApplicationSendEvent) {
        WCLiquidGlassOriginalDiagnosticApplicationSendEvent(self, selector, event);
    }
}

static BOOL WCLiquidGlassLongPressDiagnosticApplicationSendAction(
    UIApplication *self,
    SEL selector,
    SEL action,
    id target,
    id sender,
    UIEvent *event) {
    WCLiquidGlassLongPressDiagnosticSession *session = nil;
    if ([sender isKindOfClass:UIView.class]) {
        session = WCLiquidGlassLongPressSessionForView((UIView *)sender);
    } else if ([sender isKindOfClass:UIGestureRecognizer.class]) {
        session = WCLiquidGlassLongPressSessionForView(((UIGestureRecognizer *)sender).view);
    }
    if (session) {
        WCLiquidGlassLongPressAppend(session,
                                     [NSString stringWithFormat:
                                      @"sendAction selector=%@ target=%@ sender=%@ event=%@",
                                      action ? NSStringFromSelector(action) : @"nil",
                                      WCLiquidGlassLongPressClassName(target),
                                      WCLiquidGlassLongPressClassName(sender),
                                      WCLiquidGlassLongPressClassName(event)]);
    }
    BOOL handled = WCLiquidGlassOriginalDiagnosticApplicationSendAction
        ? WCLiquidGlassOriginalDiagnosticApplicationSendAction(self,
                                                               selector,
                                                               action,
                                                               target,
                                                               sender,
                                                               event)
        : NO;
    if (session) {
        WCLiquidGlassLongPressAppend(session,
                                     [NSString stringWithFormat:@"sendAction returned=%@",
                                      handled ? @"YES" : @"NO"]);
        dispatch_async(dispatch_get_main_queue(), ^{
            WCLiquidGlassLongPressCaptureSnapshot(session, @"after-action");
        });
    }
    return handled;
}

static void WCLiquidGlassLongPressDiagnosticViewRemoveFromSuperview(
    UIView *self,
    SEL selector) {
    WCLiquidGlassLongPressDiagnosticSession *session =
        objc_getAssociatedObject(self, WCLiquidGlassLongPressDiagnosticSessionKey);
    if (session) {
        WCLiquidGlassLongPressAppend(session,
                                     [NSString stringWithFormat:@"removeFromSuperview class=%@",
                                      WCLiquidGlassLongPressClassName(self)]);
    }
    if (WCLiquidGlassOriginalDiagnosticViewRemoveFromSuperview) {
        WCLiquidGlassOriginalDiagnosticViewRemoveFromSuperview(self, selector);
    }
    if (session) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.20 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            WCLiquidGlassLongPressFinalize(session, @"marked view removed");
        });
    }
}

void WCLiquidGlassInstallLongPressMenuDiagnostics(void) {
    if (WCLiquidGlassLongPressDiagnosticsInstalled) {
        return;
    }
    WCLiquidGlassLongPressDiagnosticsInstalled = YES;
    MSHookMessageEx(UIVisualEffectView.class,
                    @selector(didMoveToWindow),
                    (IMP)&WCLiquidGlassLongPressDiagnosticVisualEffectDidMoveToWindow,
                    (IMP *)&WCLiquidGlassOriginalDiagnosticVisualEffectDidMoveToWindow);
    MSHookMessageEx(UIApplication.class,
                    @selector(sendEvent:),
                    (IMP)&WCLiquidGlassLongPressDiagnosticApplicationSendEvent,
                    (IMP *)&WCLiquidGlassOriginalDiagnosticApplicationSendEvent);
    MSHookMessageEx(UIApplication.class,
                    @selector(sendAction:to:from:forEvent:),
                    (IMP)&WCLiquidGlassLongPressDiagnosticApplicationSendAction,
                    (IMP *)&WCLiquidGlassOriginalDiagnosticApplicationSendAction);
    MSHookMessageEx(UIView.class,
                    @selector(removeFromSuperview),
                    (IMP)&WCLiquidGlassLongPressDiagnosticViewRemoveFromSuperview,
                    (IMP *)&WCLiquidGlassOriginalDiagnosticViewRemoveFromSuperview);
    [[WCLiquidGlassCrashLogger sharedLogger]
     recordEvent:@"Long press menu runtime survey installed"];
}
