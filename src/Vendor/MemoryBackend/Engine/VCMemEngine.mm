/**
 * VansonCLI Memory Backend - Memory Engine Implementation
 * ObjC 桥接层实现 (简化版：仅内存搜索)
 */

#import "VCMemEngine.h"
#import "../Core/VCMemCore.hpp"
#import <mach-o/dyld.h>
#include <memory>
#include <cmath>

@implementation VCMemResultItem
@end

@interface VCMemEngine () {
    std::unique_ptr<vcore::MemCore> _core;
}
@end

@implementation VCMemEngine

+ (instancetype)shared {
    static VCMemEngine *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VCMemEngine alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _core = std::make_unique<vcore::MemCore>();

        NSString *tmpDir = NSTemporaryDirectory();
        NSString *pathA = [tmpDir stringByAppendingPathComponent:@"vcmem_scan_a.bin"];
        NSString *pathB = [tmpDir stringByAppendingPathComponent:@"vcmem_scan_b.bin"];
        _core->setStoragePath([pathA UTF8String], [pathB UTF8String]);

        _core->setFloatTolerance(0.001);
        _core->setGroupSearchRange(200);
        _core->setGroupAnchorMode(false);
    }
    return self;
}

- (void)dealloc {
    if (_core) {
        _core->clearResults();
    }
    NSString *tmpDir = NSTemporaryDirectory();
    [[NSFileManager defaultManager] removeItemAtPath:[tmpDir stringByAppendingPathComponent:@"vcmem_scan_a.bin"] error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:[tmpDir stringByAppendingPathComponent:@"vcmem_scan_b.bin"] error:nil];
}

- (void)initialize {
    static dispatch_once_t initOnce;
    dispatch_once(&initOnce, ^{
        _core->init();


    });
}

- (BOOL)isReady {
    return _core && _core->isReady();
}

#pragma mark - 配置

- (void)setFloatTolerance:(double)floatTolerance {
    _floatTolerance = floatTolerance;
    _core->setFloatTolerance(floatTolerance);
}

- (void)setGroupSearchRange:(uint64_t)groupSearchRange {
    _groupSearchRange = groupSearchRange;
    _core->setGroupSearchRange(groupSearchRange);
}

- (void)setGroupAnchorMode:(BOOL)groupAnchorMode {
    _groupAnchorMode = groupAnchorMode;
    _core->setGroupAnchorMode(groupAnchorMode);
}

- (void)setResultLimit:(NSUInteger)resultLimit {
    _resultLimit = resultLimit;
    _core->setResultLimit(resultLimit);
}

#pragma mark - 类型转换

static vcore::MemDataType toMemDataType(VCMemDataType type) {
    return static_cast<vcore::MemDataType>(type);
}

#pragma mark - 内存搜索

- (void)scanWithMode:(VCMemSearchMode)mode
              value:(NSString *)valueStr
               type:(VCMemDataType)type
         completion:(void (^)(NSUInteger, NSString *))completion {

    if (!_core->isReady()) {
        if (completion) completion(0, @"Engine not initialized");
        return;
    }


    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        vcore::MemDataType coreType = toMemDataType(type);
        std::string cValStr = [valueStr UTF8String] ?: "";

        self->_core->scan(coreType, cValStr, (int)mode, 0, 0);
        NSUInteger count = self->_core->getResultCount();

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                NSString *msg = count > 0 ? @"Search completed" : @"No results found";
                completion(count, msg);
            }
        });
    });
}

- (void)nextScanWithValue:(NSString *)valueStr
                     type:(VCMemDataType)type
               filterMode:(VCMemFilterMode)mode
               completion:(void (^)(NSUInteger, NSString *))completion {

    if (!_core->isReady()) {
        if (completion) completion(0, @"Engine not initialized");
        return;
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        vcore::MemDataType coreType = toMemDataType(type);
        std::string cValStr = [valueStr UTF8String] ?: "";

        int searchMode = 6;
        switch (mode) {
            case VCMemFilterModeDecreased: searchMode = 0; break;
            case VCMemFilterModeIncreased: searchMode = 1; break;
            case VCMemFilterModeChanged: searchMode = 5; break;
            case VCMemFilterModeUnchanged: searchMode = 6; break;
            default: searchMode = 100; break;
        }

        self->_core->nextScan(coreType, cValStr, searchMode);
        NSUInteger count = self->_core->getResultCount();

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                NSString *msg = count > 0 ? @"Filter completed" : @"No results found";
                completion(count, msg);
            }
        });
    });
}

- (void)scanNearbyWithValue:(NSString *)valueStr
                       type:(VCMemDataType)type
                      range:(uint64_t)range
                 completion:(void (^)(NSUInteger, NSString *))completion {

    if (!_core->isReady()) {
        if (completion) completion(0, @"Engine not initialized");
        return;
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        vcore::MemDataType coreType = toMemDataType(type);
        std::string cValStr = [valueStr UTF8String] ?: "";

        self->_core->scanNearby(coreType, cValStr, range);
        NSUInteger count = self->_core->getResultCount();

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                NSString *msg = count > 0 ? @"Nearby search completed" : @"No results found";
                completion(count, msg);
            }
        });
    });
}

- (void)filterResultsWithMode:(VCMemFilterMode)mode
                        val1:(NSString *)v1
                        val2:(NSString *)v2
                        type:(VCMemDataType)type
                  completion:(void (^)(NSUInteger, NSString *))completion {

    if (!_core->isReady()) {
        if (completion) completion(0, @"Engine not initialized");
        return;
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        vcore::MemDataType coreType = toMemDataType(type);
        vcore::FilterMode coreMode = static_cast<vcore::FilterMode>(mode);
        std::string s1 = [v1 UTF8String] ?: "";
        std::string s2 = [v2 UTF8String] ?: "";

        self->_core->filterResults(coreMode, coreType, s1, s2);
        NSUInteger count = self->_core->getResultCount();

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                NSString *msg = count > 0 ? @"Filter completed" : @"No results found";
                completion(count, msg);
            }
        });
    });
}

#pragma mark - 结果管理

- (NSUInteger)resultCount {
    return _core->getResultCount();
}

- (VCMemResultItem *)getResultAtIndex:(NSUInteger)index type:(VCMemDataType)type {
    if (index >= _core->getResultCount()) return nil;

    auto results = _core->getResults(index, 1);
    if (results.empty()) return nil;

    auto& cppItem = results[0];
    VCMemResultItem *item = [VCMemResultItem new];
    item.address = cppItem.address;
    item.type = (VCMemDataType)cppItem.type;

    size_t sz = vcore::getSizeForType(cppItem.type);
    if (cppItem.type == vcore::MemDataType::String) {
        // String: read up to 128 bytes from memory
        uint8_t strBuf[129] = {0};
        size_t readLen = 128;
        if (_core->readMem(cppItem.address, strBuf, readLen)) {
            strBuf[128] = 0;
            size_t len = strnlen((char*)strBuf, 128);
            NSString *str = [[NSString alloc] initWithBytes:strBuf length:len encoding:NSUTF8StringEncoding];
            if (!str) {
                // Fallback: try ASCII, replace non-printable
                NSMutableString *ascii = [NSMutableString string];
                for (size_t i = 0; i < len && i < 128; i++) {
                    uint8_t c = strBuf[i];
                    if (c >= 32 && c < 127) [ascii appendFormat:@"%c", c];
                    else [ascii appendString:@"."];
                }
                str = ascii;
            }
            item.valueStr = str;
        } else {
            item.valueStr = @"(Err)";
        }
        item.prevValue = @(0);
    } else if (vcore::isFloatType(cppItem.type)) {
        double val;
        if (sz == 4) {
            float temp;
            memcpy(&temp, &cppItem.value, 4);
            val = temp;
        } else {
            memcpy(&val, &cppItem.value, 8);
        }
        item.prevValue = @(val);
        item.valueStr = [NSString stringWithFormat:@"%.4f", val];
    } else {
        long long val = 0;
        memcpy(&val, &cppItem.value, sz > 8 ? 8 : sz);
        item.prevValue = @(val);
        item.valueStr = [NSString stringWithFormat:@"%lld", val];
    }

    return item;
}

- (void)removeResultAtIndex:(NSUInteger)index {
    _core->removeResult(index);
}

- (void)clearResults {
    _core->clearResults();
}

- (void)batchModifyWithValue:(NSString *)value
                       limit:(NSInteger)limit
                        type:(VCMemDataType)type
                        mode:(int)mode {
    vcore::MemDataType coreType = toMemDataType(type);
    std::string cVal = [value UTF8String] ?: "";
    _core->batchModify(cVal, (int)limit, coreType, mode);
}

#pragma mark - 内存读写

- (NSString *)readAddress:(uint64_t)address type:(VCMemDataType)type {
    if (address < 0x10000 || address > 0x800000000000ULL) return @"(Null)";

    uint8_t buf[8] = {0};
    size_t sz = vcore::getSizeForType(toMemDataType(type));

    if (!_core->readMem(address, buf, sz)) return @"(Err)";

    switch (type) {
        case VCMemDataTypeI8:  return [NSString stringWithFormat:@"%d", *(int8_t*)buf];
        case VCMemDataTypeU8:  return [NSString stringWithFormat:@"%u", *(uint8_t*)buf];
        case VCMemDataTypeI16: return [NSString stringWithFormat:@"%d", *(int16_t*)buf];
        case VCMemDataTypeU16: return [NSString stringWithFormat:@"%u", *(uint16_t*)buf];
        case VCMemDataTypeI32: return [NSString stringWithFormat:@"%d", *(int32_t*)buf];
        case VCMemDataTypeU32: return [NSString stringWithFormat:@"%u", *(uint32_t*)buf];
        case VCMemDataTypeI64: return [NSString stringWithFormat:@"%lld", *(int64_t*)buf];
        case VCMemDataTypeU64: return [NSString stringWithFormat:@"%llu", *(uint64_t*)buf];
        case VCMemDataTypeF32: return [NSString stringWithFormat:@"%.4f", *(float*)buf];
        case VCMemDataTypeF64: return [NSString stringWithFormat:@"%.4lf", *(double*)buf];
        case VCMemDataTypeString: {
            uint8_t strBuf[129] = {0};
            if (_core->readMem(address, strBuf, 128)) {
                strBuf[128] = 0;
                size_t len = strnlen((char*)strBuf, 128);
                NSString *str = [[NSString alloc] initWithBytes:strBuf length:len encoding:NSUTF8StringEncoding];
                if (!str) {
                    NSMutableString *ascii = [NSMutableString string];
                    for (size_t i = 0; i < len && i < 128; i++) {
                        uint8_t c = strBuf[i];
                        if (c >= 32 && c < 127) [ascii appendFormat:@"%c", c];
                        else [ascii appendString:@"."];
                    }
                    str = ascii;
                }
                return str.length > 0 ? str : @"(empty)";
            }
            return @"(Err)";
        }
        default: return @"?";
    }
}

- (BOOL)writeAddress:(uint64_t)address value:(NSString *)value type:(VCMemDataType)type {
    if (!value || value.length == 0) return NO;
    if (address < 0x10000 || address > 0x800000000000ULL) return NO;

    uint8_t buf[8] = {0};
    size_t sz = vcore::getSizeForType(toMemDataType(type));

    switch (type) {
        case VCMemDataTypeI8:  { int8_t v = [value intValue]; memcpy(buf, &v, 1); break; }
        case VCMemDataTypeU8:  { uint8_t v = [value intValue]; memcpy(buf, &v, 1); break; }
        case VCMemDataTypeI16: { int16_t v = [value intValue]; memcpy(buf, &v, 2); break; }
        case VCMemDataTypeU16: { uint16_t v = [value intValue]; memcpy(buf, &v, 2); break; }
        case VCMemDataTypeI32: { int32_t v = [value intValue]; memcpy(buf, &v, 4); break; }
        case VCMemDataTypeU32: { uint32_t v = (uint32_t)[value longLongValue]; memcpy(buf, &v, 4); break; }
        case VCMemDataTypeI64: { int64_t v = [value longLongValue]; memcpy(buf, &v, 8); break; }
        case VCMemDataTypeU64: { uint64_t v = strtoull([value UTF8String], NULL, 10); memcpy(buf, &v, 8); break; }
        case VCMemDataTypeF32: { float v = [value floatValue]; memcpy(buf, &v, 4); break; }
        case VCMemDataTypeF64: { double v = [value doubleValue]; memcpy(buf, &v, 8); break; }
        case VCMemDataTypeString: {
            const char *cstr = [value UTF8String];
            size_t len = strlen(cstr);
            return _core->writeMem(address, cstr, len);
        }
        default: return NO;
    }

    return _core->writeMem(address, buf, sz);
}

- (NSData *)readMemory:(uint64_t)address length:(size_t)length {
    if (address == 0 || length == 0) return nil;

    void *buffer = malloc(length);
    if (!buffer) return nil;

    if (_core->readMem(address, buffer, length)) {
        return [NSData dataWithBytesNoCopy:buffer length:length freeWhenDone:YES];
    }

    free(buffer);
    return nil;
}

- (BOOL)writeMemory:(uint64_t)address data:(NSData *)data {
    if (address == 0 || !data || data.length == 0) return NO;
    return _core->writeMem(address, data.bytes, data.length);
}

#pragma mark - 特征码搜索

- (void)scanSignature:(NSString *)signature
           rangeStart:(uint64_t)start
             rangeEnd:(uint64_t)end
           completion:(void (^)(NSArray<VCMemResultItem *> *))completion {

    if (!_core->isReady() || !signature || signature.length == 0) {
        if (completion) completion(@[]);
        return;
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        auto results = self->_core->scanSignature([signature UTF8String], start, end);

        NSMutableArray<VCMemResultItem *> *items = [NSMutableArray array];
        for (const auto& res : results) {
            VCMemResultItem *item = [VCMemResultItem new];
            item.address = res.address;
            item.type = VCMemDataTypeI8;
            [items addObject:item];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(items);
        });
    });
}

#pragma mark - 快速模糊搜索

- (void)fastFuzzyInitWithCompletion:(void (^)(BOOL, NSString *, NSUInteger))completion {
    if (!_core->isReady()) {
        if (completion) completion(NO, @"Engine not initialized", 0);
        return;
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        self->_core->fastFuzzyInit();
        NSUInteger count = self->_core->getFastFuzzyAddressCount();

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(YES, @"Snapshot created", count);
            }
        });
    });
}

- (BOOL)hasFastFuzzySnapshot {
    return _core->hasFastFuzzySnapshot();
}

- (void)fastFuzzyFilterWithMode:(VCMemFilterMode)mode
                           type:(VCMemDataType)type
                     completion:(void (^)(NSUInteger, NSString *))completion {

    if (!_core->isReady()) {
        if (completion) completion(0, @"Engine not initialized");
        return;
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        vcore::MemDataType coreType = toMemDataType(type);

        // 映射ObjC层的VCMemFilterMode到C++层的filterMode
        // C++层: 0=变小, 1=变大, 5=变化, 6=无变化
        // ObjC层: VCMemFilterModeIncreased=3, VCMemFilterModeDecreased=4, VCMemFilterModeChanged=5, VCMemFilterModeUnchanged=6
        int filterMode = 5; // 默认变化
        switch (mode) {
            case VCMemFilterModeDecreased: filterMode = 0; break;  // 变小
            case VCMemFilterModeIncreased: filterMode = 1; break;  // 变大
            case VCMemFilterModeChanged:   filterMode = 5; break;  // 变化
            case VCMemFilterModeUnchanged: filterMode = 6; break;  // 无变化
            default: filterMode = 5; break;
        }

        self->_core->fastFuzzyFilter(coreType, filterMode, 0, 0);
        NSUInteger count = self->_core->getResultCount();

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                NSString *msg = count > 0 ? @"Filter completed" : @"No results found";
                completion(count, msg);
            }
        });
    });
}

- (void)clearFastFuzzySnapshot {
    _core->clearFastFuzzySnapshot();
}

#pragma mark - 快照

- (void)takeSnapshot {
    _core->takeSnapshot(512 * 1024 * 1024);
}

- (void)clearSnapshot {
    _core->clearSnapshot();
}

- (void)saveBaselineSnapshot {
    _core->saveBaselineSnapshot();
}

- (void)clearBaselineSnapshot {
    _core->clearBaselineSnapshot();
}

- (BOOL)hasBaselineSnapshot {
    return _core->hasBaselineSnapshot();
}

@end
