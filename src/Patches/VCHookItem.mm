/**
 * VCHookItem -- 动态 Hook 模型
 */

#import "VCHookItem.h"

@implementation VCHookItem

- (instancetype)init {
    if (self = [super init]) {
        _hookID = [[NSUUID UUID] UUIDString];
        _hookType = @"log";
        _enabled = YES;
        _isClassMethod = NO;
        _hitCount = 0;
        _source = VCItemSourceManual;
        _isDisabledBySafeMode = NO;
        _createdAt = [NSDate date];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:_hookID forKey:@"hookID"];
    [coder encodeObject:_className forKey:@"className"];
    [coder encodeObject:_selector forKey:@"selector"];
    [coder encodeObject:_hookType forKey:@"hookType"];
    [coder encodeObject:_remark forKey:@"remark"];
    [coder encodeBool:_enabled forKey:@"enabled"];
    [coder encodeBool:_isClassMethod forKey:@"isClassMethod"];
    [coder encodeObject:@(_hitCount) forKey:@"hitCount"];
    [coder encodeInteger:_source forKey:@"source"];
    [coder encodeObject:_sourceToolID forKey:@"sourceToolID"];
    [coder encodeBool:_isDisabledBySafeMode forKey:@"isDisabledBySafeMode"];
    [coder encodeObject:_createdAt forKey:@"createdAt"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super init]) {
        _hookID = [coder decodeObjectForKey:@"hookID"];
        _className = [coder decodeObjectForKey:@"className"];
        _selector = [coder decodeObjectForKey:@"selector"];
        _hookType = [coder decodeObjectForKey:@"hookType"];
        _remark = [coder decodeObjectForKey:@"remark"];
        _enabled = [coder decodeBoolForKey:@"enabled"];
        _isClassMethod = [coder decodeBoolForKey:@"isClassMethod"];
        _hitCount = [[coder decodeObjectForKey:@"hitCount"] unsignedIntegerValue];
        _source = (VCItemSource)[coder decodeIntegerForKey:@"source"];
        _sourceToolID = [coder decodeObjectForKey:@"sourceToolID"];
        _isDisabledBySafeMode = [coder decodeBoolForKey:@"isDisabledBySafeMode"];
        _createdAt = [coder decodeObjectForKey:@"createdAt"];
    }
    return self;
}

@end
