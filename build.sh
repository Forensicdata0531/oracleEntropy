#!/bin/bash
set -e

echo "🛠️  Cleaning previous build..."
rm -rf build
mkdir -p build

echo "🚧 Compiling Metal shader..."
xcrun -sdk macosx metal -c mineKernel.metal -o build/mineKernel.air
xcrun -sdk macosx metallib build/mineKernel.air -o build/mineKernel.metallib
echo "✅ Metal shader compiled successfully."

OPENSSL_LIB_DIR=$(brew --prefix openssl)/lib
OPENSSL_INCLUDE_DIR=$(brew --prefix openssl)/include
SDK_PATH=$(xcrun --sdk macosx --show-sdk-path)
CXX=clang++
OBJCXX=clang++

INCLUDE_FLAGS="-I. -I./oracle -I/opt/homebrew/include -I$OPENSSL_INCLUDE_DIR"
BASE_CXXFLAGS="-std=c++20 -Wall -Wextra -Wno-deprecated-declarations -Wno-unused-variable -Wno-unused-parameter -g -isysroot $SDK_PATH $INCLUDE_FLAGS"
BASE_LDFLAGS="-L$OPENSSL_LIB_DIR -lssl -lcrypto -framework Foundation -framework Metal -framework CoreML -lcurses -lcurl"

echo "🔧 Compiling shared source files..."
$CXX    $BASE_CXXFLAGS -c utils.cpp             -o build/utils.o
$CXX    $BASE_CXXFLAGS -c rpc.cpp               -o build/rpc.o
$CXX    $BASE_CXXFLAGS -c sha256_compress.cpp   -o build/sha256_compress.o
$CXX    $BASE_CXXFLAGS -c sha256_wrapper.cpp    -o build/sha256_wrapper.o       # <<< Added this line
$CXX    $BASE_CXXFLAGS -c block_utils.cpp       -o build/block_utils.o
$CXX    $BASE_CXXFLAGS -c midstate.cpp          -o build/midstate.o
$CXX    $BASE_CXXFLAGS -c block.cpp             -o build/block.o

$OBJCXX $BASE_CXXFLAGS -ObjC++ -c metal_miner.mm -o build/metal_miner.o
$CXX    $BASE_CXXFLAGS -c metal_ui.cpp          -o build/metal_ui.o
$OBJCXX $BASE_CXXFLAGS -ObjC++ -c metal_ui.mm   -o build/metal_ui_mm.o
$CXX    $BASE_CXXFLAGS -c main.cpp              -o build/main.o

echo "🧩 Linking full MetalMiner executable..."
$OBJCXX build/main.o build/utils.o build/rpc.o build/sha256_compress.o build/sha256_wrapper.o build/block_utils.o build/midstate.o build/block.o \
        build/metal_miner.o build/metal_ui.o build/metal_ui_mm.o \
        $BASE_LDFLAGS -o MetalMiner
echo "✅ Build complete for MetalMiner."
