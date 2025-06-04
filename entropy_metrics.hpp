#pragma once
#include <vector>
#include <cstdint>
#include <cmath>

namespace entropy {

// Convert a byte vector to a vector of bits
std::vector<bool> bytes_to_bits(const std::vector<uint8_t>& bytes) {
    std::vector<bool> bits;
    for (uint8_t byte : bytes) {
        for (int i = 7; i >= 0; --i) {
            bits.push_back((byte >> i) & 1);
        }
    }
    return bits;
}

// Compute Hamming distance between two bit arrays
int hamming_distance(const std::vector<bool>& a, const std::vector<bool>& b) {
    if (a.size() != b.size()) return -1;
    int dist = 0;
    for (size_t i = 0; i < a.size(); ++i) {
        if (a[i] != b[i]) ++dist;
    }
    return dist;
}

// Compute Shannon entropy of a bit vector (0 or 1)
double shannon_entropy(const std::vector<bool>& bits) {
    int count1 = 0;
    for (bool b : bits) count1 += b;
    int count0 = bits.size() - count1;

    double p0 = static_cast<double>(count0) / bits.size();
    double p1 = static_cast<double>(count1) / bits.size();

    double entropy = 0.0;
    if (p0 > 0.0) entropy -= p0 * std::log2(p0);
    if (p1 > 0.0) entropy -= p1 * std::log2(p1);

    return entropy;
}

// Entropy slope = sensitivity to flipping each bit
std::vector<double> entropy_slope(const std::vector<bool>& bits) {
    std::vector<double> slope(bits.size());
    double base_entropy = shannon_entropy(bits);

    for (size_t i = 0; i < bits.size(); ++i) {
        std::vector<bool> flipped = bits;
        flipped[i] = !flipped[i];
        double flipped_entropy = shannon_entropy(flipped);
        slope[i] = std::abs(flipped_entropy - base_entropy);
    }

    return slope;
}

// Sum of entropy changes after flipping each bit
double bit_flip_sensitivity(const std::vector<bool>& bits) {
    double total = 0.0;
    double base_entropy = shannon_entropy(bits);

    for (size_t i = 0; i < bits.size(); ++i) {
        std::vector<bool> flipped = bits;
        flipped[i] = !flipped[i];
        double flipped_entropy = shannon_entropy(flipped);
        total += std::abs(flipped_entropy - base_entropy);
    }

    return total;
}

} // namespace entropy
