// sha256.h
#ifndef SHA256_H
#define SHA256_H

#include <cstdint>
#include <cstring>
#include <vector>

void sha256(const unsigned char* data, size_t len, unsigned char* out);

#endif

