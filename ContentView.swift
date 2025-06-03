// MetalBitcoinMiner.swift

import SwiftUI
import Metal
import CryptoKit

// MARK: - SwiftUI Entry

struct ContentView: View {
    var body: some View {
        Text("⛏️ Mining with Metal")
            .padding()
            .onAppear {
                fetchAndRunMiner()
            }
    }
}

// MARK: - RPC Models

struct CoinbaseAux: Decodable {
    let flags: String?
}

struct TransactionTemplate: Decodable {
    let data: String
    let hash: String
}

struct BitcoinBlockTemplate: Decodable {
    let version: Int
    let previousblockhash: String
    let transactions: [TransactionTemplate]
    let coinbaseaux: CoinbaseAux?
    let coinbasevalue: Int64
    let curtime: Int
    let bits: String
    let height: Int
    let longpollid: String
    let mintime: Int
    let mutable: [String]
    let noncerange: String
    let sigoplimit: Int
    let sizelimit: Int
    let weightlimit: Int
    let capabilities: [String]?
}

struct RPCResult<T: Decodable>: Decodable {
    let result: T
}

// MARK: - Mining Logic

func runMiner(with template: BitcoinBlockTemplate) {
    guard let device = MTLCreateSystemDefaultDevice(),
          let library = device.makeDefaultLibrary(),
          let function = library.makeFunction(name: "mineKernel") else {
        print("❌ Metal setup failed.")
        return
    }
    
    let commandQueue = device.makeCommandQueue()!
    let pipelineState: MTLComputePipelineState
    do {
        pipelineState = try device.makeComputePipelineState(function: function)
    } catch {
        print("❌ Failed to create pipeline state: \(error)")
        return
    }
    
    let targetBytes = targetFromBits(template.bits)
    let numThreads = min(ProcessInfo.processInfo.activeProcessorCount, 8)
    var totalHashes: UInt64 = 0
    var found = false
    let foundLock = NSLock()
    
    DispatchQueue.global(qos: .userInitiated).async {
        DispatchQueue.concurrentPerform(iterations: numThreads) { thread in
            var extranonce = UInt32(thread * 10_000)
            var nonceStart: UInt32 = 0
            
            miningLoop: while true {
                foundLock.lock()
                if found {
                    foundLock.unlock()
                    break miningLoop
                }
                foundLock.unlock()
                
                autoreleasepool {
                    let coinbaseTx = buildCoinbaseTx(template: template, extranonce: extranonce)
                    let merkleRoot = buildMerkleRoot(coinbaseTx: coinbaseTx, txs: template.transactions)
                    
                    var blockHeader = [UInt8](repeating: 0, count: 80)
                    withUnsafeBytes(of: UInt32(template.version).littleEndian) { blockHeader.replaceSubrange(0..<4, with: $0) }
                    
                    if let prevHash = Data(hex: template.previousblockhash)?.reversed() {
                        blockHeader.replaceSubrange(4..<36, with: prevHash)
                    }
                    
                    blockHeader.replaceSubrange(36..<68, with: merkleRoot.reversed())
                    
                    withUnsafeBytes(of: UInt32(template.curtime).littleEndian) {
                        blockHeader.replaceSubrange(68..<72, with: $0)
                    }
                    
                    if let bitsLE = UInt32(template.bits, radix: 16)?.littleEndian {
                        withUnsafeBytes(of: bitsLE) {
                            blockHeader.replaceSubrange(72..<76, with: $0)
                        }
                    }
                    
                    // The nonce range this kernel will test
                    let nonceBatchSize = 1024
                    
                    blockHeader.replaceSubrange(76..<80, with: UInt32(nonceStart).littleEndian.bytes)
                    
                    var localHeader = blockHeader
                    var localTarget = targetBytes
                    
                    guard let blockBuffer = device.makeBuffer(bytes: &localHeader, length: 80),
                          let targetBuffer = device.makeBuffer(bytes: &localTarget, length: 32),
                          let nonceBuffer = device.makeBuffer(length: MemoryLayout<UInt32>.size, options: .storageModeShared) else {
                        print("❌ Failed to create Metal buffers.")
                        return
                    }
                    DispatchQueue.global().async {
                        var nonceStart: UInt32 = 0
                        var extranonce: UInt32 = 0
                        let noNonceFound: UInt32 = 0xFFFFFFFF
                        let nonceBatchSize = 1_048_576
                        
                        miningLoop: while true {
                            // Reset the nonce buffer to indicate no nonce found yet
                            memcpy(nonceBuffer.contents(), [noNonceFound], MemoryLayout<UInt32>.size)
                            
                            let commandBuffer = commandQueue.makeCommandBuffer()!
                            let encoder = commandBuffer.makeComputeCommandEncoder()!
                            encoder.setComputePipelineState(pipelineState)
                            encoder.setBuffer(blockBuffer, offset: 0, index: 0)
                            encoder.setBuffer(targetBuffer, offset: 0, index: 1)
                            encoder.setBuffer(nonceBuffer, offset: 0, index: 2)
                            
                            let threadsPerThreadgroup = MTLSize(width: 32, height: 1, depth: 1)
                            let threadgroups = MTLSize(width: nonceBatchSize / 32, height: 1, depth: 1)
                            
                            encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
                            encoder.endEncoding()
                            
                            commandBuffer.commit()
                            commandBuffer.waitUntilCompleted()
                            
                            totalHashes += UInt64(nonceBatchSize)
                            
                            if thread == 0 && totalHashes % 65536 == 0 {
                                print("⛏️ \(totalHashes) hashes tried...")
                            }
                            
                            let foundNonce = nonceBuffer.contents().load(as: UInt32.self)
                            
                            if foundNonce != noNonceFound {
                                foundLock.lock()
                                if !found {
                                    found = true
                                    print("🎉 Block found by thread \(thread)! Nonce: \(foundNonce)")
                                    withUnsafeBytes(of: foundNonce.littleEndian) {
                                        blockHeader.replaceSubrange(76..<80, with: $0)
                                    }
                                    
                                    let fullBlock = buildFullBlock(coinbaseTx: coinbaseTx, template: template)
                                    let hexBlock = (Data(blockHeader) + fullBlock).hexEncodedString()
                                    submitBlock(hexBlock: hexBlock)
                                }
                                foundLock.unlock()
                                break miningLoop
                            }
                            
                            nonceStart += UInt32(nonceBatchSize)
                            extranonce += 1
                        }
                    }
                }
            }
        }
    }
}
// MARK: - Build Coinbase + Block

func buildCoinbaseTx(template: BitcoinBlockTemplate, extranonce: UInt32) -> Data {
    var coinbaseScript = Data()
    coinbaseScript.append(varIntEncode(value: UInt64(template.height)))
    if let flags = template.coinbaseaux?.flags,
       let flagData = Data(hex: flags) {
        coinbaseScript.append(flagData)
    }

    var extraLE = extranonce.littleEndian
    withUnsafeBytes(of: &extraLE) { coinbaseScript.append(contentsOf: $0) }

    var tx = Data()
    tx.append(UInt32ToDataLE(1)) // version
    tx.append(0x01)              // input count
    tx.append(Data(repeating: 0, count: 32)) // prev txid
    tx.append(UInt32ToDataLE(0xFFFFFFFF)) // prev vout
    tx.append(varIntEncode(value: UInt64(coinbaseScript.count)))
    tx.append(coinbaseScript)
    tx.append(UInt32ToDataLE(0xFFFFFFFF)) // sequence
    tx.append(0x01)                        // output count
    tx.append(UInt64ToDataLE(UInt64(template.coinbasevalue))) // output value
    tx.append(varIntEncode(value: 0))    // pk_script length (empty)
    tx.append(UInt32ToDataLE(0))          // locktime
    return tx
}

func buildMerkleRoot(coinbaseTx: Data, txs: [TransactionTemplate]) -> Data {
    // Convert digests to Data for concatenation and hashing
    var tree = [Data(SHA256.hash(data: coinbaseTx))]
    for tx in txs {
        if let txData = Data(hex: tx.data) {
            tree.append(Data(SHA256.hash(data: txData)))
        }
    }
    while tree.count > 1 {
        var nextLevel = [Data]()
        for i in stride(from: 0, to: tree.count, by: 2) {
            if i + 1 == tree.count {
                // hash(data + data)
                nextLevel.append(Data(SHA256.hash(data: tree[i] + tree[i])))
            } else {
                nextLevel.append(Data(SHA256.hash(data: tree[i] + tree[i + 1])))
            }
        }
        tree = nextLevel
    }
    return tree[0]
}

func buildFullBlock(coinbaseTx: Data, template: BitcoinBlockTemplate) -> Data {
    var block = Data()
    block.append(varIntEncode(value: UInt64(template.transactions.count + 1))) // Include coinbase
    block.append(coinbaseTx)
    for tx in template.transactions {
        if let txData = Data(hex: tx.data) {
            block.append(txData)
        }
    }
    return block
}

// MARK: - Helpers

func targetFromBits(_ bits: String) -> [UInt8] {
    guard let bitsInt = UInt32(bits, radix: 16) else {
        return [UInt8](repeating: 0xFF, count: 32)
    }
    let exponent = UInt8(bitsInt >> 24)
    let mantissa = bitsInt & 0xFFFFFF
    var target = [UInt8](repeating: 0, count: 32)
    let mantissaBytes = [
        UInt8((mantissa >> 16) & 0xFF),
        UInt8((mantissa >> 8) & 0xFF),
        UInt8(mantissa & 0xFF)
    ]
    let index = Int(32 - exponent)
    if index + 3 <= 32 {
        target[index] = mantissaBytes[0]
        target[index + 1] = mantissaBytes[1]
        target[index + 2] = mantissaBytes[2]
    }
    return target
}

func UInt32ToDataLE(_ value: UInt32) -> Data {
    var v = value.littleEndian
    return Data(bytes: &v, count: MemoryLayout<UInt32>.size)
}

func UInt64ToDataLE(_ value: UInt64) -> Data {
    var v = value.littleEndian
    return Data(bytes: &v, count: MemoryLayout<UInt64>.size)
}

func varIntEncode(value: UInt64) -> Data {
    if value < 0xfd {
        return Data([UInt8(value)])
    } else if value <= 0xffff {
        var d = Data([0xfd])
        d.append(contentsOf: UInt16(value).littleEndian.bytes)
        return d
    } else if value <= 0xffffffff {
        var d = Data([0xfe])
        d.append(contentsOf: UInt32(value).littleEndian.bytes)
        return d
    } else {
        var d = Data([0xff])
        d.append(contentsOf: UInt64(value).littleEndian.bytes)
        return d
    }
}

extension FixedWidthInteger {
    var bytes: [UInt8] {
        withUnsafeBytes(of: littleEndian, Array.init)
    }
}

extension Data {
    init?(hex: String) {
        let len = hex.count / 2
        var data = Data(capacity: len)
        var index = hex.startIndex
        for _ in 0..<len {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let b = UInt8(hex[index..<nextIndex], radix: 16) else { return nil }
            data.append(b)
            index = nextIndex
        }
        self = data
    }

    func hexEncodedString() -> String {
        map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Block Submission (JSON-RPC)

func submitBlock(hexBlock: String) {
    print("Submitting block (hex): \(hexBlock.prefix(64))...")

    let rpcURL = URL(string: "http://127.0.0.1:8332/")! // Replace with your node's RPC URL
    let rpcUsername = "Jw2Fresh420" // 🔒 Replace with your actual RPC username
    let rpcPassword = "0dvsiwbrbi0BITC0IN2021" // 🔒 Replace with your actual RPC password

    var request = URLRequest(url: rpcURL)
    request.httpMethod = "POST"
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")

    // Basic Authentication
    let credentials = "\(rpcUsername):\(rpcPassword)"
    if let encoded = credentials.data(using: .utf8)?.base64EncodedString() {
        request.addValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
    }

    // JSON-RPC Body
    let rpcPayload: [String: Any] = [
        "jsonrpc": "1.0",
        "id": "submitblock",
        "method": "submitblock",
        "params": [hexBlock]
    ]

    do {
        request.httpBody = try JSONSerialization.data(withJSONObject: rpcPayload, options: [])
    } catch {
        print("❌ Failed to encode JSON-RPC body: \(error)")
        return
    }

    let task = URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error {
            print("❌ RPC submission failed: \(error)")
            return
        }

        guard let data = data else {
            print("❌ No data received from RPC.")
            return
        }

        do {
            let result = try JSONSerialization.jsonObject(with: data, options: [])
            print("✅ Block submitted. RPC result: \(result)")
        } catch {
            print("❌ Failed to decode RPC response: \(error)")
        }
    }

    task.resume()
}
// MARK: - Fetch Block Template and Start Mining via JSON-RPC

func fetchAndRunMiner() {
    let rpcURL = URL(string: "http://127.0.0.1:8332/")!
    var request = URLRequest(url: rpcURL)
    request.httpMethod = "POST"
    let rpcUsername = "Jw2Fresh420"
    let rpcPassword = "0dvsiwbrbi0BITC0IN2021"
    let loginString = "\(rpcUsername):\(rpcPassword)"
    let loginData = loginString.data(using: .utf8)!
    let base64LoginString = loginData.base64EncodedString()
    request.addValue("Basic \(base64LoginString)", forHTTPHeaderField: "Authorization")
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")

    let jsonString = """
    {
      "jsonrpc": "1.0",
      "id": "metalminer",
      "method": "getblocktemplate",
      "params": [{"rules":["segwit"]}]
    }
    """
    request.httpBody = jsonString.data(using: .utf8)

    URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error {
            print("❌ RPC error: \(error)")
            return
        }
        
        if let httpResponse = response as? HTTPURLResponse {
            print("HTTP status code: \(httpResponse.statusCode)")
            print("Response headers: \(httpResponse.allHeaderFields)")
        }
        
        guard let data = data, data.count > 0 else {
            print("❌ No data received or data is empty")
            return
        }

        if let rawResponse = String(data: data, encoding: .utf8) {
            print("Raw response:\n\(rawResponse)")
        } else {
            print("Could not decode response as UTF-8 string.")
        }

        do {
            let decoder = JSONDecoder()
            let result = try decoder.decode(RPCResult<BitcoinBlockTemplate>.self, from: data)
            DispatchQueue.main.async {
                runMiner(with: result.result)
            }
        } catch {
            print("❌ Failed to decode block template: \(error)")
        }
    }.resume()
}
