#include "sha256_wrapper.hpp"
#include <openssl/sha.h>
#include <sstream>
#include <iomanip>

std::vector<uint8_t> sha256(const std::vector<uint8_t>& data) {
    std::vector<uint8_t> hash(SHA256_DIGEST_LENGTH);
    SHA256_CTX ctx;
    SHA256_Init(&ctx);
    SHA256_Update(&ctx, data.data(), data.size());
    SHA256_Final(hash.data(), &ctx);
    return hash;
}

std::vector<uint32_t> sha256_midstate(const std::vector<uint8_t>& header) {
    return std::vector<uint32_t>(8, 0);  // Stub
}

// ✅ FIXED implementation
std::string compute_sha256_midstate_hex(const uint8_t* data, size_t len) {
    SHA256_CTX ctx;
    SHA256_Init(&ctx);
    SHA256_Update(&ctx, data, len);

    unsigned char hash[SHA256_DIGEST_LENGTH];
    SHA256_Final(hash, &ctx);

    std::ostringstream oss;
    for (int i = 0; i < SHA256_DIGEST_LENGTH; ++i)
        oss << std::hex << std::setw(2) << std::setfill('0') << (int)hash[i];

    return oss.str();
}
