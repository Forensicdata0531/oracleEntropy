import Metal
import Foundation

class MetalMinerEngine {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let pipelineState: MTLComputePipelineState

    init?() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("❌ Failed to create Metal device")
            return nil
        }
        self.device = device

        // Use URL-based makeLibrary
        let libURL = URL(fileURLWithPath: "./mineKernel.metallib")
        do {
            let library = try device.makeLibrary(URL: libURL)
            guard let function = library.makeFunction(name: "mineKernel") else {
                print("❌ Failed to find function 'mineKernel' in library")
                return nil
            }
            pipelineState = try device.makeComputePipelineState(function: function)
        } catch {
            print("❌ Failed to create library or pipelineState: \(error)")
            return nil
        }

        guard let commandQueue = device.makeCommandQueue() else {
            print("❌ Failed to create command queue")
            return nil
        }
        self.commandQueue = commandQueue
    }

    func mine(header: [UInt8], target: UInt32, maxNonce: UInt32) {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            print("❌ Failed to create command buffer or encoder")
            return
        }

        let headerBuffer = device.makeBuffer(bytes: header, length: header.count, options: [])
        var targetCopy = target
        let targetBuffer = device.makeBuffer(bytes: &targetCopy, length: MemoryLayout<UInt32>.size, options: [])
        var resultNonce: UInt32 = 0xFFFFFFFF
        let resultBuffer = device.makeBuffer(bytes: &resultNonce, length: MemoryLayout<UInt32>.size, options: [])

        encoder.setComputePipelineState(pipelineState)
        encoder.setBuffer(headerBuffer, offset: 0, index: 0)
        encoder.setBuffer(targetBuffer, offset: 0, index: 1)
        encoder.setBuffer(resultBuffer, offset: 0, index: 2)

        let threadsPerThreadgroup = 256
        let threadgroups = (Int(maxNonce) + threadsPerThreadgroup - 1) / threadsPerThreadgroup

        print("[DEBUG] Dispatching \(threadgroups) threadgroups with \(threadsPerThreadgroup) threads each.")

        encoder.dispatchThreadgroups(
            MTLSize(width: threadgroups, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: threadsPerThreadgroup, height: 1, depth: 1)
        )
        encoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let foundNonce = resultBuffer?.contents().bindMemory(to: UInt32.self, capacity: 1).pointee ?? 0xFFFFFFFF
        if foundNonce != 0xFFFFFFFF {
            print("✅ Nonce found: \(foundNonce)")
        } else {
            print("❌ No valid nonce found.")
        }
    }
}
