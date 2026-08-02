#import "WCLiquidGlassMessageNotificationSettings.h"

#import "WCLiquidGlassHomeCorners.h"
#import "WCLiquidGlassPreferences.h"

typedef NS_ENUM(NSInteger, WCLiquidGlassMessageNotificationControlTag) {
    WCLiquidGlassMessageNotificationControlTagCornerRadius = 1,
    WCLiquidGlassMessageNotificationControlTagPadding
};

static NSString *WCLiquidGlassMessageNotificationDisplayValue(CGFloat value) {
    return [NSString stringWithFormat:@"%.0f pt", value];
}

static NSString *WCLiquidGlassMessageNotificationAppearanceTitle(
    WCLiquidGlassGlassAppearance appearance) {
    switch (appearance) {
        case WCLiquidGlassGlassAppearanceBalanced:
            return @"平衡";
        case WCLiquidGlassGlassAppearanceTinted:
            return @"色调";
        default:
            return @"透明";
    }
}

@implementation WCLiquidGlassMessageNotificationSettingsController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"消息通知液态";
    WCLiquidGlassConfigureSettingsTableBackground(self);
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 64.0;
    self.tableView.separatorColor = [UIColor.separatorColor colorWithAlphaComponent:0.30];
    [WCLiquidGlassPreferences registerDefaults];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(wc_preferencesChanged:)
                                               name:WCLiquidGlassPreferencesDidChangeNotification
                                             object:nil];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 4;
}

- (void)tableView:(UITableView *)tableView
  willDisplayCell:(UITableViewCell *)cell
forRowAtIndexPath:(NSIndexPath *)indexPath {
    WCLiquidGlassStyleSettingsCardCell(cell, indexPath, tableView);
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    return WCLiquidGlassSettingsSectionHeader(@"前台新消息弹窗");
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return WCLiquidGlassSettingsSectionHeaderHeight();
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    return WCLiquidGlassSettingsFooter(@"圆角与四周内边距仅调整液态背景，不改变微信原有头像、文字和按钮布局。液态效果为消息通知单独保存。");
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return WCLiquidGlassSettingsFooterHeight(@"圆角与四周内边距仅调整液态背景，不改变微信原有头像、文字和按钮布局。液态效果为消息通知单独保存。", 76.0);
}

- (UITableViewCell *)wc_cellWithTitle:(NSString *)title
                                detail:(nullable NSString *)detail
                               enabled:(BOOL)enabled
                            identifier:(NSString *)identifier {
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    }
    WCLiquidGlassConfigureSettingsCell(cell,
                                        title,
                                        detail,
                                        nil,
                                        enabled ? UIColor.labelColor : UIColor.tertiaryLabelColor);
    cell.contentView.alpha = enabled ? 1.0 : 0.45;
    cell.selectionStyle = enabled ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    cell.userInteractionEnabled = enabled;
    return cell;
}

- (UITableViewCell *)wc_sliderCellWithTitle:(NSString *)title
                                       value:(CGFloat)value
                                     maximum:(CGFloat)maximum
                                         tag:(WCLiquidGlassMessageNotificationControlTag)tag
                                     enabled:(BOOL)enabled {
    UITableViewCell *cell = [self wc_cellWithTitle:title
                                             detail:WCLiquidGlassMessageNotificationDisplayValue(value)
                                            enabled:enabled
                                         identifier:@"WCLiquidGlassMessageNotificationSliderCell"];
    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(0.0, 0.0, 152.0, 31.0)];
    slider.minimumValue = 0.0;
    slider.maximumValue = maximum;
    slider.value = value;
    slider.tag = tag;
    slider.enabled = enabled;
    [slider addTarget:self action:@selector(wc_sliderChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = slider;
    cell.accessibilityHint = enabled ? @"点按滑块外的区域可直接输入数值" : nil;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    BOOL active = WCLiquidGlassPreferences.messageNotificationGlassEnabled;
    switch (indexPath.row) {
        case 0: {
            UITableViewCell *cell = [self wc_cellWithTitle:@"启用消息通知液态"
                                                     detail:@"微信前台新消息弹窗"
                                                    enabled:YES
                                                 identifier:@"WCLiquidGlassMessageNotificationSwitchCell"];
            UISwitch *toggle = [[UISwitch alloc] init];
            toggle.on = active;
            [toggle addTarget:self action:@selector(wc_enabledChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = toggle;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            return cell;
        }
        case 1:
            return [self wc_sliderCellWithTitle:@"圆角"
                                           value:WCLiquidGlassPreferences.messageNotificationCornerRadius
                                         maximum:64.0
                                             tag:WCLiquidGlassMessageNotificationControlTagCornerRadius
                                         enabled:active];
        case 2:
            return [self wc_sliderCellWithTitle:@"四周内边距"
                                           value:WCLiquidGlassPreferences.messageNotificationPadding
                                         maximum:32.0
                                             tag:WCLiquidGlassMessageNotificationControlTagPadding
                                         enabled:active];
        case 3: {
            UITableViewCell *cell = [self wc_cellWithTitle:@"液态效果"
                                                     detail:WCLiquidGlassMessageNotificationAppearanceTitle(
                                                         WCLiquidGlassPreferences.messageNotificationGlassAppearance)
                                                    enabled:active
                                                 identifier:@"WCLiquidGlassMessageNotificationAppearanceCell"];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return cell;
        }
        default:
            return [self wc_cellWithTitle:@"" detail:nil enabled:NO identifier:@"WCLiquidGlassMessageNotificationUnusedCell"];
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (!WCLiquidGlassPreferences.messageNotificationGlassEnabled) {
        return;
    }
    if (indexPath.row == 1) {
        [self wc_presentValueInputWithTitle:@"圆角"
                                      value:WCLiquidGlassPreferences.messageNotificationCornerRadius
                                    maximum:64.0
                                     setter:^(CGFloat value) {
            [WCLiquidGlassPreferences setMessageNotificationCornerRadius:value];
        }];
    } else if (indexPath.row == 2) {
        [self wc_presentValueInputWithTitle:@"四周内边距"
                                      value:WCLiquidGlassPreferences.messageNotificationPadding
                                    maximum:32.0
                                     setter:^(CGFloat value) {
            [WCLiquidGlassPreferences setMessageNotificationPadding:value];
        }];
    } else if (indexPath.row == 3) {
        [self wc_presentAppearancePickerFromView:[tableView cellForRowAtIndexPath:indexPath]];
    }
}

- (void)wc_enabledChanged:(UISwitch *)sender {
    [WCLiquidGlassPreferences setMessageNotificationGlassEnabled:sender.isOn];
}

- (void)wc_sliderChanged:(UISlider *)slider {
    CGFloat value = round(slider.value);
    [slider setValue:value animated:NO];
    if (slider.tag == WCLiquidGlassMessageNotificationControlTagCornerRadius) {
        [WCLiquidGlassPreferences setMessageNotificationCornerRadius:value];
    } else if (slider.tag == WCLiquidGlassMessageNotificationControlTagPadding) {
        [WCLiquidGlassPreferences setMessageNotificationPadding:value];
    }
}

- (void)wc_presentValueInputWithTitle:(NSString *)title
                                 value:(CGFloat)value
                               maximum:(CGFloat)maximum
                                setter:(void (^)(CGFloat value))setter {
    NSString *message = [NSString stringWithFormat:@"输入 0–%.0f 之间的 pt 数值", maximum];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.keyboardType = UIKeyboardTypeDecimalPad;
        textField.text = [NSString stringWithFormat:@"%.0f", value];
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定"
                                             style:UIAlertActionStyleDefault
                                           handler:^(__unused UIAlertAction *action) {
        setter(MIN(maximum, MAX(0.0, alert.textFields.firstObject.text.doubleValue)));
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)wc_presentAppearancePickerFromView:(UIView *)sourceView {
    UIAlertController *picker = [UIAlertController alertControllerWithTitle:@"液态效果"
                                                                    message:@"仅应用于消息通知弹窗"
                                                             preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray<NSString *> *titles = @[@"透明", @"平衡", @"色调"];
    for (NSInteger appearance = WCLiquidGlassGlassAppearanceClear;
         appearance <= WCLiquidGlassGlassAppearanceTinted;
         appearance += 1) {
        NSString *title = titles[(NSUInteger)appearance];
        if (appearance == WCLiquidGlassPreferences.messageNotificationGlassAppearance) {
            title = [title stringByAppendingString:@" ✓"];
        }
        [picker addAction:[UIAlertAction actionWithTitle:title
                                                      style:UIAlertActionStyleDefault
                                                    handler:^(__unused UIAlertAction *action) {
            [WCLiquidGlassPreferences setMessageNotificationGlassAppearance:
                (WCLiquidGlassGlassAppearance)appearance];
        }]];
    }
    [picker addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    picker.popoverPresentationController.sourceView = sourceView;
    picker.popoverPresentationController.sourceRect = sourceView.bounds;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)wc_preferencesChanged:(NSNotification *)notification {
    [self.tableView reloadData];
}

@end
