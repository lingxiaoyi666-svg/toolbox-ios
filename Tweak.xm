#import "HGCore.h"
#import "HGSettings.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <string.h>

#pragma mark - 全局安全模式

static BOOL gSafeMode = NO;

static NSString *HGFlagPath(void) {
    return [HGLogPath().stringByDeletingLastPathComponent
            stringByAppendingPathComponent:@"BiliPure.launching"];
}

#pragma mark - 开屏广告

%hook BFCSplashManager

- (void)showSplashWithStyle:(long)style delegate:(id)delegate launchInfo:(id)launchInfo {
    if (!gSafeMode && HGOn(@"splash")) {
        HGLog(@"拦截开屏广告 style=%ld", (long)style);
        return;
    }
    %orig;
}

%end

#pragma mark - 广告视图

%hook UIView

- (void)didMoveToWindow {
    %orig;

    if (gSafeMode) return;

    @try {
        if (!self.window) return;
        Class cls = [self class];

        if (HGOn(@"adview") && HGIsAdClass(cls)) {
            if (!self.hidden) HGLog(@"隐藏广告视图 %s", class_getName(cls));
            self.hidden = YES;
            self.alpha = 0.0;
            return;
        }

        if (HGOn(@"hotsearch")) {
            const char *n = class_getName(cls);
            if (n && strncmp(n, "BBHotTopic", 10) == 0 &&
                !strstr(n, "VC") && !strstr(n, "Controller") &&
                !strstr(n, "Model") && !strstr(n, "VM") && !strstr(n, "Service")) {
                self.hidden = YES;
                self.alpha = 0.0;
            }
        }
    } @catch (NSException *e) {}
}

%end

#pragma mark - 弹窗拦截

static BOOL HGPopupBlocked(id item) {
    if (!item) return NO;
    NSString *hay = @"";
    @try {
        hay = [NSString stringWithFormat:@"%@ %@", NSStringFromClass([item class]), [item description]];
    } @catch (NSException *e) {
        return NO;
    }
    if (!hay.length) return NO;

    if (HGOn(@"teenager")) {
        if ([hay rangeOfString:@"teenager" options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
        if ([hay rangeOfString:@"Teenager"].location != NSNotFound) return YES;
    }
    if (HGOn(@"update")) {
        if ([hay rangeOfString:@"upgrade" options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
        if ([hay rangeOfString:@"UpdateNotice" options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }
    return NO;
}

%hook BFCPopper

- (void)showPopUp:(id)item {
    if (!gSafeMode && HGOn(@"popup") && HGPopupBlocked(item)) {
        HGLog(@"拦截弹窗 %@", NSStringFromClass([item class]));
        return;
    }
    %orig;
}

%end

#pragma mark - 设置页入口

static NSString *const kHGEntrySel = @"hg_openBiliPureSettings";

static BOOL HGDataHasEntry(NSArray *datas) {
    for (id m in datas) {
        @try {
            NSString *t = [m valueForKey:@"tapMethod"];
            if ([t isKindOfClass:[NSString class]] && [t isEqualToString:kHGEntrySel]) return YES;
        } @catch (NSException *e) {}
    }
    return NO;
}

static id HGMakeEntryModel(void) {
    Class M = NSClassFromString(@"BBPhoneSettingModel");
    if (!M) {
        HGLog(@"找不到 BBPhoneSettingModel，无法插入入口");
        return nil;
    }
    id m = nil;
    @try {
        m = [[M alloc] init];
        [m setValue:@"测试" forKey:@"title"];
        [m setValue:@"插件功能开关" forKey:@"subTitle"];
        [m setValue:@"测试" forKey:@"vcTitle"];
        [m setValue:kHGEntrySel forKey:@"tapMethod"];
        [m setValue:@YES forKey:@"shouldShowArrow"];
        [m setValue:@NO forKey:@"automaticCalculation"];
        [m setValue:@56 forKey:@"height"];
    } @catch (NSException *e) {
        HGLog(@"构造入口 model 失败: %@", e.reason);
        return nil;
    }
    return m;
}

static NSArray *HGPrependEntry(NSArray *datas) {
    if (![datas isKindOfClass:[NSArray class]]) return datas;
    if (HGDataHasEntry(datas)) return datas;
    id m = HGMakeEntryModel();
    if (!m) return datas;

    NSMutableArray *arr = [datas mutableCopy];
    [arr insertObject:m atIndex:0];
    HGLog(@"设置页入口已插入，共 %lu 项", (unsigned long)arr.count);
    return arr;
}

%hook BBPhoneSettingBaseVC

- (void)setDatas:(NSArray *)datas {
    NSArray *d = datas;
    if (!gSafeMode) {
        @try {
            Class selfCls = object_getClass(self);
            const char *cn = selfCls ? class_getName(selfCls) : "";
            if (cn && strcmp(cn, "BBPhoneSettingMainVC") == 0) {
                d = HGPrependEntry(datas);
            }
        } @catch (NSException *e) {}
    }
    %orig(d);
}

%end

#pragma mark - 入口

%ctor {
    @autoreleasepool {
        HGInstallCrashHandler();

        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *flag = HGFlagPath();

        if (flag && [fm fileExistsAtPath:flag]) {
            gSafeMode = YES;
            HGLog(@"上次启动未正常完成 → 本次进入安全模式，所有拦截关闭");
            [fm removeItemAtPath:flag error:nil];
        } else if (flag) {
            [fm createFileAtPath:flag contents:[NSData data] attributes:nil];
        }

        HGLog(@"BiliPure 已加载 pid=%d safeMode=%d", getpid(), (int)gSafeMode);
        if (!gSafeMode) HGDumpConfig();

        Class mainVC = objc_getClass("BBPhoneSettingMainVC");
        if (mainVC) {
            class_addMethod(mainVC,
                            NSSelectorFromString(kHGEntrySel),
                            (IMP)hg_openBiliPureSettings,
                            "v@:");
            HGLog(@"已注册设置页入口方法 %@", kHGEntrySel);
        } else {
            HGLog(@"找不到 BBPhoneSettingMainVC");
        }

        if (!gSafeMode) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [fm removeItemAtPath:flag error:nil];
                HGLog(@"启动完成，安全标记已清除");
            });
        }
    }
}
