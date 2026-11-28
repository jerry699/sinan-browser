#!/bin/bash
# Builds llama.cpp's static libraries for CraInferenceHelper: native CPU
# (AVX2/FMA on Intel), Accelerate for BLAS, Metal off, no network (CURL off).
#
# The deployment target matches the app (Package.swift: macOS 14), so the helper
# never requires a newer macOS than the bundle that ships it.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="$PWD/vendor/llama.cpp"
TARGET="${MACOSX_DEPLOYMENT_TARGET:-14.0}"
ARCH="${BUILD_ARCH:-$(uname -m)}"
BUILD="$SRC/build$([ "$ARCH" = "$(uname -m)" ] && echo "" || echo "-$ARCH")"
# Cross-compiling (the CI Intel job on an arm runner) cannot use -march=native.
CROSS="$([ "$ARCH" = "$(uname -m)" ] && echo off || echo on)"

[ -f "$SRC/CMakeLists.txt" ] || { echo "vendor/llama.cpp is missing" >&2; exit 1; }

# GitHub 的 macOS runner（Xcode 16 + Accelerate 头文件）在 ARM 原生构建时会因
# i8mm 特性标志缺失而编译失败（vmmlaq_s32 always_inline）——CI 侧 LLAMA_NO_BLAS=1
# 关掉 BLAS；本地 Intel 构建保持 ON（性能优化，都是 CPU 推理）。注释不得插进
# 反斜杠续行链中间：续行遇到 # 会吞掉整条逻辑命令的剩余部分。
# 交叉编译时 ggml-cpu 的 cmake 按 CMAKE_SYSTEM_PROCESSOR（= runner 本机架构）选
# 架构旗标：arm runner 上会给 x86_64 目标塞 -mcpu=apple-m3 → clang 直接拒绝。
# 钉成目标架构，ggml 的 ARM -mcpu 探测才会跳过（走下面显式的 AVX2/FMA/F16C）。
EXTRA_CMAKE=()
if [ "$CROSS" = on ]; then
  EXTRA_CMAKE=(-DCMAKE_SYSTEM_PROCESSOR="$ARCH")
elif [ "$ARCH" = arm64 ]; then
  # ARM 原生（CI runner）：ggml 的 -mcpu=native 探针在 Apple clang 新版下提取不到
  # 具体旗标，回退 native —— TU 级 __ARM_FEATURE_MATMUL_INT8 与 dot 函数的
  # target 属性失配，vmmlaq_s32 always_inline 编译报错。钉 apple-m2：M1/M2/M3
  # 都有 i8mm，特征检查与编译一致。
  EXTRA_CMAKE=(-DGGML_CPU_ARM_ARCH=apple-m2)
fi
cmake -S "$SRC" -B "$BUILD" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
  ${EXTRA_CMAKE[@]+"${EXTRA_CMAKE[@]}"} \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$TARGET" \
  -DGGML_NATIVE=$([ "$CROSS" = on ] && echo OFF || echo ON) \
  -DGGML_AVX2=$([ "$CROSS" = on ] && echo ON || echo OFF) \
  -DGGML_FMA=$([ "$CROSS" = on ] && echo ON || echo OFF) \
  -DGGML_F16C=$([ "$CROSS" = on ] && echo ON || echo OFF) \
  -DGGML_METAL=OFF \
  -DGGML_BLAS=$([ "${LLAMA_NO_BLAS:-0}" = 1 ] && echo OFF || echo ON) \
  -DGGML_BLAS_VENDOR=$([ "${LLAMA_NO_BLAS:-0}" = 1 ] && echo n/a || echo Apple) \
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
)
# LLAMA_NO_BLAS=1（CI 的 ARM 原生档）不产 ggml-blas，链接清单里也就没有它。
if [ "${LLAMA_NO_BLAS:-0}" != 1 ]; then LIBS+=("$BUILD/ggml/src/ggml-blas/libggml-blas.a"); fi
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
