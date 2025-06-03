// blockbuilder.hpp
#pragma once
#include <vector>
#include <cstdint>
#include "block.hpp"

// Serialize the BlockHeader into a byte array
std::vector<uint8_t> serializeHeader(const BlockHeader& header);

// Build the full block from header and transactions
std::vector<uint8_t> buildFullBlock(const BlockHeader& header, const std::vector<std::vector<uint8_t>>& txs);
