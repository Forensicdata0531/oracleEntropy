#include "entropy_metrics.hpp"
#include <cstring>
#include <cmath>
#include <iostream>

// Hamming distance implementation
int hammingDistance(const uint8_t* a, const uint8_t* b, size_t length) {
    int dist = 0;
    for (size_t i = 0; i < length; i++) {
        uint8_t val = a[i] ^ b[i];
        dist += __builtin_popcount(val);
    }
    return dist;
}

// Shannon entropy implementation
double shannonEntropy(const uint8_t* data, size_t length) {
    int counts[256] = {0};
    for (size_t i = 0; i < length; i++) {
        counts[data[i]]++;
    }
    double entropy = 0.0;
    for (int i = 0; i < 256; i++) {
        if (counts[i] == 0) continue;
        double p = (double)counts[i] / length;
        entropy -= p * log2(p);
    }
    return entropy;
}

// Entropy slope example (difference between entropy of prev and curr)
double entropySlope(const std::vector<uint8_t>& prev, const std::vector<uint8_t>& curr) {
    double prevEntropy = shannonEntropy(prev.data(), prev.size());
    double currEntropy = shannonEntropy(curr.data(), curr.size());
    return currEntropy - prevEntropy;
}

// Bit flip sensitivity - count how many bits differ when flipping each bit in input one at a time
int bitFlipSensitivity(const uint8_t* input, size_t length) {
    // Placeholder - real implementation would require hashing output difference
    // Here, simply return the number of bits set in input as a demo
    int sensitivity = 0;
    for (size_t i = 0; i < length; i++) {
        sensitivity += __builtin_popcount(input[i]);
    }
    return sensitivity;
}


