#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

void WCLiquidGlassInstallFloatingTabBarHooks(void);
BOOL WCLiquidGlassFloatingTabBarIsBlockedByWCGlass(void);

#ifdef __cplusplus
}
#endif

@interface WCLiquidGlassFloatingTabBarController : NSObject

+ (instancetype)sharedController;
- (void)start;
- (void)setNeedsUpdate;

@end

NS_ASSUME_NONNULL_END
