/**
 * VCWebSocketMonitor -- WebSocket 帧监控 (Layer 3)
 * Swizzle NSURLSessionWebSocketTask send/receive
 */

#import <Foundation/Foundation.h>

@class VCWebSocketFrame;

typedef void(^VCWSFrameCallback)(VCWebSocketFrame *frame);

@interface VCWebSocketMonitor : NSObject

+ (instancetype)shared;

/// 安装 WebSocket hook
- (void)install;

/// 卸载
- (void)uninstall;

/// 帧回调
@property (nonatomic, copy) VCWSFrameCallback onFrame;

@end
