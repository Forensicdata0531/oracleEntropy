#include <metal_stdlib>
using namespace metal;

// SHA-256 constants
typedef uint32_t u32;
constant u32 k[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
};

constant u32 h0_init[8] = {
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
};

inline u32 ROTR(u32 x, u32 n) {
    return (x >> n) | (x << (32 - n));
}

inline u32 Ch(u32 x, u32 y, u32 z) {
    return (x & y) ^ (~x & z);
}

inline u32 Maj(u32 x, u32 y, u32 z) {
    return (x & y) ^ (x & z) ^ (y & z);
}

inline u32 Sigma0(u32 x) {
    return ROTR(x, 2) ^ ROTR(x, 13) ^ ROTR(x, 22);
}

inline u32 Sigma1(u32 x) {
    return ROTR(x, 6) ^ ROTR(x, 11) ^ ROTR(x, 25);
}

inline u32 sigma0(u32 x) {
    return ROTR(x, 7) ^ ROTR(x, 18) ^ (x >> 3);
}

inline u32 sigma1(u32 x) {
    return ROTR(x, 17) ^ ROTR(x, 19) ^ (x >> 10);
}

inline void sha256_transform(const device uint8_t *data, device u32 *state) {
    u32 w[64];
    for (uint i = 0; i < 16; i++) {
        w[i] = (u32(data[i * 4]) << 24) | (u32(data[i * 4 + 1]) << 16) |
               (u32(data[i * 4 + 2]) << 8) | u32(data[i * 4 + 3]);
    }
    for (uint i = 16; i < 64; i++) {
        w[i] = sigma1(w[i - 2]) + w[i - 7] + sigma0(w[i - 15]) + w[i - 16];
    }

    u32 a = state[0];
    u32 b = state[1];
    u32 c = state[2];
    u32 d = state[3];
    u32 e = state[4];
    u32 f = state[5];
    u32 g = state[6];
    u32 h = state[7];

    for (uint i = 0; i < 64; i++) {
        u32 T1 = h + Sigma1(e) + Ch(e, f, g) + k[i] + w[i];
        u32 T2 = Sigma0(a) + Maj(a, b, c);
        h = g;
        g = f;
        f = e;
        e = d + T1;
        d = c;
        c = b;
        b = a;
        a = T1 + T2;
    }

    state[0] += a;
    state[1] += b;
    state[2] += c;
    state[3] += d;
    state[4] += e;
    state[5] += f;
    state[6] += g;
    state[7] += h;
}

inline void sha256(const device uint8_t *data, uint len, device u32 *hash) {
    for (uint i = 0; i < 8; i++) hash[i] = h0_init[i];

    uint8_t block[64] = {0};
    for (uint i = 0; i < len; i++) {
        block[i] = data[i];
    }
    block[len] = 0x80;

    uint bitLen = len * 8;
    block[63] = bitLen & 0xff;
    block[62] = (bitLen >> 8) & 0xff;
    block[61] = (bitLen >> 16) & 0xff;
    block[60] = (bitLen >> 24) & 0xff;

    sha256_transform(block, hash);
}

inline void double_sha256(const device uint8_t *data, uint len, device u32 *hash_out) {
    u32 hash1[8];
    sha256(data, len, hash1);

    uint8_t temp[32];
    for (uint i = 0; i < 8; i++) {
        temp[i * 4 + 0] = (hash1[i] >> 24) & 0xff;
        temp[i * 4 + 1] = (hash1[i] >> 16) & 0xff;
        temp[i * 4 + 2] = (hash1[i] >> 8) & 0xff;
        temp[i * 4 + 3] = (hash1[i]) & 0xff;
    }
    sha256(temp, 32, hash_out);
}

// ✅ UPDATED FUNCTION MATCHING metal_miner.mm BUFFER LAYOUT
kernel void mineKernel(
    device const uint8_t *blockHeader [[ buffer(0) ]],   // 76-byte header
    device const uint8_t *target [[ buffer(1) ]],        // 32-byte target
    device atomic_uint *resultNonce [[ buffer(2) ]],     // atomic nonce
    device const uint *nonceBasePtr [[ buffer(3) ]],     // base nonce
    device uint8_t *resultHash [[ buffer(4) ]],          // hash output
    uint id [[thread_position_in_grid]]
) {
    uint nonce = nonceBasePtr[0] + id;

    uint8_t header[80];
    for (uint i = 0; i < 76; i++) {
        header[i] = blockHeader[i];
    }
    header[76] = (nonce >> 0) & 0xff;
    header[77] = (nonce >> 8) & 0xff;
    header[78] = (nonce >> 16) & 0xff;
    header[79] = (nonce >> 24) & 0xff;

    u32 hash[8];
    double_sha256(header, 80, hash);

    uint8_t hashBytes[32];
    for (uint i = 0; i < 8; i++) {
        hashBytes[i * 4 + 0] = (hash[i] >> 24) & 0xff;
        hashBytes[i * 4 + 1] = (hash[i] >> 16) & 0xff;
        hashBytes[i * 4 + 2] = (hash[i] >> 8) & 0xff;
        hashBytes[i * 4 + 3] = (hash[i]) & 0xff;
    }

    bool isValid = true;
    for (int i = 31; i >= 0; i--) {
        if (hashBytes[i] < target[i]) break;
        if (hashBytes[i] > target[i]) {
            isValid = false;
            break;
        }
    }

    if (isValid) {
        uint expected = 0xFFFFFFFF;
        bool stored = atomic_compare_exchange_weak_explicit(resultNonce, &expected, nonce,
                                                             memory_order_relaxed, memory_order_relaxed);
        if (stored) {
            for (uint i = 0; i < 32; i++) {
                resultHash[i] = hashBytes[i];
            }
        }
    }
}
