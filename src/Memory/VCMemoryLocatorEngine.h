/**
 * VCMemoryLocatorEngine -- pointer chains, signatures, and address resolution
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface VCMemoryLocatorEngine : NSObject

+ (instancetype)shared;

- (NSDictionary * _Nullable)resolvePointerChainWithModuleName:(NSString * _Nullable)moduleName
                                                  baseAddress:(uint64_t)baseAddress
                                                   baseOffset:(uint64_t)baseOffset
                                                      offsets:(NSArray<NSNumber *> *)offsets
                                                 errorMessage:(NSString * _Nullable * _Nullable)errorMessage;

- (NSDictionary * _Nullable)readPointerChainWithModuleName:(NSString * _Nullable)moduleName
                                               baseAddress:(uint64_t)baseAddress
                                                baseOffset:(uint64_t)baseOffset
                                                   offsets:(NSArray<NSNumber *> *)offsets
                                            dataTypeString:(NSString *)dataTypeString
                                              errorMessage:(NSString * _Nullable * _Nullable)errorMessage;

- (NSDictionary * _Nullable)scanSignature:(NSString *)signature
                               moduleName:(NSString * _Nullable)moduleName
                                    limit:(NSUInteger)limit
                             errorMessage:(NSString * _Nullable * _Nullable)errorMessage;

- (NSDictionary * _Nullable)resolveSignature:(NSString *)signature
                                  moduleName:(NSString * _Nullable)moduleName
                                      offset:(int64_t)offset
                            dataTypeString:(NSString * _Nullable)dataTypeString
                                resultLimit:(NSUInteger)resultLimit
                                errorMessage:(NSString * _Nullable * _Nullable)errorMessage;

- (NSDictionary * _Nullable)resolveAddressAction:(NSString *)action
                                      moduleName:(NSString * _Nullable)moduleName
                                            rva:(uint64_t)rva
                                        address:(uint64_t)address
                                   errorMessage:(NSString * _Nullable * _Nullable)errorMessage;

- (NSDictionary * _Nullable)findPointerReferencesToAddress:(uint64_t)address
                                                     limit:(NSUInteger)limit
                                          includeSecondHop:(BOOL)includeSecondHop
                                              errorMessage:(NSString * _Nullable * _Nullable)errorMessage;

@end

NS_ASSUME_NONNULL_END
