#import <Foundation/Foundation.h>

@interface VCConsole : NSObject

/// Parse raw command string into command name + args array.
/// Returns @{@"command": NSString, @"args": NSArray<NSString*>} or nil for empty input.
+ (NSDictionary *)parseCommand:(NSString *)rawInput;

@end
