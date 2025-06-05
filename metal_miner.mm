#include "midstate.hpp"
#include "block_utils.hpp"
#include "rpc.hpp"
#include "block.hpp"

#import <Metal/Metal.h>
#import <Foundation/Foundation.h>
#include <iostream>
#import <simd/simd.h>

bool metalMineBlock(const BlockHeader& header,
                    const std::vector<uint8_t>& target,
                    uint32_t initialNonceBase,
                    uint32_t& validIndex,
                    std::vector<uint8_t>& validHash,
                    std::vector<uint8_t>& sampleHashOut,
                    uint64_t& totalHashesTried)
{
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) {
        std::cerr << "❌ Failed to create Metal device.\n";
        return false;
    }

    NSError* error = nil;
    id<MTLLibrary> library = [device newLibraryWithFile:@"build/mineKernel.metallib" error:&error];
    if (!library) {
        std::cerr << "❌ Failed to load Metal library: " << error.localizedDescription.UTF8String << "\n";
        return false;
    }

    id<MTLFunction> function = [library newFunctionWithName:@"mineMidstateSIMD2"];
    if (!function) {
        std::cerr << "❌ Failed to find Metal function 'mineMidstateSIMD2'.\n";
        return false;
    }

    id<MTLComputePipelineState> pipeline = [device newComputePipelineStateWithFunction:function error:&error];
    if (!pipeline) {
        std::cerr << "❌ Failed to create pipeline: " << error.localizedDescription.UTF8String << "\n";
        return false;
    }

    id<MTLCommandQueue> queue = [device newCommandQueue];
    if (!queue) {
        std::cerr << "❌ Failed to create command queue.\n";
        return false;
    }

    const size_t totalThreads = 131072; // 128k threads
    const size_t threadgroupSize = 256;
    size_t numThreadgroups = (totalThreads + threadgroupSize - 1) / threadgroupSize;

    // === Load midstates ===
    std::vector<MidstateEntry> entries = loadMidstates("oracle/top_midstates.json");
    if (entries.size() < totalThreads) {
        std::cerr << "❌ Need at least " << totalThreads << " midstate entries. Got " << entries.size() << "\n";
        return false;
    }

    // Prepare midstate and tail buffers
    std::vector<vector_uint2> midstateBuf(totalThreads * 8);
    std::vector<vector_uint2> tailBuf(totalThreads);

    for (size_t i = 0; i < totalThreads; ++i) {
        for (int j = 0; j < 8; ++j) {
            midstateBuf[i * 8 + j] = vector_uint2{entries[i].midstate[j], 0};
        }
        tailBuf[i] = vector_uint2{entries[i].tail, 0};
    }

    // Target vector: convert 32-byte target to uint32_t little endian pairs
    std::vector<vector_uint2> targetVec(8);
    for (int i = 0; i < 8; ++i) {
        uint32_t val = ((uint32_t*)&target[0])[i];
        targetVec[i] = vector_uint2{val, 0};
    }

    // Output buffer for results: 18 uint2 per thread
    std::vector<vector_uint2> output(totalThreads * 18, vector_uint2{0, 0});

    id<MTLBuffer> midBuf = [device newBufferWithBytes:midstateBuf.data()
                                               length:midstateBuf.size() * sizeof(vector_uint2)
                                              options:MTLResourceStorageModeShared];
    id<MTLBuffer> tailWordBuf = [device newBufferWithBytes:tailBuf.data()
                                                    length:tailBuf.size() * sizeof(vector_uint2)
                                                   options:MTLResourceStorageModeShared];
    id<MTLBuffer> tgtBuf = [device newBufferWithBytes:targetVec.data()
                                              length:targetVec.size() * sizeof(vector_uint2)
                                             options:MTLResourceStorageModeShared];
    id<MTLBuffer> outBuf = [device newBufferWithBytes:output.data()
                                              length:output.size() * sizeof(vector_uint2)
                                             options:MTLResourceStorageModeShared];
    id<MTLBuffer> nonceBuf = [device newBufferWithLength:sizeof(uint32_t)
                                                 options:MTLResourceStorageModeShared];

    if (!midBuf || !tailWordBuf || !tgtBuf || !outBuf || !nonceBuf) {
        std::cerr << "❌ One or more Metal buffers failed to allocate.\n";
        return false;
    }

    *((uint32_t*)nonceBuf.contents) = initialNonceBase;

    id<MTLCommandBuffer> cmd = [queue commandBuffer];
    [cmd addCompletedHandler:^(id<MTLCommandBuffer> cb) {
        if (cb.error) {
            std::cerr << "⚠️ Metal error: " << cb.error.localizedDescription.UTF8String << std::endl;
        }
    }];

    id<MTLComputeCommandEncoder> enc = [cmd computeCommandEncoder];
    [enc setComputePipelineState:pipeline];
    [enc setBuffer:midBuf offset:0 atIndex:0];
    [enc setBuffer:tailWordBuf offset:0 atIndex:1];
    [enc setBuffer:tgtBuf offset:0 atIndex:2];
    [enc setBuffer:outBuf offset:0 atIndex:3];
    [enc setBuffer:nonceBuf offset:0 atIndex:4];

    [enc dispatchThreadgroups:MTLSizeMake((uint32_t)numThreadgroups, 1, 1)
           threadsPerThreadgroup:MTLSizeMake((uint32_t)threadgroupSize, 1, 1)];
    [enc endEncoding];
    [cmd commit];
    [cmd waitUntilCompleted];

    totalHashesTried = totalThreads * 2; // 2 nonces per thread

    auto* result = (vector_uint2*)outBuf.contents;
    if (!result) {
        std::cerr << "❌ Could not read Metal output buffer.\n";
        return false;
    }

    bool foundValid = false;
    uint32_t foundIndex = 0;
    std::vector<uint8_t> foundHash(32);

    // Find valid nonce in results
    for (size_t thread = 0; thread < totalThreads; ++thread) {
        for (int lane = 0; lane < 2; ++lane) {
            size_t base = thread * 18 + lane * 9;
            if (result[base].y == 1) {
                foundValid = true;
                foundIndex = (uint32_t)thread;
                uint32_t nonce = result[base].x;
                foundHash.resize(32);
                for (int i = 0; i < 8; ++i) {
                    uint32_t h = result[base + 1 + i].x;
                    foundHash[i * 4 + 0] = (h >> 24) & 0xff;
                    foundHash[i * 4 + 1] = (h >> 16) & 0xff;
                    foundHash[i * 4 + 2] = (h >> 8) & 0xff;
                    foundHash[i * 4 + 3] = h & 0xff;
                }
                break;
            }
        }
        if (foundValid) break;
    }

    // Extract sample hash from first thread/lane (for UI)
    size_t sampleBase = 0; // thread=0, lane=0
    sampleHashOut.resize(32);
    for (int i = 0; i < 8; ++i) {
        uint32_t h = result[sampleBase + 1 + i].x;
        sampleHashOut[i * 4 + 0] = (h >> 24) & 0xff;
        sampleHashOut[i * 4 + 1] = (h >> 16) & 0xff;
        sampleHashOut[i * 4 + 2] = (h >> 8) & 0xff;
        sampleHashOut[i * 4 + 3] = h & 0xff;
    }

    if (foundValid) {
        validIndex = foundIndex;
        validHash = foundHash;
        return true;
    }

    return false;
}
