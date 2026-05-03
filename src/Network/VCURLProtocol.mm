/**
 * VCURLProtocol.mm -- 自定义 NSURLProtocol (Layer 2 兜底)
 * 拦截未被 Layer 1 覆盖的请求
 */

#import "VCURLProtocol.h"
#import "VCNetRecord.h"
#import "../Hook/VCHookManager.h"
#import "../../VansonCLI.h"
#import <objc/runtime.h>

static NSString *const kVCProtocolHandledKey = @"com.vanson.cli.protocol.handled";
static IMP _origDefaultConfig = NULL;

#pragma mark - Swizzled defaultSessionConfiguration

static NSURLSessionConfiguration *vc_swizzled_defaultConfig(id self, SEL _cmd) {
    NSURLSessionConfiguration *config = ((NSURLSessionConfiguration *(*)(id, SEL))_origDefaultConfig)(self, _cmd);
    // 注入 VCURLProtocol 到 protocolClasses
    NSMutableArray *protocols = config.protocolClasses ? [config.protocolClasses mutableCopy] : [NSMutableArray new];
    if (![protocols containsObject:[VCURLProtocol class]]) {
        [protocols insertObject:[VCURLProtocol class] atIndex:0];
    }
    config.protocolClasses = protocols;
    return config;
}

#pragma mark - Notification Keys

NSString *const kVCURLProtocolDidCaptureRecord = @"com.vanson.cli.urlprotocol.captured";

#pragma mark - VCURLProtocol

@interface VCURLProtocol () <NSURLSessionDataDelegate>
@property (nonatomic, strong) NSURLSession *innerSession;
@property (nonatomic, strong) NSURLSessionDataTask *innerTask;
@property (nonatomic, strong) VCNetRecord *record;
@property (nonatomic, strong) NSMutableData *accumulatedData;
@end

@implementation VCURLProtocol

+ (void)install {
    // 注册到全局
    [NSURLProtocol registerClass:[VCURLProtocol class]];

    // Swizzle defaultSessionConfiguration
    SEL sel = @selector(defaultSessionConfiguration);
    Method m = class_getClassMethod([NSURLSessionConfiguration class], sel);
    if (m) {
        _origDefaultConfig = method_setImplementation(m, (IMP)vc_swizzled_defaultConfig);
        VCLog(@"[Net] NSURLProtocol installed + defaultConfig swizzled");
    }
}
+ (void)uninstall {
    [NSURLProtocol unregisterClass:[VCURLProtocol class]];

    if (_origDefaultConfig) {
        Method m = class_getClassMethod([NSURLSessionConfiguration class], @selector(defaultSessionConfiguration));
        if (m) method_setImplementation(m, _origDefaultConfig);
        _origDefaultConfig = NULL;
    }
    VCLog(@"[Net] NSURLProtocol uninstalled");
}

#pragma mark - NSURLProtocol Override

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    // 避免递归: 已标记的请求跳过
    if ([NSURLProtocol propertyForKey:kVCProtocolHandledKey inRequest:request]) {
        return NO;
    }
    if (VCRequestIsInternal(request)) {
        return NO;
    }
    NSString *scheme = request.URL.scheme.lowercaseString;
    return [scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"];
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    NSMutableURLRequest *mutableReq = [self.request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:kVCProtocolHandledKey inRequest:mutableReq];

    // 创建记录
    _record = [[VCNetRecord alloc] init];
    _record.method = mutableReq.HTTPMethod ?: @"GET";
    _record.url = mutableReq.URL.absoluteString;
    _record.requestHeaders = mutableReq.allHTTPHeaderFields;
    _record.traceContext = [[VCHookManager shared] currentTraceContextSnapshot];
    if (mutableReq.HTTPBody) {
        _record.requestBody = (mutableReq.HTTPBody.length > kVCNetBodyMaxSize)
            ? [mutableReq.HTTPBody subdataWithRange:NSMakeRange(0, kVCNetBodyMaxSize)]
            : mutableReq.HTTPBody;
    }

    _accumulatedData = [NSMutableData new];

    // 内部 session 转发请求 (不注入 VCURLProtocol 避免递归)
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSMutableArray *protocols = [config.protocolClasses mutableCopy] ?: [NSMutableArray new];
    [protocols removeObject:[VCURLProtocol class]];
    config.protocolClasses = protocols;

    _innerSession = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:nil];
    _innerTask = [_innerSession dataTaskWithRequest:mutableReq];
    [_innerTask resume];
}

- (void)stopLoading {
    [_innerTask cancel];
    [_innerSession invalidateAndCancel];
}

#pragma mark - NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveResponse:(NSURLResponse *)response
     completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {

    NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
    _record.statusCode = http.statusCode;
    _record.responseHeaders = http.allHeaderFields;
    _record.mimeType = http.MIMEType;

    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data {

    if (_accumulatedData.length < kVCNetBodyMaxSize) {
        NSUInteger remaining = kVCNetBodyMaxSize - _accumulatedData.length;
        NSUInteger toAppend = MIN(data.length, remaining);
        [_accumulatedData appendData:[data subdataWithRange:NSMakeRange(0, toAppend)]];
    }
    [self.client URLProtocol:self didLoadData:data];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
    didCompleteWithError:(NSError *)error {

    _record.responseBody = [_accumulatedData copy];
    _record.duration = [[NSProcessInfo processInfo] systemUptime] - _record.startTime;

    // 通知 VCNetMonitor
    [[NSNotificationCenter defaultCenter] postNotificationName:kVCURLProtocolDidCaptureRecord
                                                        object:_record];

    if (error) {
        [self.client URLProtocol:self didFailWithError:error];
    } else {
        [self.client URLProtocolDidFinishLoading:self];
    }
}

@end
