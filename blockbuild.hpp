// blockbuilder.hpp
#pragma once
#include <vector>
#include <cstdint>
#include "block.hpp"

std::vector<uint8_t> buildFullBlock(const BlockHeader& header, const std::vector<std::vector<uint8_t>>& txs);
