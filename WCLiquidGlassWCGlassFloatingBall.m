#import "WCLiquidGlassWCGlassFloatingBall.h"

#import "WCLiquidGlassMenu.h"
#import "WCLiquidGlassPreferences.h"
#import "WCLiquidGlassHomeCorners.h"

#import <objc/message.h>

static NSString *const WCLiquidGlassWCGlassBallEnabledKey = @"wclg_floating_ball_enabled";
static NSString *const WCLiquidGlassWCGlassBallSizeKey = @"wclg_floating_ball_size";
static NSString *const WCLiquidGlassWCGlassBallIconKey = @"wclg_floating_ball_icon_item";
static NSString *const WCLiquidGlassWCGlassBallDockKey = @"wclg_floating_ball_edge_dock_enabled";
static NSString *const WCLiquidGlassWCGlassBallXKey = @"wclg_floating_ball_position_x";
static NSString *const WCLiquidGlassWCGlassBallYKey = @"wclg_floating_ball_position_y";
static NSString *const WCLiquidGlassWCGlassBallActionsKey = @"wclg_floating_ball_actions";

static UIImage *WCLiquidGlassWCGlassBallIconImage(CGFloat size) {
    NSString *symbol = [NSUserDefaults.standardUserDefaults stringForKey:WCLiquidGlassWCGlassBallIconKey] ?: @"ellipsis";
    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:size weight:UIImageSymbolWeightSemibold];
    return [[UIImage systemImageNamed:symbol] imageByApplyingSymbolConfiguration:configuration] ?: [UIImage systemImageNamed:@"ellipsis"];
}

static NSArray<NSString *> *WCLiquidGlassWCGlassSelectors(NSString *identifier) {
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
    return selectors[identifier] ?: @[];
}

static UIViewController *WCLiquidGlassWCGlassVisibleController(void) {
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState == UISceneActivationStateUnattached) {
            continue;
        }
        for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
            if (candidate.isKeyWindow && candidate.windowLevel == UIWindowLevelNormal) {
                window = candidate;
                break;
            }
        }
        if (window) {
            break;
        }
    }
    UIViewController *controller = window.rootViewController;
    while (controller.presentedViewController && !controller.presentedViewController.isBeingDismissed) {
        controller = controller.presentedViewController;
    }
    while (controller) {
        if ([controller isKindOfClass:UINavigationController.class]) {
            controller = ((UINavigationController *)controller).visibleViewController;
        } else if ([controller isKindOfClass:UITabBarController.class]) {
            controller = ((UITabBarController *)controller).selectedViewController;
        } else {
            break;
        }
    }
    return controller;
}

static UINavigationController *WCLiquidGlassWCGlassNavigationController(void) {
    UIViewController *visible = WCLiquidGlassWCGlassVisibleController();
    if ([visible isKindOfClass:UINavigationController.class]) {
        return (UINavigationController *)visible;
    }
    return visible.navigationController;
}

static BOOL WCLiquidGlassWCGlassInvoke(id target, SEL selector) {
    if (!target || ![target respondsToSelector:selector]) {
        return NO;
    }
    NSMethodSignature *signature = [target methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments > 3) {
        return NO;
    }
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
    return NO;
}

static NSArray<NSDictionary<NSString *, id> *> *WCLiquidGlassWCGlassDefaultActions(void) {
    NSMutableArray *items = [NSMutableArray array];
    for (NSDictionary<NSString *, NSString *> *action in WCLiquidGlassActionCatalog()) {
        NSString *identifier = action[@"identifier"];
        if (identifier.length > 0) {
            [items addObject:@{ @"action": identifier, @"hidden": @NO }];
        }
    }
    return items.copy;
}

static NSArray<NSDictionary<NSString *, id> *> *WCLiquidGlassWCGlassAllActions(void) {
    NSArray *stored = [NSUserDefaults.standardUserDefaults arrayForKey:WCLiquidGlassWCGlassBallActionsKey];
    if (![stored isKindOfClass:NSArray.class] || stored.count == 0) {
        return WCLiquidGlassWCGlassDefaultActions();
    }
    NSMutableArray *valid = [NSMutableArray array];
    NSSet *known = [NSSet setWithArray:[WCLiquidGlassActionCatalog() valueForKey:@"identifier"]];
    for (NSDictionary *item in stored) {
        NSString *identifier = item[@"action"];
        if ([identifier isKindOfClass:NSString.class] && [known containsObject:identifier]) {
            [valid addObject:@{ @"action": identifier, @"hidden": @([item[@"hidden"] boolValue]) }];
        }
    }
    return valid.count > 0 ? valid.copy : WCLiquidGlassWCGlassDefaultActions();
}

static NSArray<NSDictionary<NSString *, id> *> *WCLiquidGlassWCGlassVisibleActions(void) {
    NSMutableArray *visible = [NSMutableArray array];
    for (NSDictionary *item in WCLiquidGlassWCGlassAllActions()) {
        if (![item[@"hidden"] boolValue]) {
            [visible addObject:item];
        }
    }
    return visible.copy;
}

static void WCLiquidGlassWCGlassPerformAction(NSString *identifier) {
    id tabController = WCLiquidGlassCurrentTabController();
    if ([identifier isEqualToString:WCLiquidGlassActionPageHierarchyDiagnostics]) {
        WCLiquidGlassCaptureCurrentPageHierarchyDiagnostics();
        return;
    }
    if ([identifier hasPrefix:@"tab."] && [tabController respondsToSelector:NSSelectorFromString(@"setSelectedIndex:")]) {
        NSInteger index = [[identifier substringFromIndex:4] integerValue];
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(tabController,
                                                       NSSelectorFromString(@"setSelectedIndex:"),
                                                       index);
        return;
    }
    if ([identifier isEqualToString:WCLiquidGlassActionSettings]) {
        Class settingsClass = NSClassFromString(@"WCLiquidGlass");
        UINavigationController *navigation = WCLiquidGlassWCGlassNavigationController();
        if (settingsClass && navigation) {
            [navigation pushViewController:[[settingsClass alloc] init] animated:YES];
        }
        return;
    }
    if ([identifier isEqualToString:WCLiquidGlassActionPlugins]) {
        Class pluginsClass = NSClassFromString(@"WCPluginsViewController");
        UINavigationController *navigation = WCLiquidGlassWCGlassNavigationController();
        if (pluginsClass && navigation) {
            [navigation pushViewController:[[pluginsClass alloc] init] animated:YES];
        }
        return;
    }
    if ([identifier isEqualToString:WCLiquidGlassActionWCGlassSettings]) {
        Class pluginsClass = NSClassFromString(@"WCPluginsViewController");
        UINavigationController *navigation = WCLiquidGlassWCGlassNavigationController();
        if (pluginsClass && navigation) {
            [navigation pushViewController:[[pluginsClass alloc] init] animated:YES];
        }
        return;
    }
    if ([identifier isEqualToString:WCLiquidGlassActionMoments]) {
        Class momentsClass = NSClassFromString(@"WCTimeLineViewController");
        UINavigationController *navigation = WCLiquidGlassWCGlassNavigationController();
        if (momentsClass && navigation) {
            [navigation pushViewController:[[momentsClass alloc] init] animated:YES];
        }
        return;
    }
    if ([identifier isEqualToString:WCLiquidGlassActionDoutuAssistant]) {
        WCLiquidGlassWCGlassInvoke(WCLiquidGlassWCGlassVisibleController(), NSSelectorFromString(@"doutuAction"));
        return;
    }
    UIViewController *visible = WCLiquidGlassWCGlassVisibleController();
    for (NSString *name in WCLiquidGlassWCGlassSelectors(identifier)) {
        if (WCLiquidGlassWCGlassInvoke(visible, NSSelectorFromString(name))) {
            return;
        }
        if (WCLiquidGlassWCGlassInvoke(visible.navigationController, NSSelectorFromString(name))) {
            return;
        }
    }
}

@class WCLiquidGlassWCGlassBallSettingsController;

@interface WCLiquidGlassWCGlassBallSettingsController : UITableViewController
@property(nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *items;
@end

@interface WCLiquidGlassWCGlassBallPassthroughView : UIView
@end

@implementation WCLiquidGlassWCGlassBallPassthroughView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self ? nil : hit;
}
@end

@interface WCLiquidGlassWCGlassFloatingBall : UIView <UIGestureRecognizerDelegate>
@property(nonatomic, strong) UIButton *dismissControl;
@property(nonatomic, strong) UIVisualEffectView *menuGlass;
@property(nonatomic, strong) UIScrollView *menuScrollView;
@property(nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *menuActions;
@property(nonatomic, strong) NSMutableArray<UIButton *> *actionButtons;
@property(nonatomic, strong) UIVisualEffectView *ballGlass;
@property(nonatomic, strong) UIButton *ballButton;
@property(nonatomic, strong) UIImageView *ballIconView;
@property(nonatomic, assign, getter=isExpanded) BOOL expanded;
@property(nonatomic, assign) BOOL positionLoaded;
@property(nonatomic, assign) CGPoint dragStartCenter;
@property(nonatomic, assign) CGFloat ballDiameter;
@property(nonatomic, assign) BOOL ballDocked;
@property(nonatomic, assign) BOOL ballDockedLeft;
- (void)rebuildActionButtons;
- (void)refreshAppearance;
- (void)updateBallSymbolAnimated:(BOOL)animated;
- (CGAffineTransform)collapsedMenuTransform;
- (void)reloadConfiguration;
@end

@implementation WCLiquidGlassWCGlassFloatingBall

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (!self.expanded && hit == self) {
        return nil;
    }
    return hit;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) {
        return nil;
    }
    self.backgroundColor = UIColor.clearColor;
    self.ballDiameter = MIN(100.0, MAX(40.0, [NSUserDefaults.standardUserDefaults doubleForKey:WCLiquidGlassWCGlassBallSizeKey] ?: 48.0));
    self.ballDocked = [NSUserDefaults.standardUserDefaults objectForKey:WCLiquidGlassWCGlassBallDockKey]
        ? [NSUserDefaults.standardUserDefaults boolForKey:WCLiquidGlassWCGlassBallDockKey]
        : YES;
    self.ballDockedLeft = NO;
    self.menuActions = WCLiquidGlassWCGlassVisibleActions();
    self.actionButtons = [NSMutableArray array];

    UIBlurEffect *fallback = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
    UIVisualEffect *effect = WCLiquidGlassCurrentGlassEffect() ?: fallback;
    self.ballGlass = [[UIVisualEffectView alloc] initWithEffect:effect];
    self.ballGlass.layer.cornerRadius = self.ballDiameter / 2.0;
    self.ballGlass.layer.masksToBounds = YES;
    self.ballGlass.userInteractionEnabled = NO;
    [self addSubview:self.ballGlass];

    self.ballButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.ballButton.tintColor = UIColor.labelColor;
    [self.ballButton addTarget:self action:@selector(ballTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.ballButton];
    self.ballIconView = [[UIImageView alloc] initWithImage:WCLiquidGlassWCGlassBallIconImage(self.ballDiameter * 0.34)];
    self.ballIconView.tintColor = UIColor.labelColor;
    self.ballIconView.contentMode = UIViewContentModeScaleAspectFit;
    self.ballIconView.userInteractionEnabled = NO;
    [self.ballButton addSubview:self.ballIconView];

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(ballLongPressed:)];
    longPress.minimumPressDuration = 0.55;
    [self.ballButton addGestureRecognizer:longPress];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    pan.delegate = self;
    [self addGestureRecognizer:pan];
    [self rebuildActionButtons];
    [self refreshAppearance];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat diameter = self.ballDiameter;
    CGPoint center = self.positionLoaded ? self.ballButton.center : [self restoredCenter];
    if (!self.positionLoaded) {
        self.positionLoaded = YES;
        self.ballButton.center = [self clampedBallCenter:center];
    }
    self.ballGlass.bounds = (CGRect){CGPointZero, CGSizeMake(diameter, diameter)};
    self.ballGlass.center = self.ballButton.center;
    self.ballButton.bounds = self.ballGlass.bounds;
    self.ballButton.center = [self clampedBallCenter:self.ballButton.center];
    self.ballIconView.frame = CGRectInset(self.ballButton.bounds, diameter * 0.28, diameter * 0.28);
    if (self.expanded) {
        [self layoutMenuPanel];
    }
}

- (CGPoint)restoredCenter {
    CGFloat x = [NSUserDefaults.standardUserDefaults doubleForKey:WCLiquidGlassWCGlassBallXKey];
    CGFloat y = [NSUserDefaults.standardUserDefaults doubleForKey:WCLiquidGlassWCGlassBallYKey];
    if (x <= 0.001 || y <= 0.001) {
        return CGPointMake(CGRectGetWidth(self.bounds) - self.ballDiameter * 0.55, CGRectGetMidY(self.bounds));
    }
    return CGPointMake(CGRectGetWidth(self.bounds) * MIN(1.0, x), CGRectGetHeight(self.bounds) * MIN(1.0, y));
}

- (CGPoint)clampedBallCenter:(CGPoint)center {
    UIEdgeInsets insets = self.superview.window.safeAreaInsets;
    CGFloat half = self.ballDiameter / 2.0;
    CGFloat minX = half + 6.0;
    CGFloat maxX = CGRectGetWidth(self.bounds) - half - 6.0;
    CGFloat minY = insets.top + half + 6.0;
    CGFloat maxY = CGRectGetHeight(self.bounds) - insets.bottom - half - 6.0;
    return CGPointMake(MIN(maxX, MAX(minX, center.x)), MIN(maxY, MAX(minY, center.y)));
}

- (CGPoint)dockedBallCenterForLeft:(BOOL)left y:(CGFloat)y {
    CGFloat x = left ? self.ballDiameter / 2.0 + 10.0 : CGRectGetWidth(self.bounds) - self.ballDiameter / 2.0 - 10.0;
    return [self clampedBallCenter:CGPointMake(x, y)];
}

- (void)revealDockedBallAnimated:(BOOL)animated completion:(void (^ _Nullable)(void))completion {
    CGPoint target = [self dockedBallCenterForLeft:self.ballDockedLeft y:self.ballButton.center.y];
    void (^animations)(void) = ^{ self.ballButton.center = target; };
    if (animated) {
        [UIView animateWithDuration:0.22 animations:animations completion:^(__unused BOOL finished) { if (completion) completion(); }];
    } else {
        animations();
        if (completion) completion();
    }
}

- (void)dockBallAnimated:(BOOL)animated {
    [self revealDockedBallAnimated:animated completion:nil];
}

- (void)refreshAppearance {
    UIVisualEffect *effect = WCLiquidGlassCurrentGlassEffect() ?: [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
    self.ballGlass.effect = effect;
    self.menuGlass.effect = effect;
    self.ballIconView.image = self.expanded ? [UIImage systemImageNamed:@"xmark"] : WCLiquidGlassWCGlassBallIconImage(self.ballDiameter * 0.34);
    self.ballIconView.tintColor = UIColor.labelColor;
    for (UIButton *button in self.actionButtons) {
        button.tintColor = UIColor.labelColor;
    }
}

- (void)reloadConfiguration {
    self.ballDiameter = MIN(100.0, MAX(40.0, [NSUserDefaults.standardUserDefaults doubleForKey:WCLiquidGlassWCGlassBallSizeKey] ?: 48.0));
    self.ballDocked = [NSUserDefaults.standardUserDefaults objectForKey:WCLiquidGlassWCGlassBallDockKey]
        ? [NSUserDefaults.standardUserDefaults boolForKey:WCLiquidGlassWCGlassBallDockKey]
        : YES;
    [self setNeedsLayout];
}

- (void)updateBallSymbolAnimated:(BOOL)animated {
    UIImage *image = self.expanded
        ? [UIImage systemImageNamed:@"xmark"]
        : WCLiquidGlassWCGlassBallIconImage(self.ballDiameter * 0.34);
    void (^change)(void) = ^{ self.ballIconView.image = image; };
    if (animated) {
        [UIView transitionWithView:self.ballIconView duration:0.16 options:UIViewAnimationOptionTransitionCrossDissolve animations:change completion:nil];
    } else {
        change();
    }
}

- (CGAffineTransform)collapsedMenuTransform {
    return CGAffineTransformMakeScale(0.86, 0.86);
}

- (void)rebuildActionButtons {
    [self.actionButtons makeObjectsPerformSelector:@selector(removeFromSuperview)];
    [self.actionButtons removeAllObjects];
    self.menuActions = WCLiquidGlassWCGlassVisibleActions();
    for (NSDictionary *item in self.menuActions) {
        NSString *identifier = item[@"action"];
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        button.configuration = [UIButtonConfiguration plainButtonConfiguration];
        button.configuration.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *attributes) {
            NSMutableDictionary *updated = [attributes mutableCopy];
            updated[NSFontAttributeName] = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
            return updated;
        };
        button.tintColor = UIColor.labelColor;
        button.accessibilityLabel = WCLiquidGlassActionTitle(identifier);
        button.configuration.title = WCLiquidGlassActionTitle(identifier);
        button.configuration.image = WCLiquidGlassImageForAction(identifier, 30.0);
        button.configuration.imagePlacement = NSDirectionalRectEdgeLeading;
        button.configuration.imagePadding = 10.0;
        button.configuration.contentInsets = NSDirectionalEdgeInsetsMake(0, 8, 0, 8);
        button.imageView.contentMode = UIViewContentModeScaleAspectFit;
        button.tag = [self.menuActions indexOfObject:item];
        [button addTarget:self action:@selector(actionButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.menuScrollView addSubview:button];
        [self.actionButtons addObject:button];
    }
    if (self.expanded) {
        [self layoutMenuPanel];
    }
}

- (void)layoutMenuPanel {
    if (!self.menuGlass) {
        return;
    }
    CGFloat height = MIN(420.0, MAX(72.0, 16.0 + self.actionButtons.count * 48.0));
    CGFloat width = MIN(260.0, MAX(210.0, CGRectGetWidth(self.bounds) - 32.0));
    CGFloat x = self.ballButton.center.x < CGRectGetMidX(self.bounds) ? 16.0 : CGRectGetWidth(self.bounds) - width - 16.0;
    CGFloat y = MIN(CGRectGetHeight(self.bounds) - height - 12.0, MAX(12.0, self.ballButton.center.y - height / 2.0));
    self.menuGlass.frame = CGRectMake(x, y, width, height);
    self.menuScrollView.frame = CGRectInset(self.menuGlass.bounds, 8.0, 8.0);
    self.menuScrollView.contentSize = CGSizeMake(self.menuScrollView.bounds.size.width, MAX(self.menuScrollView.bounds.size.height, self.actionButtons.count * 48.0));
    for (NSUInteger index = 0; index < self.actionButtons.count; index++) {
        self.actionButtons[index].frame = CGRectMake(0, index * 48.0, CGRectGetWidth(self.menuScrollView.bounds), 48.0);
    }
}

- (void)ballTapped:(__unused id)sender {
    self.expanded ? [self collapseAnimated:YES] : [self expandMenu];
}

- (void)ballLongPressed:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) {
        return;
    }
    UIViewController *visible = WCLiquidGlassWCGlassVisibleController();
    UINavigationController *navigation = visible.navigationController ?: WCLiquidGlassWCGlassNavigationController();
    if (!navigation) {
        return;
    }
    WCLiquidGlassWCGlassBallSettingsController *controller = [[WCLiquidGlassWCGlassBallSettingsController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    [navigation pushViewController:controller animated:YES];
}

- (void)expandMenu {
    if (self.expanded) {
        return;
    }
    self.expanded = YES;
    [self updateBallSymbolAnimated:YES];
    if (!self.dismissControl) {
        self.dismissControl = [UIButton buttonWithType:UIButtonTypeCustom];
        self.dismissControl.frame = self.bounds;
        self.dismissControl.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.dismissControl addTarget:self action:@selector(dismissAreaTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self insertSubview:self.dismissControl atIndex:0];
    }
    self.dismissControl.hidden = NO;
    if (!self.menuGlass) {
        self.menuGlass = [[UIVisualEffectView alloc] initWithEffect:WCLiquidGlassCurrentGlassEffect() ?: [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial]];
        self.menuGlass.layer.cornerRadius = 24.0;
        self.menuGlass.layer.masksToBounds = YES;
        self.menuScrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
        self.menuScrollView.alwaysBounceVertical = YES;
        [self.menuGlass.contentView addSubview:self.menuScrollView];
        [self insertSubview:self.menuGlass aboveSubview:self.dismissControl];
        [self bringSubviewToFront:self.ballGlass];
        [self bringSubviewToFront:self.ballButton];
    }
    [self rebuildActionButtons];
    self.menuGlass.hidden = NO;
    self.menuGlass.alpha = 0.0;
    self.menuGlass.transform = [self collapsedMenuTransform];
    [self layoutMenuPanel];
    [UIView animateWithDuration:0.24 animations:^{
        self.menuGlass.alpha = 1.0;
        self.menuGlass.transform = CGAffineTransformIdentity;
    }];
}

- (void)dismissAreaTapped:(__unused id)sender {
    [self collapseAnimated:YES];
}

- (void)collapseAnimated:(BOOL)animated {
    if (!self.expanded) {
        return;
    }
    self.expanded = NO;
    [self updateBallSymbolAnimated:YES];
    void (^animations)(void) = ^{
        self.menuGlass.alpha = 0.0;
        self.menuGlass.transform = [self collapsedMenuTransform];
    };
    void (^completion)(BOOL) = ^(__unused BOOL finished) {
        self.menuGlass.hidden = YES;
        self.dismissControl.hidden = YES;
        self.menuGlass.transform = CGAffineTransformIdentity;
    };
    if (animated) {
        [UIView animateWithDuration:0.18 animations:animations completion:completion];
    } else {
        animations();
        completion(YES);
    }
}

- (void)actionButtonTapped:(UIButton *)button {
    if (button.tag >= 0 && button.tag < (NSInteger)self.menuActions.count) {
        WCLiquidGlassWCGlassPerformAction(self.menuActions[(NSUInteger)button.tag][@"action"]);
    }
    [self collapseAnimated:YES];
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    if (self.expanded) {
        [self collapseAnimated:NO];
    }
    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.dragStartCenter = self.ballButton.center;
    }
    CGPoint translation = [gesture translationInView:self];
    if (gesture.state == UIGestureRecognizerStateChanged || gesture.state == UIGestureRecognizerStateEnded) {
        self.ballButton.center = [self clampedBallCenter:CGPointMake(self.dragStartCenter.x + translation.x,
                                                                      self.dragStartCenter.y + translation.y)];
    }
    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        if (self.ballDocked) {
            self.ballDockedLeft = self.ballButton.center.x < CGRectGetMidX(self.bounds);
            [self dockBallAnimated:YES];
        }
        [NSUserDefaults.standardUserDefaults setDouble:self.ballButton.center.x / MAX(CGRectGetWidth(self.bounds), 1.0) forKey:WCLiquidGlassWCGlassBallXKey];
        [NSUserDefaults.standardUserDefaults setDouble:self.ballButton.center.y / MAX(CGRectGetHeight(self.bounds), 1.0) forKey:WCLiquidGlassWCGlassBallYKey];
    }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return [gestureRecognizer isKindOfClass:UIPanGestureRecognizer.class] && [otherGestureRecognizer.view isEqual:self.ballButton];
}

@end

@implementation WCLiquidGlassWCGlassBallSettingsController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"悬浮球功能管理";
    self.items = WCLiquidGlassWCGlassAllActions();
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemEdit target:self action:@selector(toggleEditing)];
    self.tableView.rowHeight = 56.0;
}

- (void)toggleEditing {
    [self setEditing:!self.isEditing animated:YES];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 4 : self.items.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"悬浮球" : @"功能管理";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        static NSString *identifier = @"WCGlassBallSetting";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
        }
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.accessoryView = nil;
        if (indexPath.row == 0) {
            cell.textLabel.text = @"悬浮球";
            cell.detailTextLabel.text = @"在微信所有页面常驻；拖动位置，点按展开玻璃菜单";
            UISwitch *toggle = [[UISwitch alloc] init];
            toggle.on = WCLiquidGlassWCGlassFloatingBallManager.sharedManager.isEnabled;
            toggle.tag = 100;
            [toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = toggle;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"悬浮球大小";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f pt", MAX(40.0, MIN(100.0, [NSUserDefaults.standardUserDefaults doubleForKey:WCLiquidGlassWCGlassBallSizeKey] ?: 48.0))];
            UIStepper *stepper = [[UIStepper alloc] init];
            stepper.minimumValue = 40.0;
            stepper.maximumValue = 100.0;
            stepper.stepValue = 1.0;
            stepper.value = [NSUserDefaults.standardUserDefaults doubleForKey:WCLiquidGlassWCGlassBallSizeKey] ?: 48.0;
            stepper.tag = 101;
            [stepper addTarget:self action:@selector(sizeChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = stepper;
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"悬浮球吸边";
            cell.detailTextLabel.text = @"开启后松手吸到屏幕边缘；关闭后停在拖动位置";
            UISwitch *toggle = [[UISwitch alloc] init];
            toggle.on = [NSUserDefaults.standardUserDefaults objectForKey:WCLiquidGlassWCGlassBallDockKey]
                ? [NSUserDefaults.standardUserDefaults boolForKey:WCLiquidGlassWCGlassBallDockKey]
                : YES;
            toggle.tag = 102;
            [toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = toggle;
        } else {
            cell.textLabel.text = @"悬浮球图标";
            cell.detailTextLabel.text = [NSUserDefaults.standardUserDefaults stringForKey:WCLiquidGlassWCGlassBallIconKey] ?: @"ellipsis";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        }
        return cell;
    }

    static NSString *identifier = @"WCGlassBallAction";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
        UISwitch *toggle = [[UISwitch alloc] init];
        [toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
    }
    NSDictionary *item = self.items[(NSUInteger)indexPath.row];
    NSString *action = item[@"action"];
    cell.textLabel.text = WCLiquidGlassActionTitle(action);
    cell.imageView.image = WCLiquidGlassImageForAction(action, 28.0);
    cell.imageView.tintColor = UIColor.labelColor;
    ((UISwitch *)cell.accessoryView).on = ![item[@"hidden"] boolValue];
    ((UISwitch *)cell.accessoryView).tag = 1000 + indexPath.row;
    return cell;
}

- (void)toggleChanged:(UISwitch *)toggle {
    if (toggle.tag == 100) {
        [[WCLiquidGlassWCGlassFloatingBallManager sharedManager] setEnabled:toggle.isOn];
        return;
    }
    if (toggle.tag == 102) {
        [NSUserDefaults.standardUserDefaults setBool:toggle.isOn forKey:WCLiquidGlassWCGlassBallDockKey];
        [[WCLiquidGlassWCGlassFloatingBallManager sharedManager] refresh];
        return;
    }
    NSInteger index = toggle.tag - 1000;
    if (index < 0 || index >= (NSInteger)self.items.count) {
        return;
    }
    NSMutableArray *items = [self.items mutableCopy];
    NSMutableDictionary *item = [items[(NSUInteger)index] mutableCopy];
    item[@"hidden"] = @(!toggle.isOn);
    items[(NSUInteger)index] = item.copy;
    self.items = items.copy;
    [NSUserDefaults.standardUserDefaults setObject:self.items forKey:WCLiquidGlassWCGlassBallActionsKey];
    [[WCLiquidGlassWCGlassFloatingBallManager sharedManager] refresh];
}

- (void)sizeChanged:(UIStepper *)stepper {
    [NSUserDefaults.standardUserDefaults setDouble:stepper.value forKey:WCLiquidGlassWCGlassBallSizeKey];
    [[WCLiquidGlassWCGlassFloatingBallManager sharedManager] refresh];
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:1 inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 1;
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath {
    if (sourceIndexPath.section != 1 || destinationIndexPath.section != 1) {
        return;
    }
    NSMutableArray *items = [self.items mutableCopy];
    NSDictionary *item = items[(NSUInteger)sourceIndexPath.row];
    [items removeObjectAtIndex:(NSUInteger)sourceIndexPath.row];
    [items insertObject:item atIndex:(NSUInteger)destinationIndexPath.row];
    self.items = items.copy;
    [NSUserDefaults.standardUserDefaults setObject:self.items forKey:WCLiquidGlassWCGlassBallActionsKey];
    [[WCLiquidGlassWCGlassFloatingBallManager sharedManager] refresh];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 0 || indexPath.row != 3) {
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"悬浮球图标" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray<NSString *> *symbols = @[@"ellipsis", @"circle.grid.cross.fill", @"drop.fill", @"rectangle.3.group.bubble.left"];
    for (NSString *symbol in symbols) {
        [alert addAction:[UIAlertAction actionWithTitle:symbol style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            [NSUserDefaults.standardUserDefaults setObject:symbol forKey:WCLiquidGlassWCGlassBallIconKey];
            [[WCLiquidGlassWCGlassFloatingBallManager sharedManager] refresh];
            [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:3 inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

@interface WCLiquidGlassWCGlassFloatingBallManager ()
@property(nonatomic, strong) WCLiquidGlassWCGlassBallPassthroughView *overlayView;
@property(nonatomic, strong) WCLiquidGlassWCGlassFloatingBall *ballView;
@property(nonatomic, weak) UIWindow *hostWindow;
@property(nonatomic, assign, getter=isEnabled) BOOL enabled;
@end

@implementation WCLiquidGlassWCGlassFloatingBallManager

+ (instancetype)sharedManager {
    static WCLiquidGlassWCGlassFloatingBallManager *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ manager = [[self alloc] init]; });
    return manager;
}

- (void)install {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        if ([defaults objectForKey:WCLiquidGlassWCGlassBallEnabledKey] == nil) {
            [defaults setBool:NO forKey:WCLiquidGlassWCGlassBallEnabledKey];
        }
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:UIApplicationDidBecomeActiveNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:UIWindowDidBecomeKeyNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:WCLiquidGlassPreferencesDidChangeNotification object:nil];
    });
    self.enabled = [NSUserDefaults.standardUserDefaults boolForKey:WCLiquidGlassWCGlassBallEnabledKey];
    [self refresh];
}

- (void)setEnabled:(BOOL)enabled {
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:WCLiquidGlassWCGlassBallEnabledKey];
    _enabled = enabled;
    [self refresh];
}

- (void)refresh {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self refresh]; });
        return;
    }
    _enabled = [NSUserDefaults.standardUserDefaults boolForKey:WCLiquidGlassWCGlassBallEnabledKey];
    if (!self.enabled) {
        [self.overlayView removeFromSuperview];
        self.overlayView = nil;
        self.ballView = nil;
        self.hostWindow = nil;
        return;
    }
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState == UISceneActivationStateUnattached) {
            continue;
        }
        for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
            if (candidate.isKeyWindow && candidate.windowLevel == UIWindowLevelNormal) {
                window = candidate;
                break;
            }
        }
        if (window) {
            break;
        }
    }
    if (!window || !window.rootViewController.viewIfLoaded) {
        return;
    }
    if (self.hostWindow != window) {
        [self.overlayView removeFromSuperview];
        self.hostWindow = window;
        self.overlayView = [[WCLiquidGlassWCGlassBallPassthroughView alloc] initWithFrame:window.bounds];
        self.overlayView.backgroundColor = UIColor.clearColor;
        self.overlayView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.ballView = [[WCLiquidGlassWCGlassFloatingBall alloc] initWithFrame:self.overlayView.bounds];
        self.ballView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.overlayView addSubview:self.ballView];
    }
    if (self.overlayView.superview != window.rootViewController.view) {
        [self.overlayView removeFromSuperview];
        [window.rootViewController.view addSubview:self.overlayView];
    }
    [window.rootViewController.view bringSubviewToFront:self.overlayView];
    [self.ballView reloadConfiguration];
    [self.ballView rebuildActionButtons];
    [self.ballView refreshAppearance];
}

@end
