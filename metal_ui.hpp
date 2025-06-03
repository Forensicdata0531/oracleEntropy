#pragma once
#include <atomic>
#include <string>
#include <array>
#include <mutex>
#include <chrono>

struct MiningStats {
    std::atomic<bool> quit{false};                    // Signal to stop mining
    std::atomic<uint64_t> totalHashes{0};             // Total hashes computed
    std::atomic<uint32_t> nonceBase{0};               // Starting nonce for thread/batch
    std::atomic<bool> found{false};                   // Flag if a valid hash was found
    std::atomic<float> hashrate{0.0f};                // Hashrate in H/s

    std::array<uint8_t, 32> sampleHash{};             // Latest sample hash (raw bytes)
    std::string sampleHashStr;                        // Latest sample hash as hex string
    std::string validHashStr;                         // Valid found hash (hex)
    uint32_t validNonce{0};                           // Nonce that produced validHashStr

    std::atomic<std::chrono::steady_clock::time_point> startTime;  // Mining start time
    std::mutex mutex;                                 // Guards sampleHashStr, validHashStr, validNonce
};

// Update TUI using ncurses or similar
void updateCursesUI(MiningStats& stats);

