#include "block_utils.hpp"
#include "utils.hpp"
#include "coinbase.hpp" // ✅ Bech32 decoder implemented here

#include <sstream>
#include <iomanip>
#include <cstring>
#include <openssl/sha.h>
#include <stdexcept>

// Helper: convert vector<uint8_t> to array<uint8_t, 32>
std::array<uint8_t, 32> toArray32(const std::vector<uint8_t>& vec) {
    if (vec.size() != 32) throw std::runtime_error("Expected 32-byte vector");
    std::array<uint8_t, 32> arr;
    std::copy(vec.begin(), vec.end(), arr.begin());
    return arr;
}

// Parse block header JSON into BlockHeader struct
BlockHeader parseBlockHeader(const nlohmann::json& j) {
    BlockHeader h;
    h.version = j["version"];
    h.prevBlockHash = toArray32(hexToBytes(j["previousblockhash"]));
    h.merkleRoot = toArray32(hexToBytes(j["merkleroot"]));
    h.timestamp = j["time"];
    h.bits = j["bits"];
    h.nonce = j["nonce"];
    return h;
}

// Serialize a block header into 80-byte array
std::array<uint8_t, 80> serializeBlockHeader(const BlockHeader& h) {
    std::array<uint8_t, 80> out{};
    uint32_t versionLE = __builtin_bswap32(h.version);
    std::memcpy(out.data() + 0, &versionLE, 4);

    std::array<uint8_t, 32> prev = h.prevBlockHash;
    std::reverse(prev.begin(), prev.end());
    std::memcpy(out.data() + 4, prev.data(), 32);

    std::array<uint8_t, 32> merkle = h.merkleRoot;
    std::reverse(merkle.begin(), merkle.end());
    std::memcpy(out.data() + 36, merkle.data(), 32);

    uint32_t timeLE = __builtin_bswap32(h.timestamp);
    std::memcpy(out.data() + 68, &timeLE, 4);

    uint32_t bitsLE = __builtin_bswap32(h.bits);
    std::memcpy(out.data() + 72, &bitsLE, 4);

    uint32_t nonceLE = __builtin_bswap32(h.nonce);
    std::memcpy(out.data() + 76, &nonceLE, 4);

    return out;
}

// Convert compact bits string to 32-byte full target
std::vector<uint8_t> bitsToTarget(const std::string& bitsStr) {
    uint32_t bits = std::stoul(bitsStr, nullptr, 16);
    uint32_t exponent = bits >> 24;
    uint32_t mantissa = bits & 0xFFFFFF;

    std::vector<uint8_t> target(32, 0);
    int index = exponent - 3;

    if (index < 0 || index + 3 > 32) return target;

    target[index] = (mantissa >> 16) & 0xFF;
    target[index + 1] = (mantissa >> 8) & 0xFF;
    target[index + 2] = mantissa & 0xFF;
    return target;
}

// Convert full target to compact bits format
std::string targetToBits(const std::vector<uint8_t>& target) {
    size_t i = 0;
    while (i < 32 && target[i] == 0) ++i;

    uint32_t mantissa = 0;
    if (i + 3 <= 32) {
        mantissa |= target[i] << 16;
        mantissa |= target[i + 1] << 8;
        mantissa |= target[i + 2];
    }

    uint32_t bits = ((32 - i) << 24) | mantissa;
    std::stringstream ss;
    ss << std::hex << std::setw(8) << std::setfill('0') << bits;
    return ss.str();
}

// Assemble full block
std::string createFullBlockHex(const BlockHeader& header, uint32_t validIndex,
                               const std::string& coinbaseHex,
                               const nlohmann::json& txs) {
    std::vector<uint8_t> block;
    auto headerBytes = serializeBlockHeader(header);
    block.insert(block.end(), headerBytes.begin(), headerBytes.end());

    uint8_t txCount = static_cast<uint8_t>(1 + txs.size());
    block.push_back(txCount);

    std::vector<uint8_t> coinbase = hexToBytes(coinbaseHex);
    block.insert(block.end(), coinbase.begin(), coinbase.end());

    for (const auto& tx : txs) {
        std::vector<uint8_t> txBytes = hexToBytes(tx["data"]);
        block.insert(block.end(), txBytes.begin(), txBytes.end());
    }

    return bytesToHex(block);
}
