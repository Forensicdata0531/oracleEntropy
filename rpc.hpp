#pragma once

#include <string>
#include <stdexcept>
#include <iostream>
#include <array>
#include <vector>
#include "nlohmann/json.hpp"

struct TransactionTemplate {
    std::string data;
    std::string txid;
    int fee;
};

struct BlockTemplate {
    int version;
    std::vector<uint8_t> prevBlockHash;   // bytes, big-endian
    std::vector<uint8_t> merkleRoot;      // bytes, big-endian
    uint32_t curtime;
    std::string bits;
    std::vector<TransactionTemplate> transactions;
};

class RpcClient {
public:
    RpcClient(const std::string& url, const std::string& user, const std::string& password)
        : rpcUrl(url), rpcUser(user), rpcPassword(password) {}

    nlohmann::json call(const std::string& method, const nlohmann::json& params = nullptr);
    bool submitblock(const std::string& blockHex);

private:
    std::string rpcUrl;
    std::string rpcUser;
    std::string rpcPassword;

    static size_t writeCallback(void* contents, size_t size, size_t nmemb, std::string* userp);
};

BlockTemplate getBlockTemplate(RpcClient& rpc);
