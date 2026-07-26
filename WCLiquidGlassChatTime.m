#import "WCLiquidGlassChatTime.h"

#import <CydiaSubstrate.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "WCLiquidGlassMenu.h"
#import "WCLiquidGlassPreferences.h"

static const void *WCLiquidGlassChatTimeGlassKey = &WCLiquidGlassChatTimeGlassKey;
static const void *WCLiquidGlassChatTimeMetricsKey = &WCLiquidGlassChatTimeMetricsKey;
static const void *WCLiquidGlassChatTimeEffectStateKey = &WCLiquidGlassChatTimeEffectStateKey;
static void (*WCLiquidGlassOriginalChatTimeLayoutSubviews)(UIView *, SEL) = NULL;
static BOOL WCLiquidGlassChatTimeHooksInstalled = NO;
static BOOL WCLiquidGlassChatTimeHookRetryScheduled = NO;
static NSUInteger WCLiquidGlassChatTimeHookInstallAttempts = 0;
static Class WCLiquidGlassChatTimeCellClass = Nil;
static Ivar WCLiquidGlassChatTimeLabelIvar = NULL;

@interface WCLiquidGlassChatTimeMetrics : NSObject

@property(nonatomic, copy, nullable) NSAttributedString *attributedText;
@property(nonatomic, copy, nullable) NSString *text;
@property(nonatomic, strong, nullable) UIFont *font;
@property(nonatomic, assign) CGFloat width;
@property(nonatomic, assign) CGFloat height;

@end

@implementation WCLiquidGlassChatTimeMetrics
@end

static NSHashTable<UIView *> *WCLiquidGlassVisibleChatTimeCells(void) {
    static NSHashTable<UIView *> *cells;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cells = [NSHashTable weakObjectsHashTable];
    });
    return cells;
}

static UILabel *WCLiquidGlassTimeLabelForCell(UIView *cell) {
    if (!WCLiquidGlassChatTimeLabelIvar) {
        WCLiquidGlassChatTimeLabelIvar = class_getInstanceVariable(cell.class, "m_timeLabel");
    }
    id timeLabel = WCLiquidGlassChatTimeLabelIvar ? object_getIvar(cell, WCLiquidGlassChatTimeLabelIvar) : nil;
    return [timeLabel isKindOfClass:UILabel.class] ? timeLabel : nil;
}

static WCLiquidGlassChatTimeMetrics *WCLiquidGlassTimeLabelContentMetrics(UILabel *label) {
    NSAttributedString *attributedText = label.attributedText;
    NSString *text = label.text;
    UIFont *font = label.font;
    WCLiquidGlassChatTimeMetrics *metrics = objc_getAssociatedObject(label, WCLiquidGlassChatTimeMetricsKey);
    if (metrics &&
        ((metrics.attributedText == attributedText) || [metrics.attributedText isEqual:attributedText]) &&
        ((metrics.text == text) || [metrics.text isEqualToString:text]) &&
        [metrics.font isEqual:font]) {
        return metrics;
    }

    CGFloat width = 0.0;
    CGFloat height = 0.0;
    if (attributedText.length > 0) {
        CGRect bounds = [attributedText boundingRectWithSize:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)
                                                     options:NSStringDrawingUsesLineFragmentOrigin |
                                                             NSStringDrawingUsesFontLeading
                                                     context:nil];
        width = ceil(CGRectGetWidth(bounds));
        height = ceil(CGRectGetHeight(bounds));
    } else if (text.length > 0) {
        NSDictionary<NSAttributedStringKey, id> *attributes = @{NSFontAttributeName: font ?: [UIFont systemFontOfSize:13.0]};
        CGRect bounds = [text boundingRectWithSize:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)
                                           options:NSStringDrawingUsesLineFragmentOrigin |
                                                   NSStringDrawingUsesFontLeading
                                        attributes:attributes
                                           context:nil];
        width = ceil(CGRectGetWidth(bounds));
        height = ceil(CGRectGetHeight(bounds));
    }

    metrics = [[WCLiquidGlassChatTimeMetrics alloc] init];
    metrics.attributedText = attributedText;
    metrics.text = text;
    metrics.font = font;
    metrics.width = width;
    metrics.height = height;
    objc_setAssociatedObject(label,
                             WCLiquidGlassChatTimeMetricsKey,
                             metrics,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return metrics;
}

static void WCLiquidGlassUpdateChatTimeGlass(UIView *cell) {
    UILabel *timeLabel = WCLiquidGlassTimeLabelForCell(cell);
    UIVisualEffectView *glassView = objc_getAssociatedObject(cell, WCLiquidGlassChatTimeGlassKey);
    if (!WCLiquidGlassPreferences.chatTimeGlassEnabled ||
        !timeLabel ||
        timeLabel.hidden ||
        timeLabel.alpha <= 0.01) {
        glassView.hidden = YES;
        return;
    }

    WCLiquidGlassChatTimeMetrics *contentMetrics = WCLiquidGlassTimeLabelContentMetrics(timeLabel);
    CGFloat contentWidth = contentMetrics.width;
    if (contentWidth <= 0.0) {
        glassView.hidden = YES;
        return;
    }

    UIView *hostView = timeLabel.superview;
    if (!hostView) {
        glassView.hidden = YES;
        return;
    }
    if (!glassView) {
        glassView = [[UIVisualEffectView alloc] initWithEffect:WCLiquidGlassCurrentGlassEffect()];
        glassView.userInteractionEnabled = NO;
        glassView.clipsToBounds = YES;
        glassView.layer.cornerCurve = kCACornerCurveContinuous;
        WCLiquidGlassGlassAppearance appearance = WCLiquidGlassPreferences.glassAppearance;
        NSInteger effectState = appearance * 10 + timeLabel.traitCollection.userInterfaceStyle;
        objc_setAssociatedObject(glassView,
                                 WCLiquidGlassChatTimeEffectStateKey,
                                 @(effectState),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(cell,
                                 WCLiquidGlassChatTimeGlassKey,
                                 glassView,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (glassView.superview != hostView) {
        [glassView removeFromSuperview];
        [hostView insertSubview:glassView belowSubview:timeLabel];
    }

    CGFloat horizontalPadding = 10.0;
    CGFloat verticalPadding = 6.0;
    CGFloat maximumWidth = MAX(0.0, CGRectGetWidth(hostView.bounds) - 20.0);
    CGFloat width = MIN(contentWidth + horizontalPadding * 2.0, maximumWidth);
    CGFloat height = MAX(20.0, ceil(contentMetrics.height + verticalPadding * 2.0));
    CGRect frame = CGRectIntegral(CGRectMake(CGRectGetMidX(timeLabel.frame) - width * 0.5,
                                             CGRectGetMidY(timeLabel.frame) - height * 0.5,
                                             width,
                                             height));
    if (!CGRectEqualToRect(glassView.frame, frame)) {
        glassView.frame = frame;
    }
    CGFloat cornerRadius = height * 0.5;
    if (glassView.layer.cornerRadius != cornerRadius) {
        glassView.layer.cornerRadius = cornerRadius;
    }
    WCLiquidGlassGlassAppearance appearance = WCLiquidGlassPreferences.glassAppearance;
    NSInteger effectState = appearance * 10 + timeLabel.traitCollection.userInterfaceStyle;
    if ([objc_getAssociatedObject(glassView, WCLiquidGlassChatTimeEffectStateKey) integerValue] != effectState) {
        glassView.effect = WCLiquidGlassCurrentGlassEffect();
        objc_setAssociatedObject(glassView,
                                 WCLiquidGlassChatTimeEffectStateKey,
                                 @(effectState),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    glassView.hidden = NO;
}

static void WCLiquidGlassChatTimeLayoutSubviews(UIView *self, SEL selector) {
    if (WCLiquidGlassOriginalChatTimeLayoutSubviews) {
        WCLiquidGlassOriginalChatTimeLayoutSubviews(self, selector);
    }
    [WCLiquidGlassVisibleChatTimeCells() addObject:self];
    WCLiquidGlassUpdateChatTimeGlass(self);
}

static void WCLiquidGlassRefreshChatTimeGlassInView(UIView *view, NSUInteger depth) {
    if (!view || depth > 32) {
        return;
    }
    if (WCLiquidGlassChatTimeCellClass && [view isKindOfClass:WCLiquidGlassChatTimeCellClass]) {
        [WCLiquidGlassVisibleChatTimeCells() addObject:view];
        WCLiquidGlassUpdateChatTimeGlass(view);
    }
    for (UIView *subview in view.subviews) {
        WCLiquidGlassRefreshChatTimeGlassInView(subview, depth + 1);
    }
}

static void WCLiquidGlassRefreshRegisteredChatTimeGlass(void) {
    for (UIView *cell in WCLiquidGlassVisibleChatTimeCells().allObjects) {
        if (cell.window) {
            WCLiquidGlassUpdateChatTimeGlass(cell);
        }
    }
}

static void WCLiquidGlassRefreshVisibleChatTimeGlass(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) {
            continue;
        }
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            WCLiquidGlassRefreshChatTimeGlassInView(window, 0);
        }
    }
}

void WCLiquidGlassInstallChatTimeGlassHooks(void) {
    if (WCLiquidGlassChatTimeHooksInstalled) {
        return;
    }
    WCLiquidGlassChatTimeCellClass = NSClassFromString(@"ChatTimeCellView");
    Method layoutMethod = class_getInstanceMethod(WCLiquidGlassChatTimeCellClass, @selector(layoutSubviews));
    if (!WCLiquidGlassChatTimeCellClass || !layoutMethod) {
        if (!WCLiquidGlassChatTimeHookRetryScheduled &&
            WCLiquidGlassChatTimeHookInstallAttempts < 10) {
            WCLiquidGlassChatTimeHookRetryScheduled = YES;
            WCLiquidGlassChatTimeHookInstallAttempts += 1;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                WCLiquidGlassChatTimeHookRetryScheduled = NO;
                WCLiquidGlassInstallChatTimeGlassHooks();
            });
        }
        return;
    }
    WCLiquidGlassChatTimeLabelIvar = class_getInstanceVariable(WCLiquidGlassChatTimeCellClass, "m_timeLabel");
    MSHookMessageEx(WCLiquidGlassChatTimeCellClass,
                    @selector(layoutSubviews),
                    (IMP)&WCLiquidGlassChatTimeLayoutSubviews,
                    (IMP *)&WCLiquidGlassOriginalChatTimeLayoutSubviews);
    WCLiquidGlassChatTimeHooksInstalled = WCLiquidGlassOriginalChatTimeLayoutSubviews != NULL;
    if (WCLiquidGlassChatTimeHooksInstalled) {
        [NSNotificationCenter.defaultCenter addObserverForName:WCLiquidGlassPreferencesDidChangeNotification
                                                          object:nil
                                                      queue:NSOperationQueue.mainQueue
                                                      usingBlock:^(__unused NSNotification *notification) {
            WCLiquidGlassRefreshRegisteredChatTimeGlass();
        }];
        WCLiquidGlassRefreshVisibleChatTimeGlass();
    }
}
