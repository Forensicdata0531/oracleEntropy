#import <Metal/Metal.h>
#import <Foundation/Foundation.h>
#import <simd/simd.h>  // Needed for simd::uint2
#import <iostream>
#import <vector>
#import <fstream>
#import <sstream>
#import "block.hpp"
#import "midstate.hpp"
#include <nlohmann/json.hpp>

// External logging function from main.cpp
extern void logLine(const std::string&);

static constexpr size_t THREADS_PER_GRID = 131072;
static constexpr size_t HASHES_PER_THREAD = 2;

class MetalMiner {
private:
    id<MTLDevice> device;
    id<MTLCommandQueue> commandQueue;
    id<MTLComputePipelineState> pipelineState;

    id<MTLBuffer> headerPrefixBuffer;  // 64 bytes per thread (version+prevBlockHash+merkleRoot)
    id<MTLBuffer> tailWordBuffer;      // uint2 * THREADS_PER_GRID (8 bytes per thread)
    id<MTLBuffer> targetBuffer;        // 32 bytes target
    id<MTLBuffer> resultNonceBuffer;   // atomic uint32_t
    id<MTLBuffer> resultHashBuffer;    // 64 bytes per thread (2 hashes * 32 bytes)

public:
    MetalMiner(id<MTLDevice> device, id<MTLLibrary> library) : device(device) {
        NSError *error = nil;
        id<MTLFunction> function = [library newFunctionWithName:@"mineMidstateSIMD2"];
        pipelineState = [device newComputePipelineStateWithFunction:function error:&error];
        if (error) {
            logLine("Failed to create pipeline state: " + std::string(error.localizedDescription.UTF8String));
            exit(1);
        }
        commandQueue = [device newCommandQueue];

        headerPrefixBuffer = [device newBufferWithLength:THREADS_PER_GRID * 64 options:MTLResourceStorageModeShared];
        tailWordBuffer = [device newBufferWithLength:THREADS_PER_GRID * sizeof(simd::uint2) options:MTLResourceStorageModeShared];
        targetBuffer = [device newBufferWithLength:32 options:MTLResourceStorageModeShared];
        resultNonceBuffer = [device newBufferWithLength:sizeof(uint32_t) options:MTLResourceStorageModeShared];
        resultHashBuffer = [device newBufferWithLength:THREADS_PER_GRID * HASHES_PER_THREAD * 32 options:MTLResourceStorageModeShared];

        reset();
    }

    void reset() {
        uint32_t zero = 0;
        memcpy(resultNonceBuffer.contents, &zero, sizeof(uint32_t));
    }

    void setHeaderPrefixes(const std::vector<uint8_t>& headerPrefixes) {
        // headerPrefixes.size() must be THREADS_PER_GRID * 64
        memcpy(headerPrefixBuffer.contents, headerPrefixes.data(), headerPrefixes.size());
    }

    void setTailWords(const std::vector<simd::uint2>& tailWords) {
        memcpy(tailWordBuffer.contents, tailWords.data(), tailWords.size() * sizeof(simd::uint2));
    }

    void setTarget(const std::vector<uint8_t>& target) {
        memcpy(targetBuffer.contents, target.data(), target.size());
    }

    bool mine(uint32_t& foundNonce, std::vector<uint8_t>& foundHash, uint64_t& hashesTried, std::vector<uint8_t>& sampleHashOut) {
        id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
        id<MTLComputeCommandEncoder> encoder = [commandBuffer computeCommandEncoder];

        [encoder setComputePipelineState:pipelineState];
        [encoder setBuffer:headerPrefixBuffer offset:0 atIndex:0];
        [encoder setBuffer:tailWordBuffer offset:0 atIndex:1];
        [encoder setBuffer:targetBuffer offset:0 atIndex:2];
        [encoder setBuffer:nil offset:0 atIndex:3]; // output buffer unused here
        [encoder setBuffer:resultNonceBuffer offset:0 atIndex:4];
        [encoder setBuffer:resultHashBuffer offset:0 atIndex:5];

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
            logLine("GPU error: " + std::string(commandBuffer.error.localizedDescription.UTF8String));
            return false;
        }

        hashesTried = THREADS_PER_GRID * HASHES_PER_THREAD;

        uint32_t nonceValue = *(uint32_t*)resultNonceBuffer.contents;

        // Always update sample hash from first hash in result buffer even if no valid nonce
        uint8_t* samplePtr = (uint8_t*)resultHashBuffer.contents;
        sampleHashOut.assign(samplePtr, samplePtr + 32);

        if (nonceValue == 0) {
            foundNonce = 0;
            return false;
        }

        foundNonce = nonceValue;

        // Calculate index and offset in the hash buffer for found nonce
        uint32_t index = nonceValue / HASHES_PER_THREAD;
        uint32_t offsetInThread = nonceValue % HASHES_PER_THREAD;

        if (index >= THREADS_PER_GRID) {
            logLine("Warning: Found nonce index out of bounds.");
            return false;
        }

        uint8_t* hashBase = (uint8_t*)resultHashBuffer.contents + index * HASHES_PER_THREAD * 32 + offsetInThread * 32;
        foundHash.assign(hashBase, hashBase + 32);

        return true;
    }
};

// --- Helper function to load midstates and tails from JSON ---
// Now loads header prefixes (first 64 bytes) and tails
bool loadOracleHeaderPrefixesAndTails(const std::string& filepath,
                                      std::vector<uint8_t>& headerPrefixes,
                                      std::vector<simd::uint2>& tails)
{
    std::ifstream file(filepath);
    if (!file.is_open()) {
        logLine("Failed to open oracle midstates file: " + filepath);
        return false;
    }

    nlohmann::json j;
    try {
        file >> j;
    } catch (const std::exception& e) {
        logLine(std::string("Failed to parse JSON: ") + e.what());
        return false;
    }

    if (!j.is_array()) {
        logLine("Oracle midstates JSON root is not an array.");
        return false;
    }

    size_t count = std::min(j.size(), THREADS_PER_GRID);
    headerPrefixes.resize(count * 64);
    tails.resize(count);

    for (size_t i = 0; i < count; ++i) {
        const auto& entry = j[i];
        if (!entry.contains("headerPrefix") || !entry.contains("tail")) {
            logLine("Invalid midstate entry missing keys at index: " + std::to_string(i));
            return false;
        }

        const auto& prefixArray = entry["headerPrefix"];
        if (!prefixArray.is_array() || prefixArray.size() != 64) {
            logLine("Header prefix size invalid at index: " + std::to_string(i));
            return false;
        }
        for (size_t b = 0; b < 64; ++b) {
            headerPrefixes[i * 64 + b] = prefixArray[b].get<uint8_t>();
        }

        uint32_t tailVal = entry["tail"].get<uint32_t>();
        tails[i] = simd::uint2(tailVal);
    }

    return true;
}

static MetalMiner* gMiner = nullptr;

bool metalMineBlock(
    const BlockHeader& header,
    const std::vector<uint8_t>& target,
    uint32_t initialNonceBase,
    uint32_t& validIndex,
    std::vector<uint8_t>& validHash,
    std::vector<uint8_t>& sampleHashOut,
    uint64_t& totalHashesTried)
{
    if (!gMiner) {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device) {
            logLine("Failed to create Metal device.");
            return false;
        }
        NSError* error = nil;
        NSString* path = @"/Users/jacewheeler/desktop/restoredmetalminer/oracleentropymining/oracleentropymining/mineKernel.metallib";
        id<MTLLibrary> library = [device newLibraryWithFile:path error:&error];
        if (!library) {
            logLine("Failed to load Metal library: " + std::string(error.localizedDescription.UTF8String));
            return false;
        }

        gMiner = new MetalMiner(device, library);
        logLine("MetalMiner instance created.");
    }

    static bool loadedHeaderPrefixes = false;
    static std::vector<uint8_t> headerPrefixes;
    static std::vector<simd::uint2> tailWords;

    if (!loadedHeaderPrefixes) {
        if (!loadOracleHeaderPrefixesAndTails("oracle/top_midstates.json", headerPrefixes, tailWords)) {
            logLine("Failed to load oracle header prefixes.");
            return false;
        }
        gMiner->setHeaderPrefixes(headerPrefixes);
        gMiner->setTailWords(tailWords);
        loadedHeaderPrefixes = true;
    }

    gMiner->setTarget(target);
    gMiner->reset();

    bool found = gMiner->mine(validIndex, validHash, totalHashesTried, sampleHashOut);

    return found;
}
