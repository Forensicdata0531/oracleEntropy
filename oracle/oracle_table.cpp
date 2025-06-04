#include "oracle_table.hpp"
#include <fstream>
#include <iostream>      // Added this to fix std::cerr error
#include <nlohmann/json.hpp>
#include <algorithm>

MidstateHistogram buildMidstateHistogram(const std::string& jsonPath) {
    MidstateHistogram hist;
    std::ifstream in(jsonPath);
    if (!in) {
        std::cerr << "[ERROR] Failed to open: " << jsonPath << std::endl;
        return hist;
    }

    nlohmann::json j;
    in >> j;
    for (const auto& entry : j) {
        if (!entry.contains("midstate")) continue;
        std::string hex = entry["midstate"];
        if (hex.length() < 2) continue;
        std::string prefix = hex.substr(0, 2);  // First byte hex string
        hist[prefix]++;
    }

    return hist;
}

double scoreByHistogram(const std::string& midstateHex, const MidstateHistogram& hist) {
    if (midstateHex.size() < 2) return 0.0;
    std::string prefix = midstateHex.substr(0, 2);
    auto it = hist.find(prefix);
    if (it == hist.end()) return 0.0;

    int maxCount = std::max_element(hist.begin(), hist.end(),
        [](const auto& a, const auto& b) {
            return a.second < b.second;
        })->second;

    return static_cast<double>(it->second) / maxCount;
}
