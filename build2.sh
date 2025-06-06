#!/bin/bash
set -e

echo "🔧 Building midstate tester..."

OPENSSL_LIB_DIR=$(brew --prefix openssl)/lib
OPENSSL_INCLUDE_DIR=$(brew --prefix openssl)/include
SDK_PATH=$(xcrun --sdk macosx --show-sdk-path)
CXX=clang++

INCLUDE_FLAGS="-I. -I./oracle -I/opt/homebrew/include -I$OPENSSL_INCLUDE_DIR"
CXXFLAGS="-std=c++20 -Wall -Wextra -O2 -isysroot $SDK_PATH $INCLUDE_FLAGS"
LDFLAGS="-L$OPENSSL_LIB_DIR -lssl -lcrypto"

# Removed sha256_utils.cpp to avoid duplicate symbol 'sha256' linker error
$CXX $CXXFLAGS test_midstate.cpp sha256_wrapper.cpp sha256_compress.cpp -o test_midstate $LDFLAGS

echo "✅ test_midstate built."
./test_midstate
