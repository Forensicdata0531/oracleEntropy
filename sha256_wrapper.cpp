#include "sha256_wrapper.hpp"
#include <openssl/evp.h>
#include <stdexcept>

void sha256(const uint8_t* data, size_t len, uint8_t* outHash) {
    EVP_MD_CTX* ctx = EVP_MD_CTX_new();
    if (!ctx) throw std::runtime_error("Failed to create EVP_MD_CTX");

    if (EVP_DigestInit_ex(ctx, EVP_sha256(), nullptr) != 1 ||
        EVP_DigestUpdate(ctx, data, len) != 1 ||
        EVP_DigestFinal_ex(ctx, outHash, nullptr) != 1) {
        EVP_MD_CTX_free(ctx);
        throw std::runtime_error("SHA256 digest operation failed");
    }

    EVP_MD_CTX_free(ctx);
}
