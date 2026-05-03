/**
 * VCMemoryManager -- Durable chat memory store
 * Keeps stable user/project/reference/feedback memories out of the raw transcript.
 */

#import <Foundation/Foundation.h>

@class VCToolCall;

@interface VCMemoryManager : NSObject

+ (instancetype)shared;

- (void)ingestUserText:(NSString *)text;
- (void)ingestProjectContext;
- (void)recordReferenceFromText:(NSString *)text;
- (NSDictionary *)promptPayload;
- (NSArray<NSDictionary *> *)allMemories;
- (void)save;

@end
