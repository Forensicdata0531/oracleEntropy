#pragma once
#include <vector>
#include <cstdint>
#include <string>

// Compute full SHA-256 hash
std::vector<uint8_t> sha256(const std::vector<uint8_t>& data);

// Optional: return midstate (internal state after first 64 rounds)
std::vector<uint32_t> sha256_midstate(const std::vector<uint8_t>& header);

// ✅ FIXED declaration: accepts raw bytes
std::string compute_sha256_midstate_hex(const uint8_t* data, size_t len);
