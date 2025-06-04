#include <metal_stdlib>
using namespace metal;

constant uint k[64] = {
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
};

inline uint rotr(uint x, uint n) {
    return (x >> n) | (x << (32 - n));
}

inline void sha256_round(thread uint& a, thread uint& b, thread uint& c, thread uint& d,
                         thread uint& e, thread uint& f, thread uint& g, thread uint& h,
                         uint w, uint k) {
    uint S1 = rotr(e,6) ^ rotr(e,11) ^ rotr(e,25);
    uint ch = (e & f) ^ ((~e) & g);
    uint temp1 = h + S1 + ch + k + w;
    uint S0 = rotr(a,2) ^ rotr(a,13) ^ rotr(a,22);
    uint maj = (a & b) ^ (a & c) ^ (b & c);
    uint temp2 = S0 + maj;

    h = g; g = f; f = e;
    e = d + temp1;
    d = c; c = b; b = a;
    a = temp1 + temp2;
}

kernel void mineMidstateContinuation(
    device const uint32_t* midstates       [[buffer(0)]],
    device const uint8_t* suffix16         [[buffer(1)]],
    device const uint8_t* target           [[buffer(2)]],
    device atomic_uint* resultNonce        [[buffer(3)]],
    device uint8_t* resultHashes           [[buffer(4)]],
    device atomic_uint* debugCounter       [[buffer(5)]],
    constant uint32_t& nonceBase           [[buffer(6)]],
    uint tid                               [[thread_position_in_grid]]
) {
    atomic_fetch_add_explicit(debugCounter, 1, memory_order_relaxed);
    uint nonce = nonceBase + tid;

    uint a = midstates[tid * 8 + 0];
    uint b = midstates[tid * 8 + 1];
    uint c = midstates[tid * 8 + 2];
    uint d = midstates[tid * 8 + 3];
    uint e = midstates[tid * 8 + 4];
    uint f = midstates[tid * 8 + 5];
    uint g = midstates[tid * 8 + 6];
    uint h = midstates[tid * 8 + 7];

    uint8_t tail[16];
    uint base = tid * 16;
    for (int i = 0; i < 12; ++i)
        tail[i] = suffix16[base + i];

    tail[12] = (nonce >> 0) & 0xff;
    tail[13] = (nonce >> 8) & 0xff;
    tail[14] = (nonce >> 16) & 0xff;
    tail[15] = (nonce >> 24) & 0xff;

    thread uint W[64];
    for (int i = 0; i < 4; ++i)
        W[i] = ((uint)tail[i * 4 + 0] << 24) | ((uint)tail[i * 4 + 1] << 16) |
               ((uint)tail[i * 4 + 2] << 8) | (uint)tail[i * 4 + 3];

    W[4] = 0x80000000;
    for (int i = 5; i < 15; ++i) W[i] = 0;
    W[15] = 336; // bits

    for (int i = 16; i < 64; ++i) {
        uint s0 = rotr(W[i - 15], 7) ^ rotr(W[i - 15], 18) ^ (W[i - 15] >> 3);
        uint s1 = rotr(W[i - 2], 17) ^ rotr(W[i - 2], 19) ^ (W[i - 2] >> 10);
        W[i] = W[i - 16] + s0 + W[i - 7] + s1;
    }

    for (int i = 0; i < 64; ++i)
        sha256_round(a, b, c, d, e, f, g, h, W[i], k[i]);

    a += midstates[tid * 8 + 0];
    b += midstates[tid * 8 + 1];
    c += midstates[tid * 8 + 2];
    d += midstates[tid * 8 + 3];
    e += midstates[tid * 8 + 4];
    f += midstates[tid * 8 + 5];
    g += midstates[tid * 8 + 6];
    h += midstates[tid * 8 + 7];

    uint hashWords[8] = {a,b,c,d,e,f,g,h};
    uint8_t hash[32];
    for (int i = 0; i < 8; ++i) {
        hash[i * 4 + 0] = (hashWords[i] >> 24) & 0xff;
        hash[i * 4 + 1] = (hashWords[i] >> 16) & 0xff;
        hash[i * 4 + 2] = (hashWords[i] >> 8) & 0xff;
        hash[i * 4 + 3] = hashWords[i] & 0xff;
    }

    bool success = true;
    for (int i = 31; i >= 0; --i) {
        if (hash[i] < target[i]) break;
        if (hash[i] > target[i]) { success = false; break; }
    }

    if (success) {
        uint expected = 0;
        if (atomic_compare_exchange_weak_explicit(resultNonce, &expected, nonce, memory_order_relaxed, memory_order_relaxed)) {
            for (int i = 0; i < 32; ++i)
                resultHashes[tid * 32 + i] = hash[i];
        }
    }
}
