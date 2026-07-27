#import "WCLiquidGlassHomeCorners.h"

#import <CydiaSubstrate.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "WCLiquidGlassMenu.h"
#import "WCLiquidGlassPreferences.h"

static const void *WCLiquidGlassHomeCornerStateKey = &WCLiquidGlassHomeCornerStateKey;
static const void *WCLiquidGlassHomeCornerTableStyledKey = &WCLiquidGlassHomeCornerTableStyledKey;
static const void *WCLiquidGlassHomeCornerTableRoleKey = &WCLiquidGlassHomeCornerTableRoleKey;
static const void *WCLiquidGlassHomeCornerTableRoleEpochKey = &WCLiquidGlassHomeCornerTableRoleEpochKey;
static void (*WCLiquidGlassOriginalHomeCornersTableLayoutSubviews)(UITableView *, SEL) = NULL;
static BOOL WCLiquidGlassHomeCornersHooksInstalled = NO;
static BOOL WCLiquidGlassHomeCornersHookRetryScheduled = NO;
static NSUInteger WCLiquidGlassHomeCornersHookInstallAttempts = 0;
static NSUInteger WCLiquidGlassHomeCornersConfigurationEpoch = 1;
static UIColor *WCLiquidGlassHomeCornerColorFromHex(NSString *hex);

typedef NS_ENUM(NSInteger, WCLiquidGlassHomeCornerTableRole) {
    WCLiquidGlassHomeCornerTableRoleNone = 0,
    WCLiquidGlassHomeCornerTableRoleHome,
    WCLiquidGlassHomeCornerTableRoleOtherTab
};

@interface WCLiquidGlassHomeCornerBackgroundView : UIView
@property(nonatomic, strong) UIVisualEffectView *effectView;
@property(nonatomic, assign) NSInteger visualState;
- (void)wc_updateAppearance;
@end

@implementation WCLiquidGlassHomeCornerBackgroundView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _effectView = [[UIVisualEffectView alloc] initWithEffect:nil];
        _effectView.frame = self.bounds;
        _effectView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _effectView.userInteractionEnabled = NO;
        _visualState = NSIntegerMin;
        [self addSubview:_effectView];
    }
    return self;
}

- (void)wc_updateAppearance {
    BOOL liquid = WCLiquidGlassPreferences.homeLiquidBackgroundEnabled;
    NSInteger state = liquid
        ? WCLiquidGlassPreferences.glassAppearance * 10 + self.traitCollection.userInterfaceStyle
        : -((NSInteger)WCLiquidGlassPreferences.homeCardBackgroundColorHex.hash + 2);
    if (self.visualState == state) {
        return;
    }
    self.visualState = state;
    self.effectView.hidden = !liquid;
    self.effectView.effect = liquid ? WCLiquidGlassCurrentGlassEffect() : nil;
    UIColor *backgroundColor = liquid ? UIColor.clearColor : WCLiquidGlassHomeCornerColorFromHex(WCLiquidGlassPreferences.homeCardBackgroundColorHex);
    if (![self.backgroundColor isEqual:backgroundColor]) {
        self.backgroundColor = backgroundColor;
    }
}

@end

@interface WCLiquidGlassHomeCornerCellState : NSObject
@property(nonatomic, assign) CGRect baseFrame;
@property(nonatomic, assign) CGRect appliedFrame;
@property(nonatomic, assign) BOOL hasAppliedFrame;
@property(nonatomic, strong, nullable) UIView *originalBackgroundView;
@property(nonatomic, strong, nullable) UIColor *originalBackgroundColor;
@property(nonatomic, strong, nullable) UIColor *originalContentBackgroundColor;
@property(nonatomic, assign) CGFloat originalCornerRadius;
@property(nonatomic, assign) CACornerMask originalMaskedCorners;
@property(nonatomic, assign) BOOL originalMasksToBounds;
@property(nonatomic, strong, nullable) WCLiquidGlassHomeCornerBackgroundView *cardBackground;
@property(nonatomic, assign) BOOL captured;
@end

@implementation WCLiquidGlassHomeCornerCellState
@end

static UIColor *WCLiquidGlassHomeCornerColorFromHex(NSString *hex) {
    NSString *value = [[hex stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
        stringByReplacingOccurrencesOfString:@"#" withString:@""];
    if (value.length != 6) {
        return UIColor.systemBackgroundColor;
    }
    unsigned int rgb = 0;
    [[NSScanner scannerWithString:value] scanHexInt:&rgb];
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:1.0];
}

static BOOL WCLiquidGlassHomeCornerNameContains(NSString *name, NSArray<NSString *> *tokens) {
    NSString *lowercaseName = name.lowercaseString;
    for (NSString *token in tokens) {
        if ([lowercaseName containsString:token]) {
            return YES;
        }
    }
    return NO;
}

static WCLiquidGlassHomeCornerTableRole WCLiquidGlassHomeCornerUncachedRoleForTable(UITableView *tableView) {
    if (!WCLiquidGlassPreferences.homeCornersEnabled) {
        return WCLiquidGlassHomeCornerTableRoleNone;
    }
    Class homeTableClass = NSClassFromString(@"MainFrameTableView");
    if (homeTableClass && [tableView isKindOfClass:homeTableClass]) {
        return WCLiquidGlassHomeCornerTableRoleHome;
    }
    if (!WCLiquidGlassPreferences.homeCornersSyncOtherTabsEnabled) {
        return WCLiquidGlassHomeCornerTableRoleNone;
    }
    BOOL belongsToMainFrame = NO;
    BOOL otherTabController = NO;
    for (UIResponder *responder = tableView.nextResponder;
         responder;
         responder = responder.nextResponder) {
        NSString *name = NSStringFromClass(responder.class);
        if ([name isEqualToString:@"NewMainFrameViewController"]) {
            belongsToMainFrame = YES;
        }
        if (WCLiquidGlassHomeCornerNameContains(name, @[@"findfriend", @"contact", @"more"])) {
            otherTabController = YES;
        }
    }
    return belongsToMainFrame && otherTabController
        ? WCLiquidGlassHomeCornerTableRoleOtherTab
        : WCLiquidGlassHomeCornerTableRoleNone;
}

static WCLiquidGlassHomeCornerTableRole WCLiquidGlassHomeCornerRoleForTable(UITableView *tableView) {
    NSNumber *cachedEpoch = objc_getAssociatedObject(tableView, WCLiquidGlassHomeCornerTableRoleEpochKey);
    if (cachedEpoch.unsignedIntegerValue == WCLiquidGlassHomeCornersConfigurationEpoch) {
        return [objc_getAssociatedObject(tableView, WCLiquidGlassHomeCornerTableRoleKey) integerValue];
    }
    WCLiquidGlassHomeCornerTableRole role = WCLiquidGlassHomeCornerUncachedRoleForTable(tableView);
    objc_setAssociatedObject(tableView,
                             WCLiquidGlassHomeCornerTableRoleKey,
                             @(role),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(tableView,
                             WCLiquidGlassHomeCornerTableRoleEpochKey,
                             @(WCLiquidGlassHomeCornersConfigurationEpoch),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return role;
}

static WCLiquidGlassHomeCornerCellState *WCLiquidGlassHomeCornerStateForCell(UITableViewCell *cell) {
    WCLiquidGlassHomeCornerCellState *state = objc_getAssociatedObject(cell, WCLiquidGlassHomeCornerStateKey);
    if (!state) {
        state = [[WCLiquidGlassHomeCornerCellState alloc] init];
        objc_setAssociatedObject(cell,
                                 WCLiquidGlassHomeCornerStateKey,
                                 state,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!state.captured) {
        state.originalBackgroundView = cell.backgroundView;
        state.originalBackgroundColor = cell.backgroundColor;
        state.originalContentBackgroundColor = cell.contentView.backgroundColor;
        state.originalCornerRadius = cell.layer.cornerRadius;
        state.originalMaskedCorners = cell.layer.maskedCorners;
        state.originalMasksToBounds = cell.layer.masksToBounds;
        state.captured = YES;
    }
    return state;
}

static void WCLiquidGlassHomeCornerRestoreCell(UITableViewCell *cell) {
    WCLiquidGlassHomeCornerCellState *state = objc_getAssociatedObject(cell, WCLiquidGlassHomeCornerStateKey);
    if (!state || !state.captured) {
        return;
    }
    if (state.hasAppliedFrame && CGRectEqualToRect(cell.frame, state.appliedFrame)) {
        cell.frame = state.baseFrame;
    }
    cell.backgroundView = state.originalBackgroundView;
    cell.backgroundColor = state.originalBackgroundColor;
    cell.contentView.backgroundColor = state.originalContentBackgroundColor;
    cell.layer.cornerRadius = state.originalCornerRadius;
    cell.layer.maskedCorners = state.originalMaskedCorners;
    cell.layer.masksToBounds = state.originalMasksToBounds;
    state.hasAppliedFrame = NO;
}

static CGRect WCLiquidGlassHomeCornerBaseFrame(UITableViewCell *cell,
                                               WCLiquidGlassHomeCornerCellState *state) {
    CGRect currentFrame = cell.frame;
    if (state.hasAppliedFrame && CGRectEqualToRect(currentFrame, state.appliedFrame)) {
        return state.baseFrame;
    }
    return currentFrame;
}

static void WCLiquidGlassHomeCornerApplyCell(UITableView *tableView,
                                             UITableViewCell *cell,
                                             WCLiquidGlassHomeCornerTableRole role) {
    NSIndexPath *indexPath = [tableView indexPathForCell:cell];
    if (!indexPath) {
        return;
    }
    WCLiquidGlassHomeCornerCellState *state = WCLiquidGlassHomeCornerStateForCell(cell);
    CGRect baseFrame = WCLiquidGlassHomeCornerBaseFrame(cell, state);
    BOOL home = role == WCLiquidGlassHomeCornerTableRoleHome;
    CGFloat inset = home ? WCLiquidGlassPreferences.homeCornerInset : WCLiquidGlassPreferences.homeCornerInset;
    CGFloat radius = home ? WCLiquidGlassPreferences.homeCornerRadius : WCLiquidGlassPreferences.homeOtherTabsCornerRadius;
    BOOL separate = home && WCLiquidGlassPreferences.homeSeparateCardsEnabled;
    CGFloat gap = separate ? WCLiquidGlassPreferences.homeCardGap : 0.0;
    CGRect targetFrame = baseFrame;
    targetFrame.origin.x = inset;
    targetFrame.size.width = MAX(0.0, CGRectGetWidth(tableView.bounds) - inset * 2.0);
    if (gap > 0.0) {
        CGFloat halfGap = gap * 0.5;
        targetFrame.origin.y += halfGap;
        targetFrame.size.height = MAX(1.0, targetFrame.size.height - gap);
    }
    targetFrame = CGRectIntegral(targetFrame);
    if (!CGRectEqualToRect(cell.frame, targetFrame)) {
        cell.frame = targetFrame;
    }
    state.baseFrame = baseFrame;
    state.appliedFrame = targetFrame;
    state.hasAppliedFrame = YES;

    NSInteger rows = [tableView numberOfRowsInSection:indexPath.section];
    BOOL first = indexPath.row == 0;
    BOOL last = indexPath.row == rows - 1;
    CACornerMask corners = 0;
    if (separate || rows <= 1) {
        corners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner |
            kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    } else if (first) {
        corners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    } else if (last) {
        corners = kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    }
    cell.layer.cornerRadius = corners ? radius : 0.0;
    cell.layer.cornerCurve = kCACornerCurveContinuous;
    cell.layer.maskedCorners = corners;
    cell.layer.masksToBounds = corners != 0;
    cell.backgroundColor = UIColor.clearColor;
    cell.contentView.backgroundColor = UIColor.clearColor;
    if (!state.cardBackground) {
        state.cardBackground = [[WCLiquidGlassHomeCornerBackgroundView alloc] initWithFrame:CGRectZero];
    }
    [state.cardBackground wc_updateAppearance];
    if (cell.backgroundView != state.cardBackground) {
        cell.backgroundView = state.cardBackground;
    }
}

static void WCLiquidGlassHomeCornersUpdateTable(UITableView *tableView) {
    WCLiquidGlassHomeCornerTableRole role = WCLiquidGlassHomeCornerRoleForTable(tableView);
    BOOL wasStyled = [objc_getAssociatedObject(tableView, WCLiquidGlassHomeCornerTableStyledKey) boolValue];
    if (role == WCLiquidGlassHomeCornerTableRoleNone && !wasStyled) {
        return;
    }
    if (role != WCLiquidGlassHomeCornerTableRoleNone) {
        objc_setAssociatedObject(tableView,
                                 WCLiquidGlassHomeCornerTableStyledKey,
                                 @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    for (UITableViewCell *cell in tableView.visibleCells) {
        if (role == WCLiquidGlassHomeCornerTableRoleNone) {
            WCLiquidGlassHomeCornerRestoreCell(cell);
        } else {
            WCLiquidGlassHomeCornerApplyCell(tableView, cell, role);
        }
    }
    if (role == WCLiquidGlassHomeCornerTableRoleNone) {
        objc_setAssociatedObject(tableView,
                                 WCLiquidGlassHomeCornerTableStyledKey,
                                 @NO,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void WCLiquidGlassHomeCornersTableLayoutSubviews(UITableView *self, SEL selector) {
    if (WCLiquidGlassOriginalHomeCornersTableLayoutSubviews) {
        WCLiquidGlassOriginalHomeCornersTableLayoutSubviews(self, selector);
    }
    WCLiquidGlassHomeCornersUpdateTable(self);
}

static void WCLiquidGlassHomeCornersRefreshTablesInView(UIView *view, NSUInteger depth) {
    if (!view || depth > 24) {
        return;
    }
    if ([view isKindOfClass:UITableView.class]) {
        WCLiquidGlassHomeCornersUpdateTable((UITableView *)view);
    }
    for (UIView *subview in view.subviews) {
        WCLiquidGlassHomeCornersRefreshTablesInView(subview, depth + 1);
    }
}

static void WCLiquidGlassHomeCornersRefreshVisibleTables(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) {
            continue;
        }
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            WCLiquidGlassHomeCornersRefreshTablesInView(window, 0);
        }
    }
}

void WCLiquidGlassInstallHomeCornersHooks(void) {
    if (WCLiquidGlassHomeCornersHooksInstalled) {
        return;
    }
    Method layoutMethod = class_getInstanceMethod(UITableView.class, @selector(layoutSubviews));
    if (!layoutMethod) {
        if (!WCLiquidGlassHomeCornersHookRetryScheduled && WCLiquidGlassHomeCornersHookInstallAttempts < 10) {
            WCLiquidGlassHomeCornersHookRetryScheduled = YES;
            WCLiquidGlassHomeCornersHookInstallAttempts += 1;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                WCLiquidGlassHomeCornersHookRetryScheduled = NO;
                WCLiquidGlassInstallHomeCornersHooks();
            });
        }
        return;
    }
    MSHookMessageEx(UITableView.class,
                    @selector(layoutSubviews),
                    (IMP)&WCLiquidGlassHomeCornersTableLayoutSubviews,
                    (IMP *)&WCLiquidGlassOriginalHomeCornersTableLayoutSubviews);
    WCLiquidGlassHomeCornersHooksInstalled = WCLiquidGlassOriginalHomeCornersTableLayoutSubviews != NULL;
    if (WCLiquidGlassHomeCornersHooksInstalled) {
        [NSNotificationCenter.defaultCenter addObserverForName:WCLiquidGlassPreferencesDidChangeNotification
                                                          object:nil
                                                           queue:NSOperationQueue.mainQueue
                                                      usingBlock:^(__unused NSNotification *notification) {
            WCLiquidGlassHomeCornersConfigurationEpoch += 1;
            WCLiquidGlassHomeCornersRefreshVisibleTables();
        }];
    }
}

typedef NS_ENUM(NSInteger, WCLiquidGlassHomeCornersControlTag) {
    WCLiquidGlassHomeCornersControlTagInset = 1,
    WCLiquidGlassHomeCornersControlTagHomeRadius,
    WCLiquidGlassHomeCornersControlTagOtherTabsRadius
};

static NSString *WCLiquidGlassHomeCornersDisplayValue(CGFloat value) {
    return [NSString stringWithFormat:@"%.0f pt", value];
}

@implementation WCLiquidGlassHomeCornersController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"首页圆角";
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 64.0;
    self.tableView.separatorColor = [UIColor.separatorColor colorWithAlphaComponent:0.30];
    [WCLiquidGlassPreferences registerDefaults];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(wc_preferencesChanged:)
                                               name:WCLiquidGlassPreferencesDidChangeNotification
                                             object:nil];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 8 : 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"卡片化主页列表" : @"同步到发现/通讯录/我";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return @"会话行两侧缩进并呈现圆角卡片。开启“液态背景”后，背景会跟随插件“液态效果”设置；背景颜色与它互斥。";
    }
    return @"同步后，发现、通讯录和我页面会使用相同的卡片背景与左右缩进；圆角可单独调整。";
}

- (UITableViewCell *)wc_cellWithTitle:(NSString *)title
                                detail:(nullable NSString *)detail
                               enabled:(BOOL)enabled
                            identifier:(NSString *)identifier {
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    }
    cell.textLabel.text = title;
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.textLabel.adjustsFontForContentSizeCategory = YES;
    cell.detailTextLabel.text = detail;
    cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
    cell.textLabel.textColor = enabled ? UIColor.labelColor : UIColor.tertiaryLabelColor;
    cell.detailTextLabel.textColor = enabled ? UIColor.secondaryLabelColor : UIColor.tertiaryLabelColor;
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = enabled ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    cell.userInteractionEnabled = enabled;
    return cell;
}

- (UITableViewCell *)wc_switchCellWithTitle:(NSString *)title
                                      detail:(nullable NSString *)detail
                                         on:(BOOL)on
                                     enabled:(BOOL)enabled
                                     action:(SEL)action {
    UITableViewCell *cell = [self wc_cellWithTitle:title detail:detail enabled:enabled identifier:@"WCLiquidGlassHomeCornersSwitchCell"];
    UISwitch *toggle = [[UISwitch alloc] init];
    toggle.on = on;
    toggle.enabled = enabled;
    [toggle addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = toggle;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (UITableViewCell *)wc_sliderCellWithTitle:(NSString *)title
                                       value:(CGFloat)value
                                     minimum:(CGFloat)minimum
                                     maximum:(CGFloat)maximum
                                         tag:(WCLiquidGlassHomeCornersControlTag)tag
                                     enabled:(BOOL)enabled {
    UITableViewCell *cell = [self wc_cellWithTitle:title
                                             detail:WCLiquidGlassHomeCornersDisplayValue(value)
                                            enabled:enabled
                                         identifier:@"WCLiquidGlassHomeCornersSliderCell"];
    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(0.0, 0.0, 152.0, 31.0)];
    slider.minimumValue = minimum;
    slider.maximumValue = maximum;
    slider.value = value;
    slider.tag = tag;
    slider.enabled = enabled;
    [slider addTarget:self action:@selector(wc_sliderChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = slider;
    cell.accessibilityHint = enabled ? @"点按滑块外的区域可直接输入数值" : nil;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    BOOL active = WCLiquidGlassPreferences.homeCornersEnabled;
    if (indexPath.section == 0) {
        switch (indexPath.row) {
            case 0:
                return [self wc_switchCellWithTitle:@"卡片化主页列表"
                                               detail:@"会话行两侧缩进并加圆角卡片"
                                                  on:active
                                              enabled:YES
                                              action:@selector(wc_homeCornersChanged:)];
            case 1:
                return [self wc_sliderCellWithTitle:@"左右缩进"
                                               value:WCLiquidGlassPreferences.homeCornerInset
                                             minimum:0.0
                                             maximum:32.0
                                                 tag:WCLiquidGlassHomeCornersControlTagInset
                                             enabled:active];
            case 2:
                return [self wc_sliderCellWithTitle:@"主页圆角"
                                               value:WCLiquidGlassPreferences.homeCornerRadius
                                             minimum:0.0
                                             maximum:52.0
                                                 tag:WCLiquidGlassHomeCornersControlTagHomeRadius
                                             enabled:active];
            case 3:
                return [self wc_switchCellWithTitle:@"每条独立圆角卡片"
                                               detail:@"每条会话独立成圆角卡片，可设置会话间距"
                                                  on:WCLiquidGlassPreferences.homeSeparateCardsEnabled
                                              enabled:active
                                              action:@selector(wc_separateCardsChanged:)];
            case 4: {
                UITableViewCell *cell = [self wc_cellWithTitle:@"会话间距"
                                                         detail:WCLiquidGlassHomeCornersDisplayValue(WCLiquidGlassPreferences.homeCardGap)
                                                        enabled:active
                                                     identifier:@"WCLiquidGlassHomeCornersValueCell"];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                return cell;
            }
            case 5:
                return [self wc_switchCellWithTitle:@"置顶会话间隙"
                                               detail:@"置顶与普通会话之间保留卡片间距；关闭则连续显示"
                                                  on:WCLiquidGlassPreferences.homePinnedCardGapEnabled
                                              enabled:active && WCLiquidGlassPreferences.homeSeparateCardsEnabled
                                              action:@selector(wc_pinnedGapChanged:)];
            case 6:
                return [self wc_switchCellWithTitle:@"液态背景"
                                               detail:@"卡片背景跟随“液态效果”"
                                                  on:WCLiquidGlassPreferences.homeLiquidBackgroundEnabled
                                              enabled:active
                                              action:@selector(wc_liquidBackgroundChanged:)];
            default: {
                BOOL colorEnabled = active && !WCLiquidGlassPreferences.homeLiquidBackgroundEnabled;
                UITableViewCell *cell = [self wc_cellWithTitle:@"背景颜色"
                                                         detail:WCLiquidGlassPreferences.homeCardBackgroundColorHex
                                                        enabled:colorEnabled
                                                     identifier:@"WCLiquidGlassHomeCornersColorCell"];
                cell.accessoryType = colorEnabled ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
                return cell;
            }
        }
    }
    if (indexPath.row == 0) {
        return [self wc_switchCellWithTitle:@"同步到发现/通讯录/我"
                                       detail:@"这三页也套用卡片样式（圆角可在下方单独调整）"
                                          on:WCLiquidGlassPreferences.homeCornersSyncOtherTabsEnabled
                                      enabled:active
                                      action:@selector(wc_syncOtherTabsChanged:)];
    }
    return [self wc_sliderCellWithTitle:@"发现/通讯录/我 圆角"
                                   value:WCLiquidGlassPreferences.homeOtherTabsCornerRadius
                                 minimum:0.0
                                 maximum:52.0
                                     tag:WCLiquidGlassHomeCornersControlTagOtherTabsRadius
                                 enabled:active && WCLiquidGlassPreferences.homeCornersSyncOtherTabsEnabled];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0 && indexPath.row == 1) {
        [self wc_presentValueInputWithTitle:@"左右缩进" value:WCLiquidGlassPreferences.homeCornerInset minimum:0.0 maximum:32.0 setter:^(CGFloat value) {
            [WCLiquidGlassPreferences setHomeCornerInset:value];
        }];
    } else if (indexPath.section == 0 && indexPath.row == 2) {
        [self wc_presentValueInputWithTitle:@"主页圆角" value:WCLiquidGlassPreferences.homeCornerRadius minimum:0.0 maximum:52.0 setter:^(CGFloat value) {
            [WCLiquidGlassPreferences setHomeCornerRadius:value];
        }];
    } else if (indexPath.section == 0 && indexPath.row == 4) {
        [self wc_presentValueInputWithTitle:@"会话间距" value:WCLiquidGlassPreferences.homeCardGap minimum:0.0 maximum:24.0 setter:^(CGFloat value) {
            [WCLiquidGlassPreferences setHomeCardGap:value];
        }];
    } else if (indexPath.section == 0 && indexPath.row == 7) {
        [self wc_presentBackgroundColorInput];
    } else if (indexPath.section == 1 && indexPath.row == 1) {
        [self wc_presentValueInputWithTitle:@"发现/通讯录/我 圆角" value:WCLiquidGlassPreferences.homeOtherTabsCornerRadius minimum:0.0 maximum:52.0 setter:^(CGFloat value) {
            [WCLiquidGlassPreferences setHomeOtherTabsCornerRadius:value];
        }];
    }
}

- (void)wc_homeCornersChanged:(UISwitch *)sender {
    [WCLiquidGlassPreferences setHomeCornersEnabled:sender.isOn];
}

- (void)wc_separateCardsChanged:(UISwitch *)sender {
    [WCLiquidGlassPreferences setHomeSeparateCardsEnabled:sender.isOn];
}

- (void)wc_pinnedGapChanged:(UISwitch *)sender {
    [WCLiquidGlassPreferences setHomePinnedCardGapEnabled:sender.isOn];
}

- (void)wc_liquidBackgroundChanged:(UISwitch *)sender {
    [WCLiquidGlassPreferences setHomeLiquidBackgroundEnabled:sender.isOn];
}

- (void)wc_syncOtherTabsChanged:(UISwitch *)sender {
    [WCLiquidGlassPreferences setHomeCornersSyncOtherTabsEnabled:sender.isOn];
}

- (void)wc_sliderChanged:(UISlider *)slider {
    CGFloat value = round(slider.value);
    [slider setValue:value animated:NO];
    switch (slider.tag) {
        case WCLiquidGlassHomeCornersControlTagInset:
            [WCLiquidGlassPreferences setHomeCornerInset:value];
            break;
        case WCLiquidGlassHomeCornersControlTagHomeRadius:
            [WCLiquidGlassPreferences setHomeCornerRadius:value];
            break;
        case WCLiquidGlassHomeCornersControlTagOtherTabsRadius:
            [WCLiquidGlassPreferences setHomeOtherTabsCornerRadius:value];
            break;
    }
}

- (void)wc_presentValueInputWithTitle:(NSString *)title
                                 value:(CGFloat)value
                               minimum:(CGFloat)minimum
                               maximum:(CGFloat)maximum
                                setter:(void (^)(CGFloat value))setter {
    NSString *message = [NSString stringWithFormat:@"输入 %.0f–%.0f 之间的 pt 数值", minimum, maximum];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.keyboardType = UIKeyboardTypeDecimalPad;
        textField.text = [NSString stringWithFormat:@"%.0f", value];
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        CGFloat enteredValue = alert.textFields.firstObject.text.doubleValue;
        setter(MIN(maximum, MAX(minimum, enteredValue)));
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)wc_presentBackgroundColorInput {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"背景颜色"
                                                                   message:@"输入十六进制颜色，例如 #FFFFFF"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
        textField.text = WCLiquidGlassPreferences.homeCardBackgroundColorHex;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSString *value = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (![value hasPrefix:@"#"]) {
            value = [@"#" stringByAppendingString:value];
        }
        NSRegularExpression *pattern = [NSRegularExpression regularExpressionWithPattern:@"^#[0-9A-Fa-f]{6}$" options:0 error:nil];
        if ([pattern firstMatchInString:value options:0 range:NSMakeRange(0, value.length)]) {
            [WCLiquidGlassPreferences setHomeCardBackgroundColorHex:value];
        }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)wc_preferencesChanged:(NSNotification *)notification {
    [self.tableView reloadData];
}

@end
