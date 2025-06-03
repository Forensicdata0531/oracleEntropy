#include "utils.hpp"
#include "block.hpp"
#include "block_utils.hpp"
#include "metal_ui.hpp"
#include "rpc.hpp"
#include "coinbase.hpp"
#include <iostream>
#include <vector>
#include <thread>
#include <chrono>
#include <csignal>
#include <algorithm>
#include <nlohmann/json.hpp>

bool metalMineBlock(
    const BlockHeader& header,
    const std::vector<uint8_t>& target,
    uint32_t initialNonceBase,
    uint32_t& validNonce,
    std::vector<uint8_t>& validHash,
    uint64_t& totalHashesTried);

static bool keepRunning = true;
void handleInterrupt(int) {
    keepRunning = false;
}

std::vector<uint8_t> txHashFromHex(const std::string& txHex) {
    auto txBytes = hexToBytes(txHex);
    return doubleSHA256(txBytes);
}

std::vector<uint8_t> computeMerkleRoot(std::vector<std::vector<uint8_t>> txHashes) {
    if (txHashes.empty())
        throw std::runtime_error("No transactions for Merkle root");

    while (txHashes.size() > 1) {
        if (txHashes.size() % 2 != 0)
            txHashes.push_back(txHashes.back());

        std::vector<std::vector<uint8_t>> newLevel;
        for (size_t i = 0; i < txHashes.size(); i += 2) {
            std::vector<uint8_t> concat;
            concat.reserve(txHashes[i].size() + txHashes[i + 1].size());
            concat.insert(concat.end(), txHashes[i].begin(), txHashes[i].end());
            concat.insert(concat.end(), txHashes[i + 1].begin(), txHashes[i + 1].end());
            newLevel.push_back(doubleSHA256(concat));
        }
        txHashes = std::move(newLevel);
    }
    return txHashes[0];
}

int main() {
    signal(SIGINT, handleInterrupt);

    try {
        RpcClient rpc("http://127.0.0.1:8332", "Jw2Fresh420", "0dvsiwbrbi0BITC0IN2021");

        std::cout << "📡 Fetching block template from RPC...\n";
        nlohmann::json params = nlohmann::json::array();
        params.push_back({ {"rules", {"segwit"}} });

        nlohmann::json rpcResponse = rpc.call("getblocktemplate", params);

        if (!rpcResponse.contains("result") || rpcResponse["result"].is_null()) {
            if (rpcResponse.contains("error") && !rpcResponse["error"].is_null()) {
                auto err = rpcResponse["error"];
                int code = err.value("code", 0);
                std::string message = err.value("message", "Unknown error");
                if (message.size() > 200)
                    message = message.substr(0, 200) + "... [truncated]";
                throw std::runtime_error("RPC Error (code " + std::to_string(code) + "): " + message);
            } else {
                throw std::runtime_error("RPC response missing or null 'result' field");
            }
        }

        nlohmann::json blockTemplateJson = rpcResponse["result"];
        std::cout << "Received block template keys: ";
        for (auto& el : blockTemplateJson.items()) std::cout << el.key() << " ";
        std::cout << std::endl;

        int blockHeight = blockTemplateJson.value("height", 0);
        std::string payoutAddress = "bc1qgj6au67l9n5rjnwsm48s64ermf94jfm2r4mmk7";
        std::string coinbaseTxHex = createCoinbaseTx(blockHeight, payoutAddress);

        std::vector<std::vector<uint8_t>> txHashes;
        txHashes.push_back(txHashFromHex(coinbaseTxHex));
        for (const auto& tx : blockTemplateJson["transactions"]) {
            std::string txHex = tx["data"].get<std::string>();
            txHashes.push_back(txHashFromHex(txHex));
        }

        std::vector<uint8_t> merkleRoot = computeMerkleRoot(txHashes);
        blockTemplateJson["merkleroot"] = bytesToHex(std::vector<uint8_t>(merkleRoot.rbegin(), merkleRoot.rend()));

        BlockHeader header = parseBlockHeader(blockTemplateJson);
        if (merkleRoot.size() != 32)
            throw std::runtime_error("Merkle root size incorrect");
        std::copy_n(merkleRoot.begin(), 32, header.merkleRoot.begin());

        auto target = bitsToTarget(header.bits);
        std::cout << "🎯 Target (difficulty bits): " << std::hex << header.bits << "\n";
        std::cout << "⚙️  Starting GPU mining...\n";

        MiningStats stats;
        stats.nonceBase = 0;

        while (keepRunning) {
            uint32_t validNonce = 0;
            std::vector<uint8_t> validHash;
            uint64_t hashesTried = 0;

            bool found = metalMineBlock(header, target, stats.nonceBase, validNonce, validHash, hashesTried);

            stats.hashrate = hashesTried / 1e6;

            if (validHash.size() >= 32)
                std::copy_n(validHash.begin(), 32, stats.sampleHash.begin());
            else
                std::fill(stats.sampleHash.begin(), stats.sampleHash.end(), 0);

            stats.validNonce = found ? validNonce : 0;
            updateCursesUI(stats);

            if (found) {
                std::cout << "\n✅ Block mined! Nonce: " << validNonce << "\n";
                std::cout << "Hash: " << bytesToHex(validHash) << "\n";
                break;
            }

            stats.nonceBase += static_cast<uint32_t>(hashesTried);
        }

        std::cout << "🛑 Mining stopped.\n";

    } catch (const std::exception& ex) {
        std::cerr << "💥 Exception: " << ex.what() << "\n";
        return 1;
    }

    return 0;
}
