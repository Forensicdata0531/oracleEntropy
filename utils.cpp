#include "utils.hpp"
#include <sstream>
#include <iomanip>
#include <stdexcept>
#include <CommonCrypto/CommonDigest.h>  // Use Apple CommonCrypto for SHA256

std::vector<uint8_t> hexToBytes(const std::string& hex) {
    std::vector<uint8_t> bytes;
    if (hex.length() % 2 != 0) throw std::invalid_argument("Odd length hex string");
    for (size_t i = 0; i < hex.length(); i += 2) {
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
    std::vector<uint8_t> hash1(CC_SHA256_DIGEST_LENGTH);
    std::vector<uint8_t> hash2(CC_SHA256_DIGEST_LENGTH);

    CC_SHA256(input.data(), static_cast<CC_LONG>(input.size()), hash1.data());
    CC_SHA256(hash1.data(), static_cast<CC_LONG>(hash1.size()), hash2.data());

    return hash2;
}

std::vector<uint8_t> txHashFromHex(const std::string& txHex) {
    return doubleSHA256(hexToBytes(txHex));
}

std::vector<uint8_t> computeMerkleRoot(std::vector<std::vector<uint8_t>> txHashes) {
    if (txHashes.empty()) throw std::runtime_error("No transactions for Merkle root");

    while (txHashes.size() > 1) {
        if (txHashes.size() % 2 != 0)
            txHashes.push_back(txHashes.back());

        std::vector<std::vector<uint8_t>> newLevel;
        for (size_t i = 0; i < txHashes.size(); i += 2) {
            std::vector<uint8_t> combined(txHashes[i]);
            combined.insert(combined.end(), txHashes[i + 1].begin(), txHashes[i + 1].end());
            newLevel.push_back(doubleSHA256(combined));
        }
        txHashes = std::move(newLevel);
    }

    return txHashes[0];
}

// Format uptime as HH:MM:SS (defined only here)
std::string formatUptime(std::chrono::steady_clock::time_point start) {
    auto now = std::chrono::steady_clock::now();
    auto secs = std::chrono::duration_cast<std::chrono::seconds>(now - start).count();

    int hours = static_cast<int>(secs / 3600);
    int minutes = static_cast<int>((secs % 3600) / 60);
    int seconds = static_cast<int>(secs % 60);

    std::ostringstream oss;
    oss << std::setfill('0') << std::setw(2) << hours << ":"
        << std::setw(2) << minutes << ":"
        << std::setw(2) << seconds;
    return oss.str();
}
