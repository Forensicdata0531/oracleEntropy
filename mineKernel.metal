#include <metal_stdlib>
using namespace metal;

constant uint32_t k[64] = {
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
};

inline simd::uint2 rotr(simd::uint2 x, uint n) {
    return (x >> n) | (x << (32 - n));
}

inline void sha256_expand(thread simd::uint2* w) {
    for (uint i = 16; i < 64; ++i) {
        simd::uint2 s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
        simd::uint2 s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }
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

    digest[0] = a + digest[0];
    digest[1] = b + digest[1];
    digest[2] = c + digest[2];
    digest[3] = d + digest[3];
    digest[4] = e + digest[4];
    digest[5] = f + digest[5];
    digest[6] = g + digest[6];
    digest[7] = h + digest[7];
}

inline void write_digest(thread simd::uint2* digest, thread uint8_t* out, uint lane) {
    for (uint i = 0; i < 8; i++) {
        uint32_t v = digest[i][lane];
        out[i*4 + 0] = (v >> 24) & 0xff;
        out[i*4 + 1] = (v >> 16) & 0xff;
        out[i*4 + 2] = (v >> 8)  & 0xff;
        out[i*4 + 3] = (v >> 0)  & 0xff;
    }
}

inline bool check_target(thread const uint8_t* hash, device const uint8_t* target) {
    for (int i = 31; i >= 0; i--) {
        if (hash[i] < target[i]) return true;
        if (hash[i] > target[i]) return false;
    }
    return false;
}

kernel void mineKernel(
    device const uint32_t* midstates [[buffer(0)]],
    device const uint2* tailWords [[buffer(1)]],
    device const uint8_t* target [[buffer(2)]],
    device atomic_uint* resultNonce [[buffer(3)]],
    device uint8_t* resultHashes [[buffer(4)]],
    device uint8_t* sampleHashes [[buffer(5)]], // NOTE: updated: now per-thread
    uint tid [[thread_position_in_grid]]
) {
    uint nonce0 = tid * 2;
    uint nonce1 = nonce0 + 1;

    thread simd::uint2 digest[8];
    for (uint i = 0; i < 8; ++i)
        digest[i] = simd::uint2(midstates[tid * 8 + i]);

    thread simd::uint2 w[64];
    for (uint i = 0; i < 16; i++) w[i] = simd::uint2(0);
    w[0] = simd::uint2(tailWords[tid].x);
    w[1] = simd::uint2(tailWords[tid].y);
    w[3] = simd::uint2(nonce0, nonce1);
    w[4] = simd::uint2(0x80000000);
    w[15] = simd::uint2(640);

    sha256_expand(w);
    sha256_compress(w, digest);

    for (uint i = 0; i < 16; ++i) w[i] = simd::uint2(0);
    for (uint i = 0; i < 8; ++i) w[i] = digest[i];
    w[8] = simd::uint2(0x80000000);
    w[15] = simd::uint2(256);

    thread simd::uint2 iv[8] = {
        simd::uint2(0x6a09e667), simd::uint2(0xbb67ae85), simd::uint2(0x3c6ef372), simd::uint2(0xa54ff53a),
        simd::uint2(0x510e527f), simd::uint2(0x9b05688c), simd::uint2(0x1f83d9ab), simd::uint2(0x5be0cd19)
    };
    sha256_expand(w);
    sha256_compress(w, iv);

    thread uint8_t hash0[32], hash1[32];
    write_digest(iv, hash0, 0);
    write_digest(iv, hash1, 1);

    // ✅ Save best-of-2 hash for this thread into per-thread sampleHashes
    device uint8_t* mySampleHash = sampleHashes + tid * 32;
    for (uint i = 0; i < 32; ++i)
        mySampleHash[i] = (hash0[i] < hash1[i]) ? hash0[i] : hash1[i];

    if (check_target(hash0, target)) {
        uint expected = 0;
        if (atomic_compare_exchange_weak_explicit(resultNonce, &expected, nonce0, memory_order_relaxed, memory_order_relaxed)) {
            for (uint i = 0; i < 32; ++i)
                resultHashes[tid * 64 + i] = hash0[i];
        }
    }

    if (check_target(hash1, target)) {
        uint expected = 0;
        if (atomic_compare_exchange_weak_explicit(resultNonce, &expected, nonce1, memory_order_relaxed, memory_order_relaxed)) {
            for (uint i = 0; i < 32; ++i)
                resultHashes[tid * 64 + 32 + i] = hash1[i];
        }
    }
}
