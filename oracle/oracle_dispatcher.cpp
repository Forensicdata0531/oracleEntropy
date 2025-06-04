#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <algorithm>
#include <nlohmann/json.hpp>
#include "../entropy_metrics.hpp"
#include "../entropy_filter.cpp"
#include "oracle_table.hpp"

using json = nlohmann::json;

std::vector<uint8_t> hex_to_bytes(const std::string& hex) {
    std::vector<uint8_t> bytes;
    for (size_t i = 0; i < hex.length(); i += 2) {
        std::string byteString = hex.substr(i, 2);
        uint8_t byte = static_cast<uint8_t>(strtol(byteString.c_str(), nullptr, 16));
        bytes.push_back(byte);
    }
    return bytes;
}

struct ScoredMidstate {
    std::string blockhash;
    std::string midstate_hex;
    std::string tail_hex;
    double score;
};

int main() {
    std::ifstream inFile("oracle/midstates.json");
    if (!inFile) {
        std::cerr << "❌ Error: oracle/midstates.json not found.\n";
        return 1;
    }

    json mids_json;
    inFile >> mids_json;

    if (!mids_json.is_array() || mids_json.empty()) {
        std::cerr << "❌ Error: oracle/midstates.json is empty or malformed.\n";
        return 1;
    }

    std::vector<ScoredMidstate> scored;

    // Build histogram for all entries
    MidstateHistogram hist = buildMidstateHistogram("oracle/midstates.json");

    for (const auto& entry : mids_json) {
        if (!entry.contains("midstate") || !entry.contains("blockhash") || !entry.contains("tail")) {
            continue; // skip incomplete entries
        }

        const std::string& midstate_hex = entry["midstate"];
        const std::string& blockhash = entry["blockhash"];
        const std::string& tail_hex = entry["tail"];

        if (midstate_hex.size() != 64 || tail_hex.size() < 8) continue; // sanity check

        auto bytes = hex_to_bytes(midstate_hex);
        auto bits = entropy::bytes_to_bits(bytes);

        double entropy_val = entropy::shannon_entropy(bits);
        double pattern_score = scoreByHistogram(midstate_hex, hist);
        double final_score = 0.6 * entropy_val + 0.4 * pattern_score;

        scored.push_back({blockhash, midstate_hex, tail_hex, final_score});
    }

    std::sort(scored.begin(), scored.end(), [](const ScoredMidstate& a, const ScoredMidstate& b) {
        return a.score > b.score;
    });

    const int N = 131072;
    json top_json = json::array();

    std::cout << "📊 Top " << N << " scored midstates:\n";

    for (int i = 0; i < std::min(N, static_cast<int>(scored.size())); ++i) {
        const auto& s = scored[i];
        if (i < 10) {
            std::cout << "[" << i + 1 << "] " << s.blockhash << " | score: " << s.score << "\n";
        }

        top_json.push_back({
            {"blockhash", s.blockhash},
            {"midstate", s.midstate_hex},
            {"tail", s.tail_hex},
            {"score", s.score}
        });
    }

    // Repeat top entries if fewer than N
    while ((int)top_json.size() < N && !top_json.empty()) {
        for (size_t i = 0; i < top_json.size() && (int)top_json.size() < N; ++i) {
            top_json.push_back(top_json[i]);
        }
    }

    std::ofstream outFile("oracle/top_midstates.json");
    if (!outFile) {
        std::cerr << "❌ Error: Could not write to oracle/top_midstates.json\n";
        return 1;
    }

    outFile << top_json.dump(2);
    std::cout << "✅ Saved top midstates to oracle/top_midstates.json\n";

    return 0;
}
