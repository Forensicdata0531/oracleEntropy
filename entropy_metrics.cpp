#include "entropy_metrics.hpp"
#include "utils.hpp"
#include <cmath>

// Calculate the SHA256 midstate (already done in utils, just alias here)
std::vector<uint8_t> calculateSHA256Midstate(const std::vector<uint8_t>& headerPrefix) {
    // Return first 64 bytes midstate as bytes
    // We can reuse calculateMidstate and convert uint32_t array to bytes
    auto midstateWords = calculateMidstateArray(headerPrefix);
    std::vector<uint8_t> midstateBytes(32);
    for (int i = 0; i < 8; ++i) {
        uint32_t word = midstateWords[i];
        midstateBytes[i*4 + 0] = (word >> 24) & 0xff;
        midstateBytes[i*4 + 1] = (word >> 16) & 0xff;
        midstateBytes[i*4 + 2] = (word >> 8) & 0xff;
        midstateBytes[i*4 + 3] = (word >> 0) & 0xff;
    }
    return midstateBytes;
}

// Calculate Shannon entropy of byte array normalized between 0 and 8 bits per byte
double entropyMetric(const std::vector<uint8_t>& data) {
    if (data.empty()) return 0.0;
    int counts[256] = {0};
    for (auto b : data) counts[b]++;
    double entropy = 0.0;
    double len = (double)data.size();

    for (int i = 0; i < 256; i++) {
        if (counts[i] == 0) continue;
        double p = counts[i] / len;
        entropy -= p * log2(p);
    }
    return entropy;
}

// Simple example: entropy score from nonce value (dummy)
double blockEntropyScore(uint64_t nonce) {
    // Map nonce to bytes and compute entropy (dummy implementation)
    std::vector<uint8_t> bytes(8);
    for (int i = 0; i < 8; i++) {
        bytes[i] = (nonce >> (8 * i)) & 0xff;
    }
    return entropyMetric(bytes);
}

