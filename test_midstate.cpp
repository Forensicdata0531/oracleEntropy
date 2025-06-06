#include <iostream>
#include <vector>
#include <string>
#include <sstream>
#include <iomanip>
#include "sha256_wrapper.hpp"

std::vector<uint8_t> hexStrToBytes(const std::string& hex) {
    std::vector<uint8_t> bytes;
    for (size_t i = 0; i < hex.size(); i += 2) {
        std::string byteString = hex.substr(i, 2);
        uint8_t byte = static_cast<uint8_t>(strtol(byteString.c_str(), nullptr, 16));
        bytes.push_back(byte);
    }
    return bytes;
}

int main() {
    std::string headerHex = "00c07823e498a6f1684ee9f3863ba9fadbde5c5756dfbfe4e3f400000000000000000000fd15d696b4bb18fd8a4cd7994a74c7b3d110c6a19fe9838f01f933cc";

    std::vector<uint8_t> header = hexStrToBytes(headerHex);

    // ✅ Only use the first 64 bytes (1 SHA-256 block) for midstate
    std::vector<uint8_t> first64(header.begin(), header.begin() + 64);

    std::string midstateHex = compute_sha256_midstate_hex(first64.data(), first64.size());
    std::cout << "Computed midstate: " << midstateHex << std::endl;

    return 0;
}
