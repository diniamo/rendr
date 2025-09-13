package canvas

import "core:fmt"
import "core:strings"
import stbi "vendor:stb/image"
import t "common:types"

CHANNELS :: 3

Canvas :: struct {
	wi, hi: int,
	stride: int,
	wf, hf: f32,
	data: []u8,
	path: cstring
}

create :: proc(width, height: int, path: string) -> Canvas {
	stride := CHANNELS * width

	return {
		wi = width,
		hi = height,
		stride = stride,
		wf = f32(width),
		hf = f32(height),
		data = make([]byte, stride * height),
		path = strings.clone_to_cstring(path)
	}
}

clear :: proc(canvas: ^Canvas, color: t.Color) {
	for y in 0..<canvas.hi {
		for x in 0..<canvas.wi {
			start := canvas.stride * y + CHANNELS * x

			canvas.data[start] = u8(color[0] * 255)
			canvas.data[start + 1] = u8(color[1] * 255)
			canvas.data[start + 2] = u8(color[2] * 255)
		}
	}
}

pixel :: proc(canvas: ^Canvas, position: t.Vector2, color: t.Color) {
	// From a Cartesian coordinate system
	// To a top-left origin with the y axis increasing down
	translated_x := int(position.x + canvas.wf/2)
	translated_y := int(canvas.hf/2 - position.y)

	start := canvas.stride * translated_y + CHANNELS * translated_x

	canvas.data[start] = u8(color[0] * 255)
	canvas.data[start + 1] = u8(color[1] * 255)
	canvas.data[start + 2] = u8(color[2] * 255)
}

flush :: proc(canvas: ^Canvas) -> bool {
	return stbi.write_png(
		canvas.path,
		i32(canvas.wi), i32(canvas.hi),
		CHANNELS, &canvas.data[0], i32(canvas.stride)
	) == 0
}

destroy :: proc(canvas: ^Canvas) {
	delete(canvas.path)
	delete(canvas.data)
}
