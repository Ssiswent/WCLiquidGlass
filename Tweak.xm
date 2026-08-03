#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CydiaSubstrate.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "WCLiquidGlass.h"
#import "WCLiquidGlassChatTime.h"
#import "WCLiquidGlassChatBottomMenu.h"
#import "WCLiquidGlassContactsIndex.h"
#import "WCLiquidGlassCrashLogger.h"
#import "WCLiquidGlassHomeCorners.h"
#import "WCLiquidGlassMaterialFileProtection.h"
#import "WCLiquidGlassMessageNotification.h"
#import "WCLiquidGlassMenu.h"
#import "WCLiquidGlassPreferences.h"
#import "WCLiquidGlassWCGlassLongPress.h"
#import "WCLiquidGlassWCGlassSearchTabBar.h"

#ifndef WCLIQUIDGLASS_VERSION
#define WCLIQUIDGLASS_VERSION "Unknown"
#endif

static BOOL WCLiquidGlassPluginRegistered = NO;
static NSUInteger WCLiquidGlassRegistrationAttempts = 0;
static __thread NSUInteger WCLiquidGlassDictationWriteDepth = 0;
static BOOL WCLiquidGlassKeyboardVisible = NO;
static BOOL WCLiquidGlassWCGlassRiskyReturnPending = NO;
static BOOL WCLiquidGlassWCGlassRowGuardActive = NO;
static __weak UITableView *WCLiquidGlassWCGlassGuardedTableView = nil;
static __weak UITableView *WCLiquidGlassWCGlassKnownMainFrameTableView = nil;
static BOOL WCLiquidGlassWCGlassReturnHooksInstalled = NO;
static BOOL WCLiquidGlassWCGlassHookInstallRetryScheduled = NO;
static NSUInteger WCLiquidGlassWCGlassHookInstallAttempts = 0;
static NSUInteger WCLiquidGlassWCGlassBlockedRowRequestCount = 0;
static NSUInteger WCLiquidGlassWCGlassBlockedRectRequestCount = 0;
static BOOL WCLiquidGlassWCGlassFallbackGuardLogged = NO;
static UIViewController *(*WCLiquidGlassOriginalNavigationPopViewController)(UINavigationController *, SEL, BOOL) = NULL;
static void (*WCLiquidGlassOriginalMainFrameViewWillAppear)(id, SEL, BOOL) = NULL;
static NSInteger (*WCLiquidGlassOriginalTableViewNumberOfRows)(UITableView *, SEL, NSInteger) = NULL;
static CGRect (*WCLiquidGlassOriginalTableViewRectForSection)(UITableView *, SEL, NSInteger) = NULL;
static BOOL WCLiquidGlassIsAffectedChatController(UIViewController *viewController);

static UIViewController *WCLiquidGlassStableNavigationPopViewController(UINavigationController *self,
                                                                        SEL selector,
                                                                        BOOL animated) {
    UIViewController *topViewController = self.topViewController;
    BOOL shouldStabilizeWCGlassReturn = NSProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 &&
        WCLiquidGlassPreferences.wcGlassIOS27CompatibilityEnabled &&
        WCLiquidGlassKeyboardVisible &&
        WCLiquidGlassIsAffectedChatController(topViewController) &&
        WCLiquidGlassCurrentChatInputHasText();
    WCLiquidGlassWCGlassRiskyReturnPending = shouldStabilizeWCGlassReturn;
    UIViewController *poppedViewController = WCLiquidGlassOriginalNavigationPopViewController
        ? WCLiquidGlassOriginalNavigationPopViewController(self, selector, animated)
        : nil;
    if (!poppedViewController) {
        WCLiquidGlassWCGlassRiskyReturnPending = NO;
    }
    return poppedViewController;
}

static BOOL WCLiquidGlassIsAffectedChatController(UIViewController *viewController) {
    Class chatControllerClass = NSClassFromString(@"BaseMsgContentViewController");
    return NSClassFromString(@"WCLGHomeGroups") != Nil &&
        chatControllerClass != Nil &&
        [viewController isKindOfClass:chatControllerClass];
}

static UITableView *WCLiquidGlassMainFrameTableView(id controller) {
    SEL selector = NSSelectorFromString(@"getTableView");
    id tableView = [controller respondsToSelector:selector]
        ? ((id (*)(id, SEL))objc_msgSend)(controller, selector)
        : nil;
    if (![tableView isKindOfClass:UITableView.class]) {
        selector = NSSelectorFromString(@"tableView");
        tableView = [controller respondsToSelector:selector]
            ? ((id (*)(id, SEL))objc_msgSend)(controller, selector)
            : nil;
    }
    return [tableView isKindOfClass:UITableView.class] ? tableView : nil;
}

static BOOL WCLiquidGlassControllerContainsMainFrameTable(UIViewController *controller,
                                                           UITableView *tableView,
                                                           NSUInteger depth) {
    if (!controller || depth > 16) {
        return NO;
    }
    Class mainFrameClass = NSClassFromString(@"NewMainFrameViewController");
    if (mainFrameClass != Nil &&
        [controller isKindOfClass:mainFrameClass] &&
        WCLiquidGlassMainFrameTableView(controller) == tableView) {
        return YES;
    }
    if (WCLiquidGlassControllerContainsMainFrameTable(controller.presentedViewController,
                                                       tableView,
                                                       depth + 1)) {
        return YES;
    }
    for (UIViewController *childController in controller.childViewControllers) {
        if (WCLiquidGlassControllerContainsMainFrameTable(childController,
                                                           tableView,
                                                           depth + 1)) {
            return YES;
        }
    }
    return NO;
}

static BOOL WCLiquidGlassIsMainFrameTableView(UITableView *tableView) {
    Class mainFrameClass = NSClassFromString(@"NewMainFrameViewController");
    for (UIResponder *responder = tableView.nextResponder;
         responder;
         responder = responder.nextResponder) {
        if (mainFrameClass != Nil &&
            [responder isKindOfClass:mainFrameClass] &&
            WCLiquidGlassMainFrameTableView(responder) == tableView) {
            return YES;
        }
    }
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) {
            continue;
        }
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (WCLiquidGlassControllerContainsMainFrameTable(window.rootViewController,
                                                               tableView,
                                                               0)) {
                return YES;
            }
        }
    }
    return NO;
}

static BOOL WCLiquidGlassShouldGuardOutOfBoundsSection(UITableView *tableView,
                                                        NSInteger section) {
    BOOL activeTarget = WCLiquidGlassWCGlassRowGuardActive &&
        tableView == WCLiquidGlassWCGlassGuardedTableView;
    if (!activeTarget &&
        !WCLiquidGlassPreferences.wcGlassIOS27CompatibilityEnabled) {
        return NO;
    }
    BOOL knownTarget = tableView == WCLiquidGlassWCGlassKnownMainFrameTableView;
    if (!activeTarget && !knownTarget && section >= 0 && section < 2) {
        return NO;
    }
    NSInteger sectionCount = tableView.numberOfSections;
    if (section >= 0 && section < sectionCount) {
        return NO;
    }
    if (activeTarget) {
        return YES;
    }
    if (!WCLiquidGlassPreferences.wcGlassIOS27CompatibilityEnabled ||
        NSProcessInfo.processInfo.operatingSystemVersion.majorVersion < 27 ||
        NSClassFromString(@"WCLGHomeGroups") == Nil ||
        (!knownTarget && !WCLiquidGlassIsMainFrameTableView(tableView))) {
        return NO;
    }
    WCLiquidGlassWCGlassKnownMainFrameTableView = tableView;
    if (!WCLiquidGlassWCGlassFallbackGuardLogged) {
        WCLiquidGlassWCGlassFallbackGuardLogged = YES;
        [WCLiquidGlassCrashLogger.sharedLogger recordEvent:[NSString stringWithFormat:
            @"WCGlassReturn fallback section guard section=%ld sections=%ld",
            (long)section,
            (long)sectionCount]];
    }
    return YES;
}

static NSInteger WCLiquidGlassGuardedTableViewNumberOfRows(UITableView *self,
                                                            SEL selector,
                                                            NSInteger section) {
    if (WCLiquidGlassShouldGuardOutOfBoundsSection(self, section)) {
        if (WCLiquidGlassWCGlassRowGuardActive &&
            self == WCLiquidGlassWCGlassGuardedTableView) {
            WCLiquidGlassWCGlassBlockedRowRequestCount += 1;
        }
        return 0;
    }
    return WCLiquidGlassOriginalTableViewNumberOfRows
        ? WCLiquidGlassOriginalTableViewNumberOfRows(self, selector, section)
        : 0;
}

static CGRect WCLiquidGlassGuardedTableViewRectForSection(UITableView *self,
                                                           SEL selector,
                                                           NSInteger section) {
    if (WCLiquidGlassShouldGuardOutOfBoundsSection(self, section)) {
        if (WCLiquidGlassWCGlassRowGuardActive &&
            self == WCLiquidGlassWCGlassGuardedTableView) {
            WCLiquidGlassWCGlassBlockedRectRequestCount += 1;
        }
        return CGRectZero;
    }
    return WCLiquidGlassOriginalTableViewRectForSection
        ? WCLiquidGlassOriginalTableViewRectForSection(self, selector, section)
        : CGRectZero;
}

static void WCLiquidGlassFinishWCGlassRowGuard(NSString *reason) {
    WCLiquidGlassWCGlassRowGuardActive = NO;
    WCLiquidGlassWCGlassGuardedTableView = nil;
    WCLiquidGlassWCGlassRiskyReturnPending = NO;
    [WCLiquidGlassCrashLogger.sharedLogger recordEvent:[NSString stringWithFormat:
        @"WCGlassReturn row guard end reason=%@ blockedRows=%lu blockedRects=%lu",
        reason,
        (unsigned long)WCLiquidGlassWCGlassBlockedRowRequestCount,
        (unsigned long)WCLiquidGlassWCGlassBlockedRectRequestCount]];
    WCLiquidGlassWCGlassBlockedRowRequestCount = 0;
    WCLiquidGlassWCGlassBlockedRectRequestCount = 0;
}

static void WCLiquidGlassStableMainFrameViewWillAppear(id self,
                                                       SEL selector,
                                                       BOOL animated) {
    BOOL compatibilityAvailable =
        NSProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 &&
        NSClassFromString(@"WCLGHomeGroups") != Nil;
    UITableView *tableView = compatibilityAvailable ? WCLiquidGlassMainFrameTableView(self) : nil;
    if (tableView) {
        WCLiquidGlassWCGlassKnownMainFrameTableView = tableView;
    }
    if (WCLiquidGlassWCGlassRiskyReturnPending && tableView) {
        WCLiquidGlassWCGlassBlockedRowRequestCount = 0;
        WCLiquidGlassWCGlassBlockedRectRequestCount = 0;
        WCLiquidGlassWCGlassGuardedTableView = tableView;
        WCLiquidGlassWCGlassRowGuardActive = YES;
        [WCLiquidGlassCrashLogger.sharedLogger recordEvent:[NSString stringWithFormat:
            @"WCGlassReturn row guard begin sections=%ld",
            (long)tableView.numberOfSections]];
    }

    @try {
        WCLiquidGlassOriginalMainFrameViewWillAppear(self, selector, animated);
    } @catch (NSException *exception) {
        WCLiquidGlassFinishWCGlassRowGuard(@"viewWillAppear exception");
        @throw;
    }

    if (!WCLiquidGlassWCGlassRowGuardActive ||
        tableView != WCLiquidGlassWCGlassGuardedTableView) {
        WCLiquidGlassWCGlassRiskyReturnPending = NO;
        return;
    }

    id<UIViewControllerTransitionCoordinator> coordinator =
        [self respondsToSelector:@selector(transitionCoordinator)]
            ? [self transitionCoordinator]
            : nil;
    if (coordinator) {
        [coordinator animateAlongsideTransition:nil
                                     completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
            WCLiquidGlassFinishWCGlassRowGuard(
                context.isCancelled ? @"transition cancelled" : @"transition completed");
        }];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            WCLiquidGlassFinishWCGlassRowGuard(@"next run loop");
        });
    }
}

static void WCLiquidGlassInstallWCGlassReturnHooksIfNeeded(void) {
    if (WCLiquidGlassWCGlassReturnHooksInstalled ||
        !WCLiquidGlassPreferences.wcGlassIOS27CompatibilityEnabled ||
        NSProcessInfo.processInfo.operatingSystemVersion.majorVersion < 27 ||
        NSClassFromString(@"WCLGHomeGroups") == Nil) {
        return;
    }
    Class mainFrameClass = NSClassFromString(@"NewMainFrameViewController");
    SEL popSelector = @selector(popViewControllerAnimated:);
    SEL viewWillAppearSelector = @selector(viewWillAppear:);
    SEL numberOfRowsSelector = @selector(numberOfRowsInSection:);
    SEL rectForSectionSelector = @selector(rectForSection:);
    Method popMethod = class_getInstanceMethod(UINavigationController.class, popSelector);
    Method viewWillAppearMethod = class_getInstanceMethod(mainFrameClass, viewWillAppearSelector);
    Method numberOfRowsMethod = class_getInstanceMethod(UITableView.class, numberOfRowsSelector);
    Method rectForSectionMethod = class_getInstanceMethod(UITableView.class, rectForSectionSelector);
    if (mainFrameClass == Nil ||
        popMethod == NULL ||
        viewWillAppearMethod == NULL ||
        numberOfRowsMethod == NULL ||
        rectForSectionMethod == NULL) {
        if (!WCLiquidGlassWCGlassHookInstallRetryScheduled &&
            WCLiquidGlassWCGlassHookInstallAttempts < 10) {
            WCLiquidGlassWCGlassHookInstallRetryScheduled = YES;
            WCLiquidGlassWCGlassHookInstallAttempts += 1;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                WCLiquidGlassWCGlassHookInstallRetryScheduled = NO;
                WCLiquidGlassInstallWCGlassReturnHooksIfNeeded();
            });
        }
        return;
    }
    MSHookMessageEx(UINavigationController.class,
                    popSelector,
                    (IMP)&WCLiquidGlassStableNavigationPopViewController,
                    (IMP *)&WCLiquidGlassOriginalNavigationPopViewController);
    MSHookMessageEx(mainFrameClass,
                    viewWillAppearSelector,
                    (IMP)&WCLiquidGlassStableMainFrameViewWillAppear,
                    (IMP *)&WCLiquidGlassOriginalMainFrameViewWillAppear);
    MSHookMessageEx(UITableView.class,
                    numberOfRowsSelector,
                    (IMP)&WCLiquidGlassGuardedTableViewNumberOfRows,
                    (IMP *)&WCLiquidGlassOriginalTableViewNumberOfRows);
    MSHookMessageEx(UITableView.class,
                    rectForSectionSelector,
                    (IMP)&WCLiquidGlassGuardedTableViewRectForSection,
                    (IMP *)&WCLiquidGlassOriginalTableViewRectForSection);
    WCLiquidGlassWCGlassReturnHooksInstalled =
        WCLiquidGlassOriginalNavigationPopViewController != NULL &&
        WCLiquidGlassOriginalMainFrameViewWillAppear != NULL &&
        WCLiquidGlassOriginalTableViewNumberOfRows != NULL &&
        WCLiquidGlassOriginalTableViewRectForSection != NULL;
    [WCLiquidGlassCrashLogger.sharedLogger recordEvent:
        WCLiquidGlassWCGlassReturnHooksInstalled
            ? @"WCGlassReturn stale section guard hooks installed"
            : @"WCGlassReturn stale section guard hooks failed"];
}

static void WCLiquidGlassReportManualTextEdit(id inputView) {
    if (WCLiquidGlassDictationWriteDepth > 0 || !WCLiquidGlassShouldReportManualTextEdit()) {
        return;
    }
    [NSNotificationCenter.defaultCenter postNotificationName:WCLiquidGlassManualTextEditNotification
                                                      object:inputView];
}

static void WCLiquidGlassTryRegisterPlugin(void);

static void WCLiquidGlassScheduleRegistrationRetry(void) {
    if (WCLiquidGlassPluginRegistered || WCLiquidGlassRegistrationAttempts >= 15) {
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        WCLiquidGlassTryRegisterPlugin();
    });
}

static void WCLiquidGlassTryRegisterPlugin(void) {
    if (WCLiquidGlassPluginRegistered) {
        return;
    }
    WCLiquidGlassRegistrationAttempts += 1;

    Class managerClass = NSClassFromString(@"WCPluginsMgr");
    SEL sharedSelector = NSSelectorFromString(@"sharedInstance");
    SEL registerSelector = NSSelectorFromString(@"registerControllerWithTitle:version:controller:");

    if (managerClass == Nil || ![managerClass respondsToSelector:sharedSelector]) {
        WCLiquidGlassScheduleRegistrationRetry();
        return;
    }

    id manager = ((id (*)(id, SEL))objc_msgSend)(managerClass, sharedSelector);
    if (!manager || ![manager respondsToSelector:registerSelector]) {
        WCLiquidGlassScheduleRegistrationRetry();
        return;
    }

    NSMethodSignature *signature = [manager methodSignatureForSelector:registerSelector];
    if (signature.numberOfArguments < 5) {
        WCLiquidGlassScheduleRegistrationRetry();
        return;
    }

    const char *controllerArgumentType = [signature getArgumentTypeAtIndex:4];
    if (controllerArgumentType == NULL || controllerArgumentType[0] == '#') {
        WCLiquidGlassScheduleRegistrationRetry();
        return;
    }

    ((void (*)(id, SEL, id, id, id))objc_msgSend)(manager,
                                                  registerSelector,
                                                  @"WCLiquidGlass",
                                                  [NSString stringWithUTF8String:WCLIQUIDGLASS_VERSION],
                                                  NSStringFromClass(WCLiquidGlass.class));
    WCLiquidGlassPluginRegistered = YES;
}

%hook MMInputToolView

- (void)layoutSubviews {
    %orig;
    WCLiquidGlassInstallChatBottomMenuHooks();
    WCLiquidGlassUpdateDoutuButtonVisibility(self);
}

%end

%hook MMGrowTextView

- (void)MMDictationLogicIcon_replaceRange:(NSRange)range withText:(NSString *)text {
    WCLiquidGlassDictationWriteDepth += 1;
    @try {
        %orig;
    } @finally {
        WCLiquidGlassDictationWriteDepth -= 1;
    }
}

%end

%hook MMTextView

- (void)insertText:(NSString *)text {
    WCLiquidGlassReportManualTextEdit(self);
    %orig;
}

- (void)deleteBackward {
    WCLiquidGlassReportManualTextEdit(self);
    %orig;
}

- (void)setMarkedText:(NSString *)markedText selectedRange:(NSRange)selectedRange {
    WCLiquidGlassReportManualTextEdit(self);
    %orig;
}

- (void)paste:(id)sender {
    WCLiquidGlassReportManualTextEdit(self);
    %orig;
}

%end

%ctor {
    @autoreleasepool {
        NSString *bundleIdentifier = NSBundle.mainBundle.bundleIdentifier;
        BOOL isMainWeChatProcess = [bundleIdentifier isEqualToString:@"com.tencent.xin"];
        BOOL isShareTimelineProcess = [bundleIdentifier isEqualToString:@"com.tencent.xin.sharetimeline"];
        if (!isMainWeChatProcess && !isShareTimelineProcess) {
            return;
        }

        [WCLiquidGlassPreferences registerDefaults];
        WCLiquidGlassInstallMaterialFileProtectionHooks();
        if (!isMainWeChatProcess) {
            return;
        }

        [WCLiquidGlassCrashLogger.sharedLogger start];

        dispatch_async(dispatch_get_main_queue(), ^{
            WCLiquidGlassInstallWCGlassReturnHooksIfNeeded();
            WCLiquidGlassInstallWCGlassLongPressHooks();
            WCLiquidGlassInstallWCGlassSearchTabBarHooks();
            WCLiquidGlassInstallChatTimeGlassHooks();
            WCLiquidGlassInstallChatBottomMenuHooks();
            WCLiquidGlassInstallHomeCornersHooks();
            WCLiquidGlassInstallContactsIndexHooks();
            WCLiquidGlassInstallMessageNotificationHooks();
            [WCLiquidGlassManager.sharedManager start];
            WCLiquidGlassTryRegisterPlugin();
        });

        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
                                                        object:nil
                                                         queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(__unused NSNotification *notification) {
            WCLiquidGlassTryRegisterPlugin();
        }];

        [NSNotificationCenter.defaultCenter addObserverForName:WCLiquidGlassWCGlassCompatibilityDidChangeNotification
                                                        object:nil
                                                         queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(__unused NSNotification *notification) {
            if (WCLiquidGlassPreferences.wcGlassIOS27CompatibilityEnabled) {
                WCLiquidGlassInstallWCGlassReturnHooksIfNeeded();
            } else if (WCLiquidGlassWCGlassRowGuardActive ||
                       WCLiquidGlassWCGlassRiskyReturnPending) {
                WCLiquidGlassFinishWCGlassRowGuard(@"compatibility disabled");
            }
        }];

        [NSNotificationCenter.defaultCenter addObserverForName:UIKeyboardWillShowNotification
                                                        object:nil
                                                         queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(__unused NSNotification *notification) {
            WCLiquidGlassKeyboardVisible = YES;
        }];

        [NSNotificationCenter.defaultCenter addObserverForName:UIKeyboardDidHideNotification
                                                        object:nil
                                                         queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(__unused NSNotification *notification) {
            WCLiquidGlassKeyboardVisible = NO;
        }];

    }
}
