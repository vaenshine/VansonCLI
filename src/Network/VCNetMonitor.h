/**
 * VCNetMonitor -- 网络监控引擎主类
 * 三层 Hook: NSURLSession + NSURLProtocol + WebSocket
 */

#import <Foundation/Foundation.h>

@class VCNetRecord;
@class VCWebSocketFrame;
@class VCNetMonitor;

@protocol VCNetMonitorDelegate <NSObject>
- (void)netMonitor:(VCNetMonitor *)monitor didCaptureRecord:(VCNetRecord *)record;
- (void)netMonitor:(VCNetMonitor *)monitor didCaptureWSFrame:(VCWebSocketFrame *)frame;
@end

@interface VCNetMonitor : NSObject

+ (instancetype)shared;

@property (nonatomic, weak) id<VCNetMonitorDelegate> delegate;
@property (nonatomic, readonly) BOOL isMonitoring;

- (void)startMonitoring;
- (void)stopMonitoring;

/// 所有记录 (线程安全拷贝)
- (NSArray<VCNetRecord *> *)allRecords;

/// 所有 WebSocket 帧 (线程安全拷贝)
- (NSArray<VCWebSocketFrame *> *)allWebSocketFrames;

/// 按 URL/method 过滤
- (NSArray<VCNetRecord *> *)recordsMatchingFilter:(NSString *)filter;

/// 修改重发
- (void)resendRecord:(VCNetRecord *)record withModifications:(NSDictionary *)mods;

/// 导出 cURL
- (NSString *)curlCommandForRecord:(VCNetRecord *)record;

/// 拦截规则
- (void)addInterceptRule:(NSString *)urlPattern;
- (void)removeInterceptRule:(NSString *)urlPattern;

/// 清空记录
- (void)clearRecords;

@end
