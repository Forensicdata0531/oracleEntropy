#include "rpc.hpp"
#include <curl/curl.h>
#include <stdexcept>
#include <iostream>
#include <algorithm>
#include "utils.hpp"         // For logLine, hexToBytes
#include "sha256_utils.hpp"  // For sha256Double

static void logLine(const std::string& line) {
    std::cerr << line << std::endl;
}

using json = nlohmann::json;

size_t RpcClient::writeCallback(void* contents, size_t size, size_t nmemb, std::string* userp) {
    size_t realSize = size * nmemb;
    userp->append(static_cast<char*>(contents), realSize);
    return realSize;
}

json RpcClient::call(const std::string& method, const json& params) {
    CURL* curl = curl_easy_init();
    if (!curl) throw std::runtime_error("Failed to initialize curl");

    json requestJson = {
        {"jsonrpc", "1.0"},
        {"id", "miner"},
        {"method", method},
        {"params", params.is_null() ? json::array() : params}
    };

    std::string requestStr = requestJson.dump();
    std::string readBuffer;

    struct curl_slist* headers = nullptr;
    headers = curl_slist_append(headers, "Content-Type: application/json");
    std::string authString = rpcUser + ":" + rpcPassword;

    curl_easy_setopt(curl, CURLOPT_URL, rpcUrl.c_str());
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, requestStr.c_str());
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, RpcClient::writeCallback);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &readBuffer);
    curl_easy_setopt(curl, CURLOPT_USERPWD, authString.c_str());

    CURLcode res = curl_easy_perform(curl);
    if (res != CURLE_OK) {
        curl_easy_cleanup(curl);
        throw std::runtime_error(std::string("Curl failed: ") + curl_easy_strerror(res));
    }

    curl_easy_cleanup(curl);

    try {
        return json::parse(readBuffer);
    } catch (const json::parse_error& e) {
        throw std::runtime_error(std::string("Failed to parse JSON response: ") + e.what());
    }
}

bool RpcClient::submitblock(const std::string& blockHex) {
    json requestJson = {
        {"jsonrpc", "1.0"},
        {"id", "submit"},
        {"method", "submitblock"},
        {"params", {blockHex}}
    };

    std::string requestStr = requestJson.dump();
    std::string readBuffer;

    CURL* curl = curl_easy_init();
    if (!curl) throw std::runtime_error("Failed to initialize curl");

    struct curl_slist* headers = nullptr;
    headers = curl_slist_append(headers, "Content-Type: application/json");
    std::string authString = rpcUser + ":" + rpcPassword;

    curl_easy_setopt(curl, CURLOPT_URL, rpcUrl.c_str());
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, requestStr.c_str());
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, RpcClient::writeCallback);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &readBuffer);
    curl_easy_setopt(curl, CURLOPT_USERPWD, authString.c_str());

    CURLcode res = curl_easy_perform(curl);
    if (res != CURLE_OK) {
        curl_easy_cleanup(curl);
        throw std::runtime_error(std::string("Curl failed: ") + curl_easy_strerror(res));
    }

    curl_easy_cleanup(curl);

    try {
        json response = json::parse(readBuffer);
        if (response.contains("error") && !response["error"].is_null()) {
            if (response["error"].is_object()) {
                logLine("[RPC Submitblock Error]: " + response["error"].value("message", "Unknown error"));
            } else if (response["error"].is_string()) {
                logLine("[RPC Submitblock Error]: " + response["error"].get<std::string>());
            } else {
                logLine("[RPC Submitblock Error]: Unknown error format");
            }
            return false;
        }
        return true;
    } catch (const json::parse_error& e) {
        throw std::runtime_error(std::string("Failed to parse JSON response: ") + e.what());
    }
}

// Build Merkle Tree and return full tree (last element is Merkle root)
static std::vector<std::string> buildMerkleTree(const std::vector<std::string>& txids) {
    if (txids.empty()) return {};

    std::vector<std::string> tree = txids;
    size_t offset = 0;

    while (tree.size() - offset > 1) {
        size_t count = tree.size() - offset;
        size_t pairs = (count + 1) / 2;
        for (size_t i = 0; i < pairs; i++) {
            size_t idx1 = offset + i * 2;
            size_t idx2 = (idx1 + 1 < tree.size()) ? idx1 + 1 : idx1;

            std::string left = tree[idx1];
            std::string right = tree[idx2];

            std::vector<uint8_t> leftBytes = hexToBytes(left);
            std::vector<uint8_t> rightBytes = hexToBytes(right);

            std::vector<uint8_t> concatBytes;
            concatBytes.reserve(leftBytes.size() + rightBytes.size());
            concatBytes.insert(concatBytes.end(), leftBytes.begin(), leftBytes.end());
            concatBytes.insert(concatBytes.end(), rightBytes.begin(), rightBytes.end());

            std::vector<uint8_t> hashBytes = sha256Double(concatBytes);

            std::string hashHex;
            for (auto b : hashBytes) {
                char buf[3];
                snprintf(buf, sizeof(buf), "%02x", b);
                hashHex += buf;
            }
            tree.push_back(hashHex);
        }
        offset += count;
    }
    return tree;
}

BlockTemplate getBlockTemplate(RpcClient& rpc) {
    json res = rpc.call("getblocktemplate", {{{"rules", {"segwit"}}}});
    if (!res.contains("result") || res["result"].is_null())
        throw std::runtime_error("Invalid block template: missing 'result'");

    auto tplJson = res["result"];

    BlockTemplate tpl;

    tpl.version = tplJson["version"].get<int>();
    tpl.curtime = tplJson["curtime"].get<uint32_t>();
    tpl.bits = tplJson["bits"].get<std::string>();
    tpl.prevBlockHash = hexToBytes(tplJson["previousblockhash"].get<std::string>());

    tpl.transactions.clear();
    std::vector<std::string> txids;
    for (auto& tx : tplJson["transactions"]) {
        TransactionTemplate t;
        t.data = tx["data"].get<std::string>();
        t.txid = tx["txid"].get<std::string>();
        t.fee = tx["fee"].get<int>();
        tpl.transactions.push_back(t);
        txids.push_back(t.txid);
    }

    auto merkleTree = buildMerkleTree(txids);
    if (merkleTree.empty())
        throw std::runtime_error("Failed to build Merkle tree");

    tpl.merkleRoot = hexToBytes(merkleTree.back());

    return tpl;
}
