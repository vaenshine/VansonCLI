/**
 * VCRuntimeEngine.h -- ObjC Runtime introspection engine
 * Slide-1: Runtime Engine
 *
 * In-process runtime queries via <objc/runtime.h>
 * Supports: class enumeration, method/ivar/property/protocol listing,
 *           module filtering, fuzzy search, inheritance chains,
 *           type encoding decode, IMP->RVA calculation, incremental loading
 */

#import <Foundation/Foundation.h>
#import "VCRuntimeModels.h"

@interface VCRuntimeEngine : NSObject

+ (instancetype)shared;

/**
 * Enumerate classes with optional filter/module, supports incremental loading.
 * @param filter  Fuzzy class name filter (nil = all)
 * @param module  Module name filter (nil = all)
 * @param offset  Start index for pagination
 * @param limit   Max results (0 = unlimited)
 */
- (NSArray<VCClassInfo *> *)allClassesFilteredBy:(NSString *)filter
                                          module:(NSString *)module
                                          offset:(NSUInteger)offset
                                           limit:(NSUInteger)limit;

/**
 * Full class introspection for a single class.
 */
- (VCClassInfo *)classInfoForName:(NSString *)className;

/**
 * Total registered ObjC class count.
 */
- (NSUInteger)totalClassCount;

/**
 * Decode type encoding to human-readable signature.
 * e.g. "v24@0:8@16" -> "-(void)method:(id)arg"
 */
- (NSString *)decodeTypeEncoding:(NSString *)encoding selector:(NSString *)sel isClassMethod:(BOOL)isClass;

/**
 * Decode a single type encoding character/sequence to readable type.
 */
- (NSString *)decodeSingleType:(const char *)type advance:(const char **)next;

@end