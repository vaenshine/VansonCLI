/**
 * VCRuntimeModels.h -- Runtime introspection data models
 * Slide-1: Runtime Engine
 */

#import <Foundation/Foundation.h>

// ═══════════════════════════════════════════════════════════════
// VCMethodInfo
// ═══════════════════════════════════════════════════════════════
@interface VCMethodInfo : NSObject
@property (nonatomic, strong) NSString *selector;
@property (nonatomic, strong) NSString *typeEncoding;
@property (nonatomic, strong) NSString *decodedSignature;
@property (nonatomic, assign) uintptr_t impAddress;
@property (nonatomic, assign) uintptr_t rva;
@end

// ═══════════════════════════════════════════════════════════════
// VCIvarInfo
// ═══════════════════════════════════════════════════════════════
@interface VCIvarInfo : NSObject
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *typeEncoding;
@property (nonatomic, strong) NSString *decodedType;
@property (nonatomic, assign) ptrdiff_t offset;
@end

// ═══════════════════════════════════════════════════════════════
// VCPropertyInfo
// ═══════════════════════════════════════════════════════════════
@interface VCPropertyInfo : NSObject
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *attributes;
@property (nonatomic, strong) NSString *type;
@property (nonatomic, strong) NSString *getter;
@property (nonatomic, strong) NSString *setter;
@property (nonatomic, strong) NSString *ivarName;
@property (nonatomic, assign) BOOL isReadonly;
@property (nonatomic, assign) BOOL isWeak;
@property (nonatomic, assign) BOOL isNonatomic;
@end

// ═══════════════════════════════════════════════════════════════
// VCClassInfo
// ═══════════════════════════════════════════════════════════════
@interface VCClassInfo : NSObject
@property (nonatomic, strong) NSString *className;
@property (nonatomic, strong) NSString *moduleName;
@property (nonatomic, strong) NSString *superClassName;
@property (nonatomic, strong) NSArray<NSString *> *inheritanceChain;
@property (nonatomic, strong) NSArray<VCMethodInfo *> *instanceMethods;
@property (nonatomic, strong) NSArray<VCMethodInfo *> *classMethods;
@property (nonatomic, strong) NSArray<VCIvarInfo *> *ivars;
@property (nonatomic, strong) NSArray<VCPropertyInfo *> *properties;
@property (nonatomic, strong) NSArray<NSString *> *protocols;
@end

// ═══════════════════════════════════════════════════════════════
// VCStringResult
// ═══════════════════════════════════════════════════════════════
@interface VCStringResult : NSObject
@property (nonatomic, strong) NSString *value;
@property (nonatomic, strong) NSString *section;
@property (nonatomic, strong) NSString *moduleName;
@property (nonatomic, assign) uintptr_t address;
@property (nonatomic, assign) uintptr_t rva;
@end

// ═══════════════════════════════════════════════════════════════
// VCInstanceRecord
// ═══════════════════════════════════════════════════════════════
@interface VCInstanceRecord : NSObject
@property (nonatomic, strong) NSString *className;
@property (nonatomic, strong) NSString *briefDescription;
@property (nonatomic, assign) uintptr_t address;
@property (nonatomic, strong) NSDate *discoveredAt;
@property (nonatomic, weak) id instance;
@end
