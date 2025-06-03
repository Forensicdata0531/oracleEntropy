#ifndef SHA256_WRAPPER_H
#define SHA256_WRAPPER_H

#include <cstdint>
#include <cstddef>

// Computes SHA-256 hash of the input data buffer.
// - data: pointer to the input data bytes
// - len: length of the input data in bytes
// - outHash: pointer to a buffer of at least 32 bytes where the hash will be stored
void sha256(const uint8_t* data, size_t len, uint8_t* outHash);

#endif // SHA256_WRAPPER_H

