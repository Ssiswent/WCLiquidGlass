#import <UIKit/UIKit.h>

#import "WCLiquidGlassPreferences.h"

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

UIImage *WCLiquidGlassImageForAction(NSString *actionIdentifier, CGFloat buttonDiameter);
UIImage * _Nullable WCLiquidGlassImageNamedFromCandidates(NSArray<NSString *> *assetNames);
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
void WCLiquidGlassCaptureWCGlassRegistration(NSString *title,
                                             NSString *version,
                                             NSString *controllerName);
NSDictionary<NSString *, NSString *> * _Nullable WCLiquidGlassCurrentWCGlassRegistration(void);
void WCLiquidGlassBeginWCGlassPluginListObservation(void);
void WCLiquidGlassObserveWCGlassPluginListNavigation(UIViewController * _Nullable sourceController,
                                                     UIViewController * _Nullable destinationController,
                                                     BOOL completed);
extern NSString *const WCLiquidGlassManualTextEditNotification;

#ifdef __cplusplus
}
#endif

@interface WCLiquidGlassManager : NSObject

+ (instancetype)sharedManager;
- (void)start;
- (void)reload;

@end

NS_ASSUME_NONNULL_END
