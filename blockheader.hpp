// blockheader.hpp
#pragma once
#include <string>
#include <sstream>
#include <iomanip>
#include "utils.hpp"

inline std::string reverseHex(const std::string& hex) {
    std::string out;
    for (int i = hex.size(); i > 0; i -= 2) {
        out += hex.substr(i - 2, 2);
    }
    return out;
}

inline std::string buildBlockHeader(uint32_t version, const std::string& prevBlockHash,
                             const std::string& merkleRoot, uint32_t timestamp,
                             uint32_t bits, uint32_t nonce) {
    std::ostringstream ss;
    ss << intToLittleEndianHex(version, 4);
    ss << reverseHex(prevBlockHash);
    ss << reverseHex(merkleRoot);
    ss << intToLittleEndianHex(timestamp, 4);
    ss << intToLittleEndianHex(bits, 4);
    ss << intToLittleEndianHex(nonce, 4);
    return ss.str();
}
