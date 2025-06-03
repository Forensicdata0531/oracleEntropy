#import <Metal/Metal.h>
#import <Foundation/Foundation.h>
#import <atomic>
#import <iostream>
#import <vector>
#import "block.hpp"  // For BlockHeader

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
            std::cerr << "❌ Failed to create compute pipeline state: " << error.localizedDescription.UTF8String << "\n";
            exit(1);
        }

        headerBuffer = [device newBufferWithLength:80 options:MTLResourceStorageModeShared];
        targetBuffer = [device newBufferWithLength:32 options:MTLResourceStorageModeShared];
        nonceBaseBuffer = [device newBufferWithLength:sizeof(uint32_t) options:MTLResourceStorageModeShared];
        resultNonceBuffer = [device newBufferWithLength:sizeof(uint32_t) options:MTLResourceStorageModeShared];
        resultHashesBuffer = [device newBufferWithLength:THREADS_PER_GRID * HASHES_PER_THREAD * 32 options:MTLResourceStorageModeShared];

        resetResultNonce();
    }

    void resetResultNonce() {
        uint32_t zero = 0;
        memcpy(resultNonceBuffer.contents, &zero, sizeof(uint32_t));
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
        id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
        id<MTLComputeCommandEncoder> encoder = [commandBuffer computeCommandEncoder];

        [encoder setComputePipelineState:pipelineState];
        [encoder setBuffer:headerBuffer offset:0 atIndex:0];
        [encoder setBuffer:targetBuffer offset:0 atIndex:1];
        [encoder setBuffer:nonceBaseBuffer offset:0 atIndex:2];
        [encoder setBuffer:resultNonceBuffer offset:0 atIndex:3];
        [encoder setBuffer:resultHashesBuffer offset:0 atIndex:4];

        MTLSize gridSize = MTLSizeMake(THREADS_PER_GRID, 1, 1);
        NSUInteger threadGroupSize = pipelineState.maxTotalThreadsPerThreadgroup;
        if (threadGroupSize > THREADS_PER_GRID) threadGroupSize = THREADS_PER_GRID;
        MTLSize threadgroupSize = MTLSizeMake(threadGroupSize, 1, 1);

        [encoder dispatchThreads:gridSize threadsPerThreadgroup:threadgroupSize];
        [encoder endEncoding];

        [commandBuffer commit];
        [commandBuffer waitUntilCompleted];

        if (commandBuffer.error) {
            std::cerr << "❌ GPU error: " << commandBuffer.error.localizedDescription.UTF8String << "\n";
            return false;
        }

        uint32_t foundNonce = *(uint32_t*)resultNonceBuffer.contents;
        hashesTried = static_cast<uint64_t>(THREADS_PER_GRID) * HASHES_PER_THREAD;

        if (foundNonce != 0) {
            validNonce = foundNonce;
            uint32_t nonceOffset = foundNonce - nonceBase;
            uint32_t index = nonceOffset / HASHES_PER_THREAD;
            uint32_t offset = (nonceOffset % HASHES_PER_THREAD) * 32;

            if (index < THREADS_PER_GRID) {
                uint8_t* basePtr = (uint8_t*)resultHashesBuffer.contents + index * HASHES_PER_THREAD * 32 + offset;
                validHash.assign(basePtr, basePtr + 32);
            } else {
                std::cerr << "⚠️ Invalid GPU nonce index.\n";
                return false;
            }

            uint32_t zero = 0;
            memcpy(resultNonceBuffer.contents, &zero, sizeof(uint32_t));
            return true;
        }

        nonceBase += hashesTried;
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
    uint64_t& totalHashesTried)
{
    static MetalMiner* miner = nullptr;

    if (!miner) {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device) {
            std::cerr << "❌ Metal device not found.\n";
            return false;
        }

        NSError *error = nil;
        NSURL *libURL = [NSURL fileURLWithPath:@"/Users/jacewheeler/Desktop/RestoredMetalMiner/build/mineKernel.metallib"];
        id<MTLLibrary> library = [device newLibraryWithURL:libURL error:&error];
        if (!library) {
            std::cerr << "❌ Failed to load Metal library: " << (error ? error.localizedDescription.UTF8String : "Unknown error") << "\n";
            return false;
        }

        miner = new MetalMiner(device, library);
    }

    uint8_t headerBytes[80];
    memset(headerBytes, 0, 80);

    // Pack block header into little-endian
    headerBytes[0] = header.version & 0xff;
    headerBytes[1] = (header.version >> 8) & 0xff;
    headerBytes[2] = (header.version >> 16) & 0xff;
    headerBytes[3] = (header.version >> 24) & 0xff;

    memcpy(headerBytes + 4, header.prevBlockHash.data(), 32);
    memcpy(headerBytes + 36, header.merkleRoot.data(), 32);

    headerBytes[68] = header.timestamp & 0xff;
    headerBytes[69] = (header.timestamp >> 8) & 0xff;
    headerBytes[70] = (header.timestamp >> 16) & 0xff;
    headerBytes[71] = (header.timestamp >> 24) & 0xff;

    headerBytes[72] = header.bits & 0xff;
    headerBytes[73] = (header.bits >> 8) & 0xff;
    headerBytes[74] = (header.bits >> 16) & 0xff;
    headerBytes[75] = (header.bits >> 24) & 0xff;

    // Nonce initialized to 0 (updated inside GPU)
    headerBytes[76] = 0;
    headerBytes[77] = 0;
    headerBytes[78] = 0;
    headerBytes[79] = 0;

    miner->setHeader(headerBytes);
    miner->setTarget(target.data());
    miner->setNonceBase(initialNonceBase);

    return miner->mine(validNonce, validHash, totalHashesTried);
}
