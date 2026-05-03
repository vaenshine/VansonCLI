/**
 * VCNetRecord -- 网络请求记录数据模型
 * 存储 HTTP 请求/响应 + WebSocket 帧
 */

#import <Foundation/Foundation.h>

// 最大 Body 大小 (1MB)
static const NSUInteger kVCNetBodyMaxSize = 1024 * 1024;
// 最大记录数
static const NSUInteger kVCNetMaxRecords = 500;

#pragma mark - VCNetRecord

@interface VCNetRecord : NSObject

@property (nonatomic, copy) NSString *requestID;
@property (nonatomic, copy) NSString *method;
@property (nonatomic, copy) NSString *url;
@property (nonatomic, copy) NSDictionary *requestHeaders;
@property (nonatomic, copy) NSData *requestBody;
@property (nonatomic, assign) NSInteger statusCode;
@property (nonatomic, copy) NSDictionary *responseHeaders;
@property (nonatomic, copy) NSData *responseBody;
@property (nonatomic, copy) NSString *mimeType;
@property (nonatomic, assign) NSTimeInterval startTime;
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, assign) BOOL isWebSocket;
@property (nonatomic, assign) BOOL wasModifiedByRule;
@property (nonatomic, copy) NSArray<NSString *> *matchedRules;
@property (nonatomic, copy) NSString *favoriteID;
@property (nonatomic, copy) NSString *favoriteName;
@property (nonatomic, copy) NSString *hostKey;
@property (nonatomic, copy) NSString *statusBucket;
@property (nonatomic, copy) NSDictionary *exportSnapshot;
@property (nonatomic, copy) NSDictionary *traceContext;

/// 导出为 cURL 命令
- (NSString *)curlCommand;

/// Body 转文本 (JSON 自动格式化)
- (NSString *)requestBodyAsString;
- (NSString *)responseBodyAsString;

@end

#pragma mark - VCWebSocketFrame

@interface VCWebSocketFrame : NSObject

@property (nonatomic, copy) NSString *frameID;
@property (nonatomic, copy) NSString *connectionID;
@property (nonatomic, copy) NSString *direction;   // "send" / "receive"
@property (nonatomic, copy) NSString *type;         // "text" / "binary"
@property (nonatomic, copy) NSData *payload;
@property (nonatomic, assign) NSTimeInterval timestamp;

@end
