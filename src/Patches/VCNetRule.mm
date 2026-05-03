/**
 * VCNetRule -- 网络拦截规则模型
 */

#import "VCNetRule.h"

@implementation VCNetRule

- (instancetype)init {
    if (self = [super init]) {
        _ruleID = [[NSUUID UUID] UUIDString];
        _action = @"block";
        _enabled = YES;
        _source = VCItemSourceManual;
        _isDisabledBySafeMode = NO;
        _createdAt = [NSDate date];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:_ruleID forKey:@"ruleID"];
    [coder encodeObject:_urlPattern forKey:@"urlPattern"];
    [coder encodeObject:_action forKey:@"action"];
    [coder encodeObject:_modifications forKey:@"modifications"];
    [coder encodeBool:_enabled forKey:@"enabled"];
    [coder encodeObject:_remark forKey:@"remark"];
    [coder encodeInteger:_source forKey:@"source"];
    [coder encodeObject:_sourceToolID forKey:@"sourceToolID"];
    [coder encodeBool:_isDisabledBySafeMode forKey:@"isDisabledBySafeMode"];
    [coder encodeObject:_createdAt forKey:@"createdAt"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super init]) {
        _ruleID = [coder decodeObjectForKey:@"ruleID"];
        _urlPattern = [coder decodeObjectForKey:@"urlPattern"];
        _action = [coder decodeObjectForKey:@"action"];
        _modifications = [coder decodeObjectForKey:@"modifications"];
        _enabled = [coder decodeBoolForKey:@"enabled"];
        _remark = [coder decodeObjectForKey:@"remark"];
        _source = (VCItemSource)[coder decodeIntegerForKey:@"source"];
        _sourceToolID = [coder decodeObjectForKey:@"sourceToolID"];
        _isDisabledBySafeMode = [coder decodeBoolForKey:@"isDisabledBySafeMode"];
        _createdAt = [coder decodeObjectForKey:@"createdAt"];
    }
    return self;
}

@end
