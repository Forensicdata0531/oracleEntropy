#include <iostream>
#include <fstream>
#include <unordered_set>
#include <vector>
#include <string>
#include <nlohmann/json.hpp>

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

int main() {
    std::ifstream inFile("oracle/midstates.json");
    if (!inFile) {
        std::cerr << "❌ Error: oracle/midstates.json not found.\n";
        return 1;
    }

    json midstates_json;
    inFile >> midstates_json;

    std::unordered_set<std::string> unique_midstates;

    int count = 0;
    for (const auto& entry : midstates_json) {
        if (!entry.contains("midstate")) {
            std::cerr << "⚠️ Skipping entry without 'midstate'\n";
            continue;
        }
        std::string midstate_hex = entry["midstate"];
        unique_midstates.insert(midstate_hex);
        ++count;
    }

    std::cout << "Total midstates processed: " << count << "\n";
    std::cout << "Unique midstates count: " << unique_midstates.size() << "\n";

    // Print first 5 unique midstates as a sample
    int printed = 0;
    for (const auto& m : unique_midstates) {
        std::cout << m << "\n";
        if (++printed >= 5) break;
    }

    return 0;
}
