#pragma once
#include <array>
#include <vector>
#include <algorithm>
#include <stdexcept>
#include <string>

// Convert std::vector<uint8_t> of size 32 into std::array<uint8_t, 32>
inline std::array<uint8_t, 32> to_array_32(const std::vector<uint8_t>& vec) {
    if (vec.size() != 32) {
        throw std::invalid_argument("Vector must be 32 bytes");
    }
    std::array<uint8_t, 32> arr;
    std::copy(vec.begin(), vec.end(), arr.begin());
    return arr;
}

// Compare two 32-byte hashes (big-endian comparison)
// Returns:
//   -1 if a < b
//    0 if a == b
//    1 if a > b
inline int hashCompare(const std::array<uint8_t, 32>& a, const std::array<uint8_t, 32>& b) {
    for (size_t i = 0; i < 32; ++i) {
        if (a[i] < b[i]) return -1;
        if (a[i] > b[i]) return 1;
    }
    return 0;
}

// Check if hash <= target
inline bool isHashLessOrEqual(const std::array<uint8_t, 32>& hash,
                              const std::array<uint8_t, 32>& target) {
    return hashCompare(hash, target) <= 0;
}

// Convert fixed-size array to hex string
inline std::string toHex(const std::array<uint8_t, 32>& arr) {
    const char hexmap[] = "0123456789abcdef";
    std::string s;
    s.reserve(64);
    for (auto b : arr) {
        s += hexmap[(b >> 4) & 0xF];
        s += hexmap[b & 0xF];
    }
    return s;
}

// Overload toHex for vector<uint8_t>
inline std::string toHex(const std::vector<uint8_t>& vec) {
    const char hexmap[] = "0123456789abcdef";
    std::string s;
    s.reserve(vec.size() * 2);
    for (auto b : vec) {
        s += hexmap[(b >> 4) & 0xF];
        s += hexmap[b & 0xF];
    }
    return s;
}
