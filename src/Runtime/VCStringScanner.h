/**
 * VCStringScanner.h -- Mach-O string section scanner
 * Slide-1: Runtime Engine
 *
 * Scans: __TEXT.__cstring, __TEXT.__objc_methnames,
 *        __TEXT.__objc_classname, __DATA.__cfstring
 * Supports regex and fuzzy search.
 */

#import <Foundation/Foundation.h>
#import "VCRuntimeModels.h"

@interface VCStringScanner : NSObject

/**
 * Scan Mach-O string sections for matching strings.
 * @param pattern  Regex or substring pattern
 * @param module   Module name filter (nil = main executable)
 */
+ (NSArray<VCStringResult *> *)scanStringsMatching:(NSString *)pattern
                                          inModule:(NSString *)module;

@end
