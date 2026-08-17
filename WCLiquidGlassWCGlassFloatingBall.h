#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Isolated WCGlass-style floating-ball implementation.
/// It intentionally owns its preferences and view hierarchy; the existing
/// WCLiquidGlass menu implementation does not call into this class.
@interface WCLiquidGlassWCGlassFloatingBallManager : NSObject

+ (instancetype)sharedManager;
- (void)install;
- (void)refresh;
- (void)setEnabled:(BOOL)enabled;

@property(nonatomic, readonly, getter=isEnabled) BOOL enabled;

@end

NS_ASSUME_NONNULL_END
