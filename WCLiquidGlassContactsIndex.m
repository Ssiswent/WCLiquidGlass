#import "WCLiquidGlassContactsIndex.h"

#import <CydiaSubstrate.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "WCLiquidGlassMenu.h"
#import "WCLiquidGlassPreferences.h"

static const void *WCLiquidGlassContactsIndexStateKey = &WCLiquidGlassContactsIndexStateKey;
static void (*WCLiquidGlassOriginalContactsIndexLayoutSubviews)(UIView *, SEL) = NULL;
static BOOL WCLiquidGlassContactsIndexHooksInstalled = NO;
static BOOL WCLiquidGlassContactsIndexHookRetryScheduled = NO;
static NSUInteger WCLiquidGlassContactsIndexHookInstallAttempts = 0;

@interface WCLiquidGlassContactsIndexState : NSObject
@property(nonatomic, strong) UIVisualEffectView *glassView;
@property(nonatomic, strong, nullable) UIColor *originalBackgroundColor;
@property(nonatomic, assign) BOOL capturedOriginalBackgroundColor;
@property(nonatomic, assign) BOOL originalClipsToBounds;
@property(nonatomic, assign) BOOL capturedOriginalClipsToBounds;
@property(nonatomic, assign) NSInteger effectState;
@end

@implementation WCLiquidGlassContactsIndexState

- (instancetype)init {
    self = [super init];
    if (self) {
        _effectState = NSIntegerMin;
    }
    return self;
}

@end

static NSHashTable<UIView *> *WCLiquidGlassVisibleContactsIndexViews(void) {
    static NSHashTable<UIView *> *views;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        views = [NSHashTable weakObjectsHashTable];
    });
    return views;
}

static BOOL WCLiquidGlassContactsIndexClassNameMatches(id object) {
    if (!object) {
        return NO;
    }
    NSString *className = NSStringFromClass([object class]).lowercaseString;
    return [className containsString:@"contactsviewcontroller"] ||
        [className containsString:@"666contacts"];
}

static BOOL WCLiquidGlassContactsIndexBelongsToContacts(UIView *view) {
    for (UIView *ancestor = view; ancestor; ancestor = ancestor.superview) {
        if (WCLiquidGlassContactsIndexClassNameMatches(ancestor)) {
            return YES;
        }
    }
    for (UIResponder *responder = view; responder; responder = responder.nextResponder) {
        if ([responder isKindOfClass:UIViewController.class] &&
            WCLiquidGlassContactsIndexClassNameMatches(responder)) {
            return YES;
        }
    }
    return NO;
}

static void WCLiquidGlassContactsIndexRestore(UIView *view,
                                                WCLiquidGlassContactsIndexState *state) {
    if (!state) {
        return;
    }
    if (state.capturedOriginalBackgroundColor) {
        view.backgroundColor = state.originalBackgroundColor;
    }
    if (state.capturedOriginalClipsToBounds) {
        view.clipsToBounds = state.originalClipsToBounds;
    }
    [state.glassView removeFromSuperview];
    state.capturedOriginalBackgroundColor = NO;
    state.originalBackgroundColor = nil;
    state.capturedOriginalClipsToBounds = NO;
    state.effectState = NSIntegerMin;
}

static CGRect WCLiquidGlassContactsIndexGlassFrame(UIView *view) {
    CGFloat fullWidth = MAX(0.0,
                            MAX(28.0, CGRectGetWidth(view.bounds) + 8.0) * 2.0 - 12.0);
    CGFloat visibleWidth = fullWidth * 0.5;
    return CGRectIntegral(CGRectMake(CGRectGetWidth(view.bounds) - visibleWidth,
                                     100.0,
                                     fullWidth,
                                     MAX(0.0, CGRectGetHeight(view.bounds) - 200.0)));
}

static void WCLiquidGlassContactsIndexUpdate(UIView *view) {
    WCLiquidGlassContactsIndexState *state =
        objc_getAssociatedObject(view, WCLiquidGlassContactsIndexStateKey);
    if (!WCLiquidGlassPreferences.contactsIndexGlassEnabled ||
        !WCLiquidGlassContactsIndexBelongsToContacts(view)) {
        WCLiquidGlassContactsIndexRestore(view, state);
        return;
    }

    if (!state) {
        state = [[WCLiquidGlassContactsIndexState alloc] init];
        objc_setAssociatedObject(view,
                                 WCLiquidGlassContactsIndexStateKey,
                                 state,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!state.capturedOriginalBackgroundColor) {
        state.capturedOriginalBackgroundColor = YES;
        state.originalBackgroundColor = view.backgroundColor;
    }
    if (!state.capturedOriginalClipsToBounds) {
        state.capturedOriginalClipsToBounds = YES;
        state.originalClipsToBounds = view.clipsToBounds;
    }
    if (!state.glassView) {
        state.glassView = [[UIVisualEffectView alloc] initWithEffect:nil];
        state.glassView.userInteractionEnabled = NO;
        state.glassView.clipsToBounds = YES;
        state.glassView.layer.cornerCurve = kCACornerCurveContinuous;
    }
    if (state.glassView.superview != view) {
        [state.glassView removeFromSuperview];
        [view insertSubview:state.glassView atIndex:0];
    }

    view.backgroundColor = UIColor.clearColor;
    view.clipsToBounds = NO;
    CGRect frame = WCLiquidGlassContactsIndexGlassFrame(view);
    if (!CGRectEqualToRect(state.glassView.frame, frame)) {
        state.glassView.frame = frame;
    }
    CGFloat cornerRadius = MIN(CGRectGetWidth(frame), CGRectGetHeight(frame)) * 0.5;
    if (state.glassView.layer.cornerRadius != cornerRadius) {
        state.glassView.layer.cornerRadius = cornerRadius;
    }

    NSInteger effectState = WCLiquidGlassPreferences.glassAppearance * 10 +
        view.traitCollection.userInterfaceStyle;
    if (state.effectState != effectState) {
        state.glassView.effect = WCLiquidGlassGlassEffectForAppearance(
            WCLiquidGlassPreferences.glassAppearance);
        state.effectState = effectState;
    }
    state.glassView.hidden = CGRectIsEmpty(frame);
}

static void WCLiquidGlassContactsIndexLayoutSubviews(UIView *self, SEL selector) {
    if (WCLiquidGlassOriginalContactsIndexLayoutSubviews) {
        WCLiquidGlassOriginalContactsIndexLayoutSubviews(self, selector);
    }
    [WCLiquidGlassVisibleContactsIndexViews() addObject:self];
    WCLiquidGlassContactsIndexUpdate(self);
}

static void WCLiquidGlassRefreshContactsIndexGlass(void) {
    for (UIView *view in WCLiquidGlassVisibleContactsIndexViews().allObjects) {
        WCLiquidGlassContactsIndexUpdate(view);
    }
}

void WCLiquidGlassInstallContactsIndexHooks(void) {
    if (WCLiquidGlassContactsIndexHooksInstalled) {
        return;
    }
    Class indexViewClass = NSClassFromString(@"MMTableViewIndexView");
    Method layoutMethod = class_getInstanceMethod(indexViewClass, @selector(layoutSubviews));
    if (!indexViewClass || !layoutMethod) {
        if (!WCLiquidGlassContactsIndexHookRetryScheduled &&
            WCLiquidGlassContactsIndexHookInstallAttempts < 10) {
            WCLiquidGlassContactsIndexHookRetryScheduled = YES;
            WCLiquidGlassContactsIndexHookInstallAttempts += 1;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                WCLiquidGlassContactsIndexHookRetryScheduled = NO;
                WCLiquidGlassInstallContactsIndexHooks();
            });
        }
        return;
    }
    MSHookMessageEx(indexViewClass,
                    @selector(layoutSubviews),
                    (IMP)&WCLiquidGlassContactsIndexLayoutSubviews,
                    (IMP *)&WCLiquidGlassOriginalContactsIndexLayoutSubviews);
    WCLiquidGlassContactsIndexHooksInstalled =
        WCLiquidGlassOriginalContactsIndexLayoutSubviews != NULL;
    if (WCLiquidGlassContactsIndexHooksInstalled) {
        [NSNotificationCenter.defaultCenter addObserverForName:WCLiquidGlassPreferencesDidChangeNotification
                                                        object:nil
                                                         queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(__unused NSNotification *notification) {
            WCLiquidGlassRefreshContactsIndexGlass();
        }];
    }
}
