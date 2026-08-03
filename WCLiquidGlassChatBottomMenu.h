#import <Foundation/Foundation.h>

@class UIView;

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

/// Adds the plugin's material to WeChat's native chat attachment panel.
/// The hook only observes the native panel lifecycle; it does not depend on
/// ThemeBox/素材仓 preferences, files, or runtime classes.
void WCLiquidGlassInstallChatBottomMenuHooks(void);

/// Re-scans a just-laid-out input tool hierarchy. WeChat creates the
/// attachment panel lazily, so the outer MMInputToolView can be the only
/// stable lifecycle callback available before the panel classes are loaded.
void WCLiquidGlassRefreshChatBottomMenuHierarchy(UIView *rootView);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
