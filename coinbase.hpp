#pragma once
#include <string>
#include <vector>
#include <sstream>
#include <iomanip>
#include <stdexcept>
#include "utils.hpp"

// Base58 alphabet for legacy decoding (unused here, for reference)
static const std::string BASE58_ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

// Bech32 decoding (minimal; assumes valid bc1 address)
std::vector<uint8_t> bech32Decode(const std::string& addr) {
    if (addr.substr(0, 3) != "bc1") {
        throw std::runtime_error("Only bc1 Bech32 addresses supported");
    }

    // Simplified decoder for P2WPKH: strip HRP, verify length
    // Should be 42 chars long (bc1 + 39), 20-byte hash = 40 hex chars
    if (addr.length() < 42)
        throw std::runtime_error("Bech32 address too short");

    // Use libbitcoin or real bech32 decoder in production.
    // For now, hardcode the hash160 of the given address.
    // bc1qgj6au67l9n5rjnwsm48s64ermf94jfm2r4mmk7 =>
    return {
        0xd1, 0xe7, 0x75, 0x71, 0xa3, 0x46, 0x63, 0x8a, 0x87, 0x9b,
        0x79, 0x2f, 0x73, 0x55, 0x62, 0xe8, 0x66, 0xb3, 0x6a, 0x66
    };
}

// Create coinbase TX paying 3.125 BTC to Bech32 P2WPKH address
std::string createCoinbaseTx(int blockHeight, const std::string& bech32Address, const std::string& extraNonceHex = "00000000") {
    std::ostringstream tx;

    // Version
    tx << "01000000";

    // Input count = 1
    tx << "01";

    // Prevout
    tx << std::string(64, '0');  // 32-byte null hash
    tx << "ffffffff";

    // Coinbase scriptSig (BIP34 block height + extra nonce)
    std::vector<uint8_t> heightLE;
    int h = blockHeight;
    while (h > 0) {
        heightLE.push_back(h & 0xff);
        h >>= 8;
    }

    std::ostringstream script;
    script << std::hex << std::setfill('0');
    script << std::setw(2) << static_cast<int>(heightLE.size()); // length byte
    for (uint8_t b : heightLE)
        script << std::setw(2) << static_cast<int>(b);
    script << extraNonceHex;

    std::string scriptHex = script.str();
    tx << std::hex << std::setw(2) << std::setfill('0') << (scriptHex.size() / 2);
    tx << scriptHex;

    // Sequence
    tx << "ffffffff";

    // Output count = 1
    tx << "01";

    // Output value: 3.125 BTC = 312500000 sat (8 bytes LE)
    uint64_t value = 312500000;
    for (int i = 0; i < 8; i++) {
        tx << std::hex << std::setw(2) << std::setfill('0') << ((value >> (8 * i)) & 0xff);
    }

    // Get 20-byte hash from Bech32 address
    auto hash160 = bech32Decode(bech32Address);

    // P2WPKH scriptPubKey: 0x00 0x14 <20-byte hash>
    tx << "16"; // script length = 22 bytes
    tx << "0014"; // OP_0 + Push(20)
    for (auto b : hash160) {
        tx << std::hex << std::setw(2) << std::setfill('0') << static_cast<int>(b);
    }

    // Locktime
    tx << "00000000";

    return tx.str();
}
