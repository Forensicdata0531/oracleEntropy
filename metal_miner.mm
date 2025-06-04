#import <Metal/Metal.h>
#import <Foundation/Foundation.h>
#import <atomic>
#import <iostream>
#import <vector>
#import <sstream>
#import <fstream>
#import "block.hpp"
#import <nlohmann/json.hpp>

void logLine(const std::string&);

class MetalMiner {
private:
    id<MTLDevice> device;
    id<MTLCommandQueue> commandQueue;
    id<MTLComputePipelineState> pipelineState;

    id<MTLBuffer> midstateBuffer;
    id<MTLBuffer> suffix16Buffer;
    id<MTLBuffer> targetBuffer;
    id<MTLBuffer> resultNonceBuffer;
    id<MTLBuffer> resultHashesBuffer;
    id<MTLBuffer> debugCounterBuffer;
    id<MTLBuffer> nonceBaseBuffer;

    uint32_t nonceBase;
    size_t threadCount;

public:
    MetalMiner(id<MTLDevice> dev, id<MTLLibrary> lib, size_t threads)
        : device(dev), nonceBase(0), threadCount(threads) {
        commandQueue = [device newCommandQueue];

        NSError *error = nil;
        id<MTLFunction> fn = [lib newFunctionWithName:@"mineMidstateContinuation"];
        pipelineState = [device newComputePipelineStateWithFunction:fn error:&error];
        if (!pipelineState) {
            logLine("[Metal ERROR] Failed to create pipeline.");
            exit(1);
        }

        targetBuffer        = [device newBufferWithLength:32 options:MTLResourceStorageModeShared];
        resultNonceBuffer   = [device newBufferWithLength:sizeof(uint32_t) options:MTLResourceStorageModeShared];
        resultHashesBuffer  = [device newBufferWithLength:threadCount * 32 options:MTLResourceStorageModeShared];
        debugCounterBuffer  = [device newBufferWithLength:sizeof(uint32_t) options:MTLResourceStorageModeShared];
        nonceBaseBuffer     = [device newBufferWithLength:sizeof(uint32_t) options:MTLResourceStorageModeShared];
    }

    void loadMidstateTailJSON(const std::string& path) {
        std::ifstream in(path);
        if (!in) {
            logLine("[ERROR] Failed to open JSON: " + path);
            exit(1);
        }

        nlohmann::json j;
        in >> j;

        std::vector<uint8_t> midstates;
        std::vector<uint8_t> suffixes;
        for (const auto& obj : j) {
            if (!obj.contains("midstate") || !obj.contains("tail"))
                continue;

            std::string mid = obj["midstate"];
            std::string tail = obj["tail"];

            for (size_t i = 0; i < 64; i += 2)
                midstates.push_back((uint8_t)std::stoi(mid.substr(i, 2), nullptr, 16));
            for (size_t i = 0; i < 24; i += 2)
                suffixes.push_back((uint8_t)std::stoi(tail.substr(i, 2), nullptr, 16));
        }

        threadCount = midstates.size() / 32;
        midstateBuffer = [device newBufferWithBytes:midstates.data() length:midstates.size() options:MTLResourceStorageModeShared];

        suffix16Buffer = [device newBufferWithLength:threadCount * 16 options:MTLResourceStorageModeShared];
        uint8_t* dst = (uint8_t*)suffix16Buffer.contents;
        for (size_t i = 0; i < threadCount; ++i) {
            memcpy(dst + i * 16, &suffixes[i * 12], 12);
            memset(dst + i * 16 + 12, 0, 4);
        }

        logLine("[INFO] Loaded " + std::to_string(threadCount) + " midstates.");
    }

    void setTarget(const uint8_t* targetLE) {
        memcpy(targetBuffer.contents, targetLE, 32);
    }

    void setNonceBase(uint32_t base) {
        nonceBase = base;
        memcpy(nonceBaseBuffer.contents, &nonceBase, sizeof(uint32_t));
    }

    bool mine(uint32_t& foundNonce, std::vector<uint8_t>& foundHash,
              std::vector<uint8_t>& sampleHash, uint64_t& hashesTried) {
        memset(resultNonceBuffer.contents, 0, sizeof(uint32_t));
        memset(resultHashesBuffer.contents, 0, threadCount * 32);
        memset(debugCounterBuffer.contents, 0, sizeof(uint32_t));

        id<MTLCommandBuffer> cmd = [commandQueue commandBuffer];
        id<MTLComputeCommandEncoder> encoder = [cmd computeCommandEncoder];

        [encoder setComputePipelineState:pipelineState];
        [encoder setBuffer:midstateBuffer offset:0 atIndex:0];
        [encoder setBuffer:suffix16Buffer offset:0 atIndex:1];
        [encoder setBuffer:targetBuffer offset:0 atIndex:2];
        [encoder setBuffer:resultNonceBuffer offset:0 atIndex:3];
        [encoder setBuffer:resultHashesBuffer offset:0 atIndex:4];
        [encoder setBuffer:debugCounterBuffer offset:0 atIndex:5];
        [encoder setBuffer:nonceBaseBuffer offset:0 atIndex:6];

        NSUInteger threadGroupSize = pipelineState.maxTotalThreadsPerThreadgroup;
        MTLSize grid = MTLSizeMake(threadCount, 1, 1);
        MTLSize tg = MTLSizeMake(std::min((size_t)threadGroupSize, threadCount), 1, 1);
        [encoder dispatchThreads:grid threadsPerThreadgroup:tg];
        [encoder endEncoding];

        [cmd commit];
        [cmd waitUntilCompleted];

        hashesTried = threadCount;

        uint32_t nonce = *(uint32_t*)resultNonceBuffer.contents;
        sampleHash.assign((uint8_t*)resultHashesBuffer.contents, (uint8_t*)resultHashesBuffer.contents + 32);

        if (nonce != 0) {
            size_t offset = (nonce - nonceBase) * 32;
            foundNonce = nonce;
            uint8_t* ptr = (uint8_t*)resultHashesBuffer.contents + offset;
            foundHash.assign(ptr, ptr + 32);
            return true;
        }

        nonceBase += threadCount;
        memcpy(nonceBaseBuffer.contents, &nonceBase, sizeof(uint32_t));
        return false;
    }
};

bool metalMineBlock(
    const BlockHeader& header,
    const std::vector<uint8_t>& target,
    uint32_t initialNonceBase,
    uint32_t& validNonce,
    std::vector<uint8_t>& validHash,
    std::vector<uint8_t>& sampleHashOut,
    uint64_t& totalHashesTried)
{
    static MetalMiner* miner = nullptr;

    if (!miner) {
        id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
        NSError* err = nil;
        id<MTLLibrary> lib = [dev newLibraryWithURL:[NSURL fileURLWithPath:@"./build/mineKernel.metallib"]
                                               error:&err];
        if (!lib) {
            logLine("[ERROR] Failed to load Metal library.");
            return false;
        }

        miner = new MetalMiner(dev, lib, 131072);
        miner->loadMidstateTailJSON("oracle/top_midstates.json");
    }

    std::vector<uint8_t> targetLE(target.rbegin(), target.rend());
    miner->setTarget(targetLE.data());
    miner->setNonceBase(initialNonceBase);

    return miner->mine(validNonce, validHash, sampleHashOut, totalHashesTried);
}
