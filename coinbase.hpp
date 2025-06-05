#pragma once
#include <string>
#include <vector>
#include <sstream>
#include <iomanip>
#include <stdexcept>

// Bech32 character map (reverse lookup)
static const int8_t bech32_charset_rev[128] = {
    -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
    -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
    -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
     15,-1,10,17,21,20,26,30,  7, 5,-1,-1,-1,-1,-1,-1,
    -1,29,24,13,25, 9, 8,23,18,22,31,27,19,  1,  0,  3,
    16,11,28,12,14, 6,  4,  2,-1,-1,-1,-1,-1,-1,-1,29,
    24,13,25, 9, 8,23,18,22,31,27,19,  1,  0,  3,16,11,
    28,12,14, 6,  4,  2,-1,-1,-1,-1,-1
};

// Convert 5-bit array to 8-bit array
inline std::vector<uint8_t> convertBits(const std::vector<uint8_t>& in, int fromBits, int toBits, bool pad) {
    int acc = 0, bits = 0;
    std::vector<uint8_t> out;
    const int maxv = (1 << toBits) - 1;

    for (uint8_t value : in) {
        if (value >> fromBits) throw std::runtime_error("convertBits: invalid input value");
        acc = (acc << fromBits) | value;
        bits += fromBits;
        while (bits >= toBits) {
            bits -= toBits;
            out.push_back((acc >> bits) & maxv);
        }
    }

    if (pad && bits > 0) {
        out.push_back((acc << (toBits - bits)) & maxv);
    } else if (!pad && (bits >= fromBits || ((acc << (toBits - bits)) & maxv))) {
        throw std::runtime_error("convertBits: invalid padding");
    }

    return out;
}

// Bech32 decoding (full implementation for bc1 P2WPKH and P2WSH)
inline std::vector<uint8_t> bech32Decode(const std::string& addr) {
    size_t sep = addr.find_last_of('1');
    if (sep == std::string::npos || sep < 1 || sep + 7 > addr.size())
        throw std::runtime_error("Invalid Bech32 address");

    std::vector<uint8_t> data;
    for (size_t i = sep + 1; i < addr.size(); ++i) {
        unsigned char c = static_cast<unsigned char>(addr[i]);  // Changed to unsigned char
        if (c >= 128 || bech32_charset_rev[c] == -1)
            throw std::runtime_error("Invalid character in Bech32 address");
        data.push_back(bech32_charset_rev[c]);
    }

    if (data.empty()) throw std::runtime_error("Empty Bech32 payload");
    if (data[0] > 16) throw std::runtime_error("Invalid witness version");

    return convertBits({data.begin() + 1, data.end() - 6}, 5, 8, false);
}

// Create coinbase TX paying 3.125 BTC to Bech32 P2WPKH address
inline std::string createCoinbaseTx(int blockHeight, const std::string& bech32Address, const std::string& extraNonceHex = "00000000") {
    std::ostringstream tx;

    tx << "01000000"; // version
    tx << "01";       // input count
    tx << std::string(64, '0');  // prevout hash
    tx << "ffffffff";

    std::vector<uint8_t> heightLE;
    int h = blockHeight;
    while (h > 0) {
        heightLE.push_back(h & 0xff);
        h >>= 8;
    }

    std::ostringstream script;
    script << std::hex << std::setfill('0');
    script << std::setw(2) << static_cast<int>(heightLE.size());
    for (uint8_t b : heightLE)
        script << std::setw(2) << static_cast<int>(b);
    script << extraNonceHex;

    std::string scriptHex = script.str();
    tx << std::setw(2) << scriptHex.size() / 2;
    tx << scriptHex;

    tx << "ffffffff"; // sequence
    tx << "01";       // output count

    uint64_t value = 312500000; // 3.125 BTC
    for (int i = 0; i < 8; ++i)
        tx << std::setw(2) << ((value >> (8 * i)) & 0xff);

    std::vector<uint8_t> witnessProgram = bech32Decode(bech32Address);

    tx << "16"; // 22-byte script length
    tx << "0014"; // OP_0 + push(20)
    for (auto b : witnessProgram)
        tx << std::setw(2) << static_cast<int>(b);

    tx << "00000000"; // locktime
    return tx.str();
}
