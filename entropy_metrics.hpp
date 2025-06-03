#pragma once

#include <cstdint>
#include <vector>

// Calculate entropy metrics and related helper functions for mining entropy evaluation

// Calculate SHA256 midstate (first compression stage) from block header prefix (64 bytes)
std::vector<uint8_t> calculateSHA256Midstate(const std::vector<uint8_t>& headerPrefix);

// Extract the entropy bits from SHA256 midstate or hash result
double entropyMetric(const std::vector<uint8_t>& data);

// Additional entropy-based metrics (placeholder for more complex analysis)
double blockEntropyScore(uint64_t nonce);

