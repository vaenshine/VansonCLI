/**
 * VCValueReader.h -- Instance ivar value reader
 * Slide-1: Runtime Engine
 *
 * Reads ivar values by type encoding:
 * @ (ObjC object), i/I/f/d/B/q/Q (primitives),
 * {CGRect=...} (structs), * (C string), ^v (pointer),
 * # (Class), : (SEL)
 */

#import <Foundation/Foundation.h>
#import "VCRuntimeModels.h"

@interface VCValueReader : NSObject

/**
 * Read an ivar value from a live instance.
 * Returns an ObjC object or boxed NSValue/NSNumber/NSString.
 */
+ (id)readIvar:(VCIvarInfo *)ivar fromInstance:(id)instance;

/**
 * Read a value at a raw address with given type encoding.
 * Returns a human-readable string representation.
 */
+ (NSString *)readValueAtAddress:(uintptr_t)address
                    typeEncoding:(NSString *)encoding;

@end
