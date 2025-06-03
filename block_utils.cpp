#include "block_utils.hpp"
#include <stdexcept>
#include <sstream>

using json = nlohmann::json;

// Helper to parse hex string and reverse bytes for little endian
static std::array<uint8_t, 32> parseReversedHash(const std::string& hexStr) {
    if (hexStr.size() != 64) {
        std::ostringstream oss;
        oss << "Invalid hex string length for hash: expected 64 but got " << hexStr.size();
        throw std::runtime_error(oss.str());
    }

    std::array<uint8_t, 32> result;
    for (int i = 0; i < 32; ++i) {
        std::string byteStr = hexStr.substr((31 - i) * 2, 2);
        try {
            result[i] = static_cast<uint8_t>(std::stoul(byteStr, nullptr, 16));
        } catch (const std::exception& e) {
            throw std::runtime_error("Invalid hex character in hash string");
        }
    }
    return result;
}

BlockHeader parseBlockHeader(const json& j) {
    BlockHeader header;

    if (!j.contains("version") || j["version"].is_null())
        throw std::runtime_error("JSON missing or null 'version' field");
    header.version = j.at("version").get<uint32_t>();

    if (!j.contains("previousblockhash") || j["previousblockhash"].is_null())
        throw std::runtime_error("JSON missing or null 'previousblockhash' field");
    header.prevBlockHash = parseReversedHash(j.at("previousblockhash").get<std::string>());

    if (!j.contains("merkleroot") || j["merkleroot"].is_null())
        throw std::runtime_error("JSON missing or null 'merkleroot' field");
    header.merkleRoot = parseReversedHash(j.at("merkleroot").get<std::string>());

    if (!j.contains("curtime") || j["curtime"].is_null())
        throw std::runtime_error("JSON missing or null 'curtime' field");
    header.timestamp = j.at("curtime").get<uint32_t>();

    if (!j.contains("bits") || j["bits"].is_null())
        throw std::runtime_error("JSON missing or null 'bits' field");
    header.bits = std::stoul(j.at("bits").get<std::string>(), nullptr, 16);

    header.nonce = 0;
    return header;
}
