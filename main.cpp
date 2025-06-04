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
#include <mutex>
#include <atomic>
#include <deque>
#include <sstream>
#include <condition_variable>
#include <iomanip>
#include <ncurses.h>
#include <fstream>

bool metalMineBlock(
    const BlockHeader& header,
    const std::vector<uint8_t>& target,
    uint32_t initialNonceBase,
    uint32_t& validNonce,
    std::vector<uint8_t>& validHash,
    uint64_t& totalHashesTried);

inline void writeUint32LE(std::vector<uint8_t>& buf, uint32_t val) {
    buf.push_back(val & 0xff);
    buf.push_back((val >> 8) & 0xff);
    buf.push_back((val >> 16) & 0xff);
    buf.push_back((val >> 24) & 0xff);
}

inline void writeUint64LE(std::vector<uint8_t>& buf, uint64_t val) {
    for (int i = 0; i < 8; i++)
        buf.push_back((val >> (8 * i)) & 0xff);
}

void writeVarInt(std::vector<uint8_t>& buf, uint64_t val) {
    if (val < 0xfd) {
        buf.push_back(static_cast<uint8_t>(val));
    } else if (val <= 0xffff) {
        buf.push_back(0xfd);
        buf.push_back(val & 0xff);
        buf.push_back((val >> 8) & 0xff);
    } else if (val <= 0xffffffff) {
        buf.push_back(0xfe);
        writeUint32LE(buf, static_cast<uint32_t>(val));
    } else {
        buf.push_back(0xff);
        writeUint64LE(buf, val);
    }
}

std::string createFullBlockHex(
    const BlockHeader& header,
    uint32_t nonce,
    const std::string& coinbaseTxHex,
    const nlohmann::json& transactionsJson)
{
    std::vector<uint8_t> blockBytes;

    writeUint32LE(blockBytes, header.version);
    blockBytes.insert(blockBytes.end(), header.prevBlockHash.begin(), header.prevBlockHash.end());
    blockBytes.insert(blockBytes.end(), header.merkleRoot.begin(), header.merkleRoot.end());
    writeUint32LE(blockBytes, header.timestamp);
    writeUint32LE(blockBytes, header.bits);
    writeUint32LE(blockBytes, nonce);

    writeVarInt(blockBytes, 1 + transactionsJson.size());

    auto coinbaseTxBytes = hexToBytes(coinbaseTxHex);
    blockBytes.insert(blockBytes.end(), coinbaseTxBytes.begin(), coinbaseTxBytes.end());

    for (const auto& tx : transactionsJson) {
        std::string txHex = tx["data"].get<std::string>();
        auto txBytes = hexToBytes(txHex);
        blockBytes.insert(blockBytes.end(), txBytes.begin(), txBytes.end());
    }

    return bytesToHex(blockBytes);
}

static bool keepRunning = true;
void handleInterrupt(int) { keepRunning = false; }

class RingLog {
    std::deque<std::string> buffer;
    size_t maxSize;
    std::mutex mtx;
public:
    explicit RingLog(size_t maxLines = 500) : maxSize(maxLines) {}
    void push(const std::string& line) {
        std::lock_guard<std::mutex> lock(mtx);
        if (buffer.size() >= maxSize) buffer.pop_front();
        buffer.push_back(line);
    }
    std::vector<std::string> getLines(size_t maxLines) {
        std::lock_guard<std::mutex> lock(mtx);
        size_t start = (buffer.size() > maxLines) ? buffer.size() - maxLines : 0;
        return std::vector<std::string>(buffer.begin() + start, buffer.end());
    }
};

RingLog ringLog(500);
MiningStats stats;
std::ofstream debugLogFile("mining_debug.log", std::ios::app);

void logLine(const std::string& line) { ringLog.push(line); }
void debugLog(const std::string& line) {
    if (debugLogFile.is_open()) {
        debugLogFile << line << std::endl;
        debugLogFile.flush();
    }
}

bool submitBlockRpc(RpcClient& rpc, const std::string& blockHex) {
    try {
        nlohmann::json params = nlohmann::json::array();
        params.push_back(blockHex);
        nlohmann::json response = rpc.call("submitblock", params);
        if (response.contains("error") && !response["error"].is_null()) {
            logLine("[RPC Submitblock Error]: " + response["error"].value("message", "Unknown error"));
            return false;
        } else {
            logLine("[RPC Submitblock]: Block accepted.");
            return true;
        }
    } catch (const std::exception& e) {
        logLine(std::string("[RPC Submitblock Exception]: ") + e.what());
        return false;
    }
}

void uiLoop() {
    initscr();
    noecho();
    cbreak();
    curs_set(FALSE);
    int rows, cols;
    getmaxyx(stdscr, rows, cols);

    int statsHeight = 11;
    int logHeight = rows - statsHeight - 1;
    WINDOW* statsWin = newwin(statsHeight, cols, 0, 0);
    WINDOW* logWin = newwin(logHeight, cols, statsHeight, 0);

    while (!stats.quit.load(std::memory_order_acquire)) {
        werase(statsWin);
        werase(logWin);

        mvwprintw(statsWin, 0, 1, "🚀 MetalMiner: Real-Time Mining Dashboard");
        mvwprintw(statsWin, 2, 2, "Nonce Base      : %u", stats.nonceBase.load());
        mvwprintw(statsWin, 3, 2, "Total Hashes    : %'llu", stats.totalHashes.load());
        mvwprintw(statsWin, 4, 2, "Hashrate        : %.2f H/s", stats.hashrate.load());

        auto startTime = stats.startTime.load();
        if (startTime != std::chrono::steady_clock::time_point{})
            mvwprintw(statsWin, 5, 2, "Uptime          : %s", formatUptime(startTime).c_str());

        {
            std::lock_guard<std::mutex> lock(stats.mutex);
            mvwprintw(statsWin, 7, 2, "Sample Hash     : %.64s", stats.sampleHashStr.c_str());
            if (stats.found.load()) {
                wattron(statsWin, A_BOLD);
                mvwprintw(statsWin, 8, 2, "✅ Valid Hash Found:");
                wattroff(statsWin, A_BOLD);
                mvwprintw(statsWin, 9, 2, "Nonce           : %u", stats.validNonce);
                mvwprintw(statsWin, 10, 2, "Valid Hash      : %.64s", stats.validHashStr.c_str());
            } else {
                mvwprintw(statsWin, 8, 2, "Searching for valid nonce...");
            }
        }

        wrefresh(statsWin);

        auto lines = ringLog.getLines(logHeight - 1);
        for (size_t i = 0; i < lines.size(); ++i)
            mvwprintw(logWin, i, 0, "%s", lines[i].c_str());

        box(logWin, 0, 0);
        wrefresh(logWin);

        std::this_thread::sleep_for(std::chrono::milliseconds(300));
    }

    delwin(statsWin);
    delwin(logWin);
    endwin();
}

int main() {
    signal(SIGINT, handleInterrupt);
    if (!debugLogFile.is_open()) {
        std::cerr << "Failed to open debug log file\n";
        return 1;
    }

    try {
        RpcClient rpc("http://127.0.0.1:8332", "Jw2Fresh420", "0dvsiwbrbi0BITC0IN2021");

        logLine("📡 Fetching block template from RPC...");
        auto rpcResponse = rpc.call("getblocktemplate", {{{"rules", {"segwit"}}}});

        if (!rpcResponse.contains("result") || rpcResponse["result"].is_null())
            throw std::runtime_error("Invalid block template from RPC");

        auto blockTemplateJson = rpcResponse["result"];
        for (auto& el : blockTemplateJson.items())
            debugLog(" - " + el.key());

        int blockHeight = blockTemplateJson.value("height", 0);
        std::string payoutAddress = "bc1qgj6au67l9n5rjnwsm48s64ermf94jfm2r4mmk7";
        std::string coinbaseTxHex = createCoinbaseTx(blockHeight, payoutAddress);

        std::vector<std::vector<uint8_t>> txHashes = { txHashFromHex(coinbaseTxHex) };
        for (const auto& tx : blockTemplateJson["transactions"])
            txHashes.push_back(txHashFromHex(tx["data"]));

        std::vector<uint8_t> merkleRoot = computeMerkleRoot(txHashes);
        blockTemplateJson["merkleroot"] = bytesToHex({merkleRoot.rbegin(), merkleRoot.rend()});

        BlockHeader header = parseBlockHeader(blockTemplateJson);
        std::copy_n(merkleRoot.begin(), 32, header.merkleRoot.begin());
        auto target = bitsToTarget(header.bits);

        logLine("🎯 Target (difficulty bits): " + toHex(header.bits));
        logLine("⚙️ Starting GPU mining...");

        stats.nonceBase = 0;
        stats.totalHashes = 0;
        stats.startTime.store(std::chrono::steady_clock::now());
        stats.quit.store(false);

        std::thread uiThread(uiLoop);

        std::vector<uint8_t> bestSampleHash(32, 0xff);

        while (keepRunning) {
            uint32_t validNonce = 0;
            std::vector<uint8_t> validHash;
            uint64_t hashesTried = 0;

            auto batchStart = std::chrono::steady_clock::now();
            bool found = metalMineBlock(header, target, stats.nonceBase.load(), validNonce, validHash, hashesTried);
            auto batchEnd = std::chrono::steady_clock::now();

            stats.totalHashes.fetch_add(hashesTried);

            auto seconds = std::chrono::duration<double>(batchEnd - batchStart).count();
            if (seconds > 0)
                stats.hashrate.store(static_cast<float>(hashesTried) / seconds);

            stats.nonceBase.fetch_add(static_cast<uint32_t>(hashesTried));

            {
                std::lock_guard<std::mutex> lock(stats.mutex);
                if (!validHash.empty()) {
                    // Update sample hash if better (lex order, meaning leading zeros)
                    if (validHash < bestSampleHash) {
                        bestSampleHash = validHash;
                        stats.sampleHashStr = bytesToHex(validHash);
                        stats.sampleHash.fill(0);
                        std::copy_n(validHash.begin(), std::min(validHash.size(), stats.sampleHash.size()), stats.sampleHash.begin());
                    }
                    if (found) {
                        stats.validHashStr = bytesToHex(validHash);
                    }
                }
            }

            stats.validNonce = found ? validNonce : 0;
            stats.found.store(found);

            if (found) {
                logLine("✅ Block mined! Nonce: " + std::to_string(validNonce));
                std::string fullBlockHex = createFullBlockHex(header, validNonce, coinbaseTxHex, blockTemplateJson["transactions"]);
                submitBlockRpc(rpc, fullBlockHex);
                break;
            }
        }

        stats.quit.store(true);
        uiThread.join();
        logLine("🛑 Mining stopped.");

    } catch (const std::exception& ex) {
        std::cerr << "💥 Exception: " << ex.what() << "\n";
        return 1;
    }

    return 0;
}
