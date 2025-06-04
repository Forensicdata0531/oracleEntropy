#pragma once
#include <vector>
#include <string>
#include <cstdint>
#include <array>
#include <chrono>

std::vector<uint8_t> hexToBytes(const std::string& hex);
std::string bytesToHex(const std::vector<uint8_t>& bytes);
std::string toHex(uint32_t value);
std::vector<uint8_t> doubleSHA256(const std::vector<uint8_t>& input);

std::vector<uint8_t> txHashFromHex(const std::string& txHex);
std::vector<uint8_t> computeMerkleRoot(std::vector<std::vector<uint8_t>> txHashes);

// Declare formatUptime here, define only in utils.cpp
std::string formatUptime(std::chrono::steady_clock::time_point start);
