#include "rpc.hpp"
#include <curl/curl.h>
#include <stdexcept>
#include <iostream>

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
        json response = json::parse(readBuffer);
        return response;
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
        if (response.contains("error") && response["error"].is_null()) {
            return true;
        }
        return false;
    } catch (const json::parse_error& e) {
        throw std::runtime_error(std::string("Failed to parse JSON response: ") + e.what());
    }
}
