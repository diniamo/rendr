#version 410

layout(location = 0) in vec2 position;
layout(location = 1) in vec3 color_in;

layout(location = 0) out vec3 color_out;

void main() {
	gl_Position = vec4(position, 0.0, 1.0);
	color_out = color_in;
}
