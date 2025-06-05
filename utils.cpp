#include "utils.hpp"
#include <sstream>
#include <iomanip>
#include <openssl/sha.h>
#include <stdexcept>
#include <cctype>

std::vector<uint8_t> hexToBytes(const std::string& hex) {
    std::vector<uint8_t> bytes;
    if (hex.length() % 2 != 0) {
        throw std::invalid_argument("hex string must have even length");
    }
    bytes.reserve(hex.length() / 2);
    for (size_t i = 0; i < hex.length(); i += 2) {
        char high = hex[i];
        char low = hex[i + 1];
        if (!std::isxdigit(high) || !std::isxdigit(low)) {
            throw std::invalid_argument("hex string contains non-hex characters");
        }
        uint8_t byte = static_cast<uint8_t>(std::stoi(hex.substr(i, 2), nullptr, 16));
        bytes.push_back(byte);
    }
    return bytes;
}

std::string bytesToHex(const std::vector<uint8_t>& bytes) {
    std::ostringstream oss;
    for (uint8_t b : bytes)
        oss << std::hex << std::setw(2) << std::setfill('0') << static_cast<int>(b);
    return oss.str();
}

std::string toHex(uint32_t value) {
    std::ostringstream oss;
    oss << std::hex << std::setw(8) << std::setfill('0') << value;
    return oss.str();
}

std::vector<uint8_t> doubleSHA256(const std::vector<uint8_t>& input) {
    uint8_t hash1[SHA256_DIGEST_LENGTH];
    uint8_t hash2[SHA256_DIGEST_LENGTH];

    SHA256(input.data(), input.size(), hash1);
    SHA256(hash1, SHA256_DIGEST_LENGTH, hash2);

    return std::vector<uint8_t>(hash2, hash2 + SHA256_DIGEST_LENGTH);
}

std::vector<uint8_t> sha256Double(const std::vector<uint8_t>& input) {
    return doubleSHA256(input);
}

std::vector<uint8_t> txHashFromHex(const std::string& txHex) {
    return doubleSHA256(hexToBytes(txHex));
}

std::vector<uint8_t> computeMerkleRoot(std::vector<std::vector<uint8_t>> txHashes) {
    if (txHashes.empty()) return {};

    while (txHashes.size() > 1) {
        if (txHashes.size() % 2 != 0)
            txHashes.push_back(txHashes.back());

        std::vector<std::vector<uint8_t>> newLevel;
        for (size_t i = 0; i < txHashes.size(); i += 2) {
            std::vector<uint8_t> concat(txHashes[i]);
            concat.insert(concat.end(), txHashes[i + 1].begin(), txHashes[i + 1].end());
            newLevel.push_back(doubleSHA256(concat));
        }
        txHashes = std::move(newLevel);
    }

    return txHashes[0];
}

std::string formatUptime(std::chrono::steady_clock::time_point start) {
    auto duration = std::chrono::steady_clock::now() - start;
    auto seconds = std::chrono::duration_cast<std::chrono::seconds>(duration).count();
    std::ostringstream oss;
    oss << seconds << "s";
    return oss.str();
}
