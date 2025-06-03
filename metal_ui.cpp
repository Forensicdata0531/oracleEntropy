#include "metal_ui.hpp"
#include <ncurses.h>
#include <chrono>
#include <thread>
#include <iomanip>
#include <sstream>
#include <locale>

// Utility for formatting large numbers with commas
std::string formatWithCommas(uint64_t value) {
    std::ostringstream oss;
    oss.imbue(std::locale(""));
    oss << std::fixed << value;
    return oss.str();
}

// Formats hashrate nicely
std::string formatHashrate(float rate) {
    std::ostringstream oss;
    if (rate > 1e9)
        oss << std::fixed << std::setprecision(2) << rate / 1e9 << " GH/s";
    else if (rate > 1e6)
        oss << std::fixed << std::setprecision(2) << rate / 1e6 << " MH/s";
    else if (rate > 1e3)
        oss << std::fixed << std::setprecision(2) << rate / 1e3 << " kH/s";
    else
        oss << std::fixed << std::setprecision(2) << rate << " H/s";
    return oss.str();
}

// Formats duration as HH:MM:SS
std::string formatUptime(std::chrono::steady_clock::time_point start) {
    auto now = std::chrono::steady_clock::now();
    auto secs = std::chrono::duration_cast<std::chrono::seconds>(now - start).count();

    int hours = static_cast<int>(secs / 3600);
    int minutes = static_cast<int>((secs % 3600) / 60);
    int seconds = static_cast<int>(secs % 60);

    std::ostringstream oss;
    oss << std::setfill('0') << std::setw(2) << hours << ":"
        << std::setw(2) << minutes << ":"
        << std::setw(2) << seconds;
    return oss.str();
}

void updateCursesUI(MiningStats& stats) {
    initscr();
    noecho();
    cbreak();
    curs_set(FALSE);

    while (!stats.quit.load(std::memory_order_acquire)) {
        clear();

        mvprintw(1, 2, "🚀 MetalMiner: Real-Time Mining Dashboard");
        mvprintw(3, 2, "Nonce Base      : %u", stats.nonceBase.load(std::memory_order_relaxed));
        mvprintw(4, 2, "Total Hashes    : %s", formatWithCommas(stats.totalHashes.load()).c_str());
        mvprintw(5, 2, "Hashrate        : %s", formatHashrate(stats.hashrate.load()).c_str());

        // Uptime based on start time
        auto startTime = stats.startTime.load();
        if (startTime != std::chrono::steady_clock::time_point{})
            mvprintw(6, 2, "Uptime          : %s", formatUptime(startTime).c_str());

        {
            std::lock_guard<std::mutex> lock(stats.mutex);
            if (!stats.sampleHashStr.empty())
                mvprintw(8, 2, "Sample Hash     : %.64s...", stats.sampleHashStr.c_str());

            if (stats.found.load(std::memory_order_acquire)) {
                attron(A_BOLD);
                mvprintw(10, 2, "✅ Valid Hash Found:");
                attroff(A_BOLD);
                mvprintw(11, 2, "Nonce           : %u", stats.validNonce);
                mvprintw(12, 2, "Valid Hash      : %.64s", stats.validHashStr.c_str());
            } else {
                mvprintw(10, 2, "Searching for valid nonce...");
            }
        }

        mvprintw(14, 2, "Press Ctrl+C to exit.");
        refresh();
        std::this_thread::sleep_for(std::chrono::milliseconds(200));
    }

    endwin();
}

