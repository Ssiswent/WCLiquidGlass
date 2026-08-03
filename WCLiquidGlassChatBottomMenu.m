#import "WCLiquidGlassChatBottomMenu.h"

#import <CydiaSubstrate.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "WCLiquidGlassCrashLogger.h"
#import "WCLiquidGlassMenu.h"
#import "WCLiquidGlassPreferences.h"

/*
 * ThemePro's attachment-material path is a layout hook, not a replacement
 * for WeChat's attachment controller.  Keep the same boundary here: the
 * native panel still owns its buttons, actions, sizing and presentation; we
 * only replace the panel's covering background layer with one glass view.
 */

static const void *WCLiquidGlassChatBottomMenuStateKey = &WCLiquidGlassChatBottomMenuStateKey;
static const void *WCLiquidGlassChatBottomMenuProtectEffectKey = &WCLiquidGlassChatBottomMenuProtectEffectKey;
static const void *WCLiquidGlassChatBottomMenuEffectRepairScheduledKey = &WCLiquidGlassChatBottomMenuEffectRepairScheduledKey;
static void (*WCLiquidGlassOriginalInputToolContainerLayoutSubviews)(UIView *, SEL) = NULL;
static void (*WCLiquidGlassOriginalSelectAttachmentLayoutSubviews)(UIView *, SEL) = NULL;
static void (*WCLiquidGlassOriginalInputToolViewBarLayoutSubviews)(UIView *, SEL) = NULL;
static void (*WCLiquidGlassOriginalMMInputToolViewLayoutSubviews)(UIView *, SEL) = NULL;
static BOOL WCLiquidGlassInputToolContainerHookInstalled = NO;
static BOOL WCLiquidGlassSelectAttachmentHookInstalled = NO;
static BOOL WCLiquidGlassInputToolViewBarHookInstalled = NO;
static BOOL WCLiquidGlassMMInputToolViewHookInstalled = NO;
static BOOL WCLiquidGlassChatBottomMenuObserverInstalled = NO;
static BOOL WCLiquidGlassChatBottomMenuHookRetryScheduled = NO;
static NSUInteger WCLiquidGlassChatBottomMenuHookInstallAttempts = 0;
static CFTimeInterval WCLiquidGlassChatBottomMenuLastRescanTime = 0.0;
static BOOL WCLiquidGlassChatBottomMenuRescanScheduled = NO;

@interface WCLiquidGlassChatBottomMenuBackgroundState : NSObject

@property(nonatomic, weak) UIView *view;
@property(nonatomic, strong, nullable) UIColor *backgroundColor;
@property(nonatomic, strong, nullable) UIImage *image;
@property(nonatomic, strong, nullable) UIVisualEffect *effect;
@property(nonatomic, strong, nullable) UIColor *layerBackgroundColor;
@property(nonatomic, assign) BOOL capturesLayerBackgroundColor;
@property(nonatomic, strong, nullable) UIColor *effectContentBackgroundColor;
@property(nonatomic, assign) BOOL capturesEffectContentBackgroundColor;
@property(nonatomic, assign) BOOL capturesImage;
@property(nonatomic, assign) BOOL capturesEffect;
@property(nonatomic, assign) BOOL capturesHidden;
@property(nonatomic, assign) BOOL hidden;

@end

@implementation WCLiquidGlassChatBottomMenuBackgroundState
@end

@interface WCLiquidGlassChatBottomMenuState : NSObject

@property(nonatomic, strong) UIVisualEffectView *glassView;
@property(nonatomic, strong) NSMutableArray<WCLiquidGlassChatBottomMenuBackgroundState *> *nativeBackgrounds;
@property(nonatomic, strong, nullable) UIColor *originalBackgroundColor;
@property(nonatomic, assign) BOOL capturedOriginalBackgroundColor;
@property(nonatomic, assign) NSInteger effectState;
@property(nonatomic, assign) BOOL createdEffectPresent;
@property(nonatomic, assign) BOOL effectRecoveryAttempted;
@property(nonatomic, assign) BOOL backgroundPrepared;
@property(nonatomic, assign) NSUInteger lastNativeSubviewCount;
@property(nonatomic, assign) CGRect lastViewBounds;
@property(nonatomic, weak) UIView *lastRenderHost;
@property(nonatomic, assign) BOOL lastUseSiblingRenderHost;
@property(nonatomic, weak) UIView *attachmentBar;
@property(nonatomic, assign) BOOL attachmentBarSearchCompleted;
@property(nonatomic, assign) BOOL diagnosticCandidateRecorded;
@property(nonatomic, assign) BOOL diagnosticMaterialRecorded;

@end

/*
 * WCGlass clears UIVisualEffectView.effect after an attachment panel enters its
 * hierarchy.  A private subclass gives this one replacement view its own
 * setEffect: dispatch slot, so WCGlass's superclass hook cannot turn the
 * material back into a nil effect.  The guard is scoped to this view only and
 * does not alter WeChat's or WCGlass's other effect views.
 */
@interface WCLiquidGlassChatBottomMenuEffectView : UIVisualEffectView
@end

@implementation WCLiquidGlassChatBottomMenuEffectView

- (void)setEffect:(UIVisualEffect *)effect {
    if (!effect &&
        [objc_getAssociatedObject(self, WCLiquidGlassChatBottomMenuProtectEffectKey) boolValue]) {
        return;
    }
    [super setEffect:effect];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (![objc_getAssociatedObject(self, WCLiquidGlassChatBottomMenuProtectEffectKey) boolValue] ||
        objc_getAssociatedObject(self, WCLiquidGlassChatBottomMenuEffectRepairScheduledKey)) {
        return;
    }
    objc_setAssociatedObject(self,
                             WCLiquidGlassChatBottomMenuEffectRepairScheduledKey,
                             @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak WCLiquidGlassChatBottomMenuEffectView *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        WCLiquidGlassChatBottomMenuEffectView *strongSelf = weakSelf;
        if (strongSelf && strongSelf.window && !strongSelf.effect) {
            [strongSelf setEffect:WCLiquidGlassCurrentGlassEffect()];
        }
    });
}

@end

@implementation WCLiquidGlassChatBottomMenuState

- (instancetype)init {
    self = [super init];
    if (self) {
        _nativeBackgrounds = [NSMutableArray array];
        _effectState = NSIntegerMin;
    }
    return self;
}

@end

static NSHashTable<UIView *> *WCLiquidGlassVisibleChatBottomMenuViews(void) {
    static NSHashTable<UIView *> *views;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        views = [NSHashTable weakObjectsHashTable];
    });
    return views;
}

static BOOL WCLiquidGlassChatBottomMenuClassNameContains(id object, NSString *token) {
    if (!object || token.length == 0) {
        return NO;
    }
    return [NSStringFromClass([object class]).lowercaseString containsString:token.lowercaseString];
}

static BOOL WCLiquidGlassChatBottomMenuHasSelectAncestor(UIView *view) {
    UIView *ancestor = view.superview;
    while (ancestor) {
        if (WCLiquidGlassChatBottomMenuClassNameContains(ancestor, @"selectattachmentview")) {
            return YES;
        }
        ancestor = ancestor.superview;
    }
    return NO;
}

static UIView *WCLiquidGlassChatBottomMenuFindAttachmentBar(UIView *view,
                                                             NSUInteger depth) {
    if (!view || depth > 10 || view.hidden || view.alpha <= 0.01 ||
        CGRectIsEmpty(view.bounds)) {
        return nil;
    }
    if (WCLiquidGlassChatBottomMenuClassNameContains(view, @"inputtoolviewbar")) {
        return view;
    }
    for (UIView *subview in view.subviews) {
        UIView *bar = WCLiquidGlassChatBottomMenuFindAttachmentBar(subview, depth + 1);
        if (bar) {
            return bar;
        }
    }
    return nil;
}

static BOOL WCLiquidGlassChatBottomMenuIsCandidate(UIView *view) {
    return WCLiquidGlassChatBottomMenuClassNameContains(view, @"inputtoolcontainerview") ||
        WCLiquidGlassChatBottomMenuClassNameContains(view, @"selectattachmentview") ||
        WCLiquidGlassChatBottomMenuClassNameContains(view, @"inputtoolviewbar") ||
        WCLiquidGlassChatBottomMenuClassNameContains(view, @"mminputtoolview");
}

static BOOL WCLiquidGlassChatBottomMenuHasVisibleSelectDescendant(UIView *view,
                                                                  NSUInteger depth) {
    if (!view || depth > 8) {
        return NO;
    }
    for (UIView *subview in view.subviews) {
        if (WCLiquidGlassChatBottomMenuClassNameContains(subview, @"selectattachmentview") &&
            !subview.hidden && subview.alpha > 0.01 && !CGRectIsEmpty(subview.bounds)) {
            return YES;
        }
        if (WCLiquidGlassChatBottomMenuHasVisibleSelectDescendant(subview, depth + 1)) {
            return YES;
        }
    }
    return NO;
}

static BOOL WCLiquidGlassChatBottomMenuHasVisibleAttachmentDescendant(UIView *view,
                                                                       NSUInteger depth) {
    if (!view || depth > 10) {
        return NO;
    }
    for (UIView *subview in view.subviews) {
        if ((WCLiquidGlassChatBottomMenuClassNameContains(subview, @"inputtoolcontainerview") ||
             WCLiquidGlassChatBottomMenuClassNameContains(subview, @"selectattachmentview") ||
             WCLiquidGlassChatBottomMenuClassNameContains(subview, @"inputtoolviewbar")) &&
            !subview.hidden && subview.alpha > 0.01 && !CGRectIsEmpty(subview.bounds)) {
            return YES;
        }
        if (WCLiquidGlassChatBottomMenuHasVisibleAttachmentDescendant(subview, depth + 1)) {
            return YES;
        }
    }
    return NO;
}

static BOOL WCLiquidGlassChatBottomMenuIsLikelyVisibleInputToolPanel(UIView *view) {
    if (!view || view.hidden || view.alpha <= 0.01 || CGRectIsEmpty(view.bounds)) {
        return NO;
    }
    // Some WeChat builds put the attachment buttons directly in MMInputToolView
    // and do not expose either of the two panel classes above.  The attachment
    // panel is substantially taller than the normal input toolbar and contains
    // multiple controls; use that shape only as a fallback host.
    if (!WCLiquidGlassChatBottomMenuClassNameContains(view, @"mminputtoolview") ||
        CGRectGetHeight(view.bounds) < 120.0) {
        return NO;
    }
    // On recent WeChat builds the attachment buttons are nested in private
    // stack/collection views rather than being direct UIControl children.
    // Checking only direct controls therefore rejects the real attachment
    // panel and leaves its native opaque background untouched.
    NSUInteger visibleSubviews = 0;
    for (UIView *subview in view.subviews) {
        if (!subview.hidden && subview.alpha > 0.01 && !CGRectIsEmpty(subview.bounds)) {
            visibleSubviews += 1;
        }
    }
    return visibleSubviews >= 2;
}

static BOOL WCLiquidGlassChatBottomMenuShouldUseHost(UIView *view) {
    if (!WCLiquidGlassChatBottomMenuIsCandidate(view)) {
        return NO;
    }
    if (WCLiquidGlassChatBottomMenuClassNameContains(view, @"mminputtoolview")) {
        if (!WCLiquidGlassChatBottomMenuIsLikelyVisibleInputToolPanel(view)) {
            return NO;
        }
        // A nested attachment host receives the single material layer.  The
        // outer input toolbar is deliberately never used as a render host;
        // this also prevents a full-screen layout pass during page swipes.
        return NO;
    }
    if (WCLiquidGlassChatBottomMenuClassNameContains(view, @"inputtoolviewbar") &&
        WCLiquidGlassChatBottomMenuHasSelectAncestor(view)) {
        // The enclosing SelectAttachmentView owns the single material layer.
        // A second bar-sized effect would stack the material and dim buttons.
        return NO;
    }
    if (WCLiquidGlassChatBottomMenuClassNameContains(view, @"inputtoolcontainerview") &&
        WCLiquidGlassChatBottomMenuHasVisibleSelectDescendant(view, 0)) {
        // SelectAttachmentView owns the visible panel when it is present.  A
        // single glass layer avoids stacking two translucent materials.
        return NO;
    }
    return YES;
}

static Ivar WCLiquidGlassChatBottomMenuFindIvar(Class viewClass, const char *name) {
    for (Class currentClass = viewClass; currentClass; currentClass = class_getSuperclass(currentClass)) {
        Ivar ivar = class_getInstanceVariable(currentClass, name);
        if (ivar) {
            return ivar;
        }
    }
    return NULL;
}

static UIView *WCLiquidGlassChatBottomMenuObjectIvar(UIView *view, const char *name) {
    Ivar ivar = WCLiquidGlassChatBottomMenuFindIvar(view.class, name);
    if (!ivar || ivar_getTypeEncoding(ivar)[0] != '@') {
        return nil;
    }
    id object = object_getIvar(view, ivar);
    return [object isKindOfClass:UIView.class] ? object : nil;
}

static UIView *WCLiquidGlassChatBottomMenuViewProperty(UIView *view, SEL selector) {
    if (![view respondsToSelector:selector]) {
        return nil;
    }
    id object = ((id (*)(id, SEL))objc_msgSend)(view, selector);
    return [object isKindOfClass:UIView.class] ? object : nil;
}

static BOOL WCLiquidGlassChatBottomMenuViewCoversHost(UIView *candidate, UIView *host) {
    if (!candidate || candidate == host || !candidate.superview ||
        CGRectIsEmpty(candidate.bounds) || CGRectIsEmpty(host.bounds)) {
        return NO;
    }
    CGRect frameInHost = [candidate convertRect:candidate.bounds toView:host];
    CGRect intersection = CGRectIntersection(frameInHost, host.bounds);
    if (CGRectIsNull(intersection) || CGRectIsEmpty(intersection)) {
        return NO;
    }
    CGFloat hostArea = CGRectGetWidth(host.bounds) * CGRectGetHeight(host.bounds);
    CGFloat coveredArea = CGRectGetWidth(intersection) * CGRectGetHeight(intersection);
    return hostArea > 0.0 && coveredArea / hostArea >= 0.80;
}

static void WCLiquidGlassChatBottomMenuAppendBackgroundView(NSMutableArray<UIView *> *views,
                                                             UIView *candidate,
                                                             UIView *host) {
    if (!candidate || candidate == host || !WCLiquidGlassChatBottomMenuViewCoversHost(candidate, host) ||
        [views containsObject:candidate]) {
        return;
    }
    [views addObject:candidate];
}

static BOOL WCLiquidGlassChatBottomMenuLooksLikeBackgroundView(UIView *view) {
    return [view isKindOfClass:UIVisualEffectView.class] ||
        [view isKindOfClass:UIImageView.class] ||
        WCLiquidGlassChatBottomMenuClassNameContains(view, @"background") ||
        WCLiquidGlassChatBottomMenuClassNameContains(view, @"effect") ||
        WCLiquidGlassChatBottomMenuClassNameContains(view, @"backdrop") ||
        WCLiquidGlassChatBottomMenuClassNameContains(view, @"material") ||
        WCLiquidGlassChatBottomMenuClassNameContains(view, @"visual") ||
        WCLiquidGlassChatBottomMenuClassNameContains(view, @"inputtoolviewbar");
}

static BOOL WCLiquidGlassChatBottomMenuHasOpaqueSurface(UIView *view) {
    if (!view || view.hidden || view.alpha <= 0.01) {
        return NO;
    }
    UIColor *backgroundColor = view.backgroundColor;
    if (backgroundColor && CGColorGetAlpha(backgroundColor.CGColor) > 0.01) {
        return YES;
    }
    CGColorRef layerColor = view.layer.backgroundColor;
    return layerColor && CGColorGetAlpha(layerColor) > 0.01;
}

static BOOL WCLiquidGlassChatBottomMenuLooksLikeGenericContainer(UIView *view) {
    if (!view || [view isKindOfClass:UIControl.class] ||
        [view isKindOfClass:UILabel.class] || [view isKindOfClass:UIImageView.class] ||
        [view isKindOfClass:UIVisualEffectView.class]) {
        return NO;
    }
    NSString *className = NSStringFromClass(view.class).lowercaseString;
    return ![className containsString:@"button"] &&
        ![className containsString:@"label"] &&
        ![className containsString:@"image"];
}

static void WCLiquidGlassChatBottomMenuCollectCoveringViews(UIView *container,
                                                             UIView *host,
                                                             UIView *glassView,
                                                             NSUInteger depth,
                                                             NSMutableArray<UIView *> *views) {
    if (!container || depth > 8) {
        return;
    }
    for (UIView *subview in container.subviews) {
        if (subview == glassView || subview.hidden || subview.alpha <= 0.01) {
            continue;
        }
        BOOL isKnownBackground = WCLiquidGlassChatBottomMenuLooksLikeBackgroundView(subview);
        BOOL isOpaqueContainer = WCLiquidGlassChatBottomMenuLooksLikeGenericContainer(subview) &&
            WCLiquidGlassChatBottomMenuHasOpaqueSurface(subview);
        if ((isKnownBackground || isOpaqueContainer) &&
            WCLiquidGlassChatBottomMenuViewCoversHost(subview, host)) {
            WCLiquidGlassChatBottomMenuAppendBackgroundView(views, subview, host);
        }
        WCLiquidGlassChatBottomMenuCollectCoveringViews(subview,
                                                        host,
                                                        glassView,
                                                        depth + 1,
                                                        views);
    }
}

static NSArray<UIView *> *WCLiquidGlassChatBottomMenuNativeBackgroundViews(
    UIView *host,
    UIView *glassView) {
    NSMutableArray<UIView *> *views = [NSMutableArray array];
    const char *ivarNames[] = {
        "m_backgroundView",
        "_backgroundView",
        "backgroundView",
        "m_bgImageView",
        "_bgImageView",
        "effectSubview",
        "_effectSubview",
        "topBackgroundView",
        "_topBackgroundView"
    };
    for (NSUInteger index = 0; index < sizeof(ivarNames) / sizeof(ivarNames[0]); index += 1) {
        UIView *candidate = WCLiquidGlassChatBottomMenuObjectIvar(host, ivarNames[index]);
        if (candidate != glassView) {
            WCLiquidGlassChatBottomMenuAppendBackgroundView(views, candidate, host);
        }
    }

    SEL propertySelectors[] = {
        NSSelectorFromString(@"backgroundView"),
        NSSelectorFromString(@"effectSubview"),
        NSSelectorFromString(@"topBackgroundView")
    };
    for (NSUInteger index = 0; index < sizeof(propertySelectors) / sizeof(propertySelectors[0]); index += 1) {
        UIView *candidate = WCLiquidGlassChatBottomMenuViewProperty(host, propertySelectors[index]);
        if (candidate != glassView) {
            WCLiquidGlassChatBottomMenuAppendBackgroundView(views, candidate, host);
        }
    }

    // Current WeChat builds keep the native attachment surface in private
    // tagged image views.  ThemePro targets these exact slots rather than
    // relying only on an ivar or a class name.
    const NSInteger backgroundTags[] = {0x22b8, 0x270f};
    for (NSUInteger index = 0; index < sizeof(backgroundTags) / sizeof(backgroundTags[0]); index += 1) {
        UIView *candidate = [host viewWithTag:backgroundTags[index]];
        if (candidate != glassView) {
            WCLiquidGlassChatBottomMenuAppendBackgroundView(views, candidate, host);
        }
    }

    WCLiquidGlassChatBottomMenuCollectCoveringViews(host, host, glassView, 0, views);
    return views.copy;
}

static WCLiquidGlassChatBottomMenuBackgroundState *WCLiquidGlassChatBottomMenuStateForBackground(
    WCLiquidGlassChatBottomMenuState *state,
    UIView *view) {
    for (WCLiquidGlassChatBottomMenuBackgroundState *backgroundState in state.nativeBackgrounds) {
        if (backgroundState.view == view) {
            return backgroundState;
        }
    }
    WCLiquidGlassChatBottomMenuBackgroundState *backgroundState =
        [[WCLiquidGlassChatBottomMenuBackgroundState alloc] init];
    backgroundState.view = view;
    backgroundState.backgroundColor = view.backgroundColor;
    CGColorRef layerColor = view.layer.backgroundColor;
    if (layerColor) {
        backgroundState.capturesLayerBackgroundColor = YES;
        backgroundState.layerBackgroundColor = [UIColor colorWithCGColor:layerColor];
    }
    if ([view isKindOfClass:UIImageView.class]) {
        backgroundState.capturesImage = YES;
        backgroundState.image = ((UIImageView *)view).image;
    }
    if ([view isKindOfClass:UIVisualEffectView.class]) {
        backgroundState.capturesEffect = YES;
        backgroundState.effect = ((UIVisualEffectView *)view).effect;
        backgroundState.capturesEffectContentBackgroundColor = YES;
        backgroundState.effectContentBackgroundColor = ((UIVisualEffectView *)view).contentView.backgroundColor;
    }
    backgroundState.capturesHidden = YES;
    backgroundState.hidden = view.hidden;
    [state.nativeBackgrounds addObject:backgroundState];
    return backgroundState;
}

static void WCLiquidGlassChatBottomMenuRestore(UIView *view,
                                                WCLiquidGlassChatBottomMenuState *state) {
    if (!state) {
        return;
    }
    if (state.capturedOriginalBackgroundColor) {
        view.backgroundColor = state.originalBackgroundColor;
    }
    for (WCLiquidGlassChatBottomMenuBackgroundState *backgroundState in state.nativeBackgrounds) {
        UIView *backgroundView = backgroundState.view;
        if (!backgroundView) {
            continue;
        }
        backgroundView.backgroundColor = backgroundState.backgroundColor;
        if (backgroundState.capturesLayerBackgroundColor) {
            backgroundView.layer.backgroundColor = backgroundState.layerBackgroundColor.CGColor;
        }
        if (backgroundState.capturesImage && [backgroundView isKindOfClass:UIImageView.class]) {
            ((UIImageView *)backgroundView).image = backgroundState.image;
        }
        if (backgroundState.capturesEffect && [backgroundView isKindOfClass:UIVisualEffectView.class]) {
            ((UIVisualEffectView *)backgroundView).effect = backgroundState.effect;
        }
        if (backgroundState.capturesEffectContentBackgroundColor &&
            [backgroundView isKindOfClass:UIVisualEffectView.class]) {
            ((UIVisualEffectView *)backgroundView).contentView.backgroundColor =
                backgroundState.effectContentBackgroundColor;
        }
        if (backgroundState.capturesHidden) {
            backgroundView.hidden = backgroundState.hidden;
        }
    }
    [state.glassView removeFromSuperview];
    state.capturedOriginalBackgroundColor = NO;
    state.originalBackgroundColor = nil;
    state.effectState = NSIntegerMin;
    state.effectRecoveryAttempted = NO;
    state.backgroundPrepared = NO;
    state.lastNativeSubviewCount = 0;
    state.lastViewBounds = CGRectZero;
    state.lastRenderHost = nil;
    state.lastUseSiblingRenderHost = NO;
    state.attachmentBar = nil;
    state.attachmentBarSearchCompleted = NO;
    [state.nativeBackgrounds removeAllObjects];
}

static void WCLiquidGlassChatBottomMenuClearNativeView(
    WCLiquidGlassChatBottomMenuState *state,
    UIView *view) {
    if (!view || view == state.glassView) {
        return;
    }
    WCLiquidGlassChatBottomMenuStateForBackground(state, view);
    view.backgroundColor = UIColor.clearColor;
    if (view.layer.backgroundColor) {
        view.layer.backgroundColor = UIColor.clearColor.CGColor;
    }
    if ([view isKindOfClass:UIImageView.class]) {
        ((UIImageView *)view).image = nil;
    }
    if ([view isKindOfClass:UIVisualEffectView.class]) {
        ((UIVisualEffectView *)view).effect = nil;
        ((UIVisualEffectView *)view).contentView.backgroundColor = UIColor.clearColor;
    }
}

static void WCLiquidGlassChatBottomMenuPlaceGlassView(
    WCLiquidGlassChatBottomMenuState *state,
    UIView *view,
    UIView *renderHost,
    BOOL useSiblingRenderHost) {
    if (!state.glassView || !view || !renderHost) {
        return;
    }
    if (state.glassView.superview != renderHost) {
        [state.glassView removeFromSuperview];
        NSUInteger viewIndex = [renderHost.subviews indexOfObject:view];
        [renderHost insertSubview:state.glassView
                            atIndex:viewIndex == NSNotFound ? 0 : viewIndex];
    } else if (useSiblingRenderHost) {
        // Native layout can reorder the panel after it is presented.  Restore
        // the glass immediately below it without touching any button views.
        NSUInteger viewIndex = [renderHost.subviews indexOfObject:view];
        NSUInteger glassIndex = [renderHost.subviews indexOfObject:state.glassView];
        if (viewIndex != NSNotFound && glassIndex != NSNotFound && glassIndex > viewIndex) {
            [state.glassView removeFromSuperview];
            [renderHost insertSubview:state.glassView atIndex:viewIndex];
        }
    } else if (renderHost == view && [renderHost.subviews indexOfObject:state.glassView] != 0) {
        [state.glassView removeFromSuperview];
        [renderHost insertSubview:state.glassView atIndex:0];
    }
    state.glassView.autoresizingMask = useSiblingRenderHost
        ? UIViewAutoresizingNone
        : (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight);
}

static void WCLiquidGlassChatBottomMenuConfigureGlassFrame(
    UIVisualEffectView *glassView,
    UIView *view,
    UIView *renderHost,
    BOOL useSiblingRenderHost) {
    if (!glassView || !view || !renderHost) {
        return;
    }
    glassView.frame = useSiblingRenderHost
        ? [view convertRect:view.bounds toView:renderHost]
        : renderHost.bounds;
    CGFloat height = CGRectGetHeight(view.bounds);
    CGFloat cornerRadius = view.layer.cornerRadius > 0.0
        ? view.layer.cornerRadius
        : (!useSiblingRenderHost && renderHost.layer.cornerRadius > 0.0
            ? renderHost.layer.cornerRadius
            : MIN(28.0, MAX(0.0, height * 0.5)));
    glassView.layer.cornerRadius = cornerRadius;
    CACornerMask maskedCorners = view.layer.maskedCorners;
    if (maskedCorners == 0 && !useSiblingRenderHost) {
        maskedCorners = renderHost.layer.maskedCorners;
    }
    if (maskedCorners == 0) {
        maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner |
            kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    }
    glassView.layer.maskedCorners = maskedCorners;
}

static void WCLiquidGlassChatBottomMenuUpdate(UIView *view) {
    WCLiquidGlassChatBottomMenuState *state =
        objc_getAssociatedObject(view, WCLiquidGlassChatBottomMenuStateKey);
    BOOL likelyPanel = CGRectGetHeight(view.bounds) >= 96.0 ||
        WCLiquidGlassChatBottomMenuClassNameContains(view, @"selectattachmentview");
    BOOL shouldUseHost = WCLiquidGlassChatBottomMenuShouldUseHost(view);
    if (likelyPanel && !state) {
        state = [[WCLiquidGlassChatBottomMenuState alloc] init];
        objc_setAssociatedObject(view,
                                 WCLiquidGlassChatBottomMenuStateKey,
                                 state,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (likelyPanel && state && !state.diagnosticCandidateRecorded) {
        state.diagnosticCandidateRecorded = YES;
        [WCLiquidGlassCrashLogger.sharedLogger recordEvent:[NSString stringWithFormat:
            @"ChatBottomMenu candidate=%@ host=%@ enabled=%@ window=%@ frame={x=%.1f y=%.1f w=%.1f h=%.1f} subviews=%lu",
            NSStringFromClass(view.class),
            shouldUseHost ? @"YES" : @"NO",
            WCLiquidGlassPreferences.chatBottomMenuGlassEnabled ? @"YES" : @"NO",
            view.window ? @"YES" : @"NO",
            CGRectGetMinX(view.frame),
            CGRectGetMinY(view.frame),
            CGRectGetWidth(view.bounds),
            CGRectGetHeight(view.bounds),
            (unsigned long)view.subviews.count]];
    }
    if (!WCLiquidGlassPreferences.chatBottomMenuGlassEnabled ||
        !shouldUseHost ||
        view.hidden || view.alpha <= 0.01 || CGRectIsEmpty(view.bounds)) {
        WCLiquidGlassChatBottomMenuRestore(view, state);
        return;
    }

    if (!state) {
        state = [[WCLiquidGlassChatBottomMenuState alloc] init];
        objc_setAssociatedObject(view,
                                 WCLiquidGlassChatBottomMenuStateKey,
                                 state,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!state.capturedOriginalBackgroundColor) {
        state.capturedOriginalBackgroundColor = YES;
        state.originalBackgroundColor = view.backgroundColor;
    }
    NSInteger effectState = WCLiquidGlassPreferences.glassAppearance * 10 +
        view.traitCollection.userInterfaceStyle;
    BOOL needsGlassView = !state.glassView || state.effectState != effectState;
    if (state.glassView && !state.glassView.effect && !state.effectRecoveryAttempted) {
        // Recover at most once for this presentation.  If WCGlass still clears
        // the replacement after insertion, retrying from every layout pass is
        // both ineffective and the source of the horizontal-swipe hitch.
        state.effectRecoveryAttempted = YES;
        needsGlassView = YES;
    }
    if (needsGlassView) {
        [state.glassView removeFromSuperview];
        UIVisualEffect *effect = WCLiquidGlassCurrentGlassEffect();
        state.glassView = [[WCLiquidGlassChatBottomMenuEffectView alloc] initWithEffect:effect];
        objc_setAssociatedObject(state.glassView,
                                 WCLiquidGlassChatBottomMenuProtectEffectKey,
                                 @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        state.createdEffectPresent = state.glassView.effect != nil;
        state.effectState = effectState;
        state.glassView.userInteractionEnabled = NO;
        state.glassView.clipsToBounds = YES;
        state.glassView.layer.cornerCurve = kCACornerCurveContinuous;
        state.glassView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        if (!state.glassView.effect) {
            state.effectRecoveryAttempted = YES;
        }
    }

    // ThemePro inserts its attachment image directly into the panel's native
    // background slot.  Use the same host and ordering for the glass view.
    // Supply the material to initWithEffect: above and never call setEffect:
    // here, because WCGlass clears attachment-panel effects in that setter.
    BOOL useSiblingRenderHost = NO;
    UIView *renderHost = view;
    BOOL hierarchyChanged = !state.backgroundPrepared;
    NSUInteger nativeSubviewCount = view.subviews.count;
    if (state.glassView && [view.subviews containsObject:state.glassView] && nativeSubviewCount > 0) {
        nativeSubviewCount -= 1;
    }
    if (state.backgroundPrepared && state.lastNativeSubviewCount != nativeSubviewCount) {
        hierarchyChanged = YES;
    }
    UIView *attachmentBar = state.attachmentBar;
    if (!state.attachmentBarSearchCompleted || hierarchyChanged) {
        attachmentBar = WCLiquidGlassChatBottomMenuFindAttachmentBar(view, 0);
        state.attachmentBar = attachmentBar;
        state.attachmentBarSearchCompleted = YES;
    }
    if (!renderHost) {
        WCLiquidGlassChatBottomMenuRestore(view, state);
        return;
    }
    WCLiquidGlassChatBottomMenuPlaceGlassView(state, view, renderHost, useSiblingRenderHost);

    if (hierarchyChanged) {
        WCLiquidGlassChatBottomMenuStateForBackground(state, view);
        if (attachmentBar && attachmentBar != view) {
            // The bar can carry a second opaque surface even though the
            // replacement view belongs to SelectAttachmentView.  Clear only
            // that surface; its buttons and their subviews stay untouched.
            WCLiquidGlassChatBottomMenuClearNativeView(state, attachmentBar);
        }
        for (UIView *backgroundView in WCLiquidGlassChatBottomMenuNativeBackgroundViews(view,
                                                                                           state.glassView)) {
            WCLiquidGlassChatBottomMenuClearNativeView(state, backgroundView);
        }
        if (attachmentBar && attachmentBar != view) {
            for (UIView *backgroundView in WCLiquidGlassChatBottomMenuNativeBackgroundViews(attachmentBar,
                                                                                             state.glassView)) {
                WCLiquidGlassChatBottomMenuClearNativeView(state, backgroundView);
            }
        }

        // ThemePro hides exact-class UIImageView children after the native
        // layout.  On current WeChat these are the old panel background slots;
        // action icons live inside buttons and are not direct children of the
        // bar.
        if (WCLiquidGlassChatBottomMenuClassNameContains(view, @"selectattachmentview") ||
            WCLiquidGlassChatBottomMenuClassNameContains(renderHost, @"inputtoolviewbar")) {
            for (UIView *subview in view.subviews.copy) {
                if (subview == state.glassView || subview.class != UIImageView.class) {
                    continue;
                }
                WCLiquidGlassChatBottomMenuStateForBackground(state, subview);
                subview.hidden = YES;
                ((UIImageView *)subview).image = nil;
            }
        }
        state.backgroundPrepared = YES;
        state.lastNativeSubviewCount = nativeSubviewCount;
    }

    BOOL geometryChanged = state.lastRenderHost != renderHost ||
        state.lastUseSiblingRenderHost != useSiblingRenderHost ||
        !CGRectEqualToRect(state.lastViewBounds, view.bounds);
    if (geometryChanged) {
        WCLiquidGlassChatBottomMenuConfigureGlassFrame(state.glassView,
                                                       view,
                                                       renderHost,
                                                       useSiblingRenderHost);
        state.lastRenderHost = renderHost;
        state.lastUseSiblingRenderHost = useSiblingRenderHost;
        state.lastViewBounds = view.bounds;
    }

    state.glassView.opaque = NO;
    state.glassView.backgroundColor = UIColor.clearColor;
    state.glassView.contentView.backgroundColor = UIColor.clearColor;
    state.glassView.hidden = NO;
    if (!state.diagnosticMaterialRecorded && state.glassView.window) {
        state.diagnosticMaterialRecorded = YES;
        [WCLiquidGlassCrashLogger.sharedLogger recordEvent:[NSString stringWithFormat:
            @"ChatBottomMenu material host=%@ render=%@ bar=%@ nativeBackgrounds=%lu createdEffect=%@ glassClass=%@ glassSuperview=%@ glassSuperviewClass=%@ glassWindow=%@ glassFrame={x=%.1f y=%.1f w=%.1f h=%.1f} glassEffect=%@ effectClass=%@",
            NSStringFromClass(view.class),
            NSStringFromClass(renderHost.class),
            attachmentBar ? NSStringFromClass(attachmentBar.class) : @"NONE",
            (unsigned long)state.nativeBackgrounds.count,
            state.createdEffectPresent ? @"YES" : @"NO",
            NSStringFromClass(state.glassView.class),
            state.glassView.superview == renderHost ? @"YES" : @"NO",
            state.glassView.superview ? NSStringFromClass(state.glassView.superview.class) : @"NONE",
            state.glassView.window ? @"YES" : @"NO",
            CGRectGetMinX(state.glassView.frame),
            CGRectGetMinY(state.glassView.frame),
            CGRectGetWidth(state.glassView.bounds),
            CGRectGetHeight(state.glassView.bounds),
            state.glassView.effect ? @"YES" : @"NO",
            state.glassView.effect ? NSStringFromClass(state.glassView.effect.class) : @"NONE"]];
    }
}

static void WCLiquidGlassChatBottomMenuLayoutInputToolContainer(UIView *self, SEL selector) {
    if (WCLiquidGlassOriginalInputToolContainerLayoutSubviews) {
        WCLiquidGlassOriginalInputToolContainerLayoutSubviews(self, selector);
    }
    [WCLiquidGlassVisibleChatBottomMenuViews() addObject:self];
    WCLiquidGlassChatBottomMenuUpdate(self);
}

static void WCLiquidGlassChatBottomMenuLayoutSelectAttachment(UIView *self, SEL selector) {
    if (WCLiquidGlassOriginalSelectAttachmentLayoutSubviews) {
        WCLiquidGlassOriginalSelectAttachmentLayoutSubviews(self, selector);
    }
    [WCLiquidGlassVisibleChatBottomMenuViews() addObject:self];
    WCLiquidGlassChatBottomMenuUpdate(self);
    WCLiquidGlassScheduleChatBottomMenuRescans(self);
}

static void WCLiquidGlassChatBottomMenuLayoutInputToolViewBar(UIView *self, SEL selector) {
    if (WCLiquidGlassOriginalInputToolViewBarLayoutSubviews) {
        WCLiquidGlassOriginalInputToolViewBarLayoutSubviews(self, selector);
    }
    [WCLiquidGlassVisibleChatBottomMenuViews() addObject:self];
    WCLiquidGlassChatBottomMenuUpdate(self);
}

static void WCLiquidGlassChatBottomMenuLayoutMMInputToolView(UIView *self, SEL selector) {
    if (WCLiquidGlassOriginalMMInputToolViewLayoutSubviews) {
        WCLiquidGlassOriginalMMInputToolViewLayoutSubviews(self, selector);
    }
    [WCLiquidGlassVisibleChatBottomMenuViews() addObject:self];
    WCLiquidGlassChatBottomMenuUpdate(self);
}

static void WCLiquidGlassRefreshChatBottomMenuViews(void) {
    for (UIView *view in WCLiquidGlassVisibleChatBottomMenuViews().allObjects) {
        // A native attachment panel can be laid out before UIKit attaches its
        // transition window.  Keep the associated glass state through that
        // phase; the next layout/window callback will move the same view into
        // the final hierarchy without flashing back to the opaque native layer.
        WCLiquidGlassChatBottomMenuUpdate(view);
    }
}

static void WCLiquidGlassChatBottomMenuRefreshVisibleHierarchy(UIView *view,
                                                               NSUInteger depth) {
    if (!view || depth > 32) {
        return;
    }
    if (WCLiquidGlassChatBottomMenuIsCandidate(view)) {
        [WCLiquidGlassVisibleChatBottomMenuViews() addObject:view];
        WCLiquidGlassChatBottomMenuUpdate(view);
    }
    for (UIView *subview in view.subviews) {
        WCLiquidGlassChatBottomMenuRefreshVisibleHierarchy(subview, depth + 1);
    }
}

static void WCLiquidGlassRefreshVisibleChatBottomMenuViews(void);

void WCLiquidGlassRefreshChatBottomMenuHierarchy(UIView *rootView) {
    if (!rootView) {
        return;
    }
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            WCLiquidGlassRefreshChatBottomMenuHierarchy(rootView);
        });
        return;
    }
    if (CGRectGetHeight(rootView.bounds) < 120.0 &&
        !WCLiquidGlassChatBottomMenuHasVisibleAttachmentDescendant(rootView, 0)) {
        return;
    }
    WCLiquidGlassChatBottomMenuRefreshVisibleHierarchy(rootView, 0);
}

static void WCLiquidGlassRefreshVisibleChatBottomMenuViews(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) {
            continue;
        }
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            WCLiquidGlassChatBottomMenuRefreshVisibleHierarchy(window, 0);
        }
    }
}

void WCLiquidGlassScheduleChatBottomMenuRescans(UIView *rootView) {
    if (!rootView || ![NSThread isMainThread] || rootView.hidden || rootView.alpha <= 0.01 ||
        CGRectIsEmpty(rootView.bounds)) {
        return;
    }
    BOOL isSelectAttachmentView =
        WCLiquidGlassChatBottomMenuClassNameContains(rootView, @"selectattachmentview");
    if (!isSelectAttachmentView && CGRectGetHeight(rootView.bounds) < 120.0) {
        return;
    }

    CFTimeInterval now = CACurrentMediaTime();
    if (WCLiquidGlassChatBottomMenuRescanScheduled ||
        now - WCLiquidGlassChatBottomMenuLastRescanTime < 0.12) {
        return;
    }
    WCLiquidGlassChatBottomMenuLastRescanTime = now;
    WCLiquidGlassChatBottomMenuRescanScheduled = YES;

    __weak UIView *weakRootView = rootView;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        WCLiquidGlassChatBottomMenuRescanScheduled = NO;
        UIView *strongRootView = weakRootView;
        if (strongRootView) {
            WCLiquidGlassRefreshChatBottomMenuHierarchy(strongRootView);
        }
    });
}

static void WCLiquidGlassScheduleChatBottomMenuHookRetry(void) {
    if (WCLiquidGlassChatBottomMenuHookRetryScheduled ||
        WCLiquidGlassChatBottomMenuHookInstallAttempts >= 10) {
        return;
    }
    WCLiquidGlassChatBottomMenuHookRetryScheduled = YES;
    WCLiquidGlassChatBottomMenuHookInstallAttempts += 1;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        WCLiquidGlassChatBottomMenuHookRetryScheduled = NO;
        WCLiquidGlassInstallChatBottomMenuHooks();
    });
}

void WCLiquidGlassInstallChatBottomMenuHooks(void) {
    BOOL didInstallHook = NO;
    Class inputToolContainerClass = NSClassFromString(@"InputToolContainerView");
    if (!WCLiquidGlassInputToolContainerHookInstalled && inputToolContainerClass) {
        Method layoutMethod = class_getInstanceMethod(inputToolContainerClass,
                                                       @selector(layoutSubviews));
        if (layoutMethod) {
            MSHookMessageEx(inputToolContainerClass,
                            @selector(layoutSubviews),
                            (IMP)&WCLiquidGlassChatBottomMenuLayoutInputToolContainer,
                            (IMP *)&WCLiquidGlassOriginalInputToolContainerLayoutSubviews);
            WCLiquidGlassInputToolContainerHookInstalled =
                WCLiquidGlassOriginalInputToolContainerLayoutSubviews != NULL;
            didInstallHook = WCLiquidGlassInputToolContainerHookInstalled;
        }
    }

    Class selectAttachmentClass = NSClassFromString(@"SelectAttachmentView");
    if (!WCLiquidGlassSelectAttachmentHookInstalled && selectAttachmentClass) {
        Method layoutMethod = class_getInstanceMethod(selectAttachmentClass,
                                                       @selector(layoutSubviews));
        if (layoutMethod) {
            MSHookMessageEx(selectAttachmentClass,
                            @selector(layoutSubviews),
                            (IMP)&WCLiquidGlassChatBottomMenuLayoutSelectAttachment,
                            (IMP *)&WCLiquidGlassOriginalSelectAttachmentLayoutSubviews);
            WCLiquidGlassSelectAttachmentHookInstalled =
                WCLiquidGlassOriginalSelectAttachmentLayoutSubviews != NULL;
            didInstallHook = WCLiquidGlassSelectAttachmentHookInstalled || didInstallHook;
        }
    }

    Class inputToolViewBarClass = NSClassFromString(@"InputToolViewBar");
    if (!WCLiquidGlassInputToolViewBarHookInstalled && inputToolViewBarClass) {
        Method layoutMethod = class_getInstanceMethod(inputToolViewBarClass,
                                                       @selector(layoutSubviews));
        if (layoutMethod) {
            MSHookMessageEx(inputToolViewBarClass,
                            @selector(layoutSubviews),
                            (IMP)&WCLiquidGlassChatBottomMenuLayoutInputToolViewBar,
                            (IMP *)&WCLiquidGlassOriginalInputToolViewBarLayoutSubviews);
            WCLiquidGlassInputToolViewBarHookInstalled =
                WCLiquidGlassOriginalInputToolViewBarLayoutSubviews != NULL;
            didInstallHook = WCLiquidGlassInputToolViewBarHookInstalled || didInstallHook;
        }
    }

    Class inputToolViewClass = NSClassFromString(@"MMInputToolView");
    if (!WCLiquidGlassMMInputToolViewHookInstalled && inputToolViewClass) {
        Method layoutMethod = class_getInstanceMethod(inputToolViewClass,
                                                       @selector(layoutSubviews));
        if (layoutMethod) {
            MSHookMessageEx(inputToolViewClass,
                            @selector(layoutSubviews),
                            (IMP)&WCLiquidGlassChatBottomMenuLayoutMMInputToolView,
                            (IMP *)&WCLiquidGlassOriginalMMInputToolViewLayoutSubviews);
            WCLiquidGlassMMInputToolViewHookInstalled =
                WCLiquidGlassOriginalMMInputToolViewLayoutSubviews != NULL;
            didInstallHook = WCLiquidGlassMMInputToolViewHookInstalled || didInstallHook;
        }
    }

    if (!WCLiquidGlassInputToolContainerHookInstalled ||
        !WCLiquidGlassSelectAttachmentHookInstalled ||
        !WCLiquidGlassInputToolViewBarHookInstalled ||
        !WCLiquidGlassMMInputToolViewHookInstalled) {
        WCLiquidGlassScheduleChatBottomMenuHookRetry();
    }
    if (!WCLiquidGlassChatBottomMenuObserverInstalled) {
        WCLiquidGlassChatBottomMenuObserverInstalled = YES;
        [NSNotificationCenter.defaultCenter addObserverForName:WCLiquidGlassPreferencesDidChangeNotification
                                                          object:nil
                                                           queue:NSOperationQueue.mainQueue
                                                      usingBlock:^(__unused NSNotification *notification) {
            WCLiquidGlassRefreshChatBottomMenuViews();
        }];
    }
    if (didInstallHook) {
        WCLiquidGlassRefreshVisibleChatBottomMenuViews();
    }
}
