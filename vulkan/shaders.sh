#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

glslang -V --target-env vulkan1.3 shader.vert -o shader.vert.spv
glslang -V --target-env vulkan1.3 shader.frag -o shader.frag.spv
