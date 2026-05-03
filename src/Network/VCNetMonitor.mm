/**
 * VCNetMonitor.mm -- 网络监控引擎
 * Layer 1: NSURLSession swizzle
 * Layer 2: VCURLProtocol 兜底
 * Layer 3: VCWebSocketMonitor
 */

#import "VCNetMonitor.h"
#import "VCNetRecord.h"
#import "VCURLProtocol.h"
#import "VCWebSocketMonitor.h"
#import "../Hook/VCHookManager.h"
#import "../Patches/VCPatchManager.h"
#import "../Patches/VCNetRule.h"
#import "../../VansonCLI.h"
#import <objc/runtime.h>

// 关联 key: VCNetRecord on NSURLSessionTask
static const void *kVCTaskRecordKey = &kVCTaskRecordKey;
// 关联 key: 累积 response data
static const void *kVCTaskDataKey = &kVCTaskDataKey;

// 前向声明 class extension (C 函数需要调用 _addRecord:)
@interface VCNetMonitor ()
- (void)_addRecord:(VCNetRecord *)record;
- (void)_addWebSocketFrame:(VCWebSocketFrame *)frame;
@end

#pragma mark - Original IMPs

static IMP _origDataTask = NULL;
static IMP _origUploadTask = NULL;
static IMP _origDownloadTask = NULL;
static IMP _origDidReceiveData = NULL;
static IMP _origDidComplete = NULL;

#pragma mark - Helper

static VCNetRecord *vc_createRecord(NSURLRequest *request) {
    VCNetRecord *rec = [[VCNetRecord alloc] init];
    rec.method = request.HTTPMethod ?: @"GET";
    rec.url = request.URL.absoluteString;
    rec.hostKey = request.URL.host ?: @"";
    rec.requestHeaders = request.allHTTPHeaderFields;
    rec.traceContext = [[VCHookManager shared] currentTraceContextSnapshot];
    if (request.HTTPBody) {
        rec.requestBody = (request.HTTPBody.length > kVCNetBodyMaxSize)
            ? [request.HTTPBody subdataWithRange:NSMakeRange(0, kVCNetBodyMaxSize)]
            : request.HTTPBody;
    }
    return rec;
}

static NSDictionary *vc_recordSnapshot(VCNetRecord *record) {
    return @{
        @"request": @{
            @"method": record.method ?: @"GET",
            @"url": record.url ?: @"",
            @"headers": record.requestHeaders ?: @{},
            @"body": [record requestBodyAsString] ?: @""
        },
        @"response": @{
            @"status": @(record.statusCode),
            @"headers": record.responseHeaders ?: @{},
            @"body": [record responseBodyAsString] ?: @""
        }
    };
}

static void vc_attachRecord(NSURLSessionTask *task, VCNetRecord *rec) {
    objc_setAssociatedObject(task, kVCTaskRecordKey, rec, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(task, kVCTaskDataKey, [NSMutableData new], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static VCNetRecord *vc_getRecord(NSURLSessionTask *task) {
    return objc_getAssociatedObject(task, kVCTaskRecordKey);
}

static NSMutableData *vc_getData(NSURLSessionTask *task) {
    return objc_getAssociatedObject(task, kVCTaskDataKey);
}

static NSString *vc_statusBucketForCode(NSInteger statusCode) {
    if (statusCode >= 500) return @"5xx";
    if (statusCode >= 400) return @"4xx";
    if (statusCode >= 200) return @"2xx";
    return @"other";
}

static BOOL vc_urlMatchesPattern(NSString *urlString, NSString *pattern) {
    if (urlString.length == 0 || pattern.length == 0) return NO;

    NSError *regexError = nil;
    NSString *regexPattern = pattern;
    if ([pattern containsString:@"*"]) {
        NSMutableString *escaped = [NSMutableString new];
        NSCharacterSet *specials = [NSCharacterSet characterSetWithCharactersInString:@"\\^$.|?+()[]{}"];
        for (NSUInteger i = 0; i < pattern.length; i++) {
            unichar ch = [pattern characterAtIndex:i];
            if (ch == '*') {
                [escaped appendString:@".*"];
            } else {
                if ([specials characterIsMember:ch]) [escaped appendString:@"\\"];
                [escaped appendFormat:@"%C", ch];
            }
        }
        regexPattern = escaped;
    }

    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:regexPattern options:0 error:&regexError];
    if (!regexError && regex) {
        NSRange fullRange = NSMakeRange(0, urlString.length);
        return [regex firstMatchInString:urlString options:0 range:fullRange] != nil;
    }

    return [urlString containsString:pattern];
}

static NSURLRequest *vc_requestByApplyingRules(NSURLRequest *request, NSArray<NSString *> **matchedRulesOut, BOOL *wasModifiedOut) {
    NSString *urlString = request.URL.absoluteString ?: @"";
    if (matchedRulesOut) *matchedRulesOut = @[];
    if (wasModifiedOut) *wasModifiedOut = NO;
    if (urlString.length == 0) return request;
    if (VCRequestIsInternal(request)) return request;

    NSArray<VCNetRule *> *rules = [[VCPatchManager shared] allRules];
    if (rules.count == 0) return request;

    NSMutableURLRequest *mutableRequest = nil;
    NSMutableArray<NSString *> *matchedRules = [NSMutableArray new];
    BOOL wasModified = NO;
    for (VCNetRule *rule in rules) {
        if (!rule.enabled || rule.isDisabledBySafeMode) continue;
        if (rule.urlPattern.length == 0 || !vc_urlMatchesPattern(urlString, rule.urlPattern)) continue;
        [matchedRules addObject:rule.remark.length > 0 ? rule.remark : (rule.urlPattern ?: rule.action ?: @"rule")];

        if ([rule.action isEqualToString:@"modify_header"]) {
            NSDictionary *headers = [rule.modifications[@"headers"] isKindOfClass:[NSDictionary class]] ? rule.modifications[@"headers"] : nil;
            if (headers.count == 0) continue;
            if (!mutableRequest) mutableRequest = [request mutableCopy];
            [headers enumerateKeysAndObjectsUsingBlock:^(NSString *key, id obj, BOOL *stop) {
                [mutableRequest setValue:[obj description] forHTTPHeaderField:key];
            }];
            wasModified = YES;
        } else if ([rule.action isEqualToString:@"modify_body"]) {
            id bodyValue = rule.modifications[@"body"];
            NSData *bodyData = nil;
            if ([bodyValue isKindOfClass:[NSData class]]) bodyData = bodyValue;
            else if ([bodyValue isKindOfClass:[NSString class]]) bodyData = [(NSString *)bodyValue dataUsingEncoding:NSUTF8StringEncoding];
            if (!bodyData) continue;
            if (!mutableRequest) mutableRequest = [request mutableCopy];
            mutableRequest.HTTPBody = bodyData;
            wasModified = YES;
        }
    }

    if (matchedRulesOut) *matchedRulesOut = [matchedRules copy];
    if (wasModifiedOut) *wasModifiedOut = wasModified;
    return mutableRequest ?: request;
}

#pragma mark - Layer 1: NSURLSession Swizzled Methods

static NSURLSessionDataTask *vc_swizzled_dataTask(id self, SEL _cmd, NSURLRequest *request, void (^completion)(NSData *, NSURLResponse *, NSError *)) {
    if (VCRequestIsInternal(request)) {
        return ((NSURLSessionDataTask *(*)(id, SEL, NSURLRequest *, void(^)(NSData *, NSURLResponse *, NSError *)))_origDataTask)(self, _cmd, request, completion);
    }

    NSArray<NSString *> *matchedRules = nil;
    BOOL wasModified = NO;
    request = vc_requestByApplyingRules(request, &matchedRules, &wasModified);
    VCNetRecord *rec = vc_createRecord(request);
    rec.matchedRules = matchedRules;
    rec.wasModifiedByRule = wasModified;

    void (^wrappedCompletion)(NSData *, NSURLResponse *, NSError *) = nil;
    if (completion) {
        wrappedCompletion = ^(NSData *data, NSURLResponse *response, NSError *error) {
            NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
            rec.statusCode = http.statusCode;
            rec.responseHeaders = http.allHeaderFields;
            rec.mimeType = http.MIMEType;
            if (data) {
                rec.responseBody = (data.length > kVCNetBodyMaxSize)
                    ? [data subdataWithRange:NSMakeRange(0, kVCNetBodyMaxSize)]
                    : data;
            }
            rec.statusBucket = vc_statusBucketForCode(rec.statusCode);
            rec.exportSnapshot = vc_recordSnapshot(rec);
            rec.duration = [[NSProcessInfo processInfo] systemUptime] - rec.startTime;
            [[VCNetMonitor shared] _addRecord:rec];
            completion(data, response, error);
        };
    }

    NSURLSessionDataTask *task = ((NSURLSessionDataTask *(*)(id, SEL, NSURLRequest *, void(^)(NSData *, NSURLResponse *, NSError *)))_origDataTask)(self, _cmd, request, wrappedCompletion);
    vc_attachRecord(task, rec);

    if (!completion) {
        // delegate-based: 记录会在 didReceiveData/didComplete 中完成
    }
    return task;
}

static NSURLSessionUploadTask *vc_swizzled_uploadTask(id self, SEL _cmd, NSURLRequest *request, NSData *bodyData, void (^completion)(NSData *, NSURLResponse *, NSError *)) {
    if (VCRequestIsInternal(request)) {
        return ((NSURLSessionUploadTask *(*)(id, SEL, NSURLRequest *, NSData *, void(^)(NSData *, NSURLResponse *, NSError *)))_origUploadTask)(self, _cmd, request, bodyData, completion);
    }

    NSArray<NSString *> *matchedRules = nil;
    BOOL wasModified = NO;
    request = vc_requestByApplyingRules(request, &matchedRules, &wasModified);
    if (request.HTTPBody) bodyData = request.HTTPBody;
    VCNetRecord *rec = vc_createRecord(request);
    rec.matchedRules = matchedRules;
    rec.wasModifiedByRule = wasModified;
    if (bodyData && !rec.requestBody) {
        rec.requestBody = (bodyData.length > kVCNetBodyMaxSize)
            ? [bodyData subdataWithRange:NSMakeRange(0, kVCNetBodyMaxSize)]
            : bodyData;
    }

    void (^wrappedCompletion)(NSData *, NSURLResponse *, NSError *) = nil;
    if (completion) {
        wrappedCompletion = ^(NSData *data, NSURLResponse *response, NSError *error) {
            NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
            rec.statusCode = http.statusCode;
            rec.responseHeaders = http.allHeaderFields;
            rec.mimeType = http.MIMEType;
            if (data) {
                rec.responseBody = (data.length > kVCNetBodyMaxSize)
                    ? [data subdataWithRange:NSMakeRange(0, kVCNetBodyMaxSize)]
                    : data;
            }
            rec.statusBucket = vc_statusBucketForCode(rec.statusCode);
            rec.exportSnapshot = vc_recordSnapshot(rec);
            rec.duration = [[NSProcessInfo processInfo] systemUptime] - rec.startTime;
            [[VCNetMonitor shared] _addRecord:rec];
            completion(data, response, error);
        };
    }

    NSURLSessionUploadTask *task = ((NSURLSessionUploadTask *(*)(id, SEL, NSURLRequest *, NSData *, void(^)(NSData *, NSURLResponse *, NSError *)))_origUploadTask)(self, _cmd, request, bodyData, wrappedCompletion);
    vc_attachRecord(task, rec);
    return task;
}

static NSURLSessionDownloadTask *vc_swizzled_downloadTask(id self, SEL _cmd, NSURLRequest *request, void (^completion)(NSURL *, NSURLResponse *, NSError *)) {
    if (VCRequestIsInternal(request)) {
        return ((NSURLSessionDownloadTask *(*)(id, SEL, NSURLRequest *, void(^)(NSURL *, NSURLResponse *, NSError *)))_origDownloadTask)(self, _cmd, request, completion);
    }

    NSArray<NSString *> *matchedRules = nil;
    BOOL wasModified = NO;
    request = vc_requestByApplyingRules(request, &matchedRules, &wasModified);
    VCNetRecord *rec = vc_createRecord(request);
    rec.matchedRules = matchedRules;
    rec.wasModifiedByRule = wasModified;

    void (^wrappedCompletion)(NSURL *, NSURLResponse *, NSError *) = nil;
    if (completion) {
        wrappedCompletion = ^(NSURL *location, NSURLResponse *response, NSError *error) {
            NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
            rec.statusCode = http.statusCode;
            rec.responseHeaders = http.allHeaderFields;
            rec.mimeType = http.MIMEType;
            // download task: body 在文件中, 读取前 1MB
            if (location) {
                NSData *data = [NSData dataWithContentsOfURL:location options:NSDataReadingMappedIfSafe error:nil];
                if (data) {
                    rec.responseBody = (data.length > kVCNetBodyMaxSize)
                        ? [data subdataWithRange:NSMakeRange(0, kVCNetBodyMaxSize)]
                        : data;
                }
            }
            rec.statusBucket = vc_statusBucketForCode(rec.statusCode);
            rec.exportSnapshot = vc_recordSnapshot(rec);
            rec.duration = [[NSProcessInfo processInfo] systemUptime] - rec.startTime;
            [[VCNetMonitor shared] _addRecord:rec];
            completion(location, response, error);
        };
    }

    NSURLSessionDownloadTask *task = ((NSURLSessionDownloadTask *(*)(id, SEL, NSURLRequest *, void(^)(NSURL *, NSURLResponse *, NSError *)))_origDownloadTask)(self, _cmd, request, wrappedCompletion);
    vc_attachRecord(task, rec);
    return task;
}

#pragma mark - Layer 1: Delegate Swizzle (didReceiveData / didComplete)

static void vc_swizzled_didReceiveData(id self, SEL _cmd, NSURLSession *session, NSURLSessionDataTask *dataTask, NSData *data) {
    NSMutableData *acc = vc_getData(dataTask);
    if (acc && acc.length < kVCNetBodyMaxSize) {
        NSUInteger remaining = kVCNetBodyMaxSize - acc.length;
        NSUInteger toAppend = MIN(data.length, remaining);
        [acc appendData:[data subdataWithRange:NSMakeRange(0, toAppend)]];
    }
    if (_origDidReceiveData) {
        ((void(*)(id, SEL, NSURLSession *, NSURLSessionDataTask *, NSData *))_origDidReceiveData)(self, _cmd, session, dataTask, data);
    }
}

static void vc_swizzled_didComplete(id self, SEL _cmd, NSURLSession *session, NSURLSessionTask *task, NSError *error) {
    VCNetRecord *rec = vc_getRecord(task);
    if (rec) {
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)task.response;
        rec.statusCode = http.statusCode;
        rec.responseHeaders = http.allHeaderFields;
        rec.mimeType = http.MIMEType;
        rec.responseBody = [vc_getData(task) copy];
        rec.statusBucket = vc_statusBucketForCode(rec.statusCode);
        rec.exportSnapshot = vc_recordSnapshot(rec);
        rec.duration = [[NSProcessInfo processInfo] systemUptime] - rec.startTime;
        [[VCNetMonitor shared] _addRecord:rec];
    }
    if (_origDidComplete) {
        ((void(*)(id, SEL, NSURLSession *, NSURLSessionTask *, NSError *))_origDidComplete)(self, _cmd, session, task, error);
    }
}

#pragma mark - VCNetMonitor

@implementation VCNetMonitor {
    NSMutableArray<VCNetRecord *> *_records;
    NSMutableArray<VCWebSocketFrame *> *_webSocketFrames;
    dispatch_queue_t _queue;
    NSMutableSet<NSString *> *_interceptRules;
    BOOL _monitoring;
}

+ (instancetype)shared {
    static VCNetMonitor *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VCNetMonitor alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _records = [NSMutableArray new];
        _webSocketFrames = [NSMutableArray new];
        _queue = dispatch_queue_create("com.vanson.cli.netmonitor", DISPATCH_QUEUE_SERIAL);
        _interceptRules = [NSMutableSet new];
    }
    return self;
}

- (BOOL)isMonitoring {
    return _monitoring;
}

#pragma mark - Start / Stop

- (void)startMonitoring {
    if (_monitoring) return;
    _monitoring = YES;

    // Layer 1: NSURLSession hooks
    [self _installSessionHooks];

    // Layer 2: NSURLProtocol 兜底
    [VCURLProtocol install];

    // Layer 3: WebSocket
    [[VCWebSocketMonitor shared] install];
    __weak VCNetMonitor *weakSelf = self;
    [VCWebSocketMonitor shared].onFrame = ^(VCWebSocketFrame *frame) {
        VCNetMonitor *strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf _addWebSocketFrame:frame];
    };

    // 监听 Layer 2 通知
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_onProtocolCapture:)
                                                 name:kVCURLProtocolDidCaptureRecord
                                               object:nil];

    VCLog(@"[Net] Monitoring started (3 layers)");
}

- (void)stopMonitoring {
    if (!_monitoring) return;
    _monitoring = NO;

    [VCURLProtocol uninstall];
    [[VCWebSocketMonitor shared] uninstall];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kVCURLProtocolDidCaptureRecord object:nil];

    VCLog(@"[Net] Monitoring stopped");
}

#pragma mark - Layer 1 Install

- (void)_installSessionHooks {
    Class cls = [NSURLSession class];

    // dataTaskWithRequest:completionHandler:
    SEL dataSel = @selector(dataTaskWithRequest:completionHandler:);
    Method dataMethod = class_getInstanceMethod(cls, dataSel);
    if (dataMethod && !_origDataTask) {
        _origDataTask = method_setImplementation(dataMethod, (IMP)vc_swizzled_dataTask);
    }

    // uploadTaskWithRequest:fromData:completionHandler:
    SEL uploadSel = @selector(uploadTaskWithRequest:fromData:completionHandler:);
    Method uploadMethod = class_getInstanceMethod(cls, uploadSel);
    if (uploadMethod && !_origUploadTask) {
        _origUploadTask = method_setImplementation(uploadMethod, (IMP)vc_swizzled_uploadTask);
    }

    // downloadTaskWithRequest:completionHandler:
    SEL downloadSel = @selector(downloadTaskWithRequest:completionHandler:);
    Method downloadMethod = class_getInstanceMethod(cls, downloadSel);
    if (downloadMethod && !_origDownloadTask) {
        _origDownloadTask = method_setImplementation(downloadMethod, (IMP)vc_swizzled_downloadTask);
    }

    // Delegate hooks: 遍历已注册的 delegate 类
    // 使用 protocol 方法确保覆盖常见 delegate
    [self _hookDelegateMethod:@protocol(NSURLSessionDataDelegate)
                          sel:@selector(URLSession:dataTask:didReceiveData:)
                       newIMP:(IMP)vc_swizzled_didReceiveData
                     origSlot:&_origDidReceiveData];

    [self _hookDelegateMethod:@protocol(NSURLSessionTaskDelegate)
                          sel:@selector(URLSession:task:didCompleteWithError:)
                       newIMP:(IMP)vc_swizzled_didComplete
                     origSlot:&_origDidComplete];

    VCLog(@"[Net] NSURLSession Layer 1 hooks installed");
}

- (void)_hookDelegateMethod:(Protocol *)proto sel:(SEL)sel newIMP:(IMP)newIMP origSlot:(IMP *)origSlot {
    if (*origSlot) return; // 已 hook

    // 策略: 遍历已注册的类，找到实现了该 delegate 方法的类并 hook
    // 优先 hook 常见的内部类
    NSArray *candidateClassNames = @[
        @"__NSCFURLSessionConnection",
        @"__NSURLSessionLocal",
        @"NSURLSession",
    ];

    for (NSString *clsName in candidateClassNames) {
        Class cls = NSClassFromString(clsName);
        if (!cls) continue;

        Method m = class_getInstanceMethod(cls, sel);
        if (m) {
            *origSlot = method_setImplementation(m, newIMP);
            VCLog(@"[Net] Delegate hook installed on %@ for %@", clsName, NSStringFromSelector(sel));
            return;
        }
    }

    // Fallback: 扫描所有 conform 该 protocol 的类 (限制扫描数量)
    unsigned int classCount = 0;
    Class *classes = objc_copyClassList(&classCount);
    NSUInteger hooked = 0;
    for (unsigned int i = 0; i < classCount && hooked < 3; i++) {
        Class cls = classes[i];
        // 跳过 VC 自己的类
        const char *name = class_getName(cls);
        if (name && strncmp(name, "VC", 2) == 0) continue;

        if (class_conformsToProtocol(cls, proto)) {
            Method m = class_getInstanceMethod(cls, sel);
            if (m && !*origSlot) {
                *origSlot = method_setImplementation(m, newIMP);
                VCLog(@"[Net] Delegate hook installed on %s for %@", name, NSStringFromSelector(sel));
                hooked++;
            }
        }
    }
    free(classes);

    if (!*origSlot) {
        VCLog(@"[Net] Warning: no delegate class found for %@", NSStringFromSelector(sel));
    }
}

#pragma mark - Record Management

- (void)_addRecord:(VCNetRecord *)record {
    if (!record) return;
    dispatch_async(_queue, ^{
        [self->_records addObject:record];
        // 超过 500 条自动清理
        if (self->_records.count > kVCNetMaxRecords) {
            NSUInteger excess = self->_records.count - kVCNetMaxRecords;
            [self->_records removeObjectsInRange:NSMakeRange(0, excess)];
        }
        // 通知 delegate
        id<VCNetMonitorDelegate> d = self.delegate;
        if (d) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [d netMonitor:self didCaptureRecord:record];
            });
        }
    });
}

- (void)_addWebSocketFrame:(VCWebSocketFrame *)frame {
    if (!frame) return;
    dispatch_async(_queue, ^{
        [self->_webSocketFrames addObject:frame];
        if (self->_webSocketFrames.count > kVCNetMaxRecords) {
            NSUInteger excess = self->_webSocketFrames.count - kVCNetMaxRecords;
            [self->_webSocketFrames removeObjectsInRange:NSMakeRange(0, excess)];
        }
        id<VCNetMonitorDelegate> d = self.delegate;
        if (d) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [d netMonitor:self didCaptureWSFrame:frame];
            });
        }
    });
}

- (void)_onProtocolCapture:(NSNotification *)note {
    VCNetRecord *rec = note.object;
    if ([rec isKindOfClass:[VCNetRecord class]]) {
        [self _addRecord:rec];
    }
}

#pragma mark - Query

- (NSArray<VCNetRecord *> *)allRecords {
    __block NSArray *copy = nil;
    dispatch_sync(_queue, ^{
        copy = [self->_records copy];
    });
    return copy;
}

- (NSArray<VCWebSocketFrame *> *)allWebSocketFrames {
    __block NSArray *copy = nil;
    dispatch_sync(_queue, ^{
        copy = [self->_webSocketFrames copy];
    });
    return copy;
}

- (NSArray<VCNetRecord *> *)recordsMatchingFilter:(NSString *)filter {
    if (!filter || filter.length == 0) return [self allRecords];

    __block NSArray *result = nil;
    NSString *lowerFilter = filter.lowercaseString;
    dispatch_sync(_queue, ^{
        NSPredicate *pred = [NSPredicate predicateWithBlock:^BOOL(VCNetRecord *rec, NSDictionary *bindings) {
            return [rec.url.lowercaseString containsString:lowerFilter]
                || [rec.method.lowercaseString containsString:lowerFilter];
        }];
        result = [self->_records filteredArrayUsingPredicate:pred];
    });
    return result;
}

#pragma mark - Resend

- (void)resendRecord:(VCNetRecord *)record withModifications:(NSDictionary *)mods {
    if (!record) return;

    NSString *urlStr = mods[@"url"] ?: record.url;
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) return;

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    NSString *method = [mods[@"method"] isKindOfClass:[NSString class]] ? [mods[@"method"] uppercaseString] : nil;
    req.HTTPMethod = method.length > 0 ? method : record.method;

    // 原始 headers
    [record.requestHeaders enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *val, BOOL *stop) {
        [req setValue:val forHTTPHeaderField:key];
    }];

    // 覆盖 headers
    NSDictionary *modHeaders = mods[@"headers"];
    if (modHeaders) {
        [modHeaders enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *val, BOOL *stop) {
            [req setValue:val forHTTPHeaderField:key];
        }];
    }

    // Body
    NSData *body = nil;
    if (mods[@"body"]) {
        body = [mods[@"body"] dataUsingEncoding:NSUTF8StringEncoding];
    } else {
        body = record.requestBody;
    }
    req.HTTPBody = body;

    NSURLSession *session = [NSURLSession sharedSession];
    __weak VCNetMonitor *weakSelf = self;
    [[session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        __strong VCNetMonitor *strongSelf = weakSelf;
        if (!strongSelf) return;
        VCLog(@"[Net] Resend %@ %@ -> %ld", req.HTTPMethod ?: @"GET", urlStr, (long)((NSHTTPURLResponse *)response).statusCode);
    }] resume];
}

#pragma mark - cURL

- (NSString *)curlCommandForRecord:(VCNetRecord *)record {
    return [record curlCommand];
}

#pragma mark - Intercept Rules

- (void)addInterceptRule:(NSString *)urlPattern {
    if (!urlPattern) return;
    dispatch_async(_queue, ^{
        [self->_interceptRules addObject:urlPattern];
    });
}

- (void)removeInterceptRule:(NSString *)urlPattern {
    if (!urlPattern) return;
    dispatch_async(_queue, ^{
        [self->_interceptRules removeObject:urlPattern];
    });
}

#pragma mark - Clear

- (void)clearRecords {
    dispatch_async(_queue, ^{
        [self->_records removeAllObjects];
        [self->_webSocketFrames removeAllObjects];
    });
    VCLog(@"[Net] Records cleared");
}

@end
