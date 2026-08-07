#import "WCLiquidGlassChatDiagnostics.h"

#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "WCLiquidGlassCrashLogger.h"
#import "WCLiquidGlassPreferences.h"

static const void *WCLiquidGlassChatDiagnosticsProbeKey = &WCLiquidGlassChatDiagnosticsProbeKey;
static __weak UIView *WCLiquidGlassChatDiagnosticsActiveRoot;
static __weak UIViewController *WCLiquidGlassChatDiagnosticsActiveController;
static BOOL WCLiquidGlassChatDiagnosticsScanScheduled = NO;
static NSUInteger WCLiquidGlassChatDiagnosticsScanAttempts = 0;

static NSString *WCLiquidGlassChatDiagnosticsClassName(id object) {
    return object ? NSStringFromClass([object class]) : @"nil";
}

static NSString *WCLiquidGlassChatDiagnosticsRect(CGRect rect) {
    return [NSString stringWithFormat:@"{{%.1f, %.1f}, {%.1f, %.1f}}",
            rect.origin.x, rect.origin.y, rect.size.width, rect.size.height];
}

static NSString *WCLiquidGlassChatDiagnosticsColor(UIColor *color) {
    if (!color) {
        return @"nil";
    }
    CGFloat red = 0.0;
    CGFloat green = 0.0;
    CGFloat blue = 0.0;
    CGFloat alpha = 0.0;
    if ([color getRed:&red green:&green blue:&blue alpha:&alpha]) {
        return [NSString stringWithFormat:@"rgba(%.3f, %.3f, %.3f, %.3f)", red, green, blue, alpha];
    }
    CGFloat white = 0.0;
    if ([color getWhite:&white alpha:&alpha]) {
        return [NSString stringWithFormat:@"white(%.3f, %.3f)", white, alpha];
    }
    return NSStringFromClass(color.class);
}

static NSString *WCLiquidGlassChatDiagnosticsImage(UIImage *image) {
    if (!image) {
        return @"nil";
    }
    return [NSString stringWithFormat:@"size={%.1f, %.1f} scale=%.1f mode=%ld",
            image.size.width, image.size.height, image.scale, (long)image.renderingMode];
}

static id WCLiquidGlassChatDiagnosticsObjectForSelector(UIView *view, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    if (![view respondsToSelector:selector]) {
        return nil;
    }
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(view, selector);
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static BOOL WCLiquidGlassChatDiagnosticsNameMatches(NSString *name) {
    NSString *lowercaseName = name.lowercaseString;
    for (NSString *keyword in @[@"unread", @"msgtip", @"msg_tips", @"newmsg", @"newmessage",
                                 @"notify", @"notice", @"header", @"tips", @"banner"]) {
        if ([lowercaseName containsString:keyword]) {
            return YES;
        }
    }
    return NO;
}

static BOOL WCLiquidGlassChatDiagnosticsHasKnownBackground(UIView *view) {
    for (NSString *name in @[@"bgButton", @"backgroundView", @"backgroundImageView",
                             @"backgroundEffectView", @"bgView"]) {
        if (WCLiquidGlassChatDiagnosticsObjectForSelector(view, name)) {
            return YES;
        }
    }
    return NO;
}

static void WCLiquidGlassChatDiagnosticsAppendKnownBackgrounds(NSMutableString *report,
                                                                UIView *view,
                                                                NSUInteger depth) {
    NSString *indent = [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0];
    for (NSString *name in @[@"bgButton", @"backgroundView", @"backgroundImageView",
                             @"backgroundEffectView", @"bgView"]) {
        id candidate = WCLiquidGlassChatDiagnosticsObjectForSelector(view, name);
        if (![candidate isKindOfClass:UIView.class] || candidate == view) {
            continue;
        }
        UIView *candidateView = (UIView *)candidate;
        NSString *effect = [candidateView isKindOfClass:UIVisualEffectView.class]
            ? WCLiquidGlassChatDiagnosticsClassName(((UIVisualEffectView *)candidateView).effect)
            : @"n/a";
        NSString *image = [candidateView isKindOfClass:UIImageView.class]
            ? WCLiquidGlassChatDiagnosticsImage(((UIImageView *)candidateView).image)
            : @"n/a";
        [report appendFormat:@"%@background selector=%@ class=%@ frame=%@ bg=%@ image=%@ effect=%@ corner=%.1f masks=%@\n",
         indent, name, WCLiquidGlassChatDiagnosticsClassName(candidateView),
         WCLiquidGlassChatDiagnosticsRect(candidateView.frame),
         WCLiquidGlassChatDiagnosticsColor(candidateView.backgroundColor), image, effect,
         candidateView.layer.cornerRadius, candidateView.layer.masksToBounds ? @"YES" : @"NO"];
    }
}

static void WCLiquidGlassChatDiagnosticsAppendViewTree(NSMutableString *report,
                                                        UIView *view,
                                                        NSUInteger depth,
                                                        UIView *target,
                                                        NSUInteger *nodeCount) {
    // ponytail: cap at 1200 nodes; raise only if the target is absent from the report.
    if (!view || *nodeCount >= 1200 || depth > 12) {
        if (*nodeCount >= 1200) {
            [report appendString:@"... hierarchy truncated at 1200 views ...\n"];
        }
        return;
    }
    *nodeCount += 1;
    NSString *indent = [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0];
    NSString *className = WCLiquidGlassChatDiagnosticsClassName(view);
    BOOL candidate = view == target || [view isKindOfClass:UIControl.class] ||
        WCLiquidGlassChatDiagnosticsNameMatches(className) ||
        WCLiquidGlassChatDiagnosticsHasKnownBackground(view);
    [report appendFormat:@"%@%@%@%@ frame=%@ bounds=%@ alpha=%.2f hidden=%@ interaction=%@ bg=%@ corner=%.1f masks=%@ subviews=%lu\n",
     indent, view == target ? @"TARGET " : @"", className,
     candidate ? @" candidate=YES" : @"",
     WCLiquidGlassChatDiagnosticsRect(view.frame), WCLiquidGlassChatDiagnosticsRect(view.bounds),
     view.alpha, view.hidden ? @"YES" : @"NO", view.userInteractionEnabled ? @"YES" : @"NO",
     WCLiquidGlassChatDiagnosticsColor(view.backgroundColor), view.layer.cornerRadius,
     view.layer.masksToBounds ? @"YES" : @"NO", (unsigned long)view.subviews.count];
    if ([view isKindOfClass:UIControl.class]) {
        UIControl *control = (UIControl *)view;
        [report appendFormat:@"%@control enabled=%@ selected=%@ highlighted=%@ state=%lu events=%lu\n",
         indent, control.enabled ? @"YES" : @"NO", control.selected ? @"YES" : @"NO",
         control.highlighted ? @"YES" : @"NO", (unsigned long)control.state,
         (unsigned long)control.allControlEvents];
    }
    if ([view isKindOfClass:UIImageView.class]) {
        [report appendFormat:@"%@image %@\n", indent,
         WCLiquidGlassChatDiagnosticsImage(((UIImageView *)view).image)];
    }
    if ([view isKindOfClass:UIVisualEffectView.class]) {
        [report appendFormat:@"%@effect %@\n", indent,
         WCLiquidGlassChatDiagnosticsClassName(((UIVisualEffectView *)view).effect)];
    }
    WCLiquidGlassChatDiagnosticsAppendKnownBackgrounds(report, view, depth + 1);
    for (UIView *subview in view.subviews) {
        WCLiquidGlassChatDiagnosticsAppendViewTree(report, subview, depth + 1, target, nodeCount);
        if (*nodeCount >= 1200) {
            break;
        }
    }
}

static NSString *WCLiquidGlassChatDiagnosticsViewPath(UIView *view) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    UIView *current = view;
    while (current) {
        [parts insertObject:[NSString stringWithFormat:@"%@ %@",
                             WCLiquidGlassChatDiagnosticsClassName(current),
                             WCLiquidGlassChatDiagnosticsRect(current.frame)] atIndex:0];
        current = current.superview;
    }
    return [parts componentsJoinedByString:@"\n  "];
}

static UIViewController *WCLiquidGlassChatDiagnosticsFindController(UIViewController *controller,
                                                                      NSUInteger depth) {
    if (!controller || depth > 12) {
        return nil;
    }
    UIView *view = controller.viewIfLoaded;
    NSString *name = NSStringFromClass(controller.class).lowercaseString;
    Class baseChatClass = NSClassFromString(@"BaseMsgContentViewController");
    BOOL looksLikeChat = (baseChatClass && [controller isKindOfClass:baseChatClass]) ||
        [name containsString:@"msgcontent"] || [name containsString:@"chatroom"];
    if (looksLikeChat && view.window && !view.hidden && view.alpha > 0.01) {
        return controller;
    }
    UIViewController *presented = WCLiquidGlassChatDiagnosticsFindController(controller.presentedViewController, depth + 1);
    if (presented) {
        return presented;
    }
    for (UIViewController *child in controller.childViewControllers.reverseObjectEnumerator) {
        UIViewController *match = WCLiquidGlassChatDiagnosticsFindController(child, depth + 1);
        if (match) {
            return match;
        }
    }
    return nil;
}

static NSArray<UIWindow *> *WCLiquidGlassChatDiagnosticsVisibleWindows(void) {
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) {
            continue;
        }
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        if (windowScene.activationState == UISceneActivationStateUnattached ||
            windowScene.activationState == UISceneActivationStateBackground) {
            continue;
        }
        [windows addObjectsFromArray:windowScene.windows];
    }
    [windows sortUsingComparator:^NSComparisonResult(UIWindow *first, UIWindow *second) {
        if (first.isKeyWindow == second.isKeyWindow) {
            return NSOrderedSame;
        }
        return first.isKeyWindow ? NSOrderedAscending : NSOrderedDescending;
    }];
    return windows;
}

static UIViewController *WCLiquidGlassChatDiagnosticsVisibleController(void) {
    for (UIWindow *window in WCLiquidGlassChatDiagnosticsVisibleWindows()) {
        if (window.hidden || window.alpha <= 0.01 || !window.rootViewController) {
            continue;
        }
        UIViewController *match = WCLiquidGlassChatDiagnosticsFindController(window.rootViewController, 0);
        if (match) {
            return match;
        }
    }
    return nil;
}

static NSString *WCLiquidGlassChatDiagnosticsReport(UIViewController *controller,
                                                     UIView *target,
                                                     CGPoint point,
                                                     BOOL hasPoint) {
    UIView *root = controller.viewIfLoaded;
    NSMutableString *report = [NSMutableString stringWithFormat:
        @"Privacy: visible text, message content, contact names, titles and accessibility labels are omitted.\n"
         "Controller: %@\nRoot View: %@ frame=%@ window=%@\n",
        NSStringFromClass(controller.class), WCLiquidGlassChatDiagnosticsClassName(root),
        root ? WCLiquidGlassChatDiagnosticsRect(root.frame) : @"n/a",
        root.window ? WCLiquidGlassChatDiagnosticsClassName(root.window) : @"nil"];
    if (hasPoint) {
        [report appendFormat:@"\nTap point in chat root: {%.1f, %.1f}\n", point.x, point.y];
        [report appendFormat:@"Hit view path:\n  %@\n", target ? WCLiquidGlassChatDiagnosticsViewPath(target) : @"nil"];
        if (target) {
            [report appendString:@"\nHit view background candidates:\n"];
            WCLiquidGlassChatDiagnosticsAppendKnownBackgrounds(report, target, 1);
        }
    }
    [report appendString:@"\nChat View Hierarchy\n"];
    NSUInteger nodeCount = 0;
    WCLiquidGlassChatDiagnosticsAppendViewTree(report, root, 0, target, &nodeCount);
    [report appendFormat:@"\nNodes recorded: %lu\n", (unsigned long)nodeCount];
    return report;
}

@interface WCLiquidGlassChatDiagnosticsProbe : UITapGestureRecognizer <UIGestureRecognizerDelegate>
@property(nonatomic, weak) UIViewController *controller;
@property(nonatomic, weak) UIView *rootView;
@property(nonatomic, assign) BOOL captured;
- (void)wc_captureTap:(WCLiquidGlassChatDiagnosticsProbe *)probe;
@end

@implementation WCLiquidGlassChatDiagnosticsProbe

- (instancetype)init {
    self = [super initWithTarget:nil action:NULL];
    if (self) {
        self.cancelsTouchesInView = NO;
        self.delaysTouchesBegan = NO;
        self.delaysTouchesEnded = NO;
        self.delegate = self;
        [self addTarget:self action:@selector(wc_captureTap:)];
    }
    return self;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
 shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}

- (void)wc_captureTap:(WCLiquidGlassChatDiagnosticsProbe *)probe {
    if (probe.state != UIGestureRecognizerStateRecognized || probe.captured ||
        !probe.controller || !probe.rootView) {
        return;
    }
    probe.captured = YES;
    UIView *root = probe.rootView;
    CGPoint point = [probe locationInView:root];
    UIView *target = [root hitTest:point withEvent:nil];
    [[WCLiquidGlassCrashLogger sharedLogger] recordEvent:
        [NSString stringWithFormat:@"ChatDiagnostics tap captured root=%@ hit=%@ point={%.1f,%.1f}",
         WCLiquidGlassChatDiagnosticsClassName(root), WCLiquidGlassChatDiagnosticsClassName(target),
         point.x, point.y]];
    NSString *report = WCLiquidGlassChatDiagnosticsReport(probe.controller, target, point, YES);
    [[WCLiquidGlassCrashLogger sharedLogger] writeDiagnosticReportWithTitle:@"聊天页点击诊断" content:report];
    [root removeGestureRecognizer:probe];
    objc_setAssociatedObject(root, WCLiquidGlassChatDiagnosticsProbeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    WCLiquidGlassChatDiagnosticsActiveRoot = nil;
    WCLiquidGlassChatDiagnosticsActiveController = nil;
}

@end

static void WCLiquidGlassChatDiagnosticsRemoveProbe(void) {
    UIView *root = WCLiquidGlassChatDiagnosticsActiveRoot;
    WCLiquidGlassChatDiagnosticsProbe *probe = objc_getAssociatedObject(root, WCLiquidGlassChatDiagnosticsProbeKey);
    if (probe) {
        [root removeGestureRecognizer:probe];
        objc_setAssociatedObject(root, WCLiquidGlassChatDiagnosticsProbeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    WCLiquidGlassChatDiagnosticsActiveRoot = nil;
    WCLiquidGlassChatDiagnosticsActiveController = nil;
}

static void WCLiquidGlassChatDiagnosticsArm(void);

static void WCLiquidGlassChatDiagnosticsScheduleScan(void) {
    if (!WCLiquidGlassPreferences.chatPageDiagnosticsEnabled || WCLiquidGlassChatDiagnosticsScanScheduled) {
        return;
    }
    if (WCLiquidGlassChatDiagnosticsScanAttempts >= 120) {
        return;
    }
    WCLiquidGlassChatDiagnosticsScanScheduled = YES;
    WCLiquidGlassChatDiagnosticsScanAttempts += 1;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        WCLiquidGlassChatDiagnosticsScanScheduled = NO;
        WCLiquidGlassChatDiagnosticsArm();
        if (WCLiquidGlassPreferences.chatPageDiagnosticsEnabled && !WCLiquidGlassChatDiagnosticsActiveRoot) {
            WCLiquidGlassChatDiagnosticsScheduleScan();
        }
    });
}

static void WCLiquidGlassChatDiagnosticsArm(void) {
    if (!WCLiquidGlassPreferences.chatPageDiagnosticsEnabled) {
        WCLiquidGlassChatDiagnosticsRemoveProbe();
        return;
    }
    UIViewController *controller = WCLiquidGlassChatDiagnosticsVisibleController();
    UIView *root = controller.viewIfLoaded;
    if (!controller || !root || !root.window || root.hidden || root.alpha <= 0.01) {
        WCLiquidGlassChatDiagnosticsScheduleScan();
        return;
    }
    if (WCLiquidGlassChatDiagnosticsActiveRoot == root) {
        return;
    }
    WCLiquidGlassChatDiagnosticsRemoveProbe();
    WCLiquidGlassChatDiagnosticsActiveRoot = root;
    WCLiquidGlassChatDiagnosticsActiveController = controller;
    [[WCLiquidGlassCrashLogger sharedLogger] recordEvent:
        [NSString stringWithFormat:@"ChatDiagnostics armed controller=%@ root=%@",
         NSStringFromClass(controller.class), WCLiquidGlassChatDiagnosticsClassName(root)]];
    NSString *layoutReport = WCLiquidGlassChatDiagnosticsReport(controller, nil, CGPointZero, NO);
    [[WCLiquidGlassCrashLogger sharedLogger] writeDiagnosticReportWithTitle:@"聊天页布局诊断" content:layoutReport];
    WCLiquidGlassChatDiagnosticsProbe *probe = [[WCLiquidGlassChatDiagnosticsProbe alloc] init];
    probe.controller = controller;
    probe.rootView = root;
    [root addGestureRecognizer:probe];
    objc_setAssociatedObject(root, WCLiquidGlassChatDiagnosticsProbeKey, probe, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void WCLiquidGlassInstallChatDiagnosticsHooks(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [NSNotificationCenter.defaultCenter addObserverForName:WCLiquidGlassPreferencesDidChangeNotification
                                                        object:nil
                                                         queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(__unused NSNotification *notification) {
            if (WCLiquidGlassPreferences.chatPageDiagnosticsEnabled) {
                WCLiquidGlassChatDiagnosticsScanAttempts = 0;
                WCLiquidGlassChatDiagnosticsScheduleScan();
            } else {
                WCLiquidGlassChatDiagnosticsRemoveProbe();
            }
        }];
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
                                                        object:nil
                                                         queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(__unused NSNotification *notification) {
            if (WCLiquidGlassPreferences.chatPageDiagnosticsEnabled) {
                WCLiquidGlassChatDiagnosticsScanAttempts = 0;
                WCLiquidGlassChatDiagnosticsScheduleScan();
            }
        }];
        [NSNotificationCenter.defaultCenter addObserverForName:UIWindowDidBecomeKeyNotification
                                                        object:nil
                                                         queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(__unused NSNotification *notification) {
            if (WCLiquidGlassPreferences.chatPageDiagnosticsEnabled && !WCLiquidGlassChatDiagnosticsActiveRoot) {
                WCLiquidGlassChatDiagnosticsScheduleScan();
            }
        }];
    });
    if (WCLiquidGlassPreferences.chatPageDiagnosticsEnabled) {
        WCLiquidGlassChatDiagnosticsScheduleScan();
    }
}
