#ifndef MIDSTATE_UTILS_HPP
#define MIDSTATE_UTILS_HPP

#include <array>
#include <cstdint>
#include <vector>

struct Midstate {
    std::array<uint32_t, 8> h;
};

Midstate calculateMidstateFromHeader(const std::vector<uint8_t>& header);

#endif // MIDSTATE_UTILS_HPP
