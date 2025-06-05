#import <Metal/Metal.h>
#import <Foundation/Foundation.h>
#import <simd/simd.h>
#import <iostream>
#import <vector>
#import <fstream>
#import <sstream>
#import "block.hpp"
#include <nlohmann/json.hpp>

extern void logLine(const std::string&);

static constexpr size_t THREADS_PER_GRID = 114688;
static constexpr size_t HASHES_PER_THREAD = 2;

class MetalMiner {
private:
    id<MTLDevice> device;
    id<MTLCommandQueue> commandQueue;
    id<MTLComputePipelineState> pipelineState;

    id<MTLBuffer> midstateBuffer;
    id<MTLBuffer> tailWordBuffer;
    id<MTLBuffer> targetBuffer;
    id<MTLBuffer> resultNonceBuffer;
    id<MTLBuffer> resultHashBuffer;
    id<MTLBuffer> sampleHashesBuffer;  // updated: full sample buffer per thread

public:
    MetalMiner(id<MTLDevice> device, id<MTLLibrary> library) : device(device) {
        NSError *error = nil;
        id<MTLFunction> function = [library newFunctionWithName:@"mineKernel"];
        if (!function) {
            logLine("❌ Failed to find function 'mineKernel' in metallib.");
            exit(1);
        }

        pipelineState = [device newComputePipelineStateWithFunction:function error:&error];
        if (error || !pipelineState) {
            logLine("❌ Failed to create pipeline state: " + std::string(error.localizedDescription.UTF8String));
            exit(1);
        }

        commandQueue = [device newCommandQueue];

        midstateBuffer = [device newBufferWithLength:THREADS_PER_GRID * 8 * sizeof(uint32_t)
                                             options:MTLResourceStorageModeShared];
        tailWordBuffer = [device newBufferWithLength:THREADS_PER_GRID * sizeof(simd::uint2)
                                             options:MTLResourceStorageModeShared];
        targetBuffer = [device newBufferWithLength:32 options:MTLResourceStorageModeShared];
        resultNonceBuffer = [device newBufferWithLength:sizeof(uint32_t)
                                                options:MTLResourceStorageModeShared];
        resultHashBuffer = [device newBufferWithLength:THREADS_PER_GRID * HASHES_PER_THREAD * 32
                                               options:MTLResourceStorageModeShared];
        sampleHashesBuffer = [device newBufferWithLength:THREADS_PER_GRID * 32
                                                 options:MTLResourceStorageModeShared];

        reset();
    }

    void reset() {
        uint32_t zero = 0;
        memcpy(resultNonceBuffer.contents, &zero, sizeof(uint32_t));
        memset(sampleHashesBuffer.contents, 0xff, THREADS_PER_GRID * 32);  // high bytes so min comparison works
    }

    void setMidstates(const std::vector<uint32_t>& midstates) {
        memcpy(midstateBuffer.contents, midstates.data(), midstates.size() * sizeof(uint32_t));
    }

    void setTailWords(const std::vector<simd::uint2>& tailWords) {
        memcpy(tailWordBuffer.contents, tailWords.data(), tailWords.size() * sizeof(simd::uint2));
    }

    void setTarget(const std::vector<uint8_t>& target) {
        memcpy(targetBuffer.contents, target.data(), target.size());
    }

    bool mine(uint32_t& foundNonce, std::vector<uint8_t>& foundHash,
              uint64_t& hashesTried, std::vector<uint8_t>& sampleHashOut) {
        id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
        id<MTLComputeCommandEncoder> encoder = [commandBuffer computeCommandEncoder];

        [encoder setComputePipelineState:pipelineState];
        [encoder setBuffer:midstateBuffer offset:0 atIndex:0];
        [encoder setBuffer:tailWordBuffer offset:0 atIndex:1];
        [encoder setBuffer:targetBuffer offset:0 atIndex:2];
        [encoder setBuffer:resultNonceBuffer offset:0 atIndex:3];
        [encoder setBuffer:resultHashBuffer offset:0 atIndex:4];
        [encoder setBuffer:sampleHashesBuffer offset:0 atIndex:5];  // updated buffer

        NSUInteger maxThreads = pipelineState.maxTotalThreadsPerThreadgroup;
        NSUInteger threadgroupSize = maxThreads > THREADS_PER_GRID ? THREADS_PER_GRID : maxThreads;
        NSUInteger numThreadgroups = (THREADS_PER_GRID + threadgroupSize - 1) / threadgroupSize;

        MTLSize gridSize = MTLSizeMake(numThreadgroups * threadgroupSize, 1, 1);
        MTLSize threadgroupSizeMTL = MTLSizeMake(threadgroupSize, 1, 1);

        [encoder dispatchThreads:gridSize threadsPerThreadgroup:threadgroupSizeMTL];
        [encoder endEncoding];

        [commandBuffer commit];
        [commandBuffer waitUntilCompleted];

        if (commandBuffer.error) {
            logLine("❌ GPU error: " + std::string(commandBuffer.error.localizedDescription.UTF8String));
            return false;
        }

        hashesTried = THREADS_PER_GRID * HASHES_PER_THREAD;
        uint32_t nonceValue = *(uint32_t*)resultNonceBuffer.contents;

        // ✅ Sample hash: find best from GPU buffer
        uint8_t* allSamples = (uint8_t*)sampleHashesBuffer.contents;
        std::vector<uint8_t> best(32, 0xff);
        for (size_t i = 0; i < THREADS_PER_GRID; ++i) {
            uint8_t* ptr = allSamples + i * 32;
            if (memcmp(ptr, best.data(), 32) < 0) {
                memcpy(best.data(), ptr, 32);
            }
        }
        sampleHashOut = best;

        if (nonceValue == 0) {
            foundNonce = 0;
            return false;
        }

        foundNonce = nonceValue;
        uint32_t index = nonceValue / HASHES_PER_THREAD;
        uint32_t offsetInThread = nonceValue % HASHES_PER_THREAD;

        if (index >= THREADS_PER_GRID) {
            logLine("⚠️ Found nonce index out of bounds.");
            return false;
        }

        uint8_t* hashBase = (uint8_t*)resultHashBuffer.contents + index * HASHES_PER_THREAD * 32 + offsetInThread * 32;
        foundHash.assign(hashBase, hashBase + 32);

        return true;
    }
};

// External interface
bool metalMineBlock(const BlockHeader& header,
                    const std::vector<uint8_t>& target,
                    uint32_t initialNonceBase,
                    uint32_t& validIndex,
                    std::vector<uint8_t>& validHash,
                    std::vector<uint8_t>& sampleHashOut,
                    uint64_t& totalHashesTried)
{
    static MetalMiner* miner = nullptr;
    static bool loadedOracle = false;
    static std::vector<uint32_t> midstates;
    static std::vector<simd::uint2> tailWords;

    if (!miner) {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device) {
            logLine("❌ Metal device not found.");
            return false;
        }

        NSError* error = nil;
        NSString* metallibPath = @"build/mineKernel.metallib";
        id<MTLLibrary> library = [device newLibraryWithFile:metallibPath error:&error];
        if (!library) {
            logLine("❌ Failed to load Metal library: " + std::string(error.localizedDescription.UTF8String));
            return false;
        }

        miner = new MetalMiner(device, library);
        logLine("✅ MetalMiner initialized.");
    }

    if (!loadedOracle) {
        std::ifstream f("oracle/top_midstates.json");
        if (!f.is_open()) {
            logLine("❌ Cannot open top_midstates.json");
            return false;
        }

        nlohmann::json j;
        f >> j;

        if (!j.is_array()) {
            logLine("❌ top_midstates.json is not an array");
            return false;
        }

        size_t count = std::min(j.size(), THREADS_PER_GRID);
        midstates.resize(count * 8);
        tailWords.resize(count);

        for (size_t i = 0; i < count; ++i) {
            auto& entry = j[i];
            std::string midHex = entry["midstate"];
            std::string tailHex = entry["tail"];

            for (int w = 0; w < 8; ++w) {
                std::string wordStr = midHex.substr(w * 8, 8);
                midstates[i * 8 + w] = std::stoul(wordStr, nullptr, 16);
            }

            uint32_t word1 = std::stoul(tailHex.substr(0, 8), nullptr, 16);
            uint32_t word2 = std::stoul(tailHex.substr(8, 8), nullptr, 16);
            tailWords[i] = (simd::uint2){ word1, word2 };
        }

        miner->setMidstates(midstates);
        miner->setTailWords(tailWords);
        loadedOracle = true;
    }

    miner->setTarget(target);
    miner->reset();

    return miner->mine(validIndex, validHash, totalHashesTried, sampleHashOut);
}
