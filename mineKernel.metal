#include <metal_stdlib>
using namespace metal;

constant uint32_t k[64] = {
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

inline void prepare_block(device const uint8_t* header80, uint32_t nonce0, uint32_t nonce1,
                          thread simd::uint2* block) {
    uint8_t buf0[80] = {0};
    uint8_t buf1[80] = {0};

    for (uint i = 0; i < 76; i++) {
        buf0[i] = header80[i];
        buf1[i] = header80[i];
    }

    buf0[76] = (nonce0 >> 0) & 0xff;
    buf0[77] = (nonce0 >> 8) & 0xff;
    buf0[78] = (nonce0 >> 16) & 0xff;
    buf0[79] = (nonce0 >> 24) & 0xff;

    buf1[76] = (nonce1 >> 0) & 0xff;
    buf1[77] = (nonce1 >> 8) & 0xff;
    buf1[78] = (nonce1 >> 16) & 0xff;
    buf1[79] = (nonce1 >> 24) & 0xff;

    for (uint i = 0; i < 16; i++) {
        uint32_t w0 = (uint32_t(buf0[i*4+0]) << 24) | (uint32_t(buf0[i*4+1]) << 16) |
                      (uint32_t(buf0[i*4+2]) << 8)  | (uint32_t(buf0[i*4+3]));

        uint32_t w1 = (uint32_t(buf1[i*4+0]) << 24) | (uint32_t(buf1[i*4+1]) << 16) |
                      (uint32_t(buf1[i*4+2]) << 8)  | (uint32_t(buf1[i*4+3]));

        block[i] = simd::uint2(w0, w1);
    }
}

inline void sha256_compress(thread simd::uint2* w, thread simd::uint2* digest) {
    simd::uint2 a = simd::uint2(0x6a09e667);
    simd::uint2 b = simd::uint2(0xbb67ae85);
    simd::uint2 c = simd::uint2(0x3c6ef372);
    simd::uint2 d = simd::uint2(0xa54ff53a);
    simd::uint2 e = simd::uint2(0x510e527f);
    simd::uint2 f = simd::uint2(0x9b05688c);
    simd::uint2 g = simd::uint2(0x1f83d9ab);
    simd::uint2 h = simd::uint2(0x5be0cd19);

    for (uint i = 0; i < 64; i++) {
        simd::uint2 S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
        simd::uint2 ch = (e & f) ^ ((~e) & g);
        simd::uint2 temp1 = h + S1 + ch + simd::uint2(k[i]) + w[i];
        simd::uint2 S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
        simd::uint2 maj = (a & b) ^ (a & c) ^ (b & c);
        simd::uint2 temp2 = S0 + maj;

        h = g; g = f; f = e;
        e = d + temp1;
        d = c; c = b; b = a;
        a = temp1 + temp2;
    }

    digest[0] = a + simd::uint2(0x6a09e667);
    digest[1] = b + simd::uint2(0xbb67ae85);
    digest[2] = c + simd::uint2(0x3c6ef372);
    digest[3] = d + simd::uint2(0xa54ff53a);
    digest[4] = e + simd::uint2(0x510e527f);
    digest[5] = f + simd::uint2(0x9b05688c);
    digest[6] = g + simd::uint2(0x1f83d9ab);
    digest[7] = h + simd::uint2(0x5be0cd19);
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

    // Serialize each lane and prepare second block
    thread uint8_t inter[2][32];
    for (uint i = 0; i < 8; i++) {
        uint32_t lo = digest[i][0];
        uint32_t hi = digest[i][1];
        inter[0][i*4+0] = (lo >> 24) & 0xff;
        inter[0][i*4+1] = (lo >> 16) & 0xff;
        inter[0][i*4+2] = (lo >> 8)  & 0xff;
        inter[0][i*4+3] = (lo >> 0)  & 0xff;

        inter[1][i*4+0] = (hi >> 24) & 0xff;
        inter[1][i*4+1] = (hi >> 16) & 0xff;
        inter[1][i*4+2] = (hi >> 8)  & 0xff;
        inter[1][i*4+3] = (hi >> 0)  & 0xff;
    }

    // Build new 64-byte padded blocks
    for (uint i = 0; i < 8; i++) {
        uint32_t w0 = (uint32_t(inter[0][i*4+0]) << 24) | (uint32_t(inter[0][i*4+1]) << 16) |
                      (uint32_t(inter[0][i*4+2]) << 8)  | (uint32_t(inter[0][i*4+3]));
        uint32_t w1 = (uint32_t(inter[1][i*4+0]) << 24) | (uint32_t(inter[1][i*4+1]) << 16) |
                      (uint32_t(inter[1][i*4+2]) << 8)  | (uint32_t(inter[1][i*4+3]));
        block[i] = simd::uint2(w0, w1);
    }
    block[8] = simd::uint2(0x80000000);
    for (uint i = 9; i < 15; i++) block[i] = simd::uint2(0);
    block[15] = simd::uint2(256); // 32 bytes = 256 bits

    for (uint i = 0; i < 16; i++) w[i] = block[i];
    for (uint i = 16; i < 64; i++) {
        simd::uint2 s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
        simd::uint2 s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }

    sha256_compress(w, digest);
}

inline void output_hash(const thread simd::uint2* digest, thread uint8_t* hash, uint lane) {
    for (uint i = 0; i < 8; i++) {
        uint32_t v = digest[i][lane];
        hash[i*4+0] = (v >> 24) & 0xff;
        hash[i*4+1] = (v >> 16) & 0xff;
        hash[i*4+2] = (v >> 8)  & 0xff;
        hash[i*4+3] = (v >> 0)  & 0xff;
    }
}

inline bool check_target(thread const uint8_t* hash, device const uint8_t* target) {
    for (uint i = 0; i < 32; i++) {
        if (hash[i] < target[i]) return true;
        if (hash[i] > target[i]) return false;
    }
    return false;
}

kernel void mineKernel(
    device const uint8_t* header80        [[buffer(0)]],
    device const uint8_t* target          [[buffer(1)]],
    device const uint32_t* nonceBasePtr   [[buffer(2)]],
    device atomic_uint* resultNonce       [[buffer(3)]],
    device uint8_t* resultHashes          [[buffer(4)]],
    uint tid                              [[thread_position_in_grid]]
) {
    uint nonce0 = *nonceBasePtr + tid * 2;
    uint nonce1 = nonce0 + 1;

    thread simd::uint2 block[16];
    thread simd::uint2 digest[8];
    thread uint8_t hash0[32], hash1[32];

    prepare_block(header80, nonce0, nonce1, block);
    sha256_double(block, digest);
    output_hash(digest, hash0, 0);
    output_hash(digest, hash1, 1);

    if (check_target(hash0, target)) {
        uint zero = 0;
        if (atomic_compare_exchange_weak_explicit(resultNonce, &zero, nonce0, memory_order_relaxed, memory_order_relaxed)) {
            for (uint i = 0; i < 32; i++) resultHashes[tid * 64 + i] = hash0[i];
        }
    }

    if (check_target(hash1, target)) {
        uint zero = 0;
        if (atomic_compare_exchange_weak_explicit(resultNonce, &zero, nonce1, memory_order_relaxed, memory_order_relaxed)) {
            for (uint i = 0; i < 32; i++) resultHashes[tid * 64 + 32 + i] = hash1[i];
        }
    }
}
