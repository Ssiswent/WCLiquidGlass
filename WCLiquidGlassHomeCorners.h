#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

void WCLiquidGlassInstallHomeCornersHooks(void);
void WCLiquidGlassCaptureCurrentPageHierarchyDiagnostics(void);
void WCLiquidGlassConfigureSettingsTableBackground(UITableViewController *controller);
void WCLiquidGlassStyleSettingsCardCell(UITableViewCell *cell, NSIndexPath *indexPath, UITableView *tableView);
UIView *WCLiquidGlassSettingsSectionHeader(NSString *text);
CGFloat WCLiquidGlassSettingsSectionHeaderHeight(void);
UIView *WCLiquidGlassSettingsFooter(NSString *text);
CGFloat WCLiquidGlassSettingsFooterHeight(NSString *text, CGFloat minimumHeight);
void WCLiquidGlassConfigureSettingsCell(UITableViewCell *cell,
                                        NSString *title,
                                        NSString *secondaryText,
                                        UIImage * _Nullable image,
                                        UIColor *titleColor);

#ifdef __cplusplus
}
#endif

@interface WCLiquidGlassHomeCornersController : UITableViewController
@end

NS_ASSUME_NONNULL_END
