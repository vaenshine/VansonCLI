/**
 * VCHookManager -- 动态 Hook 执行引擎
 */

#import "VCHookManager.h"
#import "../../VansonCLI.h"
#import "../Core/VCCapabilityManager.h"
#import "../AI/Security/VCPromptLeakGuard.h"
#import "../Patches/VCPatchItem.h"
#import "../Patches/VCHookItem.h"
#import "../Patches/VCValueItem.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach/mach.h>
#import <pthread.h>

NSString *const kVCHookManagerDidCaptureInvocationNotification = @"com.vanson.cli.hook.invocation";
static NSString *const kVCHookManagerTraceStackKey = @"com.vanson.cli.hook.traceStack";

@interface VCHookManager ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSValue *> *originalIMPs;   // key -> original IMP
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSValue *> *hookOrigIMPs;   // hookID -> original IMP
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *hookMethodKeys; // hookID -> method key
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *forwardedTypeEncodings; // method key -> type encoding
@property (nonatomic, strong) NSMutableDictionary<NSString *, VCPatchItem *> *activePatchItems; // method key -> patch
@property (nonatomic, strong) NSMutableDictionary<NSString *, VCHookItem *> *activeHookItems; // method key -> hook
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSValue *> *forwardInvocationIMPs; // class key -> original forwardInvocation:
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSValue *> *methodSignatureIMPs; // class key -> original methodSignatureForSelector:
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *forwardingInstallCounts; // class key -> ref count
@property (nonatomic, strong) NSMutableDictionary<NSString *, dispatch_source_t> *lockTimers; // valueID -> timer

- (NSMethodSignature *)_methodSignatureForForwardedSelector:(SEL)selector receiver:(id)receiver;
- (void)_handleForwardInvocation:(NSInvocation *)invocation receiver:(id)receiver;
@end

static NSDictionary *VCParsePatchMetadata(NSString *customCode) {
    if (![customCode isKindOfClass:[NSString class]] || customCode.length == 0) return nil;
    NSData *data = [customCode dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [json isKindOfClass:[NSDictionary class]] ? json : nil;
}

static const char *VCSkipTypeQualifiers(const char *type) {
    while (type && (*type == 'r' || *type == 'n' || *type == 'N' ||
                    *type == 'o' || *type == 'O' || *type == 'R' || *type == 'V')) {
        type++;
    }
    return type;
}

static char VCNormalizedReturnType(NSMethodSignature *signature) {
    const char *type = VCSkipTypeQualifiers(signature.methodReturnType);
    return (type && *type) ? *type : '\0';
}

static NSString *VCReadableReturnType(NSMethodSignature *signature) {
    const char *type = VCSkipTypeQualifiers(signature.methodReturnType);
    return type ? [NSString stringWithUTF8String:type] : @"?";
}

static BOOL VCTruthyPatchSupportsSignature(NSMethodSignature *signature) {
    char returnType = VCNormalizedReturnType(signature);
    switch (returnType) {
        case 'v':
        case 'B':
        case 'c':
        case 'C':
        case 's':
        case 'S':
        case 'i':
        case 'I':
        case 'l':
        case 'L':
        case 'q':
        case 'Q':
        case 'f':
        case 'd':
        case '#':
            return YES;
        default:
            return NO;
    }
}

static uint64_t VCCurrentThreadTraceID(void) {
    uint64_t threadID = 0;
    if (pthread_threadid_np(NULL, &threadID) != 0) {
        threadID = (uint64_t)[NSThread currentThread].hash;
    }
    return threadID;
}

static NSMutableArray<NSMutableDictionary *> *VCTraceInvocationStackForCurrentThread(BOOL createIfMissing) {
    NSMutableDictionary *threadDictionary = [[NSThread currentThread] threadDictionary];
    NSMutableArray<NSMutableDictionary *> *stack = threadDictionary[kVCHookManagerTraceStackKey];
    if (!stack && createIfMissing) {
        stack = [NSMutableArray new];
        threadDictionary[kVCHookManagerTraceStackKey] = stack;
    }
    return stack;
}

static NSDictionary *VCTraceContextSnapshotFromStack(NSArray<NSDictionary *> *stack, uint64_t threadID) {
    if (![stack isKindOfClass:[NSArray class]] || stack.count == 0) return nil;

    NSMutableArray<NSDictionary *> *frames = [NSMutableArray new];
    NSUInteger depth = 0;
    for (NSDictionary *frame in stack) {
        NSString *className = [frame[@"className"] isKindOfClass:[NSString class]] ? frame[@"className"] : @"";
        NSString *selector = [frame[@"selector"] isKindOfClass:[NSString class]] ? frame[@"selector"] : @"";
        NSString *invocationID = [frame[@"invocationID"] isKindOfClass:[NSString class]] ? frame[@"invocationID"] : @"";
        NSString *displayName = (className.length > 0 && selector.length > 0)
            ? [NSString stringWithFormat:@"-[%@ %@]", className, selector]
            : className;
        [frames addObject:@{
            @"invocationID": invocationID,
            @"className": className,
            @"selector": selector,
            @"depth": @(depth),
            @"displayName": displayName ?: @""
        }];
        depth++;
    }

    NSDictionary *currentFrame = frames.lastObject ?: @{};
    NSDictionary *parentFrame = frames.count > 1 ? frames[frames.count - 2] : nil;
    return @{
        @"threadID": @(threadID),
        @"depth": @(frames.count),
        @"currentInvocationID": currentFrame[@"invocationID"] ?: @"",
        @"parentInvocationID": parentFrame[@"invocationID"] ?: @"",
        @"currentDisplayName": currentFrame[@"displayName"] ?: @"",
        @"frames": [frames copy]
    };
}

static NSMethodSignature *VCForwardedMethodSignature(id self, SEL _cmd, SEL selector) {
    return [[VCHookManager shared] _methodSignatureForForwardedSelector:selector receiver:self];
}

static void VCForwardedInvocation(id self, SEL _cmd, NSInvocation *invocation) {
    [[VCHookManager shared] _handleForwardInvocation:invocation receiver:self];
}

@implementation VCHookManager

+ (instancetype)shared {
    static VCHookManager *inst;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ inst = [[self alloc] init]; });
    return inst;
}

- (instancetype)init {
    if (self = [super init]) {
        _originalIMPs = [NSMutableDictionary new];
        _hookOrigIMPs = [NSMutableDictionary new];
        _hookMethodKeys = [NSMutableDictionary new];
        _forwardedTypeEncodings = [NSMutableDictionary new];
        _activePatchItems = [NSMutableDictionary new];
        _activeHookItems = [NSMutableDictionary new];
        _forwardInvocationIMPs = [NSMutableDictionary new];
        _methodSignatureIMPs = [NSMutableDictionary new];
        _forwardingInstallCounts = [NSMutableDictionary new];
        _lockTimers = [NSMutableDictionary new];
    }
    return self;
}

#pragma mark - Patch Key

- (NSString *)keyForClass:(NSString *)cls selector:(NSString *)sel isClassMethod:(BOOL)isClassMethod {
    return [NSString stringWithFormat:@"%c%@|%@", isClassMethod ? '+' : '-', cls ?: @"", sel ?: @""];
}

- (NSString *)_classKeyForClass:(Class)cls isClassMethod:(BOOL)isClassMethod {
    return [NSString stringWithFormat:@"%c%@", isClassMethod ? '+' : '-', NSStringFromClass(cls) ?: @""];
}

- (Method)_methodForClassName:(NSString *)className selector:(NSString *)selector isClassMethod:(BOOL)isClassMethod {
    if (!className.length || !selector.length) return NULL;
    Class cls = NSClassFromString(className);
    if (!cls) return NULL;
    SEL sel = NSSelectorFromString(selector);
    return isClassMethod ? class_getClassMethod(cls, sel) : class_getInstanceMethod(cls, sel);
}

- (NSMethodSignature *)_signatureForMethod:(Method)method {
    if (!method) return nil;
    const char *types = method_getTypeEncoding(method);
    return types ? [NSMethodSignature signatureWithObjCTypes:types] : nil;
}

- (NSString *)_methodKeyForReceiver:(id)receiver selector:(SEL)selector {
    BOOL isClassMethod = object_isClass(receiver);
    Class cls = isClassMethod ? (Class)receiver : [receiver class];
    return [self keyForClass:NSStringFromClass(cls) selector:NSStringFromSelector(selector) isClassMethod:isClassMethod];
}

- (void)_installForwardingSupportForClass:(Class)cls isClassMethod:(BOOL)isClassMethod {
    if (!cls) return;

    Class targetClass = isClassMethod ? object_getClass(cls) : cls;
    NSString *classKey = [self _classKeyForClass:cls isClassMethod:isClassMethod];
    NSUInteger count = [self.forwardingInstallCounts[classKey] unsignedIntegerValue];
    if (count == 0) {
        SEL signatureSEL = @selector(methodSignatureForSelector:);
        IMP origSignatureIMP = class_getMethodImplementation(targetClass, signatureSEL);
        Method currentSignatureMethod = class_getInstanceMethod(targetClass, signatureSEL);
        const char *signatureTypes = currentSignatureMethod ? method_getTypeEncoding(currentSignatureMethod) : "@@::";
        self.methodSignatureIMPs[classKey] = [NSValue valueWithPointer:(const void *)origSignatureIMP];
        class_replaceMethod(targetClass, signatureSEL, (IMP)VCForwardedMethodSignature, signatureTypes);

        SEL forwardSEL = @selector(forwardInvocation:);
        IMP origForwardIMP = class_getMethodImplementation(targetClass, forwardSEL);
        Method currentForwardMethod = class_getInstanceMethod(targetClass, forwardSEL);
        const char *forwardTypes = currentForwardMethod ? method_getTypeEncoding(currentForwardMethod) : "v@:@";
        self.forwardInvocationIMPs[classKey] = [NSValue valueWithPointer:(const void *)origForwardIMP];
        class_replaceMethod(targetClass, forwardSEL, (IMP)VCForwardedInvocation, forwardTypes);
    }
    self.forwardingInstallCounts[classKey] = @(count + 1);
}

- (void)_uninstallForwardingSupportForClass:(Class)cls isClassMethod:(BOOL)isClassMethod {
    if (!cls) return;

    NSString *classKey = [self _classKeyForClass:cls isClassMethod:isClassMethod];
    NSUInteger count = [self.forwardingInstallCounts[classKey] unsignedIntegerValue];
    if (count <= 1) {
        Class targetClass = isClassMethod ? object_getClass(cls) : cls;
        SEL signatureSEL = @selector(methodSignatureForSelector:);
        NSValue *origSignatureValue = self.methodSignatureIMPs[classKey];
        if (origSignatureValue) {
            Method signatureMethod = class_getInstanceMethod(targetClass, signatureSEL);
            const char *signatureTypes = signatureMethod ? method_getTypeEncoding(signatureMethod) : "@@::";
            class_replaceMethod(targetClass, signatureSEL, (IMP)[origSignatureValue pointerValue], signatureTypes);
            [self.methodSignatureIMPs removeObjectForKey:classKey];
        }

        SEL forwardSEL = @selector(forwardInvocation:);
        NSValue *origForwardValue = self.forwardInvocationIMPs[classKey];
        if (origForwardValue) {
            Method forwardMethod = class_getInstanceMethod(targetClass, forwardSEL);
            const char *forwardTypes = forwardMethod ? method_getTypeEncoding(forwardMethod) : "v@:@";
            class_replaceMethod(targetClass, forwardSEL, (IMP)[origForwardValue pointerValue], forwardTypes);
            [self.forwardInvocationIMPs removeObjectForKey:classKey];
        }
        [self.forwardingInstallCounts removeObjectForKey:classKey];
        return;
    }
    self.forwardingInstallCounts[classKey] = @(count - 1);
}

- (void)_setZeroReturnValueForInvocation:(NSInvocation *)invocation {
    NSUInteger length = invocation.methodSignature.methodReturnLength;
    if (length == 0) return;
    void *buffer = calloc(1, length);
    [invocation setReturnValue:buffer];
    free(buffer);
}

- (BOOL)_setTruthyReturnValueForInvocation:(NSInvocation *)invocation receiver:(id)receiver reason:(NSString **)reason {
    char returnType = VCNormalizedReturnType(invocation.methodSignature);
    switch (returnType) {
        case 'v':
            return YES;
        case 'B': {
            BOOL value = YES;
            [invocation setReturnValue:&value];
            return YES;
        }
        case 'c': {
            char value = 1;
            [invocation setReturnValue:&value];
            return YES;
        }
        case 'C': {
            unsigned char value = 1;
            [invocation setReturnValue:&value];
            return YES;
        }
        case 's': {
            short value = 1;
            [invocation setReturnValue:&value];
            return YES;
        }
        case 'S': {
            unsigned short value = 1;
            [invocation setReturnValue:&value];
            return YES;
        }
        case 'i': {
            int value = 1;
            [invocation setReturnValue:&value];
            return YES;
        }
        case 'I': {
            unsigned int value = 1;
            [invocation setReturnValue:&value];
            return YES;
        }
        case 'l': {
            long value = 1;
            [invocation setReturnValue:&value];
            return YES;
        }
        case 'L': {
            unsigned long value = 1;
            [invocation setReturnValue:&value];
            return YES;
        }
        case 'q': {
            long long value = 1;
            [invocation setReturnValue:&value];
            return YES;
        }
        case 'Q': {
            unsigned long long value = 1;
            [invocation setReturnValue:&value];
            return YES;
        }
        case 'f': {
            float value = 1.0f;
            [invocation setReturnValue:&value];
            return YES;
        }
        case 'd': {
            double value = 1.0;
            [invocation setReturnValue:&value];
            return YES;
        }
        case '#': {
            Class value = object_isClass(receiver) ? (Class)receiver : [receiver class];
            [invocation setReturnValue:&value];
            return YES;
        }
        default:
            if (reason) *reason = [NSString stringWithFormat:@"return_yes is unsupported for return type %@",
                                   VCReadableReturnType(invocation.methodSignature)];
            return NO;
    }
}

- (NSString *)_stringFromReturnValueOfInvocation:(NSInvocation *)invocation {
    char returnType = VCNormalizedReturnType(invocation.methodSignature);
    switch (returnType) {
        case 'v':
            return @"void";
        case 'B': {
            BOOL value = NO;
            [invocation getReturnValue:&value];
            return value ? @"YES" : @"NO";
        }
        case 'c': {
            char value = 0;
            [invocation getReturnValue:&value];
            return [NSString stringWithFormat:@"%d", (int)value];
        }
        case 'C': {
            unsigned char value = 0;
            [invocation getReturnValue:&value];
            return [NSString stringWithFormat:@"%u", (unsigned int)value];
        }
        case 's': {
            short value = 0;
            [invocation getReturnValue:&value];
            return [NSString stringWithFormat:@"%d", (int)value];
        }
        case 'S': {
            unsigned short value = 0;
            [invocation getReturnValue:&value];
            return [NSString stringWithFormat:@"%u", (unsigned int)value];
        }
        case 'i': {
            int value = 0;
            [invocation getReturnValue:&value];
            return [NSString stringWithFormat:@"%d", value];
        }
        case 'I': {
            unsigned int value = 0;
            [invocation getReturnValue:&value];
            return [NSString stringWithFormat:@"%u", value];
        }
        case 'l': {
            long value = 0;
            [invocation getReturnValue:&value];
            return [NSString stringWithFormat:@"%ld", value];
        }
        case 'L': {
            unsigned long value = 0;
            [invocation getReturnValue:&value];
            return [NSString stringWithFormat:@"%lu", value];
        }
        case 'q': {
            long long value = 0;
            [invocation getReturnValue:&value];
            return [NSString stringWithFormat:@"%lld", value];
        }
        case 'Q': {
            unsigned long long value = 0;
            [invocation getReturnValue:&value];
            return [NSString stringWithFormat:@"%llu", value];
        }
        case 'f': {
            float value = 0;
            [invocation getReturnValue:&value];
            return [NSString stringWithFormat:@"%f", value];
        }
        case 'd': {
            double value = 0;
            [invocation getReturnValue:&value];
            return [NSString stringWithFormat:@"%f", value];
        }
        case '@': {
            __unsafe_unretained id value = nil;
            [invocation getReturnValue:&value];
            return value ? [value description] : @"(nil)";
        }
        case '#': {
            Class value = Nil;
            [invocation getReturnValue:&value];
            return value ? NSStringFromClass(value) : @"Nil";
        }
        case ':': {
            SEL value = NULL;
            [invocation getReturnValue:&value];
            return value ? NSStringFromSelector(value) : @"NULL";
        }
        case '*': {
            char *value = NULL;
            [invocation getReturnValue:&value];
            return value ? [NSString stringWithUTF8String:value] : @"NULL";
        }
        case '^': {
            void *value = NULL;
            [invocation getReturnValue:&value];
            return [NSString stringWithFormat:@"%p", value];
        }
        default:
            return [NSString stringWithFormat:@"<return type %@, %lu bytes>",
                    VCReadableReturnType(invocation.methodSignature),
                    (unsigned long)invocation.methodSignature.methodReturnLength];
    }
}

- (NSMethodSignature *)_methodSignatureForForwardedSelector:(SEL)selector receiver:(id)receiver {
    NSString *methodKey = [self _methodKeyForReceiver:receiver selector:selector];
    NSString *typeEncoding = nil;
    NSString *classKey = nil;
    IMP origIMP = NULL;

    @synchronized (self) {
        typeEncoding = self.forwardedTypeEncodings[methodKey];
        BOOL isClassMethod = object_isClass(receiver);
        Class cls = isClassMethod ? (Class)receiver : [receiver class];
        classKey = [self _classKeyForClass:cls isClassMethod:isClassMethod];
        origIMP = (IMP)[self.methodSignatureIMPs[classKey] pointerValue];
    }

    if (typeEncoding.length > 0) {
        return [NSMethodSignature signatureWithObjCTypes:typeEncoding.UTF8String];
    }
    if (origIMP) {
        return ((NSMethodSignature *(*)(id, SEL, SEL))origIMP)(receiver, @selector(methodSignatureForSelector:), selector);
    }
    return nil;
}

- (void)_handleForwardInvocation:(NSInvocation *)invocation receiver:(id)receiver {
    SEL selector = invocation.selector;
    NSString *methodKey = [self _methodKeyForReceiver:receiver selector:selector];
    VCPatchItem *patchItem = nil;
    VCHookItem *hookItem = nil;
    IMP origPatchIMP = NULL;
    IMP origHookIMP = NULL;
    IMP origForwardIMP = NULL;
    NSString *className = nil;
    BOOL isClassMethod = NO;

    @synchronized (self) {
        patchItem = self.activePatchItems[methodKey];
        hookItem = self.activeHookItems[methodKey];
        origPatchIMP = (IMP)[self.originalIMPs[methodKey] pointerValue];
        origHookIMP = hookItem ? (IMP)[self.hookOrigIMPs[hookItem.hookID] pointerValue] : NULL;

        isClassMethod = object_isClass(receiver);
        Class cls = isClassMethod ? (Class)receiver : [receiver class];
        className = NSStringFromClass(cls);
        NSString *classKey = [self _classKeyForClass:cls isClassMethod:isClassMethod];
        origForwardIMP = (IMP)[self.forwardInvocationIMPs[classKey] pointerValue];
    }

    if (patchItem) {
        NSString *patchType = patchItem.patchType ?: @"nop";
        if ([patchType isEqualToString:@"return_no"] || [patchType isEqualToString:@"nop"] || [patchType isEqualToString:@"custom"]) {
            [self _setZeroReturnValueForInvocation:invocation];
            VCLog("applyPatch: forwarded %@ -[%@ %@]", patchType, className, NSStringFromSelector(selector));
            return;
        }
        if ([patchType isEqualToString:@"return_yes"]) {
            NSString *reason = nil;
            if ([self _setTruthyReturnValueForInvocation:invocation receiver:receiver reason:&reason]) {
                VCLog("applyPatch: forwarded return_yes -[%@ %@]", className, NSStringFromSelector(selector));
                return;
            }
            VCLog("applyPatch: return_yes fallback to original -[%@ %@]: %@", className, NSStringFromSelector(selector), reason ?: @"unknown");
        }

        if (origPatchIMP) {
            [invocation invokeUsingIMP:origPatchIMP];
            return;
        }
    }

    if (hookItem) {
        NSTimeInterval startedAt = [[NSDate date] timeIntervalSince1970];
        NSTimeInterval endedAt = startedAt;
        uint64_t threadID = VCCurrentThreadTraceID();
        NSMutableArray<NSMutableDictionary *> *traceStack = VCTraceInvocationStackForCurrentThread(YES);
        NSDictionary *parentFrame = traceStack.lastObject;
        NSString *invocationID = [[NSUUID UUID] UUIDString];
        NSString *parentInvocationID = [parentFrame[@"invocationID"] isKindOfClass:[NSString class]] ? parentFrame[@"invocationID"] : @"";
        NSUInteger callDepth = traceStack.count;
        NSMutableDictionary *currentFrame = [@{
            @"invocationID": invocationID ?: @"",
            @"className": className ?: @"",
            @"selector": NSStringFromSelector(selector) ?: @"",
            @"threadID": @(threadID)
        } mutableCopy];
        [traceStack addObject:currentFrame];

        VCLog("[Hook] -[%@ %@] called", className, NSStringFromSelector(selector));
        hookItem.hitCount++;

        if (origHookIMP) {
            @try {
                [invocation invokeUsingIMP:origHookIMP];
            } @finally {
                endedAt = [[NSDate date] timeIntervalSince1970];
                if (traceStack.lastObject == currentFrame) {
                    [traceStack removeLastObject];
                } else {
                    [traceStack removeObject:currentFrame];
                }
                if (traceStack.count == 0) {
                    [[[NSThread currentThread] threadDictionary] removeObjectForKey:kVCHookManagerTraceStackKey];
                }
            }
            NSString *returnValue = [self _stringFromReturnValueOfInvocation:invocation];
            VCLog("[Hook] -[%@ %@] returned %@", className, NSStringFromSelector(selector), returnValue);
            [[NSNotificationCenter defaultCenter] postNotificationName:kVCHookManagerDidCaptureInvocationNotification
                                                                object:self
                                                              userInfo:@{
                @"hookID": hookItem.hookID ?: @"",
                @"invocationID": invocationID ?: @"",
                @"parentInvocationID": parentInvocationID ?: @"",
                @"className": className ?: @"",
                @"selector": NSStringFromSelector(selector) ?: @"",
                @"isClassMethod": @(isClassMethod),
                @"callDepth": @(callDepth),
                @"threadID": @(threadID),
                @"startedAt": @(startedAt),
                @"endedAt": @(endedAt),
                @"returnValue": returnValue ?: @"",
                @"durationMs": @((NSUInteger)llround((endedAt - startedAt) * 1000.0)),
                @"timestamp": @(endedAt),
            }];
            return;
        }
        [traceStack removeObject:currentFrame];
        if (traceStack.count == 0) {
            [[[NSThread currentThread] threadDictionary] removeObjectForKey:kVCHookManagerTraceStackKey];
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:kVCHookManagerDidCaptureInvocationNotification
                                                            object:self
                                                          userInfo:@{
            @"hookID": hookItem.hookID ?: @"",
            @"invocationID": invocationID ?: @"",
            @"parentInvocationID": parentInvocationID ?: @"",
            @"className": className ?: @"",
            @"selector": NSStringFromSelector(selector) ?: @"",
            @"isClassMethod": @(isClassMethod),
            @"callDepth": @(callDepth),
            @"threadID": @(threadID),
            @"startedAt": @(startedAt),
            @"endedAt": @(endedAt),
            @"returnValue": @"",
            @"durationMs": @0,
            @"timestamp": @(endedAt),
        }];
    }

    if (origForwardIMP) {
        ((void (*)(id, SEL, NSInvocation *))origForwardIMP)(receiver, @selector(forwardInvocation:), invocation);
    } else {
        [receiver doesNotRecognizeSelector:selector];
    }
}

#pragma mark - Patch 执行

- (BOOL)applyPatch:(VCPatchItem *)item {
    if (!item.className || !item.selector) return NO;
    NSString *protectedReason = [VCPromptLeakGuard blockedToolReasonForClassName:item.className moduleName:nil];
    if (protectedReason.length > 0) {
        VCLog("applyPatch: blocked protected target %@ %@ -- %@", item.className, item.selector, protectedReason);
        return NO;
    }

    NSString *capabilityReason = nil;
    if (![[VCCapabilityManager shared] canUseRuntimePatchingWithReason:&capabilityReason]) {
        VCLog("applyPatch: blocked %@ %@ -- %@", item.className, item.selector, capabilityReason);
        return NO;
    }
    if ([item.patchType isEqualToString:@"custom"]) {
        VCLog("applyPatch: custom patch execution is not implemented safely yet");
        return NO;
    }

    NSDictionary *metadata = VCParsePatchMetadata(item.customCode);
    BOOL isClassMethod = [metadata[@"isClassMethod"] boolValue];

    Class cls = NSClassFromString(item.className);
    if (!cls) {
        VCLog("applyPatch: class not found: %@", item.className);
        return NO;
    }

    SEL sel = NSSelectorFromString(item.selector);
    Method method = isClassMethod ? class_getClassMethod(cls, sel) : class_getInstanceMethod(cls, sel);
    if (!method) {
        VCLog("applyPatch: method not found: %@", item.selector);
        return NO;
    }
    NSMethodSignature *signature = [self _signatureForMethod:method];
    if ([item.patchType isEqualToString:@"return_yes"] && !VCTruthyPatchSupportsSignature(signature)) {
        VCLog("applyPatch: return_yes is unsafe for return type %@", VCReadableReturnType(signature));
        return NO;
    }

    if ([item.patchType isEqualToString:@"swizzle"]) {
        NSString *otherClassName = metadata[@"otherClassName"] ?: metadata[@"swizzleClass"] ?: metadata[@"targetClass"];
        NSString *otherSelector = metadata[@"otherSelector"] ?: metadata[@"swizzleSelector"] ?: metadata[@"targetSelector"];
        BOOL otherIsClassMethod = [metadata[@"otherIsClassMethod"] boolValue];
        Method otherMethod = [self _methodForClassName:otherClassName selector:otherSelector isClassMethod:otherIsClassMethod];
        if (!otherMethod) {
            VCLog("applyPatch: swizzle target not found %@ %@", otherClassName, otherSelector);
            return NO;
        }

        method_exchangeImplementations(method, otherMethod);
        VCLog("applyPatch: swizzled %c[%@ %@] <-> %c[%@ %@]",
              isClassMethod ? '+' : '-',
              item.className, item.selector,
              otherIsClassMethod ? '+' : '-',
              otherClassName, otherSelector);
        return YES;
    }

    NSString *key = [self keyForClass:item.className selector:item.selector isClassMethod:isClassMethod];

    @synchronized (self) {
        if (self.activeHookItems[key] || self.activePatchItems[key]) {
            VCLog("applyPatch: %@ already has an active forwarded item", key);
            return NO;
        }
        IMP origIMP = method_getImplementation(method);
        if (!origIMP) {
            VCLog("applyPatch: failed to read original IMP for %@", key);
            return NO;
        }

        self.originalIMPs[key] = [NSValue valueWithPointer:(const void *)origIMP];
        self.forwardedTypeEncodings[key] = [NSString stringWithUTF8String:method_getTypeEncoding(method)];
        self.activePatchItems[key] = item;
        [self _installForwardingSupportForClass:cls isClassMethod:isClassMethod];
        method_setImplementation(method, (IMP)_objc_msgForward);
    }

    VCLog("applyPatch: %@ -[%@ %@]", item.patchType, item.className, item.selector);
    return YES;
}

- (BOOL)revertPatch:(VCPatchItem *)item {
    if (!item.className || !item.selector) return NO;

    NSDictionary *metadata = VCParsePatchMetadata(item.customCode);
    BOOL isClassMethod = [metadata[@"isClassMethod"] boolValue];

    Class cls = NSClassFromString(item.className);
    if (!cls) return NO;

    SEL sel = NSSelectorFromString(item.selector);
    Method method = isClassMethod ? class_getClassMethod(cls, sel) : class_getInstanceMethod(cls, sel);
    if (!method) return NO;

    if ([item.patchType isEqualToString:@"swizzle"]) {
        NSString *otherClassName = metadata[@"otherClassName"] ?: metadata[@"swizzleClass"] ?: metadata[@"targetClass"];
        NSString *otherSelector = metadata[@"otherSelector"] ?: metadata[@"swizzleSelector"] ?: metadata[@"targetSelector"];
        BOOL otherIsClassMethod = [metadata[@"otherIsClassMethod"] boolValue];
        Method otherMethod = [self _methodForClassName:otherClassName selector:otherSelector isClassMethod:otherIsClassMethod];
        if (!otherMethod) return NO;
        method_exchangeImplementations(method, otherMethod);
        VCLog("revertPatch: unswizzled %c[%@ %@] <-> %c[%@ %@]",
              isClassMethod ? '+' : '-',
              item.className, item.selector,
              otherIsClassMethod ? '+' : '-',
              otherClassName, otherSelector);
        return YES;
    }

    NSString *key = [self keyForClass:item.className selector:item.selector isClassMethod:isClassMethod];

    @synchronized (self) {
        NSValue *origVal = self.originalIMPs[key];
        if (!origVal) {
            VCLog("revertPatch: no original IMP for %@", key);
            return NO;
        }
        IMP origIMP = (IMP)[origVal pointerValue];
        method_setImplementation(method, origIMP);
        [self.originalIMPs removeObjectForKey:key];
        [self.forwardedTypeEncodings removeObjectForKey:key];
        [self.activePatchItems removeObjectForKey:key];
        [self _uninstallForwardingSupportForClass:cls isClassMethod:isClassMethod];
    }

    VCLog("revertPatch: reverted -[%@ %@]", item.className, item.selector);
    return YES;
}

#pragma mark - Hook 安装

- (BOOL)installHook:(VCHookItem *)item {
    if (!item.className || !item.selector) return NO;
    NSString *protectedReason = [VCPromptLeakGuard blockedToolReasonForClassName:item.className moduleName:nil];
    if (protectedReason.length > 0) {
        VCLog("installHook: blocked protected target %@ %@ -- %@", item.className, item.selector, protectedReason);
        return NO;
    }

    NSString *capabilityReason = nil;
    if (![[VCCapabilityManager shared] canUseHookingWithReason:&capabilityReason]) {
        VCLog("installHook: blocked %@ %@ -- %@", item.className, item.selector, capabilityReason);
        return NO;
    }

    Class cls = NSClassFromString(item.className);
    if (!cls) {
        VCLog("installHook: class not found: %@", item.className);
        return NO;
    }

    SEL sel = NSSelectorFromString(item.selector);
    Method method = item.isClassMethod ? class_getClassMethod(cls, sel) : class_getInstanceMethod(cls, sel);
    if (!method) {
        VCLog("installHook: method not found: %@", item.selector);
        return NO;
    }

    NSString *methodKey = [self keyForClass:item.className selector:item.selector isClassMethod:item.isClassMethod];

    @synchronized (self) {
        if (self.hookOrigIMPs[item.hookID]) return YES;
        if (self.activeHookItems[methodKey] || self.activePatchItems[methodKey]) {
            VCLog("installHook: %@ already has an active forwarded item", methodKey);
            return NO;
        }

        IMP origIMP = method_getImplementation(method);
        if (![item.hookType isEqualToString:@"log"]) {
            VCLog("installHook: unsupported hook type %@", item.hookType ?: @"(null)");
            return NO;
        }

        self.hookOrigIMPs[item.hookID] = [NSValue valueWithPointer:(const void *)origIMP];
        self.hookMethodKeys[item.hookID] = methodKey;
        self.forwardedTypeEncodings[methodKey] = [NSString stringWithUTF8String:method_getTypeEncoding(method)];
        self.activeHookItems[methodKey] = item;
        [self _installForwardingSupportForClass:cls isClassMethod:item.isClassMethod];
        method_setImplementation(method, (IMP)_objc_msgForward);
    }

    VCLog("installHook: %@ %c[%@ %@]", item.hookType, item.isClassMethod ? '+' : '-', item.className, item.selector);
    return YES;
}

- (BOOL)removeHook:(VCHookItem *)item {
    if (!item.className || !item.selector) return NO;

    Class cls = NSClassFromString(item.className);
    if (!cls) return NO;

    SEL sel = NSSelectorFromString(item.selector);
    Method method = item.isClassMethod ? class_getClassMethod(cls, sel) : class_getInstanceMethod(cls, sel);
    if (!method) return NO;

    @synchronized (self) {
        NSValue *origVal = self.hookOrigIMPs[item.hookID];
        if (!origVal) return NO;

        IMP origIMP = (IMP)[origVal pointerValue];
        method_setImplementation(method, origIMP);
        [self.hookOrigIMPs removeObjectForKey:item.hookID];
        NSString *methodKey = self.hookMethodKeys[item.hookID] ?: [self keyForClass:item.className selector:item.selector isClassMethod:item.isClassMethod];
        [self.hookMethodKeys removeObjectForKey:item.hookID];
        [self.forwardedTypeEncodings removeObjectForKey:methodKey];
        [self.activeHookItems removeObjectForKey:methodKey];
        [self _uninstallForwardingSupportForClass:cls isClassMethod:item.isClassMethod];
    }

    VCLog("removeHook: removed %c[%@ %@]", item.isClassMethod ? '+' : '-', item.className, item.selector);
    return YES;
}

#pragma mark - 值锁定

- (BOOL)startLocking:(VCValueItem *)item {
    if (!item.valueID || item.address == 0) return NO;

    NSString *capabilityReason = nil;
    if (![[VCCapabilityManager shared] canUseMemoryWritesWithReason:&capabilityReason]) {
        VCLog("startLocking: blocked %@ -- %@", item.targetDesc ?: item.valueID, capabilityReason);
        return NO;
    }

    NSString *normalizedType = item.dataType.lowercaseString ?: @"";
    NSSet<NSString *> *supportedTypes = [NSSet setWithArray:@[
        @"char", @"uchar", @"short", @"ushort", @"int", @"uint",
        @"float", @"double", @"bool", @"long", @"ulong",
        @"longlong", @"ulonglong"
    ]];
    if (![supportedTypes containsObject:normalizedType]) {
        VCLog("startLocking: unsupported data type %@", item.dataType ?: @"(null)");
        return NO;
    }

    @synchronized (self) {
        // 已有 timer 则先停止
        if (self.lockTimers[item.valueID]) {
            [self stopLocking:item];
        }

        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                                          dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0));
        dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC, 0.1 * NSEC_PER_SEC);

        uintptr_t addr = item.address;
        NSString *dataType = [item.dataType copy];
        NSString *modValue = [item.modifiedValue copy];

        dispatch_source_set_event_handler(timer, ^{
            [self writeValue:modValue toAddress:addr dataType:dataType];
        });

        dispatch_resume(timer);
        self.lockTimers[item.valueID] = timer;
        VCLog("startLocking: %@ @ 0x%lx", item.targetDesc, (unsigned long)addr);
    }
    return YES;
}

- (void)stopLocking:(VCValueItem *)item {
    @synchronized (self) {
        dispatch_source_t timer = self.lockTimers[item.valueID];
        if (timer) {
            dispatch_source_cancel(timer);
            [self.lockTimers removeObjectForKey:item.valueID];
            VCLog("stopLocking: %@", item.valueID);
        }
    }
}

- (void)stopAllLocks {
    @synchronized (self) {
        for (NSString *key in self.lockTimers.allKeys) {
            dispatch_source_t timer = self.lockTimers[key];
            if (timer) dispatch_source_cancel(timer);
        }
        [self.lockTimers removeAllObjects];
        VCLog("stopAllLocks");
    }
}

#pragma mark - 内存写入

static BOOL vc_ensureWritable(uintptr_t addr, size_t size) {
    mach_port_t task = mach_task_self();
    vm_address_t region = (vm_address_t)addr;
    vm_size_t regionSize = 0;
    uint32_t depth = 1;
    struct vm_region_submap_info_64 info;
    mach_msg_type_number_t count = VM_REGION_SUBMAP_INFO_COUNT_64;

    kern_return_t kr = vm_region_recurse_64(task, &region, &regionSize, &depth,
                                             (vm_region_recurse_info_t)&info, &count);
    if (kr != KERN_SUCCESS) return NO;

    // 检查是否已经可写
    if (info.protection & VM_PROT_WRITE) return YES;

    // 尝试添加写权限
    kr = vm_protect(task, (vm_address_t)addr, (vm_size_t)size,
                    FALSE, info.protection | VM_PROT_WRITE);
    return (kr == KERN_SUCCESS);
}

static unsigned long long VCUnsignedLongLongFromString(NSString *value) {
    if (![value isKindOfClass:[NSString class]]) return 0;
    NSString *trimmed = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) return 0;
    return strtoull(trimmed.UTF8String, NULL, 0);
}

- (BOOL)writeValue:(NSString *)value toAddress:(uintptr_t)addr dataType:(NSString *)type {
    if (addr == 0 || !value) return NO;

    @try {
        NSString *lowerType = type.lowercaseString ?: @"";
        size_t writeSize = sizeof(void *); // default
        if ([lowerType isEqualToString:@"char"]) writeSize = sizeof(char);
        else if ([lowerType isEqualToString:@"uchar"]) writeSize = sizeof(unsigned char);
        else if ([lowerType isEqualToString:@"short"]) writeSize = sizeof(short);
        else if ([lowerType isEqualToString:@"ushort"]) writeSize = sizeof(unsigned short);
        else if ([lowerType isEqualToString:@"int"]) writeSize = sizeof(int);
        else if ([lowerType isEqualToString:@"uint"]) writeSize = sizeof(unsigned int);
        else if ([lowerType isEqualToString:@"float"]) writeSize = sizeof(float);
        else if ([lowerType isEqualToString:@"double"]) writeSize = sizeof(double);
        else if ([lowerType isEqualToString:@"bool"]) writeSize = sizeof(BOOL);
        else if ([lowerType isEqualToString:@"long"]) writeSize = sizeof(long);
        else if ([lowerType isEqualToString:@"ulong"]) writeSize = sizeof(unsigned long);
        else if ([lowerType isEqualToString:@"longlong"]) writeSize = sizeof(long long);
        else if ([lowerType isEqualToString:@"ulonglong"]) writeSize = sizeof(unsigned long long);

        if (!vc_ensureWritable(addr, writeSize)) {
            VCLog("writeValue: address 0x%lx is not writable", (unsigned long)addr);
            return NO;
        }

        if ([lowerType isEqualToString:@"char"]) {
            *(char *)addr = (char)[value intValue];
        } else if ([lowerType isEqualToString:@"uchar"]) {
            *(unsigned char *)addr = (unsigned char)[value intValue];
        } else if ([lowerType isEqualToString:@"short"]) {
            *(short *)addr = (short)[value intValue];
        } else if ([lowerType isEqualToString:@"ushort"]) {
            *(unsigned short *)addr = (unsigned short)[value intValue];
        } else if ([lowerType isEqualToString:@"int"]) {
            *(int *)addr = [value intValue];
        } else if ([lowerType isEqualToString:@"uint"]) {
            *(unsigned int *)addr = (unsigned int)VCUnsignedLongLongFromString(value);
        } else if ([lowerType isEqualToString:@"float"]) {
            *(float *)addr = [value floatValue];
        } else if ([lowerType isEqualToString:@"double"]) {
            *(double *)addr = [value doubleValue];
        } else if ([lowerType isEqualToString:@"bool"]) {
            *(BOOL *)addr = [value boolValue];
        } else if ([lowerType isEqualToString:@"long"]) {
            *(long *)addr = [value longLongValue];
        } else if ([lowerType isEqualToString:@"ulong"]) {
            *(unsigned long *)addr = (unsigned long)VCUnsignedLongLongFromString(value);
        } else if ([lowerType isEqualToString:@"longlong"]) {
            *(long long *)addr = [value longLongValue];
        } else if ([lowerType isEqualToString:@"ulonglong"]) {
            *(unsigned long long *)addr = VCUnsignedLongLongFromString(value);
        } else {
            VCLog("writeValue: unsupported type %@", type ?: @"(null)");
            return NO;
        }
        return YES;
    } @catch (NSException *e) {
        VCLog("writeValue exception at 0x%lx: %@", (unsigned long)addr, e.reason);
        return NO;
    }
}

- (NSDictionary *)currentTraceContextSnapshot {
    NSMutableArray<NSMutableDictionary *> *stack = VCTraceInvocationStackForCurrentThread(NO);
    return VCTraceContextSnapshotFromStack(stack, VCCurrentThreadTraceID());
}

@end
