//
//  TDAppStoreLink.m
//  TrollDecrypt
//

#import "TDAppStoreLink.h"
#import <UIKit/UIKit.h>

@implementation TDAppStoreLink

+ (NSNumber *)trackIdFromString:(NSString *)text {
    if (text.length == 0) {
        return nil;
    }
    NSArray<NSString *> *patterns = @[
        @"/id(\\d{5,})",          // https://apps.apple.com/cn/app/xxx/id123456789
        @"[?&]id=(\\d{5,})",      // ...?id=123456789
        @"^\\s*(\\d{6,})\\s*$",   // 直接粘数字
    ];
    for (NSString *pattern in patterns) {
        NSRegularExpression *regex =
            [NSRegularExpression regularExpressionWithPattern:pattern
                                                      options:NSRegularExpressionCaseInsensitive
                                                        error:nil];
        NSTextCheckingResult *match =
            [regex firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
        if (match && match.numberOfRanges > 1) {
            NSString *digits = [text substringWithRange:[match rangeAtIndex:1]];
            return @(digits.longLongValue);
        }
    }
    return nil;
}

+ (void)lookupTrackId:(NSNumber *)trackId
           completion:(void (^)(NSDictionary *_Nullable, NSError *_Nullable))completion {
    // 先查中国区，空结果再退回美国区（有些 App 只在一侧上架）
    [self _lookupTrackId:trackId country:@"cn" completion:^(NSDictionary *info, NSError *error) {
        if (info) {
            completion(info, nil);
            return;
        }
        [self _lookupTrackId:trackId country:@"us" completion:completion];
    }];
}

+ (void)_lookupTrackId:(NSNumber *)trackId
               country:(NSString *)country
            completion:(void (^)(NSDictionary *_Nullable, NSError *_Nullable))completion {
    NSString *urlString = [NSString stringWithFormat:
        @"https://itunes.apple.com/lookup?id=%@&country=%@&entity=software",
        trackId.stringValue, country];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        NSError *error = [NSError errorWithDomain:@"TDAppStoreLink"
                                             code:-1
                                         userInfo:@{NSLocalizedDescriptionKey: @"链接格式不对"}];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, error); });
        return;
    }

    NSURLSessionDataTask *task =
        [[NSURLSession sharedSession] dataTaskWithURL:url
                                    completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, error); });
            return;
        }
        if (!data) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, [NSError errorWithDomain:@"TDAppStoreLink"
                                                    code:-2
                                                userInfo:@{NSLocalizedDescriptionKey: @"服务器没返回内容"}]);
            });
            return;
        }
        NSError *jsonError = nil;
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (![json isKindOfClass:[NSDictionary class]]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, jsonError ?: [NSError errorWithDomain:@"TDAppStoreLink"
                                                                 code:-3
                                                             userInfo:@{NSLocalizedDescriptionKey: @"返回内容解析失败"}]);
            });
            return;
        }
        NSArray *results = ((NSDictionary *)json)[@"results"];
        if (![results isKindOfClass:[NSArray class]] || results.count == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, nil); });
            return;
        }
        NSDictionary *first = results.firstObject;
        NSString *bundleId = first[@"bundleId"];
        if (bundleId.length == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, nil); });
            return;
        }
        NSMutableDictionary *info = [NSMutableDictionary dictionary];
        info[@"trackId"] = trackId;
        info[@"bundleId"] = bundleId;
        info[@"trackName"] = first[@"trackName"] ?: bundleId;
        info[@"version"] = first[@"version"] ?: @"";
        info[@"artworkUrl"] = first[@"artworkUrl512"] ?: first[@"artworkUrl100"] ?: @"";
        dispatch_async(dispatch_get_main_queue(), ^{ completion(info, nil); });
    }];
    [task resume];
}

+ (void)openTrackId:(NSNumber *)trackId {
    NSArray<NSString *> *candidates = @[
        [NSString stringWithFormat:@"itms-apps://itunes.apple.com/app/id%@", trackId.stringValue],
        [NSString stringWithFormat:@"https://apps.apple.com/app/id%@", trackId.stringValue],
    ];
    for (NSString *candidate in candidates) {
        NSURL *url = [NSURL URLWithString:candidate];
        if (url && [[UIApplication sharedApplication] canOpenURL:url]) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
            return;
        }
    }
}

@end
