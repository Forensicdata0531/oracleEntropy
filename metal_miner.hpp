#ifndef METAL_MINER_HPP
#define METAL_MINER_HPP

#include "block.hpp"
#include <vector>
#include <cstdint>

using ByteVector = std::vector<uint8_t>;

bool metalMineBlock(
    const BlockHeader& header,
    const std::vector<uint8_t>& target,
    uint32_t initialNonceBase,
    uint32_t& validIndex,
    std::vector<uint8_t>& validHash,
    std::vector<uint8_t>& sampleHashOut,
    uint64_t& totalHashesTried);

#endif // METAL_MINER_HPP
