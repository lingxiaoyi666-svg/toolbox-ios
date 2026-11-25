//  HGHooks.m
//  纯 Objective-C runtime hook 实现 —— 不使用 Logos / %hook
//  这样编译产物不再依赖 CydiaSubstrate，非越狱注入（全能签/Sideloadly）可直接加载。

#import "HGCore.h"
#import "HGSettings.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <string.h>
#import <unistd.h>


static BOOL gSafeMode = NO;

static NSString *HGFlagPath(void) {
    NSString *log = HGLogPath();
    if (!log) return nil;
    return [log.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"BiliPure.launching"];
}

#pragma mark - 通用 hook 工具

static IMP HGSetImpl(Class cls, const char *selName, IMP newImp) {
    if (!cls || !selName || !newImp) return NULL;
    SEL sel = sel_registerName(selName);
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return NULL;
    return method_setImplementation(m, newImp);
}

#pragma mark - 1 开屏广告

static IMP gOrig_splash = NULL;

static void hg_showSplash(id self, SEL _cmd, long style, id delegate, id launchInfo) {
    if (!gSafeMode && HGOn(@"splash")) {
        HGLog(@"拦截开屏广告 style=%ld", style);
        return;
    }
    if (gOrig_splash) {
        ((void (*)(id, SEL, long, id, id))gOrig_splash)(self, _cmd, style, delegate, launchInfo);
    }
}

#pragma mark - 2 广告视图 / 热搜

static IMP gOrig_didMoveToWindow = NULL;

static void hg_didMoveToWindow(id self, SEL _cmd) {
    if (gOrig_didMoveToWindow) {
        ((void (*)(id, SEL))gOrig_didMoveToWindow)(self, _cmd);
    }
    if (gSafeMode) return;

    @try {
        UIView *view = (UIView *)self;
        if (!view.window) return;

        Class cls = object_getClass(self);
        const char *n = cls ? class_getName(cls) : "";
        if (!n) return;

        if (HGOn(@"adview") && HGIsAdClass(cls)) {
            if (!view.hidden) HGLog(@"隐藏广告视图 %s", n);
            view.hidden = YES;
            view.alpha = 0.0;
            return;
        }

        if (HGOn(@"hotsearch") && strncmp(n, "BBHotTopic", 10) == 0 &&
            !strstr(n, "VC") && !strstr(n, "Controller") &&
            !strstr(n, "Model") && !strstr(n, "VM") && !strstr(n, "Service")) {
            view.hidden = YES;
            view.alpha = 0.0;
        }
    } @catch (NSException *e) {
    }
}

#pragma mark - 3 推广弹窗

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
    }
    if (HGOn(@"update")) {
        if ([hay rangeOfString:@"upgrade" options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
        if ([hay rangeOfString:@"UpdateNotice" options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }
    return NO;
}

static IMP gOrig_showPopUp = NULL;

static void hg_showPopUp(id self, SEL _cmd, id item) {
    if (!gSafeMode && HGOn(@"popup") && HGPopupBlocked(item)) {
        HGLog(@"拦截弹窗 %@", NSStringFromClass([item class]));
        return;
    }
    if (gOrig_showPopUp) {
        ((void (*)(id, SEL, id))gOrig_showPopUp)(self, _cmd, item);
    }
}

#pragma mark - 4 设置页入口注入

static NSString *const kHGEntrySel = @"hg_openBiliPureSettings";

static BOOL HGDataHasEntry(NSArray *datas) {
    for (id m in datas) {
        @try {
            NSString *t = [m valueForKey:@"tapMethod"];
            if ([t isKindOfClass:[NSString class]] && [t isEqualToString:kHGEntrySel]) return YES;
        } @catch (NSException *e) {
        }
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
        [m setValue:@"插件设置" forKey:@"title"];
        [m setValue:@"开屏、广告、净化等开关" forKey:@"subTitle"];
        [m setValue:@"插件设置" forKey:@"vcTitle"];
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
    if (!arr) return datas;
    [arr insertObject:m atIndex:0];
    HGLog(@"设置页入口已插入，共 %lu 项", (unsigned long)arr.count);
    return arr;
}

static IMP gOrig_setDatas = NULL;

static void hg_setDatas(id self, SEL _cmd, NSArray *datas) {
    NSArray *out = datas;
    if (!gSafeMode) {
        @try {
            Class selfCls = object_getClass(self);
            const char *cn = selfCls ? class_getName(selfCls) : "";
            if (cn && strcmp(cn, "BBPhoneSettingMainVC") == 0) {
                out = HGPrependEntry(datas);
            }
        } @catch (NSException *e) {
            out = datas;
        }
    }
    if (gOrig_setDatas) {
        ((void (*)(id, SEL, NSArray *))gOrig_setDatas)(self, _cmd, out);
    }
}

#pragma mark - 入口

__attribute__((constructor))
static void HGBiliPureInit(void) {
    @autoreleasepool {
        HGInstallCrashHandler();

        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *flag = HGFlagPath();

        if (flag) {
            if ([fm fileExistsAtPath:flag]) {
                gSafeMode = YES;
                [fm removeItemAtPath:flag error:nil];
            } else {
                [fm createFileAtPath:flag contents:[NSData data] attributes:nil];
            }
        }

        if (gSafeMode) {
            HGLog(@"上次启动未正常完成 → 本次安全模式，所有拦截关闭 pid=%d", getpid());
            return;
        }

        Class splashCls = objc_getClass("BFCSplashManager");
        if (splashCls) {
            gOrig_splash = HGSetImpl(splashCls, "showSplashWithStyle:delegate:launchInfo:", (IMP)hg_showSplash);
            HGLog(@"hook BFCSplashManager %@", gOrig_splash ? @"OK" : @"MISS");
        } else {
            HGLog(@"BFCSplashManager 不存在，跳过");
        }

        gOrig_didMoveToWindow = HGSetImpl([UIView class], "didMoveToWindow", (IMP)hg_didMoveToWindow);
        HGLog(@"hook UIView.didMoveToWindow %@", gOrig_didMoveToWindow ? @"OK" : @"MISS");

        Class popperCls = objc_getClass("BFCPopper");
        if (popperCls) {
            gOrig_showPopUp = HGSetImpl(popperCls, "showPopUp:", (IMP)hg_showPopUp);
            HGLog(@"hook BFCPopper.showPopUp: %@", gOrig_showPopUp ? @"OK" : @"MISS");
        }

        Class baseCls = objc_getClass("BBPhoneSettingBaseVC");
        if (baseCls) {
            gOrig_setDatas = HGSetImpl(baseCls, "setDatas:", (IMP)hg_setDatas);
            HGLog(@"hook BBPhoneSettingBaseVC.setDatas: %@", gOrig_setDatas ? @"OK" : @"MISS");
        }

        Class mainVC = objc_getClass("BBPhoneSettingMainVC");
        if (mainVC) {
            class_addMethod(mainVC,
                            NSSelectorFromString(kHGEntrySel),
                            (IMP)hg_openBiliPureSettings,
                            "v@:");
            HGLog(@"已注册设置页入口 %@", kHGEntrySel);
        } else {
            HGLog(@"BBPhoneSettingMainVC 不存在");
        }

        HGLog(@"BiliPure 已加载 pid=%d", getpid());
        HGDumpConfig();

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [fm removeItemAtPath:flag error:nil];
            HGLog(@"启动完成，安全标记已清除");
        });
    }
}
