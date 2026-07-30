#import "WCLiquidGlassPreferences.h"

NSNotificationName const WCLiquidGlassPreferencesDidChangeNotification = @"WCLiquidGlass.PreferencesChanged";
NSNotificationName const WCLiquidGlassWCGlassCompatibilityDidChangeNotification = @"WCLiquidGlass.WCGlassCompatibilityChanged";

NSString *const WCLiquidGlassActionSettings = @"wcliquidglass_settings";
NSString *const WCLiquidGlassActionWCGlassSettings = @"wcglass_settings";
NSString *const WCLiquidGlassActionChats = @"tab.0";
NSString *const WCLiquidGlassActionContacts = @"tab.1";
NSString *const WCLiquidGlassActionDiscover = @"tab.2";
NSString *const WCLiquidGlassActionMe = @"tab.3";
NSString *const WCLiquidGlassActionPlugins = @"plugins";
NSString *const WCLiquidGlassActionDoutuAssistant = @"doutu_assistant";
NSString *const WCLiquidGlassActionMoments = @"moments";
NSString *const WCLiquidGlassActionChannels = @"channels";
NSString *const WCLiquidGlassActionAlbum = @"album";
NSString *const WCLiquidGlassActionCamera = @"camera";
NSString *const WCLiquidGlassActionVideoCall = @"video_call";
NSString *const WCLiquidGlassActionRedPacket = @"red_packet";
NSString *const WCLiquidGlassActionFiles = @"files";
NSString *const WCLiquidGlassActionTransfer = @"transfer";
NSString *const WCLiquidGlassActionLocation = @"location";
NSString *const WCLiquidGlassActionFavorites = @"favorites";
NSString *const WCLiquidGlassActionTranslate = @"translate";
NSString *const WCLiquidGlassActionScan = @"scan";
NSString *const WCLiquidGlassActionPayment = @"payment";
NSString *const WCLiquidGlassActionContactCard = @"contact_card";
NSString *const WCLiquidGlassActionSearchRecords = @"search_records";
NSString *const WCLiquidGlassActionVoiceInput = @"voice_input";
NSString *const WCLiquidGlassActionNewLine = @"new_line";
NSString *const WCLiquidGlassActionMention = @"mention";
NSString *const WCLiquidGlassActionFullInput = @"full_input";
NSString *const WCLiquidGlassActionPageHierarchyDiagnostics = @"page_hierarchy_diagnostics";

static NSString *const WCLiquidGlassEnabledKey = @"WCLiquidGlass.Enabled";
static NSString *const WCLiquidGlassSizeModeKey = @"WCLiquidGlass.SizeMode";
static NSString *const WCLiquidGlassCompactLayoutStyleKey = @"WCLiquidGlass.CompactLayoutStyle";
static NSString *const WCLiquidGlassGlassAppearanceKey = @"WCLiquidGlass.GlassAppearance";
static NSString *const WCLiquidGlassChatTimeGlassEnabledKey = @"WCLiquidGlass.ChatTimeGlassEnabled";
static NSString *const WCLiquidGlassWCGlassLongPressMenuEnabledKey = @"WCLiquidGlass.WCGlass.LongPressMenuEnabled";
static NSString *const WCLiquidGlassHomeCornersEnabledKey = @"WCLiquidGlass.HomeCorners.Enabled";
static NSString *const WCLiquidGlassHomeCornerInsetKey = @"WCLiquidGlass.HomeCorners.Inset";
static NSString *const WCLiquidGlassHomeCornerRadiusKey = @"WCLiquidGlass.HomeCorners.Radius";
static NSString *const WCLiquidGlassHomeSeparateCardsEnabledKey = @"WCLiquidGlass.HomeCorners.SeparateCardsEnabled";
static NSString *const WCLiquidGlassHomeCardGapKey = @"WCLiquidGlass.HomeCorners.Gap";
static NSString *const WCLiquidGlassHomeLiquidBackgroundEnabledKey = @"WCLiquidGlass.HomeCorners.LiquidBackgroundEnabled";
static NSString *const WCLiquidGlassAnchorOnLeftKey = @"WCLiquidGlass.Anchor.OnLeft";
static NSString *const WCLiquidGlassAnchorYKey = @"WCLiquidGlass.Anchor.YFraction";
static NSString *const WCLiquidGlassFullCrashReportsEnabledKey = @"WCLiquidGlass.Diagnostics.FullCrashReportsEnabled";
static NSString *const WCLiquidGlassWCGlassIOS27CompatibilityEnabledKey = @"WCLiquidGlass.Compatibility.WCGlassIOS27ReturnCrashFixEnabled";
static NSString *const WCLiquidGlassButtonItemsKey = @"WCLiquidGlass.ButtonItems";
static NSString *const WCLiquidGlassLegacySearchRecordsMigrationKey = @"WCLiquidGlass.Migration.SearchRecordsAdded";
static NSString *const WCLiquidGlassSearchRecordsMigrationKey = @"WCLiquidGlass.Migration.SearchRecordsAdded.V2";

static NSArray<NSDictionary<NSString *, id> *> *WCLiquidGlassDefaultButtonItems(void) {
    static NSArray<NSDictionary<NSString *, id> *> *items;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        items = @[
            @{@"slot": @"slot.0", @"action": WCLiquidGlassActionPlugins},
            @{@"slot": @"slot.1", @"action": WCLiquidGlassActionSearchRecords}
        ];
    });
    return items;
}

static BOOL WCLiquidGlassActionWasRemoved(NSString *actionIdentifier) {
    static NSSet<NSString *> *removedActions;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        removedActions = [NSSet setWithArray:@[@"paste", @"emoji_search", @"search"]];
    });
    return [removedActions containsObject:actionIdentifier];
}

static void WCLiquidGlassNotifyPreferencesChanged(void) {
    [NSNotificationCenter.defaultCenter postNotificationName:WCLiquidGlassPreferencesDidChangeNotification
                                                      object:nil];
}

static void WCLiquidGlassMigrateButtonItemsIfNeeded(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults boolForKey:WCLiquidGlassSearchRecordsMigrationKey]) {
        return;
    }

    NSArray *storedItems = [defaults arrayForKey:WCLiquidGlassButtonItemsKey];
    if (![storedItems isKindOfClass:NSArray.class] || storedItems.count == 0) {
        [defaults setBool:YES forKey:WCLiquidGlassSearchRecordsMigrationKey];
        return;
    }

    for (id item in storedItems) {
        if ([item isKindOfClass:NSDictionary.class] &&
            [item[@"slot"] isKindOfClass:NSString.class] &&
            [item[@"action"] isKindOfClass:NSString.class] &&
            [item[@"action"] isEqualToString:WCLiquidGlassActionSearchRecords]) {
            [defaults setBool:YES forKey:WCLiquidGlassSearchRecordsMigrationKey];
            return;
        }
    }

    NSMutableArray *migratedItems = [storedItems mutableCopy];
    [migratedItems addObject:@{@"slot": @"slot.search_records",
                               @"action": WCLiquidGlassActionSearchRecords}];
    [defaults setObject:migratedItems.copy forKey:WCLiquidGlassButtonItemsKey];
    [defaults setBool:YES forKey:WCLiquidGlassSearchRecordsMigrationKey];
}

NSArray<NSDictionary<NSString *, NSString *> *> *WCLiquidGlassActionCatalog(void) {
    static NSArray<NSDictionary<NSString *, NSString *> *> *catalog;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        catalog = @[
            @{@"identifier": WCLiquidGlassActionSettings, @"title": @"WCLiquidGlass", @"symbol": @"circle.grid.cross.fill"},
            @{@"identifier": WCLiquidGlassActionWCGlassSettings, @"title": @"WCGlass", @"symbol": @"drop.fill"},
            @{@"identifier": WCLiquidGlassActionChats, @"title": @"微信", @"symbol": @"message.fill"},
            @{@"identifier": WCLiquidGlassActionContacts, @"title": @"通讯录", @"symbol": @"person.2.fill"},
            @{@"identifier": WCLiquidGlassActionDiscover, @"title": @"发现", @"symbol": @"safari.fill"},
            @{@"identifier": WCLiquidGlassActionMe, @"title": @"我", @"symbol": @"person.crop.circle.fill"},
            @{@"identifier": WCLiquidGlassActionPageHierarchyDiagnostics, @"title": @"当前页面层级诊断", @"symbol": @"rectangle.3.group.bubble.left"},
            @{@"identifier": WCLiquidGlassActionPlugins, @"title": @"插件列表", @"symbol": @"shippingbox.fill"},
            @{@"identifier": WCLiquidGlassActionDoutuAssistant, @"title": @"斗图助手", @"symbol": @"face.smiling"},
            @{@"identifier": WCLiquidGlassActionMoments, @"title": @"朋友圈", @"symbol": @"circle.hexagongrid.fill"},
            @{@"identifier": WCLiquidGlassActionChannels, @"title": @"视频号", @"symbol": @"play.circle.fill"},
            @{@"identifier": WCLiquidGlassActionAlbum, @"title": @"照片", @"symbol": @"photo.on.rectangle"},
            @{@"identifier": WCLiquidGlassActionCamera, @"title": @"拍摄", @"symbol": @"camera.fill"},
            @{@"identifier": WCLiquidGlassActionVideoCall, @"title": @"视频通话", @"symbol": @"video.fill"},
            @{@"identifier": WCLiquidGlassActionRedPacket, @"title": @"红包", @"symbol": @"gift.fill"},
            @{@"identifier": WCLiquidGlassActionFiles, @"title": @"文件", @"symbol": @"folder.fill"},
            @{@"identifier": WCLiquidGlassActionTransfer, @"title": @"转账", @"symbol": @"arrow.left.arrow.right.circle.fill"},
            @{@"identifier": WCLiquidGlassActionLocation, @"title": @"位置", @"symbol": @"location.fill"},
            @{@"identifier": WCLiquidGlassActionFavorites, @"title": @"收藏", @"symbol": @"star.fill"},
            @{@"identifier": WCLiquidGlassActionTranslate, @"title": @"翻译", @"symbol": @"character.book.closed.fill"},
            @{@"identifier": WCLiquidGlassActionScan, @"title": @"扫一扫", @"symbol": @"qrcode.viewfinder"},
            @{@"identifier": WCLiquidGlassActionPayment, @"title": @"收付款", @"symbol": @"qrcode"},
            @{@"identifier": WCLiquidGlassActionContactCard, @"title": @"名片", @"symbol": @"person.text.rectangle"},
            @{@"identifier": WCLiquidGlassActionSearchRecords, @"title": @"搜索记录", @"symbol": @"magnifyingglass"},
            @{@"identifier": WCLiquidGlassActionVoiceInput, @"title": @"语音转述", @"symbol": @"waveform"},
            @{@"identifier": WCLiquidGlassActionNewLine, @"title": @"换行", @"symbol": @"return"},
            @{@"identifier": WCLiquidGlassActionMention, @"title": @"艾特", @"symbol": @"at"},
            @{@"identifier": WCLiquidGlassActionFullInput, @"title": @"全屏输入", @"symbol": @"arrow.up.left.and.arrow.down.right"},
            @{@"identifier": @"layout_test.01", @"title": @"布局测试 01", @"symbol": @"circle.fill"},
            @{@"identifier": @"layout_test.02", @"title": @"布局测试 02", @"symbol": @"square.fill"},
            @{@"identifier": @"layout_test.03", @"title": @"布局测试 03", @"symbol": @"triangle.fill"},
            @{@"identifier": @"layout_test.04", @"title": @"布局测试 04", @"symbol": @"diamond.fill"},
            @{@"identifier": @"layout_test.05", @"title": @"布局测试 05", @"symbol": @"hexagon.fill"},
            @{@"identifier": @"layout_test.06", @"title": @"布局测试 06", @"symbol": @"seal.fill"},
            @{@"identifier": @"layout_test.07", @"title": @"布局测试 07", @"symbol": @"star.fill"},
            @{@"identifier": @"layout_test.08", @"title": @"布局测试 08", @"symbol": @"heart.fill"},
            @{@"identifier": @"layout_test.09", @"title": @"布局测试 09", @"symbol": @"bolt.fill"},
            @{@"identifier": @"layout_test.10", @"title": @"布局测试 10", @"symbol": @"flame.fill"},
            @{@"identifier": @"layout_test.11", @"title": @"布局测试 11", @"symbol": @"leaf.fill"},
            @{@"identifier": @"layout_test.12", @"title": @"布局测试 12", @"symbol": @"moon.fill"},
            @{@"identifier": @"layout_test.13", @"title": @"布局测试 13", @"symbol": @"sun.max.fill"},
            @{@"identifier": @"layout_test.14", @"title": @"布局测试 14", @"symbol": @"cloud.fill"},
            @{@"identifier": @"layout_test.15", @"title": @"布局测试 15", @"symbol": @"sparkles"}
        ];
    });
    return catalog;
}

NSString *WCLiquidGlassActionTitle(NSString *actionIdentifier) {
    for (NSDictionary<NSString *, NSString *> *action in WCLiquidGlassActionCatalog()) {
        if ([action[@"identifier"] isEqualToString:actionIdentifier]) {
            return action[@"title"];
        }
    }
    return @"未知动作";
}

NSString *WCLiquidGlassActionSymbol(NSString *actionIdentifier) {
    for (NSDictionary<NSString *, NSString *> *action in WCLiquidGlassActionCatalog()) {
        if ([action[@"identifier"] isEqualToString:actionIdentifier]) {
            return action[@"symbol"];
        }
    }
    return @"questionmark";
}

NSArray<NSString *> *WCLiquidGlassActionAssetNames(NSString *actionIdentifier) {
    static NSDictionary<NSString *, NSArray<NSString *> *> *assetNames;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        assetNames = @{
            WCLiquidGlassActionPlugins: @[@"WeChat_Lab_Logo_light_small@3x", @"WeChat_Lab_Logo_light_small", @"WeChat_Lab_Logo_Dark@3x", @"WeChat_Lab_Logo_Dark", @"icons_filled_plugin", @"icons_outlined_plugin", @"plugin_filled", @"plugin_outlined", @"icons_filled_extension", @"icons_outlined_extension", @"extension_filled", @"icons_filled_setting", @"setting_filled"],
            WCLiquidGlassActionMoments: @[@"icons_outlined_colorful_moment", @"icons_filled_moments", @"icons_filled_sns"],
            WCLiquidGlassActionChannels: @[@"play_circle_regular", @"icons_filled_channels_recommend_group"],
            WCLiquidGlassActionAlbum: @[@"icons_filled_album"],
            WCLiquidGlassActionCamera: @[@"icons_filled_camera"],
            WCLiquidGlassActionVideoCall: @[@"icons_filled_video_phone", @"icons_filled_videocall", @"call_on_filled"],
            WCLiquidGlassActionRedPacket: @[@"icons_filled_red_envelope"],
            WCLiquidGlassActionFiles: @[@"icons_filled_folder", @"icons_filled_file"],
            WCLiquidGlassActionTransfer: @[@"icons_filled_transfer"],
            WCLiquidGlassActionLocation: @[@"icons_filled_location"],
            WCLiquidGlassActionFavorites: @[@"icons_filled_favorites", @"favorites_filled"],
            WCLiquidGlassActionTranslate: @[@"icons_filled_translate"],
            WCLiquidGlassActionScan: @[@"icons_filled_scan"],
            WCLiquidGlassActionPayment: @[@"icons_filled_qr_code"],
            WCLiquidGlassActionContactCard: @[@"icons_filled_me"],
            WCLiquidGlassActionSearchRecords: @[@"icons_filled_search", @"icons_outlined_search"],
            WCLiquidGlassActionVoiceInput: @[@"icons_filled_voiceinput_white", @"icons_filled_voiceinput"],
            WCLiquidGlassActionNewLine: @[@"icons_filled_note"],
            WCLiquidGlassActionMention: @[@"icons_filled_at"],
            WCLiquidGlassActionFullInput: @[@"icons_filled_maxwindow"]
        };
    });
    return assetNames[actionIdentifier] ?: @[];
}

@implementation WCLiquidGlassPreferences

+ (void)registerDefaults {
    [NSUserDefaults.standardUserDefaults registerDefaults:@{
        WCLiquidGlassEnabledKey: @NO,
        WCLiquidGlassSizeModeKey: @1,
        WCLiquidGlassCompactLayoutStyleKey: @(WCLiquidGlassCompactLayoutStyleDoubleCrescent),
        WCLiquidGlassGlassAppearanceKey: @(WCLiquidGlassGlassAppearanceClear),
        WCLiquidGlassChatTimeGlassEnabledKey: @YES,
        WCLiquidGlassWCGlassLongPressMenuEnabledKey: @YES,
        WCLiquidGlassHomeCornersEnabledKey: @NO,
        WCLiquidGlassHomeCornerInsetKey: @16.0,
        WCLiquidGlassHomeCornerRadiusKey: @32.0,
        WCLiquidGlassHomeSeparateCardsEnabledKey: @YES,
        WCLiquidGlassHomeCardGapKey: @8.0,
        WCLiquidGlassHomeLiquidBackgroundEnabledKey: @NO,
        WCLiquidGlassAnchorOnLeftKey: @NO,
        WCLiquidGlassAnchorYKey: @0.62,
        WCLiquidGlassFullCrashReportsEnabledKey: @NO,
        WCLiquidGlassWCGlassIOS27CompatibilityEnabledKey: @YES,
        WCLiquidGlassButtonItemsKey: WCLiquidGlassDefaultButtonItems()
    }];
    WCLiquidGlassMigrateButtonItemsIfNeeded();
}

+ (BOOL)enabled {
    return [NSUserDefaults.standardUserDefaults boolForKey:WCLiquidGlassEnabledKey];
}

+ (void)setEnabled:(BOOL)enabled {
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:WCLiquidGlassEnabledKey];
    WCLiquidGlassNotifyPreferencesChanged();
}

+ (NSInteger)sizeMode {
    return MIN(2, MAX(0, [NSUserDefaults.standardUserDefaults integerForKey:WCLiquidGlassSizeModeKey]));
}

+ (void)setSizeMode:(NSInteger)sizeMode {
    [NSUserDefaults.standardUserDefaults setInteger:MIN(2, MAX(0, sizeMode))
                                            forKey:WCLiquidGlassSizeModeKey];
    WCLiquidGlassNotifyPreferencesChanged();
}

+ (WCLiquidGlassCompactLayoutStyle)compactLayoutStyle {
    NSInteger style = [NSUserDefaults.standardUserDefaults integerForKey:WCLiquidGlassCompactLayoutStyleKey];
    return MIN(WCLiquidGlassCompactLayoutStylePetalCluster,
               MAX(WCLiquidGlassCompactLayoutStyleDoubleCrescent, style));
}

+ (void)setCompactLayoutStyle:(WCLiquidGlassCompactLayoutStyle)style {
    NSInteger clampedStyle = MIN(WCLiquidGlassCompactLayoutStylePetalCluster,
                                 MAX(WCLiquidGlassCompactLayoutStyleDoubleCrescent, style));
    [NSUserDefaults.standardUserDefaults setInteger:clampedStyle forKey:WCLiquidGlassCompactLayoutStyleKey];
    WCLiquidGlassNotifyPreferencesChanged();
}

+ (WCLiquidGlassGlassAppearance)glassAppearance {
    NSInteger appearance = [NSUserDefaults.standardUserDefaults integerForKey:WCLiquidGlassGlassAppearanceKey];
    return MIN(WCLiquidGlassGlassAppearanceTinted,
               MAX(WCLiquidGlassGlassAppearanceClear, appearance));
}

+ (void)setGlassAppearance:(WCLiquidGlassGlassAppearance)appearance {
    NSInteger clampedAppearance = MIN(WCLiquidGlassGlassAppearanceTinted,
                                      MAX(WCLiquidGlassGlassAppearanceClear, appearance));
    if ([self glassAppearance] == clampedAppearance) {
        return;
    }
    [NSUserDefaults.standardUserDefaults setInteger:clampedAppearance
                                            forKey:WCLiquidGlassGlassAppearanceKey];
    WCLiquidGlassNotifyPreferencesChanged();
}

+ (BOOL)chatTimeGlassEnabled {
    return [NSUserDefaults.standardUserDefaults boolForKey:WCLiquidGlassChatTimeGlassEnabledKey];
}

+ (void)setChatTimeGlassEnabled:(BOOL)enabled {
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:WCLiquidGlassChatTimeGlassEnabledKey];
    WCLiquidGlassNotifyPreferencesChanged();
}

+ (BOOL)wcGlassLongPressMenuEnabled {
    return [NSUserDefaults.standardUserDefaults boolForKey:WCLiquidGlassWCGlassLongPressMenuEnabledKey];
}

+ (void)setWCGlassLongPressMenuEnabled:(BOOL)enabled {
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:WCLiquidGlassWCGlassLongPressMenuEnabledKey];
    WCLiquidGlassNotifyPreferencesChanged();
}

+ (BOOL)homeCornersEnabled {
    return [NSUserDefaults.standardUserDefaults boolForKey:WCLiquidGlassHomeCornersEnabledKey];
}

+ (void)setHomeCornersEnabled:(BOOL)enabled {
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:WCLiquidGlassHomeCornersEnabledKey];
    WCLiquidGlassNotifyPreferencesChanged();
}

+ (CGFloat)homeCornerInset {
    return MIN(32.0, MAX(0.0, [NSUserDefaults.standardUserDefaults doubleForKey:WCLiquidGlassHomeCornerInsetKey]));
}

+ (void)setHomeCornerInset:(CGFloat)inset {
    [NSUserDefaults.standardUserDefaults setDouble:MIN(32.0, MAX(0.0, inset)) forKey:WCLiquidGlassHomeCornerInsetKey];
    WCLiquidGlassNotifyPreferencesChanged();
}

+ (CGFloat)homeCornerRadius {
    return MIN(52.0, MAX(0.0, [NSUserDefaults.standardUserDefaults doubleForKey:WCLiquidGlassHomeCornerRadiusKey]));
}

+ (void)setHomeCornerRadius:(CGFloat)radius {
    [NSUserDefaults.standardUserDefaults setDouble:MIN(52.0, MAX(0.0, radius)) forKey:WCLiquidGlassHomeCornerRadiusKey];
    WCLiquidGlassNotifyPreferencesChanged();
}

+ (BOOL)homeSeparateCardsEnabled {
    return [NSUserDefaults.standardUserDefaults boolForKey:WCLiquidGlassHomeSeparateCardsEnabledKey];
}

+ (void)setHomeSeparateCardsEnabled:(BOOL)enabled {
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:WCLiquidGlassHomeSeparateCardsEnabledKey];
    WCLiquidGlassNotifyPreferencesChanged();
}

+ (CGFloat)homeCardGap {
    return MIN(24.0, MAX(0.0, [NSUserDefaults.standardUserDefaults doubleForKey:WCLiquidGlassHomeCardGapKey]));
}

+ (void)setHomeCardGap:(CGFloat)gap {
    [NSUserDefaults.standardUserDefaults setDouble:MIN(24.0, MAX(0.0, gap)) forKey:WCLiquidGlassHomeCardGapKey];
    WCLiquidGlassNotifyPreferencesChanged();
}

+ (BOOL)homeLiquidBackgroundEnabled {
    return [NSUserDefaults.standardUserDefaults boolForKey:WCLiquidGlassHomeLiquidBackgroundEnabledKey];
}

+ (void)setHomeLiquidBackgroundEnabled:(BOOL)enabled {
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:WCLiquidGlassHomeLiquidBackgroundEnabledKey];
    WCLiquidGlassNotifyPreferencesChanged();
}

+ (BOOL)anchorOnLeft {
    return [NSUserDefaults.standardUserDefaults boolForKey:WCLiquidGlassAnchorOnLeftKey];
}

+ (CGFloat)anchorYFraction {
    CGFloat fraction = [NSUserDefaults.standardUserDefaults doubleForKey:WCLiquidGlassAnchorYKey];
    return MIN(0.9, MAX(0.1, fraction));
}

+ (void)setAnchorOnLeft:(BOOL)anchorOnLeft yFraction:(CGFloat)yFraction {
    [NSUserDefaults.standardUserDefaults setBool:anchorOnLeft forKey:WCLiquidGlassAnchorOnLeftKey];
    [NSUserDefaults.standardUserDefaults setDouble:MIN(0.9, MAX(0.1, yFraction))
                                            forKey:WCLiquidGlassAnchorYKey];
}

+ (BOOL)fullCrashReportsEnabled {
    return [NSUserDefaults.standardUserDefaults boolForKey:WCLiquidGlassFullCrashReportsEnabledKey];
}

+ (void)setFullCrashReportsEnabled:(BOOL)enabled {
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:WCLiquidGlassFullCrashReportsEnabledKey];
    WCLiquidGlassNotifyPreferencesChanged();
}

+ (BOOL)wcGlassIOS27CompatibilityEnabled {
    return [NSUserDefaults.standardUserDefaults boolForKey:WCLiquidGlassWCGlassIOS27CompatibilityEnabledKey];
}

+ (void)setWCGlassIOS27CompatibilityEnabled:(BOOL)enabled {
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:WCLiquidGlassWCGlassIOS27CompatibilityEnabledKey];
    [NSNotificationCenter.defaultCenter postNotificationName:WCLiquidGlassWCGlassCompatibilityDidChangeNotification
                                                      object:nil];
}

+ (NSArray<NSDictionary<NSString *, id> *> *)buttonItems {
    NSArray *storedItems = [NSUserDefaults.standardUserDefaults arrayForKey:WCLiquidGlassButtonItemsKey];
    if (![storedItems isKindOfClass:NSArray.class] || storedItems.count == 0) {
        return WCLiquidGlassDefaultButtonItems();
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *validItems = [NSMutableArray array];
    for (id item in storedItems) {
        if (![item isKindOfClass:NSDictionary.class] ||
            ![item[@"slot"] isKindOfClass:NSString.class] ||
            ![item[@"action"] isKindOfClass:NSString.class]) {
            continue;
        }
        NSString *actionIdentifier = item[@"action"];
        if (WCLiquidGlassActionWasRemoved(actionIdentifier)) {
            continue;
        }
        [validItems addObject:item];
    }
    if (validItems.count == 0) {
        return WCLiquidGlassDefaultButtonItems();
    }
    return validItems.copy;
}

+ (void)setButtonItems:(NSArray<NSDictionary<NSString *, id> *> *)items {
    [NSUserDefaults.standardUserDefaults setObject:items forKey:WCLiquidGlassButtonItemsKey];
    WCLiquidGlassNotifyPreferencesChanged();
}

+ (void)restoreDefaultButtonItems {
    [NSUserDefaults.standardUserDefaults removeObjectForKey:WCLiquidGlassButtonItemsKey];
    WCLiquidGlassNotifyPreferencesChanged();
}

+ (void)restoreDefaults {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults removeObjectForKey:WCLiquidGlassEnabledKey];
    [defaults removeObjectForKey:WCLiquidGlassSizeModeKey];
    [defaults removeObjectForKey:WCLiquidGlassCompactLayoutStyleKey];
    [defaults removeObjectForKey:WCLiquidGlassGlassAppearanceKey];
    [defaults removeObjectForKey:WCLiquidGlassHomeCornersEnabledKey];
    [defaults removeObjectForKey:WCLiquidGlassHomeCornerInsetKey];
    [defaults removeObjectForKey:WCLiquidGlassHomeCornerRadiusKey];
    [defaults removeObjectForKey:WCLiquidGlassHomeSeparateCardsEnabledKey];
    [defaults removeObjectForKey:WCLiquidGlassHomeCardGapKey];
    [defaults removeObjectForKey:WCLiquidGlassHomeLiquidBackgroundEnabledKey];
    [defaults removeObjectForKey:WCLiquidGlassChatTimeGlassEnabledKey];
    [defaults removeObjectForKey:WCLiquidGlassWCGlassLongPressMenuEnabledKey];
    [defaults removeObjectForKey:WCLiquidGlassAnchorOnLeftKey];
    [defaults removeObjectForKey:WCLiquidGlassAnchorYKey];
    [defaults removeObjectForKey:WCLiquidGlassFullCrashReportsEnabledKey];
    [defaults removeObjectForKey:WCLiquidGlassWCGlassIOS27CompatibilityEnabledKey];
    [defaults removeObjectForKey:WCLiquidGlassButtonItemsKey];
    [defaults removeObjectForKey:WCLiquidGlassLegacySearchRecordsMigrationKey];
    [defaults removeObjectForKey:WCLiquidGlassSearchRecordsMigrationKey];
    WCLiquidGlassNotifyPreferencesChanged();
    [NSNotificationCenter.defaultCenter postNotificationName:WCLiquidGlassWCGlassCompatibilityDidChangeNotification
                                                      object:nil];
}

@end
