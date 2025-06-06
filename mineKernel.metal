#include <metal_stdlib>
using namespace metal;

constant uint K[64] = {
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

kernel void mineKernel(
    device const uint* midstates         [[buffer(0)]],
    device const uint2* tailWords        [[buffer(1)]],
    device const uchar* target           [[buffer(2)]],
    device atomic_uint* resultNonce      [[buffer(3)]],
    device uchar* resultHashes           [[buffer(4)]],
    device atomic_uint* sampleHashLock   [[buffer(5)]],
    device uchar* sampleHashBuffer       [[buffer(6)]],
    uint gid                             [[thread_position_in_grid]]) {

    // Load midstate
    uint h[8];
    for (uint i = 0; i < 8; ++i)
        h[i] = midstates[gid * 8 + i];

    // Prepare tail padded message block (64 bytes)
    uint W[64];
    W[0] = tailWords[gid].x;
    W[1] = tailWords[gid].y;
    W[2] = 0x80000000;
    for (uint i = 3; i < 15; ++i) W[i] = 0;
    W[15] = 64;

    for (uint i = 16; i < 64; ++i) {
        uint s0 = rotr(W[i - 15], 7) ^ rotr(W[i - 15], 18) ^ (W[i - 15] >> 3);
        uint s1 = rotr(W[i - 2], 17) ^ rotr(W[i - 2], 19) ^ (W[i - 2] >> 10);
        W[i] = W[i - 16] + s0 + W[i - 7] + s1;
    }

    uint a=h[0],b=h[1],c=h[2],d=h[3],e=h[4],f=h[5],g=h[6],hh=h[7];
    for (uint i = 0; i < 64; ++i) {
        uint S1 = rotr(e,6)^rotr(e,11)^rotr(e,25);
        uint ch = (e&f)^((~e)&g);
        uint temp1 = hh + S1 + ch + K[i] + W[i];
        uint S0 = rotr(a,2)^rotr(a,13)^rotr(a,22);
        uint maj = (a&b)^(a&c)^(b&c);
        uint temp2 = S0 + maj;
        hh=g; g=f; f=e; e=d+temp1; d=c; c=b; b=a; a=temp1+temp2;
    }

    for (uint i = 0; i < 8; ++i)
        h[i] += (i==0)?a:(i==1)?b:(i==2)?c:(i==3)?d:(i==4)?e:(i==5)?f:(i==6)?g:hh;

    // Second SHA-256 compression
    uint M2[64];
    for (uint i = 0; i < 8; ++i) M2[i] = h[i];
    M2[8] = 0x80000000;
    for (uint i = 9; i < 15; ++i) M2[i] = 0;
    M2[15] = 256;

    for (uint i = 16; i < 64; ++i) {
        uint s0 = rotr(M2[i - 15], 7) ^ rotr(M2[i - 15], 18) ^ (M2[i - 15] >> 3);
        uint s1 = rotr(M2[i - 2], 17) ^ rotr(M2[i - 2], 19) ^ (M2[i - 2] >> 10);
        M2[i] = M2[i - 16] + s0 + M2[i - 7] + s1;
    }

    uint H[8] = {
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    };

    a=H[0]; b=H[1]; c=H[2]; d=H[3]; e=H[4]; f=H[5]; g=H[6]; hh=H[7];
    for (uint i = 0; i < 64; ++i) {
        uint S1 = rotr(e,6)^rotr(e,11)^rotr(e,25);
        uint ch = (e&f)^((~e)&g);
        uint temp1 = hh + S1 + ch + K[i] + M2[i];
        uint S0 = rotr(a,2)^rotr(a,13)^rotr(a,22);
        uint maj = (a&b)^(a&c)^(b&c);
        uint temp2 = S0 + maj;
        hh=g; g=f; f=e; e=d+temp1; d=c; c=b; b=a; a=temp1+temp2;
    }

    for (uint i = 0; i < 8; ++i)
        H[i] += (i==0)?a:(i==1)?b:(i==2)?c:(i==3)?d:(i==4)?e:(i==5)?f:(i==6)?g:hh;

    uchar out[32];
    for (uint i = 0; i < 8; ++i) {
        out[i*4+0] = (H[i] >> 24) & 0xff;
        out[i*4+1] = (H[i] >> 16) & 0xff;
        out[i*4+2] = (H[i] >>  8) & 0xff;
        out[i*4+3] = (H[i] >>  0) & 0xff;
    }

    // Compare against target
    bool valid = true;
    for (int i = 0; i < 32; ++i) {
        if (out[i] < target[i]) break;
        if (out[i] > target[i]) { valid = false; break; }
    }

    // Atomic update sampleHashBuffer with the lowest hash found so far
    uint expected = 0;
    if (atomic_compare_exchange_weak_explicit(sampleHashLock, &expected, 1, memory_order_relaxed, memory_order_relaxed)) {
        bool better = false;
        for (int i = 0; i < 32; ++i) {
            if (out[i] < sampleHashBuffer[i]) { better = true; break; }
            if (out[i] > sampleHashBuffer[i]) break;
        }
        if (better) {
            for (int i = 0; i < 32; ++i)
                sampleHashBuffer[i] = out[i];
        }
        atomic_store_explicit(sampleHashLock, 0, memory_order_relaxed);
    }

    // If valid, write nonce and hash results
    if (valid) {
        uint expectedNonce = 0;
        if (atomic_compare_exchange_weak_explicit(resultNonce, &expectedNonce, gid, memory_order_relaxed, memory_order_relaxed)) {
            for (int i = 0; i < 32; ++i)
                resultHashes[gid * 32 + i] = out[i];
        }
    }
}
