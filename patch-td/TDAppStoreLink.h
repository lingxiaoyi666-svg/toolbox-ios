//
//  TDAppStoreLink.h
//  TrollDecrypt
//
//  把 App Store 链接解析成 bundle id，方便「复制链接直接砸壳」。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TDAppStoreLink : NSObject

/// 从文本里抠 App Store 数字 ID：支持 apps.apple.com/.../id123、?id=123、纯数字 123
+ (nullable NSNumber *)trackIdFromString:(nullable NSString *)text;

/// 查元数据。返回字典：trackId / bundleId / trackName / version / artworkUrl
+ (void)lookupTrackId:(NSNumber *)trackId
           completion:(void (^)(NSDictionary *_Nullable info, NSError *_Nullable error))completion;

/// 跳到 App Store 详情页
+ (void)openTrackId:(NSNumber *)trackId;

@end

NS_ASSUME_NONNULL_END
