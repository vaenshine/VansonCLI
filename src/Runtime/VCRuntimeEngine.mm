/**
 * VCRuntimeEngine.mm -- ObjC Runtime introspection engine
 * Slide-1: Runtime Engine
 */

#import "VCRuntimeEngine.h"
#import "../Core/VCCore.hpp"
#import "../../VansonCLI.h"

#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <mach-o/getsect.h>
#import <dlfcn.h>

// ═══════════════════════════════════════════════════════════════
// Module lookup helpers
// ═══════════════════════════════════════════════════════════════

static NSString *vc_moduleNameForClass(Class cls) {
    if (!cls) return nil;
    Dl_info info;
    IMP imp = class_getMethodImplementation(cls, @selector(class));
    if (imp && dladdr((void *)imp, &info) && info.dli_fname) {
        NSString *path = [NSString stringWithUTF8String:info.dli_fname];
        return [path lastPathComponent];
    }
    return nil;
}

static uintptr_t vc_imageBaseForModule(const char *moduleName) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name) {
            NSString *path = [NSString stringWithUTF8String:name];
            if ([[path lastPathComponent] isEqualToString:
                 [NSString stringWithUTF8String:moduleName]]) {
                return (uintptr_t)_dyld_get_image_header(i);
            }
        }
    }
    return 0;
}

static intptr_t vc_slideForModule(const char *moduleName) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name) {
            NSString *path = [NSString stringWithUTF8String:name];
            if ([[path lastPathComponent] isEqualToString:
                 [NSString stringWithUTF8String:moduleName]]) {
                return _dyld_get_image_vmaddr_slide(i);
            }
        }
    }
    return 0;
}

static uintptr_t vc_rvaForIMP(IMP imp) {
    if (!imp) return 0;
    Dl_info info;
    if (dladdr((void *)imp, &info) && info.dli_fname) {
        intptr_t slide = vc_slideForModule(info.dli_fname);
        uintptr_t base = vc_imageBaseForModule(info.dli_fname);
        if (base) {
            return (uintptr_t)imp - base - slide + (uintptr_t)((const struct mach_header_64 *)base)->sizeofcmds + sizeof(struct mach_header_64);
        }
        // Fallback: IMP - slide - header
        return (uintptr_t)imp - slide - (uintptr_t)_dyld_get_image_header(0);
    }
    return (uintptr_t)imp;
}

// ═══════════════════════════════════════════════════════════════
// Type encoding decoder
// ═══════════════════════════════════════════════════════════════

static NSString *vc_decodeSingleType(const char *type, const char **next) {
    if (!type || *type == '\0') {
        if (next) *next = type;
        return @"void";
    }

    // Skip numeric offsets
    while (*type >= '0' && *type <= '9') type++;
    if (*type == '\0') {
        if (next) *next = type;
        return @"void";
    }

    char c = *type;
    const char *end = type + 1;

    // Skip trailing digits (stack offsets)
    while (*end >= '0' && *end <= '9') end++;

    NSString *result = nil;
    switch (c) {
        case 'v': result = @"void"; break;
        case 'c': result = @"char"; break;
        case 'i': result = @"int"; break;
        case 's': result = @"short"; break;
        case 'l': result = @"long"; break;
        case 'q': result = @"long long"; break;
        case 'C': result = @"unsigned char"; break;
        case 'I': result = @"unsigned int"; break;
        case 'S': result = @"unsigned short"; break;
        case 'L': result = @"unsigned long"; break;
        case 'Q': result = @"unsigned long long"; break;
        case 'f': result = @"float"; break;
        case 'd': result = @"double"; break;
        case 'B': result = @"BOOL"; break;
        case '*': result = @"char *"; break;
        case '#': result = @"Class"; break;
        case ':': result = @"SEL"; break;
        case '?': result = @"unknown/block"; break;
        case 'V': result = @"oneway void"; break;
        case '@': {
            if (*(type + 1) == '"') {
                // @"ClassName"
                const char *start = type + 2;
                const char *close = strchr(start, '"');
                if (close) {
                    NSString *cls = [[NSString alloc] initWithBytes:start
                                                            length:(close - start)
                                                          encoding:NSUTF8StringEncoding];
                    end = close + 1;
                    while (*end >= '0' && *end <= '9') end++;
                    result = [NSString stringWithFormat:@"%@ *", cls];
                } else {
                    result = @"id";
                }
            } else if (*(type + 1) == '?') {
                end = type + 2;
                while (*end >= '0' && *end <= '9') end++;
                result = @"id /* block */";
            } else {
                result = @"id";
            }
            break;
        }
        case '^': {
            const char *inner = type + 1;
            const char *innerNext = NULL;
            NSString *pointed = vc_decodeSingleType(inner, &innerNext);
            if (innerNext) end = innerNext;
            result = [NSString stringWithFormat:@"%@ *", pointed];
            break;
        }
        case '{': {
            const char *eq = strchr(type, '=');
            const char *close = strchr(type, '}');
            if (eq && close && eq < close) {
                NSString *name = [[NSString alloc] initWithBytes:type + 1
                                                          length:(eq - type - 1)
                                                        encoding:NSUTF8StringEncoding];
                end = close + 1;
                while (*end >= '0' && *end <= '9') end++;
                result = [NSString stringWithFormat:@"struct %@", name];
            } else if (close) {
                end = close + 1;
                while (*end >= '0' && *end <= '9') end++;
                result = @"struct ?";
            } else {
                result = @"struct ?";
            }
            break;
        }
        case '[': {
            const char *close = strchr(type, ']');
            if (close) {
                end = close + 1;
                while (*end >= '0' && *end <= '9') end++;
            }
            result = @"array";
            break;
        }
        case '(': {
            const char *close = strchr(type, ')');
            if (close) {
                end = close + 1;
                while (*end >= '0' && *end <= '9') end++;
            }
            result = @"union";
            break;
        }
        case 'r': result = @"const"; end = type + 1; break;
        case 'n': result = @"in"; end = type + 1; break;
        case 'N': result = @"inout"; end = type + 1; break;
        case 'o': result = @"out"; end = type + 1; break;
        case 'O': result = @"bycopy"; end = type + 1; break;
        case 'R': result = @"byref"; end = type + 1; break;
        default:
            result = [NSString stringWithFormat:@"<%c>", c];
            break;
    }

    if (next) *next = end;
    return result;
}

static NSString *vc_decodeMethodSignature(const char *types, NSString *sel, BOOL isClassMethod) {
    if (!types || !sel) return @"?";

    const char *p = types;
    const char *next = NULL;

    // Return type
    NSString *retType = vc_decodeSingleType(p, &next);
    p = next;

    // Skip self (@) and _cmd (:)
    if (p && *p) { vc_decodeSingleType(p, &next); p = next; }
    if (p && *p) { vc_decodeSingleType(p, &next); p = next; }

    // Split selector by ':'
    NSArray *parts = [sel componentsSeparatedByString:@":"];
    NSMutableString *sig = [NSMutableString string];
    [sig appendFormat:@"%@(%@)", isClassMethod ? @"+" : @"-", retType];

    if (parts.count <= 1 || (parts.count == 2 && [parts[1] length] == 0 && ![sel containsString:@":"])) {
        // No arguments
        [sig appendString:sel];
    } else {
        for (NSUInteger i = 0; i < parts.count; i++) {
            NSString *part = parts[i];
            if (part.length == 0 && i == parts.count - 1) break;

            if (p && *p) {
                NSString *argType = vc_decodeSingleType(p, &next);
                p = next;
                [sig appendFormat:@"%@:(%@)arg%lu ", part, argType, (unsigned long)i];
            } else {
                [sig appendFormat:@"%@: ", part];
            }
        }
    }

    return [sig stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

// ═══════════════════════════════════════════════════════════════
// VCRuntimeEngine implementation
// ═══════════════════════════════════════════════════════════════

@implementation VCRuntimeEngine {
    NSArray<NSString *> *_cachedClassNames;
    NSUInteger _cachedClassCount;
}

+ (instancetype)shared {
    static VCRuntimeEngine *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VCRuntimeEngine alloc] init];
    });
    return instance;
}

- (NSUInteger)totalClassCount {
    return (NSUInteger)objc_getClassList(NULL, 0);
}

- (void)_refreshClassListIfNeeded {
    NSUInteger current = [self totalClassCount];
    if (_cachedClassNames && _cachedClassCount == current) return;

    int count = objc_getClassList(NULL, 0);
    if (count <= 0) {
        _cachedClassNames = @[];
        _cachedClassCount = 0;
        return;
    }

    Class *classes = (Class *)malloc(sizeof(Class) * count);
    count = objc_getClassList(classes, count);

    NSMutableArray *names = [NSMutableArray arrayWithCapacity:count];
    for (int i = 0; i < count; i++) {
        const char *name = class_getName(classes[i]);
        if (name) {
            [names addObject:[NSString stringWithUTF8String:name]];
        }
    }
    free(classes);

    [names sortUsingSelector:@selector(compare:)];
    _cachedClassNames = [names copy];
    _cachedClassCount = current;
}

- (NSArray<VCClassInfo *> *)allClassesFilteredBy:(NSString *)filter
                                          module:(NSString *)module
                                          offset:(NSUInteger)offset
                                           limit:(NSUInteger)limit {
    [self _refreshClassListIfNeeded];

    NSString *lowerFilter = [filter lowercaseString];
    NSMutableArray<NSString *> *filtered = [NSMutableArray array];

    for (NSString *name in _cachedClassNames) {
        // Fuzzy name filter
        if (lowerFilter.length > 0) {
            if (![[name lowercaseString] containsString:lowerFilter]) continue;
        }
        // Module filter
        if (module.length > 0) {
            Class cls = objc_getClass([name UTF8String]);
            NSString *mod = vc_moduleNameForClass(cls);
            if (!mod || ![mod isEqualToString:module]) continue;
        }
        [filtered addObject:name];
    }

    // Pagination
    if (offset >= filtered.count) return @[];
    NSUInteger end = (limit > 0) ? MIN(offset + limit, filtered.count) : filtered.count;
    NSArray *page = [filtered subarrayWithRange:NSMakeRange(offset, end - offset)];

    NSMutableArray<VCClassInfo *> *results = [NSMutableArray arrayWithCapacity:page.count];
    for (NSString *name in page) {
        VCClassInfo *info = [self classInfoForName:name];
        if (info) [results addObject:info];
    }
    return results;
}

- (VCClassInfo *)classInfoForName:(NSString *)className {
    if (!className) return nil;
    Class cls = objc_getClass([className UTF8String]);
    if (!cls) return nil;

    VCClassInfo *info = [[VCClassInfo alloc] init];
    info.className = className;
    info.moduleName = vc_moduleNameForClass(cls) ?: @"unknown";

    // Superclass
    Class super_ = class_getSuperclass(cls);
    info.superClassName = super_ ? [NSString stringWithUTF8String:class_getName(super_)] : nil;

    // Inheritance chain
    NSMutableArray *chain = [NSMutableArray array];
    Class walk = cls;
    while (walk) {
        [chain addObject:[NSString stringWithUTF8String:class_getName(walk)]];
        walk = class_getSuperclass(walk);
    }
    info.inheritanceChain = [chain copy];

    // Instance methods
    info.instanceMethods = [self _methodsForClass:cls isMetaClass:NO];

    // Class methods (from metaclass)
    Class meta = object_getClass(cls);
    info.classMethods = [self _methodsForClass:meta isMetaClass:YES];

    // Ivars
    info.ivars = [self _ivarsForClass:cls];

    // Properties
    info.properties = [self _propertiesForClass:cls];

    // Protocols
    unsigned int protoCount = 0;
    Protocol * __unsafe_unretained *protos = class_copyProtocolList(cls, &protoCount);
    NSMutableArray *protoNames = [NSMutableArray arrayWithCapacity:protoCount];
    for (unsigned int i = 0; i < protoCount; i++) {
        const char *name = protocol_getName(protos[i]);
        if (name) [protoNames addObject:[NSString stringWithUTF8String:name]];
    }
    free(protos);
    info.protocols = [protoNames copy];

    return info;
}

// ═══════════════════════════════════════════════════════════════
// Private helpers
// ═══════════════════════════════════════════════════════════════

- (NSArray<VCMethodInfo *> *)_methodsForClass:(Class)cls isMetaClass:(BOOL)isMeta {
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:count];

    for (unsigned int i = 0; i < count; i++) {
        VCMethodInfo *m = [[VCMethodInfo alloc] init];
        SEL sel = method_getName(methods[i]);
        m.selector = NSStringFromSelector(sel);

        const char *types = method_getTypeEncoding(methods[i]);
        m.typeEncoding = types ? [NSString stringWithUTF8String:types] : @"";
        m.decodedSignature = vc_decodeMethodSignature(types, m.selector, isMeta);

        IMP imp = method_getImplementation(methods[i]);
        m.impAddress = (uintptr_t)imp;
        m.rva = vc_rvaForIMP(imp);

        [result addObject:m];
    }
    free(methods);

    [result sortUsingComparator:^NSComparisonResult(VCMethodInfo *a, VCMethodInfo *b) {
        return [a.selector compare:b.selector];
    }];
    return [result copy];
}

- (NSArray<VCIvarInfo *> *)_ivarsForClass:(Class)cls {
    unsigned int count = 0;
    Ivar *ivars = class_copyIvarList(cls, &count);
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:count];

    for (unsigned int i = 0; i < count; i++) {
        VCIvarInfo *iv = [[VCIvarInfo alloc] init];
        const char *name = ivar_getName(ivars[i]);
        iv.name = name ? [NSString stringWithUTF8String:name] : @"?";

        const char *type = ivar_getTypeEncoding(ivars[i]);
        iv.typeEncoding = type ? [NSString stringWithUTF8String:type] : @"?";
        iv.decodedType = vc_decodeSingleType(type, NULL);
        iv.offset = ivar_getOffset(ivars[i]);

        [result addObject:iv];
    }
    free(ivars);
    return [result copy];
}

- (NSArray<VCPropertyInfo *> *)_propertiesForClass:(Class)cls {
    unsigned int count = 0;
    objc_property_t *props = class_copyPropertyList(cls, &count);
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:count];

    for (unsigned int i = 0; i < count; i++) {
        VCPropertyInfo *p = [[VCPropertyInfo alloc] init];
        p.name = [NSString stringWithUTF8String:property_getName(props[i])];

        const char *attrs = property_getAttributes(props[i]);
        p.attributes = attrs ? [NSString stringWithUTF8String:attrs] : @"";

        // Parse attributes: T<type>,R,W,N,G<getter>,S<setter>,V<ivar>
        p.isReadonly = NO;
        p.isWeak = NO;
        p.isNonatomic = NO;
        p.type = @"id";

        if (attrs) {
            NSArray *parts = [[NSString stringWithUTF8String:attrs] componentsSeparatedByString:@","];
            for (NSString *part in parts) {
                if ([part hasPrefix:@"T"]) {
                    NSString *typeStr = [part substringFromIndex:1];
                    const char *t = [typeStr UTF8String];
                    p.type = vc_decodeSingleType(t, NULL);
                } else if ([part isEqualToString:@"R"]) {
                    p.isReadonly = YES;
                } else if ([part isEqualToString:@"W"]) {
                    p.isWeak = YES;
                } else if ([part isEqualToString:@"N"]) {
                    p.isNonatomic = YES;
                } else if ([part hasPrefix:@"G"]) {
                    p.getter = [part substringFromIndex:1];
                } else if ([part hasPrefix:@"S"]) {
                    p.setter = [part substringFromIndex:1];
                } else if ([part hasPrefix:@"V"]) {
                    p.ivarName = [part substringFromIndex:1];
                }
            }
        }

        if (!p.getter) p.getter = p.name;
        if (!p.setter && !p.isReadonly) {
            NSString *cap = [[p.name substringToIndex:1] uppercaseString];
            p.setter = [NSString stringWithFormat:@"set%@%@:", cap, [p.name substringFromIndex:1]];
        }

        [result addObject:p];
    }
    free(props);
    return [result copy];
}

// ═══════════════════════════════════════════════════════════════
// Public decode helpers
// ═══════════════════════════════════════════════════════════════

- (NSString *)decodeTypeEncoding:(NSString *)encoding selector:(NSString *)sel isClassMethod:(BOOL)isClass {
    return vc_decodeMethodSignature([encoding UTF8String], sel, isClass);
}

- (NSString *)decodeSingleType:(const char *)type advance:(const char **)next {
    return vc_decodeSingleType(type, next);
}

@end
