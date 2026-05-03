#import "VCCommandRouter.h"
#import "VCConsole.h"
#import "VCAliasManager.h"
#import "../Core/VCCore.hpp"

static const NSUInteger kVCMaxHistory = 200;

@interface VCCommandEntry : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *helpText;
@property (nonatomic, copy) VCCommandHandler handler;
@end

@implementation VCCommandEntry
@end

@interface VCCommandRouter ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, VCCommandEntry *> *commands;
@property (nonatomic, strong) NSMutableArray<NSString *> *history;
@end

@implementation VCCommandRouter

+ (instancetype)shared {
    static VCCommandRouter *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VCCommandRouter alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _commands = [NSMutableDictionary dictionary];
        _history = [NSMutableArray array];
        [self _registerBuiltinCommands];
        [self _registerPlaceholderCommands];
    }
    return self;
}

#pragma mark - Registration

- (void)registerCommand:(NSString *)name
                   help:(NSString *)helpText
                handler:(VCCommandHandler)handler {
    if (!name.length) return;
    VCCommandEntry *entry = [[VCCommandEntry alloc] init];
    entry.name = name;
    entry.helpText = helpText ?: @"";
    entry.handler = handler;
    self.commands[name.lowercaseString] = entry;
}

#pragma mark - Execution

- (void)executeCommand:(NSString *)rawInput output:(VCCommandOutput)output {
    if (!rawInput.length || !output) return;

    // Resolve aliases / shortcuts
    NSString *resolved = [[VCAliasManager shared] resolveInput:rawInput];

    NSDictionary *parsed = [VCConsole parseCommand:resolved];
    if (!parsed) return;

    NSString *cmdName = [parsed[@"command"] lowercaseString];
    NSArray<NSString *> *args = parsed[@"args"];

    VCCommandEntry *entry = self.commands[cmdName];
    if (!entry || !entry.handler) {
        output([NSString stringWithFormat:@"Unknown command: %@. Type 'help' for available commands.", cmdName]);
        return;
    }

    entry.handler(args, output);
}

#pragma mark - Completion

- (NSArray<NSString *> *)completionsForPartial:(NSString *)partial {
    if (!partial.length) return @[];

    NSString *lower = partial.lowercaseString;
    NSMutableArray<NSString *> *results = [NSMutableArray array];

    // Match registered commands
    for (NSString *name in self.commands) {
        if ([name hasPrefix:lower]) {
            [results addObject:name];
        }
    }

    // Match aliases
    for (NSString *alias in [VCAliasManager shared].allAliases) {
        if ([alias.lowercaseString hasPrefix:lower]) {
            [results addObject:alias];
        }
    }

    [results sortUsingSelector:@selector(compare:)];
    return [results copy];
}

#pragma mark - Help

- (NSArray<NSDictionary *> *)allCommandsHelp {
    NSMutableArray *result = [NSMutableArray array];
    NSArray *sorted = [[self.commands allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *key in sorted) {
        VCCommandEntry *entry = self.commands[key];
        [result addObject:@{@"name": entry.name, @"help": entry.helpText}];
    }
    return [result copy];
}

#pragma mark - History

- (void)addToHistory:(NSString *)command {
    if (!command.length) return;
    [self.history addObject:command];
    while (self.history.count > kVCMaxHistory) {
        [self.history removeObjectAtIndex:0];
    }
}

- (NSArray<NSString *> *)commandHistory {
    return [self.history copy];
}

- (void)clearHistory {
    [self.history removeAllObjects];
}

#pragma mark - Builtin Commands

- (void)_registerBuiltinCommands {
    __weak __typeof__(self) weakSelf = self;

    // help [command]
    [self registerCommand:@"help" help:@"Show available commands or help for a specific command" handler:^(NSArray<NSString *> *args, VCCommandOutput output) {
        __strong __typeof__(weakSelf) self = weakSelf;
        if (!self) return;

        if (args.count > 0) {
            NSString *target = args[0].lowercaseString;
            VCCommandEntry *entry = self.commands[target];
            if (entry) {
                output([NSString stringWithFormat:@"%@  -- %@", entry.name, entry.helpText]);
            } else {
                output([NSString stringWithFormat:@"Unknown command: %@. Type 'help' for available commands.", target]);
            }
            return;
        }

        NSArray *sorted = [[self.commands allKeys] sortedArrayUsingSelector:@selector(compare:)];
        NSMutableString *text = [NSMutableString string];
        for (NSString *key in sorted) {
            VCCommandEntry *entry = self.commands[key];
            [text appendFormat:@"  %-14s -- %@\n", entry.name.UTF8String, entry.helpText];
        }
        output(text);
    }];

    // clear
    [self registerCommand:@"clear" help:@"Clear console output" handler:^(NSArray<NSString *> *args, VCCommandOutput output) {
        output(@"\x1B[CLEAR]");
    }];

    // export [format]
    [self registerCommand:@"export" help:@"Export command history (json|txt)" handler:^(NSArray<NSString *> *args, VCCommandOutput output) {
        __strong __typeof__(weakSelf) self = weakSelf;
        if (!self) return;

        NSString *format = (args.count > 0) ? args[0].lowercaseString : @"json";
        NSArray<NSString *> *hist = [self commandHistory];

        if ([format isEqualToString:@"txt"]) {
            output([hist componentsJoinedByString:@"\n"]);
        } else {
            NSError *err = nil;
            NSData *data = [NSJSONSerialization dataWithJSONObject:hist options:NSJSONWritingPrettyPrinted error:&err];
            if (data) {
                output([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
            } else {
                output([NSString stringWithFormat:@"Export error: %@", err.localizedDescription]);
            }
        }
    }];

    // alias
    [self registerCommand:@"alias" help:@"Manage command aliases (alias / alias <name> <cmd> / alias -d <name>)" handler:^(NSArray<NSString *> *args, VCCommandOutput output) {
        VCAliasManager *mgr = [VCAliasManager shared];

        if (args.count == 0) {
            NSDictionary *all = [mgr allAliases];
            if (all.count == 0) {
                output(@"No aliases defined.");
                return;
            }
            NSMutableString *text = [NSMutableString string];
            for (NSString *key in [all.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
                [text appendFormat:@"  %@ -> %@\n", key, all[key]];
            }
            output(text);
            return;
        }

        if (args.count == 2 && [args[0] isEqualToString:@"-d"]) {
            [mgr removeAlias:args[1]];
            output([NSString stringWithFormat:@"Alias '%@' removed.", args[1]]);
            return;
        }

        if (args.count >= 2) {
            NSString *name = args[0];
            NSString *cmd = [[args subarrayWithRange:NSMakeRange(1, args.count - 1)]
                             componentsJoinedByString:@" "];
            [mgr setAlias:name command:cmd];
            output([NSString stringWithFormat:@"Alias '%@' -> '%@'", name, cmd]);
            return;
        }

        output(@"Usage: alias <name> <command> | alias -d <name>");
    }];

    // shortcut
    [self registerCommand:@"shortcut" help:@"Manage shortcuts (list/save/run/del)" handler:^(NSArray<NSString *> *args, VCCommandOutput output) {
        VCAliasManager *mgr = [VCAliasManager shared];

        if (args.count == 0 || [args[0] isEqualToString:@"list"]) {
            NSDictionary *all = [mgr allShortcuts];
            if (all.count == 0) {
                output(@"No shortcuts defined.");
                return;
            }
            NSMutableString *text = [NSMutableString string];
            for (NSString *key in [all.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
                [text appendFormat:@"  %@ -> %@\n", key, all[key]];
            }
            output(text);
            return;
        }

        NSString *sub = args[0].lowercaseString;

        if ([sub isEqualToString:@"save"] && args.count >= 3) {
            NSString *name = args[1];
            NSString *tmpl = [[args subarrayWithRange:NSMakeRange(2, args.count - 2)]
                              componentsJoinedByString:@" "];
            [mgr setShortcut:name template:tmpl];
            output([NSString stringWithFormat:@"Shortcut '%@' saved: %@", name, tmpl]);
            return;
        }

        if ([sub isEqualToString:@"run"] && args.count >= 2) {
            // Handled by resolveInput in executeCommand path
            // But if called directly via handler, expand and execute
            __strong __typeof__(weakSelf) self = weakSelf;
            NSString *scName = args[1];
            NSArray<NSString *> *scArgs = args.count > 2
                ? [args subarrayWithRange:NSMakeRange(2, args.count - 2)]
                : @[];
            NSString *expanded = [mgr expandShortcut:scName args:scArgs];
            if (expanded) {
                [self executeCommand:expanded output:output];
            } else {
                output([NSString stringWithFormat:@"Unknown shortcut: %@", scName]);
            }
            return;
        }

        if ([sub isEqualToString:@"del"] && args.count >= 2) {
            [mgr removeShortcut:args[1]];
            output([NSString stringWithFormat:@"Shortcut '%@' deleted.", args[1]]);
            return;
        }

        output(@"Usage: shortcut list | save <name> <template> | run <name> [args] | del <name>");
    }];
}

#pragma mark - Placeholder Commands (for completion only)

- (void)_registerPlaceholderCommands {
    // Runtime (Slide-1)
    NSArray *placeholders = @[
        @[@"classes",   @"List classes in target process"],
        @[@"methods",   @"List methods of a class"],
        @[@"ivars",     @"List instance variables of a class"],
        @[@"props",     @"List properties of a class"],
        @[@"protocols", @"List protocols of a class"],
        @[@"supers",    @"Show superclass chain"],
        @[@"strings",   @"Search strings in memory"],
        @[@"instances", @"Find live instances of a class"],
        @[@"ivar",      @"Read/write instance variable value"],
        // Process (Slide-2)
        @[@"proc",      @"Process information"],
        // Network (Slide-3)
        @[@"net",       @"Network monitoring"],
        // UI (Slide-4)
        @[@"ui",        @"UI inspection"],
        // AI (Slide-5)
        @[@"ask",       @"Ask AI a question"],
        @[@"model",     @"AI model management"],
        // Hook (Slide-12)
        @[@"hook",      @"Hook a method"],
        @[@"unhook",    @"Remove a hook"],
        @[@"hooks",     @"List active hooks"],
    ];

    for (NSArray *entry in placeholders) {
        NSString *name = entry[0];
        NSString *help = entry[1];
        // Only register if not already registered (don't overwrite real handlers)
        if (!self.commands[name]) {
            VCCommandEntry *e = [[VCCommandEntry alloc] init];
            e.name = name;
            e.helpText = help;
            e.handler = ^(NSArray<NSString *> *args, VCCommandOutput output) {
                output([NSString stringWithFormat:@"'%@' is not yet connected. This command will be available after engine integration.", name]);
            };
            self.commands[name] = e;
        }
    }
}

@end
