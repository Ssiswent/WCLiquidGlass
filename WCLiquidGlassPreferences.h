#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const WCLiquidGlassPreferencesDidChangeNotification;
extern NSNotificationName const WCLiquidGlassWCGlassCompatibilityDidChangeNotification;

extern NSString *const WCLiquidGlassActionSettings;
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

@interface WCLiquidGlassPreferences : NSObject

+ (void)registerDefaults;
+ (BOOL)enabled;
+ (void)setEnabled:(BOOL)enabled;
+ (NSInteger)sizeMode;
+ (void)setSizeMode:(NSInteger)sizeMode;
+ (WCLiquidGlassCompactLayoutStyle)compactLayoutStyle;
+ (void)setCompactLayoutStyle:(WCLiquidGlassCompactLayoutStyle)style;
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
