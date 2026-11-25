#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 读取开关，未配置时返回默认值（全部默认开启）
BOOL HGOn(NSString *key);

/// 日志：NSLog + 写 /var/mobile/Library/Preferences/com.hg.bilipure.log
void HGLog(NSString *fmt, ...);

/// 当前是否为广告类（带缓存）
BOOL HGIsAdClass(Class cls);

/// 打印各开关到日志
void HGDumpConfig(void);

/// 写开关（同时清缓存）
void HGSetOn(NSString *key, BOOL value);

/// 日志文件路径（App 沙盒 Documents/BiliPure.log）
NSString *HGLogPath(void);

/// 安装崩溃捕获，把 signal 与调用栈写进日志
void HGInstallCrashHandler(void);

#ifdef __cplusplus
}
#endif

#define HG_PREF_DOMAIN @"com.hg.bilipure"
