#pragma once
#include <vector>
#include <cstdint>
#include <cstring>
#include <string>
#include <iostream>

// Implement SHA-256 for C++ or include a library (use a placeholder here)
#include <openssl/sha.h>

// Double SHA-256 function for Bitcoin
inline std::vector<uint8_t> doubleSHA256(const std::vector<uint8_t>& data) {
    uint8_t hash1[SHA256_DIGEST_LENGTH];
    SHA256_CTX sha256;
    SHA256_Init(&sha256);
    SHA256_Update(&sha256, data.data(), data.size());
    SHA256_Final(hash1, &sha256);

    uint8_t hash2[SHA256_DIGEST_LENGTH];
    SHA256_Init(&sha256);
    SHA256_Update(&sha256, hash1, SHA256_DIGEST_LENGTH);
    SHA256_Final(hash2, &sha256);

    return std::vector<uint8_t>(hash2, hash2 + SHA256_DIGEST_LENGTH);
}

inline void printHash(const std::vector<uint8_t>& hash) {
    for (auto byte : hash) {
        printf("%02x", byte);
    }
    printf("\n");
}
