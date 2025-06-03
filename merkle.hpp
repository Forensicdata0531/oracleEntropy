#pragma once
#include <vector>
#include <string>
#include "utils.hpp"

inline std::vector<uint8_t> calculateMerkleRoot(const std::vector<std::string>& txids) {
    std::vector<std::vector<uint8_t>> hashes;

    for (const std::string& txid : txids) {
        std::vector<uint8_t> hash = hexToBytes(txid);
        reverseBytes(hash);  // Bitcoin uses LE hashes in merkle
        hashes.push_back(hash);
    }

    if (hashes.empty()) return std::vector<uint8_t>(32, 0);

    while (hashes.size() > 1) {
        if (hashes.size() % 2 != 0) {
            hashes.push_back(hashes.back()); // duplicate last if odd
        }

        std::vector<std::vector<uint8_t>> newLevel;
        for (size_t i = 0; i < hashes.size(); i += 2) {
            std::vector<uint8_t> concat = hashes[i];
            concat.insert(concat.end(), hashes[i + 1].begin(), hashes[i + 1].end());
            newLevel.push_back(doubleSHA256(concat));
        }
        hashes = std::move(newLevel);
    }

    reverseBytes(hashes[0]); // Final result must be BE
    return hashes[0];
}
