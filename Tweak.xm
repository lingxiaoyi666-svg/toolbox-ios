#import "HGCore.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#pragma mark - 通用工具

static BOOL HGIsHotSearchClass(Class cls) {
    const char *n = class_getName(cls);
    if (!n) return NO;
    if (strncmp(n, "BBHotTopic", 10) != 0) return NO;
    // 只处理视图，不碰 VC / Model
    if (strstr(n, "VC") || strstr(n, "Controller") || strstr(n, "Model") ||
        strstr(n, "VM") || strstr(n, "Service")) return NO;
    return YES;
}

#pragma mark - 开屏广告

%hook BFCSplashManager

- (void)showSplashWithStyle:(long)style delegate:(id)delegate launchInfo:(id)launchInfo {
    if (HGOn(@"splash")) {
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

    @try {
        if (!self.window) return;
        Class cls = [self class];

        if (HGOn(@"adview") && HGIsAdClass(cls)) {
            if (!self.hidden) {
                HGLog(@"隐藏广告视图 %s", class_getName(cls));
            }
            self.hidden = YES;
            self.alpha = 0.0;
            return;
        }

        if (HGOn(@"hotsearch") && HGIsHotSearchClass(cls)) {
            self.hidden = YES;
            self.alpha = 0.0;
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
    if (HGPopupBlocked(item)) {
        HGLog(@"拦截弹窗 %@", NSStringFromClass([item class]));
        return;
    }
    %orig;
}

%end

#pragma mark - 入口

%ctor {
    @autoreleasepool {
        HGLog(@"BiliPure 已加载 pid=%d", getpid());
        HGDumpConfig();
    }
}
