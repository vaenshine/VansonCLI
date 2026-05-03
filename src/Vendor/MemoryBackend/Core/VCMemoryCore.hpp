/**
 * VansonCLI Memory Backend - C++ Core
 * 内存引擎、加密核心、安全防护
 */

#ifndef VCMEMORYCORE_HPP
#define VCMEMORYCORE_HPP

#include <cstdint>
#include <cstddef>
#include <vector>
#include <string>

namespace vcore {

// ═══════════════════════════════════════════════════════════════
// 编译期字符串混淆 (防止静态分析)
// ═══════════════════════════════════════════════════════════════
template <size_t N, char K>
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

// 使用宏简化: SEC_STR("sensitive string")
#define SEC_STR(str) \
    []() { \
        static constexpr vcore::XorStr<sizeof(str), 0x5A> s(str); \
        return s.dec(); \
    }()

// ═══════════════════════════════════════════════════════════════
// 安全核心 (反调试/完整性检测)
// ═══════════════════════════════════════════════════════════════
class SecCore {
public:
    static SecCore& inst();

    // 环境检测
    bool isJailbroken();      // 检测越狱环境
    bool isDebugged();        // 检测调试器附加
    bool isFridaPresent();    // 检测 Frida

    // 主动防护 (仅越狱环境有效)
    void denyDebugger();      // 拒绝调试器附加

    // 综合检测
    bool isEnvironmentSafe(); // 综合安全检测

private:
    SecCore() = default;
    bool _jbCached = false;
    bool _jbResult = false;
};

// 数据类型 (与 VM 2.4.2 保持一致)
enum DataType : int {
    DT_I8 = 0,
    DT_I16 = 1,
    DT_I32 = 2,
    DT_I64 = 3,
    DT_U8 = 4,
    DT_U16 = 5,
    DT_U32 = 6,
    DT_U64 = 7,
    DT_F32 = 8,
    DT_F64 = 9
};

// 内存引擎
class MemEngine {
public:
    static MemEngine& inst();

    // 模块操作
    uint64_t modBase(const char* name);
    uint64_t modSize(const char* name);

    // 内存读写
    bool readMem(uint64_t addr, void* buf, size_t len);
    bool writeMem(uint64_t addr, const void* buf, size_t len);

    // 指针链
    uint64_t resolveChain(uint64_t base, uint64_t baseOff, const int64_t* offs, size_t count);

    // 读写值
    bool readVal(uint64_t addr, DataType type, char* out, size_t outLen);
    bool writeVal(uint64_t addr, DataType type, const char* val);

    // 特征码搜索
    std::vector<uint64_t> sigScan(const char* sig, const char* mod, size_t maxResults = 100);

private:
    MemEngine() = default;
    size_t typeSize(DataType t);
};

// 加密核心
class CryptoCore {
public:
    static uint32_t magic();
    static bool isMagic(const uint8_t* data, size_t len);

    // 解密 (返回解密后数据，失败返回空)
    static std::vector<uint8_t> decrypt(const uint8_t* data, size_t len);

    // 加密
    static std::vector<uint8_t> encrypt(const uint8_t* data, size_t len);

    // Hex 转换
    static std::vector<uint8_t> hexDecode(const char* hex);
    static std::string hexEncode(const uint8_t* data, size_t len);

private:
    static void deriveKey(uint8_t* buf, size_t len);
    static void deriveHMAC(uint8_t* buf, size_t len);
};

} // namespace vcore

#endif // VCMEMORYCORE_HPP
