#pragma once
#include <atomic>
#include <string>
#include <array>
#include <mutex>
#include <chrono>

// Forward declaration (no implementation here!)
std::string formatUptime(std::chrono::steady_clock::time_point start);

struct MiningStats {
    std::atomic<bool> quit{false};
    std::atomic<uint64_t> totalHashes{0};
    std::atomic<uint32_t> nonceBase{0};
    std::atomic<bool> found{false};
    std::atomic<float> hashrate{0.0f};

    std::array<uint8_t, 32> sampleHash{};
    std::string sampleHashStr;
    std::string validHashStr;
    uint32_t validNonce{0};

    std::atomic<std::chrono::steady_clock::time_point> startTime;
    std::mutex mutex;
};

void updateCursesUI(MiningStats& stats);
