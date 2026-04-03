#version 410

layout(location = 0) in vec3 color_in;

layout(location = 0) out vec3 color_out;

void main() {
    color_out = color_in;
}
