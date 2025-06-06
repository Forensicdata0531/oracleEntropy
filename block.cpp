#include "block.hpp"
#include "sha256_wrapper.hpp"
#include <simd/simd.h> // For simd::uint2

// Serialize the block header as 80 bytes (little endian, reversed hashes)
std::vector<uint8_t> BlockHeader::toBytes() const {
    std::vector<uint8_t> bytes;

    auto appendLE32 = [&](uint32_t val) {
        bytes.push_back(static_cast<uint8_t>(val & 0xff));
        bytes.push_back(static_cast<uint8_t>((val >> 8) & 0xff));
        bytes.push_back(static_cast<uint8_t>((val >> 16) & 0xff));
        bytes.push_back(static_cast<uint8_t>((val >> 24) & 0xff));
    };

    auto appendReversed = [&](const std::array<uint8_t, 32>& arr) {
        for (int i = 31; i >= 0; --i)
            bytes.push_back(arr[i]);
    };

    appendLE32(version);
    appendReversed(prevBlockHash);
    appendReversed(merkleRoot);
    appendLE32(timestamp);
    appendLE32(bits);
    appendLE32(nonce);

    return bytes;
}

std::vector<uint32_t> BlockHeader::getMidstateWords() const {
    // Compute SHA256 midstate from first 64 bytes of header
    std::vector<uint8_t> headerBytes = toBytes();
    std::vector<uint8_t> first64(headerBytes.begin(), headerBytes.begin() + 64);

    return sha256_midstate(first64); // Your existing function returning midstate uint32_t vector
}

simd::uint2 BlockHeader::getTailWords() const {
    // Extract the last 8 bytes (nonce + bits) for tail words
    std::vector<uint8_t> headerBytes = toBytes();

    uint32_t w1 = *(uint32_t*)(&headerBytes[64]); // nonce bytes
    uint32_t w2 = *(uint32_t*)(&headerBytes[68]); // bits bytes

    return simd::uint2{w1, w2};
}
