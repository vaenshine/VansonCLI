/**
 * VCToolSchemaRegistry -- canonical executable tool definitions for AI adapters
 */

#import <Foundation/Foundation.h>

@interface VCToolSchemaRegistry : NSObject

+ (NSArray<NSDictionary *> *)toolSchemasForRuntimeCapabilities:(NSDictionary *)capabilities;

@end
