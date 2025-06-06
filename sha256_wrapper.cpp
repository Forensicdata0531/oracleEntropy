#include "sha256_wrapper.hpp"
#include <openssl/sha.h>
#include <sstream>
#include <iomanip>
#include <stdexcept>

// Full SHA-256 hash
std::vector<uint8_t> sha256(const std::vector<uint8_t>& data) {
    std::vector<uint8_t> hash(SHA256_DIGEST_LENGTH);
    SHA256_CTX ctx;
    SHA256_Init(&ctx);
    SHA256_Update(&ctx, data.data(), data.size());
    SHA256_Final(hash.data(), &ctx);
    return hash;
}

// Midstate as 8-word vector
std::vector<uint32_t> sha256_midstate(const std::vector<uint8_t>& header) {
    if (header.size() != 64)
        throw std::runtime_error("sha256_midstate expects exactly 64 bytes");

    SHA256_CTX ctx;
    SHA256_Init(&ctx);
    SHA256_Update(&ctx, header.data(), header.size());

    std::vector<uint32_t> midstate(8);
    for (int i = 0; i < 8; ++i) {
        midstate[i] = ctx.h[i];  // Raw internal SHA256 state
    }
    return midstate;
}

// Midstate as hex string (big-endian)
std::string compute_sha256_midstate_hex(const uint8_t* data, size_t len) {
    if (len != 64)
        throw std::runtime_error("compute_sha256_midstate_hex expects exactly 64 bytes");

    SHA256_CTX ctx;
    SHA256_Init(&ctx);
    SHA256_Update(&ctx, data, len);

    std::ostringstream oss;
    for (int i = 0; i < 8; ++i) {
        uint32_t h = ctx.h[i];
        for (int b = 3; b >= 0; --b)
            oss << std::hex << std::setw(2) << std::setfill('0') << ((h >> (b * 8)) & 0xff);
    }

    return oss.str();
}
