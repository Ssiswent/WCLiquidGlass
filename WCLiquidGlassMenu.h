#import <UIKit/UIKit.h>

#import "WCLiquidGlassPreferences.h"

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

UIImage *WCLiquidGlassImageForAction(NSString *actionIdentifier, CGFloat buttonDiameter);
UIImage *WCLiquidGlassBrandIconImage(CGFloat size, BOOL includesBackground);
UIVisualEffect *WCLiquidGlassCurrentGlassEffect(void);
UIVisualEffect *WCLiquidGlassGlassEffectForAppearance(WCLiquidGlassGlassAppearance appearance);
UIVisualEffect * _Nullable WCLiquidGlassCurrentGlassContainerEffect(void);
typedef NS_ENUM(NSInteger, WCLiquidGlassSettingsIconKind) {
    WCLiquidGlassSettingsIconKindBrand,
    WCLiquidGlassSettingsIconKindMenu,
    WCLiquidGlassSettingsIconKindSize,
    WCLiquidGlassSettingsIconKindCompactLayout,
    WCLiquidGlassSettingsIconKindGlassAppearance,
    WCLiquidGlassSettingsIconKindActions,
    WCLiquidGlassSettingsIconKindCompatibility,
    WCLiquidGlassSettingsIconKindCrashCapture,
    WCLiquidGlassSettingsIconKindCrashLogs,
    WCLiquidGlassSettingsIconKindRestore
};
UIImage *WCLiquidGlassSettingsIconImage(WCLiquidGlassSettingsIconKind kind, CGFloat size);
UIView *WCLiquidGlassCreateStaticMenuPreview(void);
void WCLiquidGlassRefreshStaticMenuPreview(UIView *preview);
UIView * _Nullable WCLiquidGlassCurrentChatInputView(void);
BOOL WCLiquidGlassCurrentChatInputHasText(void);
BOOL WCLiquidGlassShouldReportManualTextEdit(void);
void WCLiquidGlassRefreshDoutuConfiguration(void);
void WCLiquidGlassUpdateDoutuButtonVisibility(id inputToolView);
id _Nullable WCLiquidGlassCurrentTabController(void);
extern NSString *const WCLiquidGlassManualTextEditNotification;

#ifdef __cplusplus
}
#endif

@interface WCLiquidGlassManager : NSObject

+ (instancetype)sharedManager;
- (void)start;
- (void)reload;
- (void)setNativeMenuTestIsolationEnabled:(BOOL)enabled;

@end

NS_ASSUME_NONNULL_END
