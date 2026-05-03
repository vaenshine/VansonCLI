/**
 * VCValueReader.mm -- Instance ivar value reader
 * Slide-1: Runtime Engine
 */

#import "VCValueReader.h"
#import "../Core/VCCore.hpp"
#import "../../VansonCLI.h"

#import <objc/runtime.h>
#import <UIKit/UIKit.h>

@implementation VCValueReader

+ (id)readIvar:(VCIvarInfo *)ivar fromInstance:(id)instance {
    if (!ivar || !instance) return nil;

    const char *type = [ivar.typeEncoding UTF8String];
    if (!type || *type == '\0') return nil;

    char *base = (char *)(__bridge void *)instance;
    void *ptr = base + ivar.offset;

    @try {
        return [self _readValueAtPtr:ptr type:type instance:instance ivarName:ivar.name];
    } @catch (NSException *e) {
        return [NSString stringWithFormat:@"<error: %@>", e.reason];
    }
}

+ (NSString *)readValueAtAddress:(uintptr_t)address typeEncoding:(NSString *)encoding {
    if (address == 0 || !encoding) return @"<null>";

    const char *type = [encoding UTF8String];
    if (!type || *type == '\0') return @"<unknown type>";

    @try {
        id val = [self _readValueAtPtr:(void *)address type:type instance:nil ivarName:nil];
        if ([val isKindOfClass:[NSString class]]) return val;
        return [val description] ?: @"<nil>";
    } @catch (NSException *e) {
        return [NSString stringWithFormat:@"<error: %@>", e.reason];
    }
}

// ═══════════════════════════════════════════════════════════════
// Core reader
// ═══════════════════════════════════════════════════════════════

+ (id)_readValueAtPtr:(void *)ptr
                 type:(const char *)type
             instance:(id)instance
             ivarName:(NSString *)ivarName {
    if (!ptr || !type) return nil;

    switch (*type) {
        // ObjC object
        case '@': {
            if (instance && ivarName) {
                // Prefer object_getIvar for safety
                Ivar iv = class_getInstanceVariable(object_getClass(instance),
                                                     [ivarName UTF8String]);
                if (iv) {
                    id val = object_getIvar(instance, iv);
                    if (!val) return @"nil";
                    return [self _safeDescription:val];
                }
            }
            id val = (__bridge id)(*(void **)ptr);
            if (!val) return @"nil";
            return [self _safeDescription:val];
        }

        // Class
        case '#': {
            Class cls = *(Class *)ptr;
            if (!cls) return @"nil";
            return [NSString stringWithFormat:@"[Class: %s]", class_getName(cls)];
        }

        // SEL
        case ':': {
            SEL sel = *(SEL *)ptr;
            if (!sel) return @"nil";
            return [NSString stringWithFormat:@"@selector(%@)", NSStringFromSelector(sel)];
        }

        // char (also used for BOOL on 32-bit)
        case 'c': return @(*(char *)ptr);
        case 'C': return @(*(unsigned char *)ptr);

        // int
        case 'i': return @(*(int *)ptr);
        case 'I': return @(*(unsigned int *)ptr);

        // short
        case 's': return @(*(short *)ptr);
        case 'S': return @(*(unsigned short *)ptr);

        // long
        case 'l': return @(*(long *)ptr);
        case 'L': return @(*(unsigned long *)ptr);

        // long long
        case 'q': return @(*(long long *)ptr);
        case 'Q': return @(*(unsigned long long *)ptr);

        // float / double
        case 'f': return @(*(float *)ptr);
        case 'd': return @(*(double *)ptr);

        // BOOL (arm64)
        case 'B': return *(BOOL *)ptr ? @"YES" : @"NO";

        // C string
        case '*': {
            const char *str = *(const char **)ptr;
            if (!str) return @"NULL";
            return [NSString stringWithFormat:@"\"%s\"", str];
        }

        // Pointer
        case '^': {
            void *p = *(void **)ptr;
            if (!p) return @"NULL";
            return [NSString stringWithFormat:@"%p", p];
        }

        // Struct
        case '{': {
            return [self _readStruct:ptr type:type];
        }

        // void
        case 'v': return @"void";

        // Unknown / block
        case '?': {
            void *p = *(void **)ptr;
            return p ? [NSString stringWithFormat:@"<block/fn %p>", p] : @"NULL";
        }

        default:
            return [NSString stringWithFormat:@"<unsupported: %c>", *type];
    }
}

// ═══════════════════════════════════════════════════════════════
// Struct reader (common UIKit/CoreGraphics structs)
// ═══════════════════════════════════════════════════════════════

+ (NSString *)_readStruct:(void *)ptr type:(const char *)type {
    if (!ptr || !type) return @"<null struct>";

    // Extract struct name between { and =
    const char *eq = strchr(type, '=');
    if (!eq) return [NSString stringWithFormat:@"<struct at %p>", ptr];

    size_t nameLen = eq - type - 1;
    char name[128];
    if (nameLen >= sizeof(name)) nameLen = sizeof(name) - 1;
    strncpy(name, type + 1, nameLen);
    name[nameLen] = '\0';

    // CGPoint
    if (strcmp(name, "CGPoint") == 0) {
        CGPoint p = *(CGPoint *)ptr;
        return [NSString stringWithFormat:@"{%.2f, %.2f}", p.x, p.y];
    }
    // CGSize
    if (strcmp(name, "CGSize") == 0) {
        CGSize s = *(CGSize *)ptr;
        return [NSString stringWithFormat:@"{%.2f, %.2f}", s.width, s.height];
    }
    // CGRect
    if (strcmp(name, "CGRect") == 0) {
        CGRect r = *(CGRect *)ptr;
        return [NSString stringWithFormat:@"{{%.2f, %.2f}, {%.2f, %.2f}}",
                r.origin.x, r.origin.y, r.size.width, r.size.height];
    }
    // CGAffineTransform
    if (strcmp(name, "CGAffineTransform") == 0) {
        CGAffineTransform t = *(CGAffineTransform *)ptr;
        return [NSString stringWithFormat:@"[%.2f, %.2f, %.2f, %.2f, %.2f, %.2f]",
                t.a, t.b, t.c, t.d, t.tx, t.ty];
    }
    // UIEdgeInsets
    if (strcmp(name, "UIEdgeInsets") == 0) {
        UIEdgeInsets i = *(UIEdgeInsets *)ptr;
        return [NSString stringWithFormat:@"{%.2f, %.2f, %.2f, %.2f}",
                i.top, i.left, i.bottom, i.right];
    }
    // NSRange
    if (strcmp(name, "_NSRange") == 0 || strcmp(name, "NSRange") == 0) {
        NSRange r = *(NSRange *)ptr;
        return [NSString stringWithFormat:@"{loc=%lu, len=%lu}",
                (unsigned long)r.location, (unsigned long)r.length];
    }

    return [NSString stringWithFormat:@"<struct %s at %p>", name, ptr];
}

// ═══════════════════════════════════════════════════════════════
// Safe description (truncated, exception-safe)
// ═══════════════════════════════════════════════════════════════

+ (NSString *)_safeDescription:(id)obj {
    @try {
        NSString *desc = [obj debugDescription];
        if (!desc) desc = [obj description];
        if (!desc) desc = [NSString stringWithFormat:@"<%@: %p>",
                           NSStringFromClass([obj class]), obj];
        if (desc.length > 300) {
            desc = [[desc substringToIndex:297] stringByAppendingString:@"..."];
        }
        return desc;
    } @catch (NSException *e) {
        return [NSString stringWithFormat:@"<%@: %p (desc threw %@)>",
                NSStringFromClass([obj class]), obj, e.name];
    }
}

@end
