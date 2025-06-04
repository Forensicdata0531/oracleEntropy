#include "block_utils.hpp"
#include <stdexcept>
#include <sstream>
#include <cstring>

using json = nlohmann::json;

static std::array<uint8_t, 32> parseReversedHash(const std::string& hexStr) {
    if (hexStr.size() != 64)
        throw std::runtime_error("Invalid hex length for hash");

    std::array<uint8_t, 32> result;
    for (int i = 0; i < 32; ++i) {
        std::string byteStr = hexStr.substr((31 - i) * 2, 2);
        result[i] = static_cast<uint8_t>(std::stoul(byteStr, nullptr, 16));
    }
    return result;
}

BlockHeader parseBlockHeader(const json& j) {
    BlockHeader header;
    header.version = j.at("version").get<uint32_t>();
    header.prevBlockHash = parseReversedHash(j.at("previousblockhash"));
    header.merkleRoot = parseReversedHash(j.at("merkleroot"));
    header.timestamp = j.at("curtime").get<uint32_t>();
    header.bits = std::stoul(j.at("bits").get<std::string>(), nullptr, 16);
    header.nonce = 0;
    return header;
}

static void writeLE(uint8_t* dst, uint32_t value) {
    dst[0] = value & 0xFF;
    dst[1] = (value >> 8) & 0xFF;
    dst[2] = (value >> 16) & 0xFF;
    dst[3] = (value >> 24) & 0xFF;
}

std::array<uint8_t, 80> serializeBlockHeader(const BlockHeader& h) {
    std::array<uint8_t, 80> out{};
    writeLE(out.data(), h.version);
    std::memcpy(out.data() + 4, h.prevBlockHash.data(), 32);
    std::memcpy(out.data() + 36, h.merkleRoot.data(), 32);
    writeLE(out.data() + 68, h.timestamp);
    writeLE(out.data() + 72, h.bits);
    writeLE(out.data() + 76, h.nonce);
    return out;
}
