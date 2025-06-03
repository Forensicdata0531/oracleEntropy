#!/bin/bash
set -e

echo "🛠️  Cleaning previous build..."
rm -rf build
mkdir -p build

echo "🚧 Compiling Metal shader..."
xcrun -sdk macosx metal -c mineKernel.metal -o mineKernel.air
xcrun -sdk macosx metallib mineKernel.air -o mineKernel.metallib
echo "✅ Metal shader compiled successfully."
cp mineKernel.metallib build/

# Optional Homebrew-based prefixes
OPENSSL_PREFIX=$(brew --prefix openssl@3 2>/dev/null || echo "")
BOOST_PREFIX=$(brew --prefix boost 2>/dev/null || echo "")
BITCOIN_PREFIX=$(brew --prefix libbitcoin-system 2>/dev/null || echo "")
CURL_PREFIX=$(brew --prefix curl 2>/dev/null || echo "")
NCURSES_PREFIX=$(brew --prefix ncurses 2>/dev/null || echo "")

SDK_PATH=$(xcrun --sdk macosx --show-sdk-path)
CXX=clang++

BASE_CXXFLAGS="-std=c++20 -Wall -Wextra -g -isysroot $SDK_PATH -I."

# Dynamically add include paths
[[ -n "$OPENSSL_PREFIX" ]]   && BASE_CXXFLAGS+=" -I$OPENSSL_PREFIX/include"
[[ -n "$BOOST_PREFIX" ]]     && BASE_CXXFLAGS+=" -I$BOOST_PREFIX/include"
[[ -n "$BITCOIN_PREFIX" ]]   && BASE_CXXFLAGS+=" -I$BITCOIN_PREFIX/include"
[[ -n "$CURL_PREFIX" ]]      && BASE_CXXFLAGS+=" -I$CURL_PREFIX/include"
[[ -n "$NCURSES_PREFIX" ]]   && BASE_CXXFLAGS+=" -I$NCURSES_PREFIX/include"

BASE_LDFLAGS=""
[[ -n "$OPENSSL_PREFIX" ]]   && BASE_LDFLAGS+=" -L$OPENSSL_PREFIX/lib"
[[ -n "$BOOST_PREFIX" ]]     && BASE_LDFLAGS+=" -L$BOOST_PREFIX/lib"
[[ -n "$BITCOIN_PREFIX" ]]   && BASE_LDFLAGS+=" -L$BITCOIN_PREFIX/lib"
[[ -n "$CURL_PREFIX" ]]      && BASE_LDFLAGS+=" -L$CURL_PREFIX/lib"
[[ -n "$NCURSES_PREFIX" ]]   && BASE_LDFLAGS+=" -L$NCURSES_PREFIX/lib"

BASE_LDFLAGS+=" -lcrypto -lssl"
BASE_LDFLAGS+=" -lbitcoin-system"
BASE_LDFLAGS+=" -lboost_system -lboost_thread -lpthread"
BASE_LDFLAGS+=" -lcurl -lncurses"
BASE_LDFLAGS+=" -framework Metal -framework Foundation"

OPT_FLAGS="-O3 -march=native"

echo "🔧 Compiling source files..."
$CXX $BASE_CXXFLAGS -c utils.cpp -o build/utils.o
$CXX $BASE_CXXFLAGS -c rpc.cpp -o build/rpc.o
$CXX $BASE_CXXFLAGS -c sha256_compress.cpp -o build/sha256_compress.o
$CXX $BASE_CXXFLAGS -c block_utils.cpp -o build/block_utils.o
$CXX $BASE_CXXFLAGS -c metal_miner.mm -o build/metal_miner.o
$CXX $BASE_CXXFLAGS -c metal_ui.cpp -o build/metal_ui.o
$CXX $BASE_CXXFLAGS -c metal_ui.mm -o build/metal_ui_mm.o
$CXX $BASE_CXXFLAGS $OPT_FLAGS -c main.cpp -o build/main.o

echo "🧩 Linking..."
$CXX build/*.o $BASE_LDFLAGS -o ./MetalMiner

echo "✅ Build complete."
