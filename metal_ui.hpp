#pragma once
#include <atomic>
#include <string>
#include <array>
#include <mutex>
#include <chrono>
#include <vector>
#include <deque>

// Forward declaration
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

// Ring buffer logger for UI window
class RingLog {
    std::deque<std::string> lines;
    size_t max;
    std::mutex mtx;

public:
    RingLog(size_t maxLines = 500) : max(maxLines) {}

    void push(const std::string& line) {
        std::lock_guard<std::mutex> lock(mtx);
        lines.push_back(line);
        if (lines.size() > max)
            lines.pop_front();
    }

    std::vector<std::string> getLines(size_t n) {
        std::lock_guard<std::mutex> lock(mtx);
        size_t start = lines.size() > n ? lines.size() - n : 0;
        return std::vector<std::string>(lines.begin() + start, lines.end());
    }
};

void updateCursesUI(MiningStats& stats);
