/**
 * VCURLProtocol -- 自定义 NSURLProtocol (Layer 2 兜底)
 * 拦截 NSURLSessionConfiguration 未被 Layer 1 覆盖的请求
 */

#import <Foundation/Foundation.h>

@interface VCURLProtocol : NSURLProtocol

/// 注册到全局 + Swizzle defaultSessionConfiguration
+ (void)install;

/// 注销
+ (void)uninstall;

@end

/// Notification posted when VCURLProtocol captures a request
extern NSString *const kVCURLProtocolDidCaptureRecord;
