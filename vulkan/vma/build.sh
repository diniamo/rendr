#!/bin/bash

# MIT License
#
# Copyright (c) 2023-2025 Rafael Henrique Capati
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

set -euo pipefail
cd "$(dirname "$0")"

VULKAN_MINOR_VERSION="${1:-3}"
echo "Vulkan minor version: $VULKAN_MINOR_VERSION"

VMA_VERSION="v3.2.1"
VMA_VULKAN_VERSION="100${VULKAN_MINOR_VERSION}000"
echo "VMA Vulkan version: $VMA_VULKAN_VERSION"

if [ ! -e build ]; then
	echo "Creating build files"

	mkdir build
	echo "
		#define VMA_VULKAN_VERSION $VMA_VULKAN_VERSION
		#define VMA_STATIC_VULKAN_FUNCTIONS 0
		#define VMA_DYNAMIC_VULKAN_FUNCTIONS 0
		#define VMA_IMPLEMENTATION
		#include <stdio.h>
		#include \"vk_mem_alloc.h\"
	" > build/vk_mem_alloc.cpp
fi

OS_NAME=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH_NAME=$(uname -m)
if [ "$ARCH_NAME" == "aarch64" ] || [ "$ARCH_NAME" == "arm64" ]; then
    ARCH_NAME="arm64"
else
    ARCH_NAME="x64"
fi
LIB_EXTENSION="a"
TARGET_PLATFORM="vma_${OS_NAME}_${ARCH_NAME}.${LIB_EXTENSION}"

echo "Compiling..."
"$CC" -Iinclude -O3 build/vk_mem_alloc.cpp -c -obuild/vk_mem_alloc.o

echo "Linking..."
ar rcs "external/$TARGET_PLATFORM" build/vk_mem_alloc.o
