#ifndef METAL_MINER_HPP
#define METAL_MINER_HPP

#include "block.hpp"  // Include the block header with full BlockHeader definition

bool metalMineBlock(
    const BlockHeader& header,
    const std::vector<uint8_t>& target,
    uint32_t initialNonceBase,
    uint32_t& validNonce,
    std::vector<uint8_t>& validHash,
    uint64_t& totalHashesTried);

#endif // METAL_MINER_HPP

