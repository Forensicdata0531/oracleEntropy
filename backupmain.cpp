#include <iostream>
#include <vector>
#include <iomanip>
#include <limits>
#include <algorithm>
#include <chrono>
#include <cstdint>
#include <openssl/sha.h>

#include "blocktemplate.hpp"
#include "nlohmann/json.hpp"
#include "utils.hpp"
#include "block.hpp"
#include "blockbuilder.hpp"
#include "rpc.hpp"
#include "coinbase.hpp"
#include "merkle.hpp"
#include "metal_miner.hpp"  // GPU mining interface

void appendUint32LE(std::vector<uint8_t>& data, uint32_t val) {
    for (int i = 0; i < 4; ++i)
        data.push_back(static_cast<uint8_t>(val >> (8 * i)));
}

std::vector<uint8_t> serializeHeader(const BlockHeader& header) {
    std::vector<uint8_t> data;

    appendUint32LE(data, header.version);

    std::vector<uint8_t> prevHashLE = header.prevBlockHash;
    reverseBytes(prevHashLE);
    data.insert(data.end(), prevHashLE.begin(), prevHashLE.end());

    std::vector<uint8_t> merkleRootLE = header.merkleRoot;
    reverseBytes(merkleRootLE);
    data.insert(data.end(), merkleRootLE.begin(), merkleRootLE.end());

    appendUint32LE(data, header.timestamp);
    appendUint32LE(data, header.bits);
    appendUint32LE(data, header.nonce);

    return data;
}

int hashCompare(const std::vector<uint8_t>& a, const std::vector<uint8_t>& b) {
    for (size_t i = 0; i < a.size(); ++i) {
        if (a[i] < b[i]) return -1;
        if (a[i] > b[i]) return 1;
    }
    return 0;
}

int main() {
    std::cout << "Miner ready.\n";

    try {
        RpcClient rpc("http://127.0.0.1:8332", "Jw2Fresh420", "0dvsiwbrbi0BITC0IN2021");

        nlohmann::json params = {{{"rules", {"segwit"}}}};
        auto tmplJson = rpc.call("getblocktemplate", params);

        if (!tmplJson.contains("result") || !tmplJson["result"].is_object()) {
            throw std::runtime_error("Invalid RPC response: missing 'result' object");
        }

        tmplJson["result"]["coinbaseaddress"] = "1KV2cLzRjYU8FNZ84Wqfp28bcQZC62mcFA";
        BlockTemplate tmpl = BlockTemplate::from_json(tmplJson["result"]);

        std::string coinbaseHex = createCoinbaseTx(tmpl.height, tmpl.coinbaseAddress);
        std::vector<uint8_t> coinbaseBytes = hexToBytes(coinbaseHex);
        std::vector<uint8_t> coinbaseHash = doubleSHA256(coinbaseBytes);
        reverseBytes(coinbaseHash);

        std::vector<std::string> txids = { bytesToHex(coinbaseHash) };
        for (const auto& tx : tmpl.transactions)
            txids.push_back(tx.txid);

        std::vector<uint8_t> merkleRoot = calculateMerkleRoot(txids);

        BlockHeader header {
            .version = static_cast<uint32_t>(tmpl.version),
            .prevBlockHash = tmpl.prevBlockHash,
            .merkleRoot = merkleRoot,
            .timestamp = tmpl.curtime,
            .bits = static_cast<uint32_t>(std::stoul(tmpl.bits, nullptr, 16)),
            .nonce = 0
        };

        std::vector<uint8_t> target = bitsToTarget(header.bits);
        if (bytesToHex(target) != tmpl.target) {
            std::cerr << "⚠️ Warning: bits-derived target doesn't match JSON target field\n";
        }

        std::cout << "Block Height: " << tmpl.height << "\n";
        std::cout << "Block Version: " << tmpl.version << "\n";
        std::cout << "Transaction Count: " << (1 + tmpl.transactions.size()) << "\n";
        std::cout << "Merkle Root: " << bytesToHex(merkleRoot) << "\n";
        std::cout << "Target: " << bytesToHex(target) << "\n";

        std::vector<uint8_t> rawHeader = serializeHeader(header);
        std::cout << "Raw Header (hex): " << bytesToHex(rawHeader) << "\n";

        std::cout << "Starting GPU mining...\n";
        auto startTime = std::chrono::high_resolution_clock::now();

        uint32_t validNonce = 0;
        std::vector<uint8_t> validHash(32);
        uint64_t totalHashesTried = 0;

        std::cout << "Launching metalMineBlock...\n";
        bool found = metalMineBlock(header, target, 0, validNonce, validHash, totalHashesTried);
        std::cout << "metalMineBlock finished.\n";

        auto endTime = std::chrono::high_resolution_clock::now();
        double duration = std::chrono::duration<double>(endTime - startTime).count();

        if (found) {
            reverseBytes(validHash);
            std::cout << "\n✓ Valid nonce found: " << validNonce << "\n";
            std::cout << "✓ Valid hash: " << bytesToHex(validHash) << "\n";

            int cmp = hashCompare(validHash, target);
            if (cmp <= 0) {
                std::cout << "✓ Valid hash is below the target.\n";

                // Finalize full block data
                std::vector<std::vector<uint8_t>> allTxs = { coinbaseBytes };
                for (const auto& tx : tmpl.transactions)
                    allTxs.push_back(hexToBytes(tx.data));

                std::vector<uint8_t> fullBlock = buildFullBlock(header, allTxs);
                std::string blockHex = bytesToHex(fullBlock);

                std::cout << "\n📦 Submitting block...\n";
                try {
                    nlohmann::json submitResult = rpc.call("submitblock", { blockHex });
                    if (submitResult.is_null()) {
                        std::cout << "✅ Block accepted by node.\n";
                    } else {
                        std::cout << "❌ Block rejected or unknown status: " << submitResult.dump() << "\n";
                    }
                } catch (const std::exception& ex) {
                    std::cerr << "❌ Error submitting block: " << ex.what() << "\n";
                }

                // Backup manual hex print
                std::cout << "\n📋 Backup block hex for manual submission:\n";
                std::cout << blockHex << "\n";

            } else {
                std::cerr << "⚠️ Error: Valid hash NOT below target! Possible bug.\n";
            }
        } else {
            std::cout << "No valid nonce found in this range.\n";
        }

        std::cout << "Hashes tried: " << totalHashesTried << "\n";
        std::cout << "Mining duration: " << duration << " seconds\n";
        if (duration > 0)
            std::cout << "Hashrate: " << (totalHashesTried / duration) << " hashes/sec\n";
        else
            std::cout << "Hashrate: Duration too short to calculate.\n";

    } catch (const std::exception& ex) {
        std::cerr << "Error: " << ex.what() << "\n";
    }

    return 0;
}
