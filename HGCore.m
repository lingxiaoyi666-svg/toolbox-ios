#import "HGCore.h"
#import <objc/runtime.h>
#import <string.h>
#import <signal.h>
#import <execinfo.h>
#import <fcntl.h>
#import <unistd.h>
#import <stdio.h>

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

#pragma mark - 日志（写在 App 沙盒 Documents 里，非越狱也可写）

NSString *HGLogPath(void) {
    static NSString *p = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        @try {
            NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
            if (dirs.count) {
                p = [dirs.firstObject stringByAppendingPathComponent:@"BiliPure.log"];
            }
        } @catch (NSException *e) {}
        if (!p) p = [NSTemporaryDirectory() stringByAppendingPathComponent:@"BiliPure.log"];
    });
    return p;
}

void HGLog(NSString *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSLog(@"[BiliPure] %@", msg);

    @try {
        static NSDateFormatter *df = nil;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            df = [[NSDateFormatter alloc] init];
            df.dateFormat = @"HH:mm:ss.SSS";
        });

        NSString *line = [NSString stringWithFormat:@"%@ %@\n", [df stringFromDate:[NSDate date]], msg];
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        NSString *path = HGLogPath();

        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:path]) {
            [fm createFileAtPath:path contents:data attributes:nil];
            return;
        }
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!fh) return;
        [fh seekToEndOfFile];
        [fh writeData:data];
        [fh closeFile];
    } @catch (NSException *e) {}
}

#pragma mark - 崩溃捕获

static void HGSignalHandler(int sig) {
    int fd = -1;
    @try {
        const char *path = HGLogPath().UTF8String;
        fd = open(path, O_WRONLY | O_APPEND | O_CREAT, 0644);
    } @catch (NSException *e) {}

    if (fd >= 0) {
        char head[96];
        int n = snprintf(head, sizeof(head), "\n=== BiliPure crash: signal %d ===\n", sig);
        if (n > 0) write(fd, head, (size_t)n);

        void *frames[48];
        int cnt = backtrace(frames, 48);
        backtrace_symbols_fd(frames, cnt, fd);
        close(fd);
    }

    signal(sig, SIG_DFL);
    raise(sig);
}

void HGInstallCrashHandler(void) {
    int sigs[] = {SIGSEGV, SIGABRT, SIGBUS, SIGILL, SIGFPE, SIGTRAP};
    for (unsigned i = 0; i < sizeof(sigs) / sizeof(sigs[0]); i++) {
        signal(sigs[i], HGSignalHandler);
    }
}

#pragma mark - 广告类判定（带线性缓存）

static Class gCls[512];
static BOOL gVal[512];
static int gCnt = 0;
static int gIdx = 0;

static BOOL HGRuleMatchesAd(const char *n) {
    if (!n) return NO;

    if (strncmp(n, "BBAd", 4) == 0) return YES;
    if (strncmp(n, "_TtC", 4) == 0) {
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

    for (int i = 0; i < gCnt && i < 512; i++) {
        if (gCls[i] == cls) return gVal[i];
    }

    const char *n = class_getName(cls);
    BOOL ad = HGRuleMatchesAd(n);

    if (gCnt < 512) {
        int slot = gCnt;
        gCnt = slot + 1 > 512 ? 512 : slot + 1;
        if (slot < 512) { gCls[slot] = cls; gVal[slot] = ad; }
    } else {
        int slot = gIdx;
        gCls[slot] = cls;
        gVal[slot] = ad;
        gIdx = (slot + 1) % 512;
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
