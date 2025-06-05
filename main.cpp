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
#include <nlohmann/json.hpp>
#include <mutex>
#include <atomic>
#include <ncurses.h>
#include <fstream>
#include <sstream>
#include <iomanip>

bool metalMineBlock(
    const BlockHeader& header,
    const std::vector<uint8_t>& target,
    uint32_t initialNonceBase,
    uint32_t& validIndex,
    std::vector<uint8_t>& validHash,
    std::vector<uint8_t>& sampleHashOut,
    uint64_t& totalHashesTried);

static bool keepRunning = true;
void handleInterrupt(int) { keepRunning = false; }

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
            if (response["error"].is_object()) {
                logLine("[RPC Submitblock Error]: " + response["error"].value("message", "Unknown error"));
            } else if (response["error"].is_string()) {
                logLine("[RPC Submitblock Error]: " + response["error"].get<std::string>());
            } else {
                logLine("[RPC Submitblock Error]: Unknown error format");
            }
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
    initscr(); noecho(); cbreak(); curs_set(FALSE);
    int rows, cols;
    getmaxyx(stdscr, rows, cols);

    int statsHeight = 11;
    int logHeight = rows - statsHeight - 1;
    WINDOW* statsWin = newwin(statsHeight, cols, 0, 0);
    WINDOW* logWin = newwin(logHeight, cols, statsHeight, 0);

    while (!stats.quit.load()) {
        werase(statsWin); werase(logWin);
        mvwprintw(statsWin, 0, 1, "🚀 MetalMiner: Real-Time Mining Dashboard");
        mvwprintw(statsWin, 2, 2, "Midstate Index  : %u", stats.nonceBase.load());
        mvwprintw(statsWin, 3, 2, "Total Hashes    : %'llu", stats.totalHashes.load());
        mvwprintw(statsWin, 4, 2, "Hashrate        : %.2f H/s", stats.hashrate.load());

        if (stats.startTime.load() != std::chrono::steady_clock::time_point{})
            mvwprintw(statsWin, 5, 2, "Uptime          : %s", formatUptime(stats.startTime).c_str());

        {
            std::lock_guard<std::mutex> lock(stats.mutex);
            mvwprintw(statsWin, 7, 2, "Sample Hash     : %.64s", stats.sampleHashStr.c_str());
            if (stats.found.load()) {
                wattron(statsWin, A_BOLD);
                mvwprintw(statsWin, 8, 2, "✅ Valid Hash Found:");
                wattroff(statsWin, A_BOLD);
                mvwprintw(statsWin, 9, 2, "Index           : %u", stats.validNonce);
                mvwprintw(statsWin, 10, 2, "Valid Hash      : %.64s", stats.validHashStr.c_str());
            } else {
                mvwprintw(statsWin, 8, 2, "Searching for valid midstate...");
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

    std::thread uiThread;

    try {
        RpcClient rpc("http://127.0.0.1:8332", "Jw2Fresh420", "0dvsiwbrbi0BITC0IN2021");

        logLine("📡 Fetching block template from RPC...");
        BlockTemplate tpl = getBlockTemplate(rpc);

        BlockHeader header;
        header.version = tpl.version;

        if (tpl.prevBlockHash.size() != 32) throw std::runtime_error("Invalid prevBlockHash size");
        std::copy_n(tpl.prevBlockHash.begin(), 32, header.prevBlockHash.begin());

        if (tpl.merkleRoot.size() != 32) throw std::runtime_error("Invalid merkleRoot size");
        std::copy_n(tpl.merkleRoot.begin(), 32, header.merkleRoot.begin());

        header.timestamp = tpl.curtime;
        header.bits = std::stoul(tpl.bits, nullptr, 16);

        auto target = bitsToTarget(header.bits);

        logLine("🧠 Running entropy oracle...");
        int oracleCode = system("./oracle/oracle_dispatcher");
        if (oracleCode != 0) {
            logLine("❌ Oracle dispatcher failed.");
            return 1;
        }

        logLine("✅ Oracle finished scoring midstates.");
        logLine("🎯 Target (difficulty bits): " + toHex(header.bits));
        logLine("⚙️ Starting GPU mining...");

        stats.nonceBase = 0;
        stats.totalHashes = 0;
        stats.startTime.store(std::chrono::steady_clock::now());
        stats.quit.store(false);

        uiThread = std::thread(uiLoop);
        std::vector<uint8_t> bestSampleHash(32, 0xff);

        while (keepRunning) {
            uint32_t validIndex = 0;
            std::vector<uint8_t> validHash;
            std::vector<uint8_t> sampleHash(32, 0);
            uint64_t hashesTried = 0;

            auto batchStart = std::chrono::steady_clock::now();
            bool found = metalMineBlock(header, target, stats.nonceBase.load(), validIndex, validHash, sampleHash, hashesTried);
            auto batchEnd = std::chrono::steady_clock::now();

            stats.totalHashes.fetch_add(hashesTried);
            double seconds = std::chrono::duration<double>(batchEnd - batchStart).count();
            if (seconds > 0)
                stats.hashrate.store(static_cast<float>(hashesTried) / seconds);
            stats.nonceBase.fetch_add(static_cast<uint32_t>(hashesTried));

            {
                std::lock_guard<std::mutex> lock(stats.mutex);
                stats.sampleHashStr = bytesToHex(sampleHash);
                std::copy_n(sampleHash.begin(), std::min(sampleHash.size(), stats.sampleHash.size()), stats.sampleHash.begin());

                if (!validHash.empty()) {
                    stats.validNonce = validIndex;
                    stats.validHashStr = bytesToHex(validHash);
                    stats.found.store(true);

                    logLine("✅ Valid hash found at midstate index: " + std::to_string(validIndex));
                    std::string fullBlockHex = createFullBlockHex(header, validIndex, "", nlohmann::json::array());
                    submitBlockRpc(rpc, fullBlockHex);
                    break;
                } else {
                    stats.found.store(false);
                }
            }
        }

        stats.quit.store(true);
        if (uiThread.joinable()) uiThread.join();
        logLine("🛑 Mining stopped.");

    } catch (const std::exception& ex) {
        stats.quit.store(true);
        if (uiThread.joinable()) uiThread.join();
        std::cerr << "💥 Exception: " << ex.what() << "\n";
        return 1;
    }

    return 0;
}
