#!/bin/bash
# Download wasmtime C API for Moon Code

set -e

WASMTIME_VERSION="v27.0.0"
LIBS_DIR="$(dirname "$0")/../libs"

mkdir -p "$LIBS_DIR"

download_wasmtime() {
    local platform=$1
    local archive_ext=$2
    local url="https://github.com/bytecodealliance/wasmtime/releases/download/${WASMTIME_VERSION}/wasmtime-${WASMTIME_VERSION}-${platform}-c-api.${archive_ext}"
    local archive_name="wasmtime-${WASMTIME_VERSION}-${platform}-c-api.${archive_ext}"
    local dir_name="wasmtime-${WASMTIME_VERSION}-${platform}-c-api"

    if [ -d "$LIBS_DIR/$dir_name" ]; then
        echo "✓ $dir_name already exists"
        return
    fi

    echo "Downloading $dir_name..."
    curl -L -o "$LIBS_DIR/$archive_name" "$url"

    echo "Extracting..."
    if [ "$archive_ext" = "tar.xz" ]; then
        tar -xf "$LIBS_DIR/$archive_name" -C "$LIBS_DIR"
    else
        unzip -q "$LIBS_DIR/$archive_name" -d "$LIBS_DIR"
    fi

    rm "$LIBS_DIR/$archive_name"
    echo "✓ $dir_name installed"
}

echo "=== Downloading wasmtime ${WASMTIME_VERSION} ==="

# Detect OS and download appropriate version
case "$(uname -s)" in
    Linux*)
        download_wasmtime "x86_64-linux" "tar.xz"
        ;;
    Darwin*)
        download_wasmtime "x86_64-macos" "tar.xz"
        ;;
    MINGW*|MSYS*|CYGWIN*)
        download_wasmtime "x86_64-windows" "zip"
        ;;
    *)
        echo "Unknown OS. Downloading both Linux and Windows versions..."
        download_wasmtime "x86_64-linux" "tar.xz"
        download_wasmtime "x86_64-windows" "zip"
        ;;
esac

echo ""
echo "=== Done! ==="
