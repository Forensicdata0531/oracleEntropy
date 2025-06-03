#ifndef UTILS_HPP
#define UTILS_HPP

#include <vector>
#include <array>
#include <cstdint>
#include <string>
#include "block.hpp"  // for BlockHeader struct

// Serialize a block header exactly to 80 bytes (Bitcoin block header format)
std::vector<uint8_t> serializeHeader80(const BlockHeader& header);

// Convert compact difficulty bits to full target (big endian)
std::vector<uint8_t> bitsToTarget(uint32_t bits);

// Convert bytes to hex string
std::string bytesToHex(const std::vector<uint8_t>& bytes);

// Convert hex string to bytes
std::vector<uint8_t> hexToBytes(const std::string& hex);

// SHA256 hashing using OpenSSL EVP interface
std::vector<uint8_t> sha256(const std::vector<uint8_t>& data);

// Double SHA256 (used in Bitcoin block hashing)
std::vector<uint8_t> doubleSHA256(const std::vector<uint8_t>& data);

// Load block template JSON from file
std::string loadBlockTemplate(const std::string& filepath);

// Calculate SHA256 midstate from first 64 bytes of block header prefix
std::array<uint32_t, 8> calculateMidstate(const std::vector<uint8_t>& headerPrefix);

#endif // UTILS_HPP
