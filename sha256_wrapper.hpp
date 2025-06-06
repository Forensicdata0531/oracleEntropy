#pragma once
#include <vector>
#include <cstdint>
#include <string>

// Compute full SHA-256 hash
std::vector<uint8_t> sha256(const std::vector<uint8_t>& data);

// Get SHA-256 midstate as 8-word vector
std::vector<uint32_t> sha256_midstate(const std::vector<uint8_t>& header);

// Get midstate as hex string (8 words, 32 bytes total, big-endian)
std::string compute_sha256_midstate_hex(const uint8_t* data, size_t len);
