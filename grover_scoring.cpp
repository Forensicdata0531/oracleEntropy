#include "grover_scoring.h"

float score_midstate(const Midstate& m) {
    // TODO: Replace with real scoring based on Grover-style interference
    float score = 0.0f;
    for (int i = 0; i < 8; ++i) {
        score += m.h[i] % 17;  // dummy scoring
    }
    return score;
}

