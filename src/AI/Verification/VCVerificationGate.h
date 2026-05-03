/**
 * VCVerificationGate -- Local read-only verification for executed tool calls
 */

#import <Foundation/Foundation.h>

@class VCToolCall;

@interface VCVerificationGate : NSObject

+ (void)applyVerificationToToolCall:(VCToolCall *)toolCall;

@end
