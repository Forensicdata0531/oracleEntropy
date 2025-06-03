#pragma once
#include <nlohmann/json.hpp>
#include "block.hpp"

// Updated signature: accept JSON object directly
BlockHeader parseBlockHeader(const nlohmann::json& j);
