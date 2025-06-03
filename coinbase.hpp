#pragma once
#include <string>
#include <vector>
#include <sstream>
#include <iomanip>
#include <stdexcept>
#include "utils.hpp"
#include <bitcoin/system.hpp>  // libbitcoin include

// Alias for easier use
namespace lsys = libbitcoin::system;

// Create coinbase TX paying 3.125 BTC to legacy address (P2PKH)
std::string createCoinbaseTx(int blockHeight, const std::string& address, const std::string& extraNonceHex = "00000000") {
    std::ostringstream tx;

    // Version (4 bytes little endian)
    tx << "01000000";

    // Input count = 1
    tx << "01";

    // Previous output (null prevout)
    tx << std::string(64, '0');  // 32-byte zero hash (hex)
    tx << "ffffffff";            // output index: 0xffffffff

    // Coinbase script: block height + extra nonce
    // Script size variable; height encoding according to BIP34
    if (blockHeight < 17) {
        // Push block height in minimal bytes
        tx << "03"; // script length 3 bytes
        tx << std::hex << std::setw(2) << std::setfill('0') << blockHeight;
        tx << extraNonceHex;  // extra nonce appended
    } else {
        throw std::runtime_error("Block height encoding > 16 not implemented");
    }

    // Sequence
    tx << "ffffffff";

    // Output count = 1
    tx << "01";

    // Output value = 3.125 BTC = 312500000 satoshis (8 bytes little endian)
    uint64_t value = 312500000;
    for (int i = 0; i < 8; i++) {
        tx << std::hex << std::setw(2) << std::setfill('0') << ((value >> (8*i)) & 0xff);
    }

    // Output scriptPubKey (P2PKH) - base58 decode address to hash160
    auto addr = lsys::wallet::payment_address(address);
    auto hash160 = addr.hash();

    // Script length = 25 bytes (P2PKH)
    tx << "19";

    // ScriptPubKey = OP_DUP OP_HASH160 PushBytes(20) hash160 OP_EQUALVERIFY OP_CHECKSIG
    tx << "76a914";
    for (auto byte : hash160) {
        tx << std::hex << std::setw(2) << std::setfill('0') << (int)byte;
    }
    tx << "88ac";

    // Locktime
    tx << "00000000";

    return tx.str();
}
