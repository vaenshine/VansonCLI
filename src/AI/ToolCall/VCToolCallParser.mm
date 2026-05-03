/**
 * VCToolCallParser.mm -- 双重解析实现
 */

#import "VCToolCallParser.h"
#import "../../../VansonCLI.h"

static NSString *VCParserTrimmedString(id value) {
    if ([value isKindOfClass:[NSString class]]) {
        return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        return [[(NSNumber *)value stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    return @"";
}

static NSString *VCParserStringParam(NSDictionary *params, NSArray<NSString *> *keys) {
    if (![params isKindOfClass:[NSDictionary class]]) return @"";
    for (NSString *key in keys) {
        NSString *value = VCParserTrimmedString(params[key]);
        if (value.length > 0) return value;
    }
    return @"";
}

static BOOL VCParserHasAnyValue(NSDictionary *params, NSArray<NSString *> *keys) {
    if (![params isKindOfClass:[NSDictionary class]]) return NO;
    for (NSString *key in keys) {
        id value = params[key];
        if ([value isKindOfClass:[NSString class]]) {
            if (VCParserTrimmedString(value).length > 0) return YES;
        } else if ([value isKindOfClass:[NSArray class]]) {
            if ([(NSArray *)value count] > 0) return YES;
        } else if ([value isKindOfClass:[NSDictionary class]]) {
            if ([(NSDictionary *)value count] > 0) return YES;
        } else if (value != nil && value != [NSNull null]) {
            return YES;
        }
    }
    return NO;
}

#pragma mark - VCToolCall

@implementation VCToolCall

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:_toolID forKey:@"toolID"];
    [coder encodeInteger:_type forKey:@"type"];
    [coder encodeObject:_title forKey:@"title"];
    [coder encodeObject:_params forKey:@"params"];
    [coder encodeObject:_remark forKey:@"remark"];
    [coder encodeBool:_executed forKey:@"executed"];
    [coder encodeBool:_success forKey:@"success"];
    [coder encodeObject:_resultMessage forKey:@"resultMessage"];
    [coder encodeInteger:_verificationStatus forKey:@"verificationStatus"];
    [coder encodeObject:_verificationMessage forKey:@"verificationMessage"];
    [coder encodeDouble:_lastExecutedAt forKey:@"lastExecutedAt"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super init]) {
        _toolID = [coder decodeObjectForKey:@"toolID"];
        _type = [coder containsValueForKey:@"type"] ? (VCToolCallType)[coder decodeIntegerForKey:@"type"] : VCToolCallUnknown;
        _title = [coder decodeObjectForKey:@"title"];
        _params = [coder decodeObjectForKey:@"params"];
        _remark = [coder decodeObjectForKey:@"remark"];
        _executed = [coder decodeBoolForKey:@"executed"];
        _success = [coder decodeBoolForKey:@"success"];
        _resultMessage = [coder decodeObjectForKey:@"resultMessage"];
        _verificationStatus = (VCToolCallVerificationStatus)[coder decodeIntegerForKey:@"verificationStatus"];
        _verificationMessage = [coder decodeObjectForKey:@"verificationMessage"];
        _lastExecutedAt = [coder decodeDoubleForKey:@"lastExecutedAt"];
        [VCToolCallParser normalizeToolCall:self];
    }
    return self;
}

- (NSDictionary *)toDictionary {
    return @{
        @"toolID": _toolID ?: @"",
        @"type": @(_type),
        @"title": _title ?: @"",
        @"params": _params ?: @{},
        @"remark": _remark ?: @"",
        @"executed": @(_executed),
        @"success": @(_success),
        @"resultMessage": _resultMessage ?: @"",
        @"verificationStatus": @(_verificationStatus),
        @"verificationMessage": _verificationMessage ?: @"",
        @"lastExecutedAt": @(_lastExecutedAt),
    };
}

+ (instancetype)fromDictionary:(NSDictionary *)dict {
    if (!dict) return nil;
    VCToolCall *tc = [[VCToolCall alloc] init];
    tc.toolID = dict[@"toolID"] ?: [[NSUUID UUID] UUIDString];
    tc.type = dict[@"type"] ? (VCToolCallType)[dict[@"type"] integerValue] : VCToolCallUnknown;
    tc.title = dict[@"title"] ?: @"";
    tc.params = dict[@"params"] ?: @{};
    tc.remark = dict[@"remark"] ?: @"";
    tc.executed = [dict[@"executed"] boolValue];
    tc.success = [dict[@"success"] boolValue];
    tc.resultMessage = dict[@"resultMessage"] ?: @"";
    tc.verificationStatus = (VCToolCallVerificationStatus)[dict[@"verificationStatus"] integerValue];
    tc.verificationMessage = dict[@"verificationMessage"] ?: @"";
    tc.lastExecutedAt = [dict[@"lastExecutedAt"] doubleValue];
    [VCToolCallParser normalizeToolCall:tc];
    return tc;
}

@end

#pragma mark - VCToolCallParser

@implementation VCToolCallParser

+ (NSDictionary *)_normalizedParamsFromJSONObject:(NSDictionary *)json fallbackType:(NSString *)fallbackType {
    if (![json isKindOfClass:[NSDictionary class]]) return @{};
    NSDictionary *params = [json[@"params"] isKindOfClass:[NSDictionary class]] ? json[@"params"] : nil;
    if (params) return params;

    NSMutableDictionary *flattened = [json mutableCopy];
    [flattened removeObjectForKey:@"type"];
    [flattened removeObjectForKey:@"title"];
    [flattened removeObjectForKey:@"remark"];
    [flattened removeObjectForKey:@"name"];
    if (fallbackType.length > 0 && !flattened[@"toolType"]) {
        flattened[@"toolType"] = fallbackType;
    }
    return [flattened copy];
}

+ (NSString *)_canonicalNameForType:(VCToolCallType)type {
    switch (type) {
        case VCToolCallModifyValue: return @"modify_value";
        case VCToolCallWriteMemoryBytes: return @"write_memory_bytes";
        case VCToolCallPatchMethod: return @"patch_method";
        case VCToolCallHookMethod: return @"hook_method";
        case VCToolCallModifyHeader: return @"modify_header";
        case VCToolCallSwizzleMethod: return @"swizzle_method";
        case VCToolCallModifyView: return @"modify_view";
        case VCToolCallInsertSubview: return @"insert_subview";
        case VCToolCallInvokeSelector: return @"invoke_selector";
        case VCToolCallQueryRuntime: return @"query_runtime";
        case VCToolCallQueryProcess: return @"query_process";
        case VCToolCallQueryNetwork: return @"query_network";
        case VCToolCallQueryUI: return @"query_ui";
        case VCToolCallQueryMemory: return @"query_memory";
        case VCToolCallMemoryBrowser: return @"memory_browser";
        case VCToolCallMemoryScan: return @"memory_scan";
        case VCToolCallPointerChain: return @"pointer_chain";
        case VCToolCallSignatureScan: return @"signature_scan";
        case VCToolCallAddressResolve: return @"address_resolve";
        case VCToolCallExportMermaid: return @"export_mermaid";
        case VCToolCallTraceStart: return @"trace_start";
        case VCToolCallTraceCheckpoint: return @"trace_checkpoint";
        case VCToolCallTraceStop: return @"trace_stop";
        case VCToolCallTraceEvents: return @"trace_events";
        case VCToolCallTraceExportMermaid: return @"trace_export_mermaid";
        case VCToolCallQueryArtifacts: return @"query_artifacts";
        case VCToolCallUnityRuntime: return @"unity_runtime";
        case VCToolCallOverlayCanvas: return @"overlay_canvas";
        case VCToolCallProject3D: return @"project_3d";
        case VCToolCallOverlayTrack: return @"overlay_track";
        case VCToolCallUnknown:
        default:
            return @"";
    }
}

+ (VCToolCallType)_typeFromQueryType:(NSString *)queryType params:(NSDictionary *)params {
    NSString *lower = VCParserTrimmedString(queryType).lowercaseString;
    if (lower.length == 0) return VCToolCallUnknown;

    NSSet<NSString *> *runtimeQueries = [NSSet setWithArray:@[
        @"class_search", @"class_detail", @"method_detail", @"strings_search",
        @"instances_search", @"instance_detail", @"dump_object", @"read_ivar",
        @"object_graph"
    ]];
    NSSet<NSString *> *processQueries = [NSSet setWithArray:@[
        @"basic_info", @"memory_regions", @"entitlements", @"environment"
    ]];
    NSSet<NSString *> *networkQueries = [NSSet setWithArray:@[
        @"list", @"detail", @"curl", @"har", @"ws_list", @"ws_detail"
    ]];
    NSSet<NSString *> *uiQueries = [NSSet setWithArray:@[
        @"hierarchy", @"selected_view", @"view_detail", @"responder_chain",
        @"constraints", @"accessibility", @"interactions", @"screenshot",
        @"alerts", @"alert"
    ]];
    NSSet<NSString *> *memoryQueries = [NSSet setWithArray:@[
        @"address_context", @"read_value", @"read_struct", @"matrix_scan",
        @"camera_candidates", @"matrix_validate", @"pointer_follow", @"hexdump", @"snapshot",
        @"snapshot_list", @"snapshot_detail", @"diff_snapshot"
    ]];
    NSSet<NSString *> *artifactQueries = [NSSet setWithArray:@[
        @"overview", @"trace_sessions", @"trace_session_detail", @"diagram_list",
        @"diagram_detail", @"memory_snapshot_list", @"memory_snapshot_detail",
        @"track_list", @"track_detail"
    ]];
    NSSet<NSString *> *unityQueries = [NSSet setWithArray:@[
        @"detect", @"symbols", @"icalls", @"drawing_support", @"camera_main",
        @"find_by_name", @"find_by_tag", @"get_component", @"list_renderers",
        @"transform_position", @"renderer_bounds", @"project_renderer_bounds",
        @"world_to_screen", @"notes"
    ]];

    if ([runtimeQueries containsObject:lower]) return VCToolCallQueryRuntime;
    if ([processQueries containsObject:lower]) return VCToolCallQueryProcess;
    if ([networkQueries containsObject:lower]) return VCToolCallQueryNetwork;
    if ([uiQueries containsObject:lower]) return VCToolCallQueryUI;
    if ([memoryQueries containsObject:lower]) return VCToolCallQueryMemory;
    if ([artifactQueries containsObject:lower]) return VCToolCallQueryArtifacts;
    if ([unityQueries containsObject:lower]) return VCToolCallUnityRuntime;

    if ([lower isEqualToString:@"modules"]) {
        BOOL looksLikeUnity = VCParserHasAnyValue(params, @[
            @"preferredModule", @"symbols", @"icallNames", @"includeDefaultSymbols",
            @"includeDefaultICalls", @"componentName", @"cameraAddress",
            @"transformAddress", @"rendererAddress", @"componentAddress",
            @"gameObjectAddress", @"worldX", @"worldY", @"worldZ"
        ]);
        return looksLikeUnity ? VCToolCallUnityRuntime : VCToolCallQueryProcess;
    }

    return VCToolCallUnknown;
}

+ (VCToolCallType)_typeFromAction:(NSString *)action params:(NSDictionary *)params {
    NSString *lower = VCParserTrimmedString(action).lowercaseString;
    if (lower.length == 0) return VCToolCallUnknown;

    NSSet<NSString *> *canvasActions = [NSSet setWithArray:@[
        @"line", @"box", @"circle", @"text", @"polyline", @"corner_box",
        @"health_bar", @"offscreen_arrow", @"skeleton", @"clear", @"show", @"hide"
    ]];
    NSSet<NSString *> *browserActions = [NSSet setWithArray:@[
        @"goto", @"page", @"next", @"prev", @"peek"
    ]];
    NSSet<NSString *> *scanActions = [NSSet setWithArray:@[
        @"start", @"refine", @"results"
    ]];
    NSSet<NSString *> *pointerActions = [NSSet setWithArray:@[
        @"resolve", @"read", @"find_refs"
    ]];
    NSSet<NSString *> *addressActions = [NSSet setWithArray:@[
        @"module_base", @"module_size", @"rva_to_runtime", @"runtime_to_rva"
    ]];

    if ([canvasActions containsObject:lower]) return VCToolCallOverlayCanvas;
    if ([browserActions containsObject:lower] ||
        ([lower isEqualToString:@"status"] && VCParserHasAnyValue(params, @[@"pageSize", @"length"]))) {
        return VCToolCallMemoryBrowser;
    }
    if (([scanActions containsObject:lower] || [lower isEqualToString:@"status"] || [lower isEqualToString:@"clear"]) &&
        VCParserHasAnyValue(params, @[@"scanMode", @"filterMode", @"dataType", @"resultLimit", @"refreshValues"])) {
        return VCToolCallMemoryScan;
    }
    if ([pointerActions containsObject:lower] &&
        VCParserHasAnyValue(params, @[@"offsets", @"baseAddress", @"baseOffset", @"moduleName"])) {
        return VCToolCallPointerChain;
    }
    if ([lower isEqualToString:@"scan"] && VCParserHasAnyValue(params, @[@"signature"])) {
        return VCToolCallSignatureScan;
    }
    if ([addressActions containsObject:lower]) return VCToolCallAddressResolve;
    if (([@[@"start", @"stop", @"save", @"restore", @"list", @"status", @"clear"] containsObject:lower]) &&
        VCParserHasAnyValue(params, @[
            @"trackMode", @"track_mode", @"trackerID", @"tracker_id", @"trackerPath",
            @"tracker_path", @"pointAddress", @"rectAddress", @"worldAddress",
            @"matrixAddress", @"transformAddress", @"rendererAddress"
        ])) {
        return VCToolCallOverlayTrack;
    }
    if (([lower isEqualToString:@"modify_header"] || [lower isEqualToString:@"modify_body"]) ||
        VCParserHasAnyValue(params, @[@"urlPattern", @"url_pattern", @"headers", @"body"])) {
        return VCToolCallModifyHeader;
    }

    return VCToolCallUnknown;
}

+ (VCToolCallType)_inferTypeFromParams:(NSDictionary *)params fallbackName:(NSString *)fallbackName {
    if (![params isKindOfClass:[NSDictionary class]]) return VCToolCallUnknown;

    VCToolCallType explicitType = [self _typeFromName:VCParserStringParam(params, @[@"toolType", @"tool_type", @"toolName", @"tool_name"])];
    if (explicitType != VCToolCallUnknown) return explicitType;

    explicitType = [self _typeFromName:fallbackName];
    if (explicitType != VCToolCallUnknown) return explicitType;

    NSString *queryType = VCParserStringParam(params, @[@"queryType", @"query_type"]);
    if (queryType.length > 0) {
        VCToolCallType queryToolType = [self _typeFromQueryType:queryType params:params];
        if (queryToolType != VCToolCallUnknown) return queryToolType;
    }

    NSString *action = VCParserStringParam(params, @[@"action"]);
    if (action.length > 0) {
        VCToolCallType actionType = [self _typeFromAction:action params:params];
        if (actionType != VCToolCallUnknown) return actionType;
    }

    if (VCParserHasAnyValue(params, @[@"sessionName", @"captureNetwork", @"captureUI", @"methodTargets", @"checkpointTriggers"])) {
        return VCToolCallTraceStart;
    }
    if (VCParserHasAnyValue(params, @[@"memoryWatches"]) &&
        VCParserHasAnyValue(params, @[@"label", @"resetBaseline", @"sessionID"])) {
        return VCToolCallTraceCheckpoint;
    }
    if (VCParserHasAnyValue(params, @[@"kindNames"]) && VCParserHasAnyValue(params, @[@"sessionID", @"limit"])) {
        return VCToolCallTraceEvents;
    }
    if (VCParserHasAnyValue(params, @[@"diagramType", @"content"])) return VCToolCallExportMermaid;
    if (VCParserHasAnyValue(params, @[@"matrixAddress", @"matrixElements", @"worldAddress"])) return VCToolCallProject3D;
    if (VCParserHasAnyValue(params, @[@"otherClassName", @"otherSelector"])) return VCToolCallSwizzleMethod;
    if (VCParserHasAnyValue(params, @[@"patchType", @"className", @"selector"])) return VCToolCallPatchMethod;
    if (VCParserHasAnyValue(params, @[@"hookType", @"className", @"selector"])) return VCToolCallHookMethod;
    if (VCParserHasAnyValue(params, @[@"hexData", @"hex_data", @"bytes"]) && VCParserHasAnyValue(params, @[@"address", @"addr"])) {
        return VCToolCallWriteMemoryBytes;
    }
    if (VCParserHasAnyValue(params, @[@"modifiedValue", @"modified_value"]) &&
        VCParserHasAnyValue(params, @[
            @"address", @"addr", @"source", @"targetSource", @"target_source",
            @"matchValue", @"match_value", @"currentValue", @"originalValue",
            @"useActiveScanResults", @"use_active_scan_results", @"allScanCandidates"
        ])) {
        return VCToolCallModifyValue;
    }
    if (VCParserHasAnyValue(params, @[@"property", @"key", @"attribute"]) &&
        VCParserHasAnyValue(params, @[@"value", @"newValue", @"new_value"])) {
        return VCToolCallModifyView;
    }
    if (VCParserHasAnyValue(params, @[@"parentAddress", @"parent_address", @"subviewType", @"viewType"])) {
        return VCToolCallInsertSubview;
    }
    if (VCParserHasAnyValue(params, @[@"selector", @"sel"]) &&
        VCParserHasAnyValue(params, @[@"address", @"targetAddress", @"target_address", @"className"])) {
        return VCToolCallInvokeSelector;
    }

    return VCToolCallUnknown;
}

+ (BOOL)_isMutationType:(VCToolCallType)type {
    switch (type) {
        case VCToolCallModifyValue:
        case VCToolCallWriteMemoryBytes:
        case VCToolCallPatchMethod:
        case VCToolCallHookMethod:
        case VCToolCallModifyHeader:
        case VCToolCallSwizzleMethod:
        case VCToolCallModifyView:
        case VCToolCallInsertSubview:
        case VCToolCallInvokeSelector:
        case VCToolCallOverlayCanvas:
        case VCToolCallOverlayTrack:
            return YES;
        default:
            return NO;
    }
}

+ (VCToolCallType)_resolvedTypeForName:(NSString *)name params:(NSDictionary *)params {
    VCToolCallType directType = [self _typeFromName:name];
    VCToolCallType inferredFromParams = [self _inferTypeFromParams:params fallbackName:nil];

    if (directType == VCToolCallUnknown) {
        if (inferredFromParams != VCToolCallUnknown) return inferredFromParams;
        return [self _inferTypeFromParams:params fallbackName:name];
    }

    if (inferredFromParams != VCToolCallUnknown && inferredFromParams != directType) {
        BOOL hasQueryType = VCParserStringParam(params, @[@"queryType", @"query_type"]).length > 0;
        BOOL hasAction = VCParserStringParam(params, @[@"action"]).length > 0;
        BOOL hasModifyAddress = VCParserHasAnyValue(params, @[
            @"address", @"addr", @"source", @"targetSource", @"target_source",
            @"matchValue", @"match_value", @"currentValue", @"originalValue",
            @"useActiveScanResults", @"use_active_scan_results", @"allScanCandidates"
        ]);
        BOOL hasModifiedValue = VCParserHasAnyValue(params, @[@"modifiedValue", @"modified_value", @"value", @"new_value"]);
        BOOL directModifyLooksIncomplete = (directType == VCToolCallModifyValue) && (!hasModifyAddress || !hasModifiedValue);

        if ((hasQueryType || hasAction) && [self _isMutationType:directType]) {
            return inferredFromParams;
        }
        if (directModifyLooksIncomplete) {
            return inferredFromParams;
        }
    }

    return directType;
}

+ (void)normalizeToolCall:(VCToolCall *)toolCall {
    if (![toolCall isKindOfClass:[VCToolCall class]]) return;

    NSDictionary *params = [toolCall.params isKindOfClass:[NSDictionary class]] ? toolCall.params : @{};
    toolCall.params = params;

    NSString *currentTitle = VCParserTrimmedString(toolCall.title);
    VCToolCallType inferredType = [self _resolvedTypeForName:currentTitle params:params];

    BOOL hasQueryType = VCParserStringParam(params, @[@"queryType", @"query_type"]).length > 0;
    BOOL hasAction = VCParserStringParam(params, @[@"action"]).length > 0;
    BOOL hasModifyAddress = VCParserHasAnyValue(params, @[
        @"address", @"addr", @"source", @"targetSource", @"target_source",
        @"matchValue", @"match_value", @"currentValue", @"originalValue",
        @"useActiveScanResults", @"use_active_scan_results", @"allScanCandidates"
    ]);
    BOOL hasModifiedValue = VCParserHasAnyValue(params, @[@"modifiedValue", @"modified_value", @"value", @"new_value"]);
    BOOL modifyLooksIncomplete = (toolCall.type == VCToolCallModifyValue) && (!hasModifyAddress || !hasModifiedValue);

    if (inferredType != VCToolCallUnknown) {
        if (toolCall.type == VCToolCallUnknown) {
            toolCall.type = inferredType;
        } else if (toolCall.type != inferredType && (hasQueryType || hasAction || modifyLooksIncomplete)) {
            toolCall.type = inferredType;
        }
    }

    NSString *canonicalTitle = [self _canonicalNameForType:toolCall.type];
    NSString *currentLower = currentTitle.lowercaseString ?: @"";
    BOOL titleLooksPlaceholder = currentTitle.length == 0 ||
                                 [currentLower isEqualToString:@"unknown"] ||
                                 ([currentLower isEqualToString:@"modify_value"] && toolCall.type != VCToolCallModifyValue);
    if (titleLooksPlaceholder && canonicalTitle.length > 0) {
        toolCall.title = canonicalTitle;
    }
}

+ (NSArray<VCToolCall *> *)parseToolCalls:(NSDictionary *)response
                                     text:(NSString *)text
                                 protocol:(VCAPIProtocol)protocol {
    // Try API structured fields first
    NSArray<VCToolCall *> *apiCalls = [self parseFromAPIResponse:response protocol:protocol];
    if (apiCalls.count) return apiCalls;

    // Fallback to text parsing
    return [self parseFromText:text];
}

#pragma mark - Mechanism 1: API Structured Fields

+ (NSArray<VCToolCall *> *)parseFromAPIResponse:(NSDictionary *)response
                                       protocol:(VCAPIProtocol)protocol {
    if (!response) return @[];

    switch (protocol) {
        case VCAPIProtocolOpenAI:
        case VCAPIProtocolOpenAIResponses:
            return [self _parseOpenAIToolCalls:response];
        case VCAPIProtocolAnthropic:
            return [self _parseAnthropicToolCalls:response];
        case VCAPIProtocolGemini:
            return [self _parseGeminiToolCalls:response];
    }
    return @[];
}

+ (NSArray<VCToolCall *> *)_parseOpenAIToolCalls:(NSDictionary *)response {
    // response["choices"][0]["message"]["tool_calls"]
    // or from streaming accumulator: response["tool_calls"]
    NSArray *toolCalls = response[@"tool_calls"];
    if (!toolCalls) {
        NSArray *choices = response[@"choices"];
        NSDictionary *message = [choices.firstObject objectForKey:@"message"];
        toolCalls = message[@"tool_calls"];
    }
    if (!toolCalls.count) return @[];

    NSMutableArray<VCToolCall *> *results = [NSMutableArray new];
    for (NSDictionary *tc in toolCalls) {
        VCToolCall *call = [[VCToolCall alloc] init];
        call.toolID = tc[@"id"] ?: [[NSUUID UUID] UUIDString];

        NSString *name = tc[@"name"] ?: tc[@"function"][@"name"];

        // Parse arguments
        id argsValue = tc[@"arguments"] ?: tc[@"input"] ?: tc[@"function"][@"arguments"];
        if ([argsValue isKindOfClass:[NSString class]]) {
            NSData *d = [(NSString *)argsValue dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
            call.params = [self _normalizedParamsFromJSONObject:json fallbackType:name];
        } else if ([argsValue isKindOfClass:[NSDictionary class]]) {
            call.params = [self _normalizedParamsFromJSONObject:(NSDictionary *)argsValue fallbackType:name];
        }
        if (!call.params) call.params = @{};

        call.type = [self _resolvedTypeForName:name params:call.params];
        NSString *resolvedTitle = name.length > 0 ? name : [self _canonicalNameForType:call.type];
        call.title = resolvedTitle.length > 0 ? resolvedTitle : @"unknown";
        [self normalizeToolCall:call];

        [results addObject:call];
    }
    return results;
}

+ (NSArray<VCToolCall *> *)_parseAnthropicToolCalls:(NSDictionary *)response {
    // response["content"] -> filter type="tool_use"
    NSArray *content = response[@"content"];
    if (!content) content = response[@"content_blocks"];
    if (!content.count) return @[];

    NSMutableArray<VCToolCall *> *results = [NSMutableArray new];
    for (NSDictionary *block in content) {
        if (![block[@"type"] isEqualToString:@"tool_use"] &&
            !block[@"name"]) continue; // Skip non-tool blocks

        VCToolCall *call = [[VCToolCall alloc] init];
        call.toolID = block[@"id"] ?: [[NSUUID UUID] UUIDString];
        call.params = block[@"input"] ?: @{};
        call.type = [self _resolvedTypeForName:block[@"name"] params:call.params];
        NSString *resolvedTitle = VCParserTrimmedString(block[@"name"]);
        if (resolvedTitle.length == 0) resolvedTitle = [self _canonicalNameForType:call.type];
        call.title = resolvedTitle.length > 0 ? resolvedTitle : @"unknown";
        [self normalizeToolCall:call];
        [results addObject:call];
    }
    return results;
}

+ (NSArray<VCToolCall *> *)_parseGeminiToolCalls:(NSDictionary *)response {
    // response["candidates"][0]["content"]["parts"] -> filter functionCall
    NSArray *candidates = response[@"candidates"];
    NSDictionary *content = [candidates.firstObject objectForKey:@"content"];
    NSArray *parts = content[@"parts"];
    if (!parts.count) return @[];

    NSMutableArray<VCToolCall *> *results = [NSMutableArray new];
    for (NSDictionary *part in parts) {
        NSDictionary *fc = part[@"functionCall"];
        if (!fc) continue;

        VCToolCall *call = [[VCToolCall alloc] init];
        call.toolID = [[NSUUID UUID] UUIDString];
        call.params = fc[@"args"] ?: @{};
        call.type = [self _resolvedTypeForName:fc[@"name"] params:call.params];
        NSString *resolvedTitle = VCParserTrimmedString(fc[@"name"]);
        if (resolvedTitle.length == 0) resolvedTitle = [self _canonicalNameForType:call.type];
        call.title = resolvedTitle.length > 0 ? resolvedTitle : @"unknown";
        [self normalizeToolCall:call];
        [results addObject:call];
    }
    return results;
}

#pragma mark - Mechanism 2: Text Parsing

+ (NSArray<VCToolCall *> *)parseFromText:(NSString *)text {
    if (!text.length) return @[];

    NSMutableArray<VCToolCall *> *results = [NSMutableArray new];

    // Regex: <tool_call type="...">...</tool_call> (dotall)
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression
        regularExpressionWithPattern:@"<tool_call(?:\\s+type=\"([^\"]+)\")?>(.*?)</tool_call>"
        options:NSRegularExpressionDotMatchesLineSeparators
        error:&error];
    if (error) return @[];

    NSArray<NSTextCheckingResult *> *matches = [regex matchesInString:text
        options:0 range:NSMakeRange(0, text.length)];

    for (NSTextCheckingResult *match in matches) {
        if (match.numberOfRanges < 3) continue;
        NSString *attributeType = nil;
        NSRange typeRange = [match rangeAtIndex:1];
        if (typeRange.location != NSNotFound && typeRange.length > 0) {
            attributeType = [text substringWithRange:typeRange];
        }

        NSString *jsonStr = [text substringWithRange:[match rangeAtIndex:2]];
        jsonStr = [jsonStr stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

        NSData *jsonData = [jsonStr dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
        if (![json isKindOfClass:[NSDictionary class]]) continue;

        NSString *toolType = [json[@"type"] isKindOfClass:[NSString class]] ? json[@"type"] : attributeType;

        VCToolCall *call = [[VCToolCall alloc] init];
        call.toolID = [[NSUUID UUID] UUIDString];
        call.params = [self _normalizedParamsFromJSONObject:json fallbackType:toolType];
        call.type = [self _resolvedTypeForName:toolType params:call.params];
        NSString *resolvedTitle = [json[@"title"] isKindOfClass:[NSString class]] ? json[@"title"] : nil;
        if (VCParserTrimmedString(resolvedTitle).length == 0) resolvedTitle = toolType;
        if (VCParserTrimmedString(resolvedTitle).length == 0) resolvedTitle = [self _canonicalNameForType:call.type];
        call.title = VCParserTrimmedString(resolvedTitle).length > 0 ? resolvedTitle : @"unknown";
        call.remark = json[@"remark"] ?: @"";
        [self normalizeToolCall:call];
        [results addObject:call];
    }

    return results;
}

#pragma mark - Helpers

+ (VCToolCallType)_typeFromName:(NSString *)name {
    NSString *lower = VCParserTrimmedString(name).lowercaseString;
    if (lower.length == 0) return VCToolCallUnknown;
    if ([lower containsString:@"trace_start"]) return VCToolCallTraceStart;
    if ([lower containsString:@"trace_checkpoint"]) return VCToolCallTraceCheckpoint;
    if ([lower containsString:@"trace_stop"]) return VCToolCallTraceStop;
    if ([lower containsString:@"trace_events"]) return VCToolCallTraceEvents;
    if ([lower containsString:@"trace_export_mermaid"]) return VCToolCallTraceExportMermaid;
    if ([lower containsString:@"query_artifacts"]) return VCToolCallQueryArtifacts;
    if ([lower containsString:@"unity_runtime"]) return VCToolCallUnityRuntime;
    if ([lower containsString:@"overlay_canvas"]) return VCToolCallOverlayCanvas;
    if ([lower containsString:@"project_3d"] || [lower containsString:@"project3d"]) return VCToolCallProject3D;
    if ([lower containsString:@"overlay_track"] || [lower containsString:@"track_overlay"]) return VCToolCallOverlayTrack;
    if ([lower containsString:@"query_runtime"]) return VCToolCallQueryRuntime;
    if ([lower containsString:@"query_process"]) return VCToolCallQueryProcess;
    if ([lower containsString:@"query_network"]) return VCToolCallQueryNetwork;
    if ([lower containsString:@"query_ui"]) return VCToolCallQueryUI;
    if ([lower containsString:@"query_memory"]) return VCToolCallQueryMemory;
    if ([lower containsString:@"memory_browser"]) return VCToolCallMemoryBrowser;
    if ([lower containsString:@"memory_scan"]) return VCToolCallMemoryScan;
    if ([lower containsString:@"pointer_chain"]) return VCToolCallPointerChain;
    if ([lower containsString:@"signature_scan"]) return VCToolCallSignatureScan;
    if ([lower containsString:@"address_resolve"]) return VCToolCallAddressResolve;
    if ([lower containsString:@"export_mermaid"]) return VCToolCallExportMermaid;
    if ([lower containsString:@"insert_subview"] || [lower containsString:@"insert_view"] || [lower containsString:@"add_label"]) return VCToolCallInsertSubview;
    if ([lower containsString:@"invoke_selector"] || [lower containsString:@"call_selector"] || [lower containsString:@"invoke_method"]) return VCToolCallInvokeSelector;
    if ([lower containsString:@"write_memory_bytes"] || [lower containsString:@"write_bytes"]) return VCToolCallWriteMemoryBytes;
    if ([lower containsString:@"modify_value"]) return VCToolCallModifyValue;
    if ([lower containsString:@"patch_method"]) return VCToolCallPatchMethod;
    if ([lower containsString:@"hook"]) return VCToolCallHookMethod;
    if ([lower containsString:@"modify_header"]) return VCToolCallModifyHeader;
    if ([lower containsString:@"swizzle"]) return VCToolCallSwizzleMethod;
    if ([lower containsString:@"modify_view"]) return VCToolCallModifyView;
    return VCToolCallUnknown;
}

@end
