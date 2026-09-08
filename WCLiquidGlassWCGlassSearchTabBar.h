#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

void WCLiquidGlassInstallWCGlassSearchTabBarHooks(void);
Class _Nullable WCLiquidGlassWCGlassTabBarOverlayClass(void);
BOOL WCLiquidGlassWCGlassFloatingOverlayIsActiveForTabBar(UIView *tabBar);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
