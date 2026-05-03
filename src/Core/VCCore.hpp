/**
 * VCCore.hpp -- VansonCLI C++ Core
 * XorStr 编译期字符串混淆 + SecCore 安全检测
 * XOR key = 0x37 (区别于 VM 0x42, VL 0x5A)
 */

#ifndef VCCORE_HPP
#define VCCORE_HPP

#include <cstdint>
#include <cstddef>
#include <string>
#include <vector>

namespace VCCore {

// ═══════════════════════════════════════════════════════════════
// XorStr -- 编译期字符串混淆
// ═══════════════════════════════════════════════════════════════
template <size_t N, char K = 0x37>
class XorStr {
public:
    constexpr XorStr(const char* str) : _data() {
        for (size_t i = 0; i < N; ++i) {
            _data[i] = str[i] ^ K;
        }
    }

    std::string dec() const {
        std::string r;
        r.reserve(N);
        for (size_t i = 0; i < N; ++i) {
            r += _data[i] ^ K;
        }
        return r;
    }

private:
    char _data[N];
};

// VC_SEC("sensitive string") -- 运行时解密
#define VC_SEC(str) \
    []() -> std::string { \
        static constexpr VCCore::XorStr<sizeof(str), 0x37> s(str); \
        return s.dec(); \
    }()

// VC_SECN("string") -- 返回 NSString*
#define VC_SECN(str) \
    [NSString stringWithUTF8String:VC_SEC(str).c_str()]

// ═══════════════════════════════════════════════════════════════
// SecCore -- 安全环境检测
// ═══════════════════════════════════════════════════════════════
class SecCore {
public:
    static SecCore& inst();

    bool isJailbroken();
    bool isDebugged();
    bool isFridaPresent();
    void denyDebugger();
    bool isEnvironmentSafe();

private:
    SecCore() = default;
    bool _jbCached = false;
    bool _jbResult = false;
};

// ═══════════════════════════════════════════════════════════════
// Hex Utilities (可复用)
// ═══════════════════════════════════════════════════════════════
std::vector<uint8_t> hexDecode(const char* hex);
std::string hexEncode(const uint8_t* data, size_t len);

} // namespace VCCore

#endif // VCCORE_HPP
