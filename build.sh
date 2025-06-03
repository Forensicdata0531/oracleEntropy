#!/bin/bash
set -e

echo "🛠️  Cleaning previous build..."
rm -rf build
mkdir -p build

echo "🚧 Compiling Metal shader..."
if ! xcrun -sdk macosx metal -o mineKernel.metallib mineKernel.metal; then
  echo "⚠️  No Metal shader found, skipping."
fi

OPENSSL_PREFIX=$(brew --prefix openssl@3 2>/dev/null || echo "")
BOOST_PREFIX="/usr/local"
BITCOIN_PREFIX=$(brew --prefix libbitcoin-system 2>/dev/null || echo "/usr/local")
CURL_PREFIX=$(brew --prefix curl 2>/dev/null || echo "")

SDK_PATH=$(xcrun --sdk macosx --show-sdk-path)

CXX=clang++

BASE_CXXFLAGS="-std=c++20 -Wall -Wextra -g -isysroot $SDK_PATH \
  -I. \
  ${OPENSSL_PREFIX:+-I${OPENSSL_PREFIX}/include} \
  ${BOOST_PREFIX:+-I${BOOST_PREFIX}/include} \
  ${BITCOIN_PREFIX:+-I${BITCOIN_PREFIX}/include} \
  ${CURL_PREFIX:+-I${CURL_PREFIX}/include}"

BASE_LDFLAGS="${OPENSSL_PREFIX:+-L${OPENSSL_PREFIX}/lib} \
  ${BOOST_PREFIX:+-L${BOOST_PREFIX}/lib} \
  ${BITCOIN_PREFIX:+-L${BITCOIN_PREFIX}/lib} \
  ${CURL_PREFIX:+-L${CURL_PREFIX}/lib} \
  -lcrypto -lssl \
  -lbitcoin-system \
  -lboost_system -lboost_thread -lpthread \
  -lcurl \
  -framework Metal -framework Foundation"

OPT_FLAGS="-O3 -march=native"

echo "🔧 Compiling source files..."

$CXX $BASE_CXXFLAGS -c utils.cpp -o build/utils.o
$CXX $BASE_CXXFLAGS -c oracle_dispatcher.cpp -o build/oracle_dispatcher.o
$CXX $BASE_CXXFLAGS -c entropy_metrics.cpp -o build/entropy_metrics.o

# Compile sha256_wrapper.cpp using OpenSSL version
$CXX $BASE_CXXFLAGS -c sha256_wrapper.cpp -o build/sha256_wrapper.o

# Compile your new sha256_compress.cpp and midstate_utils.cpp files
$CXX $BASE_CXXFLAGS $OPT_FLAGS -c sha256_compress.cpp -o build/sha256_compress.o
$CXX $BASE_CXXFLAGS $OPT_FLAGS -c midstate_utils.cpp -o build/midstate_utils.o

$CXX $BASE_CXXFLAGS -c rpc.cpp -o build/rpc.o
$CXX $BASE_CXXFLAGS -c metal_miner.mm -o build/metal_miner.o

$CXX ${BASE_CXXFLAGS} $OPT_FLAGS -c main.cpp -o build/main.o

echo "🧩 Linking..."
$CXX build/*.o $BASE_LDFLAGS -o build/quantum_miner

echo "✅ Build complete."
