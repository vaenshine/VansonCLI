/**
 * VCToolSchemaRegistry -- provider-agnostic tool schema builder
 */

#import "VCToolSchemaRegistry.h"

static NSDictionary *VCStringToolProperty(NSString *description) {
    return @{
        @"type": @"string",
        @"description": description ?: @"",
    };
}

static NSDictionary *VCBooleanToolProperty(NSString *description) {
    return @{
        @"type": @"boolean",
        @"description": description ?: @"",
    };
}

static NSDictionary *VCNumberToolProperty(NSString *description) {
    return @{
        @"type": @"number",
        @"description": description ?: @"",
    };
}

static NSDictionary *VCToolSchema(NSString *name,
                                  NSString *toolDescription,
                                  NSDictionary<NSString *, NSDictionary *> *properties,
                                  NSArray<NSString *> *requiredKeys) {
    return @{
        @"name": name ?: @"tool",
        @"description": toolDescription ?: @"",
        @"parameters": @{
            @"type": @"object",
            @"properties": properties ?: @{},
            @"required": requiredKeys ?: @[],
            @"additionalProperties": @YES,
        }
    };
}

@implementation VCToolSchemaRegistry

+ (NSArray<NSDictionary *> *)toolSchemasForRuntimeCapabilities:(NSDictionary *)capabilities {
    BOOL canWriteMemory = [capabilities[@"canWriteMemory"] boolValue];
    BOOL canModifyRuntime = [capabilities[@"canModifyRuntime"] boolValue];
    BOOL canInstallHooks = [capabilities[@"canInstallHooks"] boolValue];

    NSMutableArray<NSDictionary *> *schemas = [NSMutableArray new];

    [schemas addObject:VCToolSchema(
        @"query_runtime",
        @"Read Objective-C runtime metadata such as classes, methods, strings, live instances, object ivars, and conservative object graphs.",
        @{
            @"queryType": VCStringToolProperty(@"Runtime query mode: class_search, class_detail, method_detail, strings_search, instances_search, instance_detail, dump_object, read_ivar, or object_graph."),
            @"filter": VCStringToolProperty(@"Optional class/member/string filter."),
            @"pattern": VCStringToolProperty(@"Optional string search pattern."),
            @"className": VCStringToolProperty(@"Target class name for class_detail or instances_search."),
            @"selector": VCStringToolProperty(@"Target selector for method_detail."),
            @"ivarName": VCStringToolProperty(@"Target ivar name for read_ivar."),
            @"module": VCStringToolProperty(@"Optional module name filter."),
            @"memberFilter": VCStringToolProperty(@"Optional member filter when loading class detail."),
            @"instanceAddress": VCStringToolProperty(@"Optional live instance address for instance_detail, read_ivar, or object_graph."),
            @"isClassMethod": VCBooleanToolProperty(@"Whether method_detail targets a class method."),
            @"maxDepth": VCNumberToolProperty(@"Optional maximum depth for object_graph."),
            @"collectionLimit": VCNumberToolProperty(@"Optional maximum collection members to expand per container in object_graph."),
            @"offset": VCNumberToolProperty(@"Optional pagination offset."),
            @"limit": VCNumberToolProperty(@"Optional result limit."),
        },
        @[@"queryType"]
    )];

    [schemas addObject:VCToolSchema(
        @"query_process",
        @"Read process metadata such as bundle info, loaded modules, memory regions, entitlements, and environment variables.",
        @{
            @"queryType": VCStringToolProperty(@"Process query mode: basic_info, modules, memory_regions, entitlements, or environment."),
            @"filter": VCStringToolProperty(@"Optional module or environment filter."),
            @"category": VCStringToolProperty(@"Optional module category filter such as app, framework, system, or thirdparty."),
            @"protection": VCStringToolProperty(@"Optional memory protection filter such as r-x or rw-."),
            @"address": VCStringToolProperty(@"Optional address to locate inside the memory map."),
            @"offset": VCNumberToolProperty(@"Optional pagination offset."),
            @"limit": VCNumberToolProperty(@"Optional result limit."),
        },
        @[@"queryType"]
    )];

    [schemas addObject:VCToolSchema(
        @"unity_runtime",
        @"Detect whether the host is a Unity app, identify IL2CPP or Mono markers, list Unity-related modules, resolve common exported symbols or IL2CPP icalls, and return grounded guidance for Unity object analysis or drawing preparation.",
        @{
            @"queryType": VCStringToolProperty(@"Unity query mode: detect, modules, symbols, icalls, drawing_support, camera_main, find_by_name, find_by_tag, get_component, list_renderers, transform_position, renderer_bounds, project_renderer_bounds, world_to_screen, or notes."),
            @"preferredModule": VCStringToolProperty(@"Optional Unity-related module name to prioritize when resolving symbols."),
            @"symbols": @{
                @"type": @"array",
                @"description": @"Optional explicit exported symbol names to resolve. When omitted, default Unity, IL2CPP, or Mono entry points are used.",
                @"items": @{@"type": @"string"}
            },
            @"includeDefaultSymbols": VCBooleanToolProperty(@"Whether default Unity runtime symbols should also be resolved."),
            @"icallNames": @{
                @"type": @"array",
                @"description": @"Optional explicit IL2CPP icall names to resolve. When omitted, a default drawing-oriented set is used.",
                @"items": @{@"type": @"string"}
            },
            @"includeDefaultICalls": VCBooleanToolProperty(@"Whether default drawing-oriented Unity icalls should also be resolved."),
            @"name": VCStringToolProperty(@"For find_by_name or list_renderers, a concrete Unity GameObject name."),
            @"tag": VCStringToolProperty(@"For find_by_tag or list_renderers, a concrete Unity tag."),
            @"limit": VCNumberToolProperty(@"Optional maximum number of Unity objects or renderer candidates to return."),
            @"componentName": VCStringToolProperty(@"For get_component, the Unity component type name such as Renderer, MeshRenderer, SkinnedMeshRenderer, Transform, or Collider."),
            @"cameraAddress": VCStringToolProperty(@"Optional Unity camera address to use for world_to_screen instead of Camera.main."),
            @"transformAddress": VCStringToolProperty(@"Optional Unity Transform address for transform_position or world_to_screen."),
            @"rendererAddress": VCStringToolProperty(@"Optional Unity Renderer address for renderer_bounds or project_renderer_bounds."),
            @"componentAddress": VCStringToolProperty(@"Optional Unity Component address. The bridge resolves its Transform first."),
            @"gameObjectAddress": VCStringToolProperty(@"Optional Unity GameObject address. The bridge resolves its Transform first."),
            @"worldX": VCNumberToolProperty(@"World-space X coordinate for world_to_screen."),
            @"worldY": VCNumberToolProperty(@"World-space Y coordinate for world_to_screen."),
            @"worldZ": VCNumberToolProperty(@"World-space Z coordinate for world_to_screen.")
        },
        @[@"queryType"]
    )];

    [schemas addObject:VCToolSchema(
        @"query_network",
        @"Read captured network traffic, WebSocket frames, export HAR, request detail, or export a request as cURL.",
        @{
            @"queryType": VCStringToolProperty(@"Network query mode: list, detail, curl, har, ws_list, or ws_detail."),
            @"filter": VCStringToolProperty(@"Optional URL or method filter."),
            @"requestID": VCStringToolProperty(@"Request identifier for detail or curl."),
            @"frameID": VCStringToolProperty(@"WebSocket frame identifier for ws_detail."),
            @"connectionID": VCStringToolProperty(@"Optional WebSocket connection identifier for ws_list."),
            @"includeBodies": VCBooleanToolProperty(@"Whether to include request and response bodies for detail."),
            @"limit": VCNumberToolProperty(@"Optional result limit for list."),
        },
        @[@"queryType"]
    )];

    [schemas addObject:VCToolSchema(
        @"query_ui",
        @"Read the live UIKit hierarchy, selected view detail, visible alerts, responder chain, constraints, accessibility info, interaction bindings, or save a screenshot.",
        @{
            @"queryType": VCStringToolProperty(@"UI query mode: hierarchy, selected_view, view_detail, alerts, responder_chain, constraints, accessibility, interactions, or screenshot."),
            @"address": VCStringToolProperty(@"Optional live view address."),
            @"filter": VCStringToolProperty(@"Optional class, text, or address filter for hierarchy."),
            @"maxDepth": VCNumberToolProperty(@"Optional maximum hierarchy depth."),
            @"limit": VCNumberToolProperty(@"Optional result limit."),
        },
        @[@"queryType"]
    )];

    [schemas addObject:VCToolSchema(
        @"query_memory",
        @"Read conservative memory context, primitive values, pointer chains, bounded hex dumps, validate matrix candidates across multiple captures, or persisted memory snapshots and diffs.",
        @{
            @"queryType": VCStringToolProperty(@"Memory query mode: address_context, read_value, read_struct, matrix_scan, camera_candidates, matrix_validate, pointer_follow, hexdump, snapshot, snapshot_list, snapshot_detail, or diff_snapshot."),
            @"address": VCStringToolProperty(@"Target address such as 0x1234abcd. Optional for snapshot_list, snapshot_detail, or diff_snapshot when comparing saved snapshots."),
            @"typeEncoding": VCStringToolProperty(@"Safe primitive or struct type encoding such as i, q, d, B, ^v, or {CGRect={CGPoint=dd}{CGSize=dd}}."),
            @"structType": VCStringToolProperty(@"For read_struct, supported structured reads such as cgpoint, cgsize, cgrect, affine, insets, range, vector2f, vector3f, vector4f, matrix4x4f, or matrix4x4d."),
            @"matrixType": VCStringToolProperty(@"For matrix_scan or camera_candidates, matrix type such as matrix4x4f or matrix4x4d."),
            @"action": VCStringToolProperty(@"For matrix_validate: start, capture, status, rank, or clear."),
            @"protection": VCStringToolProperty(@"Optional protection filter such as rw-, r--, or r. Defaults to readable non-executable regions."),
            @"stepBytes": VCNumberToolProperty(@"For matrix_scan, scan stride in bytes. Defaults to 16 for float matrices."),
            @"regionByteLimit": VCNumberToolProperty(@"Optional maximum bytes to inspect per region while scanning for matrices."),
            @"totalByteBudget": VCNumberToolProperty(@"Optional maximum total bytes to inspect across all regions while scanning for matrices."),
            @"module": VCStringToolProperty(@"Optional module name filter for matrix_scan or camera_candidates."),
            @"expectedMotion": VCStringToolProperty(@"For matrix_validate, the expected camera motion pattern: rotate_only, zoom_only, move_only, or mixed."),
            @"label": VCStringToolProperty(@"For matrix_validate capture, an optional motion label such as baseline, yaw_left, yaw_right, pitch_up, or zoom_in."),
            @"sessionID": VCStringToolProperty(@"Optional matrix_validate session identifier. When omitted, the active matrix validation session is used."),
            @"candidateAddresses": @{
                @"type": @"array",
                @"description": @"For matrix_validate start, a list of matrix candidate addresses to validate.",
                @"items": @{@"type": @"string"}
            },
            @"candidates": @{
                @"type": @"array",
                @"description": @"For matrix_validate start, optional full candidate objects from matrix_scan or camera_candidates.",
                @"items": @{@"type": @"object"}
            },
            @"depth": VCNumberToolProperty(@"Optional pointer follow depth."),
            @"length": VCNumberToolProperty(@"Optional byte count for hexdump."),
            @"limit": VCNumberToolProperty(@"Optional result limit for snapshot_list."),
            @"snapshotID": VCStringToolProperty(@"Saved snapshot identifier for snapshot_detail or diff_snapshot."),
            @"snapshotPath": VCStringToolProperty(@"Saved snapshot path for snapshot_detail or diff_snapshot."),
            @"otherSnapshotID": VCStringToolProperty(@"Optional second snapshot identifier for diff_snapshot."),
            @"otherSnapshotPath": VCStringToolProperty(@"Optional second snapshot path for diff_snapshot."),
        },
        @[@"queryType"]
    )];

    [schemas addObject:VCToolSchema(
        @"project_3d",
        @"Project a non-Unity 3D world position or a simple 3D bounds volume into overlay screen coordinates using a concrete 4x4 view-projection matrix or matrix address.",
        @{
            @"mode": VCStringToolProperty(@"Projection mode: point or bounds. point is the default."),
            @"worldX": VCNumberToolProperty(@"World-space X coordinate."),
            @"worldY": VCNumberToolProperty(@"World-space Y coordinate."),
            @"worldZ": VCNumberToolProperty(@"World-space Z coordinate."),
            @"worldAddress": VCStringToolProperty(@"Optional address of a vector in memory when worldX/worldY/worldZ are not provided."),
            @"worldType": VCStringToolProperty(@"Type of worldAddress such as vector3f, vector4f, CGPoint, or cgpoint."),
            @"extentX": VCNumberToolProperty(@"For mode=bounds, world-space half-width on X."),
            @"extentY": VCNumberToolProperty(@"For mode=bounds, world-space half-height on Y."),
            @"extentZ": VCNumberToolProperty(@"For mode=bounds, world-space half-depth on Z."),
            @"extentAddress": VCStringToolProperty(@"Optional address of an extents vector in memory for mode=bounds."),
            @"extentType": VCStringToolProperty(@"Type of extentAddress such as vector3f or vector3d."),
            @"matrixAddress": VCStringToolProperty(@"Optional address of a 4x4 matrix in memory."),
            @"matrixType": VCStringToolProperty(@"Matrix element type, typically matrix4x4f or matrix4x4d."),
            @"matrixLayout": VCStringToolProperty(@"Matrix layout: auto, row_major, or column_major. auto compares both and picks the more plausible projection."),
            @"matrixElements": @{
                @"type": @"array",
                @"description": @"Optional explicit 16-number matrix when no matrixAddress is available.",
                @"items": @{@"type": @"number"}
            },
            @"viewportWidth": VCNumberToolProperty(@"Optional viewport width. Defaults to the current overlay width."),
            @"viewportHeight": VCNumberToolProperty(@"Optional viewport height. Defaults to the current overlay height."),
            @"viewportX": VCNumberToolProperty(@"Optional viewport origin X."),
            @"viewportY": VCNumberToolProperty(@"Optional viewport origin Y."),
            @"flipY": VCBooleanToolProperty(@"Whether to convert projected Y into top-left overlay coordinates. Defaults to true.")
        },
        @[]
    )];

    [schemas addObject:VCToolSchema(
        @"memory_browser",
        @"Browse readable memory as paged hex plus ASCII output, keep a lightweight cursor for next or previous pages, and inspect common typed previews at the current address.",
        @{
            @"action": VCStringToolProperty(@"Browser action: goto, page, next, prev, peek, or status."),
            @"address": VCStringToolProperty(@"Target runtime address such as 0x1234abcd. Required for goto or peek, optional for page when a browser session is already active."),
            @"pageSize": VCNumberToolProperty(@"Page size in bytes, clamped to a safe range. Defaults to 256."),
            @"length": VCNumberToolProperty(@"Optional read length for the current page or peek. Defaults to pageSize and is clamped within the containing readable region.")
        },
        @[@"action"]
    )];

    [schemas addObject:VCToolSchema(
        @"memory_scan",
        @"Locate unknown numeric or string values by scanning writable memory, then refine the candidate set as the app state changes.",
        @{
            @"action": VCStringToolProperty(@"Scan action: start, refine, results, status, or clear."),
            @"scanMode": VCStringToolProperty(@"For action=start, scan mode: exact, fuzzy, between, or group. group accepts a semicolon-separated composite value string."),
            @"filterMode": VCStringToolProperty(@"For action=refine, filter mode: exact, increased, decreased, changed, unchanged, greater, less, or between."),
            @"dataType": VCStringToolProperty(@"Data type: int8, int16, int32, int64, uint8, uint16, uint32, uint64, float, double, string, int_auto, uint_auto, or float_auto."),
            @"value": VCStringToolProperty(@"Primary value for exact/group start or exact refine."),
            @"minValue": VCStringToolProperty(@"Minimum value for between start or between refine."),
            @"maxValue": VCStringToolProperty(@"Maximum value for between start or between refine."),
            @"floatTolerance": VCNumberToolProperty(@"Optional float comparison tolerance for float or double scans."),
            @"groupRange": VCNumberToolProperty(@"Optional byte window for group scans."),
            @"groupAnchorMode": VCBooleanToolProperty(@"Whether group scan items should search relative to the first item instead of sequentially."),
            @"resultLimit": VCNumberToolProperty(@"Optional maximum result count to retain for the scan."),
            @"offset": VCNumberToolProperty(@"For action=results, pagination offset."),
            @"limit": VCNumberToolProperty(@"For action=results, number of candidates to return."),
            @"refreshValues": VCBooleanToolProperty(@"For action=results, whether to re-read current values from memory.")
        },
        @[@"action"]
    )];

    [schemas addObject:VCToolSchema(
        @"pointer_chain",
        @"Resolve or read a module-relative or runtime-rooted pointer chain so a temporary address can be turned into a reusable path.",
        @{
            @"action": VCStringToolProperty(@"Pointer chain action: resolve, read, or find_refs."),
            @"moduleName": VCStringToolProperty(@"Optional module name when the chain should start from a module base."),
            @"baseAddress": VCStringToolProperty(@"Optional concrete runtime base address when the chain should start from a known pointer slot instead of a module."),
            @"baseOffset": VCStringToolProperty(@"Optional base offset added before the first dereference."),
            @"offsets": @{
                @"type": @"array",
                @"description": @"Pointer offsets applied after each dereference.",
                @"items": @{@"type": @"number"}
            },
            @"dataType": VCStringToolProperty(@"For action=read, primitive type to read at the resolved address: int8, int16, int32, int64, uint8, uint16, uint32, uint64, float, or double."),
            @"address": VCStringToolProperty(@"For action=find_refs, target runtime address to search references for."),
            @"limit": VCNumberToolProperty(@"For action=find_refs, maximum number of direct references to return."),
            @"includeSecondHop": VCBooleanToolProperty(@"For action=find_refs, whether to also suggest shallow two-hop chains.")
        },
        @[@"action"]
    )];

    [schemas addObject:VCToolSchema(
        @"signature_scan",
        @"Search a module or the process for an AOB signature, then optionally resolve a final address and read its current value.",
        @{
            @"action": VCStringToolProperty(@"Signature action: scan or resolve."),
            @"signature": VCStringToolProperty(@"Signature string such as '01 23 ?? 45'."),
            @"moduleName": VCStringToolProperty(@"Optional module name to constrain the signature search."),
            @"offset": VCStringToolProperty(@"Optional signed offset added to the first signature match for action=resolve."),
            @"limit": VCNumberToolProperty(@"Maximum number of matches to return for action=scan."),
            @"dataType": VCStringToolProperty(@"For action=resolve, optional primitive type to read at the resolved address.")
        },
        @[@"action", @"signature"]
    )];

    [schemas addObject:VCToolSchema(
        @"address_resolve",
        @"Resolve module base or size, convert RVA to runtime address, or map a runtime address back to its owning module and RVA.",
        @{
            @"action": VCStringToolProperty(@"Address action: module_base, module_size, rva_to_runtime, or runtime_to_rva."),
            @"moduleName": VCStringToolProperty(@"Module name for module_base, module_size, or rva_to_runtime."),
            @"rva": VCStringToolProperty(@"RVA offset such as 0x1234 for rva_to_runtime."),
            @"address": VCStringToolProperty(@"Runtime address such as 0x1234abcd for runtime_to_rva.")
        },
        @[@"action"]
    )];

    [schemas addObject:VCToolSchema(
        @"query_artifacts",
        @"Browse saved trace sessions, checkpoints, Mermaid diagrams, and memory snapshots so analysis can resume across tabs or launches.",
        @{
            @"queryType": VCStringToolProperty(@"Artifact query mode: overview, trace_sessions, trace_session_detail, diagram_list, diagram_detail, memory_snapshot_list, memory_snapshot_detail, track_list, or track_detail."),
            @"sessionID": VCStringToolProperty(@"Trace session identifier for trace_session_detail."),
            @"artifactID": VCStringToolProperty(@"Artifact identifier or filename stem for diagram_detail."),
            @"artifactPath": VCStringToolProperty(@"Saved artifact path for diagram_detail or any direct file-based lookup."),
            @"snapshotID": VCStringToolProperty(@"Saved snapshot identifier for memory_snapshot_detail."),
            @"snapshotPath": VCStringToolProperty(@"Saved snapshot path for memory_snapshot_detail."),
            @"trackerID": VCStringToolProperty(@"Saved tracker identifier for track_detail."),
            @"trackerPath": VCStringToolProperty(@"Saved tracker path for track_detail."),
            @"includeContent": VCBooleanToolProperty(@"Whether artifact detail should include full saved content when applicable."),
            @"limit": VCNumberToolProperty(@"Optional result limit."),
        },
        @[@"queryType"]
    )];

    [schemas addObject:VCToolSchema(
        @"export_mermaid",
        @"Persist a Mermaid diagram so the analysis can be resumed later.",
        @{
            @"title": VCStringToolProperty(@"Diagram title."),
            @"diagramType": VCStringToolProperty(@"Diagram category such as ui_tree, sequence, object_graph, or flow."),
            @"content": VCStringToolProperty(@"Mermaid source to save."),
            @"summary": VCStringToolProperty(@"Short note describing what the diagram represents."),
        },
        @[@"content"]
    )];

    [schemas addObject:VCToolSchema(
        @"trace_start",
        @"Start a lightweight runtime trace session that can capture temporary method hooks, network traffic, UI selections, bounded memory watch diffs, and optional event-triggered checkpoints.",
        @{
            @"sessionName": VCStringToolProperty(@"Optional trace session name."),
            @"captureNetwork": VCBooleanToolProperty(@"Whether to capture network requests during the trace."),
            @"captureUI": VCBooleanToolProperty(@"Whether to capture UI selection events during the trace."),
            @"stopExisting": VCBooleanToolProperty(@"Whether to stop the currently active trace first."),
            @"maxEvents": VCNumberToolProperty(@"Maximum number of events to retain."),
            @"methodTargets": @{
                @"type": @"array",
                @"description": @"Optional methods to trace. Each target needs className, selector, and optional isClassMethod.",
                @"items": @{
                    @"type": @"object",
                    @"properties": @{
                        @"className": @{@"type": @"string"},
                        @"selector": @{@"type": @"string"},
                        @"isClassMethod": @{@"type": @"boolean"}
                    },
                    @"required": @[@"className", @"selector"],
                    @"additionalProperties": @YES
                }
            },
            @"memoryWatches": @{
                @"type": @"array",
                @"description": @"Optional bounded memory watches captured at trace start and stop. Each watch needs address and can include label, length, and typeEncoding.",
                @"items": @{
                    @"type": @"object",
                    @"properties": @{
                        @"address": @{@"type": @"string"},
                        @"label": @{@"type": @"string"},
                        @"length": @{@"type": @"number"},
                        @"typeEncoding": @{@"type": @"string"}
                    },
                    @"required": @[@"address"],
                    @"additionalProperties": @YES
                }
            },
            @"checkpointTriggers": @{
                @"type": @"array",
                @"description": @"Optional automatic checkpoint rules. Triggers are one-shot by default, can watch method/network/ui events, and may require watched memory changes before firing.",
                @"items": @{
                    @"type": @"object",
                    @"properties": @{
                        @"kind": @{@"type": @"string"},
                        @"label": @{@"type": @"string"},
                        @"once": @{@"type": @"boolean"},
                        @"maxCount": @{@"type": @"number"},
                        @"resetBaseline": @{@"type": @"boolean"},
                        @"className": @{@"type": @"string"},
                        @"selector": @{@"type": @"string"},
                        @"isClassMethod": @{@"type": @"boolean"},
                        @"httpMethod": @{@"type": @"string"},
                        @"host": @{@"type": @"string"},
                        @"pathContains": @{@"type": @"string"},
                        @"statusCode": @{@"type": @"number"},
                        @"viewClassName": @{@"type": @"string"},
                        @"address": @{@"type": @"string"},
                        @"titleContains": @{@"type": @"string"},
                        @"summaryContains": @{@"type": @"string"},
                        @"watchAddress": @{@"type": @"string"},
                        @"watchLabel": @{@"type": @"string"},
                        @"onlyWhenChanged": @{@"type": @"boolean"},
                        @"changedBytesAtLeast": @{@"type": @"number"},
                        @"requireTypedChange": @{@"type": @"boolean"},
                        @"typedEquals": @{@"type": @"string"},
                        @"typedContains": @{@"type": @"string"},
                        @"memoryWatches": @{
                            @"type": @"array",
                            @"items": @{
                                @"type": @"object",
                                @"properties": @{
                                    @"address": @{@"type": @"string"},
                                    @"label": @{@"type": @"string"},
                                    @"length": @{@"type": @"number"},
                                    @"typeEncoding": @{@"type": @"string"}
                                },
                                @"required": @[@"address"],
                                @"additionalProperties": @YES
                            }
                        }
                    },
                    @"required": @[@"kind"],
                    @"additionalProperties": @YES
                }
            }
        },
        @[]
    )];

    [schemas addObject:VCToolSchema(
        @"trace_checkpoint",
        @"Capture a mid-trace checkpoint, optionally registering extra memory watches and diffing current watched memory against the latest baselines.",
        @{
            @"sessionID": VCStringToolProperty(@"Optional trace session id. Defaults to the active session."),
            @"label": VCStringToolProperty(@"Optional human-readable checkpoint label."),
            @"resetBaseline": VCBooleanToolProperty(@"Whether the checkpoint should update watch baselines to the newly captured values."),
            @"memoryWatches": @{
                @"type": @"array",
                @"description": @"Optional extra bounded memory watches to add before capturing the checkpoint.",
                @"items": @{
                    @"type": @"object",
                    @"properties": @{
                        @"address": @{@"type": @"string"},
                        @"label": @{@"type": @"string"},
                        @"length": @{@"type": @"number"},
                        @"typeEncoding": @{@"type": @"string"}
                    },
                    @"required": @[@"address"],
                    @"additionalProperties": @YES
                }
            }
        },
        @[]
    )];

    [schemas addObject:VCToolSchema(
        @"trace_stop",
        @"Stop the active trace session or a specific trace session by id.",
        @{
            @"sessionID": VCStringToolProperty(@"Optional trace session id. Defaults to the active session."),
        },
        @[]
    )];

    [schemas addObject:VCToolSchema(
        @"trace_events",
        @"Read events from the active trace session or a specific trace session, including derived caller-callee call tree data, related network/UI associations, checkpoint markers, and memory watch diffs when available.",
        @{
            @"sessionID": VCStringToolProperty(@"Optional trace session id. Defaults to the active session."),
            @"limit": VCNumberToolProperty(@"Maximum number of events to return."),
            @"kindNames": @{
                @"type": @"array",
                @"description": @"Optional event kind filter such as method, network, ui, checkpoint, or memory.",
                @"items": @{@"type": @"string"}
            }
        },
        @[]
    )];

    [schemas addObject:VCToolSchema(
        @"trace_export_mermaid",
        @"Generate a Mermaid diagram from a trace session and persist it for later review, including linked checkpoint markers and watched memory diffs when present.",
        @{
            @"sessionID": VCStringToolProperty(@"Optional trace session id. Defaults to the active session."),
            @"style": VCStringToolProperty(@"Diagram style: sequence, flow, or call_tree. call_tree includes linked network/UI side events when available."),
            @"title": VCStringToolProperty(@"Optional diagram title."),
            @"limit": VCNumberToolProperty(@"Maximum number of trace events to include."),
        },
        @[]
    )];

    if (canWriteMemory) {
        [schemas addObject:VCToolSchema(
            @"modify_value",
            @"Write or lock a primitive value at a known runtime address. It can also batch-write the active memory_scan candidates when source=active_memory_scan and matchValue are provided. Use this for writable data, heap, or ivar storage. Executable text patching should use patch_method or swizzle_method instead.",
            @{
                @"address": VCStringToolProperty(@"Target memory address such as 0x1234abcd."),
                @"dataType": VCStringToolProperty(@"Primitive type: bool, char, uchar, short, ushort, int, uint, long, ulong, longlong, ulonglong, float, or double."),
                @"mode": VCStringToolProperty(@"write_once to perform one direct write, or lock to keep the value enforced over time. Defaults to lock."),
                @"modifiedValue": VCStringToolProperty(@"Replacement value to keep writing."),
                @"source": VCStringToolProperty(@"Optional source. Use active_memory_scan to write matching candidates from the current memory_scan result set."),
                @"matchValue": VCStringToolProperty(@"When source=active_memory_scan, only candidates whose refreshed currentValue equals this value are written."),
                @"maxWrites": VCNumberToolProperty(@"When source=active_memory_scan, maximum number of candidates to inspect and write."),
                @"target": VCStringToolProperty(@"Human-readable target label."),
                @"originalValue": VCStringToolProperty(@"Observed original value if known."),
                @"remark": VCStringToolProperty(@"Why this change is needed."),
            },
            @[@"modifiedValue"]
        )];

        [schemas addObject:VCToolSchema(
            @"write_memory_bytes",
            @"Write raw bytes to a known writable runtime address. Use this when a primitive value write is not sufficient and you already know the exact byte sequence to apply.",
            @{
                @"address": VCStringToolProperty(@"Target memory address such as 0x1234abcd."),
                @"hexData": VCStringToolProperty(@"Byte string such as '90 90 90 90' or 'AABBCCDD'."),
                @"target": VCStringToolProperty(@"Optional human-readable target label."),
                @"remark": VCStringToolProperty(@"Why these bytes should be written.")
            },
            @[@"address", @"hexData"]
        )];
    }

    if (canModifyRuntime) {
        [schemas addObject:VCToolSchema(
            @"patch_method",
            @"Apply a conservative runtime patch to one Objective-C method.",
            @{
                @"className": VCStringToolProperty(@"Objective-C class name."),
                @"selector": VCStringToolProperty(@"Selector name."),
                @"patchType": VCStringToolProperty(@"Patch mode: nop, return_no, or return_yes."),
                @"remark": VCStringToolProperty(@"Why this patch is being proposed."),
            },
            @[@"className", @"selector"]
        )];

        [schemas addObject:VCToolSchema(
            @"swizzle_method",
            @"Exchange the implementations of two Objective-C methods.",
            @{
                @"className": VCStringToolProperty(@"Source class name."),
                @"selector": VCStringToolProperty(@"Source selector."),
                @"otherClassName": VCStringToolProperty(@"Target class name."),
                @"otherSelector": VCStringToolProperty(@"Target selector."),
                @"isClassMethod": VCBooleanToolProperty(@"Whether the source selector is a class method."),
                @"otherIsClassMethod": VCBooleanToolProperty(@"Whether the target selector is a class method."),
                @"remark": VCStringToolProperty(@"Why this swizzle is needed."),
            },
            @[@"className", @"selector", @"otherClassName", @"otherSelector"]
        )];
    }

    if (canInstallHooks) {
        [schemas addObject:VCToolSchema(
            @"hook_method",
            @"Install a read-only logging hook for one Objective-C method.",
            @{
                @"className": VCStringToolProperty(@"Objective-C class name."),
                @"selector": VCStringToolProperty(@"Selector to hook."),
                @"isClassMethod": VCBooleanToolProperty(@"Whether the selector is a class method."),
                @"hookType": VCStringToolProperty(@"Hook mode. Only log is currently supported."),
                @"remark": VCStringToolProperty(@"Why this hook is needed."),
            },
            @[@"className", @"selector"]
        )];
    }

    [schemas addObject:VCToolSchema(
        @"modify_header",
        @"Create a network interception rule that modifies request headers or body for matching URLs.",
        @{
            @"urlPattern": VCStringToolProperty(@"URL wildcard or regex-like pattern to match."),
            @"action": VCStringToolProperty(@"Rule action. Only modify_header and modify_body are currently executable."),
            @"headers": @{
                @"type": @"object",
                @"description": @"Headers to set when action is modify_header.",
                @"additionalProperties": @{@"type": @"string"}
            },
            @"body": VCStringToolProperty(@"Replacement request body when action is modify_body."),
            @"remark": VCStringToolProperty(@"Why this rule is needed."),
        },
        @[@"urlPattern"]
    )];

    [schemas addObject:VCToolSchema(
        @"overlay_canvas",
        @"Draw, update, hide, or clear non-interactive screen-space annotations on the overlay canvas. Use this after world_to_screen or any other analysis that yields screen coordinates.",
        @{
            @"action": VCStringToolProperty(@"Canvas action: line, box, circle, text, polyline, corner_box, health_bar, offscreen_arrow, skeleton, clear, show, or hide."),
            @"canvasID": VCStringToolProperty(@"Optional canvas namespace. Defaults to unity."),
            @"itemID": VCStringToolProperty(@"Optional stable item identifier so repeated draws replace the same overlay item."),
            @"x": VCNumberToolProperty(@"Generic X coordinate for text or circle center."),
            @"y": VCNumberToolProperty(@"Generic Y coordinate for text or circle center."),
            @"x1": VCNumberToolProperty(@"Line start X."),
            @"y1": VCNumberToolProperty(@"Line start Y."),
            @"x2": VCNumberToolProperty(@"Line end X."),
            @"y2": VCNumberToolProperty(@"Line end Y."),
            @"width": VCNumberToolProperty(@"Box width."),
            @"height": VCNumberToolProperty(@"Box height."),
            @"radius": VCNumberToolProperty(@"Circle radius."),
            @"size": VCNumberToolProperty(@"Generic size for offscreen_arrow or other compact shapes."),
            @"angle": VCNumberToolProperty(@"Angle in degrees for offscreen_arrow."),
            @"text": VCStringToolProperty(@"Text label for action=text."),
            @"points": @{
                @"type": @"array",
                @"description": @"For polyline or skeleton, ordered screen points. Each point may be an object with x/y or a two-number array.",
                @"items": @{
                    @"anyOf": @[
                        @{
                            @"type": @"object",
                            @"properties": @{
                                @"x": @{@"type": @"number"},
                                @"y": @{@"type": @"number"}
                            }
                        },
                        @{
                            @"type": @"array",
                            @"items": @{@"type": @"number"}
                        }
                    ]
                }
            },
            @"bones": @{
                @"type": @"array",
                @"description": @"For skeleton, line segments referencing point indices like [[0,1],[1,2]].",
                @"items": @{
                    @"type": @"array",
                    @"items": @{@"type": @"number"}
                }
            },
            @"closed": VCBooleanToolProperty(@"For polyline, whether the path should close back to the first point."),
            @"color": VCStringToolProperty(@"Stroke or text color as #RRGGBB, #RRGGBBAA, or a named color."),
            @"fillColor": VCStringToolProperty(@"Optional fill color for box or circle."),
            @"backgroundColor": VCStringToolProperty(@"Optional text background color."),
            @"lineWidth": VCNumberToolProperty(@"Optional line width for line, box, or circle."),
            @"fontSize": VCNumberToolProperty(@"Optional text font size."),
            @"cornerRadius": VCNumberToolProperty(@"Optional corner radius for box."),
            @"value": VCNumberToolProperty(@"For health_bar, current value."),
            @"maxValue": VCNumberToolProperty(@"For health_bar, maximum value."),
            @"showLabel": VCBooleanToolProperty(@"For health_bar or skeleton, whether to draw extra labels or joint markers.")
        },
        @[@"action"]
    )];

    [schemas addObject:VCToolSchema(
        @"overlay_track",
        @"Start, stop, clear, or inspect a persistent per-frame overlay tracker that continuously reprojects a moving point or bounds volume and redraws it on the overlay canvas.",
        @{
            @"action": VCStringToolProperty(@"Tracker action: start, stop, clear, status, save, restore, or list."),
            @"trackMode": VCStringToolProperty(@"Tracking mode for action=start: screen_point, screen_rect, project_point, project_bounds, unity_transform, or unity_renderer. mode is accepted as an alias."),
            @"canvasID": VCStringToolProperty(@"Optional canvas namespace. Defaults to tracking."),
            @"itemID": VCStringToolProperty(@"Optional stable tracker identifier. When omitted, a fresh identifier is created."),
            @"drawStyle": VCStringToolProperty(@"Optional drawing style such as circle, circle_label, box, or box_label."),
            @"label": VCStringToolProperty(@"Optional persistent text label drawn near the tracked point or box."),
            @"title": VCStringToolProperty(@"For action=save, optional preset title."),
            @"subtitle": VCStringToolProperty(@"For action=save, optional preset subtitle."),
            @"trackerID": VCStringToolProperty(@"For action=restore, optional saved tracker identifier."),
            @"trackerPath": VCStringToolProperty(@"For action=restore, optional saved tracker path."),
            @"color": VCStringToolProperty(@"Primary stroke/text color."),
            @"fillColor": VCStringToolProperty(@"Optional fill color for filled circles or boxes."),
            @"backgroundColor": VCStringToolProperty(@"Optional label background color."),
            @"lineWidth": VCNumberToolProperty(@"Optional line width."),
            @"fontSize": VCNumberToolProperty(@"Optional label font size."),
            @"radius": VCNumberToolProperty(@"Optional point radius for point trackers."),
            @"cornerRadius": VCNumberToolProperty(@"Optional corner radius for box trackers."),
            @"labelOffsetX": VCNumberToolProperty(@"Optional label X offset from the tracked anchor."),
            @"labelOffsetY": VCNumberToolProperty(@"Optional label Y offset from the tracked anchor."),
            @"updateInterval": VCNumberToolProperty(@"Optional minimum refresh interval in seconds between redraws."),
            @"maxConsecutiveFailures": VCNumberToolProperty(@"Optional maximum consecutive projection failures before auto-stop."),
            @"pointAddress": VCStringToolProperty(@"For screen_point, address of a screen-space point struct."),
            @"pointType": VCStringToolProperty(@"For screen_point, struct type such as cgpoint or vector2f."),
            @"rectAddress": VCStringToolProperty(@"For screen_rect, address of a screen-space rect struct."),
            @"rectType": VCStringToolProperty(@"For screen_rect, struct type such as cgrect."),
            @"worldX": VCNumberToolProperty(@"For project_point/project_bounds, world-space X."),
            @"worldY": VCNumberToolProperty(@"For project_point/project_bounds, world-space Y."),
            @"worldZ": VCNumberToolProperty(@"For project_point/project_bounds, world-space Z."),
            @"worldAddress": VCStringToolProperty(@"For project_point/project_bounds, optional address of a world vector in memory."),
            @"worldType": VCStringToolProperty(@"Structured type of worldAddress, such as vector3f or vector4f."),
            @"extentX": VCNumberToolProperty(@"For project_bounds, world-space half-width on X."),
            @"extentY": VCNumberToolProperty(@"For project_bounds, world-space half-height on Y."),
            @"extentZ": VCNumberToolProperty(@"For project_bounds, world-space half-depth on Z."),
            @"extentAddress": VCStringToolProperty(@"For project_bounds, optional address of an extents vector."),
            @"extentType": VCStringToolProperty(@"Structured type of extentAddress."),
            @"matrixAddress": VCStringToolProperty(@"For project_point/project_bounds, address of a 4x4 matrix."),
            @"matrixType": VCStringToolProperty(@"Matrix type such as matrix4x4f or matrix4x4d."),
            @"matrixLayout": VCStringToolProperty(@"Matrix layout: auto, row_major, or column_major."),
            @"matrixElements": @{
                @"type": @"array",
                @"description": @"Optional explicit 16-number matrix when no matrixAddress is available.",
                @"items": @{@"type": @"number"}
            },
            @"viewportWidth": VCNumberToolProperty(@"Optional viewport width override."),
            @"viewportHeight": VCNumberToolProperty(@"Optional viewport height override."),
            @"viewportX": VCNumberToolProperty(@"Optional viewport origin X."),
            @"viewportY": VCNumberToolProperty(@"Optional viewport origin Y."),
            @"flipY": VCBooleanToolProperty(@"Whether projected Y should be flipped into top-left overlay coordinates."),
            @"cameraAddress": VCStringToolProperty(@"For unity_transform/unity_renderer, optional explicit Unity camera address."),
            @"transformAddress": VCStringToolProperty(@"For unity_transform, explicit Unity Transform address."),
            @"componentAddress": VCStringToolProperty(@"For unity_transform, explicit Unity Component address."),
            @"gameObjectAddress": VCStringToolProperty(@"For unity_transform, explicit Unity GameObject address."),
            @"rendererAddress": VCStringToolProperty(@"For unity_renderer, explicit Unity Renderer address."),
            @"objectKind": VCStringToolProperty(@"For unity_transform, optional transform/component/gameobject hint when using a generic address."),
        },
        @[@"action"]
    )];

    [schemas addObject:VCToolSchema(
        @"modify_view",
        @"Change a live UIKit view property such as hidden, alpha, frame, text, backgroundColor, or textColor.",
        @{
            @"address": VCStringToolProperty(@"Optional target view address such as 0x1234abcd."),
            @"property": VCStringToolProperty(@"View property to change."),
            @"value": @{
                @"anyOf": @[
                    @{@"type": @"string"},
                    @{@"type": @"number"},
                    @{@"type": @"boolean"},
                    @{
                        @"type": @"object",
                        @"properties": @{
                            @"x": @{@"type": @"number"},
                            @"y": @{@"type": @"number"},
                            @"width": @{@"type": @"number"},
                            @"height": @{@"type": @"number"}
                        },
                        @"additionalProperties": @NO
                    }
                ],
                @"description": @"New property value."
            },
            @"remark": VCStringToolProperty(@"Why the view should be changed."),
        },
        @[@"property", @"value"]
    )];

    [schemas addObject:VCToolSchema(
        @"insert_subview",
        @"Insert a simple native subview into an existing live parent view. If no parent address or selected view exists, VansonCLI uses the current key window.",
        @{
            @"address": VCStringToolProperty(@"Optional parent view address. Omit it to use the selected view or current key window."),
            @"className": VCStringToolProperty(@"UIView subclass to create, such as UILabel, UIButton, UIView, UITextField, or UITextView."),
            @"frame": @{
                @"type": @"object",
                @"description": @"Subview frame in parent coordinates.",
                @"properties": @{
                    @"x": @{@"type": @"number"},
                    @"y": @{@"type": @"number"},
                    @"width": @{@"type": @"number"},
                    @"height": @{@"type": @"number"}
                },
                @"additionalProperties": @NO
            },
            @"text": VCStringToolProperty(@"Primary text when applicable."),
            @"title": VCStringToolProperty(@"Button title when applicable."),
            @"backgroundColor": VCStringToolProperty(@"Hex background color."),
            @"textColor": VCStringToolProperty(@"Hex text color."),
            @"placeholder": VCStringToolProperty(@"Placeholder text for input controls."),
            @"alpha": VCNumberToolProperty(@"Subview alpha."),
            @"hidden": VCBooleanToolProperty(@"Initial hidden state."),
            @"remark": VCStringToolProperty(@"Why this subview is being inserted."),
        },
        @[]
    )];

    [schemas addObject:VCToolSchema(
        @"invoke_selector",
        @"Invoke a safe zero-arg or one-arg selector on a live UIKit object.",
        @{
            @"address": VCStringToolProperty(@"Optional target address."),
            @"selector": VCStringToolProperty(@"Selector name to invoke."),
            @"argument": @{
                @"anyOf": @[
                    @{@"type": @"string"},
                    @{@"type": @"number"},
                    @{@"type": @"boolean"}
                ],
                @"description": @"Optional single argument."
            },
            @"remark": VCStringToolProperty(@"Why the selector should be invoked."),
        },
        @[@"selector"]
    )];

    return [schemas copy];
}

@end
