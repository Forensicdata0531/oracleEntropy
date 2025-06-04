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

OPENSSL_LIB_DIR=$(brew --prefix openssl)/lib
OPENSSL_INCLUDE_DIR=$(brew --prefix openssl)/include

SDK_PATH=$(xcrun --sdk macosx --show-sdk-path)
CXX=clang++
OBJCXX=clang++

INCLUDE_FLAGS="-I. -I/opt/homebrew/include -I$OPENSSL_INCLUDE_DIR"
BASE_CXXFLAGS="-std=c++20 -Wall -Wextra -g -isysroot $SDK_PATH $INCLUDE_FLAGS"

BASE_LDFLAGS="-L$OPENSSL_LIB_DIR -lssl -lcrypto -framework Foundation -framework Metal -lcurses -lcurl"
OPT_FLAGS="-O3 -march=native"

echo "🔧 Compiling source files..."
$CXX $BASE_CXXFLAGS -c utils.cpp -o build/utils.o
$CXX $BASE_CXXFLAGS -c rpc.cpp -o build/rpc.o
$CXX $BASE_CXXFLAGS -c sha256_compress.cpp -o build/sha256_compress.o
$CXX $BASE_CXXFLAGS -c block_utils.cpp -o build/block_utils.o
$OBJCXX $BASE_CXXFLAGS -ObjC++ -c metal_miner.mm -o build/metal_miner.o
$CXX $BASE_CXXFLAGS -c metal_ui.cpp -o build/metal_ui.o
$OBJCXX $BASE_CXXFLAGS -ObjC++ -c metal_ui.mm -o build/metal_ui_mm.o
$CXX $BASE_CXXFLAGS -c main.cpp -o build/main.o

$CXX $BASE_CXXFLAGS -c oracle/sha256_wrapper.cpp -o build/sha256_wrapper.o
$CXX $BASE_CXXFLAGS -c oracle/entropy_metrics.cpp -o build/entropy_metrics.o
$CXX $BASE_CXXFLAGS -c oracle/oracle_dispatcher.cpp -o build/oracle_dispatcher.o
$CXX $BASE_CXXFLAGS -c oracle/oracle_table.cpp -o build/oracle_table.o

echo "🧩 Linking full miner..."
$CXX build/utils.o build/rpc.o build/sha256_compress.o build/block_utils.o build/metal_miner.o build/metal_ui.o build/metal_ui_mm.o build/main.o \
build/sha256_wrapper.o build/entropy_metrics.o build/oracle_table.o \
$BASE_LDFLAGS -o ./MetalMiner
echo "✅ Build complete for MetalMiner."

echo "📦 Building oracle_dispatcher tool..."
$CXX build/oracle_dispatcher.o build/entropy_metrics.o build/sha256_wrapper.o build/oracle_table.o \
$BASE_LDFLAGS -o oracle/oracle_dispatcher
echo "✅ oracle_dispatcher built successfully."

echo "🔨 Building build_midstates tool..."
clang++ -std=c++20 -I. -I/opt/homebrew/include -L$OPENSSL_LIB_DIR -lssl -lcrypto oracle/build_midstates.cpp -o oracle/build_midstates
echo "✅ build_midstates built successfully."
