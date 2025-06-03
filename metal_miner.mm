#import <Metal/Metal.h>
#import <Foundation/Foundation.h>
#include "block.hpp"
#include <iostream>
#include <vector>
#include <algorithm>
#include <cstring>
#include <simd/simd.h>  // for simd_uint4

// Forward declaration for SHA256 (you must provide a real implementation)
void sha256(const uint8_t* data, size_t len, uint8_t* outHash);

// Serialize header to 80 bytes (little-endian as per Bitcoin spec)
std::vector<uint8_t> serializeHeader80(const BlockHeader& header) {
    std::vector<uint8_t> out;

    auto appendLE32 = [&](uint32_t val) {
        for (size_t i = 0; i < 4; ++i)
            out.push_back((val >> (8 * i)) & 0xff);
    };

    auto appendReversed = [&](const std::array<uint8_t,32>& v) {
        for (int i = 31; i >= 0; --i)
            out.push_back(v[i]);
    };

    appendLE32(header.version);
    appendReversed(header.prevBlockHash);
    appendReversed(header.merkleRoot);
    appendLE32(header.timestamp);
    appendLE32(header.bits);
    appendLE32(header.nonce);

    return out;
}

bool metalMineBlock(
    const BlockHeader& header,
    const std::vector<uint8_t>& target,
    uint32_t initialNonceBase,
    uint32_t& validNonce,
    std::vector<uint8_t>& validHash,
    uint64_t& totalHashesTried)
{
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) {
        std::cerr << "Metal not supported on this device." << std::endl;
        return false;
    }

    NSError* error = nil;
    id<MTLLibrary> library = [device newDefaultLibrary];
    if (!library) {
        std::cerr << "Failed to create Metal library." << std::endl;
        return false;
    }

    id<MTLFunction> kernelFunction = [library newFunctionWithName:@"mineKernel"];
    if (!kernelFunction) {
        std::cerr << "Failed to load Metal kernel function." << std::endl;
        return false;
    }

    id<MTLComputePipelineState> pipelineState = [device newComputePipelineStateWithFunction:kernelFunction error:&error];
    if (!pipelineState) {
        std::cerr << "Failed to create pipeline state: " << [[error localizedDescription] UTF8String] << std::endl;
        return false;
    }

    id<MTLCommandQueue> commandQueue = [device newCommandQueue];
    if (!commandQueue) {
        std::cerr << "Failed to create Metal command queue." << std::endl;
        return false;
    }

    // Step 1: Serialize Block Header
    std::vector<uint8_t> headerData = serializeHeader80(header);
    if (headerData.size() != 80) {
        std::cerr << "Serialized header is not 80 bytes." << std::endl;
        return false;
    }

    const uint32_t threads = 65536;  // tune for device
    totalHashesTried = threads;
    uint32_t nonceBase = initialNonceBase;

    // Step 2: Prepare Buffers

    // Midstate is SHA256 of first 64 bytes (first SHA256)
    uint8_t midstateBytes[32];
    sha256(headerData.data(), 64, midstateBytes); // Provide your SHA256 implementation

    // Convert midstate bytes to simd_uint4 (4x uint32_t = 16 bytes, so 32 bytes = 2 simd_uint4)
    simd_uint4 midstateSimd[2];
    for (int i = 0; i < 2; ++i) {
        uint32_t* p = (uint32_t*)(midstateBytes + i * 16);
        midstateSimd[i] = simd_make_uint4(p[0], p[1], p[2], p[3]);
    }

    id<MTLBuffer> midstateBuffer = [device newBufferWithBytes:midstateSimd length:sizeof(midstateSimd) options:MTLResourceStorageModeShared];

    // Tail buffer is last 16 bytes of header (timestamp + bits + nonce + padding)
    // Pack as simd_uint4 for alignment
    simd_uint4 tailSimd;
    memcpy(&tailSimd, headerData.data() + 64, 16);
    id<MTLBuffer> tailBuffer = [device newBufferWithBytes:&tailSimd length:sizeof(tailSimd) options:MTLResourceStorageModeShared];

    // Target buffer (difficulty target as 32 bytes)
    id<MTLBuffer> targetBuffer = [device newBufferWithBytes:target.data() length:target.size() options:MTLResourceStorageModeShared];

    // Buffer to receive result nonce if found
    id<MTLBuffer> resultNonceBuf = [device newBufferWithLength:sizeof(uint32_t) options:MTLResourceStorageModeShared];
    memset(resultNonceBuf.contents, 0, sizeof(uint32_t));

    // Buffer for base nonce input
    id<MTLBuffer> nonceBaseBuf = [device newBufferWithBytes:&nonceBase length:sizeof(uint32_t) options:MTLResourceStorageModeShared];

    // Buffer to store hashes found by threads (for validation/debugging)
    id<MTLBuffer> resultHashes = [device newBufferWithLength:threads * 32 options:MTLResourceStorageModeShared];

    // Prepare command buffer and encoder
    id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
    id<MTLComputeCommandEncoder> encoder = [commandBuffer computeCommandEncoder];

    [encoder setComputePipelineState:pipelineState];
    [encoder setBuffer:midstateBuffer offset:0 atIndex:0];
    [encoder setBuffer:tailBuffer offset:0 atIndex:1];
    [encoder setBuffer:targetBuffer offset:0 atIndex:2];
    [encoder setBuffer:resultNonceBuf offset:0 atIndex:3];
    [encoder setBuffer:nonceBaseBuf offset:0 atIndex:4];
    [encoder setBuffer:resultHashes offset:0 atIndex:5];

    MTLSize gridSize = MTLSizeMake(threads, 1, 1);
    NSUInteger threadGroupSize = pipelineState.maxTotalThreadsPerThreadgroup;
    if (threadGroupSize > threads) threadGroupSize = threads;
    MTLSize threadgroupSize = MTLSizeMake(threadGroupSize, 1, 1);

    [encoder dispatchThreads:gridSize threadsPerThreadgroup:threadgroupSize];
    [encoder endEncoding];
    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];

    uint32_t foundNonce = *((uint32_t*)resultNonceBuf.contents);
    if (foundNonce != 0) {
        validNonce = foundNonce;
        validHash.assign(
            (uint8_t*)resultHashes.contents + (validNonce - nonceBase) * 32,
            (uint8_t*)resultHashes.contents + (validNonce - nonceBase + 1) * 32
        );
        return true;
    }

    return false;
}
