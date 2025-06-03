#ifndef UTILS_HPP
#define UTILS_HPP

#include <vector>
#include <array>
#include <cstdint>
#include <string>
#include "block.hpp"  // for BlockHeader struct

// Calculate midstate from header prefix bytes (first 64 bytes)
std::array<uint32_t, 8> calculateMidstateArray(const std::vector<uint8_t>& headerPrefix);

// Serialize a block header to a vector of bytes
std::vector<uint8_t> serializeHeader(const BlockHeader& header);

// Double SHA256 hash
std::vector<uint8_t> sha256d(const std::vector<uint8_t>& data);

// Convert compact difficulty bits to full target (big endian)
std::vector<uint8_t> bitsToTarget(uint32_t bits);

// Convert bytes to hex string
std::string bytesToHex(const std::vector<uint8_t>& bytes);

// Load block template JSON from file
std::string loadBlockTemplate(const std::string& filepath);

#endif // UTILS_HPP
