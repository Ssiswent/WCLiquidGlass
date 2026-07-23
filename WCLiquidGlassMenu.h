#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

UIImage *WCLiquidGlassImageForAction(NSString *actionIdentifier, CGFloat buttonDiameter);
UIImage *WCLiquidGlassBrandIconImage(CGFloat size, BOOL includesBackground);
typedef NS_ENUM(NSInteger, WCLiquidGlassSettingsIconKind) {
    WCLiquidGlassSettingsIconKindBrand,
    WCLiquidGlassSettingsIconKindMenu,
    WCLiquidGlassSettingsIconKindSize,
    WCLiquidGlassSettingsIconKindCompactLayout,
    WCLiquidGlassSettingsIconKindActions,
    WCLiquidGlassSettingsIconKindCompatibility,
    WCLiquidGlassSettingsIconKindCrashCapture,
    WCLiquidGlassSettingsIconKindCrashLogs,
    WCLiquidGlassSettingsIconKindRestore
};
UIImage *WCLiquidGlassSettingsIconImage(WCLiquidGlassSettingsIconKind kind, CGFloat size);
UIView * _Nullable WCLiquidGlassCurrentChatInputView(void);
BOOL WCLiquidGlassCurrentChatInputHasText(void);
BOOL WCLiquidGlassShouldReportManualTextEdit(void);
void WCLiquidGlassRefreshDoutuConfiguration(void);
void WCLiquidGlassUpdateDoutuButtonVisibility(id inputToolView);
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
