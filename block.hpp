#pragma once

#include <cstdint>
#include <vector>
#include <array>

// Convert compact bits field (Bitcoin format) into a 32-byte target hash (big-endian)
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

// Block header structure — 80 bytes when serialized
struct BlockHeader {
    uint32_t version;
    std::array<uint8_t, 32> prevBlockHash;
    std::array<uint8_t, 32> merkleRoot;
    uint32_t timestamp;
    uint32_t bits;
    uint32_t nonce;

    // Returns the 80-byte serialized block header in little-endian format with hashes reversed
    std::vector<uint8_t> toBytes() const {
        std::vector<uint8_t> bytes;

        auto appendLE32 = [&](uint32_t val) {
            bytes.push_back(static_cast<uint8_t>(val & 0xff));
            bytes.push_back(static_cast<uint8_t>((val >> 8) & 0xff));
            bytes.push_back(static_cast<uint8_t>((val >> 16) & 0xff));
            bytes.push_back(static_cast<uint8_t>((val >> 24) & 0xff));
        };

        auto appendReversed = [&](const std::array<uint8_t, 32>& arr) {
            // Bitcoin serializes hashes as little-endian, so reverse bytes before appending
            for (int i = 31; i >= 0; --i) {
                bytes.push_back(arr[i]);
            }
        };

        appendLE32(version);
        appendReversed(prevBlockHash);
        appendReversed(merkleRoot);
        appendLE32(timestamp);
        appendLE32(bits);
        appendLE32(nonce);

        return bytes;
    }
};
