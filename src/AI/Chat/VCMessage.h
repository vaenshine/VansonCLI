/**
 * VCMessage -- 消息模型
 * blocks 是聊天渲染的唯一真相源
 */

#import <Foundation/Foundation.h>

@class VCToolCall;

@interface VCMessage : NSObject <NSCoding>

@property (nonatomic, copy) NSString *messageID;
@property (nonatomic, copy) NSString *role;          // "user" / "assistant" / "system"
@property (nonatomic, copy) NSString *content;
@property (nonatomic, copy) NSArray<VCToolCall *> *toolCalls;
@property (nonatomic, copy) NSArray<NSDictionary *> *references;
@property (nonatomic, copy) NSArray<NSDictionary *> *blocks;
@property (nonatomic, copy) NSDate *timestamp;
@property (nonatomic, assign) BOOL isEdited;

+ (instancetype)messageWithRole:(NSString *)role content:(NSString *)content;

- (NSDictionary *)toDictionary;
+ (instancetype)fromDictionary:(NSDictionary *)dict;

// Convert to API format (for sending to AI)
- (NSDictionary *)toAPIFormat;

// Returns the canonical render blocks for this message.
- (NSArray<NSDictionary *> *)resolvedBlocks;

@end
