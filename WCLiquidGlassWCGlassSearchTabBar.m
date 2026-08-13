#import "WCLiquidGlassWCGlassSearchTabBar.h"

#import "WCLiquidGlassMenu.h"

#import <CydiaSubstrate.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

static const NSInteger WCLiquidGlassWCGlassSearchTabBarTabCount = 4;
static BOOL WCLiquidGlassWCGlassSearchTabBarHooksInstalled = NO;
static BOOL WCLiquidGlassWCGlassSearchTabBarHookRetryScheduled = NO;
static NSUInteger WCLiquidGlassWCGlassSearchTabBarHookInstallAttempts = 0;
static void (*WCLiquidGlassOriginalWCGlassSearchTabBarSelectIndex)(id, SEL, NSInteger) = NULL;

static Class WCLiquidGlassWCGlassSearchTabBarOverlayClass(void) {
    Class legacyClass = NSClassFromString(@"WCLGSearchTabBarOverlay");
    if (legacyClass) {
        return legacyClass;
    }
    return NSClassFromString(@"qz64vfjsximzq3xbay5woqdm");
}

static id WCLiquidGlassWCGlassSearchTabBarObjectValue(id target, SEL selector) {
    if (!target || !selector || ![target respondsToSelector:selector]) {
        return nil;
    }
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(target, selector);
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static NSInteger WCLiquidGlassWCGlassSearchTabBarIntegerValue(id target,
                                                               SEL selector,
                                                               NSInteger fallback) {
    if (!target || !selector || ![target respondsToSelector:selector]) {
        return fallback;
    }
    @try {
        return ((NSInteger (*)(id, SEL))objc_msgSend)(target, selector);
    } @catch (__unused NSException *exception) {
        return fallback;
    }
}

static void WCLiquidGlassWCGlassSearchTabBarInvoke(id target, SEL selector) {
    if (target && selector && [target respondsToSelector:selector]) {
        ((void (*)(id, SEL))objc_msgSend)(target, selector);
    }
}

static void WCLiquidGlassWCGlassSearchTabBarSetInteger(id target,
                                                       SEL selector,
                                                       NSInteger value) {
    if (target && selector && [target respondsToSelector:selector]) {
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(target, selector, value);
    }
}

static void WCLiquidGlassWCGlassSearchTabBarSetBool(id target,
                                                    SEL selector,
                                                    BOOL value) {
    if (target && selector && [target respondsToSelector:selector]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(target, selector, value);
    }
}

static void WCLiquidGlassWCGlassSearchTabBarSetMenuVisible(id target,
                                                           BOOL visible,
                                                           BOOL animated) {
    SEL selector = NSSelectorFromString(@"setMenuVisible:animated:");
    if (target && [target respondsToSelector:selector]) {
        ((void (*)(id, SEL, BOOL, BOOL))objc_msgSend)(target,
                                                     selector,
                                                     visible,
                                                     animated);
    }
}

static BOOL WCLiquidGlassWCGlassSearchTabBarCanSelect(id tabController,
                                                      NSInteger index) {
    if (!tabController ||
        index < 0 ||
        index >= WCLiquidGlassWCGlassSearchTabBarTabCount ||
        ![tabController respondsToSelector:NSSelectorFromString(@"setSelectedIndex:")]) {
        return NO;
    }
    id viewControllers = WCLiquidGlassWCGlassSearchTabBarObjectValue(
        tabController,
        NSSelectorFromString(@"viewControllers"));
    return [viewControllers isKindOfClass:NSArray.class] &&
        index < (NSInteger)[viewControllers count];
}

static void WCLiquidGlassSafeWCGlassSearchTabBarSelectIndex(id self,
                                                            SEL selector,
                                                            NSInteger index) {
    id tabController = WCLiquidGlassCurrentTabController();
    if (!WCLiquidGlassWCGlassSearchTabBarCanSelect(tabController, index)) {
        if (WCLiquidGlassOriginalWCGlassSearchTabBarSelectIndex) {
            WCLiquidGlassOriginalWCGlassSearchTabBarSelectIndex(self, selector, index);
        }
        return;
    }
    NSInteger currentIndex = WCLiquidGlassWCGlassSearchTabBarIntegerValue(
        tabController,
        NSSelectorFromString(@"selectedIndex"),
        NSNotFound);
    if (currentIndex == index) {
        if (WCLiquidGlassOriginalWCGlassSearchTabBarSelectIndex) {
            WCLiquidGlassOriginalWCGlassSearchTabBarSelectIndex(self, selector, index);
        }
        return;
    }

    SEL selectingIndexSelector = NSSelectorFromString(@"selectingIndex");
    if (WCLiquidGlassWCGlassSearchTabBarIntegerValue(self,
                                                     selectingIndexSelector,
                                                     0) != 0) {
        return;
    }

    @try {
        WCLiquidGlassWCGlassSearchTabBarSetBool(
            self,
            NSSelectorFromString(@"setSelectingIndex:"),
            YES);
        WCLiquidGlassWCGlassSearchTabBarInvoke(
            self,
            NSSelectorFromString(@"lightFeedback"));
        WCLiquidGlassWCGlassSearchTabBarSetInteger(
            self,
            NSSelectorFromString(@"setHighlightedIndex:"),
            index);
        WCLiquidGlassWCGlassSearchTabBarInvoke(
            self,
            NSSelectorFromString(@"updateOptionHighlights"));
        WCLiquidGlassWCGlassSearchTabBarSetMenuVisible(self, NO, YES);

        WCLiquidGlassWCGlassSearchTabBarSetInteger(
            tabController,
            NSSelectorFromString(@"setSelectedIndex:"),
            index);

        dispatch_async(dispatch_get_main_queue(), ^{
            WCLiquidGlassWCGlassSearchTabBarInvoke(
                self,
                @selector(setNeedsLayout));
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(0.26 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            WCLiquidGlassWCGlassSearchTabBarSetBool(
                self,
                NSSelectorFromString(@"setSelectingIndex:"),
                NO);
        });
    } @catch (__unused NSException *exception) {
        WCLiquidGlassWCGlassSearchTabBarSetBool(
            self,
            NSSelectorFromString(@"setSelectingIndex:"),
            NO);
        if (WCLiquidGlassOriginalWCGlassSearchTabBarSelectIndex) {
            WCLiquidGlassOriginalWCGlassSearchTabBarSelectIndex(self, selector, index);
        }
    }
}

void WCLiquidGlassInstallWCGlassSearchTabBarHooks(void) {
    if (WCLiquidGlassWCGlassSearchTabBarHooksInstalled) {
        return;
    }

    Class overlayClass = WCLiquidGlassWCGlassSearchTabBarOverlayClass();
    SEL selectIndexSelector = NSSelectorFromString(@"selectIndex:");
    Method selectIndexMethod = overlayClass
        ? class_getInstanceMethod(overlayClass, selectIndexSelector)
        : NULL;
    if (overlayClass == Nil || selectIndexMethod == NULL) {
        if (!WCLiquidGlassWCGlassSearchTabBarHookRetryScheduled &&
            WCLiquidGlassWCGlassSearchTabBarHookInstallAttempts < 20) {
            WCLiquidGlassWCGlassSearchTabBarHookRetryScheduled = YES;
            WCLiquidGlassWCGlassSearchTabBarHookInstallAttempts += 1;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                         (int64_t)(0.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                WCLiquidGlassWCGlassSearchTabBarHookRetryScheduled = NO;
                WCLiquidGlassInstallWCGlassSearchTabBarHooks();
            });
        }
        return;
    }

    MSHookMessageEx(overlayClass,
                    selectIndexSelector,
                    (IMP)&WCLiquidGlassSafeWCGlassSearchTabBarSelectIndex,
                    (IMP *)&WCLiquidGlassOriginalWCGlassSearchTabBarSelectIndex);
    WCLiquidGlassWCGlassSearchTabBarHooksInstalled =
        WCLiquidGlassOriginalWCGlassSearchTabBarSelectIndex != NULL;
}
