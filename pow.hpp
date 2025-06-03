// pow.hpp
#pragma once
#include <string>
#include <vector>
#include <openssl/sha.h>
#include <iostream>
#include "utils.hpp"

inline std::vector<uint8_t> sha256d(const std::vector<uint8_t>& data) {
    uint8_t hash1[SHA256_DIGEST_LENGTH];
    uint8_t hash2[SHA256_DIGEST_LENGTH];
    SHA256(data.data(), data.size(), hash1);
    SHA256(hash1, SHA256_DIGEST_LENGTH, hash2);
    return std::vector<uint8_t>(hash2, hash2 + SHA256_DIGEST_LENGTH);
}

inline std::vector<uint8_t> bitsToTarget(uint32_t bits) {
    uint32_t exponent = bits >> 24;
    uint32_t mantissa = bits & 0xFFFFFF;
    std::vector<uint8_t> target(32, 0);
    int offset = exponent - 3;
    target[31 - offset] = (mantissa >> 16) & 0xFF;
    target[31 - offset - 1] = (mantissa >> 8) & 0xFF;
    target[31 - offset - 2] = mantissa & 0xFF;
    return target;
}

inline bool isValidHash(const std::vector<uint8_t>& hash, const std::vector<uint8_t>& target) {
    for (int i = 0; i < 32; ++i) {
        if (hash[i] < target[i]) return true;
        if (hash[i] > target[i]) return false;
    }
    return true;
}

inline uint32_t mineBlock(std::string headerHex, uint32_t startNonce, uint32_t maxNonce, uint32_t bits, std::string& outHashHex) {
    std::vector<uint8_t> target = bitsToTarget(bits);
    for (uint32_t nonce = startNonce; nonce < maxNonce; ++nonce) {
        std::string nonceHex = intToLittleEndianHex(nonce, 4);
        std::string attempt = headerHex.substr(0, 152) + nonceHex;
        std::vector<uint8_t> headerBytes = hexToBytes(attempt);
        std::vector<uint8_t> hash = sha256d(headerBytes);

        std::string hashHex;
        for (int i = 31; i >= 0; --i) hashHex += byteToHex(hash[i]);

        if (isValidHash(hash, target)) {
            outHashHex = hashHex;
            return nonce;
        }

        if (nonce % 100000 == 0) {
            std::cout << "Tried nonce: " << nonce << ", hash: " << hashHex << "\r" << std::flush;
        }
    }
    return 0xFFFFFFFF;
}
