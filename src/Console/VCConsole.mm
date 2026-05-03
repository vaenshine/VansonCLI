#import "VCConsole.h"

@implementation VCConsole

+ (NSDictionary *)parseCommand:(NSString *)rawInput {
    if (!rawInput) return nil;

    NSString *trimmed = [rawInput stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) return nil;

    NSMutableArray<NSString *> *tokens = [NSMutableArray array];
    NSMutableString *current = [NSMutableString string];
    unichar quoteChar = 0;
    BOOL inQuote = NO;

    for (NSUInteger i = 0; i < trimmed.length; i++) {
        unichar c = [trimmed characterAtIndex:i];

        if (inQuote) {
            if (c == quoteChar) {
                inQuote = NO;
            } else {
                [current appendFormat:@"%C", c];
            }
        } else {
            if (c == '"' || c == '\'') {
                inQuote = YES;
                quoteChar = c;
            } else if (c == ' ' || c == '\t') {
                if (current.length > 0) {
                    [tokens addObject:[current copy]];
                    [current setString:@""];
                }
            } else {
                [current appendFormat:@"%C", c];
            }
        }
    }

    // Unmatched quote: flush remaining as-is
    if (current.length > 0) {
        [tokens addObject:[current copy]];
    }

    if (tokens.count == 0) return nil;

    NSString *command = tokens[0];
    NSArray<NSString *> *args = tokens.count > 1
        ? [tokens subarrayWithRange:NSMakeRange(1, tokens.count - 1)]
        : @[];

    return @{@"command": command, @"args": args};
}

@end
