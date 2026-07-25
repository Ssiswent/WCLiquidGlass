#import "WCLiquidGlass.h"
#import "WCLiquidGlassCrashLogger.h"
#import "WCLiquidGlassMenu.h"
#import "WCLiquidGlassPreferences.h"

static const NSUInteger WCLiquidGlassMaximumButtonCount = 12;

#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>

#ifndef WCLIQUIDGLASS_VERSION
#define WCLIQUIDGLASS_VERSION "Unknown"
#endif

static UIColor *WCLiquidGlassBackdropTopColor(UITraitCollection *traits) {
    return traits.userInterfaceStyle == UIUserInterfaceStyleDark
        ? [UIColor colorWithRed:0.12 green:0.07 blue:0.04 alpha:1.0]
        : [UIColor colorWithRed:1.0 green:0.94 blue:0.84 alpha:1.0];
}

static UIColor *WCLiquidGlassBackdropBaseColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return WCLiquidGlassBackdropTopColor(traits);
    }];
}

@interface WCLiquidGlassBackdropView : UIView
@end

@implementation WCLiquidGlassBackdropView

+ (Class)layerClass {
    return CAGradientLayer.class;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self wc_updateColors];
    }
    return self;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self wc_updateColors];
    }
}

- (void)wc_updateColors {
    BOOL dark = self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    CAGradientLayer *gradient = (CAGradientLayer *)self.layer;
    gradient.colors = dark
        ? @[(id)WCLiquidGlassBackdropTopColor(self.traitCollection).CGColor,
            (id)[UIColor colorWithRed:0.025 green:0.025 blue:0.04 alpha:1.0].CGColor]
        : @[(id)WCLiquidGlassBackdropTopColor(self.traitCollection).CGColor,
            (id)[UIColor colorWithRed:0.94 green:0.95 blue:1.0 alpha:1.0].CGColor];
    gradient.startPoint = CGPointMake(0.0, 0.0);
    gradient.endPoint = CGPointMake(1.0, 1.0);
}

@end

static UIVisualEffect *WCLiquidGlassSettingsEffect(void) {
    Class glassClass = NSClassFromString(@"UIGlassEffect");
    SEL selector = NSSelectorFromString(@"effectWithStyle:");
    if (glassClass && [glassClass respondsToSelector:selector]) {
        UIVisualEffect *effect = ((id (*)(id, SEL, NSInteger))objc_msgSend)(glassClass, selector, 0);
        if (effect) {
            return effect;
        }
    }
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
}

static UIFont *WCLiquidGlassFont(CGFloat size, UIFontWeight weight);

static UIFontTextStyle WCLiquidGlassTextStyleForSize(CGFloat size) {
    if (size >= 20.0) {
        return UIFontTextStyleTitle2;
    }
    if (size >= 16.0) {
        return UIFontTextStyleBody;
    }
    if (size >= 14.0) {
        return UIFontTextStyleSubheadline;
    }
    if (size >= 12.0) {
        return UIFontTextStyleFootnote;
    }
    return UIFontTextStyleCaption2;
}

static BOOL WCLiquidGlassHasDifferentContentSizeCategory(UITraitCollection *current,
                                                          UITraitCollection *previous) {
    return ![current.preferredContentSizeCategory isEqualToString:previous.preferredContentSizeCategory];
}

static CGFloat WCLiquidGlassSectionHeaderHeight(void) {
    return MAX(38.0, ceil(WCLiquidGlassFont(13.0, UIFontWeightSemibold).lineHeight + 8.0));
}

static CGFloat WCLiquidGlassFooterHeight(NSString *text, CGFloat minimumHeight) {
    UIFont *font = WCLiquidGlassFont(13.0, UIFontWeightRegular);
    CGFloat width = MAX(1.0, UIScreen.mainScreen.bounds.size.width - 40.0);
    CGRect textBounds = [text boundingRectWithSize:CGSizeMake(width, CGFLOAT_MAX)
                                           options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                        attributes:@{NSFontAttributeName: font}
                                           context:nil];
    return MAX(minimumHeight, ceil(textBounds.size.height + 6.0));
}

static CGFloat WCLiquidGlassHeaderHeight(void) {
    CGFloat textHeight = WCLiquidGlassFont(22.0, UIFontWeightSemibold).lineHeight + 4.0 +
        WCLiquidGlassFont(14.0, UIFontWeightRegular).lineHeight * 2.0 + 10.0 +
        MAX(24.0, WCLiquidGlassFont(11.5, UIFontWeightSemibold).lineHeight + 8.0);
    return MAX(164.0, ceil(50.0 + textHeight));
}

static void WCLiquidGlassConfigureTableBackground(UITableViewController *controller) {
    UIColor *backgroundColor = WCLiquidGlassBackdropBaseColor();
    controller.view.backgroundColor = backgroundColor;
    controller.tableView.backgroundColor = backgroundColor;
    controller.tableView.backgroundView = [[WCLiquidGlassBackdropView alloc] init];
}

static void WCLiquidGlassStyleCardCell(UITableViewCell *cell,
                                       NSIndexPath *indexPath,
                                       UITableView *tableView) {
    NSInteger rowCount = [tableView.dataSource tableView:tableView numberOfRowsInSection:indexPath.section];
    BOOL first = indexPath.row == 0;
    BOOL last = indexPath.row == rowCount - 1;
    CACornerMask corners = 0;
    if (first) {
        corners |= kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    }
    if (last) {
        corners |= kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    }
    cell.backgroundConfiguration = nil;
    cell.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:0.14 alpha:0.94]
            : [UIColor colorWithWhite:1.0 alpha:0.84];
    }];
    cell.contentView.backgroundColor = UIColor.clearColor;
    cell.layer.cornerRadius = (first || last) ? 24.0 : 0.0;
    cell.layer.cornerCurve = kCACornerCurveContinuous;
    cell.layer.maskedCorners = corners;
    cell.layer.masksToBounds = YES;
}

static UIFont *WCLiquidGlassFont(CGFloat size, UIFontWeight weight) {
    NSString *fontName = weight >= UIFontWeightSemibold ? @"PingFangSC-Semibold" : @"PingFangSC-Regular";
    UIFont *font = [UIFont fontWithName:fontName size:size] ?: [UIFont systemFontOfSize:size weight:weight];
    return [[UIFontMetrics metricsForTextStyle:WCLiquidGlassTextStyleForSize(size)] scaledFontForFont:font];
}

static UILabel *WCLiquidGlassSectionLabel(NSString *text, UIColor *color) {
    UIFont *font = WCLiquidGlassFont(13.0, UIFontWeightSemibold);
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20.0, 4.0, 300.0,
                                                                ceil(font.lineHeight + 4.0))];
    label.text = text;
    label.font = font;
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = color;
    return label;
}

static UILabel *WCLiquidGlassFooterLabel(NSString *text) {
    UIFont *font = WCLiquidGlassFont(13.0, UIFontWeightRegular);
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20.0, 2.0, UIScreen.mainScreen.bounds.size.width - 40.0,
                                                                WCLiquidGlassFooterHeight(text, 48.0) - 4.0)];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    label.text = text;
    label.font = font;
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = UIColor.secondaryLabelColor;
    label.numberOfLines = 0;
    return label;
}

static void WCLiquidGlassConfigureCell(UITableViewCell *cell,
                                       NSString *title,
                                       NSString *secondaryText,
                                       UIImage *image,
                                       UIColor *titleColor) {
    UIListContentConfiguration *content = [UIListContentConfiguration valueCellConfiguration];
    content.text = title;
    content.secondaryText = secondaryText;
    content.image = image;
    content.textProperties.font = WCLiquidGlassFont(17.0, UIFontWeightRegular);
    content.textProperties.adjustsFontForContentSizeCategory = YES;
    content.textProperties.color = titleColor ?: UIColor.labelColor;
    content.secondaryTextProperties.font = WCLiquidGlassFont(15.0, UIFontWeightRegular);
    content.secondaryTextProperties.adjustsFontForContentSizeCategory = YES;
    content.secondaryTextProperties.color = UIColor.secondaryLabelColor;
    content.imageProperties.maximumSize = CGSizeMake(28.0, 28.0);
    content.imageProperties.reservedLayoutSize = CGSizeMake(28.0, 28.0);
    content.imageProperties.tintColor = UIColor.labelColor;
    content.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(10.0, 16.0, 10.0, 12.0);
    cell.contentConfiguration = content;
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
}

@interface WCLiquidGlassButtonEditorController : UITableViewController

@property(nonatomic, strong) NSMutableArray<NSMutableDictionary<NSString *, id> *> *items;
@property(nonatomic, copy) NSArray<NSString *> *availableNavigationActions;
@property(nonatomic, copy) NSArray<NSString *> *availableChatActions;

@end


@implementation WCLiquidGlassButtonEditorController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"按钮与动作";
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 66.0;
    WCLiquidGlassConfigureTableBackground(self);
    self.tableView.separatorColor = [UIColor.separatorColor colorWithAlphaComponent:0.30];
    self.tableView.allowsSelectionDuringEditing = YES;
    self.navigationItem.rightBarButtonItem = self.editButtonItem;
    [self wc_reloadItems];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection] ||
        WCLiquidGlassHasDifferentContentSizeCategory(self.traitCollection, previousTraitCollection)) {
        [self.tableView reloadData];
    }
}

- (void)tableView:(UITableView *)tableView
  willDisplayCell:(UITableViewCell *)cell
forRowAtIndexPath:(NSIndexPath *)indexPath {
    WCLiquidGlassStyleCardCell(cell, indexPath, tableView);
}

- (void)wc_reloadItems {
    NSMutableArray *items = [NSMutableArray array];
    for (NSDictionary<NSString *, id> *item in WCLiquidGlassPreferences.buttonItems) {
        [items addObject:item.mutableCopy];
    }
    self.items = items;
    [self wc_rebuildAvailableActions];
    [self.tableView reloadData];
}

- (void)wc_saveItems {
    [WCLiquidGlassPreferences setButtonItems:self.items.copy];
}

- (NSSet<NSString *> *)wc_currentActionIdentifiers {
    NSMutableSet<NSString *> *actionIdentifiers = [NSMutableSet set];
    [self.items enumerateObjectsUsingBlock:^(NSDictionary<NSString *, id> *item, NSUInteger index, BOOL *stop) {
        if ([item[@"action"] isKindOfClass:NSString.class]) {
            [actionIdentifiers addObject:item[@"action"]];
        }
    }];
    return actionIdentifiers.copy;
}

- (void)wc_rebuildAvailableActions {
    NSSet<NSString *> *currentActions = [self wc_currentActionIdentifiers];
    NSArray<NSString *> *navigationActions = @[
        WCLiquidGlassActionSettings, WCLiquidGlassActionPlugins,
        WCLiquidGlassActionMoments, WCLiquidGlassActionChannels
    ];
    NSArray<NSString *> *chatActions = @[
        WCLiquidGlassActionDoutuAssistant, WCLiquidGlassActionSearchRecords,
        WCLiquidGlassActionAlbum, WCLiquidGlassActionCamera, WCLiquidGlassActionVideoCall,
        WCLiquidGlassActionRedPacket, WCLiquidGlassActionFiles, WCLiquidGlassActionTransfer,
        WCLiquidGlassActionLocation, WCLiquidGlassActionFavorites, WCLiquidGlassActionTranslate,
        WCLiquidGlassActionScan, WCLiquidGlassActionPayment, WCLiquidGlassActionContactCard,
        WCLiquidGlassActionVoiceInput, WCLiquidGlassActionNewLine,
        WCLiquidGlassActionMention, WCLiquidGlassActionFullInput
    ];
    NSPredicate *availablePredicate = [NSPredicate predicateWithBlock:^BOOL(NSString *actionIdentifier,
                                                                           NSDictionary *bindings) {
        return ![currentActions containsObject:actionIdentifier];
    }];
    self.availableNavigationActions = [navigationActions filteredArrayUsingPredicate:availablePredicate];
    self.availableChatActions = [chatActions filteredArrayUsingPredicate:availablePredicate];
}

- (NSArray<NSString *> *)wc_availableActionsForSection:(NSInteger)section {
    return section == 1 ? self.availableNavigationActions : self.availableChatActions;
}

- (NSInteger)wc_availableSectionForAction:(NSString *)actionIdentifier {
    NSArray<NSString *> *navigationActions = @[
        WCLiquidGlassActionSettings, WCLiquidGlassActionPlugins,
        WCLiquidGlassActionMoments, WCLiquidGlassActionChannels
    ];
    return [navigationActions containsObject:actionIdentifier] ? 1 : 2;
}

- (void)wc_reloadAvailableSectionsWithoutAnimation {
    [UIView performWithoutAnimation:^{
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1, 2)]
                      withRowAnimation:UITableViewRowAnimationNone];
    }];
}

- (void)wc_confirmRestoreButtons {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"恢复默认按钮？"
                                                                   message:@"按钮顺序和已添加动作会恢复，其他设置不受影响。"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"恢复"
                                             style:UIAlertActionStyleDestructive
                                           handler:^(UIAlertAction *action) {
        [WCLiquidGlassPreferences restoreDefaultButtonItems];
        [self wc_reloadItems];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 4;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) {
        return self.items.count;
    }
    if (section == 1 || section == 2) {
        return [self wc_availableActionsForSection:section].count;
    }
    return 1;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSArray<NSString *> *titles = @[@"已添加", @"导航与入口", @"聊天工具", @"管理"];
    return WCLiquidGlassSectionLabel(titles[section], UIColor.secondaryLabelColor);
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return WCLiquidGlassSectionHeaderHeight();
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return WCLiquidGlassFooterLabel(@"点按右上角“编辑”后，可删除按钮或按住右侧把手调整顺序。");
    }
    if (section == 2) {
        return WCLiquidGlassFooterLabel(@"编辑时轻点加号即可添加；已添加的动作不会重复显示。");
    }
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return WCLiquidGlassFooterHeight(@"点按右上角“编辑”后，可删除按钮或按住右侧把手调整顺序。", 54.0);
    }
    if (section == 2) {
        return WCLiquidGlassFooterHeight(@"编辑时轻点加号即可添加；已添加的动作不会重复显示。", 54.0);
    }
    return CGFLOAT_MIN;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return self.editing && indexPath.section == 0;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        return self.editing;
    }
    return self.editing && (indexPath.section == 1 || indexPath.section == 2)
        && self.items.count < WCLiquidGlassMaximumButtonCount;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.editing && indexPath.section == 0) {
        return UITableViewCellEditingStyleDelete;
    }
    if (self.editing && (indexPath.section == 1 || indexPath.section == 2)
        && self.items.count < WCLiquidGlassMaximumButtonCount) {
        return UITableViewCellEditingStyleInsert;
    }
    return UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    return self.editing && indexPath.section < 3;
}

- (void)tableView:(UITableView *)tableView
commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
 forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete && indexPath.section == 0) {
        NSString *actionIdentifier = self.items[indexPath.row][@"action"];
        BOOL wasAtMaximum = self.items.count == WCLiquidGlassMaximumButtonCount;
        [self.items removeObjectAtIndex:indexPath.row];
        [self wc_rebuildAvailableActions];
        [self wc_saveItems];
        NSInteger destinationSection = [self wc_availableSectionForAction:actionIdentifier];
        NSUInteger destinationRow = [[self wc_availableActionsForSection:destinationSection] indexOfObject:actionIdentifier];
        [tableView performBatchUpdates:^{
            [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
            if (destinationRow != NSNotFound) {
                NSIndexPath *destination = [NSIndexPath indexPathForRow:destinationRow inSection:destinationSection];
                [tableView insertRowsAtIndexPaths:@[destination] withRowAnimation:UITableViewRowAnimationAutomatic];
            }
        } completion:^(BOOL finished) {
            if (wasAtMaximum) {
                [self wc_reloadAvailableSectionsWithoutAnimation];
            }
        }];
        return;
    }
    if (editingStyle != UITableViewCellEditingStyleInsert
        || (indexPath.section != 1 && indexPath.section != 2)
        || self.items.count >= WCLiquidGlassMaximumButtonCount) {
        return;
    }
    NSString *actionIdentifier = [self wc_availableActionsForSection:indexPath.section][indexPath.row];
    NSUInteger destinationRow = self.items.count;
    [self.items addObject:[@{
        @"slot": [NSString stringWithFormat:@"slot.%@", NSUUID.UUID.UUIDString],
        @"action": actionIdentifier
    } mutableCopy]];
    [self wc_rebuildAvailableActions];
    [self wc_saveItems];
    BOOL reachedMaximum = self.items.count == WCLiquidGlassMaximumButtonCount;
    [tableView performBatchUpdates:^{
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
        NSIndexPath *destination = [NSIndexPath indexPathForRow:destinationRow inSection:0];
        [tableView insertRowsAtIndexPaths:@[destination] withRowAnimation:UITableViewRowAnimationAutomatic];
    } completion:^(BOOL finished) {
        if (reachedMaximum) {
            [self wc_reloadAvailableSectionsWithoutAnimation];
        }
    }];
}

- (void)tableView:(UITableView *)tableView
 moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath
        toIndexPath:(NSIndexPath *)destinationIndexPath {
    NSMutableDictionary *item = self.items[sourceIndexPath.row];
    [self.items removeObjectAtIndex:sourceIndexPath.row];
    [self.items insertObject:item atIndex:destinationIndexPath.row];
    [self wc_saveItems];
}

- (NSIndexPath *)tableView:(UITableView *)tableView
targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)sourceIndexPath
       toProposedIndexPath:(NSIndexPath *)proposedDestinationIndexPath {
    if (proposedDestinationIndexPath.section == 0) {
        return proposedDestinationIndexPath;
    }
    return [NSIndexPath indexPathForRow:self.items.count - 1 inSection:0];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"WCLiquidGlassButtonEditorCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
    }

    if (indexPath.section == 3) {
        WCLiquidGlassConfigureCell(cell,
                                   @"恢复默认按钮",
                                   @"恢复为最初的按钮与顺序",
                                   WCLiquidGlassSettingsIconImage(WCLiquidGlassSettingsIconKindRestore, 32.0),
                                   UIColor.systemRedColor);
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.showsReorderControl = NO;
        cell.contentView.alpha = 1.0;
        return cell;
    }

    NSString *actionIdentifier = indexPath.section == 0
        ? self.items[indexPath.row][@"action"]
        : [self wc_availableActionsForSection:indexPath.section][indexPath.row];
    WCLiquidGlassConfigureCell(cell,
                               WCLiquidGlassActionTitle(actionIdentifier),
                               nil,
                               WCLiquidGlassImageForAction(actionIdentifier, 60.0),
                               UIColor.labelColor);
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.showsReorderControl = indexPath.section == 0;
    cell.contentView.alpha = (indexPath.section > 0
                              && self.items.count >= WCLiquidGlassMaximumButtonCount) ? 0.45 : 1.0;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 3) {
        [self wc_confirmRestoreButtons];
    }
}

@end

@interface WCLiquidGlassCrashLogsController : UITableViewController

@property(nonatomic, copy) NSArray<NSURL *> *logURLs;

@end


@implementation WCLiquidGlassCrashLogsController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"崩溃日志";
    WCLiquidGlassConfigureTableBackground(self);
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 76.0;
    self.tableView.separatorColor = [UIColor.separatorColor colorWithAlphaComponent:0.30];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"清空"
                                                                               style:UIBarButtonItemStylePlain
                                                                              target:self
                                                                              action:@selector(wc_confirmDeleteAll)];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(wc_logsChanged:)
                                               name:WCLiquidGlassCrashLogsDidChangeNotification
                                             object:nil];
    [self wc_reloadLogs];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection] ||
        WCLiquidGlassHasDifferentContentSizeCategory(self.traitCollection, previousTraitCollection)) {
        [self.tableView reloadData];
    }
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.logURLs.count;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    return WCLiquidGlassSectionLabel(@"最近日志", UIColor.secondaryLabelColor);
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return WCLiquidGlassSectionHeaderHeight();
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    return WCLiquidGlassFooterLabel(@"最多保留 20 份。点击日志可调用 iOS 系统分享；内容包含崩溃堆栈、系统与已加载插件信息，不记录聊天文字。");
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return WCLiquidGlassFooterHeight(@"最多保留 20 份。点击日志可调用 iOS 系统分享；内容包含崩溃堆栈、系统与已加载插件信息，不记录聊天文字。", 72.0);
}

- (void)tableView:(UITableView *)tableView
  willDisplayCell:(UITableViewCell *)cell
forRowAtIndexPath:(NSIndexPath *)indexPath {
    WCLiquidGlassStyleCardCell(cell, indexPath, tableView);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"WCLiquidGlassCrashLogCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    }
    NSURL *URL = self.logURLs[indexPath.row];
    NSNumber *fileSize = nil;
    NSDate *modifiedAt = nil;
    [URL getResourceValue:&fileSize forKey:NSURLFileSizeKey error:nil];
    [URL getResourceValue:&modifiedAt forKey:NSURLContentModificationDateKey error:nil];
    BOOL fullReport = [URL.pathExtension.lowercaseString isEqualToString:@"crash"];
    NSString *title = fullReport ? @"完整崩溃报告" : @"Objective-C 异常报告";
    NSString *detail = [NSString stringWithFormat:@"%@ · %@",
                        modifiedAt ? [NSDateFormatter localizedStringFromDate:modifiedAt
                                                                    dateStyle:NSDateFormatterShortStyle
                                                                    timeStyle:NSDateFormatterMediumStyle] : @"未知时间",
                        [NSByteCountFormatter stringFromByteCount:fileSize.longLongValue
                                                      countStyle:NSByteCountFormatterCountStyleFile]];
    WCLiquidGlassConfigureCell(cell, title, detail,
                               WCLiquidGlassSettingsIconImage(WCLiquidGlassSettingsIconKindCrashLogs, 32.0), UIColor.labelColor);
    cell.accessibilityHint = URL.lastPathComponent;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSURL *URL = self.logURLs[indexPath.row];
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[URL]
                                                                        applicationActivities:nil];
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    share.popoverPresentationController.sourceView = cell;
    share.popoverPresentationController.sourceRect = cell.bounds;
    [self presentViewController:share animated:YES completion:nil];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (void)tableView:(UITableView *)tableView
commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
 forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) {
        return;
    }
    [[WCLiquidGlassCrashLogger sharedLogger] deleteLogAtURL:self.logURLs[indexPath.row] error:nil];
}

- (void)wc_reloadLogs {
    self.logURLs = WCLiquidGlassCrashLogger.sharedLogger.crashLogURLs;
    self.navigationItem.rightBarButtonItem.enabled = self.logURLs.count > 0;
    if (self.logURLs.count == 0) {
        UILabel *empty = [[UILabel alloc] init];
        empty.text = @"暂无崩溃日志\n发生可捕获的异常后会自动出现在这里";
        empty.numberOfLines = 0;
        empty.textAlignment = NSTextAlignmentCenter;
        empty.textColor = UIColor.secondaryLabelColor;
        empty.font = WCLiquidGlassFont(15.0, UIFontWeightRegular);
        empty.adjustsFontForContentSizeCategory = YES;
        self.tableView.backgroundView = empty;
    } else {
        self.tableView.backgroundView = [[WCLiquidGlassBackdropView alloc] init];
    }
    [self.tableView reloadData];
}

- (void)wc_logsChanged:(NSNotification *)notification {
    [self wc_reloadLogs];
}

- (void)wc_confirmDeleteAll {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"清空全部日志？"
                                                                   message:@"删除后无法恢复。"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"清空"
                                             style:UIAlertActionStyleDestructive
                                           handler:^(UIAlertAction *action) {
        [WCLiquidGlassCrashLogger.sharedLogger deleteAllLogs];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end


@interface WCLiquidGlass ()

@property(nonatomic, strong) UISwitch *enabledSwitch;
@property(nonatomic, strong) UISwitch *fullCrashReportsSwitch;

@end


@implementation WCLiquidGlass

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"WCLiquidGlass";
    WCLiquidGlassConfigureTableBackground(self);
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 66.0;
    self.tableView.separatorColor = [UIColor.separatorColor colorWithAlphaComponent:0.30];
    self.tableView.tableHeaderView = [self wc_makeHeaderView];
    [WCLiquidGlassPreferences registerDefaults];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(wc_preferencesChanged:)
                                           name:WCLiquidGlassPreferencesDidChangeNotification
                                           object:nil];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection] ||
        WCLiquidGlassHasDifferentContentSizeCategory(self.traitCollection, previousTraitCollection)) {
        self.tableView.tableHeaderView = [self wc_makeHeaderView];
        [self.tableView reloadData];
    }
}

- (void)tableView:(UITableView *)tableView
  willDisplayCell:(UITableViewCell *)cell
forRowAtIndexPath:(NSIndexPath *)indexPath {
    WCLiquidGlassStyleCardCell(cell, indexPath, tableView);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIView *header = self.tableView.tableHeaderView;
    if (!header) {
        return;
    }
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    if (fabs(CGRectGetWidth(header.frame) - width) > 0.5) {
        header.frame = CGRectMake(0.0, 0.0, width, WCLiquidGlassHeaderHeight());
        self.tableView.tableHeaderView = header;
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (UIView *)wc_makeHeaderView {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 320.0, WCLiquidGlassHeaderHeight())];
    UIVisualEffectView *card = [[UIVisualEffectView alloc] initWithEffect:WCLiquidGlassSettingsEffect()];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.layer.cornerRadius = 28.0;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.clipsToBounds = YES;

    UIImageView *brandIcon = [[UIImageView alloc] initWithImage:WCLiquidGlassBrandIconImage(58.0, YES)];
    brandIcon.translatesAutoresizingMaskIntoConstraints = NO;
    brandIcon.contentMode = UIViewContentModeScaleAspectFit;

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"WCLiquidGlass";
    title.font = WCLiquidGlassFont(22.0, UIFontWeightSemibold);
    title.adjustsFontForContentSizeCategory = YES;
    title.textColor = UIColor.labelColor;

    UILabel *subtitle = [[UILabel alloc] init];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.text = @"为微信打造的模块化交互增强";
    subtitle.textColor = UIColor.secondaryLabelColor;
    subtitle.font = WCLiquidGlassFont(14.0, UIFontWeightRegular);
    subtitle.adjustsFontForContentSizeCategory = YES;
    subtitle.numberOfLines = 2;

    UIView *versionBadge = [[UIView alloc] init];
    versionBadge.translatesAutoresizingMaskIntoConstraints = NO;
    versionBadge.backgroundColor = UIColor.secondarySystemFillColor;
    versionBadge.layer.cornerRadius = 12.0;
    versionBadge.layer.cornerCurve = kCACornerCurveContinuous;
    versionBadge.layer.borderWidth = 0.5;
    versionBadge.layer.borderColor = [UIColor.separatorColor colorWithAlphaComponent:0.34].CGColor;

    UILabel *version = [[UILabel alloc] init];
    version.translatesAutoresizingMaskIntoConstraints = NO;
    NSString *displayVersion = [NSString stringWithUTF8String:WCLIQUIDGLASS_VERSION];
    displayVersion = [[displayVersion stringByReplacingOccurrencesOfString:@"~" withString:@" "] uppercaseString];
    version.text = [NSString stringWithFormat:@"Version %@", displayVersion];
    version.font = WCLiquidGlassFont(11.5, UIFontWeightSemibold);
    version.adjustsFontForContentSizeCategory = YES;
    version.textColor = UIColor.secondaryLabelColor;
    version.textAlignment = NSTextAlignmentCenter;

    [header addSubview:card];
    [card.contentView addSubview:brandIcon];
    [card.contentView addSubview:title];
    [card.contentView addSubview:subtitle];
    [card.contentView addSubview:versionBadge];
    [versionBadge addSubview:version];
    [NSLayoutConstraint activateConstraints:@[
        [card.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20.0],
        [card.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20.0],
        [card.topAnchor constraintEqualToAnchor:header.topAnchor constant:14.0],
        [card.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-12.0],
        [brandIcon.leadingAnchor constraintEqualToAnchor:card.contentView.leadingAnchor constant:22.0],
        [brandIcon.topAnchor constraintEqualToAnchor:card.contentView.topAnchor constant:24.0],
        [brandIcon.widthAnchor constraintEqualToConstant:58.0],
        [brandIcon.heightAnchor constraintEqualToConstant:58.0],
        [title.leadingAnchor constraintEqualToAnchor:brandIcon.trailingAnchor constant:15.0],
        [title.topAnchor constraintEqualToAnchor:brandIcon.topAnchor constant:0.0],
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:card.contentView.trailingAnchor constant:-20.0],
        [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:4.0],
        [subtitle.trailingAnchor constraintLessThanOrEqualToAnchor:card.contentView.trailingAnchor constant:-20.0],
        [versionBadge.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [versionBadge.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:10.0],
        [versionBadge.heightAnchor constraintEqualToConstant:MAX(24.0, ceil(version.font.lineHeight + 8.0))],
        [version.leadingAnchor constraintEqualToAnchor:versionBadge.leadingAnchor constant:10.0],
        [version.trailingAnchor constraintEqualToAnchor:versionBadge.trailingAnchor constant:-10.0],
        [version.centerYAnchor constraintEqualToAnchor:versionBadge.centerYAnchor]
    ]];
    return header;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 5;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) {
        return 3;
    }
    return section == 3 ? 2 : 1;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSArray<NSString *> *titles = @[@"菜单", @"内容", @"兼容性", @"诊断", @"维护"];
    return WCLiquidGlassSectionLabel(titles[section], UIColor.secondaryLabelColor);
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return WCLiquidGlassSectionHeaderHeight();
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return WCLiquidGlassFooterLabel(@"入口可在微信任意页面呼出，闲置时自动吸附并半隐藏到屏幕边缘。空间不足时自动使用所选紧凑布局。");
    }
    if (section == 1) {
        return WCLiquidGlassFooterLabel(@"在“按钮与动作”页面点按编辑，即可添加、删除或拖动调整按钮顺序。");
    }
    if (section == 2) {
        return WCLiquidGlassFooterLabel(@"仅用于修复 iOS 27 与 WCGlass 横向胶囊分组、全屏分组的返回闪退。开关切换后立即生效。");
    }
    if (section == 3) {
        return WCLiquidGlassFooterLabel(@"基础诊断始终开启且不记录聊天内容。完整采集可获得原生线程与二进制镜像信息，重启微信后生效；系统强杀、Jetsam 与看门狗终止可能无法捕获。");
    }
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return WCLiquidGlassFooterHeight(@"入口可在微信任意页面呼出，闲置时自动吸附并半隐藏到屏幕边缘。空间不足时自动使用所选紧凑布局。", 72.0);
    }
    if (section == 1) {
        return WCLiquidGlassFooterHeight(@"在“按钮与动作”页面点按编辑，即可添加、删除或拖动调整按钮顺序。", 54.0);
    }
    if (section == 2) {
        return WCLiquidGlassFooterHeight(@"仅用于修复 iOS 27 与 WCGlass 横向胶囊分组、全屏分组的返回闪退。开关切换后立即生效。", 64.0);
    }
    return section == 3
        ? WCLiquidGlassFooterHeight(@"基础诊断始终开启且不记录聊天内容。完整采集可获得原生线程与二进制镜像信息，重启微信后生效；系统强杀、Jetsam 与看门狗终止可能无法捕获。", 92.0)
        : CGFLOAT_MIN;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"WCLiquidGlassSettingsCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
    }

    if (indexPath.section == 0 && indexPath.row == 0) {
        WCLiquidGlassConfigureCell(cell, @"启用全局环形菜单", nil,
                                   WCLiquidGlassSettingsIconImage(WCLiquidGlassSettingsIconKindMenu, 32.0), UIColor.labelColor);
        self.enabledSwitch = [[UISwitch alloc] init];
        self.enabledSwitch.on = WCLiquidGlassPreferences.enabled;
        [self.enabledSwitch addTarget:self action:@selector(wc_enabledChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = self.enabledSwitch;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (indexPath.section == 0 && indexPath.row == 1) {
        WCLiquidGlassConfigureCell(cell, @"按钮大小", [self wc_sizeModeTitle],
                                   WCLiquidGlassSettingsIconImage(WCLiquidGlassSettingsIconKindSize, 32.0), UIColor.labelColor);
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 0) {
        WCLiquidGlassConfigureCell(cell, @"紧凑布局", [self wc_compactLayoutStyleTitle],
                                   WCLiquidGlassSettingsIconImage(WCLiquidGlassSettingsIconKindCompactLayout, 32.0), UIColor.labelColor);
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 1) {
        NSString *count = [NSString stringWithFormat:@"%lu 个槽位", (unsigned long)WCLiquidGlassPreferences.buttonItems.count];
        WCLiquidGlassConfigureCell(cell, @"按钮与动作", count,
                                   WCLiquidGlassSettingsIconImage(WCLiquidGlassSettingsIconKindActions, 32.0), UIColor.labelColor);
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 2) {
        WCLiquidGlassConfigureCell(cell, @"WCGlass iOS 27 兼容修复", @"修复带键盘返回时的闪退",
                                   WCLiquidGlassSettingsIconImage(WCLiquidGlassSettingsIconKindCompatibility, 32.0), UIColor.labelColor);
        UISwitch *wcGlassCompatibilitySwitch = [[UISwitch alloc] init];
        wcGlassCompatibilitySwitch.on = WCLiquidGlassPreferences.wcGlassIOS27CompatibilityEnabled;
        [wcGlassCompatibilitySwitch addTarget:self action:@selector(wc_wcGlassCompatibilityChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = wcGlassCompatibilitySwitch;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (indexPath.section == 3 && indexPath.row == 0) {
        WCLiquidGlassConfigureCell(cell, @"完整崩溃采集", @"重启微信后生效",
                                   WCLiquidGlassSettingsIconImage(WCLiquidGlassSettingsIconKindCrashCapture, 32.0), UIColor.labelColor);
        self.fullCrashReportsSwitch = [[UISwitch alloc] init];
        self.fullCrashReportsSwitch.on = WCLiquidGlassPreferences.fullCrashReportsEnabled;
        [self.fullCrashReportsSwitch addTarget:self action:@selector(wc_fullCrashReportsChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = self.fullCrashReportsSwitch;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (indexPath.section == 3) {
        NSUInteger count = WCLiquidGlassCrashLogger.sharedLogger.crashLogURLs.count;
        NSString *detail = count > 0 ? [NSString stringWithFormat:@"%lu 份", (unsigned long)count] : @"暂无日志";
        WCLiquidGlassConfigureCell(cell, @"崩溃日志", detail,
                                   WCLiquidGlassSettingsIconImage(WCLiquidGlassSettingsIconKindCrashLogs, 32.0), UIColor.labelColor);
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        WCLiquidGlassConfigureCell(cell, @"恢复默认设置", nil,
                                   WCLiquidGlassSettingsIconImage(WCLiquidGlassSettingsIconKindRestore, 32.0), UIColor.systemRedColor);
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0 && indexPath.row == 1) {
        [self wc_presentSizePickerFromView:[tableView cellForRowAtIndexPath:indexPath]];
    } else if (indexPath.section == 0 && indexPath.row == 2) {
        [self wc_presentCompactLayoutPickerFromView:[tableView cellForRowAtIndexPath:indexPath]];
    } else if (indexPath.section == 1) {
        [self.navigationController pushViewController:[[WCLiquidGlassButtonEditorController alloc] init] animated:YES];
    } else if (indexPath.section == 3 && indexPath.row == 1) {
        [self.navigationController pushViewController:[[WCLiquidGlassCrashLogsController alloc] init] animated:YES];
    } else if (indexPath.section == 4) {
        [self wc_confirmRestore];
    }
}

- (void)wc_enabledChanged:(UISwitch *)sender {
    [WCLiquidGlassPreferences setEnabled:sender.isOn];
}

- (void)wc_fullCrashReportsChanged:(UISwitch *)sender {
    [WCLiquidGlassPreferences setFullCrashReportsEnabled:sender.isOn];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"重启微信后生效"
                                                                   message:sender.isOn
                                                                        ? @"完整崩溃采集会在下次启动微信时启用。它能提供更完整的原生崩溃信息，但可能与其他崩溃采集插件竞争异常处理权。"
                                                                        : @"完整崩溃采集会在下次启动微信时关闭；基础 Objective-C 异常诊断仍会保留。"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)wc_wcGlassCompatibilityChanged:(UISwitch *)sender {
    [WCLiquidGlassPreferences setWCGlassIOS27CompatibilityEnabled:sender.isOn];
}

- (NSString *)wc_sizeModeTitle {
    switch (WCLiquidGlassPreferences.sizeMode) {
        case 0:
            return @"紧凑 · 53pt";
        case 2:
            return @"大 · 66pt";
        default:
            return @"标准 · 60pt";
    }
}

- (NSString *)wc_compactLayoutStyleTitle {
    switch (WCLiquidGlassPreferences.compactLayoutStyle) {
        case WCLiquidGlassCompactLayoutStyleSCurve:
            return @"流动 S 弧";
        case WCLiquidGlassCompactLayoutStyleWideFan:
            return @"宽扇形";
        case WCLiquidGlassCompactLayoutStylePetalCluster:
            return @"花瓣环簇";
        default:
            return @"双层月牙";
    }
}

- (void)wc_presentSizePickerFromView:(UIView *)sourceView {
    UIAlertController *picker = [UIAlertController alertControllerWithTitle:@"按钮大小"
                                                                     message:nil
                                                              preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray<NSString *> *titles = @[@"紧凑 · 53pt", @"标准 · 60pt", @"大 · 66pt"];
    [titles enumerateObjectsUsingBlock:^(NSString *title, NSUInteger index, BOOL *stop) {
        UIAlertAction *action = [UIAlertAction actionWithTitle:title
                                                        style:UIAlertActionStyleDefault
                                                      handler:^(UIAlertAction *selectedAction) {
            [WCLiquidGlassPreferences setSizeMode:index];
        }];
        [picker addAction:action];
    }];
    [picker addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    picker.popoverPresentationController.sourceView = sourceView;
    picker.popoverPresentationController.sourceRect = sourceView.bounds;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)wc_presentCompactLayoutPickerFromView:(UIView *)sourceView {
    UIAlertController *picker = [UIAlertController alertControllerWithTitle:@"紧凑布局"
                                                                     message:@"菜单空间不足时自动采用；所有样式都会保留胶黏动画所需的按钮间距。"
                                                              preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray<NSString *> *titles = @[@"双层月牙", @"流动 S 弧", @"宽扇形", @"花瓣环簇"];
    [titles enumerateObjectsUsingBlock:^(NSString *title, NSUInteger index, BOOL *stop) {
        UIAlertAction *action = [UIAlertAction actionWithTitle:title
                                                        style:UIAlertActionStyleDefault
                                                      handler:^(UIAlertAction *selectedAction) {
            [WCLiquidGlassPreferences setCompactLayoutStyle:(WCLiquidGlassCompactLayoutStyle)index];
        }];
        [picker addAction:action];
    }];
    [picker addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    picker.popoverPresentationController.sourceView = sourceView;
    picker.popoverPresentationController.sourceRect = sourceView.bounds;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)wc_confirmRestore {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"恢复默认设置？"
                                                                   message:@"开关、按钮大小、紧凑布局、入口位置、按钮动作、兼容性和诊断选项都会恢复。"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"恢复"
                                             style:UIAlertActionStyleDestructive
                                           handler:^(UIAlertAction *action) {
        [WCLiquidGlassPreferences restoreDefaults];
        [self.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)wc_preferencesChanged:(NSNotification *)notification {
    [self.tableView reloadData];
}

@end
