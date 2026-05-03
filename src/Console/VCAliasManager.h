#import <Foundation/Foundation.h>

@interface VCAliasManager : NSObject

+ (instancetype)shared;

/// Aliases
- (void)setAlias:(NSString *)name command:(NSString *)command;
- (void)removeAlias:(NSString *)name;
- (NSDictionary<NSString *, NSString *> *)allAliases;

/// Shortcuts
- (void)setShortcut:(NSString *)name template:(NSString *)tmpl;
- (void)removeShortcut:(NSString *)name;
- (NSDictionary<NSString *, NSString *> *)allShortcuts;
- (NSString *)expandShortcut:(NSString *)name args:(NSArray<NSString *> *)args;

/// Unified resolve: alias replacement + shortcut expansion
- (NSString *)resolveInput:(NSString *)rawInput;

@end
