#!/bin/bash
# Builds llama.cpp's static libraries for CraInferenceHelper: native CPU
# (AVX2/FMA on Intel), Accelerate for BLAS, Metal off, no network (CURL off).
#
# The deployment target matches the app (Package.swift: macOS 14), so the helper
# never requires a newer macOS than the bundle that ships it.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="$PWD/vendor/llama.cpp"
BUILD="$SRC/build"
TARGET="${MACOSX_DEPLOYMENT_TARGET:-14.0}"
ARCH="${BUILD_ARCH:-$(uname -m)}"
# Cross-compiling (the CI Intel job on an arm runner) cannot use -march=native.
CROSS="$([ "$ARCH" = "$(uname -m)" ] && echo off || echo on)"

[ -f "$SRC/CMakeLists.txt" ] || { echo "vendor/llama.cpp is missing" >&2; exit 1; }

cmake -S "$SRC" -B "$BUILD" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$TARGET" \
  -DGGML_NATIVE=$([ "$CROSS" = on ] && echo OFF || echo ON) \
  -DGGML_AVX2=$([ "$CROSS" = on ] && echo ON || echo OFF) \
  -DGGML_FMA=$([ "$CROSS" = on ] && echo ON || echo OFF) \
  -DGGML_F16C=$([ "$CROSS" = on ] && echo ON || echo OFF) \
  -DGGML_METAL=OFF \
  # GitHub 的 macOS runner（Xcode 16 + Accelerate 头文件）在 ARM 原生构建时会因
  # i8mm 特性标志缺失而编译失败（vmmlaq_s32 always_inline）——CI 侧关掉 BLAS，
  # 本地 Intel 构建保持 ON（性能优化，引擎不受影响，都是 CPU 推理）。
  -DGGML_BLAS=$([ "${LLAMA_NO_BLAS:-0}" = 1 ] && echo OFF || echo ON) \
  -DGGML_BLAS_VENDOR=$([ "${LLAMA_NO_BLAS:-0}" = 1 ] && echo "n/a" || echo Apple) \
  -DLLAMA_CURL=OFF \
  -DLLAMA_BUILD_TESTS=OFF \
  -DLLAMA_BUILD_EXAMPLES=OFF \
  -DLLAMA_BUILD_TOOLS=OFF \
  -DBUILD_SHARED_LIBS=OFF

cmake --build "$BUILD" -j"$(sysctl -n hw.ncpu)" --target llama

LIBS=(
  "$BUILD/src/libllama.a"
  "$BUILD/ggml/src/libggml.a"
  "$BUILD/ggml/src/libggml-base.a"
  "$BUILD/ggml/src/libggml-cpu.a"
  "$BUILD/ggml/src/ggml-blas/libggml-blas.a"
)
# otool writes into a file: awk exits after the first match, and with pipefail the
# resulting SIGPIPE would fail the script. A static archive carries one
# LC_BUILD_VERSION per object file; the first is enough.
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
for lib in "${LIBS[@]}"; do
  [ -f "$lib" ] || { echo "missing $lib" >&2; exit 1; }
  otool -l "$lib" > "$TMP"
  minos=$(awk '/LC_BUILD_VERSION/{found=1} found && $1=="minos"{print $2; exit}' "$TMP")
  echo "$(basename "$lib"): minos ${minos:-unknown}"
  [ "${minos%%.*}" = "${TARGET%%.*}" ] || { echo "expected minos $TARGET" >&2; exit 1; }
done
