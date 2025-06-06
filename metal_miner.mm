#import <Metal/Metal.h>
#import <Foundation/Foundation.h>
#import <simd/simd.h>
#import <iostream>
#import <vector>
#import <fstream>
#import <sstream>
#import "block.hpp"
#include <nlohmann/json.hpp>
#include <random>
#include <algorithm>
#include <map>
#include <numeric>

extern void logLine(const std::string&);

static constexpr size_t THREADS_PER_GRID = 180244;
static constexpr size_t HASHES_PER_THREAD = 80;

class MetalMiner {
private:
    id<MTLCommandQueue> commandQueue;
    id<MTLComputePipelineState> pipelineState;

    id<MTLBuffer> midstateBuffer;
    id<MTLBuffer> tailWordBuffer;
    id<MTLBuffer> targetBuffer;
    id<MTLBuffer> resultNonceBuffer;
    id<MTLBuffer> resultHashBuffer;
    id<MTLBuffer> sampleHashBuffer;
    id<MTLBuffer> sampleHashLockBuffer;

public:
    MetalMiner(id<MTLDevice> device, id<MTLLibrary> library) {
        NSError *error = nil;
        id<MTLFunction> function = [library newFunctionWithName:@"mineKernel"];
        if (!function) {
            logLine("❌ Failed to find function 'mineKernel'");
            exit(1);
        }

        pipelineState = [device newComputePipelineStateWithFunction:function error:&error];
        if (!pipelineState) {
            logLine("❌ Failed to create pipeline state");
            exit(1);
        }

        commandQueue = [device newCommandQueue];

        midstateBuffer = [device newBufferWithLength:THREADS_PER_GRID * 8 * sizeof(uint32_t) options:MTLResourceStorageModeShared];
        tailWordBuffer = [device newBufferWithLength:THREADS_PER_GRID * sizeof(simd::uint2) options:MTLResourceStorageModeShared];
        targetBuffer = [device newBufferWithLength:32 options:MTLResourceStorageModeShared];
        resultNonceBuffer = [device newBufferWithLength:sizeof(uint32_t) options:MTLResourceStorageModeShared];
        resultHashBuffer = [device newBufferWithLength:THREADS_PER_GRID * HASHES_PER_THREAD * 32 options:MTLResourceStorageModeShared];
        sampleHashBuffer = [device newBufferWithLength:32 options:MTLResourceStorageModeShared];
        sampleHashLockBuffer = [device newBufferWithLength:sizeof(uint32_t) options:MTLResourceStorageModeShared];

        reset();
    }

    void reset() {
        uint32_t zero = 0;
        memcpy(resultNonceBuffer.contents, &zero, sizeof(uint32_t));
        memcpy(sampleHashLockBuffer.contents, &zero, sizeof(uint32_t));
        memset(sampleHashBuffer.contents, 0xFF, 32);
    }

    void setMidstates(const std::vector<uint32_t>& midstates) {
        memcpy(midstateBuffer.contents, midstates.data(), midstates.size() * sizeof(uint32_t));
    }

    void setTailWords(const std::vector<simd::uint2>& tailWords) {
        memcpy(tailWordBuffer.contents, tailWords.data(), tailWords.size() * sizeof(simd::uint2));
    }

    void setTarget(const std::vector<uint8_t>& target) {
        memcpy(targetBuffer.contents, target.data(), 32);
    }

    bool mine(uint32_t& foundNonce, std::vector<uint8_t>& foundHash, uint64_t& hashesTried, std::vector<uint8_t>& sampleHashOut) {
        reset();

        id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
        id<MTLComputeCommandEncoder> encoder = [commandBuffer computeCommandEncoder];

        [encoder setComputePipelineState:pipelineState];
        [encoder setBuffer:midstateBuffer offset:0 atIndex:0];
        [encoder setBuffer:tailWordBuffer offset:0 atIndex:1];
        [encoder setBuffer:targetBuffer offset:0 atIndex:2];
        [encoder setBuffer:resultNonceBuffer offset:0 atIndex:3];
        [encoder setBuffer:resultHashBuffer offset:0 atIndex:4];
        [encoder setBuffer:sampleHashLockBuffer offset:0 atIndex:5];
        [encoder setBuffer:sampleHashBuffer offset:0 atIndex:6];

        NSUInteger tgSize = std::min((NSUInteger)THREADS_PER_GRID, pipelineState.maxTotalThreadsPerThreadgroup);
        NSUInteger numGroups = (THREADS_PER_GRID + tgSize - 1) / tgSize;

        [encoder dispatchThreads:MTLSizeMake(numGroups * tgSize, 1, 1)
         threadsPerThreadgroup:MTLSizeMake(tgSize, 1, 1)];
        [encoder endEncoding];
        [commandBuffer commit];
        [commandBuffer waitUntilCompleted];

        hashesTried = THREADS_PER_GRID * HASHES_PER_THREAD;
        uint32_t nonceValue = *(uint32_t*)resultNonceBuffer.contents;
        foundNonce = nonceValue;

        [sampleHashBuffer didModifyRange:NSMakeRange(0, 32)];
        uint8_t* samplePtr = (uint8_t*)sampleHashBuffer.contents;
        sampleHashOut.assign(samplePtr, samplePtr + 32);

        if (nonceValue == 0) return false;
        uint32_t index = nonceValue / HASHES_PER_THREAD;
        uint32_t offset = nonceValue % HASHES_PER_THREAD;

        if (index >= THREADS_PER_GRID) {
            logLine("⚠️ Found nonce index out of bounds.");
            return false;
        }

        uint8_t* hashPtr = (uint8_t*)resultHashBuffer.contents + (index * HASHES_PER_THREAD + offset) * 32;
        foundHash.assign(hashPtr, hashPtr + 32);
        return true;
    }
};

// *** NO extern "C" here — keep C++ linkage ***

bool metalMineBlock(
    const BlockHeader& header,
    const std::vector<uint8_t>& target,
    uint32_t initialNonceBase,
    uint32_t& validIndex,
    std::vector<uint8_t>& validHash,
    std::vector<uint8_t>& sampleHashOut,
    uint64_t& totalHashesTried)
{
    static MetalMiner* miner = nullptr;
    if (!miner) {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device) {
            logLine("❌ No Metal device found.");
            return false;
        }

        NSError* error = nil;
        NSString* metallibPath = @"build/mineKernel.metallib";
        id<MTLLibrary> library = [device newLibraryWithFile:metallibPath error:&error];
        if (!library) {
            logLine("❌ Failed to load Metal library.");
            return false;
        }

        miner = new MetalMiner(device, library);
        logLine("✅ MetalMiner initialized.");
    }

    std::vector<uint32_t> midstate = header.getMidstateWords();
    simd::uint2 tail = header.getTailWords();

    std::vector<uint32_t> mids(THREADS_PER_GRID * 8);
    std::vector<simd::uint2> tails(THREADS_PER_GRID);

    for (size_t i = 0; i < THREADS_PER_GRID; ++i) {
        std::copy(midstate.begin(), midstate.end(), mids.begin() + i * 8);
        tails[i] = tail;
    }

    miner->setMidstates(mids);
    miner->setTailWords(tails);
    miner->setTarget(target);
    return miner->mine(validIndex, validHash, totalHashesTried, sampleHashOut);
}
