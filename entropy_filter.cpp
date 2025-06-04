#include "entropy_metrics.hpp"
#include <cmath>
#include <bitset>
#include <vector>
#include <cstdint>

namespace entropy {

// Helper: count bits set in a byte
inline int popcount(uint8_t b) {
    return std::bitset<8>(b).count();
}

// Convert byte vector to bit vector (0 or 1 per bit)
std::vector<uint8_t> bytes_to_bitvec8(const std::vector<uint8_t>& bytes) {
    std::vector<uint8_t> bits;
    bits.reserve(bytes.size() * 8);
    for (uint8_t b : bytes) {
        for (int i = 7; i >= 0; --i) {
            bits.push_back((b >> i) & 1);
        }
    }
    return bits;
}

// Hamming distance between two byte arrays (bitwise XOR popcount)
int hamming_distance(const std::vector<uint8_t>& a, const std::vector<uint8_t>& b) {
    if (a.size() != b.size()) return -1;
    int dist = 0;
    for (size_t i = 0; i < a.size(); ++i) {
        dist += popcount(a[i] ^ b[i]);
    }
    return dist;
}

// Shannon entropy of bit vector (0s and 1s)
double shannon_entropy(const std::vector<uint8_t>& bits) {
    if (bits.empty()) return 0.0;
    double count0 = 0, count1 = 0;
    for (uint8_t bit : bits) {
        if (bit == 0) count0 += 1;
        else count1 += 1;
    }
    double p0 = count0 / bits.size();
    double p1 = count1 / bits.size();
    double entropy = 0.0;
    if (p0 > 0) entropy -= p0 * std::log2(p0);
    if (p1 > 0) entropy -= p1 * std::log2(p1);
    return entropy;
}

// Entropy slope: how much entropy changes per bit flip
std::vector<double> entropy_slope(const std::vector<uint8_t>& bits) {
    std::vector<double> slopes;
    slopes.reserve(bits.size());
    double base_entropy = shannon_entropy(bits);
    for (size_t i = 0; i < bits.size(); ++i) {
        std::vector<uint8_t> flipped = bits;
        flipped[i] ^= 1;
        double flipped_entropy = shannon_entropy(flipped);
        slopes.push_back(flipped_entropy - base_entropy);
    }
    return slopes;
}

// Total change in entropy after flipping each bit
double bit_flip_sensitivity(const std::vector<uint8_t>& bits) {
    double sensitivity = 0.0;
    double base_entropy = shannon_entropy(bits);
    for (size_t i = 0; i < bits.size(); ++i) {
        std::vector<uint8_t> flipped = bits;
        flipped[i] ^= 1;
        double flipped_entropy = shannon_entropy(flipped);
        sensitivity += std::abs(flipped_entropy - base_entropy);
    }
    return sensitivity;
}

} // namespace entropy
