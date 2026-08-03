#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

/// Adds the plugin's material to WeChat's native chat attachment panel.
/// The hook only observes the native panel lifecycle; it does not depend on
/// ThemeBox/素材仓 preferences, files, or runtime classes.
void WCLiquidGlassInstallChatBottomMenuHooks(void);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
