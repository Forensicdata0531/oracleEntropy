#include <metal_stdlib>
using namespace metal;

inline uint2 ROTR(uint2 x, uint n) { return (x >> n) | (x << (32 - n)); }
inline uint2 Ch(uint2 x, uint2 y, uint2 z) { return (x & y) ^ (~x & z); }
inline uint2 Maj(uint2 x, uint2 y, uint2 z) { return (x & y) ^ (x & z) ^ (y & z); }
inline uint2 Sigma0(uint2 x) { return ROTR(x, 2) ^ ROTR(x, 13) ^ ROTR(x, 22); }
inline uint2 Sigma1(uint2 x) { return ROTR(x, 6) ^ ROTR(x, 11) ^ ROTR(x, 25); }
inline uint2 sigma0(uint2 x) { return ROTR(x, 7) ^ ROTR(x, 18) ^ (x >> 3); }
inline uint2 sigma1(uint2 x) { return ROTR(x, 17) ^ ROTR(x, 19) ^ (x >> 10); }

constant uint K[64] = {
    0x428a2f98u, 0x71374491u, 0xb5c0fbcfu, 0xe9b5dba5u,
    0x3956c25bu, 0x59f111f1u, 0x923f82a4u, 0xab1c5ed5u,
    0xd807aa98u, 0x12835b01u, 0x243185beu, 0x550c7dc3u,
    0x72be5d74u, 0x80deb1feu, 0x9bdc06a7u, 0xc19bf174u,
    0xe49b69c1u, 0xefbe4786u, 0x0fc19dc6u, 0x240ca1ccu,
    0x2de92c6fu, 0x4a7484aau, 0x5cb0a9dcu, 0x76f988dau,
    0x983e5152u, 0xa831c66du, 0xb00327c8u, 0xbf597fc7u,
    0xc6e00bf3u, 0xd5a79147u, 0x06ca6351u, 0x14292967u,
    0x27b70a85u, 0x2e1b2138u, 0x4d2c6dfcu, 0x53380d13u,
    0x650a7354u, 0x766a0abbu, 0x81c2c92eu, 0x92722c85u,
    0xa2bfe8a1u, 0xa81a664bu, 0xc24b8b70u, 0xc76c51a3u,
    0xd192e819u, 0xd6990624u, 0xf40e3585u, 0x106aa070u,
    0x19a4c116u, 0x1e376c08u, 0x2748774cu, 0x34b0bcb5u,
    0x391c0cb3u, 0x4ed8aa4au, 0x5b9cca4fu, 0x682e6ff3u,
    0x748f82eeu, 0x78a5636fu, 0x84c87814u, 0x8cc70208u,
    0x90befffau, 0xa4506cebu, 0xbef9a3f7u, 0xc67178f2u
};

kernel void mineMidstateSIMD2(
    device const uint2* midstates [[buffer(0)]],
    device const uint2* tailWords [[buffer(1)]],
    device const uint2* target    [[buffer(2)]],
    device uint2* output          [[buffer(3)]],
    device atomic_uint* nonceBase [[buffer(4)]],
    uint gid [[thread_position_in_grid]]
) {
    // Fetch 2 nonces (for 2 lanes) - one per lane of uint2 nonce
    uint baseNonce = atomic_fetch_add_explicit(nonceBase, 2, memory_order_relaxed);
    uint2 nonce = uint2(baseNonce, baseNonce + 1);

    thread uint2 w[64];

    // Zero initialize
    for (uint i = 0; i < 64; ++i) {
        w[i] = uint2(0, 0);
    }

    // Load tail words (the 4 last 32-bit words excluding nonce) at index 14 (because 15 is nonce)
    w[14] = tailWords[gid];
    w[15] = nonce;

    // Message schedule extension:
    for (uint i = 16; i < 64; ++i) {
        w[i] = sigma1(w[i-2]) + w[i-7] + sigma0(w[i-15]) + w[i-16];
    }

    // Load midstate (initial hash values)
    uint base = gid * 8;
    uint2 a = midstates[base + 0];
    uint2 b = midstates[base + 1];
    uint2 c = midstates[base + 2];
    uint2 d = midstates[base + 3];
    uint2 e = midstates[base + 4];
    uint2 f = midstates[base + 5];
    uint2 g = midstates[base + 6];
    uint2 h = midstates[base + 7];

    // SHA-256 compression loop: 64 rounds
    for (uint i = 0; i < 64; ++i) {
        uint2 T1 = h + Sigma1(e) + Ch(e, f, g) + uint2(K[i]) + w[i];
        uint2 T2 = Sigma0(a) + Maj(a, b, c);
        h = g;
        g = f;
        f = e;
        e = d + T1;
        d = c;
        c = b;
        b = a;
        a = T1 + T2;
    }

    // Compute final hash (add midstate)
    uint2 H[8];
    H[0] = a + midstates[base + 0];
    H[1] = b + midstates[base + 1];
    H[2] = c + midstates[base + 2];
    H[3] = d + midstates[base + 3];
    H[4] = e + midstates[base + 4];
    H[5] = f + midstates[base + 5];
    H[6] = g + midstates[base + 6];
    H[7] = h + midstates[base + 7];

    // Perform lexicographic comparison of lanes against target
    bool2 valid = bool2(false);
    // We do lexicographic check for lane x (hash lane 0)
    for (uint i = 0; i < 8; ++i) {
        if (!valid.x) {
            if (H[i].x < target[i].x) {
                valid.x = true;
                break;
            } else if (H[i].x > target[i].x) {
                break;
            }
        }
    }
    // For lane y (hash lane 1)
    for (uint i = 0; i < 8; ++i) {
        if (!valid.y) {
            if (H[i].y < target[i].y) {
                valid.y = true;
                break;
            } else if (H[i].y > target[i].y) {
                break;
            }
        }
    }

    // Output results if valid
    if (valid.x) {
        output[0] = uint2(nonce.x, 1); // nonce + found flag 1 for lane 0
        for (uint i = 0; i < 8; ++i) output[1 + i] = H[i];
    }
    if (valid.y) {
        output[9] = uint2(nonce.y, 1); // nonce + found flag 1 for lane 1
        for (uint i = 0; i < 8; ++i) output[10 + i] = uint2(H[i].y, 0);
    }
}
