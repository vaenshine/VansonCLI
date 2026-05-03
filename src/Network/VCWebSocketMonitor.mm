/**
 * VCWebSocketMonitor.mm -- WebSocket 帧监控 (Layer 3)
 * Swizzle NSURLSessionWebSocketTask send/receive
 */

#import "VCWebSocketMonitor.h"
#import "VCNetRecord.h"
#import "../../VansonCLI.h"
#import <objc/runtime.h>

static IMP _origSendMessage = NULL;
static IMP _origReceiveMessage = NULL;

// 关联 key: connectionID
static const void *kVCWSConnectionIDKey = &kVCWSConnectionIDKey;

#pragma mark - Swizzled Methods

static void vc_swizzled_sendMessage(id self, SEL _cmd, id message, void (^completion)(NSError *)) {
    // 获取或创建 connectionID
    NSString *connID = objc_getAssociatedObject(self, kVCWSConnectionIDKey);
    if (!connID) {
        connID = [[NSUUID UUID] UUIDString];
        objc_setAssociatedObject(self, kVCWSConnectionIDKey, connID, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    // 构建帧记录
    VCWebSocketFrame *frame = [[VCWebSocketFrame alloc] init];
    frame.connectionID = connID;
    frame.direction = @"send";

    // NSURLSessionWebSocketMessage
    if ([message respondsToSelector:@selector(type)]) {
        NSInteger msgType = [(NSURLSessionWebSocketMessage *)message type];
        if (msgType == NSURLSessionWebSocketMessageTypeString) {
            frame.type = @"text";
            NSString *str = [(NSURLSessionWebSocketMessage *)message string];
            frame.payload = [str dataUsingEncoding:NSUTF8StringEncoding];
        } else {
            frame.type = @"binary";
            frame.payload = [(NSURLSessionWebSocketMessage *)message data];
        }
    }

    VCWSFrameCallback cb = [VCWebSocketMonitor shared].onFrame;
    if (cb) cb(frame);

    // 调用原方法
    ((void(*)(id, SEL, id, void(^)(NSError *)))_origSendMessage)(self, _cmd, message, completion);
}

static void vc_swizzled_receiveMessage(id self, SEL _cmd, void (^completion)(NSURLSessionWebSocketMessage *, NSError *)) {
    NSString *connID = objc_getAssociatedObject(self, kVCWSConnectionIDKey);
    if (!connID) {
        connID = [[NSUUID UUID] UUIDString];
        objc_setAssociatedObject(self, kVCWSConnectionIDKey, connID, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    NSString *capturedConnID = connID;
    void (^wrappedCompletion)(NSURLSessionWebSocketMessage *, NSError *) = ^(NSURLSessionWebSocketMessage *msg, NSError *error) {
        if (msg && !error) {
            VCWebSocketFrame *frame = [[VCWebSocketFrame alloc] init];
            frame.connectionID = capturedConnID;
            frame.direction = @"receive";

            if (msg.type == NSURLSessionWebSocketMessageTypeString) {
                frame.type = @"text";
                frame.payload = [msg.string dataUsingEncoding:NSUTF8StringEncoding];
            } else {
                frame.type = @"binary";
                frame.payload = msg.data;
            }

            VCWSFrameCallback cb = [VCWebSocketMonitor shared].onFrame;
            if (cb) cb(frame);
        }
        if (completion) completion(msg, error);
    };

    ((void(*)(id, SEL, void(^)(NSURLSessionWebSocketMessage *, NSError *)))_origReceiveMessage)(self, _cmd, wrappedCompletion);
}

#pragma mark - VCWebSocketMonitor

@implementation VCWebSocketMonitor {
    BOOL _installed;
}

+ (instancetype)shared {
    static VCWebSocketMonitor *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VCWebSocketMonitor alloc] init];
    });
    return instance;
}

- (void)install {
    if (_installed) return;
    _installed = YES;

    Class cls = NSClassFromString(@"__NSCFURLSessionWebSocketTask");
    if (!cls) cls = [NSURLSessionWebSocketTask class];

    // sendMessage:completionHandler:
    SEL sendSel = @selector(sendMessage:completionHandler:);
    Method sendMethod = class_getInstanceMethod(cls, sendSel);
    if (sendMethod) {
        _origSendMessage = method_setImplementation(sendMethod, (IMP)vc_swizzled_sendMessage);
        VCLog(@"[Net] WebSocket sendMessage hooked");
    }

    // receiveMessageWithCompletionHandler:
    SEL recvSel = @selector(receiveMessageWithCompletionHandler:);
    Method recvMethod = class_getInstanceMethod(cls, recvSel);
    if (recvMethod) {
        _origReceiveMessage = method_setImplementation(recvMethod, (IMP)vc_swizzled_receiveMessage);
        VCLog(@"[Net] WebSocket receiveMessage hooked");
    }
}

- (void)uninstall {
    if (!_installed) return;
    _installed = NO;

    Class cls = NSClassFromString(@"__NSCFURLSessionWebSocketTask");
    if (!cls) cls = [NSURLSessionWebSocketTask class];

    if (_origSendMessage) {
        Method m = class_getInstanceMethod(cls, @selector(sendMessage:completionHandler:));
        if (m) method_setImplementation(m, _origSendMessage);
        _origSendMessage = NULL;
    }
    if (_origReceiveMessage) {
        Method m = class_getInstanceMethod(cls, @selector(receiveMessageWithCompletionHandler:));
        if (m) method_setImplementation(m, _origReceiveMessage);
        _origReceiveMessage = NULL;
    }
    VCLog(@"[Net] WebSocket hooks removed");
}

@end
