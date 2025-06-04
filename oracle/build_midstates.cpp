#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <sstream>
#include <iomanip>
#include <openssl/sha.h>
#include <nlohmann/json.hpp>

using json = nlohmann::json;

std::vector<uint8_t> hexToBytes(const std::string& hex) {
    std::vector<uint8_t> bytes;
    for (size_t i = 0; i < hex.length(); i += 2)
        bytes.push_back(static_cast<uint8_t>(std::stoul(hex.substr(i, 2), nullptr, 16)));
    return bytes;
}

std::string bytesToHex(const std::vector<uint8_t>& bytes) {
    std::ostringstream oss;
    for (uint8_t b : bytes)
        oss << std::hex << std::setw(2) << std::setfill('0') << (int)b;
    return oss.str();
}

std::string sha256Midstate(const std::vector<uint8_t>& header64) {
    SHA256_CTX ctx;
    SHA256_Init(&ctx);
    SHA256_Update(&ctx, header64.data(), header64.size());

    // midstate lives inside ctx.h[]
    std::ostringstream oss;
    for (int i = 0; i < 8; ++i) {
        uint32_t word = ctx.h[i];
        for (int b = 3; b >= 0; --b)
            oss << std::hex << std::setw(2) << std::setfill('0') << ((word >> (b * 8)) & 0xff);
    }
    return oss.str();
}

int main() {
    std::ifstream in("oracle/block_headers.json");
    if (!in) {
        std::cerr << "❌ Cannot open block_headers.json\n";
        return 1;
    }

    json blocks;
    in >> blocks;
    json out = json::array();

    for (const auto& b : blocks) {
        // Use correct keys from your JSON:
        if (!b.contains("hash") || !b.contains("header_hex")) {
            std::cerr << "Warning: missing or invalid hash/header_hex, skipping\n";
            continue;
        }
        std::string blockhash = b["hash"];
        std::string headerHex = b["header_hex"];
        auto headerBytes = hexToBytes(headerHex);
        if (headerBytes.size() != 80) {
            std::cerr << "Warning: header length != 80 bytes, skipping\n";
            continue;
        }

        std::vector<uint8_t> first64(headerBytes.begin(), headerBytes.begin() + 64);
        std::vector<uint8_t> tail(headerBytes.begin() + 64, headerBytes.end());

        std::string midstate = sha256Midstate(first64);
        std::string tailHex = bytesToHex(tail);

        out.push_back({
            {"blockhash", blockhash},
            {"midstate", midstate},
            {"tail", tailHex}
        });
    }

    std::ofstream outFile("oracle/midstates.json");
    if (!outFile) {
        std::cerr << "❌ Cannot write to midstates.json\n";
        return 1;
    }

    outFile << out.dump(2);
    std::cout << "✅ Wrote " << out.size() << " entries to oracle/midstates.json\n";
    return 0;
}
