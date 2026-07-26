#import "WCLiquidGlassMenu.h"
#import "WCLiquidGlassIconAssets.h"
#import "WCLiquidGlassPreferences.h"

#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>

static const CGFloat WCLiquidGlassContainerSpacing = 8.0;
static const CGFloat WCLiquidGlassSelectedScale = 1.5;
static const NSUInteger WCLiquidGlassCompactMinimumCount = 7;
static const NSUInteger WCLiquidGlassDoubleCrescentMinimumCount = 8;
NSString *const WCLiquidGlassManualTextEditNotification = @"WCLiquidGlassManualTextEditNotification";
static BOOL WCLiquidGlassManualTextEditMonitoringEnabled = NO;
static BOOL WCLiquidGlassDoutuConfiguredCached = NO;
static char WCLiquidGlassDoutuCachedButtonKey;
static char WCLiquidGlassDoutuLastVisibilityKey;

static void WCLiquidGlassAppendArcOffsets(NSMutableArray<NSValue *> *offsets,
                                           NSUInteger count,
                                           CGFloat radius,
                                           CGFloat startAngle,
                                           CGFloat endAngle,
                                           CGFloat centerX) {
    if (count == 0) {
        return;
    }
    if (count == 1) {
        [offsets addObject:[NSValue valueWithCGPoint:CGPointMake(centerX + radius, 0.0)]];
        return;
    }
    for (NSUInteger index = 0; index < count; index += 1) {
        CGFloat progress = (CGFloat)index / (count - 1);
        CGFloat angle = startAngle + (endAngle - startAngle) * progress;
        [offsets addObject:[NSValue valueWithCGPoint:CGPointMake(centerX + radius * cos(angle),
                                                                 radius * sin(angle))]];
    }
}

static CGPoint WCLiquidGlassCubicPoint(CGFloat progress,
                                       CGPoint start,
                                       CGPoint control1,
                                       CGPoint control2,
                                       CGPoint end) {
    CGFloat inverse = 1.0 - progress;
    return CGPointMake(inverse * inverse * inverse * start.x +
                           3.0 * inverse * inverse * progress * control1.x +
                           3.0 * inverse * progress * progress * control2.x +
                           progress * progress * progress * end.x,
                       inverse * inverse * inverse * start.y +
                           3.0 * inverse * inverse * progress * control1.y +
                           3.0 * inverse * progress * progress * control2.y +
                           progress * progress * progress * end.y);
}

static CGPoint WCLiquidGlassFlowingSPoint(CGFloat progress) {
    return progress <= 0.5
        ? WCLiquidGlassCubicPoint(progress * 2.0,
                                  CGPointMake(165.0, -132.0),
                                  CGPointMake(20.0, -132.0),
                                  CGPointMake(20.0, -42.0),
                                  CGPointMake(132.0, 0.0))
        : WCLiquidGlassCubicPoint((progress - 0.5) * 2.0,
                                  CGPointMake(132.0, 0.0),
                                  CGPointMake(244.0, 42.0),
                                  CGPointMake(244.0, 132.0),
                                  CGPointMake(98.0, 132.0));
}

static void WCLiquidGlassEqualFlowingSPoints(NSUInteger count,
                                              CGPoint output[12]) {
    const NSUInteger sampleCount = 600;
    CGPoint sampledPoints[601];
    CGFloat cumulativeLengths[601];
    sampledPoints[0] = WCLiquidGlassFlowingSPoint(0.0);
    cumulativeLengths[0] = 0.0;
    for (NSUInteger sample = 1; sample <= sampleCount; sample += 1) {
        sampledPoints[sample] = WCLiquidGlassFlowingSPoint((CGFloat)sample / sampleCount);
        cumulativeLengths[sample] = cumulativeLengths[sample - 1] +
            hypot(sampledPoints[sample].x - sampledPoints[sample - 1].x,
                  sampledPoints[sample].y - sampledPoints[sample - 1].y);
    }

    NSUInteger upper = 1;
    for (NSUInteger index = 0; index < count; index += 1) {
        CGFloat targetLength = cumulativeLengths[sampleCount] * index / MAX((CGFloat)count - 1.0, 1.0);
        while (upper < sampleCount && cumulativeLengths[upper] < targetLength) {
            upper += 1;
        }
        CGFloat segmentLength = cumulativeLengths[upper] - cumulativeLengths[upper - 1];
        CGFloat segmentProgress = segmentLength > 0.0001
            ? (targetLength - cumulativeLengths[upper - 1]) / segmentLength
            : 0.0;
        output[index] = CGPointMake(sampledPoints[upper - 1].x +
                                        (sampledPoints[upper].x - sampledPoints[upper - 1].x) * segmentProgress,
                                    sampledPoints[upper - 1].y +
                                        (sampledPoints[upper].y - sampledPoints[upper - 1].y) * segmentProgress);
    }
}

static CGFloat WCLiquidGlassMinimumPointDistance(CGPoint points[12], NSUInteger count) {
    CGFloat minimumDistance = CGFLOAT_MAX;
    for (NSUInteger first = 0; first < count; first += 1) {
        for (NSUInteger second = first + 1; second < count; second += 1) {
            minimumDistance = MIN(minimumDistance,
                                  hypot(points[first].x - points[second].x,
                                        points[first].y - points[second].y));
        }
    }
    return minimumDistance;
}

static void WCLiquidGlassAlignOffsetsToAnchorDistance(NSMutableArray<NSValue *> *offsets,
                                                       CGFloat desiredDistance) {
    if (offsets.count == 0) {
        return;
    }
    CGFloat minimumX = CGFLOAT_MAX;
    for (NSValue *value in offsets) {
        minimumX = MIN(minimumX, value.CGPointValue.x);
    }
    CGFloat low = -minimumX + 0.1;
    CGFloat high = low + 300.0;
    for (NSUInteger iteration = 0; iteration < 50; iteration += 1) {
        CGFloat middle = (low + high) * 0.5;
        CGFloat nearestDistance = CGFLOAT_MAX;
        for (NSValue *value in offsets) {
            CGPoint point = value.CGPointValue;
            nearestDistance = MIN(nearestDistance, hypot(point.x + middle, point.y));
        }
        if (nearestDistance < desiredDistance) {
            low = middle;
        } else {
            high = middle;
        }
    }
    CGFloat translation = (low + high) * 0.5;
    for (NSUInteger index = 0; index < offsets.count; index += 1) {
        CGPoint point = offsets[index].CGPointValue;
        offsets[index] = [NSValue valueWithCGPoint:CGPointMake(point.x + translation, point.y)];
    }
}

static void WCLiquidGlassAppendFlowingSOffsets(NSMutableArray<NSValue *> *offsets,
                                                NSUInteger count,
                                                CGFloat anchorClearance,
                                                CGFloat diameter) {
    CGPoint referencePoints[12];
    WCLiquidGlassEqualFlowingSPoints(count, referencePoints);
    CGFloat referenceMinimumDistance = WCLiquidGlassMinimumPointDistance(referencePoints, count);
    CGFloat scale = (diameter + 10.0) / MAX(referenceMinimumDistance, 0.0001);
    for (NSUInteger index = 0; index < count; index += 1) {
        CGPoint point = CGPointMake(referencePoints[index].x * scale,
                                    referencePoints[index].y * scale);
        [offsets addObject:[NSValue valueWithCGPoint:point]];
    }
    WCLiquidGlassAlignOffsetsToAnchorDistance(offsets, anchorClearance);
}

static CGFloat WCLiquidGlassRingHalfAngle(NSUInteger count,
                                           CGFloat radius,
                                           CGFloat targetCenterSpacing) {
    if (count <= 1) {
        return 0.0;
    }
    CGFloat step = 2.0 * asin(MIN(0.98, targetCenterSpacing / (2.0 * radius)));
    return step * (count - 1) * 0.5;
}

static void WCLiquidGlassCrescentRadii(NSUInteger innerCount,
                                       NSUInteger outerCount,
                                       CGFloat targetCenterSpacing,
                                       CGFloat span,
                                       CGFloat *innerRadius,
                                       CGFloat *outerRadius) {
    *innerRadius = targetCenterSpacing /
        (2.0 * sin(span / (2.0 * (innerCount - 1))));
    *outerRadius = targetCenterSpacing /
        (2.0 * sin(span / (2.0 * (outerCount - 1))));
}

BOOL WCLiquidGlassShouldReportManualTextEdit(void) {
    return WCLiquidGlassManualTextEditMonitoringEnabled;
}

static UIVisualEffect *WCLiquidGlassMakeEffect(void) {
    Class glassClass = NSClassFromString(@"UIGlassEffect");
    SEL factorySelector = NSSelectorFromString(@"effectWithStyle:");
    if (glassClass != Nil && [glassClass respondsToSelector:factorySelector]) {
        WCLiquidGlassGlassAppearance appearance = WCLiquidGlassPreferences.glassAppearance;
        UIVisualEffect *effect = ((id (*)(id, SEL, NSInteger))objc_msgSend)(glassClass,
                                                                           factorySelector,
                                                                           appearance == WCLiquidGlassGlassAppearanceClear ? 1 : 0);
        if (appearance == WCLiquidGlassGlassAppearanceTinted) {
            SEL tintColorSelector = NSSelectorFromString(@"setTintColor:");
            if ([effect respondsToSelector:tintColorSelector]) {
                UIColor *tintColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
                    return traits.userInterfaceStyle == UIUserInterfaceStyleDark
                        ? [UIColor colorWithWhite:1.0 alpha:0.23]
                        : [UIColor colorWithWhite:1.0 alpha:0.16];
                }];
                ((void (*)(id, SEL, id))objc_msgSend)(effect, tintColorSelector, tintColor);
            }
        }
        SEL interactiveSelector = NSSelectorFromString(@"setInteractive:");
        if ([effect respondsToSelector:interactiveSelector]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(effect, interactiveSelector, NO);
        }
        if (effect) {
            return effect;
        }
    }

    BOOL dark = UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    UIBlurEffectStyle style = dark ? UIBlurEffectStyleSystemThickMaterialDark
                                   : UIBlurEffectStyleSystemChromeMaterialLight;
    return [UIBlurEffect effectWithStyle:style];
}

static UIVisualEffect *WCLiquidGlassMakeContainerEffect(void) {
    Class containerClass = NSClassFromString(@"UIGlassContainerEffect");
    if (containerClass == Nil) {
        return nil;
    }

    id effect = [[containerClass alloc] init];
    SEL spacingSelector = NSSelectorFromString(@"setSpacing:");
    if ([effect respondsToSelector:spacingSelector]) {
        ((void (*)(id, SEL, CGFloat))objc_msgSend)(effect,
                                                  spacingSelector,
                                                  WCLiquidGlassContainerSpacing);
    }
    return effect;
}

static CGFloat WCLiquidGlassButtonDiameter(void) {
    switch (WCLiquidGlassPreferences.sizeMode) {
        case 0:
            return 53.0;
        case 2:
            return 66.0;
        default:
            return 60.0;
    }
}

static UIWindow *WCLiquidGlassApplicationWindow(void) {
    UIWindow *fallbackWindow = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive ||
            ![scene isKindOfClass:UIWindowScene.class]) {
            continue;
        }
        for (UIWindow *window in ((UIWindowScene *)scene).windows.reverseObjectEnumerator) {
            if (window.isKeyWindow &&
                ![NSStringFromClass(window.class) containsString:@"WCLiquidGlass"]) {
                if (window.windowLevel == UIWindowLevelNormal) {
                    return window;
                }
                fallbackWindow = window;
            }
        }
    }
    return fallbackWindow;
}

static UIViewController *WCLiquidGlassVisibleControllerFrom(UIViewController *controller) {
    if (!controller) {
        return nil;
    }
    if (controller.presentedViewController) {
        return WCLiquidGlassVisibleControllerFrom(controller.presentedViewController);
    }
    if ([controller isKindOfClass:UINavigationController.class]) {
        return WCLiquidGlassVisibleControllerFrom(((UINavigationController *)controller).visibleViewController);
    }
    if ([controller isKindOfClass:UITabBarController.class]) {
        return WCLiquidGlassVisibleControllerFrom(((UITabBarController *)controller).selectedViewController);
    }
    for (UIViewController *child in controller.childViewControllers) {
        UIViewController *visibleChild = WCLiquidGlassVisibleControllerFrom(child);
        if (visibleChild.viewIfLoaded.window) {
            return visibleChild;
        }
    }
    return controller;
}

static UITabBarController *WCLiquidGlassFindTabController(UIViewController *controller) {
    if (!controller) {
        return nil;
    }
    if ([controller isKindOfClass:UITabBarController.class]) {
        return (UITabBarController *)controller;
    }
    UITabBarController *presented = WCLiquidGlassFindTabController(controller.presentedViewController);
    if (presented) {
        return presented;
    }
    for (UIViewController *child in controller.childViewControllers) {
        UITabBarController *tabController = WCLiquidGlassFindTabController(child);
        if (tabController) {
            return tabController;
        }
    }
    return nil;
}

static id WCLiquidGlassFindMMTabController(UIViewController *controller) {
    if (!controller) {
        return nil;
    }
    if ([NSStringFromClass(controller.class) containsString:@"MMTabBarController"]) {
        return controller;
    }
    id presented = WCLiquidGlassFindMMTabController(controller.presentedViewController);
    if (presented) {
        return presented;
    }
    for (UIViewController *child in controller.childViewControllers) {
        id tabController = WCLiquidGlassFindMMTabController(child);
        if (tabController) {
            return tabController;
        }
    }
    return nil;
}

static id WCLiquidGlassObjectFromSelector(id target, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    if (!target || ![target respondsToSelector:selector]) {
        return nil;
    }
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(target, selector);
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static id WCLiquidGlassMMTabController(void) {
    UIViewController *rootController = WCLiquidGlassApplicationWindow().rootViewController;
    id tabController = WCLiquidGlassFindMMTabController(rootController);
    if (tabController) {
        return tabController;
    }

    id applicationDelegate = UIApplication.sharedApplication.delegate;
    NSArray *owners = @[applicationDelegate ?: (id)NSNull.null,
                        rootController ?: (id)NSNull.null,
                        WCLiquidGlassVisibleControllerFrom(rootController) ?: (id)NSNull.null];
    for (id owner in owners) {
        tabController = WCLiquidGlassObjectFromSelector(owner, @"getMMTabBarController");
        if (tabController) {
            return tabController;
        }
    }
    return nil;
}

static id WCLiquidGlassCurrentTabController(void) {
    id tabController = WCLiquidGlassMMTabController();
    return tabController ?: WCLiquidGlassFindTabController(WCLiquidGlassApplicationWindow().rootViewController);
}

static NSArray *WCLiquidGlassArrayFromSelectors(id target, NSArray<NSString *> *selectorNames) {
    for (NSString *selectorName in selectorNames) {
        id value = WCLiquidGlassObjectFromSelector(target, selectorName);
        if ([value isKindOfClass:NSArray.class] && [value count] > 0) {
            return value;
        }
    }
    return nil;
}

static NSArray *WCLiquidGlassPrivateTabSources(id tabController) {
    NSArray *sources = WCLiquidGlassArrayFromSelectors(tabController,
                                                       @[@"getTabBarBtnViews",
                                                         @"tabBarItemViews",
                                                         @"tabBarBtnViews",
                                                         @"tabBarBtns",
                                                         @"_tabBarBtns"]);
    if (sources.count > 0) {
        return sources;
    }

    id tabBar = WCLiquidGlassObjectFromSelector(tabController, @"tabBar");
    sources = WCLiquidGlassArrayFromSelectors(tabBar,
                                              @[@"getTabBarBtnViews",
                                                @"tabBarItemViews",
                                                @"tabBarBtnViews",
                                                @"tabBarBtns",
                                                @"_tabBarBtns"]);
    return sources;
}

static NSInteger WCLiquidGlassCurrentTabIndex(id tabController) {
    for (NSString *selectorName in @[@"selectedIndex", @"currentIndex"]) {
        SEL selector = NSSelectorFromString(selectorName);
        if ([tabController respondsToSelector:selector]) {
            return ((NSInteger (*)(id, SEL))objc_msgSend)(tabController, selector);
        }
    }
    return 0;
}

static UIImageView *WCLiquidGlassNativeImageViewInView(UIView *view) {
    if (!view) {
        return nil;
    }

    UIImageView *bestImageView = nil;
    CGFloat bestArea = 0.0;
    if ([view isKindOfClass:UIImageView.class]) {
        UIImageView *imageView = (UIImageView *)view;
        CGFloat width = CGRectGetWidth(imageView.bounds);
        CGFloat height = CGRectGetHeight(imageView.bounds);
        if (imageView.image && width >= 10.0 && height >= 10.0 && width <= 64.0 && height <= 64.0) {
            bestImageView = imageView;
            bestArea = width * height;
        }
    }

    for (UIView *subview in view.subviews) {
        UIImageView *candidate = WCLiquidGlassNativeImageViewInView(subview);
        if (!candidate) {
            continue;
        }
        CGFloat area = CGRectGetWidth(candidate.bounds) * CGRectGetHeight(candidate.bounds);
        if (area > bestArea) {
            bestImageView = candidate;
            bestArea = area;
        }
    }
    return bestImageView;
}

static NSArray<UIView *> *WCLiquidGlassNativeTabSources(UITabBarController *tabController) {
    NSMutableArray<UIView *> *sources = [NSMutableArray array];
    for (UIView *subview in tabController.tabBar.subviews) {
        if (CGRectGetWidth(subview.bounds) < 20.0) {
            continue;
        }
        NSString *className = NSStringFromClass(subview.class);
        if (([subview isKindOfClass:UIControl.class] || [className containsString:@"TabBarButton"]) &&
            WCLiquidGlassNativeImageViewInView(subview)) {
            [sources addObject:subview];
        }
    }
    [sources sortUsingComparator:^NSComparisonResult(UIView *left, UIView *right) {
        CGFloat leftX = CGRectGetMidX(left.frame);
        CGFloat rightX = CGRectGetMidX(right.frame);
        if (leftX < rightX) {
            return NSOrderedAscending;
        }
        if (leftX > rightX) {
            return NSOrderedDescending;
        }
        return NSOrderedSame;
    }];
    return sources.copy;
}

static UIImage *WCLiquidGlassImageFromSourceAtDepth(id source, NSUInteger depth) {
    if (!source || depth > 5) {
        return nil;
    }
    if ([source isKindOfClass:UIImage.class]) {
        return source;
    }

    for (NSString *selectorName in @[@"item", @"iconView", @"imageView"]) {
        id child = WCLiquidGlassObjectFromSelector(source, selectorName);
        if (child && child != source) {
            UIImage *image = WCLiquidGlassImageFromSourceAtDepth(child, depth + 1);
            if (image) {
                return image;
            }
        }
    }

    for (NSString *selectorName in @[@"highlightImage", @"selectedImage", @"icon", @"image", @"iconImage"]) {
        id candidate = WCLiquidGlassObjectFromSelector(source, selectorName);
        UIImage *image = WCLiquidGlassImageFromSourceAtDepth(candidate, depth + 1);
        if (image) {
            return image;
        }
    }

    if ([source isKindOfClass:UIView.class]) {
        UIImage *image = WCLiquidGlassNativeImageViewInView(source).image;
        if (image) {
            return image;
        }
    }
    return nil;
}

static UIImage *WCLiquidGlassImageFromSource(id source) {
    return WCLiquidGlassImageFromSourceAtDepth(source, 0);
}

static UIImage *WCLiquidGlassNativeTabImage(id tabController, NSInteger index) {
    NSArray *sources = WCLiquidGlassPrivateTabSources(tabController);
    if (index >= 0 && index < (NSInteger)sources.count) {
        UIImage *image = WCLiquidGlassImageFromSource(sources[index]);
        if (image) {
            return [image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        }
    }

    if (![tabController isKindOfClass:UITabBarController.class]) {
        return nil;
    }
    UITabBarController *systemTabController = tabController;
    sources = WCLiquidGlassNativeTabSources(systemTabController);
    if (index >= 0 && index < (NSInteger)sources.count) {
        UIImage *image = WCLiquidGlassImageFromSource(sources[index]);
        if (image) {
            return [image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        }
    }

    if (index >= 0 && index < (NSInteger)systemTabController.tabBar.items.count) {
        UITabBarItem *item = systemTabController.tabBar.items[index];
        UIImage *image = item.selectedImage ?: item.image;
        return [image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    }
    return nil;
}

static id WCLiquidGlassThemeManager(void) {
    Class serviceCenterClass = NSClassFromString(@"MMServiceCenter");
    Class themeManagerClass = NSClassFromString(@"MMThemeManager");
    SEL defaultCenterSelector = NSSelectorFromString(@"defaultCenter");
    SEL getServiceSelector = NSSelectorFromString(@"getService:");
    if (!serviceCenterClass || !themeManagerClass ||
        ![serviceCenterClass respondsToSelector:defaultCenterSelector]) {
        return nil;
    }
    @try {
        id serviceCenter = ((id (*)(id, SEL))objc_msgSend)(serviceCenterClass, defaultCenterSelector);
        if ([serviceCenter respondsToSelector:getServiceSelector]) {
            return ((id (*)(id, SEL, Class))objc_msgSend)(serviceCenter,
                                                          getServiceSelector,
                                                          themeManagerClass);
        }
    } @catch (__unused NSException *exception) {
    }
    return nil;
}

static UIColor *WCLiquidGlassDynamicIconColor(void) {
    UITraitCollection *traits = UITraitCollection.currentTraitCollection;
    return traits.userInterfaceStyle == UIUserInterfaceStyleDark
        ? UIColor.whiteColor
        : UIColor.blackColor;
}

static UIImage *WCLiquidGlassImageNamedFromCandidates(NSArray<NSString *> *assetNames) {
    id themeManager = WCLiquidGlassThemeManager();
    SEL svgSelector = NSSelectorFromString(@"svgImageNamed:color:");
    for (NSString *assetName in assetNames) {
        NSString *drawerAssetName = [NSString stringWithFormat:@"drawer_%@", assetName];
        if ([themeManager respondsToSelector:svgSelector]) {
            for (NSString *name in @[drawerAssetName, assetName]) {
                @try {
                    UIImage *image = ((id (*)(id, SEL, id, id))objc_msgSend)(themeManager,
                                                                            svgSelector,
                                                                            name,
                                                                            WCLiquidGlassDynamicIconColor());
                    if (image) {
                        return image;
                    }
                } @catch (__unused NSException *exception) {
                }
            }
        }
        UIImage *image = [UIImage imageNamed:drawerAssetName];
        if (image) {
            return [image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        }
        image = [UIImage imageNamed:assetName];
        if (image) {
            return [image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        }
    }
    return nil;
}

static UIImage *WCLiquidGlassWeChatAssetImage(NSString *actionIdentifier) {
    return WCLiquidGlassImageNamedFromCandidates(WCLiquidGlassActionAssetNames(actionIdentifier));
}

static UIImage *WCLiquidGlassDoutuAssistantImage(void) {
    BOOL dark = UITraitCollection.currentTraitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    NSArray<NSString *> *fileNames = dark
        ? @[@"dt_dark_icon.png", @"dt_icon_dark.png", @"dt_icon.png"]
        : @[@"dt_icon.png", @"dt_dark_icon.png", @"dt_icon_dark.png"];
    for (NSString *fileName in fileNames) {
        NSArray<NSString *> *paths = @[
            [@"/var/jb/Library/PreferenceLoader/Preferences" stringByAppendingPathComponent:fileName],
            [@"/Library/PreferenceLoader/Preferences" stringByAppendingPathComponent:fileName],
            [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:fileName]
        ];
        for (NSString *path in paths) {
            UIImage *image = [UIImage imageWithContentsOfFile:path];
            if (image) {
                return [image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
            }
        }
        UIImage *image = [UIImage imageNamed:fileName];
        if (image) {
            return [image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        }
    }
    return nil;
}

static NSString *WCLiquidGlassSettingsIconFileName(WCLiquidGlassSettingsIconKind kind) {
    switch (kind) {
        case WCLiquidGlassSettingsIconKindBrand:
            return @"brand.png";
        case WCLiquidGlassSettingsIconKindMenu:
            return @"menu.png";
        case WCLiquidGlassSettingsIconKindSize:
            return @"size.png";
        case WCLiquidGlassSettingsIconKindCompactLayout:
            return @"compact-layout.png";
        case WCLiquidGlassSettingsIconKindGlassAppearance:
            return @"glass-appearance.png";
        case WCLiquidGlassSettingsIconKindActions:
            return @"actions.png";
        case WCLiquidGlassSettingsIconKindCompatibility:
            return @"compatibility.png";
        case WCLiquidGlassSettingsIconKindCrashCapture:
            return @"crash-capture.png";
        case WCLiquidGlassSettingsIconKindCrashLogs:
            return @"crash-logs.png";
        case WCLiquidGlassSettingsIconKindRestore:
            return @"restore.png";
    }
    return nil;
}

static NSData *WCLiquidGlassEmbeddedIconData(NSString *fileName) {
    const unsigned char *bytes = NULL;
    NSUInteger length = 0;
    if ([fileName isEqualToString:@"brand.png"]) {
        bytes = WCLiquidGlassIconBrand;
        length = WCLiquidGlassIconBrand_len;
    } else if ([fileName isEqualToString:@"brand-dark.png"]) {
        bytes = WCLiquidGlassIconBrandDark;
        length = WCLiquidGlassIconBrandDark_len;
    } else if ([fileName isEqualToString:@"menu.png"]) {
        bytes = WCLiquidGlassIconMenu;
        length = WCLiquidGlassIconMenu_len;
    } else if ([fileName isEqualToString:@"size.png"]) {
        bytes = WCLiquidGlassIconSize;
        length = WCLiquidGlassIconSize_len;
    } else if ([fileName isEqualToString:@"compact-layout.png"]) {
        bytes = WCLiquidGlassIconCompactLayout;
        length = WCLiquidGlassIconCompactLayout_len;
    } else if ([fileName isEqualToString:@"glass-appearance.png"]) {
        bytes = WCLiquidGlassIconGlassAppearance;
        length = WCLiquidGlassIconGlassAppearance_len;
    } else if ([fileName isEqualToString:@"actions.png"]) {
        bytes = WCLiquidGlassIconActions;
        length = WCLiquidGlassIconActions_len;
    } else if ([fileName isEqualToString:@"compatibility.png"]) {
        bytes = WCLiquidGlassIconCompatibility;
        length = WCLiquidGlassIconCompatibility_len;
    } else if ([fileName isEqualToString:@"crash-capture.png"]) {
        bytes = WCLiquidGlassIconCrashCapture;
        length = WCLiquidGlassIconCrashCapture_len;
    } else if ([fileName isEqualToString:@"crash-logs.png"]) {
        bytes = WCLiquidGlassIconCrashLogs;
        length = WCLiquidGlassIconCrashLogs_len;
    } else if ([fileName isEqualToString:@"restore.png"]) {
        bytes = WCLiquidGlassIconRestore;
        length = WCLiquidGlassIconRestore_len;
    } else if ([fileName isEqualToString:@"menu-dark.png"]) {
        bytes = WCLiquidGlassIconMenuDark;
        length = WCLiquidGlassIconMenuDark_len;
    } else if ([fileName isEqualToString:@"size-dark.png"]) {
        bytes = WCLiquidGlassIconSizeDark;
        length = WCLiquidGlassIconSizeDark_len;
    } else if ([fileName isEqualToString:@"compact-layout-dark.png"]) {
        bytes = WCLiquidGlassIconCompactLayoutDark;
        length = WCLiquidGlassIconCompactLayoutDark_len;
    } else if ([fileName isEqualToString:@"glass-appearance-dark.png"]) {
        bytes = WCLiquidGlassIconGlassAppearanceDark;
        length = WCLiquidGlassIconGlassAppearanceDark_len;
    } else if ([fileName isEqualToString:@"actions-dark.png"]) {
        bytes = WCLiquidGlassIconActionsDark;
        length = WCLiquidGlassIconActionsDark_len;
    } else if ([fileName isEqualToString:@"compatibility-dark.png"]) {
        bytes = WCLiquidGlassIconCompatibilityDark;
        length = WCLiquidGlassIconCompatibilityDark_len;
    } else if ([fileName isEqualToString:@"crash-capture-dark.png"]) {
        bytes = WCLiquidGlassIconCrashCaptureDark;
        length = WCLiquidGlassIconCrashCaptureDark_len;
    } else if ([fileName isEqualToString:@"crash-logs-dark.png"]) {
        bytes = WCLiquidGlassIconCrashLogsDark;
        length = WCLiquidGlassIconCrashLogsDark_len;
    } else if ([fileName isEqualToString:@"restore-dark.png"]) {
        bytes = WCLiquidGlassIconRestoreDark;
        length = WCLiquidGlassIconRestoreDark_len;
    }
    return bytes ? [NSData dataWithBytesNoCopy:(void *)bytes length:length freeWhenDone:NO] : nil;
}

static UIImage *WCLiquidGlassPluginIconAsset(NSString *fileName) {
    static NSCache<NSString *, UIImage *> *iconCache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        iconCache = [[NSCache alloc] init];
        iconCache.countLimit = 16;
    });

    UIImage *cachedImage = [iconCache objectForKey:fileName];
    if (cachedImage) {
        return cachedImage;
    }

    NSData *embeddedData = WCLiquidGlassEmbeddedIconData(fileName);
    UIImage *embeddedImage = embeddedData
        ? [UIImage imageWithData:embeddedData scale:UIScreen.mainScreen.scale]
        : nil;
    if (embeddedImage) {
        embeddedImage = [embeddedImage imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        [iconCache setObject:embeddedImage forKey:fileName];
        return embeddedImage;
    }

    NSArray<NSString *> *paths = @[
        [@"/var/jb/Library/Application Support/WCLiquidGlass/Icons" stringByAppendingPathComponent:fileName],
        [@"/Library/Application Support/WCLiquidGlass/Icons" stringByAppendingPathComponent:fileName]
    ];
    for (NSString *path in paths) {
        UIImage *image = [UIImage imageWithContentsOfFile:path];
        if (image) {
            image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
            [iconCache setObject:image forKey:fileName];
            return image;
        }
    }
    return nil;
}

UIImage *WCLiquidGlassSettingsIconImage(WCLiquidGlassSettingsIconKind kind, CGFloat size) {
    (void)size;
    NSString *fileName = WCLiquidGlassSettingsIconFileName(kind);
    if (UITraitCollection.currentTraitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
        NSString *darkFileName = [fileName stringByReplacingOccurrencesOfString:@".png" withString:@"-dark.png"];
        if (WCLiquidGlassEmbeddedIconData(darkFileName)) {
            fileName = darkFileName;
        }
    }
    return WCLiquidGlassPluginIconAsset(fileName);
}

static UIImage *WCLiquidGlassImageWithMaximumSide(UIImage *image, CGFloat maximumSide) {
    if (!image.CGImage || maximumSide <= 0.0) {
        return image;
    }
    CGFloat pixelSide = MAX(CGImageGetWidth(image.CGImage), CGImageGetHeight(image.CGImage));
    UIImage *sizedImage = [[UIImage alloc] initWithCGImage:image.CGImage
                                                      scale:pixelSide / maximumSide
                                                orientation:image.imageOrientation];
    return [sizedImage imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

UIImage *WCLiquidGlassBrandIconImage(CGFloat size, BOOL includesBackground) {
    (void)includesBackground;
    BOOL dark = UITraitCollection.currentTraitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    return WCLiquidGlassImageWithMaximumSide(WCLiquidGlassPluginIconAsset(dark ? @"brand-dark.png" : @"brand.png"), size);
}

static void WCLiquidGlassFillActionBrandPath(UIBezierPath *path, UIColor *color) {
    [color setFill];
    [path fill];
}

static UIImage *WCLiquidGlassActionBrandImage(CGFloat side) {
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.opaque = NO;
    format.scale = 0.0;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)
                                                                                format:format];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *rendererContext) {
        CGContextRef context = rendererContext.CGContext;
        CGContextSetAllowsAntialiasing(context, YES);
        CGContextSetShouldAntialias(context, YES);
        CGContextSetFlatness(context, 0.1);
        CGFloat scale = side / 1024.0;
        CGContextScaleCTM(context, scale, scale);
        CGContextTranslateCTM(context, 182.0, 191.0);
        CGContextScaleCTM(context, 1.378, 1.378);
        BOOL dark = UITraitCollection.currentTraitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
        UIColor *black = dark ? [UIColor colorWithRed:0.949 green:0.949 blue:0.969 alpha:1.0]
                             : [UIColor colorWithWhite:0.02 alpha:1.0];
        UIColor *gray = dark ? [UIColor colorWithRed:0.557 green:0.557 blue:0.576 alpha:1.0]
                            : [UIColor colorWithRed:0.725 green:0.718 blue:0.698 alpha:1.0];

        UIBezierPath *underside = [UIBezierPath bezierPath];
        [underside moveToPoint:CGPointMake(232.0, 298.0)];
        [underside addCurveToPoint:CGPointMake(314.0, 295.0) controlPoint1:CGPointMake(262.0, 307.0) controlPoint2:CGPointMake(288.0, 303.0)];
        [underside addCurveToPoint:CGPointMake(389.0, 303.0) controlPoint1:CGPointMake(340.0, 287.0) controlPoint2:CGPointMake(366.0, 293.0)];
        [underside addCurveToPoint:CGPointMake(447.0, 297.0) controlPoint1:CGPointMake(410.0, 312.0) controlPoint2:CGPointMake(431.0, 309.0)];
        [underside addCurveToPoint:CGPointMake(407.0, 319.0) controlPoint1:CGPointMake(443.0, 311.0) controlPoint2:CGPointMake(429.0, 318.0)];
        [underside addCurveToPoint:CGPointMake(344.0, 307.0) controlPoint1:CGPointMake(382.0, 321.0) controlPoint2:CGPointMake(363.0, 312.0)];
        [underside addCurveToPoint:CGPointMake(279.0, 313.0) controlPoint1:CGPointMake(320.0, 300.0) controlPoint2:CGPointMake(299.0, 307.0)];
        [underside addCurveToPoint:CGPointMake(222.0, 309.0) controlPoint1:CGPointMake(258.0, 319.0) controlPoint2:CGPointMake(238.0, 315.0)];
        [underside closePath];
        WCLiquidGlassFillActionBrandPath(underside, gray);

        UIBezierPath *leftTentacle = [UIBezierPath bezierPath];
        [leftTentacle moveToPoint:CGPointMake(123.0, 330.0)];
        [leftTentacle addCurveToPoint:CGPointMake(174.0, 338.0) controlPoint1:CGPointMake(140.0, 313.0) controlPoint2:CGPointMake(164.0, 317.0)];
        [leftTentacle addCurveToPoint:CGPointMake(175.0, 424.0) controlPoint1:CGPointMake(184.0, 359.0) controlPoint2:CGPointMake(182.0, 398.0)];
        [leftTentacle addCurveToPoint:CGPointMake(124.0, 448.0) controlPoint1:CGPointMake(169.0, 447.0) controlPoint2:CGPointMake(146.0, 454.0)];
        [leftTentacle addCurveToPoint:CGPointMake(98.0, 398.0) controlPoint1:CGPointMake(103.0, 442.0) controlPoint2:CGPointMake(96.0, 423.0)];
        [leftTentacle addCurveToPoint:CGPointMake(123.0, 330.0) controlPoint1:CGPointMake(100.0, 371.0) controlPoint2:CGPointMake(104.0, 349.0)];
        [leftTentacle closePath];
        WCLiquidGlassFillActionBrandPath(leftTentacle, black);

        UIBezierPath *middleTentacle = [UIBezierPath bezierPath];
        [middleTentacle moveToPoint:CGPointMake(224.0, 327.0)];
        [middleTentacle addCurveToPoint:CGPointMake(275.0, 337.0) controlPoint1:CGPointMake(241.0, 311.0) controlPoint2:CGPointMake(264.0, 316.0)];
        [middleTentacle addCurveToPoint:CGPointMake(277.0, 425.0) controlPoint1:CGPointMake(285.0, 358.0) controlPoint2:CGPointMake(283.0, 399.0)];
        [middleTentacle addCurveToPoint:CGPointMake(226.0, 448.0) controlPoint1:CGPointMake(271.0, 448.0) controlPoint2:CGPointMake(248.0, 454.0)];
        [middleTentacle addCurveToPoint:CGPointMake(201.0, 398.0) controlPoint1:CGPointMake(205.0, 442.0) controlPoint2:CGPointMake(199.0, 422.0)];
        [middleTentacle addCurveToPoint:CGPointMake(224.0, 327.0) controlPoint1:CGPointMake(202.0, 370.0) controlPoint2:CGPointMake(206.0, 347.0)];
        [middleTentacle closePath];
        WCLiquidGlassFillActionBrandPath(middleTentacle, black);

        UIBezierPath *rightTentacle = [UIBezierPath bezierPath];
        [rightTentacle moveToPoint:CGPointMake(325.0, 329.0)];
        [rightTentacle addCurveToPoint:CGPointMake(376.0, 338.0) controlPoint1:CGPointMake(342.0, 313.0) controlPoint2:CGPointMake(365.0, 317.0)];
        [rightTentacle addCurveToPoint:CGPointMake(379.0, 424.0) controlPoint1:CGPointMake(386.0, 359.0) controlPoint2:CGPointMake(385.0, 398.0)];
        [rightTentacle addCurveToPoint:CGPointMake(328.0, 448.0) controlPoint1:CGPointMake(373.0, 447.0) controlPoint2:CGPointMake(350.0, 454.0)];
        [rightTentacle addCurveToPoint:CGPointMake(302.0, 398.0) controlPoint1:CGPointMake(307.0, 442.0) controlPoint2:CGPointMake(301.0, 423.0)];
        [rightTentacle addCurveToPoint:CGPointMake(325.0, 329.0) controlPoint1:CGPointMake(304.0, 371.0) controlPoint2:CGPointMake(307.0, 349.0)];
        [rightTentacle closePath];
        WCLiquidGlassFillActionBrandPath(rightTentacle, gray);

        UIBezierPath *dome = [UIBezierPath bezierPath];
        [dome moveToPoint:CGPointMake(16.0, 255.0)];
        [dome addCurveToPoint:CGPointMake(80.0, 81.0) controlPoint1:CGPointMake(10.0, 196.0) controlPoint2:CGPointMake(34.0, 133.0)];
        [dome addCurveToPoint:CGPointMake(238.0, 17.0) controlPoint1:CGPointMake(120.0, 37.0) controlPoint2:CGPointMake(176.0, 18.0)];
        [dome addCurveToPoint:CGPointMake(405.0, 79.0) controlPoint1:CGPointMake(302.0, 16.0) controlPoint2:CGPointMake(361.0, 37.0)];
        [dome addCurveToPoint:CGPointMake(468.0, 233.0) controlPoint1:CGPointMake(446.0, 118.0) controlPoint2:CGPointMake(468.0, 175.0)];
        [dome addCurveToPoint:CGPointMake(429.0, 301.0) controlPoint1:CGPointMake(468.0, 269.0) controlPoint2:CGPointMake(455.0, 290.0)];
        [dome addCurveToPoint:CGPointMake(355.0, 288.0) controlPoint1:CGPointMake(402.0, 312.0) controlPoint2:CGPointMake(379.0, 294.0)];
        [dome addCurveToPoint:CGPointMake(272.0, 304.0) controlPoint1:CGPointMake(326.0, 281.0) controlPoint2:CGPointMake(299.0, 294.0)];
        [dome addCurveToPoint:CGPointMake(195.0, 299.0) controlPoint1:CGPointMake(245.0, 314.0) controlPoint2:CGPointMake(220.0, 311.0)];
        [dome addCurveToPoint:CGPointMake(128.0, 294.0) controlPoint1:CGPointMake(170.0, 287.0) controlPoint2:CGPointMake(150.0, 286.0)];
        [dome addCurveToPoint:CGPointMake(55.0, 297.0) controlPoint1:CGPointMake(101.0, 305.0) controlPoint2:CGPointMake(78.0, 306.0)];
        [dome addCurveToPoint:CGPointMake(16.0, 255.0) controlPoint1:CGPointMake(31.0, 288.0) controlPoint2:CGPointMake(18.0, 272.0)];
        [dome closePath];
        WCLiquidGlassFillActionBrandPath(dome, black);

        UIBezierPath *window = [UIBezierPath bezierPath];
        [window moveToPoint:CGPointMake(347.0, 178.0)];
        [window addCurveToPoint:CGPointMake(420.0, 198.0) controlPoint1:CGPointMake(374.0, 170.0) controlPoint2:CGPointMake(404.0, 178.0)];
        [window addCurveToPoint:CGPointMake(412.0, 251.0) controlPoint1:CGPointMake(434.0, 216.0) controlPoint2:CGPointMake(430.0, 239.0)];
        [window addCurveToPoint:CGPointMake(342.0, 239.0) controlPoint1:CGPointMake(391.0, 264.0) controlPoint2:CGPointMake(359.0, 258.0)];
        [window addCurveToPoint:CGPointMake(347.0, 178.0) controlPoint1:CGPointMake(325.0, 219.0) controlPoint2:CGPointMake(328.0, 187.0)];
        [window closePath];
        WCLiquidGlassFillActionBrandPath(window, gray);

        UIBezierPath *windowCutout = [UIBezierPath bezierPath];
        [windowCutout moveToPoint:CGPointMake(418.0, 210.0)];
        [windowCutout addCurveToPoint:CGPointMake(432.0, 228.0) controlPoint1:CGPointMake(427.0, 211.0) controlPoint2:CGPointMake(432.0, 218.0)];
        [windowCutout addCurveToPoint:CGPointMake(418.0, 247.0) controlPoint1:CGPointMake(432.0, 238.0) controlPoint2:CGPointMake(427.0, 245.0)];
        [windowCutout addCurveToPoint:CGPointMake(409.0, 229.0) controlPoint1:CGPointMake(412.0, 242.0) controlPoint2:CGPointMake(409.0, 236.0)];
        [windowCutout addCurveToPoint:CGPointMake(418.0, 210.0) controlPoint1:CGPointMake(409.0, 221.0) controlPoint2:CGPointMake(412.0, 215.0)];
        [windowCutout closePath];
        WCLiquidGlassFillActionBrandPath(windowCutout, black);
    }];
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

static UIImage *WCLiquidGlassWCGlassSettingsImage(CGFloat buttonDiameter) {
    Class settingsClass = NSClassFromString(@"WCLGSettingsViewController");
    NSBundle *bundle = settingsClass ? [NSBundle bundleForClass:settingsClass] : nil;
    if (!bundle) {
        return nil;
    }

    UIImage *image = [UIImage imageNamed:@"WeChatLiquidGlassLogo"
                                 inBundle:bundle
            compatibleWithTraitCollection:UITraitCollection.currentTraitCollection];
    if (!image) {
        NSString *path = [bundle pathForResource:@"WeChatLiquidGlassLogo" ofType:@"png"];
        image = path ? [UIImage imageWithContentsOfFile:path] : nil;
    }
    return image
        ? WCLiquidGlassImageWithMaximumSide(image, floor(buttonDiameter * 0.42))
        : nil;
}

UIImage *WCLiquidGlassImageForAction(NSString *actionIdentifier, CGFloat buttonDiameter) {
    static NSCache<NSString *, UIImage *> *imageCache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        imageCache = [[NSCache alloc] init];
        imageCache.countLimit = 96;
    });
    NSInteger interfaceStyle = UITraitCollection.currentTraitCollection.userInterfaceStyle;
    NSString *cacheKey = [NSString stringWithFormat:@"%@|%.1f|%ld",
                                                    actionIdentifier,
                                                    buttonDiameter,
                                                    (long)interfaceStyle];
    UIImage *cachedImage = [imageCache objectForKey:cacheKey];
    if (cachedImage) {
        return cachedImage;
    }

    UIImage *image = [actionIdentifier isEqualToString:WCLiquidGlassActionSettings]
        ? WCLiquidGlassActionBrandImage(floor(buttonDiameter * 0.48))
        : nil;
    if (!image && [actionIdentifier isEqualToString:WCLiquidGlassActionWCGlassSettings]) {
        image = WCLiquidGlassWCGlassSettingsImage(buttonDiameter);
    }
    if (!image && [actionIdentifier isEqualToString:WCLiquidGlassActionDoutuAssistant]) {
        image = WCLiquidGlassDoutuAssistantImage();
    }
    if (!image) {
        image = WCLiquidGlassWeChatAssetImage(actionIdentifier);
    }
    if (!image && [actionIdentifier hasPrefix:@"tab."]) {
        NSInteger index = [[actionIdentifier substringFromIndex:4] integerValue];
        image = WCLiquidGlassNativeTabImage(WCLiquidGlassCurrentTabController(), index);
        image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    if (!image) {
        UIImageSymbolConfiguration *configuration =
            [UIImageSymbolConfiguration configurationWithPointSize:floor(buttonDiameter * 0.34)
                                                            weight:UIImageSymbolWeightSemibold];
        image = [[UIImage systemImageNamed:WCLiquidGlassActionSymbol(actionIdentifier)]
                 imageByApplyingSymbolConfiguration:configuration];
        if (!image) {
            image = [[UIImage systemImageNamed:@"questionmark.circle.fill"]
                     imageByApplyingSymbolConfiguration:configuration];
        }
        image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    if ([actionIdentifier isEqualToString:WCLiquidGlassActionPlugins]) {
        image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    if (image) {
        [imageCache setObject:image forKey:cacheKey];
    }
    return image;
}

static UIImage *WCLiquidGlassCloseImage(void) {
    UIImage *image = WCLiquidGlassImageNamedFromCandidates(@[@"icons_outlined_close",
                                                              @"icons_filled_close",
                                                              @"close_outlined",
                                                              @"close_filled",
                                                              @"icon_close"]);
    if (image) {
        return image;
    }

    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.opaque = NO;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(32.0, 32.0)
                                                                                format:format];
    image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        UIBezierPath *path = [UIBezierPath bezierPath];
        path.lineWidth = 3.5;
        path.lineCapStyle = kCGLineCapRound;
        [path moveToPoint:CGPointMake(9.0, 9.0)];
        [path addLineToPoint:CGPointMake(23.0, 23.0)];
        [path moveToPoint:CGPointMake(23.0, 9.0)];
        [path addLineToPoint:CGPointMake(9.0, 23.0)];
        [UIColor.blackColor setStroke];
        [path stroke];
    }];
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

static UIViewController *WCLiquidGlassVisibleController(void) {
    return WCLiquidGlassVisibleControllerFrom(WCLiquidGlassApplicationWindow().rootViewController);
}

static UINavigationController *WCLiquidGlassNavigationController(void) {
    UIViewController *visibleController = WCLiquidGlassVisibleController();
    if ([visibleController isKindOfClass:UINavigationController.class]) {
        return (UINavigationController *)visibleController;
    }
    return visibleController.navigationController;
}

static void WCLiquidGlassShowActionError(NSString *message) {
    UIViewController *controller = WCLiquidGlassVisibleController();
    if (!controller) {
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"WCLiquidGlass"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [controller presentViewController:alert animated:YES completion:nil];
}

static BOOL WCLiquidGlassInvokeSelectorOnTarget(id target, NSArray<NSString *> *selectorNames) {
    for (NSString *selectorName in selectorNames) {
        SEL selector = NSSelectorFromString(selectorName);
        if (!target || ![target respondsToSelector:selector]) {
            continue;
        }
        NSMethodSignature *signature = [target methodSignatureForSelector:selector];
        @try {
            if (signature.numberOfArguments == 2) {
                ((void (*)(id, SEL))objc_msgSend)(target, selector);
                return YES;
            }
            if (signature.numberOfArguments == 3) {
                ((void (*)(id, SEL, id))objc_msgSend)(target, selector, nil);
                return YES;
            }
        } @catch (__unused NSException *exception) {
        }
    }
    return NO;
}

static BOOL WCLiquidGlassTargetSupportsSelectors(id target, NSArray<NSString *> *selectorNames) {
    for (NSString *selectorName in selectorNames) {
        if ([target respondsToSelector:NSSelectorFromString(selectorName)]) {
            return YES;
        }
    }
    return NO;
}

static id WCLiquidGlassTargetInView(UIView *view, NSArray<NSString *> *selectorNames) {
    if (WCLiquidGlassTargetSupportsSelectors(view, selectorNames)) {
        return view;
    }

    for (UIView *subview in view.subviews) {
        id target = WCLiquidGlassTargetInView(subview, selectorNames);
        if (target) {
            return target;
        }
    }
    return nil;
}

static id WCLiquidGlassActionTarget(NSArray<NSString *> *selectorNames) {
    if (selectorNames.count == 0) {
        return nil;
    }
    UIViewController *visibleController = WCLiquidGlassVisibleController();
    id tabController = WCLiquidGlassCurrentTabController();
    NSMutableArray *targets = [NSMutableArray arrayWithObjects:visibleController ?: NSNull.null,
                                                           visibleController.navigationController ?: NSNull.null,
                                                           tabController ?: NSNull.null,
                                                           nil];
    for (NSString *propertyName in @[@"hostViewController", @"parentViewController", @"toolView",
                                      @"messageToolBar", @"m_toolView", @"inputToolView",
                                      @"m_inputController"]) {
        id target = WCLiquidGlassObjectFromSelector(visibleController, propertyName);
        if (target) {
            [targets addObject:target];
        }
    }
    for (id target in targets) {
        if (target != NSNull.null && WCLiquidGlassTargetSupportsSelectors(target, selectorNames)) {
            return target;
        }
    }
    return visibleController.viewIfLoaded
        ? WCLiquidGlassTargetInView(visibleController.view, selectorNames)
        : nil;
}

static NSArray<id> *WCLiquidGlassActionTargetCandidates(UIViewController *visibleController,
                                                          id tabController) {
    NSMutableArray *targets = [NSMutableArray arrayWithObjects:visibleController ?: NSNull.null,
                                                           visibleController.navigationController ?: NSNull.null,
                                                           tabController ?: NSNull.null,
                                                           nil];
    for (NSString *propertyName in @[@"hostViewController", @"parentViewController", @"toolView",
                                      @"messageToolBar", @"m_toolView", @"inputToolView",
                                      @"m_inputController"]) {
        id target = WCLiquidGlassObjectFromSelector(visibleController, propertyName);
        if (target) {
            [targets addObject:target];
        }
    }
    return targets.copy;
}

static void WCLiquidGlassFindActionTargetsInView(UIView *view,
                                                  NSDictionary<NSString *, NSArray<NSString *> *> *selectorNames,
                                                  NSMutableDictionary<NSString *, id> *targets) {
    if (!view || targets.count == selectorNames.count) {
        return;
    }
    for (NSString *actionIdentifier in selectorNames) {
        if (!targets[actionIdentifier] &&
            WCLiquidGlassTargetSupportsSelectors(view, selectorNames[actionIdentifier])) {
            targets[actionIdentifier] = view;
        }
    }
    if (targets.count == selectorNames.count) {
        return;
    }
    for (UIView *subview in view.subviews) {
        WCLiquidGlassFindActionTargetsInView(subview, selectorNames, targets);
        if (targets.count == selectorNames.count) {
            return;
        }
    }
}

static NSDictionary<NSString *, id> *WCLiquidGlassActionTargetsForSelectors(
    UIViewController *visibleController,
    id tabController,
    NSDictionary<NSString *, NSArray<NSString *> *> *selectorNames) {
    if (selectorNames.count == 0) {
        return @{};
    }
    NSMutableDictionary<NSString *, id> *targets = [NSMutableDictionary dictionary];
    for (id candidate in WCLiquidGlassActionTargetCandidates(visibleController, tabController)) {
        if (candidate == NSNull.null) {
            continue;
        }
        for (NSString *actionIdentifier in selectorNames) {
            if (!targets[actionIdentifier] &&
                WCLiquidGlassTargetSupportsSelectors(candidate, selectorNames[actionIdentifier])) {
                targets[actionIdentifier] = candidate;
            }
        }
        if (targets.count == selectorNames.count) {
            return targets.copy;
        }
    }
    WCLiquidGlassFindActionTargetsInView(visibleController.viewIfLoaded, selectorNames, targets);
    return targets.copy;
}

static BOOL WCLiquidGlassInvokeActionSelectors(NSArray<NSString *> *selectorNames) {
    id target = WCLiquidGlassActionTarget(selectorNames);
    return target ? WCLiquidGlassInvokeSelectorOnTarget(target, selectorNames) : NO;
}

static NSInteger WCLiquidGlassVoiceTranscriptionControlScore(UIControl *control) {
    NSMutableArray<NSString *> *signals = [NSMutableArray array];
    for (NSString *value in @[NSStringFromClass(control.class) ?: @"",
                              control.accessibilityLabel ?: @"",
                              control.accessibilityIdentifier ?: @"",
                              control.accessibilityValue ?: @""]) {
        if (value.length > 0) {
            [signals addObject:value.lowercaseString];
        }
    }
    for (id target in control.allTargets) {
        for (NSNumber *event in @[@(UIControlEventTouchUpInside),
                                   @(UIControlEventPrimaryActionTriggered),
                                   @(UIControlEventValueChanged)]) {
            NSArray<NSString *> *actions = [control actionsForTarget:target
                                                     forControlEvent:event.unsignedIntegerValue];
            for (NSString *action in actions) {
                if (action.length > 0) {
                    [signals addObject:action.lowercaseString];
                }
            }
        }
    }

    NSString *combined = [signals componentsJoinedByString:@" "];
    if ([combined containsString:@"videovoip"] ||
        [combined containsString:@"videocall"] ||
        [combined containsString:@"openvoicecall"] ||
        [combined containsString:@"视频通话"] ||
        [combined containsString:@"语音通话"] ||
        [combined containsString:@"按住说话"]) {
        return NSIntegerMin;
    }

    NSInteger score = 0;
    if ([combined containsString:@"onvoiceinputbuttonclicked:"]) {
        score += 500;
    }
    if ([combined containsString:@"transcri"] || [combined containsString:@"dictation"]) {
        score += 320;
    }
    if ([combined containsString:@"voiceinput"]) {
        score += 260;
    }
    if ([combined containsString:@"语音转述"] ||
        [combined containsString:@"转文字"] ||
        [combined containsString:@"转文本"]) {
        score += 500;
    }
    if ([combined containsString:@"语音输入"]) {
        score += 260;
    }
    return score;
}

static void WCLiquidGlassFindVoiceTranscriptionControlInView(UIView *view,
                                                              UIControl **bestControl,
                                                              NSInteger *bestScore) {
    if ([view isKindOfClass:UIControl.class]) {
        NSInteger score = WCLiquidGlassVoiceTranscriptionControlScore((UIControl *)view);
        if (score > *bestScore) {
            *bestControl = (UIControl *)view;
            *bestScore = score;
        }
    }
    for (UIView *subview in view.subviews) {
        WCLiquidGlassFindVoiceTranscriptionControlInView(subview, bestControl, bestScore);
    }
}

static UIControl *WCLiquidGlassVoiceTranscriptionControl(void) {
    UIViewController *visibleController = WCLiquidGlassVisibleController();
    if (!visibleController.viewIfLoaded) {
        return nil;
    }
    UIControl *control = nil;
    NSInteger score = NSIntegerMin;
    WCLiquidGlassFindVoiceTranscriptionControlInView(visibleController.view, &control, &score);
    for (NSString *propertyName in @[@"toolView", @"messageToolBar", @"m_toolView",
                                      @"inputToolView", @"m_inputController"]) {
        id candidate = WCLiquidGlassObjectFromSelector(visibleController, propertyName);
        UIView *candidateView = [candidate isKindOfClass:UIView.class]
            ? candidate
            : ([candidate isKindOfClass:UIViewController.class]
                ? ((UIViewController *)candidate).viewIfLoaded
                : nil);
        if (candidateView) {
            WCLiquidGlassFindVoiceTranscriptionControlInView(candidateView, &control, &score);
        }
    }
    return score >= 260 && control.isEnabled ? control : nil;
}

static BOOL WCLiquidGlassTriggerVoiceTranscription(void) {
    UIControl *control = WCLiquidGlassVoiceTranscriptionControl();
    if (!control) {
        return NO;
    }
    [control sendActionsForControlEvents:UIControlEventTouchUpInside];
    return YES;
}

static BOOL WCLiquidGlassViewBelongsToChatInput(UIView *view) {
    for (UIView *ancestor = view.superview; ancestor; ancestor = ancestor.superview) {
        NSString *className = NSStringFromClass(ancestor.class);
        if ([className containsString:@"MMGrowTextView"] ||
            [className containsString:@"MMInputToolView"] ||
            [className containsString:@"MessageInputTool"] ||
            [className containsString:@"ChatInputTool"]) {
            return YES;
        }
    }
    return NO;
}

static void WCLiquidGlassFindChatInputViewInView(UIView *view,
                                                  UIView **bestView,
                                                  NSInteger *bestScore) {
    if (([view isKindOfClass:UITextView.class] || [view isKindOfClass:UITextField.class]) &&
        WCLiquidGlassViewBelongsToChatInput(view)) {
        NSInteger score = view.isFirstResponder ? 1000 : 500;
        if ([NSStringFromClass(view.class) containsString:@"MMTextView"]) {
            score += 200;
        }
        if (!view.hidden && view.alpha > 0.01 && score > *bestScore) {
            *bestView = view;
            *bestScore = score;
        }
    }
    for (UIView *subview in view.subviews) {
        WCLiquidGlassFindChatInputViewInView(subview, bestView, bestScore);
    }
}

UIView *WCLiquidGlassCurrentChatInputView(void) {
    UIViewController *visibleController = WCLiquidGlassVisibleController();
    if (!visibleController.viewIfLoaded) {
        return nil;
    }
    UIView *inputView = nil;
    NSInteger score = NSIntegerMin;
    WCLiquidGlassFindChatInputViewInView(visibleController.view, &inputView, &score);
    for (NSString *propertyName in @[@"toolView", @"messageToolBar", @"m_toolView",
                                      @"inputToolView", @"m_inputController"]) {
        id candidate = WCLiquidGlassObjectFromSelector(visibleController, propertyName);
        UIView *candidateView = [candidate isKindOfClass:UIView.class]
            ? candidate
            : ([candidate isKindOfClass:UIViewController.class]
                ? ((UIViewController *)candidate).viewIfLoaded
                : nil);
        if (candidateView) {
            WCLiquidGlassFindChatInputViewInView(candidateView, &inputView, &score);
        }
    }
    return inputView;
}

BOOL WCLiquidGlassCurrentChatInputHasText(void) {
    UIView *inputView = WCLiquidGlassCurrentChatInputView();
    if ([inputView isKindOfClass:UITextView.class]) {
        return ((UITextView *)inputView).text.length > 0;
    }
    if ([inputView isKindOfClass:UITextField.class]) {
        return ((UITextField *)inputView).text.length > 0;
    }
    return NO;
}

static NSArray<NSString *> *WCLiquidGlassDoutuButtonPropertyNames(void) {
    return @[@"doutuButton", @"DoutuButton", @"douTuButton", @"doutu", @"DouTu"];
}

static UIControl *WCLiquidGlassControlFromObjectSelectors(id target,
                                                          NSArray<NSString *> *selectorNames) {
    for (NSString *selectorName in selectorNames) {
        SEL selector = NSSelectorFromString(selectorName);
        if (!target || ![target respondsToSelector:selector]) {
            continue;
        }
        NSMethodSignature *signature = [target methodSignatureForSelector:selector];
        const char *returnType = signature.methodReturnType;
        if (!returnType || returnType[0] != '@' || signature.numberOfArguments != 2) {
            continue;
        }
        @try {
            id candidate = ((id (*)(id, SEL))objc_msgSend)(target, selector);
            if ([candidate isKindOfClass:UIControl.class]) {
                return candidate;
            }
        } @catch (__unused NSException *exception) {
        }
    }
    return nil;
}

static BOOL WCLiquidGlassDoutuAssistantEnabled(void) {
    Class configClass = NSClassFromString(@"DouTuConfig");
    SEL sharedSelector = NSSelectorFromString(@"sharedConfig");
    SEL enabledSelector = NSSelectorFromString(@"DTEnabled");
    if (!configClass || ![configClass respondsToSelector:sharedSelector]) {
        return NO;
    }
    @try {
        id config = ((id (*)(id, SEL))objc_msgSend)(configClass, sharedSelector);
        if ([config respondsToSelector:enabledSelector]) {
            return ((BOOL (*)(id, SEL))objc_msgSend)(config, enabledSelector);
        }
    } @catch (__unused NSException *exception) {
    }
    return NO;
}

static BOOL WCLiquidGlassTriggerDoutuAssistant(void) {
    if (!WCLiquidGlassDoutuAssistantEnabled()) {
        return NO;
    }
    return WCLiquidGlassInvokeActionSelectors(@[@"doutuAction"]);
}

static BOOL WCLiquidGlassDoutuAssistantConfigured(void) {
    if (!WCLiquidGlassPreferences.enabled) {
        return NO;
    }
    for (NSDictionary<NSString *, id> *item in WCLiquidGlassPreferences.buttonItems) {
        if ([item[@"action"] isEqualToString:WCLiquidGlassActionDoutuAssistant]) {
            return YES;
        }
    }
    return NO;
}

void WCLiquidGlassRefreshDoutuConfiguration(void) {
    WCLiquidGlassDoutuConfiguredCached = WCLiquidGlassDoutuAssistantConfigured();
}

static char WCLiquidGlassDoutuOriginalHiddenKey;

void WCLiquidGlassUpdateDoutuButtonVisibility(id inputToolView) {
    UIControl *button = objc_getAssociatedObject(inputToolView, &WCLiquidGlassDoutuCachedButtonKey);
    if (button && ![button isDescendantOfView:inputToolView]) {
        button = nil;
        objc_setAssociatedObject(inputToolView,
                                 &WCLiquidGlassDoutuCachedButtonKey,
                                 nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(inputToolView,
                                 &WCLiquidGlassDoutuLastVisibilityKey,
                                 nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!button && !WCLiquidGlassDoutuConfiguredCached) {
        return;
    }
    if (!button) {
        button = WCLiquidGlassControlFromObjectSelectors(inputToolView,
                                                          WCLiquidGlassDoutuButtonPropertyNames());
        if (button) {
            objc_setAssociatedObject(inputToolView,
                                     &WCLiquidGlassDoutuCachedButtonKey,
                                     button,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    if (!button) {
        return;
    }
    NSNumber *originalHidden = objc_getAssociatedObject(button,
                                                         &WCLiquidGlassDoutuOriginalHiddenKey);
    BOOL shouldHide = WCLiquidGlassDoutuConfiguredCached && WCLiquidGlassDoutuAssistantEnabled();
    NSNumber *lastShouldHide = objc_getAssociatedObject(inputToolView,
                                                         &WCLiquidGlassDoutuLastVisibilityKey);
    if (lastShouldHide && lastShouldHide.boolValue == shouldHide &&
        (!shouldHide || button.hidden)) {
        return;
    }
    if (shouldHide) {
        if (!originalHidden) {
            objc_setAssociatedObject(button,
                                     &WCLiquidGlassDoutuOriginalHiddenKey,
                                     @(button.hidden),
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (!button.hidden) {
            button.hidden = YES;
        }
    } else if (originalHidden) {
        button.hidden = originalHidden.boolValue;
        objc_setAssociatedObject(button,
                                 &WCLiquidGlassDoutuOriginalHiddenKey,
                                 nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    objc_setAssociatedObject(inputToolView,
                             &WCLiquidGlassDoutuLastVisibilityKey,
                             @(shouldHide),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static NSArray<NSString *> *WCLiquidGlassSelectorsForAction(NSString *actionIdentifier) {
    static NSDictionary<NSString *, NSArray<NSString *> *> *selectors;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        selectors = @{
            WCLiquidGlassActionChannels: @[@"openFinderTimeline"],
            WCLiquidGlassActionAlbum: @[@"onMediaBrowserClicked:"],
            WCLiquidGlassActionCamera: @[@"onCameraControllerClicked:", @"OpenCameraController"],
            WCLiquidGlassActionVideoCall: @[@"onVideoVoipButtonClicked:"],
            WCLiquidGlassActionRedPacket: @[@"onRedEnvelopesClicked:"],
            WCLiquidGlassActionFiles: @[@"onFileBrowserClicked:", @"onFileBrowser"],
            WCLiquidGlassActionTransfer: @[@"onTransferButtonClicked:"],
            WCLiquidGlassActionLocation: @[@"onLocationButtonClicked:"],
            WCLiquidGlassActionFavorites: @[@"onMyFavoritesButtonClicked:"],
            WCLiquidGlassActionTranslate: @[@"onClickTranslateToolOpenMenu"],
            WCLiquidGlassActionScan: @[@"onScanViewController", @"jumpToCameraScanInTopViewController:"],
            WCLiquidGlassActionPayment: @[@"jumpToOfflinePay"],
            WCLiquidGlassActionContactCard: @[@"onShareCardButtonClicked:"],
            WCLiquidGlassActionSearchRecords: @[@"pushSearchControllerWithCompletion:", @"onSearchItem"],
            WCLiquidGlassActionNewLine: @[@"inputNewLine"],
            WCLiquidGlassActionMention: @[@"atUser"],
            WCLiquidGlassActionFullInput: @[@"jumpToFullScreenVC"]
        };
    });
    return selectors[actionIdentifier] ?: @[];
}

static BOOL WCLiquidGlassOpenControllerNamed(NSArray<NSString *> *classNames) {
    UINavigationController *navigationController = WCLiquidGlassNavigationController();
    if (!navigationController) {
        return NO;
    }
    for (NSString *className in classNames) {
        Class controllerClass = NSClassFromString(className);
        if (!controllerClass) {
            continue;
        }
        @try {
            UIViewController *controller = [[controllerClass alloc] init];
            if ([controller isKindOfClass:UIViewController.class]) {
                [navigationController pushViewController:controller animated:YES];
                return YES;
            }
        } @catch (__unused NSException *exception) {
        }
    }
    return NO;
}

static BOOL WCLiquidGlassCanSelectTab(id tabController, NSInteger index) {
    NSArray *sources = WCLiquidGlassPrivateTabSources(tabController);
    NSUInteger tabCount = sources.count;
    if ([tabController isKindOfClass:UITabBarController.class]) {
        tabCount = ((UITabBarController *)tabController).viewControllers.count;
    }
    return index >= 0 &&
        index < (NSInteger)tabCount &&
        [tabController respondsToSelector:NSSelectorFromString(@"setSelectedIndex:")];
}

static NSSet<NSString *> *WCLiquidGlassAvailableActionIdentifiers(
    NSArray<NSDictionary<NSString *, id> *> *items) {
    UIViewController *visibleController = WCLiquidGlassVisibleController();
    UINavigationController *navigationController = [visibleController isKindOfClass:UINavigationController.class]
        ? (UINavigationController *)visibleController
        : visibleController.navigationController;
    id tabController = WCLiquidGlassCurrentTabController();
    NSMutableSet<NSString *> *availableActions = [NSMutableSet set];
    NSMutableDictionary<NSString *, NSArray<NSString *> *> *selectorNames = [NSMutableDictionary dictionary];
    BOOL needsDoutuAssistant = NO;
    BOOL hasChannelsAction = NO;
    BOOL hasFilesAction = NO;

    for (NSDictionary<NSString *, id> *item in items) {
        NSString *actionIdentifier = item[@"action"];
        if (![actionIdentifier isKindOfClass:NSString.class]) {
            continue;
        }
        if ([actionIdentifier hasPrefix:@"tab."]) {
            NSInteger index = [[actionIdentifier substringFromIndex:4] integerValue];
            if (WCLiquidGlassCanSelectTab(tabController, index)) {
                [availableActions addObject:actionIdentifier];
            }
        } else if ([actionIdentifier isEqualToString:WCLiquidGlassActionSettings]) {
            if (navigationController) {
                [availableActions addObject:actionIdentifier];
            }
        } else if ([actionIdentifier isEqualToString:WCLiquidGlassActionWCGlassSettings]) {
            if (navigationController && NSClassFromString(@"WCLGSettingsViewController")) {
                [availableActions addObject:actionIdentifier];
            }
        } else if ([actionIdentifier isEqualToString:WCLiquidGlassActionPlugins]) {
            if (navigationController && NSClassFromString(@"WCPluginsViewController")) {
                [availableActions addObject:actionIdentifier];
            }
        } else if ([actionIdentifier isEqualToString:WCLiquidGlassActionMoments]) {
            if (navigationController && NSClassFromString(@"WCTimeLineViewController")) {
                [availableActions addObject:actionIdentifier];
            }
        } else if ([actionIdentifier isEqualToString:WCLiquidGlassActionVoiceInput]) {
            if (WCLiquidGlassVoiceTranscriptionControl()) {
                [availableActions addObject:actionIdentifier];
            }
        } else if ([actionIdentifier isEqualToString:WCLiquidGlassActionDoutuAssistant]) {
            needsDoutuAssistant = YES;
        } else {
            hasChannelsAction |= [actionIdentifier isEqualToString:WCLiquidGlassActionChannels];
            hasFilesAction |= [actionIdentifier isEqualToString:WCLiquidGlassActionFiles];
            NSArray<NSString *> *actionSelectors = WCLiquidGlassSelectorsForAction(actionIdentifier);
            if (actionSelectors.count > 0) {
                selectorNames[actionIdentifier] = actionSelectors;
            }
        }
    }

    if (needsDoutuAssistant && WCLiquidGlassDoutuAssistantEnabled() &&
        WCLiquidGlassCurrentChatInputHasText()) {
        selectorNames[WCLiquidGlassActionDoutuAssistant] = @[@"doutuAction"];
    }

    NSDictionary<NSString *, id> *actionTargets = WCLiquidGlassActionTargetsForSelectors(visibleController,
                                                                                            tabController,
                                                                                            selectorNames);
    for (NSString *actionIdentifier in actionTargets) {
        [availableActions addObject:actionIdentifier];
    }
    if (!actionTargets[WCLiquidGlassActionChannels] &&
        hasChannelsAction &&
        navigationController && NSClassFromString(@"WCFinderTimelineTabViewController")) {
        [availableActions addObject:WCLiquidGlassActionChannels];
    }
    if (!actionTargets[WCLiquidGlassActionFiles] &&
        hasFilesAction &&
        navigationController && NSClassFromString(@"LMFileBrowserViewController")) {
        [availableActions addObject:WCLiquidGlassActionFiles];
    }
    return availableActions.copy;
}

static void WCLiquidGlassPerformAction(NSString *actionIdentifier) {
    id tabController = WCLiquidGlassCurrentTabController();
    if ([actionIdentifier hasPrefix:@"tab."]) {
        NSInteger index = [[actionIdentifier substringFromIndex:4] integerValue];
        SEL setSelectedIndexSelector = NSSelectorFromString(@"setSelectedIndex:");
        if (WCLiquidGlassCanSelectTab(tabController, index)) {
            ((void (*)(id, SEL, NSInteger))objc_msgSend)(tabController,
                                                        setSelectedIndexSelector,
                                                        index);
            return;
        }
        WCLiquidGlassShowActionError(@"当前微信版本没有找到对应的标签页。");
        return;
    }

    if ([actionIdentifier isEqualToString:WCLiquidGlassActionSettings]) {
        UINavigationController *navigationController = WCLiquidGlassNavigationController();
        Class settingsClass = NSClassFromString(@"WCLiquidGlass");
        if (navigationController && settingsClass) {
            UIViewController *settingsController = [[settingsClass alloc] init];
            [navigationController pushViewController:settingsController animated:YES];
            return;
        }
        WCLiquidGlassShowActionError(@"当前页面无法打开 WCLiquidGlass 设置。");
        return;
    }

    if ([actionIdentifier isEqualToString:WCLiquidGlassActionWCGlassSettings]) {
        if (WCLiquidGlassOpenControllerNamed(@[@"WCLGSettingsViewController"])) {
            return;
        }
        WCLiquidGlassShowActionError(@"没有找到 WCGlass 设置页面，请确认 WCGlass 已启用。");
        return;
    }

    if ([actionIdentifier isEqualToString:WCLiquidGlassActionPlugins]) {
        if (WCLiquidGlassOpenControllerNamed(@[@"WCPluginsViewController"])) {
            return;
        }
        WCLiquidGlassShowActionError(@"没有找到 WCPluginsMgr 的插件列表控制器。");
        return;
    }

    if ([actionIdentifier isEqualToString:WCLiquidGlassActionVoiceInput]) {
        if (WCLiquidGlassTriggerVoiceTranscription()) {
            return;
        }
        WCLiquidGlassShowActionError(@"当前页面没有找到微信原生的语音转述按钮。");
        return;
    }

    if ([actionIdentifier isEqualToString:WCLiquidGlassActionDoutuAssistant]) {
        if (WCLiquidGlassTriggerDoutuAssistant()) {
            return;
        }
        WCLiquidGlassShowActionError(@"当前页面无法调用斗图助手，请确认插件已启用并进入聊天页面。");
        return;
    }

    if ([actionIdentifier isEqualToString:WCLiquidGlassActionMoments]) {
        if (WCLiquidGlassOpenControllerNamed(@[@"WCTimeLineViewController"])) {
            return;
        }
    } else if ([actionIdentifier isEqualToString:WCLiquidGlassActionChannels]) {
        if (WCLiquidGlassInvokeActionSelectors(WCLiquidGlassSelectorsForAction(actionIdentifier)) ||
            WCLiquidGlassOpenControllerNamed(@[@"WCFinderTimelineTabViewController"])) {
            return;
        }
    } else if ([actionIdentifier isEqualToString:WCLiquidGlassActionFiles]) {
        if (WCLiquidGlassInvokeActionSelectors(WCLiquidGlassSelectorsForAction(actionIdentifier)) ||
            WCLiquidGlassOpenControllerNamed(@[@"LMFileBrowserViewController"])) {
            return;
        }
    } else {
        NSArray<NSString *> *actionSelectors = WCLiquidGlassSelectorsForAction(actionIdentifier);
        if (actionSelectors.count > 0 && WCLiquidGlassInvokeActionSelectors(actionSelectors)) {
            return;
        }
    }

    WCLiquidGlassShowActionError([NSString stringWithFormat:@"当前页面不支持“%@”，请进入对应页面后重试。",
                                                            WCLiquidGlassActionTitle(actionIdentifier)]);
}

@interface WCLiquidGlassOrbView : UIVisualEffectView

@property(nonatomic, copy) NSString *actionIdentifier;
@property(nonatomic, strong) UIImageView *iconView;
@property(nonatomic, assign) CGFloat diameter;
@property(nonatomic, assign) UIUserInterfaceStyle imageStyle;
@property(nonatomic, assign) BOOL showsCloseIcon;

- (instancetype)initWithDiameter:(CGFloat)diameter;
- (void)prepareForDiameter:(CGFloat)diameter;
- (void)configureWithActionIdentifier:(NSString *)actionIdentifier;
- (void)setCloseAppearance;
- (void)setAnchorAppearance;
- (void)setSelectedAppearance:(BOOL)selected animated:(BOOL)animated;
- (void)setDraggedAppearanceTowardPoint:(CGPoint)point inView:(UIView *)view;
- (void)setToggleActiveAppearance:(BOOL)active;

@end

@implementation WCLiquidGlassOrbView

- (instancetype)initWithDiameter:(CGFloat)diameter {
    self = [super initWithEffect:WCLiquidGlassMakeEffect()];
    if (!self) {
        return nil;
    }

    _diameter = diameter;
    self.bounds = CGRectMake(0, 0, diameter, diameter);
    self.clipsToBounds = YES;
    self.contentView.clipsToBounds = YES;
    self.userInteractionEnabled = YES;
    self.isAccessibilityElement = YES;

    _iconView = [[UIImageView alloc] init];
    _iconView.contentMode = UIViewContentModeScaleAspectFit;
    _iconView.tintColor = UIColor.labelColor;
    _iconView.userInteractionEnabled = NO;
    [self.contentView addSubview:_iconView];

    return self;
}

- (void)prepareForDiameter:(CGFloat)diameter {
    if (fabs(self.diameter - diameter) <= 0.1) {
        return;
    }
    _diameter = diameter;
    if (self.actionIdentifier.length > 0) {
        self.iconView.image = WCLiquidGlassImageForAction(self.actionIdentifier, diameter);
    }
    [self setNeedsLayout];
}

- (void)configureWithActionIdentifier:(NSString *)actionIdentifier {
    self.actionIdentifier = actionIdentifier;
    self.showsCloseIcon = NO;
    self.imageStyle = UITraitCollection.currentTraitCollection.userInterfaceStyle;
    self.accessibilityLabel = WCLiquidGlassActionTitle(actionIdentifier);

    self.iconView.tintColor = UIColor.labelColor;
    self.layer.borderWidth = 0.0;
    self.layer.borderColor = UIColor.clearColor.CGColor;
    self.accessibilityValue = nil;
    self.iconView.image = WCLiquidGlassImageForAction(actionIdentifier, self.diameter);
    [self setNeedsLayout];
}

- (void)setCloseAppearance {
    self.actionIdentifier = nil;
    self.showsCloseIcon = YES;
    self.accessibilityLabel = @"关闭";
    self.iconView.tintColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traitCollection) {
        if (traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
            return [UIColor colorWithWhite:0.82 alpha:1.0];
        }
        return [UIColor colorWithRed:0.63 green:0.72 blue:0.59 alpha:1.0];
    }];
    self.iconView.image = WCLiquidGlassCloseImage();
    [self setNeedsLayout];
}

- (void)setAnchorAppearance {
    self.actionIdentifier = nil;
    self.showsCloseIcon = NO;
    self.accessibilityLabel = @"WCLiquidGlass 菜单";
    self.iconView.tintColor = UIColor.labelColor;
    UIImage *image = WCLiquidGlassImageNamedFromCandidates(@[@"icons_filled_more"]);
    if (!image) {
        UIImageSymbolConfiguration *configuration =
            [UIImageSymbolConfiguration configurationWithPointSize:floor(self.diameter * 0.34)
                                                            weight:UIImageSymbolWeightSemibold];
        image = [[[UIImage systemImageNamed:@"ellipsis.circle.fill"]
                  imageByApplyingSymbolConfiguration:configuration]
                 imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    self.iconView.image = image;
    [self setNeedsLayout];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        self.effect = WCLiquidGlassMakeEffect();
        self.imageStyle = self.traitCollection.userInterfaceStyle;
        if (self.actionIdentifier.length > 0) {
            self.iconView.image = WCLiquidGlassImageForAction(self.actionIdentifier, self.diameter);
        } else if (self.showsCloseIcon) {
            [self setCloseAppearance];
        } else {
            [self setAnchorAppearance];
        }
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.layer.cornerRadius = CGRectGetHeight(self.bounds) * 0.5;
    self.layer.cornerCurve = kCACornerCurveContinuous;

    CGFloat iconSide = floor(self.diameter * 0.54);
    self.iconView.bounds = CGRectMake(0.0, 0.0, iconSide, iconSide);
    self.iconView.center = CGPointMake(CGRectGetMidX(self.contentView.bounds),
                                       CGRectGetMidY(self.contentView.bounds));
}

- (void)setSelectedAppearance:(BOOL)selected animated:(BOOL)animated {
    void (^changes)(void) = ^{
        self.transform = selected ? CGAffineTransformMakeScale(WCLiquidGlassSelectedScale,
                                                                WCLiquidGlassSelectedScale)
                                  : CGAffineTransformIdentity;
        self.iconView.transform = selected ? CGAffineTransformMakeScale(0.82, 0.82)
                                           : CGAffineTransformIdentity;
        self.layer.zPosition = selected ? 30.0 : 0.0;
    };
    if (!animated) {
        [self.layer removeAllAnimations];
        [self.iconView.layer removeAllAnimations];
        changes();
        return;
    }
    [UIView animateWithDuration:selected ? 0.24 : 0.20
                          delay:0
         usingSpringWithDamping:selected ? 0.70 : 0.86
          initialSpringVelocity:selected ? 0.8 : 0.35
                        options:UIViewAnimationOptionAllowUserInteraction |
                                UIViewAnimationOptionBeginFromCurrentState
                     animations:changes
                     completion:nil];
}

- (void)setDraggedAppearanceTowardPoint:(CGPoint)point inView:(UIView *)view {
    CGPoint center = [self.superview convertPoint:self.center toView:view];
    CGFloat deltaX = point.x - center.x;
    CGFloat deltaY = point.y - center.y;
    CGFloat distance = hypot(deltaX, deltaY);
    CGFloat angle = distance > 0.5 ? atan2(deltaY, deltaX) : 0.0;
    CGFloat progress = MIN(1.0, distance / MAX(self.diameter * 1.7, 1.0));
    CGFloat baseScale = WCLiquidGlassSelectedScale;
    CGFloat extraAlong = 1.0 + 0.10 * progress;
    CGFloat extraAcross = 1.0 - 0.04 * progress;
    CGFloat pull = MIN(self.diameter * 0.10, distance * 0.055);

    CGAffineTransform transform = CGAffineTransformMakeRotation(angle);
    transform = CGAffineTransformScale(transform,
                                       baseScale * extraAlong,
                                       baseScale * extraAcross);
    transform = CGAffineTransformRotate(transform, -angle);
    transform.tx += cos(angle) * pull;
    transform.ty += sin(angle) * pull;

    CGFloat iconBaseScale = 0.82;
    CGAffineTransform iconTransform = CGAffineTransformMakeRotation(angle);
    iconTransform = CGAffineTransformScale(iconTransform,
                                           iconBaseScale / extraAlong,
                                           iconBaseScale / extraAcross);
    iconTransform = CGAffineTransformRotate(iconTransform, -angle);

    [UIView performWithoutAnimation:^{
        self.transform = transform;
        self.iconView.transform = iconTransform;
        self.layer.zPosition = 30.0;
    }];
}

- (void)setToggleActiveAppearance:(BOOL)active {
    UIColor *activeColor = UIColor.systemGreenColor;
    self.layer.borderWidth = active ? 2.5 : 0.0;
    self.layer.borderColor = active ? activeColor.CGColor : UIColor.clearColor.CGColor;
    self.iconView.tintColor = active ? activeColor : UIColor.labelColor;
    self.accessibilityValue = active ? @"已开启" : @"已关闭";
}

@end

@interface WCLiquidGlassHostView : UIView <UIGestureRecognizerDelegate>

@property(nonatomic, strong) UIVisualEffectView *glassContainer;
@property(nonatomic, strong) UIControl *dismissControl;
@property(nonatomic, strong) WCLiquidGlassOrbView *anchorOrb;
@property(nonatomic, copy) NSArray<WCLiquidGlassOrbView *> *optionOrbs;
@property(nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *visibleItems;
@property(nonatomic, assign) BOOL menuOpen;
@property(nonatomic, assign) BOOL anchorOnLeft;
@property(nonatomic, assign) BOOL anchorIdleHidden;
@property(nonatomic, assign) NSUInteger idleHideGeneration;
@property(nonatomic, assign) NSUInteger contentRefreshGeneration;
@property(nonatomic, assign) NSUInteger menuTransitionGeneration;
@property(nonatomic, assign) CGPoint panStartCenter;
@property(nonatomic, assign) NSInteger highlightedIndex;
@property(nonatomic, assign) BOOL voiceTranscriptionActive;
@property(nonatomic, weak) UIView *observedChatInputView;
@property(nonatomic, assign) BOOL observedChatInputHadText;
@property(nonatomic, weak) UIView *manualChatInputView;
@property(nonatomic, assign) BOOL manualChatInputHasText;
@property(nonatomic, assign) BOOL manualChatInputStartedFromEmpty;
@property(nonatomic, assign) NSUInteger manualInputGeneration;
@property(nonatomic, assign) CGFloat keyboardTop;
@property(nonatomic, assign) CGFloat resolvedOptionDiameter;
@property(nonatomic, strong) UISelectionFeedbackGenerator *selectionFeedbackGenerator;
@property(nonatomic, weak) WCLiquidGlassOrbView *pressedOrb;
@property(nonatomic, assign) BOOL observesInputNotifications;

- (instancetype)initWithFrame:(CGRect)frame observesInputNotifications:(BOOL)observesInputNotifications;
- (void)reload;
- (void)openMenu;
- (void)closeMenuSelectingIndex:(NSInteger)index;
- (void)wc_resetMenuImmediately;
- (void)wc_activateOptionAtIndex:(NSInteger)index;
- (void)wc_cancelIdleHide;
- (void)wc_scheduleIdleHide;
- (void)wc_revealAnchorAnimated:(BOOL)animated;
- (NSArray<NSDictionary<NSString *, id> *> *)wc_currentVisibleItems;
- (BOOL)wc_isCurrentChatInputView:(UIView *)inputView;
- (WCLiquidGlassOrbView *)wc_newOptionOrbForItem:(NSDictionary<NSString *, id> *)item
                                        diameter:(CGFloat)diameter;
- (void)wc_refreshOpenMenuAnimated;
- (BOOL)wc_shouldRetryDoutuRefreshForInputHasText:(BOOL)inputHasText;
- (BOOL)wc_hasManualChatInput;
- (void)wc_updateVoiceOrbToggleAppearance;
- (void)wc_emitSelectionFeedback;
- (CGFloat)wc_optionDiameterForCount:(NSUInteger)count;
- (void)wc_layoutOptionOrbsAnimated:(BOOL)animated;
- (void)wc_updateAnchorVisual;
- (void)wc_beginPressOnOrb:(WCLiquidGlassOrbView *)orb towardPoint:(CGPoint)point;
- (void)wc_updatePressTowardPoint:(CGPoint)point;
- (void)wc_endPressAnimated:(BOOL)animated;

@end

@implementation WCLiquidGlassHostView

- (instancetype)initWithFrame:(CGRect)frame {
    return [self initWithFrame:frame observesInputNotifications:YES];
}

- (instancetype)initWithFrame:(CGRect)frame observesInputNotifications:(BOOL)observesInputNotifications {
    self = [super initWithFrame:frame];
    if (!self) {
        return nil;
    }

    self.backgroundColor = UIColor.clearColor;
    self.clipsToBounds = NO;
    _highlightedIndex = NSNotFound;
    _keyboardTop = CGFLOAT_MAX;
    _selectionFeedbackGenerator = [[UISelectionFeedbackGenerator alloc] init];
    _observesInputNotifications = observesInputNotifications;
    if (observesInputNotifications) {
        WCLiquidGlassManualTextEditMonitoringEnabled = YES;
    }

    _dismissControl = [[UIControl alloc] initWithFrame:self.bounds];
    _dismissControl.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _dismissControl.hidden = YES;
    [_dismissControl addTarget:self action:@selector(wc_backgroundTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_dismissControl];

    _glassContainer = [[UIVisualEffectView alloc] initWithEffect:WCLiquidGlassMakeContainerEffect()];
    _glassContainer.frame = self.bounds;
    _glassContainer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _glassContainer.backgroundColor = UIColor.clearColor;
    _glassContainer.clipsToBounds = NO;
    _glassContainer.contentView.clipsToBounds = NO;
    [self addSubview:_glassContainer];

    if (observesInputNotifications) {
        NSNotificationCenter *notificationCenter = NSNotificationCenter.defaultCenter;
        [notificationCenter addObserver:self
                               selector:@selector(wc_chatInputContentDidChange:)
                                   name:UITextViewTextDidChangeNotification
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(wc_chatInputContentDidChange:)
                                   name:UITextFieldTextDidChangeNotification
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(wc_manualTextEdit:)
                                   name:WCLiquidGlassManualTextEditNotification
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(wc_keyboardWillChangeFrame:)
                                   name:UIKeyboardWillChangeFrameNotification
                                 object:nil];
        [notificationCenter addObserver:self
                               selector:@selector(wc_keyboardWillHide:)
                                   name:UIKeyboardWillHideNotification
                                 object:nil];
    }

    [self reload];
    return self;
}

- (void)dealloc {
    if (self.observesInputNotifications) {
        WCLiquidGlassManualTextEditMonitoringEnabled = NO;
        [NSNotificationCenter.defaultCenter removeObserver:self];
    }
}

- (void)setVoiceTranscriptionActive:(BOOL)voiceTranscriptionActive {
    _voiceTranscriptionActive = voiceTranscriptionActive;
    self.observedChatInputView = WCLiquidGlassCurrentChatInputView();
    self.observedChatInputHadText = WCLiquidGlassCurrentChatInputHasText();
}

- (void)wc_emitSelectionFeedback {
    [self.selectionFeedbackGenerator selectionChanged];
    [self.selectionFeedbackGenerator prepare];
}

- (void)wc_beginPressOnOrb:(WCLiquidGlassOrbView *)orb towardPoint:(CGPoint)point {
    if (!orb) {
        return;
    }
    BOOL isContinuingCurrentPress = self.pressedOrb == orb;
    if (self.pressedOrb && self.pressedOrb != orb) {
        [self.pressedOrb setSelectedAppearance:NO animated:YES];
    }
    self.pressedOrb = orb;
    if (orb == self.anchorOrb && !isContinuingCurrentPress) {
        [orb setSelectedAppearance:YES animated:YES];
    }
    [orb setDraggedAppearanceTowardPoint:point inView:self];
}

- (void)wc_updatePressTowardPoint:(CGPoint)point {
    [self.pressedOrb setDraggedAppearanceTowardPoint:point inView:self];
}

- (void)wc_endPressAnimated:(BOOL)animated {
    WCLiquidGlassOrbView *pressedOrb = self.pressedOrb;
    self.pressedOrb = nil;
    [pressedOrb setSelectedAppearance:NO animated:animated];
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    for (WCLiquidGlassOrbView *orb in self.optionOrbs.reverseObjectEnumerator) {
        if (!orb.hidden && orb.alpha > 0.01) {
            CGPoint localPoint = [orb convertPoint:point fromView:self];
            UIView *hit = [orb hitTest:localPoint withEvent:event];
            if (hit) {
                return hit;
            }
        }
    }
    CGPoint anchorPoint = [self.anchorOrb convertPoint:point fromView:self];
    UIView *anchorHit = [self.anchorOrb hitTest:anchorPoint withEvent:event];
    if (anchorHit) {
        return anchorHit;
    }
    return self.menuOpen ? self.dismissControl : nil;
}

- (NSArray<NSDictionary<NSString *, id> *> *)wc_currentVisibleItems {
    NSMutableArray<NSDictionary<NSString *, id> *> *visibleItems = [NSMutableArray array];
    id tabController = WCLiquidGlassCurrentTabController();
    NSString *currentTabAction = tabController
        ? [NSString stringWithFormat:@"tab.%ld", (long)WCLiquidGlassCurrentTabIndex(tabController)]
        : nil;
    NSArray<NSDictionary<NSString *, id> *> *buttonItems = WCLiquidGlassPreferences.buttonItems;
    NSSet<NSString *> *availableActions = WCLiquidGlassAvailableActionIdentifiers(buttonItems);
    BOOL manualChatInputHidesVoiceAction = [self wc_hasManualChatInput];
    for (NSDictionary<NSString *, id> *item in buttonItems) {
        NSString *actionIdentifier = item[@"action"];
        BOOL voiceAction = [actionIdentifier isEqualToString:WCLiquidGlassActionVoiceInput];
        BOOL voiceActionStaysAvailable = voiceAction && !manualChatInputHidesVoiceAction &&
            self.voiceTranscriptionActive;
        BOOL canPerform = voiceAction && manualChatInputHidesVoiceAction
            ? NO
            : (voiceActionStaysAvailable || [availableActions containsObject:actionIdentifier]);
        if (![actionIdentifier isEqualToString:currentTabAction] &&
            canPerform) {
            [visibleItems addObject:item];
        }
    }
    return visibleItems.copy;
}

- (WCLiquidGlassOrbView *)wc_newOptionOrbForItem:(NSDictionary<NSString *, id> *)item
                                        diameter:(CGFloat)diameter {
    WCLiquidGlassOrbView *orb = [[WCLiquidGlassOrbView alloc] initWithDiameter:diameter];
    [orb configureWithActionIdentifier:item[@"action"]];
    orb.alpha = 0.0;
    orb.hidden = YES;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                         action:@selector(wc_optionTapped:)];
    [orb addGestureRecognizer:tap];

    UILongPressGestureRecognizer *longPress =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                      action:@selector(wc_optionLongPressed:)];
    longPress.minimumPressDuration = 0.18;
    longPress.allowableMovement = 96.0;
    [orb addGestureRecognizer:longPress];
    [self.glassContainer.contentView addSubview:orb];
    return orb;
}

- (void)reload {
    [self wc_resetMenuImmediately];
    self.anchorIdleHidden = NO;
    CGFloat diameter = WCLiquidGlassButtonDiameter();
    self.anchorOnLeft = WCLiquidGlassPreferences.anchorOnLeft;

    NSArray<NSDictionary<NSString *, id> *> *newVisibleItems = [self wc_currentVisibleItems];
    CGFloat optionDiameter = [self wc_optionDiameterForCount:newVisibleItems.count];
    BOOL voiceActionAvailable = [newVisibleItems indexOfObjectPassingTest:^BOOL(NSDictionary *item,
                                                                                NSUInteger index,
                                                                                BOOL *stop) {
        return [item[@"action"] isEqualToString:WCLiquidGlassActionVoiceInput];
    }] != NSNotFound;
    if (!voiceActionAvailable) {
        self.voiceTranscriptionActive = NO;
    }

    NSMutableArray<WCLiquidGlassOrbView *> *remainingOrbs = [self.optionOrbs mutableCopy] ?: [NSMutableArray array];
    NSMutableArray<WCLiquidGlassOrbView *> *orbs = [NSMutableArray arrayWithCapacity:newVisibleItems.count];
    UIUserInterfaceStyle imageStyle = UITraitCollection.currentTraitCollection.userInterfaceStyle;
    for (NSDictionary<NSString *, id> *item in newVisibleItems) {
        NSString *actionIdentifier = item[@"action"];
        NSUInteger reusableIndex = [remainingOrbs indexOfObjectPassingTest:^BOOL(WCLiquidGlassOrbView *orb,
                                                                                 NSUInteger index,
                                                                                 BOOL *stop) {
            return [orb.actionIdentifier isEqualToString:actionIdentifier];
        }];
        WCLiquidGlassOrbView *orb = nil;
        if (reusableIndex != NSNotFound) {
            orb = remainingOrbs[reusableIndex];
            [remainingOrbs removeObjectAtIndex:reusableIndex];
            orb.effect = WCLiquidGlassMakeEffect();
            if (orb.imageStyle != imageStyle) {
                [orb configureWithActionIdentifier:actionIdentifier];
            }
        } else {
            orb = [self wc_newOptionOrbForItem:item diameter:optionDiameter];
        }
        [orbs addObject:orb];
    }
    for (WCLiquidGlassOrbView *orb in remainingOrbs) {
        [orb removeFromSuperview];
    }
    self.visibleItems = newVisibleItems;
    self.optionOrbs = orbs.copy;

    if (!self.anchorOrb || fabs(self.anchorOrb.diameter - diameter) > 0.1) {
        [self.anchorOrb removeFromSuperview];
        self.anchorOrb = [[WCLiquidGlassOrbView alloc] initWithDiameter:diameter];
        self.anchorOrb.accessibilityLabel = @"WCLiquidGlass 菜单";
        [self.glassContainer.contentView addSubview:self.anchorOrb];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                             action:@selector(wc_anchorTapped:)];
        [self.anchorOrb addGestureRecognizer:tap];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                             action:@selector(wc_anchorPanned:)];
        pan.delegate = self;
        [self.anchorOrb addGestureRecognizer:pan];

        UILongPressGestureRecognizer *longPress =
            [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                          action:@selector(wc_anchorLongPressed:)];
        longPress.minimumPressDuration = 0.22;
        longPress.allowableMovement = 96.0;
        longPress.delegate = self;
        [self.anchorOrb addGestureRecognizer:longPress];
    }
    self.anchorOrb.effect = WCLiquidGlassMakeEffect();
    [self wc_updateAnchorVisual];
    [self setNeedsLayout];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self wc_scheduleIdleHide];
    });
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!self.menuOpen) {
        [self wc_layoutAnchorFromPreferences];
    } else {
        [self wc_layoutOptionOrbsAnimated:NO];
    }
}

- (void)wc_layoutAnchorFromPreferences {
    CGFloat diameter = self.anchorOrb.diameter;
    UIEdgeInsets safeArea = self.safeAreaInsets;
    CGFloat x = self.anchorIdleHidden
        ? (self.anchorOnLeft ? 0.0 : CGRectGetWidth(self.bounds))
        : (self.anchorOnLeft ? diameter * 0.5 + 12.0
                             : CGRectGetWidth(self.bounds) - diameter * 0.5 - 12.0);
    CGFloat minimumY = safeArea.top + diameter * 0.5 + 12.0;
    CGFloat maximumY = [self wc_effectiveLayoutBottom] - diameter * 0.5 - 12.0;
    maximumY = MAX(minimumY, maximumY);
    CGFloat y = CGRectGetHeight(self.bounds) * WCLiquidGlassPreferences.anchorYFraction;
    self.anchorOrb.center = CGPointMake(x, MIN(maximumY, MAX(minimumY, y)));
}

- (CGFloat)wc_effectiveLayoutBottom {
    CGFloat naturalBottom = CGRectGetHeight(self.bounds) - self.safeAreaInsets.bottom;
    return MIN(naturalBottom, self.keyboardTop);
}

- (void)wc_animateForKeyboardNotification:(NSNotification *)notification
                                   changes:(void (^)(void))changes {
    NSDictionary *userInfo = notification.userInfo;
    NSTimeInterval duration = [userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationCurve curve = [userInfo[UIKeyboardAnimationCurveUserInfoKey] integerValue];
    UIViewAnimationOptions options = (UIViewAnimationOptions)(curve << 16) |
                                     UIViewAnimationOptionBeginFromCurrentState |
                                     UIViewAnimationOptionAllowUserInteraction;
    [UIView animateWithDuration:duration
                          delay:0
                        options:options
                     animations:changes
                     completion:nil];
}

- (void)wc_layoutForKeyboardNotification:(NSNotification *)notification {
    [self wc_animateForKeyboardNotification:notification changes:^{
        [self wc_layoutAnchorFromPreferences];
        if (self.menuOpen) {
            [self wc_layoutOptionOrbsAnimated:NO];
        }
    }];
}

- (void)wc_keyboardWillChangeFrame:(NSNotification *)notification {
    CGRect endFrame = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect localFrame = [self convertRect:endFrame fromView:nil];
    CGFloat boundsHeight = CGRectGetHeight(self.bounds);
    BOOL coversBottom = CGRectGetMaxY(localFrame) >= boundsHeight - 1.0 &&
                        CGRectGetMinY(localFrame) < boundsHeight;
    self.keyboardTop = coversBottom ? MAX(self.safeAreaInsets.top, CGRectGetMinY(localFrame))
                                    : CGFLOAT_MAX;
    [self wc_layoutForKeyboardNotification:notification];
}

- (void)wc_keyboardWillHide:(NSNotification *)notification {
    self.keyboardTop = CGFLOAT_MAX;
    [self wc_layoutForKeyboardNotification:notification];
}

- (BOOL)wc_isCurrentChatInputView:(UIView *)inputView {
    UIViewController *visibleController = WCLiquidGlassVisibleController();
    if (!inputView.isFirstResponder ||
        !visibleController.viewIfLoaded ||
        ![inputView isDescendantOfView:visibleController.view]) {
        return NO;
    }

    for (UIView *view = inputView; view; view = view.superview) {
        NSString *className = NSStringFromClass(view.class);
        if ([className containsString:@"MMGrowTextView"] ||
            [className containsString:@"MMInputToolView"] ||
            [className containsString:@"MessageInputTool"] ||
            [className containsString:@"ChatInputTool"]) {
            return YES;
        }
        if (view == visibleController.view) {
            break;
        }
    }
    return NO;
}

- (void)wc_chatInputContentDidChange:(NSNotification *)notification {
    if (![notification.object isKindOfClass:UIView.class]) {
        return;
    }

    UIView *inputView = (UIView *)notification.object;
    if (![self wc_isCurrentChatInputView:inputView]) {
        return;
    }

    BOOL inputHasText = [inputView isKindOfClass:UITextView.class]
        ? ((UITextView *)inputView).text.length > 0
        : ([inputView isKindOfClass:UITextField.class]
            ? ((UITextField *)inputView).text.length > 0
            : NO);
    BOOL inputWasCleared = self.voiceTranscriptionActive &&
        self.observedChatInputView == inputView &&
        self.observedChatInputHadText &&
        !inputHasText;
    self.observedChatInputView = inputView;
    self.observedChatInputHadText = inputHasText;
    if (inputWasCleared) {
        self.voiceTranscriptionActive = NO;
        [self wc_updateVoiceOrbToggleAppearance];
    }

    if (!self.menuOpen || !WCLiquidGlassDoutuAssistantEnabled() ||
        ![self wc_shouldRetryDoutuRefreshForInputHasText:inputHasText]) {
        return;
    }

    NSUInteger generation = ++self.contentRefreshGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.06 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || generation != self.contentRefreshGeneration ||
            !self.menuOpen) {
            return;
        }
        [self wc_refreshOpenMenuAnimated];
        if (![self wc_shouldRetryDoutuRefreshForInputHasText:inputHasText]) {
            return;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.22 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || generation != self.contentRefreshGeneration ||
                !self.menuOpen) {
                return;
            }
            [self wc_refreshOpenMenuAnimated];
        });
    });
}

- (BOOL)wc_shouldRetryDoutuRefreshForInputHasText:(BOOL)inputHasText {
    BOOL hasDoutuAction = [WCLiquidGlassPreferences.buttonItems indexOfObjectPassingTest:
        ^BOOL(NSDictionary<NSString *, id> *item, NSUInteger index, BOOL *stop) {
            return [item[@"action"] isEqualToString:WCLiquidGlassActionDoutuAssistant];
        }] != NSNotFound;
    if (!hasDoutuAction) {
        return NO;
    }
    BOOL doutuIsVisible = [self.visibleItems indexOfObjectPassingTest:
        ^BOOL(NSDictionary<NSString *, id> *item, NSUInteger index, BOOL *stop) {
            return [item[@"action"] isEqualToString:WCLiquidGlassActionDoutuAssistant];
        }] != NSNotFound;
    return doutuIsVisible != inputHasText;
}

- (void)wc_manualTextEdit:(NSNotification *)notification {
    if (![notification.object isKindOfClass:UIView.class] ||
        ![self wc_isCurrentChatInputView:notification.object]) {
        return;
    }
    UIView *inputView = notification.object;
    BOOL wasVoiceTranscriptionActive = self.voiceTranscriptionActive;
    BOOL inputWasEmpty = !WCLiquidGlassCurrentChatInputHasText();
    self.manualChatInputView = inputView;
    if (wasVoiceTranscriptionActive) {
        self.manualChatInputStartedFromEmpty = NO;
    } else if (inputWasEmpty) {
        self.manualChatInputStartedFromEmpty = YES;
    }
    NSUInteger generation = ++self.manualInputGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || generation != self.manualInputGeneration ||
            ![self wc_isCurrentChatInputView:inputView]) {
            return;
        }
        BOOL inputHasText = WCLiquidGlassCurrentChatInputHasText();
        if (!inputHasText) {
            self.manualChatInputStartedFromEmpty = NO;
        }
        self.manualChatInputHasText = !wasVoiceTranscriptionActive && inputHasText &&
            self.manualChatInputStartedFromEmpty;
        if (wasVoiceTranscriptionActive && self.voiceTranscriptionActive) {
            self.voiceTranscriptionActive = NO;
            [self wc_updateVoiceOrbToggleAppearance];
        }
        if (self.menuOpen) {
            [self wc_refreshOpenMenuAnimated];
        }
    });
}

- (BOOL)wc_hasManualChatInput {
    return self.manualChatInputHasText &&
        self.manualChatInputView == WCLiquidGlassCurrentChatInputView() &&
        WCLiquidGlassCurrentChatInputHasText();
}

- (void)wc_updateVoiceOrbToggleAppearance {
    for (WCLiquidGlassOrbView *orb in self.optionOrbs) {
        if ([orb.actionIdentifier isEqualToString:WCLiquidGlassActionVoiceInput]) {
            [orb setToggleActiveAppearance:self.voiceTranscriptionActive];
            break;
        }
    }
}

- (void)wc_cancelIdleHide {
    self.idleHideGeneration += 1;
}

- (void)wc_scheduleIdleHide {
    if (self.menuOpen || !self.anchorOrb) {
        return;
    }
    NSUInteger generation = ++self.idleHideGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.8 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || self.menuOpen || generation != self.idleHideGeneration) {
            return;
        }
        self.anchorIdleHidden = YES;
        [UIView animateWithDuration:0.36
                              delay:0
             usingSpringWithDamping:0.82
              initialSpringVelocity:0.4
                            options:UIViewAnimationOptionAllowUserInteraction |
                                    UIViewAnimationOptionBeginFromCurrentState
                         animations:^{
            [self wc_layoutAnchorFromPreferences];
        } completion:nil];
    });
}

- (void)wc_revealAnchorAnimated:(BOOL)animated {
    [self wc_cancelIdleHide];
    self.anchorIdleHidden = NO;
    void (^changes)(void) = ^{
        [self wc_layoutAnchorFromPreferences];
    };
    if (!animated) {
        changes();
        return;
    }
    [UIView animateWithDuration:0.3
                          delay:0
         usingSpringWithDamping:0.82
          initialSpringVelocity:0.5
                        options:UIViewAnimationOptionAllowUserInteraction |
                                UIViewAnimationOptionBeginFromCurrentState
                     animations:changes
                     completion:nil];
}

- (NSArray<NSValue *> *)wc_fittedCompactCentersFromOffsets:(NSArray<NSValue *> *)offsets
                                                   minimumY:(CGFloat)minimumY
                                                   maximumY:(CGFloat)maximumY
                                                    diameter:(CGFloat)diameter {
    if (offsets.count == 0) {
        return @[];
    }

    CGFloat direction = self.anchorOnLeft ? 1.0 : -1.0;
    CGFloat minimumX = self.safeAreaInsets.left + diameter * 0.5 + 12.0;
    CGFloat maximumX = CGRectGetWidth(self.bounds) - self.safeAreaInsets.right - diameter * 0.5 - 12.0;
    CGFloat boundsMinimumX = CGFLOAT_MAX;
    CGFloat boundsMaximumX = -CGFLOAT_MAX;
    CGFloat boundsMinimumY = CGFLOAT_MAX;
    CGFloat boundsMaximumY = -CGFLOAT_MAX;
    for (NSValue *value in offsets) {
        CGPoint offset = value.CGPointValue;
        CGPoint center = CGPointMake(self.anchorOrb.center.x + direction * offset.x,
                                     self.anchorOrb.center.y + offset.y);
        boundsMinimumX = MIN(boundsMinimumX, center.x);
        boundsMaximumX = MAX(boundsMaximumX, center.x);
        boundsMinimumY = MIN(boundsMinimumY, center.y);
        boundsMaximumY = MAX(boundsMaximumY, center.y);
    }

    CGFloat translationY = 0.0;
    if (boundsMinimumY < minimumY) {
        translationY = minimumY - boundsMinimumY;
    }
    if (boundsMaximumY + translationY > maximumY) {
        translationY += maximumY - (boundsMaximumY + translationY);
    }

    CGFloat translationX = 0.0;
    if (boundsMinimumX < minimumX) {
        translationX = minimumX - boundsMinimumX;
    }
    if (boundsMaximumX + translationX > maximumX) {
        translationX += maximumX - (boundsMaximumX + translationX);
    }

    NSMutableArray<NSValue *> *fittedCenters = [NSMutableArray arrayWithCapacity:offsets.count];
    for (NSValue *value in offsets) {
        CGPoint offset = value.CGPointValue;
        CGPoint center = CGPointMake(self.anchorOrb.center.x + direction * offset.x,
                                     self.anchorOrb.center.y + offset.y);
        center.x += translationX;
        center.y += translationY;
        [fittedCenters addObject:[NSValue valueWithCGPoint:center]];
    }
    return fittedCenters.copy;
}

- (NSArray<NSValue *> *)wc_compactOptionCentersWithDiameter:(CGFloat)diameter
                                                    minimumY:(CGFloat)minimumY
                                                    maximumY:(CGFloat)maximumY {
    NSUInteger count = self.optionOrbs.count;
    CGFloat anchorClearance = self.anchorOrb.diameter * 0.5 + diameter * 0.5 + 16.0;
    NSMutableArray<NSValue *> *offsets = [NSMutableArray arrayWithCapacity:count];

    switch (WCLiquidGlassPreferences.compactLayoutStyle) {
        case WCLiquidGlassCompactLayoutStyleSCurve: {
            WCLiquidGlassAppendFlowingSOffsets(offsets, count, anchorClearance, diameter);
            break;
        }
        case WCLiquidGlassCompactLayoutStyleWideFan: {
            CGFloat targetCenterSpacing = diameter + 9.0;
            NSUInteger middleCount = MAX(2, (NSUInteger)lround((count - 1) * 0.36));
            const NSUInteger ringCounts[] = {1, middleCount, count - 1 - middleCount};
            for (NSUInteger ringIndex = 0; ringIndex < 3; ringIndex += 1) {
                NSUInteger ringCount = ringCounts[ringIndex];
                CGFloat radius = anchorClearance + targetCenterSpacing * ringIndex;
                CGFloat halfAngle = WCLiquidGlassRingHalfAngle(ringCount,
                                                               radius,
                                                               targetCenterSpacing);
                WCLiquidGlassAppendArcOffsets(offsets,
                                               ringCount,
                                               radius,
                                               -halfAngle,
                                               halfAngle,
                                               0.0);
            }
            break;
        }
        case WCLiquidGlassCompactLayoutStylePetalCluster: {
            CGFloat targetCenterSpacing = diameter + 10.0;
            if (count > 8) {
                NSUInteger petalCount = count - 1;
                CGFloat ringRadius = targetCenterSpacing /
                    (2.0 * sin(M_PI / petalCount));
                CGFloat clusterCenterX = anchorClearance + ringRadius;
                [offsets addObject:[NSValue valueWithCGPoint:CGPointMake(clusterCenterX, 0.0)]];
                for (NSUInteger index = 0; index < petalCount; index += 1) {
                    CGFloat angle = M_PI + M_PI * 2.0 * index / petalCount;
                    [offsets addObject:[NSValue valueWithCGPoint:CGPointMake(clusterCenterX + ringRadius * cos(angle),
                                                                             ringRadius * sin(angle))]];
                }
            } else {
                CGFloat radius = targetCenterSpacing / (2.0 * sin(M_PI / count));
                CGFloat clusterCenterX = anchorClearance + radius;
                for (NSUInteger index = 0; index < count; index += 1) {
                    CGFloat angle = -M_PI_2 + M_PI * 2.0 * index / count;
                    [offsets addObject:[NSValue valueWithCGPoint:CGPointMake(clusterCenterX + radius * cos(angle),
                                                                             radius * sin(angle))]];
                }
            }
            break;
        }
        default: {
            NSUInteger innerCount = count / 2 - 1;
            NSUInteger outerCount = count - innerCount;
            CGFloat targetCenterSpacing = diameter + 10.0;
            CGFloat low = 90.0 * M_PI / 180.0;
            CGFloat high = 170.0 * M_PI / 180.0;
            for (NSUInteger iteration = 0; iteration < 50; iteration += 1) {
                CGFloat middle = (low + high) * 0.5;
                CGFloat innerRadius = 0.0;
                CGFloat outerRadius = 0.0;
                WCLiquidGlassCrescentRadii(innerCount,
                                           outerCount,
                                           targetCenterSpacing,
                                           middle,
                                           &innerRadius,
                                           &outerRadius);
                if (outerRadius - innerRadius > targetCenterSpacing) {
                    low = middle;
                } else {
                    high = middle;
                }
            }
            CGFloat span = MIN((low + high) * 0.5, 150.0 * M_PI / 180.0);
            CGFloat innerRadius = 0.0;
            CGFloat outerRadius = 0.0;
            WCLiquidGlassCrescentRadii(innerCount,
                                       outerCount,
                                       targetCenterSpacing,
                                       span,
                                       &innerRadius,
                                       &outerRadius);
            CGFloat centerX = anchorClearance - innerRadius;
            WCLiquidGlassAppendArcOffsets(offsets,
                                           innerCount,
                                           innerRadius,
                                           -span * 0.5,
                                           span * 0.5,
                                           centerX);
            WCLiquidGlassAppendArcOffsets(offsets,
                                           outerCount,
                                           outerRadius,
                                           -span * 0.5,
                                           span * 0.5,
                                           centerX);
            WCLiquidGlassAlignOffsetsToAnchorDistance(offsets, anchorClearance);
            break;
        }
    }

    return [self wc_fittedCompactCentersFromOffsets:offsets
                                            minimumY:minimumY
                                            maximumY:maximumY
                                             diameter:diameter];
}

- (CGFloat)wc_optionDiameterForCount:(NSUInteger)count {
    CGFloat preferredDiameter = self.anchorOrb ? self.anchorOrb.diameter : WCLiquidGlassButtonDiameter();
    if (count <= 8) {
        return preferredDiameter;
    }
    CGFloat countAdjustedMaximum = MAX(44.0, 50.0 - (count - 9) * 2.0);
    return MAX(44.0, MIN(countAdjustedMaximum, preferredDiameter * 0.82));
}

- (CGFloat)wc_optionDiameter {
    return [self wc_optionDiameterForCount:self.optionOrbs.count];
}

- (NSArray<NSValue *> *)wc_optionCenters {
    NSUInteger count = self.optionOrbs.count;
    if (count == 0) {
        return @[];
    }

    CGFloat diameter = [self wc_optionDiameter];
    CGFloat desiredGap = MAX(diameter + 10.0, round(diameter * (count > 4 ? 1.16 : 1.28)));
    UIEdgeInsets safeArea = self.safeAreaInsets;
    CGFloat minimumY = safeArea.top + diameter * 0.5 + 18.0;
    CGFloat maximumY = [self wc_effectiveLayoutBottom] - diameter * 0.5 - 18.0;
    maximumY = MAX(minimumY, maximumY);
    CGFloat availableHeight = maximumY - minimumY;
    NSUInteger compactMinimumCount =
        WCLiquidGlassPreferences.compactLayoutStyle == WCLiquidGlassCompactLayoutStyleDoubleCrescent
            ? WCLiquidGlassDoubleCrescentMinimumCount
            : WCLiquidGlassCompactMinimumCount;
    BOOL spaceRequiresCompactLayout = count > 1 &&
        desiredGap * (count - 1) > availableHeight;
    if (spaceRequiresCompactLayout && count < compactMinimumCount) {
        CGFloat usableHeight = [self wc_effectiveLayoutBottom] - safeArea.top - 36.0;
        CGFloat maximumDefaultDiameter =
            (usableHeight - 8.0 * (count - 1)) / MAX((CGFloat)count, 1.0);
        diameter = MAX(40.0, MIN(diameter, floor(maximumDefaultDiameter)));
        desiredGap = MAX(diameter + 10.0,
                         round(diameter * (count > 4 ? 1.16 : 1.28)));
        minimumY = safeArea.top + diameter * 0.5 + 18.0;
        maximumY = [self wc_effectiveLayoutBottom] - diameter * 0.5 - 18.0;
        maximumY = MAX(minimumY, maximumY);
        availableHeight = maximumY - minimumY;
    }
    BOOL needsCompactLayout = count >= compactMinimumCount &&
        desiredGap * (count - 1) > availableHeight;
    if (needsCompactLayout) {
        NSArray<NSValue *> *centers = nil;
        while (diameter >= 40.0) {
            minimumY = safeArea.top + diameter * 0.5 + 18.0;
            maximumY = [self wc_effectiveLayoutBottom] - diameter * 0.5 - 18.0;
            maximumY = MAX(minimumY, maximumY);
            centers = [self wc_compactOptionCentersWithDiameter:diameter
                                                        minimumY:minimumY
                                                        maximumY:maximumY];
            CGFloat minimumX = safeArea.left + diameter * 0.5 + 12.0;
            CGFloat maximumX = CGRectGetWidth(self.bounds) - safeArea.right - diameter * 0.5 - 12.0;
            BOOL fits = YES;
            for (NSValue *value in centers) {
                CGPoint center = value.CGPointValue;
                if (center.x < minimumX - 0.5 || center.x > maximumX + 0.5 ||
                    center.y < minimumY - 0.5 || center.y > maximumY + 0.5) {
                    fits = NO;
                    break;
                }
            }
            if (fits || diameter <= 40.0) {
                self.resolvedOptionDiameter = diameter;
                return centers;
            }
            diameter = MAX(40.0, diameter - 2.0);
        }
    }

    self.resolvedOptionDiameter = diameter;

    CGFloat gap = count > 1 ? MIN(desiredGap, availableHeight / (count - 1)) : 0.0;
    CGFloat totalHeight = diameter + gap * (count - 1);
    CGFloat startY = self.anchorOrb.center.y - totalHeight * 0.5 + diameter * 0.5;
    startY = MAX(minimumY, MIN(startY, maximumY - gap * (count - 1)));

    CGFloat middle = (count - 1) * 0.5;
    CGFloat divisor = MAX(middle, 1.0);
    CGFloat anchorClearance = self.anchorOrb.diameter * 0.5 + diameter * 0.5 + 10.0;
    CGFloat minimumX = safeArea.left + diameter * 0.5 + 12.0;
    CGFloat maximumX = CGRectGetWidth(self.bounds) - safeArea.right - diameter * 0.5 - 12.0;
    CGFloat availableHorizontal = self.anchorOnLeft
        ? maximumX - self.anchorOrb.center.x
        : self.anchorOrb.center.x - minimumX;
    CGFloat maximumCurveDepth = MAX(0.0, availableHorizontal - anchorClearance);
    CGFloat preferredCurveDepth = round(diameter * (count > 6 ? 1.55 : 1.35));
    CGFloat curveDepth = MIN(preferredCurveDepth, maximumCurveDepth);
    NSMutableArray<NSValue *> *offsets = [NSMutableArray arrayWithCapacity:count];
    if (count >= 2 && count <= 3) {
        CGFloat fanRadius = self.anchorOrb.diameter * 0.5 + diameter * 0.5 + 16.0;
        CGFloat targetChord = diameter + (count == 2 ? 16.0 : 10.0);
        CGFloat chordRatio = MIN(0.98, targetChord / (fanRadius * 2.0));
        CGFloat halfAngle = count == 2 ? asin(chordRatio) : asin(chordRatio) * 2.0;
        for (NSUInteger index = 0; index < count; index += 1) {
            CGFloat progress = (CGFloat)index / (count - 1);
            CGFloat angle = -halfAngle + halfAngle * 2.0 * progress;
            [offsets addObject:[NSValue valueWithCGPoint:CGPointMake(fanRadius * cos(angle),
                                                                     fanRadius * sin(angle))]];
        }
        return [self wc_fittedCompactCentersFromOffsets:offsets
                                                minimumY:minimumY
                                                maximumY:maximumY
                                                 diameter:diameter];
    }
    for (NSUInteger index = 0; index < count; index += 1) {
        CGFloat normalizedDistance = fabs((CGFloat)index - middle) / divisor;
        CGFloat inward = anchorClearance + (count > 1 ? curveDepth * cos(normalizedDistance * M_PI_2) : 0.0);
        CGFloat y = startY + gap * index - self.anchorOrb.center.y;
        [offsets addObject:[NSValue valueWithCGPoint:CGPointMake(inward, y)]];
    }
    return [self wc_fittedCompactCentersFromOffsets:offsets
                                            minimumY:minimumY
                                            maximumY:maximumY
                                             diameter:diameter];
}

- (void)wc_layoutOptionOrbsAnimated:(BOOL)animated {
    NSArray<NSValue *> *centers = [self wc_optionCenters];
    CGFloat diameter = self.resolvedOptionDiameter > 0.0
        ? self.resolvedOptionDiameter
        : [self wc_optionDiameter];
    [self.optionOrbs enumerateObjectsUsingBlock:^(WCLiquidGlassOrbView *orb,
                                                   NSUInteger index,
                                                   BOOL *stop) {
        if (index >= centers.count) {
            return;
        }
        [orb prepareForDiameter:diameter];
        void (^changes)(void) = ^{
            orb.bounds = CGRectMake(0.0, 0.0, diameter, diameter);
            orb.center = centers[index].CGPointValue;
            orb.alpha = 1.0;
            orb.transform = index == self.highlightedIndex
                ? CGAffineTransformMakeScale(WCLiquidGlassSelectedScale, WCLiquidGlassSelectedScale)
                : CGAffineTransformIdentity;
        };
        if (animated) {
            [UIView animateWithDuration:0.48
                                  delay:index * 0.035
                 usingSpringWithDamping:0.54
                  initialSpringVelocity:0.95
                                options:UIViewAnimationOptionAllowUserInteraction |
                                        UIViewAnimationOptionBeginFromCurrentState
                             animations:changes
                             completion:nil];
        } else {
            changes();
        }
    }];
}

- (void)wc_refreshOpenMenuAnimated {
    if (!self.menuOpen) {
        return;
    }

    NSArray<NSDictionary<NSString *, id> *> *newVisibleItems = [self wc_currentVisibleItems];
    NSMutableArray<NSString *> *oldActionIdentifiers = [NSMutableArray array];
    for (NSDictionary<NSString *, id> *item in self.visibleItems) {
        [oldActionIdentifiers addObject:item[@"action"]];
    }
    NSMutableArray<NSString *> *newActionIdentifiers = [NSMutableArray array];
    for (NSDictionary<NSString *, id> *item in newVisibleItems) {
        [newActionIdentifiers addObject:item[@"action"]];
    }
    if ([oldActionIdentifiers isEqualToArray:newActionIdentifiers]) {
        return;
    }

    [self wc_setHighlightedIndex:NSNotFound];
    NSMutableDictionary<NSString *, WCLiquidGlassOrbView *> *existingOrbs = [NSMutableDictionary dictionary];
    for (WCLiquidGlassOrbView *orb in self.optionOrbs) {
        if (orb.actionIdentifier) {
            existingOrbs[orb.actionIdentifier] = orb;
        }
    }

    CGFloat diameter = [self wc_optionDiameterForCount:newVisibleItems.count];
    NSMutableArray<WCLiquidGlassOrbView *> *newOrbs = [NSMutableArray arrayWithCapacity:newVisibleItems.count];
    for (NSDictionary<NSString *, id> *item in newVisibleItems) {
        NSString *actionIdentifier = item[@"action"];
        WCLiquidGlassOrbView *orb = existingOrbs[actionIdentifier];
        if (orb) {
            [existingOrbs removeObjectForKey:actionIdentifier];
        } else {
            orb = [self wc_newOptionOrbForItem:item diameter:diameter];
            orb.center = self.anchorOrb.center;
            orb.transform = CGAffineTransformMakeScale(0.72, 0.72);
        }
        orb.hidden = NO;
        [newOrbs addObject:orb];
    }

    NSArray<WCLiquidGlassOrbView *> *removedOrbs = existingOrbs.allValues;
    self.visibleItems = newVisibleItems;
    self.optionOrbs = newOrbs.copy;
    BOOL voiceActionAvailable = [newActionIdentifiers containsObject:WCLiquidGlassActionVoiceInput];
    if (!voiceActionAvailable) {
        self.voiceTranscriptionActive = NO;
    }

    for (WCLiquidGlassOrbView *orb in removedOrbs) {
        [UIView animateWithDuration:0.24
                              delay:0
                            options:UIViewAnimationOptionBeginFromCurrentState |
                                    UIViewAnimationOptionAllowUserInteraction
                         animations:^{
            orb.alpha = 0.0;
            orb.transform = CGAffineTransformMakeScale(0.68, 0.68);
        } completion:^(__unused BOOL finished) {
            [orb removeFromSuperview];
        }];
    }
    [self wc_layoutOptionOrbsAnimated:YES];
}

- (void)openMenu {
    if (self.menuOpen) {
        return;
    }
    [self reload];
    [self wc_revealAnchorAnimated:NO];
    if (self.optionOrbs.count == 0) {
        [self wc_scheduleIdleHide];
        return;
    }
    self.menuOpen = YES;
    [self.selectionFeedbackGenerator prepare];
    self.dismissControl.hidden = NO;
    self.highlightedIndex = NSNotFound;
    [self wc_updateAnchorVisual];

    for (WCLiquidGlassOrbView *orb in self.optionOrbs) {
        if ([orb.actionIdentifier isEqualToString:WCLiquidGlassActionVoiceInput]) {
            [orb setToggleActiveAppearance:self.voiceTranscriptionActive];
        }
        orb.hidden = NO;
        orb.center = self.anchorOrb.center;
        orb.alpha = 0.0;
        orb.transform = CGAffineTransformMakeScale(0.72, 0.72);
    }
    [self wc_layoutOptionOrbsAnimated:YES];
}

- (void)wc_resetMenuImmediately {
    [self wc_cancelIdleHide];
    self.contentRefreshGeneration += 1;
    self.menuTransitionGeneration += 1;
    self.menuOpen = NO;
    self.dismissControl.hidden = YES;
    self.highlightedIndex = NSNotFound;
    [self wc_endPressAnimated:NO];

    [self.anchorOrb.layer removeAllAnimations];
    [self.anchorOrb.iconView.layer removeAllAnimations];
    [self.optionOrbs enumerateObjectsUsingBlock:^(WCLiquidGlassOrbView *orb,
                                                   NSUInteger index,
                                                   BOOL *stop) {
        [orb setSelectedAppearance:NO animated:NO];
        orb.center = self.anchorOrb.center;
        orb.alpha = 0.0;
        orb.transform = CGAffineTransformMakeScale(0.72, 0.72);
        orb.hidden = YES;
    }];
    [self wc_updateAnchorVisual];
}

- (void)closeMenuSelectingIndex:(NSInteger)index {
    if (!self.menuOpen) {
        return;
    }
    self.menuOpen = NO;
    self.contentRefreshGeneration += 1;
    NSUInteger transitionGeneration = ++self.menuTransitionGeneration;
    self.dismissControl.hidden = YES;
    NSString *actionIdentifier = nil;
    if (index >= 0 && index < (NSInteger)self.optionOrbs.count) {
        actionIdentifier = self.optionOrbs[index].actionIdentifier;
    }
    [self wc_endPressAnimated:YES];
    [self wc_setHighlightedIndex:NSNotFound];
    [self wc_updateAnchorVisual];

    [self.optionOrbs enumerateObjectsUsingBlock:^(WCLiquidGlassOrbView *orb,
                                                   NSUInteger orbIndex,
                                                   BOOL *stop) {
        [UIView animateWithDuration:0.2
                              delay:orbIndex * 0.018
                            options:UIViewAnimationOptionBeginFromCurrentState
                         animations:^{
            orb.center = self.anchorOrb.center;
            orb.alpha = 0.0;
            orb.transform = CGAffineTransformMakeScale(0.72, 0.72);
        } completion:^(BOOL finished) {
            if (finished && transitionGeneration == self.menuTransitionGeneration && !self.menuOpen) {
                orb.hidden = YES;
            }
        }];
    }];
    [self wc_scheduleIdleHide];

    if (actionIdentifier) {
        NSUInteger actionGeneration = self.contentRefreshGeneration;
        [self wc_emitSelectionFeedback];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.22 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (actionGeneration != self.contentRefreshGeneration ||
                UIApplication.sharedApplication.applicationState != UIApplicationStateActive) {
                return;
            }
            WCLiquidGlassPerformAction(actionIdentifier);
        });
    }
}

- (void)wc_updateAnchorVisual {
    if (self.menuOpen) {
        [self.anchorOrb setCloseAppearance];
    } else {
        [self.anchorOrb setAnchorAppearance];
    }
}

- (void)wc_anchorTapped:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateEnded) {
        return;
    }
    self.menuOpen ? [self closeMenuSelectingIndex:NSNotFound] : [self openMenu];
}

- (void)wc_anchorPanned:(UIPanGestureRecognizer *)gesture {
    CGPoint location = [gesture locationInView:self];
    if (self.menuOpen) {
        if (gesture.state == UIGestureRecognizerStateBegan) {
            [self wc_beginPressOnOrb:self.anchorOrb towardPoint:location];
        } else if (gesture.state == UIGestureRecognizerStateChanged) {
            [self wc_highlightNearestOrbToPoint:location magnetic:YES];
        } else if (gesture.state == UIGestureRecognizerStateEnded) {
            [self wc_activateOptionAtIndex:self.highlightedIndex];
        } else if (gesture.state == UIGestureRecognizerStateCancelled ||
                   gesture.state == UIGestureRecognizerStateFailed) {
            [self closeMenuSelectingIndex:NSNotFound];
        }
        return;
    }

    if (gesture.state == UIGestureRecognizerStateBegan) {
        [self wc_revealAnchorAnimated:NO];
        self.panStartCenter = self.anchorOrb.center;
        [self wc_beginPressOnOrb:self.anchorOrb towardPoint:location];
    } else if (gesture.state == UIGestureRecognizerStateChanged) {
        CGPoint translation = [gesture translationInView:self];
        self.anchorOrb.center = CGPointMake(self.panStartCenter.x + translation.x,
                                            self.panStartCenter.y + translation.y);
        CGPoint dragDelta = CGPointMake(self.anchorOrb.center.x - self.panStartCenter.x,
                                        self.anchorOrb.center.y - self.panStartCenter.y);
        CGFloat dragDistance = hypot(dragDelta.x, dragDelta.y);
        CGPoint stretchPoint = self.anchorOrb.center;
        if (dragDistance > 2.0) {
            CGFloat stretchDistance = MIN(self.anchorOrb.diameter * 1.7, dragDistance);
            stretchPoint.x += dragDelta.x / dragDistance * stretchDistance;
            stretchPoint.y += dragDelta.y / dragDistance * stretchDistance;
        }
        [self wc_updatePressTowardPoint:stretchPoint];
    } else if (gesture.state == UIGestureRecognizerStateEnded ||
               gesture.state == UIGestureRecognizerStateCancelled) {
        [self wc_endPressAnimated:YES];
        self.anchorOnLeft = self.anchorOrb.center.x < CGRectGetMidX(self.bounds);
        CGFloat yFraction = self.anchorOrb.center.y / MAX(CGRectGetHeight(self.bounds), 1.0);
        [WCLiquidGlassPreferences setAnchorOnLeft:self.anchorOnLeft yFraction:yFraction];
        [UIView animateWithDuration:0.36
                              delay:0
             usingSpringWithDamping:0.72
              initialSpringVelocity:0.7
                            options:UIViewAnimationOptionBeginFromCurrentState
                         animations:^{
            [self wc_layoutAnchorFromPreferences];
        } completion:^(__unused BOOL finished) {
            [self wc_scheduleIdleHide];
        }];
    }
}

- (void)wc_anchorLongPressed:(UILongPressGestureRecognizer *)gesture {
    CGPoint point = [gesture locationInView:self];
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [self openMenu];
        [self wc_beginPressOnOrb:self.anchorOrb towardPoint:point];
    } else if (gesture.state == UIGestureRecognizerStateChanged) {
        [self wc_highlightNearestOrbToPoint:point magnetic:YES];
    } else if (gesture.state == UIGestureRecognizerStateEnded) {
        [self wc_activateOptionAtIndex:self.highlightedIndex];
    } else if (gesture.state == UIGestureRecognizerStateCancelled ||
               gesture.state == UIGestureRecognizerStateFailed) {
        [self closeMenuSelectingIndex:NSNotFound];
    }
}

- (void)wc_optionTapped:(UITapGestureRecognizer *)gesture {
    NSInteger index = [self.optionOrbs indexOfObject:(WCLiquidGlassOrbView *)gesture.view];
    [self wc_activateOptionAtIndex:index];
}

- (void)wc_optionLongPressed:(UILongPressGestureRecognizer *)gesture {
    CGPoint point = [gesture locationInView:self];
    if (gesture.state == UIGestureRecognizerStateBegan) {
        NSInteger index = [self.optionOrbs indexOfObject:(WCLiquidGlassOrbView *)gesture.view];
        [self wc_setHighlightedIndex:index];
        [self wc_beginPressOnOrb:(WCLiquidGlassOrbView *)gesture.view towardPoint:point];
    } else if (gesture.state == UIGestureRecognizerStateChanged) {
        [self wc_highlightNearestOrbToPoint:point magnetic:YES];
    } else if (gesture.state == UIGestureRecognizerStateEnded) {
        [self wc_activateOptionAtIndex:self.highlightedIndex];
    } else if (gesture.state == UIGestureRecognizerStateCancelled ||
               gesture.state == UIGestureRecognizerStateFailed) {
        [self wc_setHighlightedIndex:NSNotFound];
    }
}

- (void)wc_activateOptionAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.optionOrbs.count) {
        [self closeMenuSelectingIndex:NSNotFound];
        return;
    }
    WCLiquidGlassOrbView *orb = self.optionOrbs[index];
    if (![orb.actionIdentifier isEqualToString:WCLiquidGlassActionVoiceInput]) {
        [self closeMenuSelectingIndex:index];
        return;
    }

    UIControl *control = WCLiquidGlassVoiceTranscriptionControl();
    if (!control) {
        [self closeMenuSelectingIndex:NSNotFound];
        WCLiquidGlassShowActionError(@"当前页面没有找到微信原生的语音转述按钮。");
        return;
    }

    BOOL wasActive = self.voiceTranscriptionActive;
    [control sendActionsForControlEvents:UIControlEventTouchUpInside];
    self.voiceTranscriptionActive = !wasActive;
    [orb setToggleActiveAppearance:self.voiceTranscriptionActive];
    [self wc_emitSelectionFeedback];
    [self wc_setHighlightedIndex:NSNotFound];

    if (wasActive) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.16 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self closeMenuSelectingIndex:NSNotFound];
        });
    }
}

- (void)wc_backgroundTapped {
    [self closeMenuSelectingIndex:NSNotFound];
}

- (void)wc_highlightNearestOrbToPoint:(CGPoint)point magnetic:(BOOL)magnetic {
    __block NSInteger nearestIndex = NSNotFound;
    __block CGFloat nearestDistance = CGFLOAT_MAX;
    CGFloat threshold = self.anchorOrb.diameter * (magnetic ? 1.35 : 0.65);
    [self.optionOrbs enumerateObjectsUsingBlock:^(WCLiquidGlassOrbView *orb,
                                                   NSUInteger index,
                                                   BOOL *stop) {
        CGFloat distance = hypot(point.x - orb.center.x, point.y - orb.center.y);
        if (distance < nearestDistance && distance <= threshold) {
            nearestDistance = distance;
            nearestIndex = index;
        }
    }];
    CGFloat anchorDistance = hypot(point.x - self.anchorOrb.center.x,
                                   point.y - self.anchorOrb.center.y);
    if (anchorDistance <= threshold && anchorDistance < nearestDistance) {
        if (self.highlightedIndex != NSNotFound) {
            [self wc_setHighlightedIndex:NSNotFound];
        }
        [self wc_beginPressOnOrb:self.anchorOrb towardPoint:point];
        return;
    }
    if (nearestIndex != NSNotFound) {
        [self wc_setHighlightedIndex:nearestIndex];
        [self wc_beginPressOnOrb:self.optionOrbs[nearestIndex] towardPoint:point];
    } else {
        [self wc_updatePressTowardPoint:point];
    }
}

- (void)wc_setHighlightedIndex:(NSInteger)index {
    if (self.highlightedIndex == index) {
        return;
    }
    NSInteger previousIndex = self.highlightedIndex;
    self.highlightedIndex = index;
    if (previousIndex >= 0 && previousIndex < (NSInteger)self.optionOrbs.count) {
        [self.optionOrbs[previousIndex] setSelectedAppearance:NO animated:YES];
    }
    if (index >= 0 && index < (NSInteger)self.optionOrbs.count) {
        [self.optionOrbs[index] setSelectedAppearance:YES animated:YES];
    }
    if (index == NSNotFound) {
        [self wc_endPressAnimated:YES];
    }
    if (index != NSNotFound) {
        [self wc_emitSelectionFeedback];
    }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
        shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return NO;
}

@end

@interface WCLiquidGlassStaticMenuPreviewView : WCLiquidGlassHostView

- (void)refreshAppearance;

@end


@implementation WCLiquidGlassStaticMenuPreviewView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame observesInputNotifications:NO];
    if (!self) {
        return nil;
    }
    self.userInteractionEnabled = NO;
    self.isAccessibilityElement = NO;
    self.dismissControl.hidden = YES;
    self.anchorOrb.userInteractionEnabled = NO;
    self.anchorOrb.isAccessibilityElement = NO;
    for (WCLiquidGlassOrbView *orb in self.optionOrbs) {
        orb.userInteractionEnabled = NO;
        orb.isAccessibilityElement = NO;
    }
    return self;
}

- (NSArray<NSDictionary<NSString *, id> *> *)wc_currentVisibleItems {
    return @[
        @{@"slot": @"preview.camera", @"action": WCLiquidGlassActionCamera},
        @{@"slot": @"preview.album", @"action": WCLiquidGlassActionAlbum},
        @{@"slot": @"preview.voice", @"action": WCLiquidGlassActionVoiceInput},
        @{@"slot": @"preview.search", @"action": WCLiquidGlassActionSearchRecords},
        @{@"slot": @"preview.doutu", @"action": WCLiquidGlassActionDoutuAssistant}
    ];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self wc_applyPreviewLayout];
}

- (void)wc_applyPreviewLayout {
    if (!self.anchorOrb || CGRectIsEmpty(self.bounds)) {
        return;
    }
    self.anchorOnLeft = YES;
    self.anchorIdleHidden = NO;
    CGFloat diameter = self.anchorOrb.diameter;
    self.anchorOrb.center = CGPointMake(diameter * 0.5 + 12.0,
                                        CGRectGetHeight(self.bounds) * 0.58);
    self.menuOpen = YES;
    [self wc_updateAnchorVisual];
    for (WCLiquidGlassOrbView *orb in self.optionOrbs) {
        orb.hidden = NO;
        orb.alpha = 1.0;
        orb.transform = CGAffineTransformIdentity;
    }
    [self wc_layoutOptionOrbsAnimated:NO];
}

- (void)refreshAppearance {
    [self reload];
    [self wc_applyPreviewLayout];
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    return nil;
}

@end

UIView *WCLiquidGlassCreateStaticMenuPreview(void) {
    return [[WCLiquidGlassStaticMenuPreviewView alloc] initWithFrame:CGRectZero];
}

void WCLiquidGlassRefreshStaticMenuPreview(UIView *preview) {
    if ([preview isKindOfClass:WCLiquidGlassStaticMenuPreviewView.class]) {
        [(WCLiquidGlassStaticMenuPreviewView *)preview refreshAppearance];
    }
}

@interface WCLiquidGlassHostController : UIViewController

@property(nonatomic, strong) WCLiquidGlassHostView *hostView;

@end

@implementation WCLiquidGlassHostController

- (void)loadView {
    self.hostView = [[WCLiquidGlassHostView alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.view = self.hostView;
}

@end

@interface WCLiquidGlassWindow : UIWindow
@end

@implementation WCLiquidGlassWindow

- (BOOL)canBecomeKeyWindow {
    return NO;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    return hitView == self ? nil : hitView;
}

@end

@interface WCLiquidGlassManager ()

@property(nonatomic, strong) WCLiquidGlassWindow *window;
@property(nonatomic, strong) WCLiquidGlassHostController *hostController;
@property(nonatomic, assign) BOOL started;

@end

@implementation WCLiquidGlassManager

+ (instancetype)sharedManager {
    static WCLiquidGlassManager *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[self alloc] init];
    });
    return manager;
}

- (void)start {
    if (self.started) {
        [self reload];
        return;
    }
    self.started = YES;
    [WCLiquidGlassPreferences registerDefaults];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(wc_applicationWillResignActive:)
                                               name:UIApplicationWillResignActiveNotification
                                             object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(wc_applicationBecameActive:)
                                               name:UIApplicationDidBecomeActiveNotification
                                             object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(wc_preferencesChanged:)
                                               name:WCLiquidGlassPreferencesDidChangeNotification
                                             object:nil];
    [self reload];
}

- (void)reload {
    dispatch_async(dispatch_get_main_queue(), ^{
        WCLiquidGlassRefreshDoutuConfiguration();
        [self wc_ensureWindow];
        [self.hostController.hostView reload];
        self.window.hidden = !WCLiquidGlassPreferences.enabled;
    });
}

- (void)wc_ensureWindow {
    UIWindowScene *activeScene = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive &&
            [scene isKindOfClass:UIWindowScene.class]) {
            activeScene = (UIWindowScene *)scene;
            break;
        }
    }
    if (!activeScene) {
        return;
    }

    if (self.window && self.window.windowScene == activeScene) {
        return;
    }
    self.hostController = [[WCLiquidGlassHostController alloc] init];
    self.window = [[WCLiquidGlassWindow alloc] initWithWindowScene:activeScene];
    self.window.frame = activeScene.coordinateSpace.bounds;
    self.window.rootViewController = self.hostController;
    self.window.backgroundColor = UIColor.clearColor;
    self.window.windowLevel = UIWindowLevelAlert + 1.0;
    self.window.hidden = YES;
}

- (void)wc_applicationWillResignActive:(NSNotification *)notification {
    [self.hostController.hostView wc_resetMenuImmediately];
}

- (void)wc_applicationBecameActive:(NSNotification *)notification {
    [self reload];
}

- (void)wc_preferencesChanged:(NSNotification *)notification {
    [self reload];
}

@end
