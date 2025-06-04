#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <nlohmann/json.hpp>
#include "sha256_wrapper.hpp"

using json = nlohmann::json;

// Utility: Convert hex string to bytes
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
    std::ifstream inFile("oracle/block_headers.json");
    if (!inFile) {
        std::cerr << "❌ Error: oracle/block_headers.json not found.\n";
        return 1;
    }

    json headers_json;
    inFile >> headers_json;
    std::cout << "Loaded " << headers_json.size() << " entries from block_headers.json\n";

    json output_json = json::array();  // Initialize explicitly as array

    for (const auto& entry : headers_json) {
        if (!entry.contains("header_hex")) {
            std::cerr << "⚠️ Skipping entry without 'header_hex'\n";
            continue;
        }
        if (!entry.contains("hash")) {
            std::cerr << "⚠️ Skipping entry without 'hash'\n";
            continue;
        }

        std::string hex_header = entry["header_hex"];
        std::string blockhash = entry["hash"];

        std::vector<uint8_t> raw = hex_to_bytes(hex_header);
        std::string midstate_hex = compute_sha256_midstate_hex(raw.data(), raw.size());

        output_json.push_back({
            {"blockhash", blockhash},
            {"midstate", midstate_hex}
        });
    }

    std::ofstream outFile("oracle/midstates.json");
    if (!outFile) {
        std::cerr << "❌ Error: Unable to open oracle/midstates.json for writing.\n";
        return 1;
    }
    outFile << output_json.dump(2);

    std::cout << "✅ Saved " << output_json.size() << " midstates to oracle/midstates.json\n";
    return 0;
}
