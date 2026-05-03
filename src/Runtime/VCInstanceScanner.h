/**
 * VCInstanceScanner.h -- Live instance scanner
 * Slide-1: Runtime Engine
 *
 * Method 1: NSHashTable weak tracking via alloc hook
 * Method 2: malloc zone heap enumeration with isa matching
 * Includes timeout protection for large heaps.
 */

#import <Foundation/Foundation.h>
#import "VCRuntimeModels.h"

@interface VCInstanceScanner : NSObject

/**
 * Scan heap for live instances of a given class.
 * Uses malloc zone enumeration with timeout protection.
 * @param className  Target class name
 * @return Array of discovered instance records
 */
+ (NSArray<VCInstanceRecord *> *)scanInstancesOfClass:(NSString *)className;

/**
 * Register a class for alloc tracking (weak references).
 * Future allocations will be recorded in the weak table.
 */
+ (void)trackAllocsForClass:(NSString *)className;

/**
 * Get tracked instances (from alloc hook).
 */
+ (NSArray<VCInstanceRecord *> *)trackedInstancesOfClass:(NSString *)className;

@end
