#import <Metal/Metal.h>
#import <Foundation/Foundation.h>
#import <atomic>
#import <iostream>
#import <vector>
#import <sstream>
#import "block.hpp"

// Forward declaration (from main.cpp or a shared header)
void logLine(const std::string&);

class MetalMiner {
private:
    id<MTLDevice> device;
    id<MTLCommandQueue> commandQueue;
    id<MTLComputePipelineState> pipelineState;
    id<MTLBuffer> headerBuffer;
    id<MTLBuffer> targetBuffer;
    id<MTLBuffer> nonceBaseBuffer;
    id<MTLBuffer> resultNonceBuffer;
    id<MTLBuffer> resultHashesBuffer;
    id<MTLBuffer> debugCounterBuffer;

    uint32_t nonceBase;

    static constexpr size_t THREADS_PER_GRID = 131072;
    static constexpr size_t HASHES_PER_THREAD = 2;

public:
    MetalMiner(id<MTLDevice> dev, id<MTLLibrary> library) : device(dev), nonceBase(0) {
        commandQueue = [device newCommandQueue];

        NSError *error = nil;
        id<MTLFunction> function = [library newFunctionWithName:@"mineKernel"];
        pipelineState = [device newComputePipelineStateWithFunction:function error:&error];
        if (error) {
            logLine("❌ Failed to create compute pipeline state: " + std::string(error.localizedDescription.UTF8String));
            exit(1);
        }

        headerBuffer = [device newBufferWithLength:80 options:MTLResourceStorageModeShared];
        targetBuffer = [device newBufferWithLength:32 options:MTLResourceStorageModeShared];
        nonceBaseBuffer = [device newBufferWithLength:sizeof(uint32_t) options:MTLResourceStorageModeShared];
        resultNonceBuffer = [device newBufferWithLength:sizeof(uint32_t) options:MTLResourceStorageModeShared];
        resultHashesBuffer = [device newBufferWithLength:THREADS_PER_GRID * HASHES_PER_THREAD * 32 options:MTLResourceStorageModeShared];
        debugCounterBuffer = [device newBufferWithLength:sizeof(uint32_t) options:MTLResourceStorageModeShared];

        resetResultNonce();
    }

    void resetResultNonce() {
        uint32_t zero = 0;
        memcpy(resultNonceBuffer.contents, &zero, sizeof(uint32_t));
        memcpy(debugCounterBuffer.contents, &zero, sizeof(uint32_t));
        nonceBase = 0;
    }

    void setHeader(const uint8_t header[80]) {
        memcpy(headerBuffer.contents, header, 80);
    }

    void setTarget(const uint8_t target[32]) {
        memcpy(targetBuffer.contents, target, 32);
    }

    void setNonceBase(uint32_t base) {
        nonceBase = base;
        memcpy(nonceBaseBuffer.contents, &nonceBase, sizeof(uint32_t));
    }

    bool mine(uint32_t& validNonce, std::vector<uint8_t>& validHash, uint64_t& hashesTried) {
        std::ostringstream oss;
        oss << "[DEBUG] Starting mining batch. Nonce base: " << nonceBase;
        logLine(oss.str());

        id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
        id<MTLComputeCommandEncoder> encoder = [commandBuffer computeCommandEncoder];

        uint32_t zero = 0;
        memcpy(resultNonceBuffer.contents, &zero, sizeof(uint32_t));
        memcpy(debugCounterBuffer.contents, &zero, sizeof(uint32_t));

        [encoder setComputePipelineState:pipelineState];
        [encoder setBuffer:headerBuffer offset:0 atIndex:0];
        [encoder setBuffer:targetBuffer offset:0 atIndex:1];
        [encoder setBuffer:nonceBaseBuffer offset:0 atIndex:2];
        [encoder setBuffer:resultNonceBuffer offset:0 atIndex:3];
        [encoder setBuffer:resultHashesBuffer offset:0 atIndex:4];
        [encoder setBuffer:debugCounterBuffer offset:0 atIndex:5];

        NSUInteger threadGroupSize = pipelineState.maxTotalThreadsPerThreadgroup;
        if (threadGroupSize > THREADS_PER_GRID) threadGroupSize = THREADS_PER_GRID;
        NSUInteger numThreadgroups = (THREADS_PER_GRID + threadGroupSize - 1) / threadGroupSize;

        MTLSize gridSize = MTLSizeMake(numThreadgroups * threadGroupSize, 1, 1);
        MTLSize threadgroupSize = MTLSizeMake(threadGroupSize, 1, 1);

        std::ostringstream oss2;
        oss2 << "[DEBUG] Dispatching kernel with grid size: " << gridSize.width
             << ", threadgroup size: " << threadgroupSize.width;
        logLine(oss2.str());

        [encoder dispatchThreads:gridSize threadsPerThreadgroup:threadgroupSize];
        [encoder endEncoding];

        [commandBuffer commit];
        [commandBuffer waitUntilCompleted];

        if (commandBuffer.error) {
            logLine(std::string("[ERROR] GPU error: ") + commandBuffer.error.localizedDescription.UTF8String);
            return false;
        }

        hashesTried = static_cast<uint64_t>(THREADS_PER_GRID) * HASHES_PER_THREAD;
        uint32_t foundNonce = *(uint32_t*)resultNonceBuffer.contents;
        uint32_t debugCount = *(uint32_t*)debugCounterBuffer.contents;

        std::ostringstream oss3;
        oss3 << "[DEBUG] Kernel threads executed: " << debugCount
             << ", Hashes tried: " << hashesTried
             << ", Found nonce: " << foundNonce;
        logLine(oss3.str());

        if (foundNonce != 0) {
            validNonce = foundNonce;

            uint32_t nonceOffset = foundNonce - nonceBase;
            uint32_t index = nonceOffset / HASHES_PER_THREAD;
            uint32_t offset = (nonceOffset % HASHES_PER_THREAD) * 32;

            std::ostringstream oss4;
            oss4 << "[DEBUG] Valid nonce offset: " << nonceOffset
                 << ", index: " << index
                 << ", offset in buffer: " << offset;
            logLine(oss4.str());

            if (index < THREADS_PER_GRID) {
                uint8_t* basePtr = (uint8_t*)resultHashesBuffer.contents + index * HASHES_PER_THREAD * 32 + offset;
                validHash.assign(basePtr, basePtr + 32);
                logLine("[DEBUG] Valid hash copied.");
                return true;
            } else {
                logLine("[WARN] Invalid GPU nonce index.");
                return false;
            }
        }

        nonceBase += hashesTried;
        memcpy(nonceBaseBuffer.contents, &nonceBase, sizeof(uint32_t));
        return false;
    }
};

bool metalMineBlock(
    const uint8_t* header80,
    const std::vector<uint8_t>& targetLE,
    uint32_t initialNonceBase,
    uint32_t& validNonce,
    std::vector<uint8_t>& validHash,
    uint64_t& totalHashesTried)
{
    static MetalMiner* miner = nullptr;

    if (!miner) {
        logLine("[DEBUG] Creating Metal device and loading library...");
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device) {
            logLine("[ERROR] Metal device not found.");
            return false;
        }

        NSError *error = nil;
        NSURL *libURL = [NSURL fileURLWithPath:@"/Users/jacewheeler/Desktop/RestoredMetalMiner/build/mineKernel.metallib"];
        id<MTLLibrary> library = [device newLibraryWithURL:libURL error:&error];
        if (!library) {
            logLine(std::string("[ERROR] Failed to load Metal library: ") +
                    (error ? error.localizedDescription.UTF8String : "Unknown error"));
            return false;
        }

        miner = new MetalMiner(device, library);
        logLine("[DEBUG] MetalMiner instance created.");
    }

    logLine("[DEBUG] Setting header and target buffers...");
    miner->setHeader(header80);
    miner->setTarget(targetLE.data());
    miner->setNonceBase(initialNonceBase);

    logLine("[DEBUG] Starting mining operation...");
    bool found = miner->mine(validNonce, validHash, totalHashesTried);
    if (found) {
        logLine("[DEBUG] Mining found valid nonce: " + std::to_string(validNonce));
    } else {
        logLine("[DEBUG] Mining batch finished with no valid nonce.");
    }
    return found;
}

// Overload for main.cpp
bool metalMineBlock(
    const BlockHeader& header,
    const std::vector<uint8_t>& target,
    uint32_t initialNonceBase,
    uint32_t& validNonce,
    std::vector<uint8_t>& validHash,
    uint64_t& totalHashesTried)
{
    uint8_t header80[80] = {0};

    header80[0] = header.version & 0xff;
    header80[1] = (header.version >> 8) & 0xff;
    header80[2] = (header.version >> 16) & 0xff;
    header80[3] = (header.version >> 24) & 0xff;

    memcpy(header80 + 4, header.prevBlockHash.data(), 32);
    memcpy(header80 + 36, header.merkleRoot.data(), 32);

    header80[68] = header.timestamp & 0xff;
    header80[69] = (header.timestamp >> 8) & 0xff;
    header80[70] = (header.timestamp >> 16) & 0xff;
    header80[71] = (header.timestamp >> 24) & 0xff;

    header80[72] = header.bits & 0xff;
    header80[73] = (header.bits >> 8) & 0xff;
    header80[74] = (header.bits >> 16) & 0xff;
    header80[75] = (header.bits >> 24) & 0xff;

    header80[76] = 0;
    header80[77] = 0;
    header80[78] = 0;
    header80[79] = 0;

    std::vector<uint8_t> targetLE(target.rbegin(), target.rend());

    return metalMineBlock(header80, targetLE, initialNonceBase, validNonce, validHash, totalHashesTried);
}
