#pragma once
#include <vector>
#include <string>
#include <cstdint>

// Represents a midstate entry with 8 uint32_t values and a tail
struct MidstateEntry {
    uint32_t midstate[8];
    uint32_t tail;
};

// Loads midstates from a JSON file and returns a vector of MidstateEntry
std::vector<MidstateEntry> loadMidstates(const std::string& filename);
