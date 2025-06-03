#ifndef SHA256_COMPRESS_HPP
#define SHA256_COMPRESS_HPP

#include <cstdint>
#include <array>

// Compress one 64-byte block and update the SHA256 state
// Input:
//   block: pointer to 64 bytes of data
//   state: current SHA256 state (8 uint32_t words)
// Output:
//   state is updated with the compressed values
void sha256_compress(const uint8_t block[64], std::array<uint32_t, 8>& state);

#endif // SHA256_COMPRESS_HPP
