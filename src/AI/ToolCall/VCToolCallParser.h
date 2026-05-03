/**
 * VCToolCallParser -- 双重解析 Tool Calls
 * 机制1: API 结构化字段 (首选)
 * 机制2: 文本 <tool_call>{json}</tool_call> 标记 (fallback)
 */

#import <Foundation/Foundation.h>
#import "../Models/VCProviderConfig.h"

typedef NS_ENUM(NSInteger, VCToolCallType) {
    VCToolCallUnknown = -1,
    VCToolCallModifyValue = 0,
    VCToolCallWriteMemoryBytes,
    VCToolCallPatchMethod,
    VCToolCallHookMethod,
    VCToolCallModifyHeader,
    VCToolCallSwizzleMethod,
    VCToolCallModifyView,
    VCToolCallInsertSubview,
    VCToolCallInvokeSelector,
    VCToolCallQueryRuntime,
    VCToolCallQueryProcess,
    VCToolCallQueryNetwork,
    VCToolCallQueryUI,
    VCToolCallQueryMemory,
    VCToolCallMemoryBrowser,
    VCToolCallMemoryScan,
    VCToolCallPointerChain,
    VCToolCallSignatureScan,
    VCToolCallAddressResolve,
    VCToolCallExportMermaid,
    VCToolCallTraceStart,
    VCToolCallTraceCheckpoint,
    VCToolCallTraceStop,
    VCToolCallTraceEvents,
    VCToolCallTraceExportMermaid,
    VCToolCallQueryArtifacts,
    VCToolCallUnityRuntime,
    VCToolCallOverlayCanvas,
    VCToolCallProject3D,
    VCToolCallOverlayTrack,
};

typedef NS_ENUM(NSInteger, VCToolCallVerificationStatus) {
    VCToolCallVerificationNone = 0,
    VCToolCallVerificationClaimed,
    VCToolCallVerificationVerified,
    VCToolCallVerificationFailed,
};

@interface VCToolCall : NSObject <NSCoding>

@property (nonatomic, copy) NSString *toolID;
@property (nonatomic, assign) VCToolCallType type;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSDictionary *params;
@property (nonatomic, copy) NSString *remark;
@property (nonatomic, assign) BOOL executed;
@property (nonatomic, assign) BOOL success;
@property (nonatomic, copy) NSString *resultMessage;
@property (nonatomic, assign) VCToolCallVerificationStatus verificationStatus;
@property (nonatomic, copy) NSString *verificationMessage;
@property (nonatomic, assign) NSTimeInterval lastExecutedAt;

- (NSDictionary *)toDictionary;
+ (instancetype)fromDictionary:(NSDictionary *)dict;

@end

@interface VCToolCallParser : NSObject

// 机制1: 从 API 结构化字段解析 (首选)
+ (NSArray<VCToolCall *> *)parseFromAPIResponse:(NSDictionary *)response
                                       protocol:(VCAPIProtocol)protocol;

// 机制2: 从文本中解析 <tool_call>{json}</tool_call> 标记 (fallback)
+ (NSArray<VCToolCall *> *)parseFromText:(NSString *)text;

// 统一入口
+ (NSArray<VCToolCall *> *)parseToolCalls:(NSDictionary *)response
                                     text:(NSString *)text
                                 protocol:(VCAPIProtocol)protocol;

// Re-normalize a tool call loaded from cache or built from partial provider data.
+ (void)normalizeToolCall:(VCToolCall *)toolCall;

@end
