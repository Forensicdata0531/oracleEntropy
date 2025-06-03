#pragma once
#include <vector>
#include <cstdint>

// Represents the internal state (midstate) of a SHA256 hash computation
struct Midstate {
    uint32_t h[8];

    Midstate() {
        for (int i = 0; i < 8; ++i)
            h[i] = 0;
    }
};

// Extracts midstate from a raw header (placeholder implementation)
Midstate extract_midstate(const uint8_t* header, size_t header_len);

// Calculates midstate by hashing the input header with SHA256.
// Attempts to extract the internal SHA256 state if possible.
// If not supported on the platform, returns zeroed midstate.
Midstate calculateMidstate(const std::vector<uint8_t>& header);
