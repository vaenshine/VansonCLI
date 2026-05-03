/**
 * VCStringScanner.mm -- Mach-O string section scanner
 * Slide-1: Runtime Engine
 */

#import "VCStringScanner.h"
#import "../Core/VCCore.hpp"
#import "../../VansonCLI.h"

#import <mach-o/dyld.h>
#import <mach-o/getsect.h>
#import <mach-o/loader.h>
#import <string.h>

// ═══════════════════════════════════════════════════════════════
// Section descriptor
// ═══════════════════════════════════════════════════════════════

typedef struct {
    const char *segment;
    const char *section;
    NSString *displayName;
} VCSectionDesc;

static const VCSectionDesc kSections[] = {
    { "__TEXT", "__cstring",         @"__TEXT.__cstring" },
    { "__TEXT", "__objc_methnames",  @"__TEXT.__objc_methnames" },
    { "__TEXT", "__objc_classname",  @"__TEXT.__objc_classname" },
    { "__DATA", "__cfstring",       @"__DATA.__cfstring" },
};
static const int kSectionCount = sizeof(kSections) / sizeof(kSections[0]);

// ═══════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════

static uint32_t vc_imageIndexForModule(NSString *module) {
    uint32_t count = _dyld_image_count();
    if (!module) return 0; // main executable
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name) {
            NSString *path = [NSString stringWithUTF8String:name];
            if ([[path lastPathComponent] isEqualToString:module]) return i;
        }
    }
    return 0;
}

@implementation VCStringScanner

+ (NSArray<VCStringResult *> *)scanStringsMatching:(NSString *)pattern
                                          inModule:(NSString *)module {
    if (!pattern || pattern.length == 0) return @[];

    uint32_t idx = vc_imageIndexForModule(module);
    const struct mach_header_64 *header =
        (const struct mach_header_64 *)_dyld_get_image_header(idx);
    intptr_t slide = _dyld_get_image_vmaddr_slide(idx);

    if (!header) return @[];

    NSString *modName = module;
    if (!modName) {
        const char *name = _dyld_get_image_name(idx);
        modName = name ? [[NSString stringWithUTF8String:name] lastPathComponent] : @"main";
    }

    // Try regex first, fall back to substring
    NSRegularExpression *regex =
        [NSRegularExpression regularExpressionWithPattern:pattern
                                                 options:NSRegularExpressionCaseInsensitive
                                                   error:nil];

    NSMutableArray<VCStringResult *> *results = [NSMutableArray array];

    for (int s = 0; s < kSectionCount; s++) {
        unsigned long size = 0;
        const uint8_t *data = getsectiondata(header,
                                             kSections[s].segment,
                                             kSections[s].section,
                                             &size);
        if (!data || size == 0) continue;

        // __DATA.__cfstring has a different layout (struct { ptr, flags, str, len })
        if (strcmp(kSections[s].section, "__cfstring") == 0) {
            [self _scanCFStrings:data size:size slide:slide
                         header:header section:kSections[s].displayName
                         module:modName pattern:pattern regex:regex
                        results:results];
            continue;
        }

        // C-string sections: null-terminated strings packed together
        const char *ptr = (const char *)data;
        const char *end = (const char *)(data + size);

        while (ptr < end) {
            size_t len = strnlen(ptr, end - ptr);
            if (len == 0) { ptr++; continue; }

            NSString *str = [[NSString alloc] initWithBytes:ptr
                                                     length:len
                                                   encoding:NSUTF8StringEncoding];
            if (str && [self _string:str matchesPattern:pattern regex:regex]) {
                VCStringResult *r = [[VCStringResult alloc] init];
                r.value = str;
                r.section = kSections[s].displayName;
                r.moduleName = modName;
                r.address = (uintptr_t)ptr;
                r.rva = (uintptr_t)ptr - (uintptr_t)header - slide;
                [results addObject:r];
            }
            ptr += len + 1;
        }
    }

    return [results copy];
}

// ═══════════════════════════════════════════════════════════════
// Private helpers
// ═══════════════════════════════════════════════════════════════

+ (BOOL)_string:(NSString *)str matchesPattern:(NSString *)pattern
          regex:(NSRegularExpression *)regex {
    if (regex) {
        NSRange range = NSMakeRange(0, str.length);
        return [regex firstMatchInString:str options:0 range:range] != nil;
    }
    return [[str lowercaseString] containsString:[pattern lowercaseString]];
}

+ (void)_scanCFStrings:(const uint8_t *)data
                  size:(unsigned long)size
                 slide:(intptr_t)slide
                header:(const struct mach_header_64 *)header
               section:(NSString *)sectionName
                module:(NSString *)modName
               pattern:(NSString *)pattern
                 regex:(NSRegularExpression *)regex
               results:(NSMutableArray<VCStringResult *> *)results {
    // CFString struct: { Class isa; uint32_t flags; const char *str; long length; }
    // On arm64: 32 bytes per entry
    static const size_t kCFStringSize = 32;
    if (size < kCFStringSize) return;

    size_t count = size / kCFStringSize;
    for (size_t i = 0; i < count; i++) {
        const uint8_t *entry = data + (i * kCFStringSize);
        // str pointer is at offset 16
        const char *cstr = *(const char **)(entry + 16);
        if (!cstr) continue;

        // Validate pointer is readable
        @try {
            size_t len = strlen(cstr);
            if (len == 0 || len > 10000) continue;

            NSString *str = [NSString stringWithUTF8String:cstr];
            if (str && [self _string:str matchesPattern:pattern regex:regex]) {
                VCStringResult *r = [[VCStringResult alloc] init];
                r.value = str;
                r.section = sectionName;
                r.moduleName = modName;
                r.address = (uintptr_t)cstr;
                r.rva = (uintptr_t)entry - (uintptr_t)header - slide;
                [results addObject:r];
            }
        } @catch (NSException *e) {
            continue; // Bad pointer, skip
        }
    }
}

@end
