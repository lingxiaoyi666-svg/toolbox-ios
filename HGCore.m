#import "HGCore.h"
#import <objc/runtime.h>
#import <string.h>

#pragma mark - 开关

static NSMutableDictionary *gCache;
static dispatch_once_t gOnce;

BOOL HGOn(NSString *key) {
    dispatch_once(&gOnce, ^{ gCache = [NSMutableDictionary dictionary]; });

    @synchronized (gCache) {
        NSNumber *hit = gCache[key];
        if (hit) return hit.boolValue;
    }

    BOOL v = YES;
    @try {
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        NSString *k = [@"HGP_" stringByAppendingString:key];
        if ([d objectForKey:k] != nil) v = [d boolForKey:k];
        else if ([d objectForKey:key] != nil) v = [d boolForKey:key];
    } @catch (NSException *e) {}

    @synchronized (gCache) { gCache[key] = @(v); }
    return v;
}

void HGSetOn(NSString *key, BOOL value) {
    @try {
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        [d setBool:value forKey:[@"HGP_" stringByAppendingString:key]];
    } @catch (NSException *e) {}
    @synchronized (gCache) { gCache[key] = @(value); }
}

#pragma mark - 日志
void HGLog(NSString *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSLog(@"[BiliPure] %@", msg);

    static NSString *logPath = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        logPath = @"/var/mobile/Library/Preferences/com.hg.bilipure.log";
    });
    @try {
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:logPath]) {
            [fm createFileAtPath:logPath contents:nil attributes:nil];
        }
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logPath];
        [fh seekToEndOfFile];
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        df.dateFormat = @"HH:mm:ss.SSS";
        NSString *line = [NSString stringWithFormat:@"%@ %@\n", [df stringFromDate:[NSDate date]], msg];
        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    } @catch (NSException *e) {}
}

#pragma mark - 广告类判定（带线性缓存）

static Class gCls[512];
static BOOL gVal[512];
static int gCnt = 0;
static int gIdx = 0;

static BOOL HGRuleMatchesAd(const char *n) {
    if (!n) return NO;

    // 明确是广告模块的类
    if (strncmp(n, "BBAd", 4) == 0) return YES;
    if (strncmp(n, "_TtC", 4) == 0) {
        // Swift 类名形如 _TtC10BBAdCardV211AdCardModel，模块名里带 Ad
        if (strstr(n, "BBAdCard")) return YES;
        if (strstr(n, "BBAdSplash")) return YES;
        if (strstr(n, "BBAdLiveBigCard")) return YES;
        if (strstr(n, "BBAdCarouselView")) return YES;
        if (strstr(n, "BBAdTagStyleView")) return YES;
        if (strstr(n, "BBAdRcmdReasonView")) return YES;
        if (strstr(n, "TheseusEndPageAdCard")) return YES;
        if (strstr(n, "PlayerAdPopper")) return YES;
        return NO;
    }

    if (strstr(n, "AdCardMark")) return YES;
    if (strstr(n, "TheseusEndPageAdCard")) return YES;
    if (strstr(n, "BBHotTopicAd")) return YES;
    if (strstr(n, "BrandSplash")) return YES;
    if (strstr(n, "BusinessSplashBrandSpace")) return YES;
    if (strstr(n, "BBAdStory")) return YES;
    if (strstr(n, "BBAdSearch")) return YES;

    return NO;
}

BOOL HGIsAdClass(Class cls) {
    if (!cls) return NO;

    for (int i = 0; i < gCnt; i++) {
        if (gCls[i] == cls) return gVal[i];
    }

    const char *n = class_getName(cls);
    BOOL ad = HGRuleMatchesAd(n);

    if (gCnt < 512) {
        gCls[gCnt] = cls;
        gVal[gCnt] = ad;
        gCnt++;
    } else {
        gCls[gIdx] = cls;
        gVal[gIdx] = ad;
        gIdx = (gIdx + 1) % 512;
    }
    return ad;
}

#pragma mark - 配置快照

void HGDumpConfig(void) {
    NSArray *keys = @[@"splash", @"adview", @"hotsearch", @"mytab", @"popup",
                      @"watermark", @"danmaku", @"teenager", @"update"];
    NSMutableString *s = [NSMutableString string];
    for (NSString *k in keys) {
        [s appendFormat:@"%@=%@ ", k, HGOn(k) ? @"on" : @"off"];
    }
    HGLog(@"配置: %@", s);
}
