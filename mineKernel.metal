#include <metal_stdlib>
using namespace metal;

constant uint32_t K[64] = {
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,
    0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,
    0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,
    0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,
    0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,
    0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,
    0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,
    0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,
    0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
};

inline simd::uint2 rotr(simd::uint2 x, uint n) {
    return (x >> n) | (x << (32 - n));
}

inline void sha256_compress(thread simd::uint2* w, thread simd::uint2* digest) {
    simd::uint2 a = digest[0];
    simd::uint2 b = digest[1];
    simd::uint2 c = digest[2];
    simd::uint2 d = digest[3];
    simd::uint2 e = digest[4];
    simd::uint2 f = digest[5];
    simd::uint2 g = digest[6];
    simd::uint2 h = digest[7];

    for (uint i = 16; i < 64; i++) {
        simd::uint2 s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
        simd::uint2 s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }

    for (uint i = 0; i < 64; i++) {
        simd::uint2 S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
        simd::uint2 ch = (e & f) ^ ((~e) & g);
        simd::uint2 temp1 = h + S1 + ch + simd::uint2(K[i]) + w[i];
        simd::uint2 S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
        simd::uint2 maj = (a & b) ^ (a & c) ^ (b & c);
        simd::uint2 temp2 = S0 + maj;

        h = g; g = f; f = e;
        e = d + temp1;
        d = c; c = b; b = a;
        a = temp1 + temp2;
    }

    digest[0] += a;
    digest[1] += b;
    digest[2] += c;
    digest[3] += d;
    digest[4] += e;
    digest[5] += f;
    digest[6] += g;
    digest[7] += h;
}

inline void sha256_double(thread simd::uint2* block, thread simd::uint2* digest) {
    simd::uint2 w[64];

    for (uint i = 0; i < 16; i++) w[i] = block[i];
    for (uint i = 16; i < 64; i++) {
        simd::uint2 s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
        simd::uint2 s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }

    sha256_compress(w, digest);

    // Prepare block for second SHA256 round (hash output + padding)
    thread simd::uint2 block2[16];
    for (uint i = 0; i < 8; i++) {
        uint32_t val = digest[i][0];
        block2[i] = simd::uint2(
            ((val & 0xff000000) >> 24) |
            ((val & 0x00ff0000) >> 8) |
            ((val & 0x0000ff00) << 8) |
            ((val & 0x000000ff) << 24),
            0); // Second lane is zero, process serially
    }
    block2[8] = simd::uint2(0x80000000, 0);
    for (uint i = 9; i < 15; i++) block2[i] = simd::uint2(0, 0);
    block2[15] = simd::uint2(256, 0);

    // Init IV for second round
    digest[0] = simd::uint2(0x6a09e667);
    digest[1] = simd::uint2(0xbb67ae85);
    digest[2] = simd::uint2(0x3c6ef372);
    digest[3] = simd::uint2(0xa54ff53a);
    digest[4] = simd::uint2(0x510e527f);
    digest[5] = simd::uint2(0x9b05688c);
    digest[6] = simd::uint2(0x1f83d9ab);
    digest[7] = simd::uint2(0x5be0cd19);

    sha256_compress(block2, digest);
}

inline void output_hash(const thread simd::uint2* digest, thread uint8_t* hash, uint lane) {
    for (uint i = 0; i < 8; i++) {
        uint32_t v = digest[i][lane];
        hash[i*4+0] = (v >> 24) & 0xff;
        hash[i*4+1] = (v >> 16) & 0xff;
        hash[i*4+2] = (v >> 8) & 0xff;
        hash[i*4+3] = (v >> 0) & 0xff;
    }
}

inline bool check_target(const thread uint8_t* hash, device const uint8_t* target) {
    for (int i = 31; i >= 0; i--) {
        if (hash[i] < target[i]) return true;
        if (hash[i] > target[i]) return false;
    }
    return false;
}

kernel void mineMidstateSIMD2(
    device const uint2* midstates [[ buffer(0) ]],  // bitsliced midstates, unused here
    device const uint2* tailWords [[ buffer(1) ]],  // tail + nonce area
    device const uint8_t* target [[ buffer(2) ]],
    device uint2* output [[ buffer(3) ]],           // output storage, unused here
    device atomic_uint* resultNonce [[ buffer(4) ]],
    device uint8_t* resultHashes [[ buffer(5) ]],
    uint tid [[ thread_position_in_grid ]]
) {
    const uint lane = tid & 1;
    const uint threadIdx = tid >> 1;
    if (threadIdx >= 131072) return;

    // Early abort if nonce found
    uint currentResultNonce = atomic_load_explicit(resultNonce, memory_order_relaxed);
    if (currentResultNonce != 0) return;

    // Reconstruct 80-byte block with nonce for both lanes
    thread uint8_t header_bytes[80];

    // Since we cannot reconstruct the original midstate bytes, zero out first 64 bytes here
    for (uint i = 0; i < 64; i++) header_bytes[i] = 0;

    // Unpack tailWords (bitsliced uint2) into last 8 bytes (64..71)
    uint tail_word0 = tailWords[threadIdx].x;
    uint tail_word1 = tailWords[threadIdx].y;

    header_bytes[64] = (tail_word0 >> 0) & 0xff;
    header_bytes[65] = (tail_word0 >> 8) & 0xff;
    header_bytes[66] = (tail_word0 >> 16) & 0xff;
    header_bytes[67] = (tail_word0 >> 24) & 0xff;

    header_bytes[68] = (tail_word1 >> 0) & 0xff;
    header_bytes[69] = (tail_word1 >> 8) & 0xff;
    header_bytes[70] = (tail_word1 >> 16) & 0xff;
    header_bytes[71] = (tail_word1 >> 24) & 0xff;

    // Load the current nonce base atomically
    uint baseNonce = atomic_load_explicit(resultNonce, memory_order_relaxed);
    if (baseNonce == 0) baseNonce = 0; // If none found, start at zero

    uint nonce = baseNonce + threadIdx * 2 + lane;
    header_bytes[76] = (nonce >> 0) & 0xff;
    header_bytes[77] = (nonce >> 8) & 0xff;
    header_bytes[78] = (nonce >> 16) & 0xff;
    header_bytes[79] = (nonce >> 24) & 0xff;

    // Prepare bitsliced block for double SHA-256
    thread simd::uint2 block[16];
    for (uint i = 0; i < 16; i++) {
        uint32_t w0 = (uint32_t(header_bytes[i*4 + 0]) << 24) |
                      (uint32_t(header_bytes[i*4 + 1]) << 16) |
                      (uint32_t(header_bytes[i*4 + 2]) << 8)  |
                      (uint32_t(header_bytes[i*4 + 3]));
        uint32_t w1 = w0; // Duplicate for bitslicing lane 1
        block[i] = simd::uint2(w0, w1);
    }

    // Initialize digest IV
    thread simd::uint2 digest[8];
    digest[0] = simd::uint2(0x6a09e667);
    digest[1] = simd::uint2(0xbb67ae85);
    digest[2] = simd::uint2(0x3c6ef372);
    digest[3] = simd::uint2(0xa54ff53a);
    digest[4] = simd::uint2(0x510e527f);
    digest[5] = simd::uint2(0x9b05688c);
    digest[6] = simd::uint2(0x1f83d9ab);
    digest[7] = simd::uint2(0x5be0cd19);

    // Perform double SHA256 compression
    sha256_double(block, digest);

    // Output hashes for both lanes
    thread uint8_t hash0[32];
    thread uint8_t hash1[32];
    output_hash(digest, hash0, 0);
    output_hash(digest, hash1, 1);

    // Check target against hashes
    bool valid0 = check_target(hash0, target);
    bool valid1 = check_target(hash1, target);

    // Atomically store nonce and hash if valid (lane 0)
    if (valid0) {
        uint expected = 0;
        if (atomic_compare_exchange_weak_explicit(resultNonce, &expected, nonce, memory_order_relaxed, memory_order_relaxed)) {
            for (uint i = 0; i < 32; i++) {
                resultHashes[tid * 64 + i] = hash0[i];
            }
        }
    }

    // Atomically store nonce and hash if valid (lane 1)
    if (valid1) {
        uint expected = 0;
        uint nonce1 = nonce + 1;
        if (atomic_compare_exchange_weak_explicit(resultNonce, &expected, nonce1, memory_order_relaxed, memory_order_relaxed)) {
            for (uint i = 0; i < 32; i++) {
                resultHashes[tid * 64 + 32 + i] = hash1[i];
            }
        }
    }
}
