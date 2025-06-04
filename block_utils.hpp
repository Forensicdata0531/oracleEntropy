#pragma once
#include <nlohmann/json.hpp>
#include "block.hpp"
#include <string>
#include <vector>

// Block header parsing and serialization
BlockHeader parseBlockHeader(const nlohmann::json& j);
std::array<uint8_t, 80> serializeBlockHeader(const BlockHeader& header);

// Full block hex constructor
std::string createFullBlockHex(const BlockHeader& header, uint32_t validIndex,
                               const std::string& coinbaseHex,
                               const nlohmann::json& transactions);

// Declare only - no definitions or default arguments here!
std::string createCoinbaseTx(int height, const std::string& payoutAddress, const std::string& extraData);
std::vector<uint8_t> bech32Decode(const std::string& addr);
