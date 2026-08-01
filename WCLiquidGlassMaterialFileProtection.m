#import "WCLiquidGlassMaterialFileProtection.h"

#import <CydiaSubstrate.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <stdatomic.h>

#import "WCLiquidGlassPreferences.h"

static void (*WCLiquidGlassOriginalDiskUsageScanerStart)(id, SEL, id) = NULL;
static void (*WCLiquidGlassOriginalSetDeleteUnknow)(id, SEL, BOOL) = NULL;
static void (*WCLiquidGlassOriginalSetReportDeleteUnknow)(id, SEL, BOOL) = NULL;
static void (*WCLiquidGlassOriginalSetDeleteEmptyFolder)(id, SEL, BOOL) = NULL;
static BOOL (*WCLiquidGlassOriginalRemoveItemAtPath)(NSFileManager *, SEL, NSString *, NSError **) = NULL;
static BOOL (*WCLiquidGlassOriginalShouldMoveItem)(NSFileManager *, SEL, id, NSString *, NSString *) = NULL;

static BOOL WCLiquidGlassDiskUsageScanerHookInstalled = NO;
static BOOL WCLiquidGlassSetDeleteUnknowHookInstalled = NO;
static BOOL WCLiquidGlassSetReportDeleteUnknowHookInstalled = NO;
static BOOL WCLiquidGlassSetDeleteEmptyFolderHookInstalled = NO;
static BOOL WCLiquidGlassRemoveItemHookInstalled = NO;
static BOOL WCLiquidGlassShouldMoveItemHookInstalled = NO;
static BOOL WCLiquidGlassMaterialFileProtectionRetryScheduled = NO;
static NSUInteger WCLiquidGlassMaterialFileProtectionInstallAttempts = 0;
static BOOL WCLiquidGlassMaterialFileProtectionObserverInstalled = NO;
static atomic_bool WCLiquidGlassMaterialFileProtectionEnabled = ATOMIC_VAR_INIT(true);

// ThemePro bypasses its own resource operations through this state.
static BOOL WCLiquidGlassMaterialFileWorking = NO;

static void WCLiquidGlassReloadMaterialFileProtectionPreference(void) {
    atomic_store_explicit(&WCLiquidGlassMaterialFileProtectionEnabled,
                          WCLiquidGlassPreferences.materialFileProtectionEnabled,
                          memory_order_relaxed);
}

static void WCLiquidGlassMaterialFileProtectionPreferenceChanged(
    __unused CFNotificationCenterRef center,
    __unused void *observer,
    __unused CFNotificationName name,
    __unused const void *object,
    __unused CFDictionaryRef userInfo) {
    WCLiquidGlassReloadMaterialFileProtectionPreference();
}

static BOOL WCLiquidGlassMaterialFileProtectionPreferenceEnabled(void) {
    return atomic_load_explicit(&WCLiquidGlassMaterialFileProtectionEnabled,
                                memory_order_relaxed);
}

static BOOL WCLiquidGlassMaterialFileProtectionIsActive(void) {
    return WCLiquidGlassMaterialFileProtectionPreferenceEnabled() &&
        !WCLiquidGlassMaterialFileWorking;
}

static BOOL WCLiquidGlassPathContainsAny(NSString *path, NSArray<NSString *> *components) {
    if (![path isKindOfClass:NSString.class]) {
        return NO;
    }
    for (NSString *component in components) {
        if ([path containsString:component]) {
            return YES;
        }
    }
    return NO;
}

static NSArray<NSString *> *WCLiquidGlassRemoveItemProtectedComponents(void) {
    static NSArray<NSString *> *components;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        components = @[
            @"ThemePro",
            @"MemoryStatKV",
            @"MMResourceMgr",
            @"MMCDNSource",
            @"currentTpBundle",
            @"95555E94-EF53-47DF-856E-D968CA855806",
            @"Assets.themePro",
            @"icon.png",
            @"info.json",
            @"weui_color.xml",
            @"DIY",
            @"_tempCopyCaches"
        ];
    });
    return components;
}

static NSArray<NSString *> *WCLiquidGlassMoveItemProtectedComponents(void) {
    static NSArray<NSString *> *components;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        components = @[
            @"ThemePro",
            @"MemoryStatKV",
            @"MMResourceMgr",
            @"MMCDNSource",
            @"currentTpBundle",
            @"95555E94-EF53-47DF-856E-D968CA855806",
            @"Assets.themePro",
            @"icon.png",
            @"info.json",
            @"weui_color.xml",
            @"DIY"
        ];
    });
    return components;
}

static void WCLiquidGlassSetDiskUsageBoolean(id config, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    if ([config respondsToSelector:selector]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(config, selector, NO);
    }
}

static void WCLiquidGlassDiskUsageScanerStart(id self, SEL selector, id config) {
    if (WCLiquidGlassMaterialFileProtectionPreferenceEnabled()) {
        WCLiquidGlassSetDiskUsageBoolean(config, @"setM_isDeleteUnknow:");
        WCLiquidGlassSetDiskUsageBoolean(config, @"setM_isReportDelUnknow:");
        WCLiquidGlassSetDiskUsageBoolean(config, @"setIsDeleteEmptyFolder:");
    }
    if (WCLiquidGlassOriginalDiskUsageScanerStart) {
        WCLiquidGlassOriginalDiskUsageScanerStart(self, selector, config);
    }
}

static void WCLiquidGlassSetDeleteUnknow(id self, SEL selector, BOOL value) {
    if (WCLiquidGlassOriginalSetDeleteUnknow) {
        WCLiquidGlassOriginalSetDeleteUnknow(self,
                                             selector,
                                             WCLiquidGlassMaterialFileProtectionPreferenceEnabled() ? NO : value);
    }
}

static void WCLiquidGlassSetReportDeleteUnknow(id self, SEL selector, BOOL value) {
    if (WCLiquidGlassOriginalSetReportDeleteUnknow) {
        WCLiquidGlassOriginalSetReportDeleteUnknow(self,
                                                   selector,
                                                   WCLiquidGlassMaterialFileProtectionPreferenceEnabled() ? NO : value);
    }
}

static void WCLiquidGlassSetDeleteEmptyFolder(id self, SEL selector, BOOL value) {
    if (WCLiquidGlassOriginalSetDeleteEmptyFolder) {
        WCLiquidGlassOriginalSetDeleteEmptyFolder(self,
                                                  selector,
                                                  WCLiquidGlassMaterialFileProtectionPreferenceEnabled() ? NO : value);
    }
}

static BOOL WCLiquidGlassRemoveItemAtPath(NSFileManager *self,
                                          SEL selector,
                                          NSString *path,
                                          NSError **error) {
    if (WCLiquidGlassMaterialFileProtectionIsActive() &&
        WCLiquidGlassPathContainsAny(path, WCLiquidGlassRemoveItemProtectedComponents())) {
        return YES;
    }
    return WCLiquidGlassOriginalRemoveItemAtPath
        ? WCLiquidGlassOriginalRemoveItemAtPath(self, selector, path, error)
        : NO;
}

static BOOL WCLiquidGlassShouldMoveItem(NSFileManager *self,
                                        SEL selector,
                                        id operation,
                                        NSString *fromPath,
                                        NSString *toPath) {
    if (WCLiquidGlassMaterialFileProtectionIsActive() &&
        WCLiquidGlassPathContainsAny(fromPath, WCLiquidGlassMoveItemProtectedComponents())) {
        return NO;
    }
    return WCLiquidGlassOriginalShouldMoveItem
        ? WCLiquidGlassOriginalShouldMoveItem(self, selector, operation, fromPath, toPath)
        : NO;
}

static void WCLiquidGlassInstallMaterialFileProtectionHooksNow(void) {
    Class scanerClass = NSClassFromString(@"MMDiskUsageScaner");
    Class scanConfigClass = NSClassFromString(@"MMDiskUsageScanConfig");
    SEL startSelector = NSSelectorFromString(@"startWithScanConfig:");
    SEL deleteUnknowSelector = NSSelectorFromString(@"setM_isDeleteUnknow:");
    SEL reportDeleteUnknowSelector = NSSelectorFromString(@"setM_isReportDelUnknow:");
    SEL deleteEmptyFolderSelector = NSSelectorFromString(@"setIsDeleteEmptyFolder:");
    SEL removeItemSelector = @selector(removeItemAtPath:error:);
    SEL shouldMoveItemSelector = NSSelectorFromString(@"filesystemItemMoveOperation:shouldMoveItemAtPath:toPath:");

    if (!WCLiquidGlassDiskUsageScanerHookInstalled &&
        class_getInstanceMethod(scanerClass, startSelector) != NULL) {
        MSHookMessageEx(scanerClass,
                        startSelector,
                        (IMP)&WCLiquidGlassDiskUsageScanerStart,
                        (IMP *)&WCLiquidGlassOriginalDiskUsageScanerStart);
        WCLiquidGlassDiskUsageScanerHookInstalled = WCLiquidGlassOriginalDiskUsageScanerStart != NULL;
    }
    if (!WCLiquidGlassSetDeleteUnknowHookInstalled &&
        class_getInstanceMethod(scanConfigClass, deleteUnknowSelector) != NULL) {
        MSHookMessageEx(scanConfigClass,
                        deleteUnknowSelector,
                        (IMP)&WCLiquidGlassSetDeleteUnknow,
                        (IMP *)&WCLiquidGlassOriginalSetDeleteUnknow);
        WCLiquidGlassSetDeleteUnknowHookInstalled = WCLiquidGlassOriginalSetDeleteUnknow != NULL;
    }
    if (!WCLiquidGlassSetReportDeleteUnknowHookInstalled &&
        class_getInstanceMethod(scanConfigClass, reportDeleteUnknowSelector) != NULL) {
        MSHookMessageEx(scanConfigClass,
                        reportDeleteUnknowSelector,
                        (IMP)&WCLiquidGlassSetReportDeleteUnknow,
                        (IMP *)&WCLiquidGlassOriginalSetReportDeleteUnknow);
        WCLiquidGlassSetReportDeleteUnknowHookInstalled = WCLiquidGlassOriginalSetReportDeleteUnknow != NULL;
    }
    if (!WCLiquidGlassSetDeleteEmptyFolderHookInstalled &&
        class_getInstanceMethod(scanConfigClass, deleteEmptyFolderSelector) != NULL) {
        MSHookMessageEx(scanConfigClass,
                        deleteEmptyFolderSelector,
                        (IMP)&WCLiquidGlassSetDeleteEmptyFolder,
                        (IMP *)&WCLiquidGlassOriginalSetDeleteEmptyFolder);
        WCLiquidGlassSetDeleteEmptyFolderHookInstalled = WCLiquidGlassOriginalSetDeleteEmptyFolder != NULL;
    }
    if (!WCLiquidGlassRemoveItemHookInstalled &&
        class_getInstanceMethod(NSFileManager.class, removeItemSelector) != NULL) {
        MSHookMessageEx(NSFileManager.class,
                        removeItemSelector,
                        (IMP)&WCLiquidGlassRemoveItemAtPath,
                        (IMP *)&WCLiquidGlassOriginalRemoveItemAtPath);
        WCLiquidGlassRemoveItemHookInstalled = WCLiquidGlassOriginalRemoveItemAtPath != NULL;
    }
    if (!WCLiquidGlassShouldMoveItemHookInstalled &&
        class_getInstanceMethod(NSFileManager.class, shouldMoveItemSelector) != NULL) {
        MSHookMessageEx(NSFileManager.class,
                        shouldMoveItemSelector,
                        (IMP)&WCLiquidGlassShouldMoveItem,
                        (IMP *)&WCLiquidGlassOriginalShouldMoveItem);
        WCLiquidGlassShouldMoveItemHookInstalled = WCLiquidGlassOriginalShouldMoveItem != NULL;
    }
}

void WCLiquidGlassInstallMaterialFileProtectionHooks(void) {
    if (!WCLiquidGlassMaterialFileProtectionObserverInstalled) {
        WCLiquidGlassMaterialFileProtectionObserverInstalled = YES;
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            WCLiquidGlassMaterialFileProtectionPreferenceChanged,
            (__bridge CFStringRef)WCLiquidGlassMaterialFileProtectionDarwinNotification,
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
        WCLiquidGlassReloadMaterialFileProtectionPreference();
    }
    WCLiquidGlassInstallMaterialFileProtectionHooksNow();
    BOOL allHooksInstalled =
        WCLiquidGlassDiskUsageScanerHookInstalled &&
        WCLiquidGlassSetDeleteUnknowHookInstalled &&
        WCLiquidGlassSetReportDeleteUnknowHookInstalled &&
        WCLiquidGlassSetDeleteEmptyFolderHookInstalled &&
        WCLiquidGlassRemoveItemHookInstalled &&
        WCLiquidGlassShouldMoveItemHookInstalled;
    if (allHooksInstalled || WCLiquidGlassMaterialFileProtectionRetryScheduled ||
        WCLiquidGlassMaterialFileProtectionInstallAttempts >= 20) {
        return;
    }
    WCLiquidGlassMaterialFileProtectionRetryScheduled = YES;
    WCLiquidGlassMaterialFileProtectionInstallAttempts += 1;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        WCLiquidGlassMaterialFileProtectionRetryScheduled = NO;
        WCLiquidGlassInstallMaterialFileProtectionHooks();
    });
}
