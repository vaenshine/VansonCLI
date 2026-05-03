/**
 * VCValueItem -- 内存值修改模型
 */

#import "VCValueItem.h"

@implementation VCValueItem

- (instancetype)init {
    if (self = [super init]) {
        _valueID = [[NSUUID UUID] UUIDString];
        _dataType = @"int";
        _locked = NO;
        _source = VCItemSourceManual;
        _isDisabledBySafeMode = NO;
        _createdAt = [NSDate date];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:_valueID forKey:@"valueID"];
    [coder encodeObject:_targetDesc forKey:@"targetDesc"];
    [coder encodeObject:@(_address) forKey:@"address"];
    [coder encodeObject:@(_offset) forKey:@"offset"];
    [coder encodeObject:_dataType forKey:@"dataType"];
    [coder encodeObject:_originalValue forKey:@"originalValue"];
    [coder encodeObject:_modifiedValue forKey:@"modifiedValue"];
    [coder encodeBool:_locked forKey:@"locked"];
    [coder encodeObject:_remark forKey:@"remark"];
    [coder encodeInteger:_source forKey:@"source"];
    [coder encodeObject:_sourceToolID forKey:@"sourceToolID"];
    [coder encodeBool:_isDisabledBySafeMode forKey:@"isDisabledBySafeMode"];
    [coder encodeObject:_createdAt forKey:@"createdAt"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super init]) {
        _valueID = [coder decodeObjectForKey:@"valueID"];
        _targetDesc = [coder decodeObjectForKey:@"targetDesc"];
        _address = [[coder decodeObjectForKey:@"address"] unsignedLongLongValue];
        _offset = [[coder decodeObjectForKey:@"offset"] longLongValue];
        _dataType = [coder decodeObjectForKey:@"dataType"];
        _originalValue = [coder decodeObjectForKey:@"originalValue"];
        _modifiedValue = [coder decodeObjectForKey:@"modifiedValue"];
        _locked = [coder decodeBoolForKey:@"locked"];
        _remark = [coder decodeObjectForKey:@"remark"];
        _source = (VCItemSource)[coder decodeIntegerForKey:@"source"];
        _sourceToolID = [coder decodeObjectForKey:@"sourceToolID"];
        _isDisabledBySafeMode = [coder decodeBoolForKey:@"isDisabledBySafeMode"];
        _createdAt = [coder decodeObjectForKey:@"createdAt"];
    }
    return self;
}

@end
