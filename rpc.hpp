#pragma once

#include <curl/curl.h>
#include <string>
#include <stdexcept>
#include <iostream>
#include "nlohmann/json.hpp"

class RpcClient {
public:
    RpcClient(const std::string& url, const std::string& user, const std::string& password)
        : rpcUrl(url), rpcUser(user), rpcPassword(password) {}

    // Existing call(...) for any RPC method
    nlohmann::json call(const std::string& method, const nlohmann::json& params = nullptr);

    // New helper: submitblock
    // Returns true if block was accepted (RPC returned null error), false otherwise.
    bool submitblock(const std::string& blockHex);

private:
    std::string rpcUrl;
    std::string rpcUser;
    std::string rpcPassword;

    static size_t writeCallback(void* contents, size_t size, size_t nmemb, std::string* userp);
};
