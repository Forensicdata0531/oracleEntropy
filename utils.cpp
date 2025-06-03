#include "utils.hpp"
#include <fstream>
#include <sstream>
#include <iomanip>
#include <stdexcept>
#include <openssl/sha.h>
#include <algorithm>

// Calculate midstate by SHA256 hashing only the first 64 bytes (first half) of the header
std::array<uint32_t, 8> calculateMidstateArray(const std::vector<uint8_t>& headerPrefix) {
    if (headerPrefix.size() != 64) {
        throw std::runtime_error("Header prefix must be exactly 64 bytes");
    }
    uint8_t hash[32];
    SHA256(headerPrefix.data(), headerPrefix.size(), hash);

    std::array<uint32_t, 8> result;
    for (size_t i = 0; i < 8; ++i) {
        result[i] = (hash[i * 4] << 24) | (hash[i * 4 + 1] << 16) |
                    (hash[i * 4 + 2] << 8) | hash[i * 4 + 3];
    }

    return result;
}

std::string loadBlockTemplate(const std::string& filepath) {
    std::ifstream file(filepath);
    if (!file) throw std::runtime_error("Failed to open block template file: " + filepath);
    std::stringstream buffer;
    buffer << file.rdbuf();
    return buffer.str();
}

std::vector<uint8_t> serializeHeader(const BlockHeader& header) {
    // Use the method in BlockHeader for consistency
    return header.toBytes();
}

std::vector<uint8_t> sha256d(const std::vector<uint8_t>& data) {
    uint8_t hash1[SHA256_DIGEST_LENGTH];
    SHA256(data.data(), data.size(), hash1);

    std::vector<uint8_t> hash2(SHA256_DIGEST_LENGTH);
    SHA256(hash1, SHA256_DIGEST_LENGTH, hash2.data());

    return hash2;
}

std::string bytesToHex(const std::vector<uint8_t>& bytes) {
    std::ostringstream oss;
    for (auto b : bytes) {
        oss << std::hex << std::setw(2) << std::setfill('0') << (int)b;
    }
    return oss.str();
}
