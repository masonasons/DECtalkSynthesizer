#!/bin/bash

# Build script for DECtalk static library for macOS
# This script compiles DECtalkMini as a static library that can be linked with the AU extension

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DECTALK_DIR="$SCRIPT_DIR/../dectalk"
OUTPUT_DIR="$SCRIPT_DIR/lib"
# Note: This script was for dectalk-mini. The full dectalk uses autoconf/make.
# For full dectalk build instructions, see dectalk/ports/macosx/

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Compiler flags
CC=clang
CFLAGS="-O2 -arch arm64 -arch x86_64 -mmacosx-version-min=14.0"
DEFINES="-D_REENTRANT -DNOMME -DLTSSIM -DTTSSIM -DANSI -DENGLISH -DENGLISH_US -DACCESS32 -DTYPING_MODE -DACNA -DDISABLE_AUDIO -DSINGLE_THREADED -DNO_FILESYSTEM"
INCLUDES="-I$INCLUDE_DIR"

echo "Building DECtalk static library..."
echo "Source directory: $DECTALK_DIR"
echo "Output directory: $OUTPUT_DIR"

# Compile all source files
OBJECTS=""
for src in "$SRC_DIR"/*.c; do
    filename=$(basename "$src" .c)
    obj="$OUTPUT_DIR/$filename.o"
    echo "Compiling $filename.c..."
    $CC $CFLAGS $DEFINES $INCLUDES -c "$src" -o "$obj" 2>/dev/null || {
        echo "Warning: Failed to compile $filename.c, skipping..."
        continue
    }
    OBJECTS="$OBJECTS $obj"
done

# Create static library
echo "Creating static library..."
ar rcs "$OUTPUT_DIR/libdectalk.a" $OBJECTS

# Clean up object files
rm -f "$OUTPUT_DIR"/*.o

echo ""
echo "Build complete!"
echo "Static library: $OUTPUT_DIR/libdectalk.a"
echo ""
echo "To use in Xcode:"
echo "1. Add libdectalk.a to your target"
echo "2. Add $INCLUDE_DIR to Header Search Paths"
echo "3. Add $OUTPUT_DIR to Library Search Paths"
