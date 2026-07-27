#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const WCLiquidGlassPreferencesDidChangeNotification;
extern NSNotificationName const WCLiquidGlassWCGlassCompatibilityDidChangeNotification;

extern NSString *const WCLiquidGlassActionSettings;
extern NSString *const WCLiquidGlassActionWCGlassSettings;
extern NSString *const WCLiquidGlassActionPlugins;
extern NSString *const WCLiquidGlassActionDoutuAssistant;
extern NSString *const WCLiquidGlassActionMoments;
extern NSString *const WCLiquidGlassActionChannels;
extern NSString *const WCLiquidGlassActionAlbum;
extern NSString *const WCLiquidGlassActionCamera;
extern NSString *const WCLiquidGlassActionVideoCall;
extern NSString *const WCLiquidGlassActionRedPacket;
extern NSString *const WCLiquidGlassActionFiles;
extern NSString *const WCLiquidGlassActionTransfer;
extern NSString *const WCLiquidGlassActionLocation;
extern NSString *const WCLiquidGlassActionFavorites;
extern NSString *const WCLiquidGlassActionTranslate;
extern NSString *const WCLiquidGlassActionScan;
extern NSString *const WCLiquidGlassActionPayment;
extern NSString *const WCLiquidGlassActionContactCard;
extern NSString *const WCLiquidGlassActionSearchRecords;
extern NSString *const WCLiquidGlassActionVoiceInput;
extern NSString *const WCLiquidGlassActionNewLine;
extern NSString *const WCLiquidGlassActionMention;
extern NSString *const WCLiquidGlassActionFullInput;

typedef NS_ENUM(NSInteger, WCLiquidGlassCompactLayoutStyle) {
    WCLiquidGlassCompactLayoutStyleDoubleCrescent = 0,
    WCLiquidGlassCompactLayoutStyleSCurve,
    WCLiquidGlassCompactLayoutStyleWideFan,
    WCLiquidGlassCompactLayoutStylePetalCluster
};

typedef NS_ENUM(NSInteger, WCLiquidGlassGlassAppearance) {
    WCLiquidGlassGlassAppearanceClear = 0,
    WCLiquidGlassGlassAppearanceBalanced,
    WCLiquidGlassGlassAppearanceTinted
};

@interface WCLiquidGlassPreferences : NSObject

+ (void)registerDefaults;
+ (BOOL)enabled;
+ (void)setEnabled:(BOOL)enabled;
+ (NSInteger)sizeMode;
+ (void)setSizeMode:(NSInteger)sizeMode;
+ (WCLiquidGlassCompactLayoutStyle)compactLayoutStyle;
+ (void)setCompactLayoutStyle:(WCLiquidGlassCompactLayoutStyle)style;
+ (WCLiquidGlassGlassAppearance)glassAppearance;
+ (void)setGlassAppearance:(WCLiquidGlassGlassAppearance)appearance;
+ (BOOL)chatTimeGlassEnabled;
+ (void)setChatTimeGlassEnabled:(BOOL)enabled;
+ (BOOL)homeCornersEnabled;
+ (void)setHomeCornersEnabled:(BOOL)enabled;
+ (CGFloat)homeCornerInset;
+ (void)setHomeCornerInset:(CGFloat)inset;
+ (CGFloat)homeCornerRadius;
+ (void)setHomeCornerRadius:(CGFloat)radius;
+ (BOOL)homeSeparateCardsEnabled;
+ (void)setHomeSeparateCardsEnabled:(BOOL)enabled;
+ (CGFloat)homeCardGap;
+ (void)setHomeCardGap:(CGFloat)gap;
+ (BOOL)homePinnedCardGapEnabled;
+ (void)setHomePinnedCardGapEnabled:(BOOL)enabled;
+ (BOOL)homeLiquidBackgroundEnabled;
+ (void)setHomeLiquidBackgroundEnabled:(BOOL)enabled;
+ (NSString *)homeCardBackgroundColorHex;
+ (void)setHomeCardBackgroundColorHex:(NSString *)hex;
+ (BOOL)homeCornersSyncOtherTabsEnabled;
+ (void)setHomeCornersSyncOtherTabsEnabled:(BOOL)enabled;
+ (CGFloat)homeOtherTabsCornerRadius;
+ (void)setHomeOtherTabsCornerRadius:(CGFloat)radius;
+ (BOOL)anchorOnLeft;
+ (CGFloat)anchorYFraction;
+ (void)setAnchorOnLeft:(BOOL)anchorOnLeft yFraction:(CGFloat)yFraction;
+ (BOOL)fullCrashReportsEnabled;
+ (void)setFullCrashReportsEnabled:(BOOL)enabled;
+ (BOOL)wcGlassIOS27CompatibilityEnabled;
+ (void)setWCGlassIOS27CompatibilityEnabled:(BOOL)enabled;
+ (NSArray<NSDictionary<NSString *, id> *> *)buttonItems;
+ (void)setButtonItems:(NSArray<NSDictionary<NSString *, id> *> *)items;
+ (void)restoreDefaultButtonItems;
+ (void)restoreDefaults;

@end

NSArray<NSDictionary<NSString *, NSString *> *> *WCLiquidGlassActionCatalog(void);
NSString *WCLiquidGlassActionTitle(NSString *actionIdentifier);
NSString *WCLiquidGlassActionSymbol(NSString *actionIdentifier);
NSArray<NSString *> *WCLiquidGlassActionAssetNames(NSString *actionIdentifier);

NS_ASSUME_NONNULL_END
