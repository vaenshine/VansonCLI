/**
 * VCCrypto.mm -- 全新加密方案实现
 */

#import "VCCrypto.h"
#import "../../VansonCLI.h"
#import <CommonCrypto/CommonCryptor.h>
#import <CommonCrypto/CommonHMAC.h>
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>

@implementation VCCrypto

static NSString *VCNormalizePublicKeyString(NSString *publicKey) {
    if (![publicKey isKindOfClass:[NSString class]]) return nil;
    NSString *trimmed = [publicKey stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) return nil;
    if ([trimmed containsString:@"BEGIN PUBLIC KEY"]) return trimmed;
    if ([trimmed containsString:@"-----BEGIN"]) return trimmed;
    return trimmed;
}

static NSData *VCPublicKeyDataFromString(NSString *publicKey) {
    NSString *normalized = VCNormalizePublicKeyString(publicKey);
    if (normalized.length == 0) return nil;

    if (![normalized containsString:@"BEGIN"]) {
        return [[NSData alloc] initWithBase64EncodedString:normalized options:NSDataBase64DecodingIgnoreUnknownCharacters];
    }

    NSMutableString *base64 = [normalized mutableCopy];
    [base64 replaceOccurrencesOfString:@"-----BEGIN PUBLIC KEY-----" withString:@"" options:0 range:NSMakeRange(0, base64.length)];
    [base64 replaceOccurrencesOfString:@"-----END PUBLIC KEY-----" withString:@"" options:0 range:NSMakeRange(0, base64.length)];
    [base64 replaceOccurrencesOfString:@"-----BEGIN EC PUBLIC KEY-----" withString:@"" options:0 range:NSMakeRange(0, base64.length)];
    [base64 replaceOccurrencesOfString:@"-----END EC PUBLIC KEY-----" withString:@"" options:0 range:NSMakeRange(0, base64.length)];
    [base64 replaceOccurrencesOfString:@"\r" withString:@"" options:0 range:NSMakeRange(0, base64.length)];
    [base64 replaceOccurrencesOfString:@"\n" withString:@"" options:0 range:NSMakeRange(0, base64.length)];
    [base64 replaceOccurrencesOfString:@" " withString:@"" options:0 range:NSMakeRange(0, base64.length)];
    return [[NSData alloc] initWithBase64EncodedString:base64 options:NSDataBase64DecodingIgnoreUnknownCharacters];
}

static SecKeyRef VCCreatePublicKey(NSData *keyData, CFStringRef keyType) {
    if (!keyData.length) return nil;
    NSDictionary *attrs = @{
        (__bridge id)kSecAttrKeyType: (__bridge id)keyType,
        (__bridge id)kSecAttrKeyClass: (__bridge id)kSecAttrKeyClassPublic,
        (__bridge id)kSecAttrKeySizeInBits: @(keyData.length * 8),
    };
    return SecKeyCreateWithData((__bridge CFDataRef)keyData, (__bridge CFDictionaryRef)attrs, NULL);
}

static const NSUInteger kVCCryptoCurrentIVLength = kCCBlockSizeAES128;
static const NSUInteger kVCCryptoLegacyIVLength = 12;
static const NSUInteger kVCCryptoHMACLength = CC_SHA256_DIGEST_LENGTH;

static NSData *VCAESCBCIVFromStoredIV(NSData *storedIV) {
    if (![storedIV isKindOfClass:[NSData class]] || storedIV.length == 0) return nil;
    if (storedIV.length >= kVCCryptoCurrentIVLength) {
        return [storedIV subdataWithRange:NSMakeRange(0, kVCCryptoCurrentIVLength)];
    }
    NSMutableData *expanded = [NSMutableData dataWithLength:kVCCryptoCurrentIVLength];
    memcpy(expanded.mutableBytes, storedIV.bytes, storedIV.length);
    return expanded;
}

static NSData *VCCryptoDecryptAESCBC(NSData *encrypted, NSData *storedIV, NSData *key) {
    NSData *cbcIV = VCAESCBCIVFromStoredIV(storedIV);
    if (!encrypted.length || !cbcIV.length || key.length != 32) return nil;

    size_t bufferSize = encrypted.length + kCCBlockSizeAES128;
    NSMutableData *plaintext = [NSMutableData dataWithLength:bufferSize];
    size_t numBytesDecrypted = 0;

    CCCryptorStatus status = CCCrypt(
        kCCDecrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding,
        key.bytes, key.length,
        cbcIV.bytes,
        encrypted.bytes, encrypted.length,
        plaintext.mutableBytes, bufferSize,
        &numBytesDecrypted
    );

    if (status != kCCSuccess) return nil;
    plaintext.length = numBytesDecrypted;
    return plaintext;
}

#pragma mark - Hex Utilities

+ (NSData *)dataFromHexString:(NSString *)hex {
    NSMutableData *data = [NSMutableData dataWithCapacity:hex.length / 2];
    unsigned char byte;
    char chars[3] = {0};
    for (NSUInteger i = 0; i + 1 < hex.length; i += 2) {
        chars[0] = [hex characterAtIndex:i];
        chars[1] = [hex characterAtIndex:i + 1];
        byte = (unsigned char)strtol(chars, NULL, 16);
        [data appendBytes:&byte length:1];
    }
    return data;
}

+ (NSString *)hexStringFromData:(NSData *)data {
    const unsigned char *bytes = (const unsigned char *)data.bytes;
    NSMutableString *hex = [NSMutableString stringWithCapacity:data.length * 2];
    for (NSUInteger i = 0; i < data.length; i++) {
        [hex appendFormat:@"%02x", bytes[i]];
    }
    return hex;
}

#pragma mark - AES-256-GCM

+ (NSData *)encryptData:(NSData *)plaintext withKey:(NSData *)key {
    if (!plaintext || !key || key.length != 32) return nil;

    // Store a full AES-CBC IV so provider keys survive save/load reliably.
    NSData *iv = [self randomBytes:kVCCryptoCurrentIVLength];
    if (!iv) return nil;

    // AES-256-GCM via SecKey / CCCrypt fallback
    // iOS 13+ 支持 CryptoKit, 但 Tweak 环境用 CommonCrypto
    // 此处使用 AES-CBC + HMAC 作为 GCM 的替代方案
    size_t bufferSize = plaintext.length + kCCBlockSizeAES128;
    NSMutableData *ciphertext = [NSMutableData dataWithLength:bufferSize];
    size_t numBytesEncrypted = 0;

    CCCryptorStatus status = CCCrypt(
        kCCEncrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding,
        key.bytes, key.length,
        iv.bytes,
        plaintext.bytes, plaintext.length,
        ciphertext.mutableBytes, bufferSize,
        &numBytesEncrypted
    );

    if (status != kCCSuccess) return nil;
    ciphertext.length = numBytesEncrypted;

    // HMAC for integrity
    NSMutableData *payload = [NSMutableData dataWithData:iv];
    [payload appendData:ciphertext];
    NSData *hmac = [self hmacSHA256:payload withKey:key];

    // Format: IV(16) + Ciphertext + HMAC(32)
    NSMutableData *result = [NSMutableData dataWithData:iv];
    [result appendData:ciphertext];
    [result appendData:hmac];
    return result;
}

+ (NSData *)decryptData:(NSData *)ciphertext withKey:(NSData *)key {
    if (!ciphertext || !key || key.length != 32) return nil;
    if (ciphertext.length < kVCCryptoLegacyIVLength + kVCCryptoHMACLength + 1) return nil;

    const uint8_t *bytes = (const uint8_t *)ciphertext.bytes;
    NSUInteger len = ciphertext.length;

    NSArray<NSNumber *> *candidateIVLengths = @[@(kVCCryptoCurrentIVLength), @(kVCCryptoLegacyIVLength)];
    for (NSNumber *candidate in candidateIVLengths) {
        NSUInteger ivLength = candidate.unsignedIntegerValue;
        if (len <= ivLength + kVCCryptoHMACLength) continue;

        NSData *storedIV = [NSData dataWithBytes:bytes length:ivLength];
        NSData *encrypted = [NSData dataWithBytes:bytes + ivLength length:len - ivLength - kVCCryptoHMACLength];
        NSData *storedHmac = [NSData dataWithBytes:bytes + len - kVCCryptoHMACLength length:kVCCryptoHMACLength];

        NSMutableData *payload = [NSMutableData dataWithData:storedIV];
        [payload appendData:encrypted];
        NSData *computedHmac = [self hmacSHA256:payload withKey:key];
        if (![storedHmac isEqualToData:computedHmac]) {
            continue;
        }

        NSData *plaintext = VCCryptoDecryptAESCBC(encrypted, storedIV, key);
        if (plaintext.length > 0) {
            return plaintext;
        }
    }

    VCLog(@"Crypto: provider secret decryption failed");
    return nil;
}

#pragma mark - Signature Verification

+ (BOOL)verifySignature:(NSData *)signature
                forData:(NSData *)data
          withPublicKey:(NSString *)publicKeyPEM {
    if (!signature.length || !data.length || publicKeyPEM.length == 0) return NO;

    NSData *keyData = VCPublicKeyDataFromString(publicKeyPEM);
    if (!keyData.length) {
        VCLog(@"Crypto: invalid public key data");
        return NO;
    }

    SecKeyRef rsaKey = VCCreatePublicKey(keyData, kSecAttrKeyTypeRSA);
    if (rsaKey) {
        BOOL canVerify = SecKeyIsAlgorithmSupported(rsaKey, kSecKeyOperationTypeVerify, kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256);
        if (canVerify) {
            BOOL ok = SecKeyVerifySignature(rsaKey,
                                            kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256,
                                            (__bridge CFDataRef)data,
                                            (__bridge CFDataRef)signature,
                                            NULL);
            CFRelease(rsaKey);
            if (ok) return YES;
        } else {
            CFRelease(rsaKey);
        }
    }

    SecKeyRef ecKey = VCCreatePublicKey(keyData, kSecAttrKeyTypeECSECPrimeRandom);
    if (ecKey) {
        BOOL canVerify = SecKeyIsAlgorithmSupported(ecKey, kSecKeyOperationTypeVerify, kSecKeyAlgorithmECDSASignatureMessageX962SHA256);
        if (canVerify) {
            BOOL ok = SecKeyVerifySignature(ecKey,
                                            kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
                                            (__bridge CFDataRef)data,
                                            (__bridge CFDataRef)signature,
                                            NULL);
            CFRelease(ecKey);
            if (ok) return YES;
        } else {
            CFRelease(ecKey);
        }
    }

    // Fallback: verify pre-hashed message for servers that sign SHA-256 digest directly.
    unsigned char digestBytes[CC_SHA256_DIGEST_LENGTH] = {0};
    CC_SHA256(data.bytes, (CC_LONG)data.length, digestBytes);
    NSData *digest = [NSData dataWithBytes:digestBytes length:sizeof(digestBytes)];

    rsaKey = VCCreatePublicKey(keyData, kSecAttrKeyTypeRSA);
    if (rsaKey) {
        BOOL canVerify = SecKeyIsAlgorithmSupported(rsaKey, kSecKeyOperationTypeVerify, kSecKeyAlgorithmRSASignatureDigestPKCS1v15SHA256);
        if (canVerify) {
            BOOL ok = SecKeyVerifySignature(rsaKey,
                                            kSecKeyAlgorithmRSASignatureDigestPKCS1v15SHA256,
                                            (__bridge CFDataRef)digest,
                                            (__bridge CFDataRef)signature,
                                            NULL);
            CFRelease(rsaKey);
            if (ok) return YES;
        } else {
            CFRelease(rsaKey);
        }
    }

    ecKey = VCCreatePublicKey(keyData, kSecAttrKeyTypeECSECPrimeRandom);
    if (ecKey) {
        BOOL canVerify = SecKeyIsAlgorithmSupported(ecKey, kSecKeyOperationTypeVerify, kSecKeyAlgorithmECDSASignatureDigestX962SHA256);
        if (canVerify) {
            BOOL ok = SecKeyVerifySignature(ecKey,
                                            kSecKeyAlgorithmECDSASignatureDigestX962SHA256,
                                            (__bridge CFDataRef)digest,
                                            (__bridge CFDataRef)signature,
                                            NULL);
            CFRelease(ecKey);
            if (ok) return YES;
        } else {
            CFRelease(ecKey);
        }
    }

    VCLog(@"Crypto: signature verification failed");
    return NO;
}

#pragma mark - Random

+ (NSData *)randomBytes:(NSUInteger)length {
    NSMutableData *data = [NSMutableData dataWithLength:length];
    int result = SecRandomCopyBytes(kSecRandomDefault, length, data.mutableBytes);
    return (result == errSecSuccess) ? data : nil;
}

#pragma mark - HMAC

+ (NSData *)hmacSHA256:(NSData *)data withKey:(NSData *)key {
    NSMutableData *hmac = [NSMutableData dataWithLength:CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, key.bytes, key.length, data.bytes, data.length, hmac.mutableBytes);
    return hmac;
}

@end
