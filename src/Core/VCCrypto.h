/**
 * VCCrypto -- 全新加密方案
 * 通用数据加密、签名校验和 HMAC 工具
 */

#import <Foundation/Foundation.h>

@interface VCCrypto : NSObject

// Hex 工具 (可复用)
+ (NSData *)dataFromHexString:(NSString *)hex;
+ (NSString *)hexStringFromData:(NSData *)data;

// AES-256-GCM 加解密
+ (NSData *)encryptData:(NSData *)plaintext withKey:(NSData *)key;
+ (NSData *)decryptData:(NSData *)ciphertext withKey:(NSData *)key;

// 签名验证
+ (BOOL)verifySignature:(NSData *)signature
                forData:(NSData *)data
          withPublicKey:(NSString *)publicKeyPEM;

// 随机数
+ (NSData *)randomBytes:(NSUInteger)length;

// HMAC-SHA256
+ (NSData *)hmacSHA256:(NSData *)data withKey:(NSData *)key;

@end
