#include <metal_stdlib>
using namespace metal;

constant uint K[64] = {
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

inline uint rotr(uint x, uint n) {
    return (x >> n) | (x << (32 - n));
}

inline uint Ch(uint x, uint y, uint z) {
    return (x & y) ^ (~x & z);
}

inline uint Maj(uint x, uint y, uint z) {
    return (x & y) ^ (x & z) ^ (y & z);
}

inline uint Sigma0(uint x) {
    return rotr(x,2) ^ rotr(x,13) ^ rotr(x,22);
}

inline uint Sigma1(uint x) {
    return rotr(x,6) ^ rotr(x,11) ^ rotr(x,25);
}

inline uint sigma0(uint x) {
    return rotr(x,7) ^ rotr(x,18) ^ (x >> 3);
}

inline uint sigma1(uint x) {
    return rotr(x,17) ^ rotr(x,19) ^ (x >> 10);
}

kernel void mineKernel(
    device const uint *midstate [[ buffer(0) ]],
    device const uchar *tail [[ buffer(1) ]],
    device const uchar *target [[ buffer(2) ]],
    device atomic_uint *resultNonce [[ buffer(3) ]],
    device const uint *nonceBase [[ buffer(4) ]],
    device uchar *resultHashes [[ buffer(5) ]],
    uint tid [[ thread_position_in_grid ]]
) {
    // Each thread tries nonce = nonceBase + tid
    uint nonce = nonceBase[0] + tid;

    // Prepare message schedule array W[64]
    uint W[64];

    // Load midstate into working variables (a..h)
    uint a = midstate[0];
    uint b = midstate[1];
    uint c = midstate[2];
    uint d = midstate[3];
    uint e = midstate[4];
    uint f = midstate[5];
    uint g = midstate[6];
    uint h = midstate[7];

    // Message block preparation
    // Midstate is SHA256 of first 64 bytes (header[0..63])
    // Tail buffer contains last 16 bytes: timestamp(4), bits(4), nonce(4), padding(4)

    // Construct W[0..15]
    // Tail buffer bytes (16 bytes):
    // tail[0..3] = timestamp
    // tail[4..7] = bits
    // tail[8..11] = nonce (to be set)
    // tail[12..15] = padding

    // Use the existing tail bytes for all except nonce (set to current nonce)

    // Load first 12 bytes as 3 uints (little endian)
    W[0] = ((uint)tail[0]) | ((uint)tail[1] << 8) | ((uint)tail[2] << 16) | ((uint)tail[3] << 24);
    W[1] = ((uint)tail[4]) | ((uint)tail[5] << 8) | ((uint)tail[6] << 16) | ((uint)tail[7] << 24);
    W[2] = nonce;  // Set nonce here
    W[3] = ((uint)tail[12]) | ((uint)tail[13] << 8) | ((uint)tail[14] << 16) | ((uint)tail[15] << 24);

    // Rest of W
    for (int i = 4; i < 16; ++i) {
        W[i] = 0;
    }

    // Extend W[16..63]
    for (int i = 16; i < 64; ++i) {
        W[i] = sigma1(W[i-2]) + W[i-7] + sigma0(W[i-15]) + W[i-16];
    }

    // Perform SHA256 compression
    for (int i = 0; i < 64; ++i) {
        uint T1 = h + Sigma1(e) + Ch(e,f,g) + K[i] + W[i];
        uint T2 = Sigma0(a) + Maj(a,b,c);
        h = g;
        g = f;
        f = e;
        e = d + T1;
        d = c;
        c = b;
        b = a;
        a = T1 + T2;
    }

    // Add compressed chunk to current hash value
    a += midstate[0];
    b += midstate[1];
    c += midstate[2];
    d += midstate[3];
    e += midstate[4];
    f += midstate[5];
    g += midstate[6];
    h += midstate[7];

    // Pack hash result as 32 bytes little endian
    uchar hash[32];
    auto toBytes = [&](uint x, int offset) {
        hash[offset + 0] = (uchar)(x & 0xff);
        hash[offset + 1] = (uchar)((x >> 8) & 0xff);
        hash[offset + 2] = (uchar)((x >> 16) & 0xff);
        hash[offset + 3] = (uchar)((x >> 24) & 0xff);
    };
    toBytes(a, 0);
    toBytes(b, 4);
    toBytes(c, 8);
    toBytes(d, 12);
    toBytes(e, 16);
    toBytes(f, 20);
    toBytes(g, 24);
    toBytes(h, 28);

    // Check hash against target (compare 32 bytes as big endian)
    bool meetsTarget = true;
    for (int i = 31; i >= 0; --i) {
        if (hash[i] < target[i]) {
            break; // Hash less than target
        } else if (hash[i] > target[i]) {
            meetsTarget = false;
            break;
        }
    }

    if (meetsTarget) {
        // Atomically record the nonce if no other found
        uint expected = 0;
        if (atomic_compare_exchange_weak_explicit(resultNonce, &expected, nonce, memory_order_relaxed, memory_order_relaxed)) {
            // Copy hash to resultHashes array slot for this thread
            for (int i = 0; i < 32; ++i) {
                resultHashes[tid * 32 + i] = hash[i];
            }
        }
    }
}
