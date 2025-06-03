#include "utils.hpp"
#include <algorithm>
#include <stdexcept>
#include <cstring>
#include <fstream>
#include <sstream>
#include <openssl/evp.h>
#include <openssl/sha.h>   // Needed for SHA256_CTX and internal state access
#include <iostream>

// Helper to reverse bytes in a vector
void reverseBytes(std::vector<uint8_t>& data) {
    std::reverse(data.begin(), data.end());
}

// SHA256 hashing using OpenSSL EVP interface
std::vector<uint8_t> sha256(const std::vector<uint8_t>& data) {
    std::vector<uint8_t> hash(EVP_MAX_MD_SIZE);
    unsigned int len = 0;

    EVP_MD_CTX* ctx = EVP_MD_CTX_new();
    if (!ctx) throw std::runtime_error("Failed to create EVP_MD_CTX");

    if (EVP_DigestInit_ex(ctx, EVP_sha256(), nullptr) != 1) {
        EVP_MD_CTX_free(ctx);
        throw std::runtime_error("EVP_DigestInit_ex failed");
    }

    if (EVP_DigestUpdate(ctx, data.data(), data.size()) != 1) {
        EVP_MD_CTX_free(ctx);
        throw std::runtime_error("EVP_DigestUpdate failed");
    }

    if (EVP_DigestFinal_ex(ctx, hash.data(), &len) != 1) {
        EVP_MD_CTX_free(ctx);
        throw std::runtime_error("EVP_DigestFinal_ex failed");
    }

    EVP_MD_CTX_free(ctx);
    hash.resize(len);
    return hash;
}

// Double SHA256 (used in Bitcoin block hashing)
std::vector<uint8_t> doubleSHA256(const std::vector<uint8_t>& data) {
    return sha256(sha256(data));
}

// Encode variable length integer (Bitcoin style)
std::vector<uint8_t> encodeVarInt(uint64_t value) {
    std::vector<uint8_t> result;
    if (value < 0xfd) {
        result.push_back(static_cast<uint8_t>(value));
    } else if (value <= 0xffff) {
        result.push_back(0xfd);
        result.push_back(static_cast<uint8_t>(value & 0xff));
        result.push_back(static_cast<uint8_t>((value >> 8) & 0xff));
    } else if (value <= 0xffffffff) {
        result.push_back(0xfe);
        for (int i = 0; i < 4; i++)
            result.push_back(static_cast<uint8_t>((value >> (8 * i)) & 0xff));
    } else {
        result.push_back(0xff);
        for (int i = 0; i < 8; i++)
            result.push_back(static_cast<uint8_t>((value >> (8 * i)) & 0xff));
    }
    return result;
}

// Encode block height according to BIP34 scriptSig format
std::vector<uint8_t> encodeBlockHeightBIP34(int height) {
    if (height < 0) throw std::runtime_error("Negative block height not allowed");
    if (height == 0) return {0x00};

    std::vector<uint8_t> heightBytes;
    while (height > 0) {
        heightBytes.push_back(static_cast<uint8_t>(height & 0xff));
        height >>= 8;
    }

    std::vector<uint8_t> result;
    result.push_back(static_cast<uint8_t>(heightBytes.size()));
    result.insert(result.end(), heightBytes.begin(), heightBytes.end());
    return result;
}

// Convert 64-bit unsigned int to little endian bytes
std::vector<uint8_t> uint64ToLE(uint64_t value) {
    std::vector<uint8_t> result(8);
    for (int i = 0; i < 8; ++i)
        result[i] = static_cast<uint8_t>((value >> (8 * i)) & 0xff);
    return result;
}

// Convert 32-bit unsigned int to little endian bytes
std::vector<uint8_t> uint32ToLE(uint32_t value) {
    std::vector<uint8_t> result(4);
    for (int i = 0; i < 4; ++i)
        result[i] = static_cast<uint8_t>((value >> (8 * i)) & 0xff);
    return result;
}

// Decode Base58Check string to bytes
std::vector<uint8_t> base58CheckDecode(const std::string& addr) {
    static const std::string BASE58_ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
    uint64_t num = 0;
    for (char c : addr) {
        num *= 58;
        auto idx = BASE58_ALPHABET.find(c);
        if (idx == std::string::npos) throw std::runtime_error("Invalid Base58 character");
        num += idx;
    }

    std::vector<uint8_t> result;
    while (num > 0) {
        result.insert(result.begin(), static_cast<uint8_t>(num & 0xff));
        num >>= 8;
    }

    // Handle leading zeros
    for (char c : addr) {
        if (c == '1') result.insert(result.begin(), 0x00);
        else break;
    }

    return result;
}

// Convert bytes to hex string
std::string bytesToHex(const std::vector<uint8_t>& data) {
    const char* hexChars = "0123456789abcdef";
    std::string hex;
    hex.reserve(data.size() * 2);
    for (uint8_t byte : data) {
        hex.push_back(hexChars[(byte >> 4) & 0xF]);
        hex.push_back(hexChars[byte & 0xF]);
    }
    return hex;
}

// Convert hex string to bytes
std::vector<uint8_t> hexToBytes(const std::string& hex) {
    if (hex.length() % 2 != 0)
        throw std::invalid_argument("Hex string has odd length");

    std::vector<uint8_t> bytes;
    bytes.reserve(hex.length() / 2);
    for (size_t i = 0; i < hex.length(); i += 2) {
        std::string byteString = hex.substr(i, 2);
        bytes.push_back(static_cast<uint8_t>(std::stoul(byteString, nullptr, 16)));
    }
    return bytes;
}

// Load block template JSON or raw data from file
std::string loadBlockTemplate(const std::string& path) {
    std::ifstream file(path);
    if (!file) throw std::runtime_error("Could not open file: " + path);

    std::ostringstream contents;
    contents << file.rdbuf();
    return contents.str();
}

// Calculate SHA256 midstate from first 64 bytes of block header prefix using EVP API (OpenSSL 3.x safe)
std::array<uint32_t, 8> calculateMidstate(const std::vector<uint8_t>& headerPrefix) {
    if (headerPrefix.size() != 64)
        throw std::runtime_error("Header prefix must be exactly 64 bytes");

    EVP_MD_CTX* ctx = EVP_MD_CTX_new();
    if (!ctx) throw std::runtime_error("Failed to create EVP_MD_CTX");

    if (EVP_DigestInit_ex(ctx, EVP_sha256(), nullptr) != 1) {
        EVP_MD_CTX_free(ctx);
        throw std::runtime_error("EVP_DigestInit_ex failed");
    }

    if (EVP_DigestUpdate(ctx, headerPrefix.data(), headerPrefix.size()) != 1) {
        EVP_MD_CTX_free(ctx);
        throw std::runtime_error("EVP_DigestUpdate failed");
    }

    // Access internal SHA256 state (may not be portable across OpenSSL versions)
    SHA256_CTX* shaCtx = reinterpret_cast<SHA256_CTX*>(ctx);
    std::array<uint32_t, 8> state;
    std::memcpy(state.data(), shaCtx->h, sizeof(state));

    EVP_MD_CTX_free(ctx);
    return state;
}

// Serialize BlockHeader to an 80-byte vector for mining (little-endian fields and hashes reversed)
std::vector<uint8_t> serializeHeader80(const BlockHeader& header) {
    std::vector<uint8_t> serialized;

    // Version (4 bytes LE)
    for (int i = 0; i < 4; i++)
        serialized.push_back(static_cast<uint8_t>((header.version >> (8 * i)) & 0xff));

    // Previous block hash (32 bytes reversed for little-endian)
    for (int i = 31; i >= 0; i--)
        serialized.push_back(header.prevBlockHash[i]);

    // Merkle root (32 bytes reversed for little-endian)
    for (int i = 31; i >= 0; i--)
        serialized.push_back(header.merkleRoot[i]);

    // Timestamp (4 bytes LE)
    for (int i = 0; i < 4; i++)
        serialized.push_back(static_cast<uint8_t>((header.timestamp >> (8 * i)) & 0xff));

    // Bits (4 bytes LE)
    for (int i = 0; i < 4; i++)
        serialized.push_back(static_cast<uint8_t>((header.bits >> (8 * i)) & 0xff));

    // Nonce (4 bytes LE)
    for (int i = 0; i < 4; i++)
        serialized.push_back(static_cast<uint8_t>((header.nonce >> (8 * i)) & 0xff));

    return serialized;
}
