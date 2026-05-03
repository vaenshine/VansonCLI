/**
 * VCUnityRuntimeEngine -- lightweight Unity/IL2CPP/Mono runtime detection
 * and exported symbol resolution for guided analysis.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface VCUnityRuntimeEngine : NSObject

+ (instancetype)shared;

- (NSDictionary *)detectUnityRuntime;
- (NSArray<NSDictionary *> *)unityModuleSummariesWithLimit:(NSUInteger)limit;
- (NSDictionary *)resolveSymbols:(NSArray<NSString *> *)symbolNames
                 preferredModule:(NSString * _Nullable)preferredModuleName
           includeDefaultSymbols:(BOOL)includeDefaultSymbols;
- (NSDictionary *)resolveICalls:(NSArray<NSString *> *)icallNames
             includeDefaultICalls:(BOOL)includeDefaultICalls;
- (NSDictionary *)drawingSupportSummary;
- (NSDictionary *)mainCameraSummary;
- (NSDictionary *)findGameObjectByName:(NSString *)name;
- (NSDictionary *)findGameObjectsByTag:(NSString *)tag limit:(NSUInteger)limit;
- (NSDictionary *)componentForObjectAddress:(uintptr_t)address
                                 objectKind:(NSString * _Nullable)objectKind
                              componentName:(NSString *)componentName;
- (NSDictionary *)rendererCandidatesForName:(NSString * _Nullable)name
                                        tag:(NSString * _Nullable)tag
                                      limit:(NSUInteger)limit;
- (NSDictionary *)transformPositionForAddress:(uintptr_t)address objectKind:(NSString * _Nullable)objectKind;
- (NSDictionary *)rendererBoundsForAddress:(uintptr_t)address;
- (NSDictionary *)projectRendererBoundsForAddress:(uintptr_t)address cameraAddress:(uintptr_t)cameraAddress;
- (NSDictionary *)worldToScreenForWorldX:(double)x
                                       y:(double)y
                                       z:(double)z
                           cameraAddress:(uintptr_t)cameraAddress;
- (NSDictionary *)runtimeNotes;

@end

NS_ASSUME_NONNULL_END
