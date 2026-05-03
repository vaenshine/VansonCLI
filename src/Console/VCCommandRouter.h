#import <Foundation/Foundation.h>

typedef void(^VCCommandOutput)(NSString *text);
typedef void(^VCCommandHandler)(NSArray<NSString *> *args, VCCommandOutput output);

@interface VCCommandRouter : NSObject

+ (instancetype)shared;

/// Register a command with help text and handler
- (void)registerCommand:(NSString *)name
                   help:(NSString *)helpText
                handler:(VCCommandHandler)handler;

/// Execute a raw command string (alias-resolved, then routed)
- (void)executeCommand:(NSString *)rawInput output:(VCCommandOutput)output;

/// Tab-completion: prefix match against registered commands + aliases
- (NSArray<NSString *> *)completionsForPartial:(NSString *)partial;

/// All registered commands help info
- (NSArray<NSDictionary *> *)allCommandsHelp;

/// Command history
- (void)addToHistory:(NSString *)command;
- (NSArray<NSString *> *)commandHistory;
- (void)clearHistory;

@end
