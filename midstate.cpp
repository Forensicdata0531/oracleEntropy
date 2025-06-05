#include "midstate.hpp"
#include <fstream>
#include <iostream>
#include <nlohmann/json.hpp>
#include "utils.hpp"  // For hexToBytes

std::vector<MidstateEntry> loadMidstates(const std::string& filename) {
    std::ifstream file(filename);
    if (!file.is_open()) {
        std::cerr << "Failed to open midstate file: " << filename << std::endl;
        return {};
    }

    nlohmann::json j;
    try {
        file >> j;
    } catch (const std::exception& e) {
        std::cerr << "JSON parse error: " << e.what() << std::endl;
        return {};
    }

    if (!j.is_array()) {
        std::cerr << "Midstates JSON is not an array!\n" << j.dump(2) << std::endl;
        return {};
    }

    std::vector<MidstateEntry> entries;
    for (const auto& item : j) {
        MidstateEntry e;

        // Convert midstate hex string to bytes
        std::string midstateHex = item["midstate"].get<std::string>();
        std::vector<uint8_t> midBytes = hexToBytes(midstateHex);
        if (midBytes.size() != 32) {
            std::cerr << "Invalid midstate length, expected 32 bytes but got " << midBytes.size() << std::endl;
            continue;
        }

        // Pack bytes into 8 uint32_t elements in LITTLE-ENDIAN
        for (int i = 0; i < 8; ++i) {
            e.midstate[i] = 
                (uint32_t(midBytes[i * 4 + 3]) << 24) |
                (uint32_t(midBytes[i * 4 + 2]) << 16) |
                (uint32_t(midBytes[i * 4 + 1]) << 8)  |
                (uint32_t(midBytes[i * 4 + 0]));
        }

        // Convert tail hex string to uint32_t (4 bytes) in LITTLE-ENDIAN
        std::string tailHex = item["tail"].get<std::string>();
        std::vector<uint8_t> tailBytes = hexToBytes(tailHex);
        if (tailBytes.size() < 4) {
            std::cerr << "Invalid tail length, expected at least 4 bytes but got " << tailBytes.size() << std::endl;
            continue;
        }

        e.tail = 
            (uint32_t(tailBytes[3]) << 24) |
            (uint32_t(tailBytes[2]) << 16) |
            (uint32_t(tailBytes[1]) << 8)  |
            (uint32_t(tailBytes[0]));

        entries.push_back(e);
    }

    return entries;
}
