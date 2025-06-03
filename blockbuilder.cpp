// blockbuilder.cpp
#include "blockbuilder.hpp"
#include "utils.hpp"
#include <stdexcept>
#include <algorithm> // for std::reverse

// Serialize the BlockHeader fields in correct order (little-endian)
std::vector<uint8_t> serializeHeader(const BlockHeader& header) {
    std::vector<uint8_t> out;

    auto appendLE = [&](auto value, size_t size) {
        for (size_t i = 0; i < size; ++i)
            out.push_back(static_cast<uint8_t>(value >> (8 * i)));
    };

    appendLE(header.version, 4);

    std::vector<uint8_t> prevLE = header.prevBlockHash;
    std::reverse(prevLE.begin(), prevLE.end());
    out.insert(out.end(), prevLE.begin(), prevLE.end());

    std::vector<uint8_t> merkleLE = header.merkleRoot;
    std::reverse(merkleLE.begin(), merkleLE.end());
    out.insert(out.end(), merkleLE.begin(), merkleLE.end());

    appendLE(header.timestamp, 4);
    appendLE(header.bits, 4);
    appendLE(header.nonce, 4);

    return out;
}

std::vector<uint8_t> buildFullBlock(const BlockHeader& header, const std::vector<std::vector<uint8_t>>& txs) {
    std::vector<uint8_t> block;

    // Serialize the block header
    auto headerBytes = serializeHeader(header);
    block.insert(block.end(), headerBytes.begin(), headerBytes.end());

    // Add VarInt for number of transactions
    auto varint = encodeVarInt(txs.size());
    block.insert(block.end(), varint.begin(), varint.end());

    // Append each transaction
    for (const auto& tx : txs)
        block.insert(block.end(), tx.begin(), tx.end());

    return block;
}
