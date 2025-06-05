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

    // === Load midstates ===
    std::vector<MidstateEntry> entries = loadMidstates("oracle/top_midstates.json");
    if (entries.size() < 256) {
        std::cerr << "❌ Need at least 256 midstate entries. Got " << entries.size() << "\n";
        return false;
    }

    const size_t numThreads = 256;
    std::vector<vector_uint2> midstateBuf(numThreads * 8);
    std::vector<vector_uint2> tailBuf(numThreads);

    for (size_t i = 0; i < numThreads; ++i) {
        for (int j = 0; j < 8; ++j) {
            midstateBuf[i * 8 + j] = vector_uint2{entries[i].midstate[j], 0};
        }
        tailBuf[i] = vector_uint2{entries[i].tail, 0};
    }

    std::vector<vector_uint2> targetVec(8);
    for (int i = 0; i < 8; ++i) {
        targetVec[i] = vector_uint2{target[i], target[i]};
    }

    std::vector<vector_uint2> output(numThreads * 18, vector_uint2{0, 0});

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

    // ✅ Validate buffer creation
    if (!midBuf || !tailWordBuf || !tgtBuf || !outBuf || !nonceBuf) {
        std::cerr << "❌ One or more Metal buffers failed to allocate.\n";
        return false;
    }

    *((uint32_t*)nonceBuf.contents) = initialNonceBase;

    id<MTLCommandBuffer> cmd = [queue commandBuffer];

    // ✅ Add Metal error handler
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

    [enc dispatchThreadgroups:MTLSizeMake(1, 1, 1)
       threadsPerThreadgroup:MTLSizeMake(numThreads, 1, 1)];
    [enc endEncoding];

    [cmd commit];
    [cmd waitUntilCompleted];

    totalHashesTried = numThreads * 2;

    // ✅ Safe GPU memory read
    auto* result = (vector_uint2*)outBuf.contents;
    if (!result) {
        std::cerr << "❌ Failed to read GPU output buffer (nullptr).\n";
        return false;
    }

    try {
        for (size_t thread = 0; thread < numThreads; ++thread) {
            for (int lane = 0; lane < 2; ++lane) {
                int base = static_cast<int>(thread * 18 + lane * 9);
                if (result[base].y == 1) {
                    validIndex = static_cast<uint32_t>(thread);
                    uint32_t nonce = result[base].x;

                    validHash.resize(32);
                    for (int i = 0; i < 8; ++i) {
                        uint32_t h = result[base + 1 + i].x;
                        validHash[i * 4 + 0] = (h >> 24) & 0xff;
                        validHash[i * 4 + 1] = (h >> 16) & 0xff;
                        validHash[i * 4 + 2] = (h >> 8) & 0xff;
                        validHash[i * 4 + 3] = h & 0xff;
                    }

                    sampleHashOut = validHash;
                    return true;
                }
            }
        }
    } catch (const std::exception& e) {
        std::cerr << "❌ Exception while reading Metal output: " << e.what() << std::endl;
        return false;
    } catch (...) {
        std::cerr << "❌ Unknown fatal exception while reading Metal output.\n";
        return false;
    }

    sampleHashOut.assign(32, 0);
    return false;
}
