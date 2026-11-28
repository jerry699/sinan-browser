#!/bin/bash
# Builds whisper.cpp's static libraries for CraWhisper: native CPU (AVX2/FMA on
# Intel), Accelerate for BLAS, Metal off (the Radeon crashes in llama_decode and
# was 7-13x slower — the doc measured it for llama.cpp, whisper inherits it), no
# examples/tests/server (CraWhisper is the only consumer). Same macOS 14 floor as
# the app. Output: vendor/whisper.cpp/build/{src,ggml/src}/*.a, read by Package.swift.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="$PWD/vendor/whisper.cpp"
BUILD="$SRC/build"
TARGET="${MACOSX_DEPLOYMENT_TARGET:-14.0}"
ARCH="${BUILD_ARCH:-$(uname -m)}"
# Cross-compiling (the CI Intel job on an arm runner) cannot use -march=native.
CROSS="$([ "$ARCH" = "$(uname -m)" ] && echo off || echo on)"

[ -f "$SRC/CMakeLists.txt" ] || { echo "vendor/whisper.cpp is missing" >&2; exit 1; }

# 交叉时钉目标架构（同 build-llama.sh）：ggml 按 CMAKE_SYSTEM_PROCESSOR（= runner
# 本机架构）选旗标，arm runner 会给 x86_64 目标塞 -mcpu=apple-m3 → clang 拒绝。
EXTRA_CMAKE=()
if [ "$CROSS" = on ]; then EXTRA_CMAKE=(-DCMAKE_SYSTEM_PROCESSOR="$ARCH"); fi
cmake -S "$SRC" -B "$BUILD" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$TARGET" \
  -DWHISPER_BUILD_EXAMPLES=OFF \
  -DWHISPER_BUILD_TESTS=OFF \
  -DWHISPER_BUILD_SERVER=OFF \
  -DGGML_METAL=OFF \
  -DGGML_NATIVE=$([ "$CROSS" = on ] && echo OFF || echo ON) \
  -DBUILD_SHARED_LIBS=OFF \
  -DLLAMA_BUILD_COMMON=OFF \
  -Wno-dev \
  ${EXTRA_CMAKE[@]+"${EXTRA_CMAKE[@]}"}
cmake --build "$BUILD" --config Release -j "$(sysctl -n hw.ncpu)"
ls -la "$BUILD/src/libwhisper.a"
