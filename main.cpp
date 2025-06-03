#include "utils.hpp"
#include "block.hpp"
#include "midstate_utils.hpp"
#include <iostream>
#include <chrono>
#include <thread>
#include <climits>

int main() {
    try {
        std::cout << "Loading block template...\n";
        std::string blockTemplateJson = loadBlockTemplate("blocktemplate.json");

        std::cout << "Block template loaded, parsing...\n";

        BlockHeader header;
        header.version = 0x20000000;
        std::fill(header.prevBlockHash.begin(), header.prevBlockHash.end(), 0);
        std::fill(header.merkleRoot.begin(), header.merkleRoot.end(), 0);
        header.timestamp = 0x5F5E100;
        header.bits = 0x1d00ffff;
        header.nonce = 0;

        // Serialize header
        auto headerBytes = serializeHeader(header);

        // Calculate midstate from first 64 bytes (everything except nonce)
        std::vector<uint8_t> prefix(headerBytes.begin(), headerBytes.begin() + 64);
        auto midstate = calculateMidstateArray(prefix);

        std::cout << "Starting mining simulation...\n";

        for (uint32_t nonce = 0; nonce < UINT32_MAX; ++nonce) {
            header.nonce = nonce;
            auto headerSer = serializeHeader(header);

            auto hash = sha256d(headerSer);

            // Convert hash to big-endian for target comparison
            std::vector<uint8_t> hashBE(hash.rbegin(), hash.rend());

            auto target = bitsToTarget(header.bits);

            if (std::lexicographical_compare(hashBE.begin(), hashBE.end(), target.begin(), target.end())) {
                std::cout << "Block mined! Nonce: " << nonce << "\n";
                std::cout << "Hash: " << bytesToHex(hashBE) << "\n";
                break;
            }

            if (nonce % 1000000 == 0) {
                std::cout << "Tried " << nonce << " nonces...\n";
                std::this_thread::sleep_for(std::chrono::milliseconds(10));
            }
        }
    } catch (const std::exception& ex) {
        std::cerr << "Exception: " << ex.what() << "\n";
        return 1;
    }

    return 0;
}
