#import "VCAliasManager.h"
#import "VCConsole.h"

static NSString *const kVCAliasesKey   = @"com.vanson.cli.aliases";
static NSString *const kVCShortcutsKey = @"com.vanson.cli.shortcuts";
static const NSUInteger kVCMaxAliasDepth = 10;

@interface VCAliasManager ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *aliases;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *shortcuts;
@end

@implementation VCAliasManager

+ (instancetype)shared {
    static VCAliasManager *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VCAliasManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSDictionary *saved = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kVCAliasesKey];
        _aliases = saved ? [saved mutableCopy] : [NSMutableDictionary dictionary];

        NSDictionary *savedSC = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kVCShortcutsKey];
        _shortcuts = savedSC ? [savedSC mutableCopy] : [NSMutableDictionary dictionary];
    }
    return self;
}

#pragma mark - Persistence

- (void)_saveAliases {
    [[NSUserDefaults standardUserDefaults] setObject:[self.aliases copy] forKey:kVCAliasesKey];
}

- (void)_saveShortcuts {
    [[NSUserDefaults standardUserDefaults] setObject:[self.shortcuts copy] forKey:kVCShortcutsKey];
}

#pragma mark - Aliases

- (void)setAlias:(NSString *)name command:(NSString *)command {
    if (!name.length || !command.length) return;

    // Cycle detection: follow alias chain up to kVCMaxAliasDepth
    NSString *target = command;
    NSMutableSet *visited = [NSMutableSet setWithObject:name];
    for (NSUInteger depth = 0; depth < kVCMaxAliasDepth; depth++) {
        // Parse first word of target
        NSDictionary *parsed = [VCConsole parseCommand:target];
        if (!parsed) break;
        NSString *firstWord = parsed[@"command"];
        if ([visited containsObject:firstWord]) {
            // Cycle detected - do not create
            return;
        }
        NSString *next = self.aliases[firstWord];
        if (!next) break;
        [visited addObject:firstWord];
        target = next;
    }

    self.aliases[name] = command;
    [self _saveAliases];
}

- (void)removeAlias:(NSString *)name {
    if (!name.length) return;
    [self.aliases removeObjectForKey:name];
    [self _saveAliases];
}

- (NSDictionary<NSString *, NSString *> *)allAliases {
    return [self.aliases copy];
}

#pragma mark - Shortcuts

- (void)setShortcut:(NSString *)name template:(NSString *)tmpl {
    if (!name.length || !tmpl.length) return;
    self.shortcuts[name] = tmpl;
    [self _saveShortcuts];
}

- (void)removeShortcut:(NSString *)name {
    if (!name.length) return;
    [self.shortcuts removeObjectForKey:name];
    [self _saveShortcuts];
}

- (NSDictionary<NSString *, NSString *> *)allShortcuts {
    return [self.shortcuts copy];
}

- (NSString *)expandShortcut:(NSString *)name args:(NSArray<NSString *> *)args {
    NSString *tmpl = self.shortcuts[name];
    if (!tmpl) return nil;

    NSMutableString *result = [tmpl mutableCopy];
    for (NSUInteger i = 0; i < args.count; i++) {
        NSString *placeholder = [NSString stringWithFormat:@"$%lu", (unsigned long)(i + 1)];
        [result replaceOccurrencesOfString:placeholder
                                withString:args[i]
                                   options:NSLiteralSearch
                                     range:NSMakeRange(0, result.length)];
    }
    return [result copy];
}

#pragma mark - Resolve

- (NSString *)resolveInput:(NSString *)rawInput {
    if (!rawInput.length) return rawInput;

    NSDictionary *parsed = [VCConsole parseCommand:rawInput];
    if (!parsed) return rawInput;

    NSString *firstWord = parsed[@"command"];
    NSArray<NSString *> *args = parsed[@"args"];

    // 1. Check alias
    NSString *aliasTarget = self.aliases[firstWord];
    if (aliasTarget) {
        if (args.count > 0) {
            return [NSString stringWithFormat:@"%@ %@",
                    aliasTarget, [args componentsJoinedByString:@" "]];
        }
        return aliasTarget;
    }

    // 2. Check shortcut run: "shortcut run <name> [args...]"
    if ([firstWord isEqualToString:@"shortcut"] && args.count >= 2 &&
        [args[0] isEqualToString:@"run"]) {
        NSString *scName = args[1];
        NSArray<NSString *> *scArgs = args.count > 2
            ? [args subarrayWithRange:NSMakeRange(2, args.count - 2)]
            : @[];
        NSString *expanded = [self expandShortcut:scName args:scArgs];
        if (expanded) return expanded;
    }

    return rawInput;
}

@end
