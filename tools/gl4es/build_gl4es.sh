#!/usr/bin/env bash
# Build gl4es (libGL.so.1) for aarch64 Ubuntu Touch (Halium 12, Mali-G57).
# Produces overlay/system/usr/local/lib/gl4es/libGL.so.1 wired to libhybris GLVND EGL/GLESv2.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC_DIR="${GL4ES_SRC:-$ROOT/build-workspace/gl4es}"
OUT_DIR="$ROOT/overlay/system/usr/local/lib/gl4es"

if [ ! -d "$SRC_DIR/.git" ]; then
    mkdir -p "$(dirname "$SRC_DIR")"
    git clone --depth 1 https://github.com/ptitSeb/gl4es.git "$SRC_DIR"
fi

BUILD_DIR="$SRC_DIR/build"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

CMAKE_EXTRA=()
CFLAGS="-O3 -DLIBGL_FB=3 -Wno-date-time -Wno-pointer-sign -Wno-dangling-else -Wno-implicit-const-int-float-conversion"

if [ "$(uname -m)" != "aarch64" ]; then
    if command -v zig >/dev/null 2>&1; then
        WRAPPER="$(mktemp /tmp/zig-aarch64-cc.XXXXXX.sh)"
        INC_DIR="$(mktemp -d /tmp/gl4es-inc.XXXXXX)"
        trap 'rm -rf "$WRAPPER" "$INC_DIR"' EXIT
        printf '#!/bin/sh\nexec zig cc -target aarch64-linux-gnu.2.31 "$@"\n' > "$WRAPPER"
        chmod +x "$WRAPPER"
        ln -sfn /usr/include/X11 "$INC_DIR/X11"
        CFLAGS="$CFLAGS -I$INC_DIR"
        CMAKE_EXTRA+=(
            -DCMAKE_SYSTEM_NAME=Linux
            -DCMAKE_SYSTEM_PROCESSOR=aarch64
            -DCMAKE_C_COMPILER="$WRAPPER"
            -DCMAKE_SHARED_LINKER_FLAGS="-L${AARCH64_SYSLIB:-/tmp/aarch64-syslib} -Wl,--allow-shlib-undefined"
        )
    elif command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
        CMAKE_EXTRA+=(
            -DCMAKE_SYSTEM_NAME=Linux
            -DCMAKE_SYSTEM_PROCESSOR=aarch64
            -DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc
        )
    else
        echo "Error: need zig or aarch64-linux-gnu-gcc to cross-compile gl4es" >&2
        exit 1
    fi
fi

cmake -S "$SRC_DIR" -B "$BUILD_DIR" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DHYBRIS=ON \
    -DUSE_CLOCK=ON \
    -DDEFAULT_ES=2 \
    -DDEFAULT_EGL="/usr/lib/aarch64-linux-gnu/libEGL.so.1" \
    -DDEFAULT_GLES="/usr/lib/aarch64-linux-gnu/libGLESv2.so.2" \
    -DCMAKE_C_FLAGS="$CFLAGS" \
    "${CMAKE_EXTRA[@]}"

ninja -C "$BUILD_DIR" -j"$(nproc)"

if command -v llvm-strip >/dev/null 2>&1; then
    llvm-strip --strip-unneeded "$SRC_DIR/lib/libGL.so.1"
fi

mkdir -p "$OUT_DIR"
cp -f "$SRC_DIR/lib/libGL.so.1" "$OUT_DIR/libGL.so.1"
ln -sf libGL.so.1 "$OUT_DIR/libGL.so"
chmod 755 "$OUT_DIR/libGL.so.1"
ls -lh "$OUT_DIR/libGL.so.1"
