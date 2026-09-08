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
void WCLiquidGlassLayoutChatToolbarForInput(id inputToolView);
void WCLiquidGlassApplyPendingChatTableAnchor(UITableView *tableView);
void WCLiquidGlassTraceChatToolbarForInput(id inputToolView, NSString *source);
UIEdgeInsets WCLiquidGlassChatTableInsetForHost(UITableView *tableView,
                                                 UIEdgeInsets inset,
                                                 BOOL indicatorInset);
void WCLiquidGlassTraceChatTableInsetMutation(UITableView *tableView,
                                               NSString *source,
                                               UIEdgeInsets requested,
                                               UIEdgeInsets applied,
                                               UIEdgeInsets beforeInset,
                                               CGPoint beforeOffset);
id _Nullable WCLiquidGlassCurrentTabController(void);
NSInteger WCLiquidGlassCurrentTabIndex(id _Nullable tabController);
BOOL WCLiquidGlassIsAtCurrentTabRoot(id _Nullable tabController);
BOOL WCLiquidGlassCanSelectTab(id _Nullable tabController, NSInteger index);
UIImage * _Nullable WCLiquidGlassNativeTabImage(id _Nullable tabController, NSInteger index);
UIWindow * _Nullable WCLiquidGlassApplicationWindow(void);
void WCLiquidGlassPerformActionIdentifier(NSString *actionIdentifier);
NSArray<NSDictionary<NSString *, id> *> *WCLiquidGlassFloatingTabBarActionItems(void);
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
