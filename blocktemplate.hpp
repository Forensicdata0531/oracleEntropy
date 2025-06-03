#pragma once
#include <string>
#include <vector>
#include <iostream>
#include <stdexcept>
#include "nlohmann/json.hpp"
#include "utils.hpp"

struct TransactionTemplate {
    std::string data;
    std::string txid;
    int fee;
};

struct BlockTemplate {
    int version;
    std::vector<uint8_t> prevBlockHash;   // bytes, big-endian from hex
    std::string coinbaseAddress;
    std::vector<TransactionTemplate> transactions;
    uint64_t coinbaseValue;
    std::string bits;                      // hex string
    std::string target;                    // hex string (optional validation)
    uint32_t curtime;
    int height;

    static BlockTemplate from_json(const nlohmann::json& j) {
        BlockTemplate bt;

        if (!j.contains("version") || !j["version"].is_number_integer())
            throw std::runtime_error("Missing or invalid 'version' in JSON: " + j.dump());

        bt.version = j["version"].get<int>();

        if (!j.contains("previousblockhash") || !j["previousblockhash"].is_string())
            throw std::runtime_error("Missing or invalid 'previousblockhash'");

        std::string prevHashHex = j["previousblockhash"].get<std::string>();
        bt.prevBlockHash = hexToBytes(prevHashHex);
        if (bt.prevBlockHash.size() != 32)
            throw std::runtime_error("previousBlockHash decoded length is not 32 bytes.");

        if (!j.contains("coinbaseaddress") || !j["coinbaseaddress"].is_string())
            throw std::runtime_error("Missing or invalid 'coinbaseaddress'");

        bt.coinbaseAddress = j["coinbaseaddress"].get<std::string>();

        if (!j.contains("coinbasevalue") || !j["coinbasevalue"].is_number_unsigned())
            throw std::runtime_error("Missing or invalid 'coinbasevalue'");

        bt.coinbaseValue = j["coinbasevalue"].get<uint64_t>();

        if (!j.contains("bits") || !j["bits"].is_string())
            throw std::runtime_error("Missing or invalid 'bits'");

        bt.bits = j["bits"].get<std::string>();

        if (!j.contains("target") || !j["target"].is_string())
            throw std::runtime_error("Missing or invalid 'target'");

        bt.target = j["target"].get<std::string>();

        if (!j.contains("curtime") || !j["curtime"].is_number_unsigned())
            throw std::runtime_error("Missing or invalid 'curtime'");

        bt.curtime = j["curtime"].get<uint32_t>();

        if (!j.contains("height") || !j["height"].is_number_integer())
            throw std::runtime_error("Missing or invalid 'height'");

        bt.height = j["height"].get<int>();

        if (!j.contains("transactions") || !j["transactions"].is_array())
            throw std::runtime_error("Missing or invalid 'transactions'");

        for (const auto& tx : j["transactions"]) {
            if (!tx.contains("data") || !tx["data"].is_string())
                throw std::runtime_error("Invalid or missing 'data' in transaction");

            if (!tx.contains("txid") || !tx["txid"].is_string())
                throw std::runtime_error("Invalid or missing 'txid' in transaction");

            if (!tx.contains("fee") || !tx["fee"].is_number_integer())
                throw std::runtime_error("Invalid or missing 'fee' in transaction");

            TransactionTemplate t;
            t.data = tx["data"].get<std::string>();
            t.txid = tx["txid"].get<std::string>();
            t.fee = tx["fee"].get<int>();

            bt.transactions.push_back(t);
        }

        return bt;
    }
};
