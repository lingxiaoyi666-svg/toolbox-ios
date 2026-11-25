#import <UIKit/UIKit.h>

@interface BiliPureSettingsVC : UITableViewController
@end

/// 点击设置页「测试」那一行时调用（由 Tweak 注入到 BBPhoneSettingMainVC）
void hg_openBiliPureSettings(id self, SEL _cmd);
