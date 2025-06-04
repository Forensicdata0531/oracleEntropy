#pragma once
#include <nlohmann/json.hpp>
#include "block.hpp"

BlockHeader parseBlockHeader(const nlohmann::json& j);
std::array<uint8_t, 80> serializeBlockHeader(const BlockHeader& header);
