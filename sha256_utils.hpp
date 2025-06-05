#pragma once
#include <vector>
#include <cstdint>

std::vector<uint8_t> sha256(const std::vector<uint8_t>& data);
std::vector<uint8_t> sha256Double(const std::vector<uint8_t>& data);
