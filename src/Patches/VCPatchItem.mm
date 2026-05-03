/**
 * VCPatchItem -- 方法补丁模型
 */

#import "VCPatchItem.h"

@implementation VCPatchItem

- (instancetype)init {
    if (self = [super init]) {
        _patchID = [[NSUUID UUID] UUIDString];
        _patchType = @"nop";
        _enabled = YES;
        _source = VCItemSourceManual;
        _isDisabledBySafeMode = NO;
        _createdAt = [NSDate date];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:_patchID forKey:@"patchID"];
    [coder encodeObject:_className forKey:@"className"];
    [coder encodeObject:_selector forKey:@"selector"];
    [coder encodeObject:_patchType forKey:@"patchType"];
    [coder encodeObject:_customCode forKey:@"customCode"];
    [coder encodeObject:_remark forKey:@"remark"];
    [coder encodeBool:_enabled forKey:@"enabled"];
    [coder encodeInteger:_source forKey:@"source"];
    [coder encodeObject:_sourceToolID forKey:@"sourceToolID"];
    [coder encodeBool:_isDisabledBySafeMode forKey:@"isDisabledBySafeMode"];
    [coder encodeObject:_createdAt forKey:@"createdAt"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super init]) {
        _patchID = [coder decodeObjectForKey:@"patchID"];
        _className = [coder decodeObjectForKey:@"className"];
        _selector = [coder decodeObjectForKey:@"selector"];
        _patchType = [coder decodeObjectForKey:@"patchType"];
        _customCode = [coder decodeObjectForKey:@"customCode"];
        _remark = [coder decodeObjectForKey:@"remark"];
        _enabled = [coder decodeBoolForKey:@"enabled"];
        _source = (VCItemSource)[coder decodeIntegerForKey:@"source"];
        _sourceToolID = [coder decodeObjectForKey:@"sourceToolID"];
        _isDisabledBySafeMode = [coder decodeBoolForKey:@"isDisabledBySafeMode"];
        _createdAt = [coder decodeObjectForKey:@"createdAt"];
    }
    return self;
}

@end
