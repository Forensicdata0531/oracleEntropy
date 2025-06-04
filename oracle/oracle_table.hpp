// oracle_table.hpp
#pragma once
#include <unordered_map>
#include <string>

// Map: prefix (like "6b") → frequency count
using MidstateHistogram = std::unordered_map<std::string, int>;

// Function declarations
MidstateHistogram buildMidstateHistogram(const std::string& jsonPath);
double scoreByHistogram(const std::string& midstateHex, const MidstateHistogram& hist);
