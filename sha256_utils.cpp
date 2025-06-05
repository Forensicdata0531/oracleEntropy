#include "sha256_utils.hpp"
#include <openssl/sha.h>

std::vector<uint8_t> sha256(const std::vector<uint8_t>& data) {
    std::vector<uint8_t> hash(SHA256_DIGEST_LENGTH);
    SHA256_CTX sha256;
    SHA256_Init(&sha256);
    SHA256_Update(&sha256, data.data(), data.size());
    SHA256_Final(hash.data(), &sha256);
    return hash;
}

std::vector<uint8_t> sha256Double(const std::vector<uint8_t>& data) {
    return sha256(sha256(data));
}
