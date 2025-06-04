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

SDK_PATH=$(xcrun --sdk macosx --show-sdk-path)
CXX=clang++

BASE_CXXFLAGS="-std=c++20 -Wall -Wextra -g -isysroot $SDK_PATH -I."

# ✅ Link with native macOS frameworks (no OpenSSL)
BASE_LDFLAGS="-framework Foundation -framework Metal -lcurses -lcurl"

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
