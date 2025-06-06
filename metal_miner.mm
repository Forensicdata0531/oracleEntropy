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

extern void logLine(const std::string&);

static constexpr size_t THREADS_PER_GRID = 114688;
static constexpr size_t HASHES_PER_THREAD = 2;

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
        resultNonceBuffer = [device newBufferWithLength:sizeof(uint32_t) options:MTLResourceStorageModeShared];
        resultHashBuffer = [device newBufferWithLength:THREADS_PER_GRID * HASHES_PER_THREAD * 32
                                               options:MTLResourceStorageModeShared];
        sampleHashBuffer = [device newBufferWithLength:32 options:MTLResourceStorageModeShared];
        sampleHashLockBuffer = [device newBufferWithLength:sizeof(uint32_t) options:MTLResourceStorageModeShared];

        reset();
    }

    void reset() {
        uint32_t zero = 0;
        memcpy(resultNonceBuffer.contents, &zero, sizeof(uint32_t));
        memcpy(sampleHashLockBuffer.contents, &zero, sizeof(uint32_t));
        memset(sampleHashBuffer.contents, 0xFF, 32); // reset sample hash to max
    }

    void setMidstates(const std::vector<uint32_t>& midstates) {
        if (midstates.size() != THREADS_PER_GRID * 8) {
            logLine("❌ Midstates size mismatch!");
            exit(1);
        }
        memcpy(midstateBuffer.contents, midstates.data(), midstates.size() * sizeof(uint32_t));
    }

    void setTailWords(const std::vector<simd::uint2>& tailWords) {
        if (tailWords.size() != THREADS_PER_GRID) {
            logLine("❌ TailWords size mismatch!");
            exit(1);
        }
        memcpy(tailWordBuffer.contents, tailWords.data(), tailWords.size() * sizeof(simd::uint2));
    }

    void setTarget(const std::vector<uint8_t>& target) {
        if (target.size() != 32) {
            logLine("❌ Target size must be 32 bytes!");
            exit(1);
        }
        memcpy(targetBuffer.contents, target.data(), 32);
    }

    bool mine(uint32_t& foundNonce, std::vector<uint8_t>& foundHash,
              uint64_t& hashesTried, std::vector<uint8_t>& sampleHashOut) {
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

        NSUInteger threadgroupSize = std::min((NSUInteger)THREADS_PER_GRID, pipelineState.maxTotalThreadsPerThreadgroup);
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
        foundNonce = nonceValue;

        [sampleHashBuffer didModifyRange:NSMakeRange(0, 32)];

        static uint64_t debugCounter = 0;
        debugCounter++;
        uint8_t* samplePtr = (uint8_t*)sampleHashBuffer.contents;
        sampleHashOut.assign(samplePtr, samplePtr + 32);

        if (debugCounter % 1000 == 0) {
            std::cout << "[DEBUG] SampleHash GPU buffer (first 8 bytes): ";
            for (int i = 0; i < 8; i++) {
                printf("%02x", samplePtr[i]);
            }
            std::cout << "...\n";
        }

        if (nonceValue == 0) {
            return false;
        }

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
    static std::vector<uint32_t> allMidstates;
    static std::vector<simd::uint2> allTailWords;
    static size_t batchCounter = 0;

    // New static vars for batch control:
    static uint64_t hashesOnCurrentBatch = 0;
    static const uint64_t HASHES_PER_BATCH = THREADS_PER_GRID * HASHES_PER_THREAD * 100000ULL; // tune this as needed

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

        size_t total = j.size();
        allMidstates.resize(total * 8);
        allTailWords.resize(total);

        for (size_t i = 0; i < total; ++i) {
            const std::string& midHex = j[i]["midstate"];
            const std::string& tailHex = j[i]["tail"];

            for (int w = 0; w < 8; ++w) {
                allMidstates[i * 8 + w] = std::stoul(midHex.substr(w * 8, 8), nullptr, 16);
            }

            uint32_t word1 = std::stoul(tailHex.substr(0, 8), nullptr, 16);
            uint32_t word2 = std::stoul(tailHex.substr(8, 8), nullptr, 16);
            allTailWords[i] = simd::uint2{ word1, word2 };
        }

        loadedOracle = true;
    }

    size_t totalEntries = allMidstates.size() / 8;
    size_t totalBatches = (totalEntries + THREADS_PER_GRID - 1) / THREADS_PER_GRID;

    // Only advance batch after mining enough hashes on current batch
    hashesOnCurrentBatch += totalHashesTried;
    if (hashesOnCurrentBatch >= HASHES_PER_BATCH) {
        hashesOnCurrentBatch = 0;
        batchCounter = (batchCounter + 1) % totalBatches;
    }

    size_t batchIndex = batchCounter;
    size_t offset = batchIndex * THREADS_PER_GRID;

    size_t batchSize = THREADS_PER_GRID;
    if (batchIndex == totalBatches - 1) {
        batchSize = totalEntries - offset; // last batch size might be smaller
    }

    std::vector<uint32_t> currentMidstates(THREADS_PER_GRID * 8, 0);
    std::vector<simd::uint2> currentTailWords(THREADS_PER_GRID, simd::uint2{0,0});

    for (size_t i = 0; i < batchSize; ++i) {
        size_t idx = offset + i;
        for (int w = 0; w < 8; ++w)
            currentMidstates[i * 8 + w] = allMidstates[idx * 8 + w];
        currentTailWords[i] = allTailWords[idx];
    }

    if (batchCounter % 5 == 0) {
        std::stringstream s;
        s << "[DEBUG] Batch index: " << batchIndex
          << ", Offset: " << offset
          << ", Midstate[0]: 0x" << std::hex << currentMidstates[0];
        logLine(s.str());
    }

    miner->setMidstates(currentMidstates);
    miner->setTailWords(currentTailWords);
    miner->setTarget(target);

    return miner->mine(validIndex, validHash, totalHashesTried, sampleHashOut);
}
