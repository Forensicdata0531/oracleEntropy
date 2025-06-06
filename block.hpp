#pragma once

#include <cstdint>
#include <vector>
#include <array>
#include <simd/simd.h>

inline std::vector<uint8_t> bitsToTarget(uint32_t bits) {
    uint32_t exponent = bits >> 24;
    uint32_t mantissa = bits & 0x007fffff;
    std::vector<uint8_t> target(32, 0);

    if (exponent <= 3) {
        mantissa >>= 8 * (3 - exponent);
        target[31] = mantissa & 0xff;
        if (exponent >= 2) target[30] = (mantissa >> 8) & 0xff;
        if (exponent >= 1) target[29] = (mantissa >> 16) & 0xff;
    } else {
        size_t index = 32 - exponent;
        target[index]     = (mantissa >> 16) & 0xff;
        target[index + 1] = (mantissa >> 8) & 0xff;
        target[index + 2] = mantissa & 0xff;
    }

    return target;
}

struct BlockHeader {
    uint32_t version;
    std::array<uint8_t, 32> prevBlockHash;
    std::array<uint8_t, 32> merkleRoot;
    uint32_t timestamp;
    uint32_t bits;
    uint32_t nonce;

    std::vector<uint8_t> toBytes() const;

    // Returns vector<uint32_t> representing the 8 32-bit words of midstate
    std::vector<uint32_t> getMidstateWords() const;

    // Returns the last 8 bytes (tail words) packed as simd::uint2 (two uint32_t)
    simd::uint2 getTailWords() const;
};
